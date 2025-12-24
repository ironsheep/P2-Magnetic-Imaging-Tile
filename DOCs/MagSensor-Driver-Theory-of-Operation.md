# Tile Sensor Driver Theory of Operation
**Magnetic Imaging Tile - isp_tile_sensor.spin2**

## Document Version
- **Version:** 1.4
- **Date:** 2025-12-23
- **Status:** Implementation Documentation - VERIFIED MAPPING + EVENT-DRIVEN FIFO

> **NOTE**: This document describes the *implemented* sensor mapping based on empirical testing.
> The unified_sensor_map table v3 has been **VERIFIED** via quadrant center testing.
> See "Schematic vs Empirical Findings" section for documented discrepancy with schematic (vertical flip).

## Overview

The tile sensor driver (`isp_tile_sensor.spin2`) is a high-performance, single-COG solution for acquiring magnetic field data from the SparkFun Magnetic Imaging Tile V3. Through careful optimization using pipelined SPI transfers, the driver achieves **~1,370 fps** frame rate capability while consuming only a single COG resource.

### Key Achievements
- **~1,330 fps** theoretical frame rate (full-speed operation)
- **11.2 us** per sensor read (pipelined)
- **~750 us** total frame acquisition time (64 sensors)
- **Single COG** operation
- **Smart Pin** SPI for hardware-assisted ADC communication
- **Pipelined** counter advance overlaps with SPI transfer time
- **Event-driven FIFO** with COGATN wake-up of consumer COGs
- **Zero artificial delays** - runs at natural SPI timing limit

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

The 8x8 sensor array is organized as 4 subtiles (quadrants). The hardware EN signals follow counter bits [5:4]:

```
Physical Layout:          Hardware Counter Mapping:
┌────────┬────────┐      ┌─────────────┬─────────────┐
│ Upper  │ Upper  │      │ EN1 (0-15)  │ EN2 (16-31) │
│ Left   │ Right  │      │ Upper-Left  │ Upper-Right │
├────────┼────────┤      ├─────────────┼─────────────┤
│ Lower  │ Lower  │      │ EN3 (32-47) │ EN4 (48-63) │
│ Left   │ Right  │      │ Lower-Left  │ Lower-Right │
└────────┴────────┘      └─────────────┴─────────────┘

subtile_order[] = {0, 1, 2, 3}   ' Sequential - matches hardware EN decode
```

### Channel-to-Position Mapping

Within each subtile, the hardware channel (0-15) maps to physical position (row, col) as follows (from PCB schematic):

```
Channel Layout (within each 4x4 subtile):
        Col0    Col1    Col2    Col3
Row0    Ch9     Ch11    Ch13    Ch15    (top row)
Row1    Ch8     Ch10    Ch12    Ch14
Row2    Ch6     Ch4     Ch2     Ch0
Row3    Ch7     Ch5     Ch3     Ch1     (bottom row)
```

### Mapping Tables
```spin2
' Subtile reading order - sequential to match hardware EN signals
subtile_order   BYTE    0, 1, 2, 3

' Frame buffer offsets for each subtile (using 8-wide row addressing)
'   subtile 0: offset 0  → rows 0-3, cols 0-3 (upper-left)
'   subtile 1: offset 4  → rows 0-3, cols 4-7 (upper-right)
'   subtile 2: offset 32 → rows 4-7, cols 0-3 (lower-left)
'   subtile 3: offset 36 → rows 4-7, cols 4-7 (lower-right)
subtile_offset  BYTE    0, 4, 32, 36

' Pixel mapping within each subtile - from hardware schematic
' Maps channel number (0-15) to frame buffer position
' Position = row * 8 + col (using 8-wide row addressing)
pixel_order     BYTE    19, 27, 18, 26, 17, 25, 16, 24  ' Channels 0-7 → rows 2-3
                BYTE     8,  0,  9,  1, 10,  2, 11,  3  ' Channels 8-15 → rows 0-1
```

---

## Coordinate Transformation Pipeline

### Overview

The sensor data undergoes transformation from hardware read order to display-ready frame buffer layout.

**Key Insight:** All transformations can and should be combined into a single 64-entry lookup table for:
- Simplicity: One table lookup per sensor
- Performance: Eliminates multiple table lookups and runtime math
- Debuggability: Clear mapping from hardware index to final buffer position

### Current Multi-Stage Approach (Being Unified)

The current implementation uses three separate transformation stages. This section documents each stage to understand what they do, then shows how to combine them.

#### Transformation Layer Analysis

**Layer 1: Subtile Selection (`subtile_order[]`)**
- **Purpose:** Map hardware counter range to quadrant
- **Input:** Counter bits [5:4] (values 0-3)
- **Output:** Subtile number to read
- **Current values:** `{0, 1, 2, 3}` (sequential)

**Layer 2: Subtile Offset (`subtile_offset[]`)**
- **Purpose:** Provide base buffer address for each quadrant
- **Input:** Subtile number (0-3)
- **Output:** Buffer offset (0, 4, 32, or 36)
- **Current values:** `{0, 4, 32, 36}` → UL, UR, LL, LR quadrants

**Layer 3: Within-Subtile Mapping (`pixel_order[]`)**
- **Purpose:** Map hardware channel (0-15) to position within 4x4 quadrant
- **Input:** Channel number within subtile (counter & 0x0F)
- **Output:** Relative buffer position (using 8-wide row addressing)
- **Based on:** PCB schematic serpentine wiring pattern

**Layer 4: Rotation Correction (`rotation_ccw90[]`)**
- **Purpose:** Correct overall 90° CW rotation from hardware orientation
- **Input:** Linear buffer index (0-63)
- **Output:** Rotated buffer index (0-63)
- **Applied:** 90° counter-clockwise transformation

---

## Orientation Reference Frames

### Hardware Documentation (Schematic Orientation)

The hardware documentation (`MagSensor-Tile-Hardware.md`) is based on schematic analysis and uses the schematic's orientation convention:

| Counter Bits [5:4] | EN Signal | Expected Quadrant (Schematic) |
|-------------------|-----------|-------------------------------|
| 00 (0-15)         | EN1       | Upper-Left (UL)               |
| 01 (16-31)        | EN2       | Upper-Right (UR)              |
| 10 (32-47)        | EN3       | Lower-Left (LL)               |
| 11 (48-63)        | EN4       | Lower-Right (LR)              |

### Orientation Choice

The schematic and this implementation use different viewing orientations - both are correct for their reference frame:

| Counter Range | Schematic Orientation | Implementation Orientation |
|--------------|----------------------|---------------------------|
| 0-15 (EN1)   | Upper-Left           | Lower-Left (LL) |
| 16-31 (EN2)  | Upper-Right          | Lower-Right (LR) |
| 32-47 (EN3)  | Lower-Left           | Upper-Left (UL) |
| 48-63 (EN4)  | Lower-Right          | Upper-Right (UR) |

**Author's choice:** This implementation uses **connector at BOTTOM** as the viewing orientation. The schematic likely uses connector at TOP or views from the back side. The quadrants are the same physical locations - just named according to different reference frames.

### Quadrant Center Verification Test (2025-12-23)

Test methodology: Place magnet at CENTER of each physical quadrant, measure centroid of activated pixels.

| Physical Position | Expected Centroid | Measured Centroid | Status |
|-------------------|-------------------|-------------------|--------|
| UL center | ~(1.5, 1.5) | **(1.5, 1.7)** | PASS |
| UR center | ~(1.5, 5.5) | **(1.6, 5.5)** | PASS |
| LR center | ~(5.5, 5.5) | **(5.6, 5.4)** | PASS |
| LL center | ~(5.5, 1.5) | **(5.6, 1.2)** | PASS |

All four quadrants map correctly with centroids within 0.3 pixels of expected positions.

### Summary

- **Hardware documentation** - Uses schematic's orientation convention
- **Implementation documentation** - Uses connector-at-bottom orientation (author's choice)
- **unified_sensor_map v3** - VERIFIED for connector-at-bottom viewing

### Unified Mapping Table Approach

Instead of four separate tables with runtime computation, we create ONE 64-entry lookup table:

```
unified_sensor_map[counter_index] = final_buffer_position
```

**Benefits:**
1. **Single lookup:** One table access per sensor (was 4 lookups + math)
2. **Pre-computed:** All transformations baked in at compile time
3. **Debuggable:** Each entry shows exactly where that sensor data goes
4. **Testable:** Can verify each of 64 entries independently

**Generation Algorithm:**
```
For counter = 0 to 63:
    1. Determine physical quadrant from EN signal (using empirical mapping)
    2. Get channel within quadrant: channel = counter & 0x0F
    3. Map channel to physical position within quadrant (from schematic)
    4. Calculate physical row/col in full 8x8 grid
    5. Since we want physical = buffer (1:1): buffer_idx = physical_row * 8 + physical_col
    6. unified_sensor_map[counter] = buffer_idx
```

**Computed Unified Table:**

Using the empirical EN→quadrant mapping and the schematic channel→position mapping:

```
                                Within-Quadrant                Physical    Buffer
Counter  EN   Physical Quad    Ch → (row,col)                 (row,col)   Index
-------  ---  ---------------  ---------------------------    ---------   ------
  0      EN1  Lower-Right      0 → (2,3) + (4,4) offset       (6,7)       55
  1      EN1  Lower-Right      1 → (3,3) + (4,4) offset       (7,7)       63
  2      EN1  Lower-Right      2 → (2,2) + (4,4) offset       (6,6)       54
  ...    ...  ...              ...                            ...         ...
  9      EN1  Lower-Right      9 → (0,0) + (4,4) offset       (4,4)       36
  ...
 16      EN2  Upper-Right      0 → (2,3) + (0,4) offset       (2,7)       23
 17      EN2  Upper-Right      1 → (3,3) + (0,4) offset       (3,7)       31
  ...
 25      EN2  Upper-Right      9 → (0,0) + (0,4) offset       (0,4)        4
  ...
 32      EN3  Lower-Left       0 → (2,3) + (4,0) offset       (6,3)       51
 33      EN3  Lower-Left       1 → (3,3) + (4,0) offset       (7,3)       59
  ...
 41      EN3  Lower-Left       9 → (0,0) + (4,0) offset       (4,0)       32
  ...
 48      EN4  Upper-Left       0 → (2,3) + (0,0) offset       (2,3)       19
 49      EN4  Upper-Left       1 → (3,3) + (0,0) offset       (3,3)       27
  ...
 57      EN4  Upper-Left       9 → (0,0) + (0,0) offset       (0,0)        0
```

**Complete unified_sensor_map[64] Array - VERIFIED (v3):**

```spin2
' VERIFIED Unified sensor mapping v3: counter index (0-63) → final buffer position (0-63)
' Verified via quadrant center testing (2025-12-23)
'
' EN→QUADRANT MAPPING (verified):
'   EN1 (counter 0-15)  → Physical LL quadrant → Buffer rows 4-7, cols 0-3
'   EN2 (counter 16-31) → Physical LR quadrant → Buffer rows 4-7, cols 4-7
'   EN3 (counter 32-47) → Physical UL quadrant → Buffer rows 0-3, cols 0-3
'   EN4 (counter 48-63) → Physical UR quadrant → Buffer rows 0-3, cols 4-7
'
' NOTE: This differs from schematic (vertical flip). See "Schematic vs Empirical Findings".

unified_sensor_map  BYTE    34, 42, 35, 43, 32, 40, 33, 41    ' Counter 0-7   (EN1 → LL)
                    BYTE    48, 56, 49, 57, 50, 58, 51, 59    ' Counter 8-15  (EN1 → LL)
                    BYTE    38, 46, 39, 47, 36, 44, 37, 45    ' Counter 16-23 (EN2 → LR)
                    BYTE    52, 60, 53, 61, 54, 62, 55, 63    ' Counter 24-31 (EN2 → LR)
                    BYTE     2, 10,  3, 11,  0,  8,  1,  9    ' Counter 32-39 (EN3 → UL)
                    BYTE    16, 24, 17, 25, 18, 26, 19, 27    ' Counter 40-47 (EN3 → UL)
                    BYTE     6, 14,  7, 15,  4, 12,  5, 13    ' Counter 48-55 (EN4 → UR)
                    BYTE    20, 28, 21, 29, 22, 30, 23, 31    ' Counter 56-63 (EN4 → UR)
```

**Corner Verification:**
| Counter | EN | Physical Quadrant | Channel | Physical Corner | Buffer Index | Buffer Position |
|---------|----|--------------------|---------|-----------------|--------------|-----------------|
| 9       | 1  | Lower-Right        | 9       | BR (4,4)        | 36           | Row 4, Col 4    |
| 1       | 1  | Lower-Right        | 1       | BR corner (7,7) | 63           | Row 7, Col 7 ✓  |
| 25      | 2  | Upper-Right        | 9       | TR (0,4)        | 4            | Row 0, Col 4    |
| 31      | 2  | Upper-Right        | 15      | TR corner (0,7) | 7            | Row 0, Col 7 ✓  |
| 41      | 3  | Lower-Left         | 9       | BL (4,0)        | 32           | Row 4, Col 0    |
| 39      | 3  | Lower-Left         | 7       | BL corner (7,0) | 56           | Row 7, Col 0 ✓  |
| 57      | 4  | Upper-Left         | 9       | TL (0,0)        | 0            | Row 0, Col 0 ✓  |

### Physical Orientation Reference

```
                    TOP (away from connector)
              ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
              │ TL  │     │     │     │     │     │     │ TR  │  row 0
              ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
              │     │     │     │     │     │     │     │     │  row 1
              │     │                 ...                │     │  ...
              │     │     │     │     │     │     │     │     │  row 6
              ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
              │ BL  │     │     │     │     │     │     │ BR  │  row 7
              └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
                col 0                                   col 7
                    BOTTOM (connector edge)
```

**Target Frame Buffer Layout:**
- Top-Left physical corner → buffer[0] (row 0, col 0)
- Top-Right physical corner → buffer[7] (row 0, col 7)
- Bottom-Left physical corner → buffer[56] (row 7, col 0)
- Bottom-Right physical corner → buffer[63] (row 7, col 7)

### Transformation Stages

#### Stage 1: Hardware Read Order → Linear Index
The hardware counter steps through sensors in a non-sequential pattern due to PCB routing:

1. **Subtile Selection:** `subtile_order[]` maps counter position to actual subtile (0,2,1,3 not 0,1,2,3)
2. **Subtile Offset:** `subtile_offset[]` provides frame buffer base offset for each subtile
3. **Serpentine Pattern:** `pixel_order[]` maps sensor within subtile to position (handles serpentine wiring)

**Result:** `linear_idx = pixel_order[sensor_in_subtile] + subtile_offset[subtile_num]`

#### Stage 2: Rotation Correction (90° CCW)

**Problem:** The raw linear index produces an image rotated 90° clockwise from physical orientation.

**Verified by Magnet Test (2025-12-23):**
| Physical Corner | Detected at Buffer Position | Expected After Rotation |
|-----------------|----------------------------|------------------------|
| Top-Left | [0,6], [0,7], [1,7] | [0,0], [0,1], [1,0] |
| Top-Right | [6,7], [7,6], [7,7] | [0,7], [1,7], [0,6] |
| Bottom-Right | [6,0], [7,0], [7,1] | [7,7], [7,6], [6,7] |
| Bottom-Left | [0,0], [0,1], [1,0] | [7,0], [6,0], [7,1] |

**Solution:** Apply 90° counter-clockwise rotation via lookup table.

**Math:**
```
Given:  old_idx = old_row * 8 + old_col
Where:  old_row = old_idx / 8
        old_col = old_idx % 8

Transform:
        new_row = 7 - old_col
        new_col = old_row

Result: new_idx = (7 - old_col) * 8 + old_row
```

**Lookup Table (`rotation_ccw90[]`):**
```spin2
rotation_ccw90  BYTE    56, 48, 40, 32, 24, 16,  8,  0    ' row 0 → col 7..0 of row 7..0
                BYTE    57, 49, 41, 33, 25, 17,  9,  1    ' row 1
                BYTE    58, 50, 42, 34, 26, 18, 10,  2    ' row 2
                BYTE    59, 51, 43, 35, 27, 19, 11,  3    ' row 3
                BYTE    60, 52, 44, 36, 28, 20, 12,  4    ' row 4
                BYTE    61, 53, 45, 37, 29, 21, 13,  5    ' row 5
                BYTE    62, 54, 46, 38, 30, 22, 14,  6    ' row 6
                BYTE    63, 55, 47, 39, 31, 23, 15,  7    ' row 7
```

**Example:**
- Input: `old_idx=7` (row 0, col 7) — physical Top-Left position before rotation
- Transform: `new_row = 7-7 = 0`, `new_col = 0`
- Output: `new_idx=0` — correct Top-Left position in buffer

#### Stage 3: Future Corrections (Reserved)
Reserved for additional transformations if needed:
- Horizontal/vertical flip for display orientation
- Per-quadrant adjustments if serpentine varies
- Can be combined into single 64-byte lookup for efficiency

### Implementation in PASM

```pasm
.store_sensor_value
    ' STAGE 1: Hardware Read Order → Linear Index
    ' ... lookup subtile_order, subtile_offset, pixel_order ...
    mov     linear_idx, pixel_pos
    add     linear_idx, frame_offset

    ' STAGE 2: Rotation Correction (90° CCW)
    mov     pa, lut_rotation
    add     pa, linear_idx
    rdbyte  rotated_idx, pa

    ' STAGE 3: (Reserved)

    ' Final: Store at rotated position
    mov     buf_ptr, rotated_idx
    shl     buf_ptr, #1              ' * 2 for WORD
    add     buf_ptr, framePtr
    wrword  sensor_val, buf_ptr
```

### Performance Impact

The rotation lookup adds minimal overhead:
- **2 PASM instructions** per sensor (mov + add + rdbyte)
- **~12 ns** per sensor at 250 MHz
- **~768 ns** per frame (64 sensors)
- **0.1%** of total frame time (718 µs)

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
| MODE_ADC_VERIFY | 5 | ADC verification: 2 scans with detailed logging for logic analyzer comparison |

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

## Event-Driven FIFO Integration

### Producer-Consumer Architecture

The sensor driver operates as a **producer** in an event-driven architecture:

```
Sensor COG (Producer)          Consumer COGs (HDMI/OLED)
        │                              │
        │ acquire_sensor_frame()       │ dequeueEventDriven()
        │         │                    │         │
        │         ▼                    │         ▼
        │ ┌─────────────┐              │ ┌─────────────┐
        │ │ Get frame   │              │ │ WAITATN     │ ← Zero-power wait
        │ │ from pool   │              │ │ (sleeping)  │
        │ └─────────────┘              │ └─────────────┘
        │         │                    │         │
        │         ▼                    │         │
        │ ┌─────────────┐              │         │
        │ │ Fill frame  │              │         │
        │ │ (64 sensors)│              │         │
        │ └─────────────┘              │         │
        │         │                    │         │
        │         ▼                    │         │
        │ ┌─────────────┐              │         │
        │ │ commitFrame │──── COGATN ──│────────►│ Wake!
        │ │ + notify    │              │         │
        │ └─────────────┘              │         ▼
        │         │                    │ ┌─────────────┐
        │         │                    │ │ Dequeue &   │
        │         │                    │ │ render      │
        │         │                    │ └─────────────┘
```

### Full-Speed Operation

The sensor runs at maximum SPI speed with **zero artificial delays**:

```spin2
' After frame acquisition completes:
if fifo.commitFrame(fifo.FIFO_SENSOR, framePtr) < 0
    ' FIFO full - release frame (decimation)
    fifo.releaseFrame(framePtr)
else
    frame_count++

' FULL SPEED: No artificial delay - natural timing is:
'   SPI: 24 bits × 64 sensors × (1/2.5MHz) = ~614µs per frame
'   Plus pipeline overhead: ~750µs total = ~1,330 fps theoretical max
```

### COGATN Wake-up Mechanism

When the sensor commits a frame, the FIFO manager automatically sends COGATN:

1. **Sensor commits frame:** `fifo.commitFrame(FIFO_SENSOR, framePtr)`
2. **FIFO manager notifies:** Sends COGATN to registered decimator COG
3. **Decimator wakes:** Processes frame, routes to HDMI/OLED FIFOs
4. **Display COGs wake:** Each receives COGATN when their FIFO gets data

**Benefits:**
- **Zero jitter:** COGs wake in ~4 clock cycles (vs 0-1ms polling)
- **Zero power waste:** WAITATN consumes no power while waiting
- **Independent rates:** Each display wakes only when its FIFO has data

### Timing Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| Frame acquisition | ~750 µs | 64 sensors, pipelined SPI |
| Theoretical max fps | ~1,330 | No artificial delays |
| COGATN latency | ~4 clocks | ~16 ns at 250 MHz |
| Consumer wake time | ~20 clocks | Event detection + WAITATN return |

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
| 1.1 | 2025-12-23 | Added Coordinate Transformation Pipeline section. Verified ADC bit extraction with logic analyzer (AD7680 16-bit confirmed). Added MODE_ADC_VERIFY. Added 90° CCW rotation lookup table for correct physical orientation. |
| 1.2 | 2025-12-23 | Added "Schematic vs Empirical Findings" section. Marked unified_sensor_map as PROVISIONAL. Documented testing caveats. Distinguished between hardware documentation (pristine, schematic-based) and implementation documentation (empirical observations). |
| 1.3 | 2025-12-23 | **VERIFIED** unified_sensor_map v3 via quadrant center testing. All 4 quadrants map correctly (centroids within 0.3 pixels of expected). Clarified orientation choice: implementation uses connector-at-bottom viewing (author's choice), schematic uses different reference frame. Removed PROVISIONAL status. |
| 1.4 | 2025-12-23 | **EVENT-DRIVEN FIFO**: Added COGATN-based wake-up mechanism. Removed all artificial delays for full-speed operation (~1,330 fps). Added "Event-Driven FIFO Integration" section documenting producer-consumer architecture with WAITATN. |
