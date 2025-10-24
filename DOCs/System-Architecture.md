# Magnetic Imaging Tile - System Architecture

**Project**: P2 Magnetic Imaging Tile Driver
**Architecture**: Decoupled Pipeline with Rate Decimation
**Date**: 2025-10-21
**Version**: 1.0

---

## Architecture Overview

The system implements a **fully autonomous pipeline architecture** where each subsystem runs independently in its own COG, communicating only through FIFOs. The main COG acts as an orchestrator during startup, then exits to a monitoring role.

### Design Philosophy

1. **Decoupled Operation** - No subsystem directly calls another
2. **FIFO-Based Communication** - All data flows through hub RAM FIFOs
3. **Autonomous COGs** - Each COG runs at its natural rate
4. **Rate Matching** - Decimator handles speed conversion
5. **Main COG Free** - Main loop available for monitoring/control

---

## System Block Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         MAIN COG (COG 0)                            │
│  Role: System Orchestrator & Monitor                                │
│  - Starts all subsystems in correct order                           │
│  - Performs initial calibration                                     │
│  - Monitors system health (optional)                                │
│  - Does NOT touch data path after startup                           │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    TILE SENSOR COG (COG 1)                          │
│  Role: High-Speed Autonomous Data Acquisition                       │
│  Rate: 375 fps (target) | 1,500 fps (theoretical max)              │
│                                                                     │
│  ┌────────────┐   ┌──────────────┐   ┌───────────────┐            │
│  │ Hardware   │ → │  Processing  │ → │  FIFO Write   │            │
│  │ Scan       │   │  Pipeline    │   │  (Sensor)     │            │
│  │  640µs     │   │    6µs       │   │    2µs        │            │
│  └────────────┘   └──────────────┘   └───────────────┘            │
│                                                                     │
│  Processing: Scan → Baseline Subtract → Pixel Remap                │
│  Output: Processed frames (logical order, calibrated)              │
└──────────────────────────────────┬──────────────────────────────────┘
                                   ↓
                          ┌─────────────────┐
                          │  SENSOR FIFO    │
                          │  (FIFO #0)      │
                          │  375 fps        │
                          │  32 frames deep │
                          │  4 KB           │
                          └─────────────────┘
                                   ↓
┌──────────────────────────────────┴──────────────────────────────────┐
│                      DECIMATOR COG (COG 2)                          │
│  Role: Rate Conversion & Multi-Display Distribution                │
│  Input: 375 fps | Output: 60 fps (both displays)                   │
│                                                                     │
│  ┌──────────────┐   ┌─────────────────┐   ┌──────────────────┐    │
│  │ Read Sensor  │ → │  Decimation     │ → │  Dual FIFO       │    │
│  │ FIFO         │   │  (6:1 ratio)    │   │  Write           │    │
│  │ (375 fps)    │   │  Frame Select   │   │  OLED + HDMI     │    │
│  └──────────────┘   └─────────────────┘   └──────────────────┘    │
│                                                                     │
│  Strategy: Every 6th frame → both display FIFOs                    │
│  Optional: Frame averaging, color mapping                          │
└──────────────────────────────┬───────────────────┬─────────────────┘
                                ↓                   ↓
                    ┌───────────────────┐  ┌──────────────────┐
                    │  OLED FIFO        │  │  HDMI FIFO       │
                    │  (FIFO #1)        │  │  (FIFO #2)       │
                    │  60 fps           │  │  60 fps          │
                    │  4 frames deep    │  │  4 frames deep   │
                    │  512 bytes        │  │  512 bytes       │
                    └───────────────────┘  └──────────────────┘
                                ↓                   ↓
┌───────────────────────────────┴──┐   ┌────────────┴────────────────┐
│     OLED DISPLAY COG (COG 3)     │   │  HDMI DISPLAY COG (COG 4)   │
│  Role: Autonomous OLED Rendering │   │  Role: Autonomous VGA/HDMI  │
│  Rate: 60 fps                    │   │  Rate: 60 fps               │
│                                  │   │                             │
│  ┌──────────┐   ┌─────────────┐ │   │  ┌──────────┐  ┌──────────┐ │
│  │ Read     │ → │  Render to  │ │   │  │ Read     │→ │ Render   │ │
│  │ OLED     │   │  128x128    │ │   │  │ HDMI     │  │ to VGA/  │ │
│  │ FIFO     │   │  SSD1351    │ │   │  │ FIFO     │  │ HDMI     │ │
│  └──────────┘   └─────────────┘ │   │  └──────────┘  └──────────┘ │
│                                  │   │                             │
│  Output: Physical OLED (P16-23) │   │  Output: HDMI (DVI pins)    │
└──────────────────────────────────┘   └─────────────────────────────┘
```

---

## COG Allocation

| COG | Subsystem | Rate | Function |
|-----|-----------|------|----------|
| 0 | Main | N/A | System orchestrator & monitor |
| 1 | Tile Sensor | 375 fps | Hardware acquisition & processing |
| 2 | Decimator | 375→60 fps | Rate conversion & distribution |
| 3 | OLED Display | 60 fps | OLED rendering (128×128) |
| 4 | HDMI Display | 60 fps | VGA/HDMI output |
| 5-7 | Available | - | Future expansion |

**Total COGs Used**: 5 of 8
**Available**: 3 COGs for future features

---

## FIFO Configuration

### Pre-Allocated FIFOs (from isp_frame_fifo.spin2)

| FIFO | Name | Producer | Consumer | Rate | Depth | Memory |
|------|------|----------|----------|------|-------|--------|
| #0 | Sensor FIFO | Tile Sensor | Decimator | 375 fps | 32 frames | 4 KB |
| #1 | OLED FIFO | Decimator | OLED Display | 60 fps | 4 frames | 512 B |
| #2 | HDMI FIFO | Decimator | HDMI Display | 60 fps | 4 frames | 512 B |

**Total FIFO Memory**: ~5 KB

### FIFO Sizing Rationale

**Sensor FIFO (Deep Buffer)**:
- **Purpose**: Absorb timing jitter from sensor acquisition
- **Depth**: 32 frames = 85ms buffering @ 375 fps
- **Protection**: Prevents sensor COG from blocking if decimator pauses

**Display FIFOs (Shallow Buffers)**:
- **Purpose**: Decouple display timing from decimator
- **Depth**: 4 frames = 67ms buffering @ 60 fps
- **Efficiency**: Minimal memory, sufficient for smooth operation

---

## Timing Specifications

### Tile Sensor COG @ 375 fps

| Operation | Time (µs) | % of Frame |
|-----------|-----------|------------|
| Frame Period | 2,670 | 100% |
| Sensor Scan (64 sensors) | 640 | 24% |
| Baseline Subtraction | 3 | 0.1% |
| Pixel Remapping | 3 | 0.1% |
| FIFO Write | 2 | 0.08% |
| Buffer Management | 2 | 0.08% |
| **Total Active** | **650** | **24.3%** |
| **Idle Time** | **2,020** | **75.7%** |

**Headroom**: 75.7% idle time allows for future features

### Theoretical Maximum Performance

| Parameter | Value |
|-----------|-------|
| Minimum Scan Time | 640 µs |
| Maximum Frame Rate | 1,563 fps |
| Current Target | 375 fps (24% of max) |
| Available Headroom | 4× speed increase possible |

---

## Data Flow

### Frame Structure

```
Raw Hardware Frame (acquisition order):
┌───────────────────────────────────────┐
│ Sensor 0, 1, 2, ... 63                │
│ (Hardware scanning order)             │
│ 64 × 16-bit values = 128 bytes        │
└───────────────────────────────────────┘
                  ↓
        Baseline Subtraction
                  ↓
┌───────────────────────────────────────┐
│ Deviation values (signed)             │
│ -2048 to +2047 (12-bit range)         │
│ 64 × 16-bit signed = 128 bytes        │
└───────────────────────────────────────┘
                  ↓
          Pixel Remapping
                  ↓
┌───────────────────────────────────────┐
│ Logical 8×8 Grid (spatial order)      │
│ Row 0: sensors 0-7                    │
│ Row 1: sensors 8-15                   │
│ ...                                   │
│ Row 7: sensors 56-63                  │
│ 64 × 16-bit signed = 128 bytes        │
└───────────────────────────────────────┘
```

### Frame Journey

```
1. Tile Sensor COG:
   - Scans hardware in physical order
   - Subtracts baseline[i] from raw[i]
   - Remaps to logical grid positions
   - Writes to Sensor FIFO

2. Decimator COG:
   - Reads from Sensor FIFO @ 375 fps
   - Selects every 6th frame
   - Writes same frame to BOTH:
     * OLED FIFO
     * HDMI FIFO

3. Display COGs (parallel):
   - OLED: Reads OLED FIFO, renders to 128×128 OLED
   - HDMI: Reads HDMI FIFO, renders to VGA/HDMI output
```

---

## Hardware Interface

### Tile Sensor Pins (P8-P15)

| Pin | Function | Wire Color | Direction | Description |
|-----|----------|------------|-----------|-------------|
| P8 | CS | VIOLET | Output | AD7680 Chip Select |
| P9 | CCLK | WHITE | Output | Counter Clock (sensor advance) |
| P10 | MISO | BLUE | Input | AD7680 Data Output |
| P11 | CLRb | GRAY | Output | Counter Clear (reset) |
| P12 | SCLK | GREEN | Output | AD7680 SPI Clock |
| P13 | (unused) | - | - | Reserved |
| P14 | (unused) | - | - | Reserved |
| P15 | AOUT | YELLOW | - | Analog Output (not used) |

### OLED Display Pins (P16-P23)

| Pin | Function | Description |
|-----|----------|-------------|
| P16-P23 | SPI + DC/RST/CS | SSD1351 128×128 OLED |

### HDMI/VGA Pins

| Pin Group | Function |
|-----------|----------|
| DVI pins | Digital video output |

---

## System Startup Sequence

```spin2
PUB main() | fifo_obj

    debug("=== Magnetic Imaging Tile System ===")

    '═══════════════════════════════════════════════════════
    ' PHASE 1: Initialize FIFO System
    '═══════════════════════════════════════════════════════
    debug("Initializing FIFO system...")
    fifo_obj := fifo.start()
    ' FIFOs #0, #1, #2 now allocated and ready

    '═══════════════════════════════════════════════════════
    ' PHASE 2: Start Consumers First (avoid overflow)
    '═══════════════════════════════════════════════════════
    debug("Starting display subsystems...")
    oled_cog := oled_display.start(fifo_obj, FIFO_OLED)
    hdmi_cog := hdmi_display.start(fifo_obj, FIFO_HDMI)

    '═══════════════════════════════════════════════════════
    ' PHASE 3: Start Middle Tier (decimator)
    '═══════════════════════════════════════════════════════
    debug("Starting decimator...")
    decimator_cog := decimator.start(fifo_obj, FIFO_SENSOR,
                                      FIFO_OLED, FIFO_HDMI)

    '═══════════════════════════════════════════════════════
    ' PHASE 4: Start Producer Last
    '═══════════════════════════════════════════════════════
    debug("Starting tile sensor acquisition...")
    sensor_cog := tile_sensor.start(fifo_obj, FIFO_SENSOR)

    '═══════════════════════════════════════════════════════
    ' PHASE 5: System Calibration
    '═══════════════════════════════════════════════════════
    debug("Calibrating baseline (no magnet)...")
    tile_sensor.calibrate_baseline(100)  ' 100 samples

    debug("=== All Subsystems Running ===")
    debug("Sensor: ", udec(sensor_cog))
    debug("Decimator: ", udec(decimator_cog))
    debug("OLED: ", udec(oled_cog))
    debug("HDMI: ", udec(hdmi_cog))

    '═══════════════════════════════════════════════════════
    ' PHASE 6: Main COG Monitoring Loop
    '═══════════════════════════════════════════════════════
    repeat
        ' Optional: Monitor system health
        monitor_system()
        WAITMS(1000)
```

---

## Decimator Strategies

### Current: Simple Frame Selection (Every Nth)

```spin2
PRI decimator_loop(sensor_fifo, oled_fifo, hdmi_fifo) | frame[64], count

    DECIMATION_RATIO := 6    ' 375 fps ÷ 6 = 62.5 fps
    count := 0

    repeat
        ' Read next frame from sensor FIFO (375 fps)
        pop_frame(sensor_fifo, @frame)

        count++
        if count >= DECIMATION_RATIO
            count := 0

            ' Push same frame to BOTH displays
            push_frame(oled_fifo, @frame)
            push_frame(hdmi_fifo, @frame)
```

**Characteristics**:
- Simple, deterministic
- Low latency (6 frame periods = 16ms)
- No additional processing overhead

### Future: Frame Averaging (Smoother)

```spin2
' Average 6 consecutive frames
accumulate_frame(@frame)
if count == DECIMATION_RATIO
    averaged_frame := accumulator / 6
    push_to_displays(averaged_frame)
    clear_accumulator()
```

**Characteristics**:
- Noise reduction
- Smoother visualization
- Higher latency (6 frame periods)

---

## Pixel Remapping

### Hardware Scanning Order

The magnetic tile hardware scans sensors in a specific order:
- **Subtile order**: 0, 2, 1, 3 (NOT sequential!)
- **Within subtile**: Serpentine pattern

### Logical 8×8 Grid Mapping

```
Logical Grid (what user expects):
┌─────────────────────────────┐
│  0   1   2   3   4   5   6   7  │  Row 0
│  8   9  10  11  12  13  14  15  │  Row 1
│ 16  17  18  19  20  21  22  23  │  Row 2
│ 24  25  26  27  28  29  30  31  │  Row 3
│ 32  33  34  35  36  37  38  39  │  Row 4
│ 40  41  42  43  44  45  46  47  │  Row 5
│ 48  49  50  51  52  53  54  55  │  Row 6
│ 56  57  58  59  60  61  62  63  │  Row 7
└─────────────────────────────┘
```

**Remap Table**: `remap_hw_to_logical[64]` (created during initialization)

---

## Calibration Process

### Baseline Calibration (Zero-Field Reference)

```spin2
PUB calibrate_baseline(num_samples) | i, s, sum

    ' Ensure no magnet near sensor during calibration!

    repeat i from 0 to 63
        sum := 0

        ' Average multiple samples per sensor
        repeat s from 0 to num_samples - 1
            reset_counter()
            advance_to_sensor(i)
            sum += read_sensor()

        ' Store baseline
        baseline[i] := sum / num_samples

    debug("Baseline calibration complete")
```

**When to calibrate**:
- System startup (automatic)
- User command (manual re-calibration)
- Temperature change detected (future)

---

## Performance Monitoring

### Available Metrics

```spin2
PUB get_sensor_stats() : stats_ptr
'' Returns pointer to stats structure
''
'' stats[0] = current frame rate (fps)
'' stats[1] = average scan time (µs)
'' stats[2] = FIFO depth (current)
'' stats[3] = FIFO overruns (count)
'' stats[4] = frames processed (total)
```

### Debug Output Example

```
=== System Status ===
Sensor COG:    375.2 fps, 648 µs/frame
Sensor FIFO:   8/32 frames (25% full)
Decimator:     62.5 fps output
OLED FIFO:     2/4 frames (50% full)
HDMI FIFO:     1/4 frames (25% full)
Total frames:  12,458
Overruns:      0
```

---

## Memory Usage Summary

| Component | Memory | Location |
|-----------|--------|----------|
| **COG RAM** | | |
| Tile Sensor Code | ~300 longs | COG 1 |
| Sensor Variables | ~200 longs | COG 1 |
| **HUB RAM** | | |
| Sensor FIFO | 4 KB | Hub |
| OLED FIFO | 512 B | Hub |
| HDMI FIFO | 512 B | Hub |
| Baseline Array | 128 B | Hub |
| Remap Table | 64 B | Hub |
| Display Buffers | Variable | Hub |
| **Total** | **~6 KB** | **(of 512 KB)** |

**Hub RAM Usage**: < 2% of available
**Plenty of room for future expansion**

---

## Future Expansion Possibilities

### Additional Features (3 COGs available)

1. **Serial Communication COG** - Host PC interface
2. **Data Logging COG** - Record frames to external storage
3. **Processing COG** - Real-time analysis (magnet detection, tracking)

### Performance Scaling

| Target FPS | Frame Period | Decimation Ratio | Display FPS |
|------------|--------------|------------------|-------------|
| 375 (current) | 2,670 µs | 6:1 | 62.5 |
| 750 | 1,333 µs | 12:1 | 62.5 |
| 1,200 | 833 µs | 20:1 | 60 |
| 1,500 (max) | 667 µs | 25:1 | 60 |

---

## Error Handling

### Potential Issues & Mitigation

| Issue | Detection | Response |
|-------|-----------|----------|
| FIFO Overflow | Counter in FIFO | Log error, continue |
| ADC Format Error | Bit validation | Log, use previous value |
| COG Crash | Watchdog (future) | Restart COG |
| Calibration Failure | Value range check | Retry or use defaults |

---

## Document History

| Date | Version | Changes |
|------|---------|---------|
| 2025-10-21 | 1.0 | Initial architecture document |

---

*This architecture provides a robust, scalable foundation for the magnetic imaging tile system with clean separation of concerns and autonomous operation.*
