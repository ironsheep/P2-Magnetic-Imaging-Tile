# Tile Sensor Driver Theory of Operation
**Magnetic Imaging Tile - isp_tile_sensor.spin2**

## Document Version
- **Version:** 1.0
- **Date:** 2025-11-30
- **Status:** Implementation Documentation (Post-Optimization, Stability Testing In Progress)

## Overview

The tile sensor driver (`isp_tile_sensor.spin2`) is a high-performance, single-COG solution for acquiring magnetic field data from the SparkFun Magnetic Imaging Tile V3. Through careful optimization using pipelined SPI transfers, the driver achieves **~1,370 fps** frame rate capability while consuming only a single COG resource.

### Key Achievements
- **~1,370 fps** theoretical frame rate (measured)
- **11.2 us** per sensor read (pipelined)
- **718 us** total frame acquisition time (64 sensors)
- **Single COG** operation
- **Smart Pin** SPI for hardware-assisted ADC communication
- **Pipelined** counter advance overlaps with SPI transfer time

### Performance Comparison
| Metric | Before Optimization | After Optimization | Improvement |
|--------|---------------------|-------------------|-------------|
| Per-sensor time | 18 us | 11.2 us | 38% faster |
| Frame acquisition | 1,152 us | 718 us | 38% faster |
| Max frame rate | 868 fps | ~1,370 fps | 58% more fps |

---

## Architecture Overview

### Hardware Components

The SparkFun Magnetic Imaging Tile V3 consists of:
- **8x8 Hall Effect Sensor Array**: 64 sensors arranged in 4 subtiles (quadrants)
- **Hardware Multiplexer**: 6-bit counter selects which sensor is routed to ADC
- **AD7680 16-bit ADC**: External high-precision analog-to-digital converter
- **SPI Interface**: 24-bit transfers (4 leading zeros + 16 data bits + 4 trailing zeros)

### Data Flow
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TILE SENSOR HARDWARE                               │
│                                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                 │
│  │ 8x8 Sensor   │     │ Hardware     │     │ AD7680       │                 │
│  │ Array        │────▶│ Multiplexer  │────▶│ 16-bit ADC   │                 │
│  │ (64 Hall     │     │ (6-bit       │     │ (SPI)        │                 │
│  │  sensors)    │     │  counter)    │     │              │                 │
│  └──────────────┘     └──────────────┘     └──────────────┘                 │
│         │                    │                    │                          │
│         │              CCLK (advance)        SPI (SCLK/MISO)                 │
│         │              CLRb (reset)          CS (chip select)               │
└─────────│────────────────────│────────────────────│──────────────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SENSOR COG (P2)                                     │
│                                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                 │
│  │ Counter      │     │ Pipelined    │     │ Sensor       │                 │
│  │ Control      │────▶│ PASM         │────▶│ Mapping      │                 │
│  │ (CLRb/CCLK)  │     │ Acquisition  │     │ (subtile/    │                 │
│  │              │     │ Loop         │     │  pixel order)│                 │
│  └──────────────┘     └──────────────┘     └──────────────┘                 │
│                              │                    │                          │
│                              ▼                    ▼                          │
│                       ┌──────────────┐     ┌──────────────┐                 │
│                       │ Frame Buffer │     │ FIFO         │                 │
│                       │ (128 bytes)  │────▶│ Commit       │                 │
│                       │              │     │              │                 │
│                       └──────────────┘     └──────────────┘                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                                    │
                                                    ▼
                                            ┌──────────────┐
                                            │ Sensor FIFO  │
                                            │ (to decimator│
                                            │  & displays) │
                                            └──────────────┘
```

### Pin Assignments (P8-P15 Group)
| Signal | P2 Pin | Relative | Function | Direction |
|--------|--------|----------|----------|-----------|
| CS | P8 | +0 | ADC Chip Select | Output |
| CCLK | P9 | +1 | Counter Clock (advance sensor) | Output |
| MISO | P10 | +2 | ADC Data (SPI receive) | Input |
| CLRb | P11 | +3 | Counter Clear (active low) | Output |
| SCLK | P12 | +4 | ADC SPI Clock | Output |
| AOUT | P14 | +6 | Analog Output (unused) | - |

---

## Smart Pin Configuration

### SCLK Pin (Clock Generation)
```spin2
' P_PULSE mode: generates N pulses when triggered
PINSTART(pin_sclk, P_OE | P_PULSE, clk_period | (clk_period >> 1) << 16, 0)
```
- **Mode:** P_PULSE (hardware pulse generator)
- **Frequency:** 2.5 MHz (AD7680 maximum)
- **Period:** 100 sysclks at 250 MHz
- **Trigger:** `WYPIN pin_sclk, #24` generates exactly 24 clock pulses

### MISO Pin (Data Reception)
```spin2
' P_SYNC_RX mode: shifts in data synchronized to external clock
PINSTART(pin_miso, P_SYNC_RX | P_PLUS2_B | P_INVERT_B, %0_10111, 0)
```
- **Mode:** P_SYNC_RX (synchronous serial receive)
- **Clock source:** Linked to SCLK pin via P_PLUS2_B (pin+2)
- **P_INVERT_B:** Sample on falling edge (AD7680 outputs on falling edge)
- **Bit count:** 24 bits (encoded as 23 in X register)
- **Optimization:** Configured ONCE at startup, stays enabled across all transfers

### Event Configuration
```spin2
' Configure SE1 event for SCLK completion detection
event_config := %01_000000 | ABS_PIN_SCLK    ' Positive edge on IN flag
setse1  event_config
```
- **Event SE1:** Triggers when SCLK Smart Pin sets IN flag (transfer complete)
- **Usage:** `waitse1` efficiently halts COG until SPI transfer completes
- **Benefit:** Replaces inefficient polling loop

---

## Pipelined Acquisition Algorithm

### The Key Optimization

The breakthrough optimization overlaps counter advance with SPI transfer time:

**Sequential (Before):**
```
Sensor N:   [CS low][Settle 2us][SPI 9.6us][Read][CS high][Counter++]
            ←──────────────── 18 us total ────────────────→
```

**Pipelined (After):**
```
Sensor N:   [CS low][SPI 9.6us][Read][CS high]
                    ↓
            [Counter++ to N+1] ← happens DURING SPI!
                    ↓
Sensor N+1: [Residual settle][CS low][SPI 9.6us]...
            ←───────────── 11.2 us total ─────────────→
```

### Acquisition Sequence

#### Phase 1: First Sensor (Full Setup)
```pasm
' Reset counter to position 0
drvl    #ABS_PIN_CLRB
waitx   #COUNTER_SETUP_DELAY
drvh    #ABS_PIN_CLRB

' Advance to sensor 1 (first active sensor)
drvh    #ABS_PIN_CCLK
waitx   #COUNTER_SETUP_DELAY
drvl    #ABS_PIN_CCLK

' Full settle time for first sensor
drvl    #ABS_PIN_CS
waitx   #SENSOR_SETTLE_DELAY         ' 2 us

' Start SPI, advance counter DURING transfer
wypin   #SPI_TRANSFER_BITS, #ABS_PIN_SCLK
akpin   #ABS_PIN_SCLK
drvh    #ABS_PIN_CCLK                ' Counter to sensor 1
waitx   #COUNTER_SETUP_DELAY
drvl    #ABS_PIN_CCLK
waitse1                               ' Wait for SPI complete

' Read and process
rdpin   sensor_val, #ABS_PIN_MISO
drvh    #ABS_PIN_CS
rev     sensor_val
shr     sensor_val, #4
and     sensor_val, ##$FFFF
```

#### Phase 2: Pipelined Loop (Sensors 1-62)
```pasm
.pipelined_loop
    waitx   #RESIDUAL_SETTLE_DELAY   ' 800 ns (sensor already settling)
    drvl    #ABS_PIN_CS

    wypin   #SPI_TRANSFER_BITS, #ABS_PIN_SCLK
    akpin   #ABS_PIN_SCLK

    cmp     total_sensor_count, #63 wcz
    if_ae   jmp     #.last_sensor

    ' WHILE SPI RUNS: Advance to NEXT sensor
    drvh    #ABS_PIN_CCLK
    waitx   #COUNTER_SETUP_DELAY
    drvl    #ABS_PIN_CCLK

    waitse1

    rdpin   sensor_val, #ABS_PIN_MISO
    drvh    #ABS_PIN_CS
    ' ... process and store ...

    add     total_sensor_count, #1
    jmp     #.pipelined_loop
```

#### Phase 3: Last Sensor (No Counter Advance)
```pasm
.last_sensor
    waitse1                          ' Just wait for SPI
    rdpin   sensor_val, #ABS_PIN_MISO
    drvh    #ABS_PIN_CS
    ' ... process and store final sensor ...
```

---

## Timing Constants

| Constant | Value (clocks) | Time | Purpose |
|----------|----------------|------|---------|
| SENSOR_SETTLE_DELAY | 500 | 2 us | Analog settling for first sensor |
| COUNTER_SETUP_DELAY | 63 | 252 ns | Counter pulse width |
| RESIDUAL_SETTLE_DELAY | 200 | 800 ns | Additional settle in pipelined mode |
| SPI_TRANSFER_BITS | 24 | 9.6 us | AD7680 transfer size |
| SPI_CLOCK_FREQ | 2.5 MHz | - | AD7680 maximum clock rate |

---

## Sensor Mapping

### Subtile Organization

The 8x8 sensor array is organized as 4 subtiles (quadrants), but they are NOT read in sequential order:

```
Physical Layout:        Hardware Read Order:
┌────┬────┐            ┌────┬────┐
│ 0  │ 1  │            │ 1st│ 3rd│
├────┼────┤            ├────┼────┤
│ 2  │ 3  │            │ 2nd│ 4th│
└────┴────┘            └────┴────┘

subtile_order[] = {0, 2, 1, 3}
```

### Serpentine Pattern

Within each subtile, sensors follow a serpentine (snake) pattern:
```
┌──▶──▶──▶──┐
│           │
└──◀──◀──◀──┘
┌──▶──▶──▶──┐
│           │
└──◀──◀──◀──┘
```

### Mapping Tables
```spin2
' Subtile reading order
subtile_order   BYTE    0, 2, 1, 3

' Frame buffer offsets for each subtile (words)
subtile_offset  BYTE    0, 4, 32, 36

' Pixel mapping within each subtile (serpentine pattern)
pixel_order     BYTE    26, 27, 18, 19, 10, 11, 2, 3
                BYTE    1, 0, 9, 8, 17, 16, 25, 24
```

---

## Frame Buffer Format

Each frame is 128 bytes (64 sensors x 2 bytes per sensor):
- **Type:** WORD array (16-bit values)
- **Range:** 0-65535 (AD7680 16-bit ADC)
- **Layout:** Linear array indexed by mapped pixel position
- **Storage:** Hub RAM, allocated from FIFO frame pool

---

## Acquisition Modes

| Mode | Value | Description |
|------|-------|-------------|
| MODE_STOPPED | 0 | No acquisition |
| MODE_LIVE | 1 | Real-time sensor reading (pipelined PASM) |
| MODE_HIGH_SPEED | 2 | Reserved for future optimization |
| MODE_DEBUG | 3 | Reserved for debugging |
| MODE_TEST_PATTERN | 4 | Generate test frames (digits 0-5) |

---

## Known Issues and Status

### Resolved
- **Counter comparison bug:** Changed `wz`/`if_z` to `wcz`/`if_ae` for defensive >= 63 check

### Under Investigation
1. **Memory corruption:** Garbage pointers appearing in FIFO after sustained operation
2. **System instability:** Crashes after initial frames at high speed
3. **CLRb behavior:** Counter reset stops pulsing but acquisition continues (counter wraps naturally)

### Performance Validated
- Frame acquisition time: 718 us (verified via logic analyzer)
- Per-sensor timing: 11.2 us average (pipelined)
- SPI clock: 2.5 MHz (AD7680 maximum)

---

## Debug Output

The driver reports frame count via `get_frame_count()` method. Periodic status is reported by the main application decimation loop every 30 frames.

---

## Future Optimization Opportunities

### 1. Remove Per-Frame Counter Reset
Currently CLRb pulses at start of every frame. Since we read exactly 64 sensors, counter naturally wraps to 0. Could eliminate CLRb after startup.

**Estimated savings:** ~500 ns per frame

### 2. DMA/Streamer for Frame Buffer
Could use P2 streamer to transfer completed frame to FIFO without CPU involvement.

### 3. Dual-Buffering
Ping-pong between two frame buffers to eliminate FIFO wait time.

---

## Related Documents

- **Hardware Specification:** `DOCs/Magnetic-Tile-Hardware.md`
- **OLED Driver:** `DOCs/OLED-Driver-Theory-of-Operation.md`
- **Implementation Plan:** `tasks/implementation-plan-spi-optimization.md`
- **AD7680 Datasheet:** `DOCs/Hardware-PDFs/`

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-30 | Initial documentation after pipelined optimization achieving ~1,370 fps |
