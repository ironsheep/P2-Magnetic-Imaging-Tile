# Sensor Architecture
**Magnetic Imaging Tile - Sensor Acquisition Subsystem**

## Document Version
- **Version:** 1.0
- **Date:** 2025-11-04
- **Status:** Design Specification

## Overview

The Sensor subsystem is responsible for acquiring magnetic field measurements from the 8×8 Hall effect sensor array at high frame rates (target: 2000 fps). It interfaces with the SparkFun Magnetic Imaging Tile V3 hardware through a multiplexed analog front-end and external 16-bit ADC, producing calibrated frames for downstream processing and display.

## Design Goals

1. **Maximum Frame Rate** - Achieve up to 2000 fps sensor acquisition
2. **Dual COG Architecture** - Separate PASM acquisition from FIFO coordination
3. **Hardware Accuracy** - Proper sensor selection, settling, and ADC timing
4. **Baseline Calibration** - Zero-field reference for differential measurements
5. **Mailbox Coordination** - Efficient Spin2 ↔ PASM communication

---

## System Context

### Hardware Interface

**SparkFun Magnetic Imaging Tile V3:**
- **Sensor Array:** 8×8 Hall effect sensors (64 total)
- **Organization:** 4 subtiles (quadrants) of 4×4 sensors each
- **Multiplexer:** Binary counter advances through sensor positions
- **ADC:** AD7680 16-bit external ADC (2.5 MHz SPI maximum)

### Pin Assignments (P8-P15)

| Pin | Function | Wire Color | Direction | Description |
|-----|----------|------------|-----------|-------------|
| P8 | CS | VIOLET | Output | AD7680 Chip Select |
| P9 | CCLK | WHITE | Output | Counter Clock (sensor advance) |
| P10 | MISO | BLUE | Input | AD7680 SPI Data |
| P11 | CLRb | GRAY | Output | Counter Clear (reset) |
| P12 | SCLK | GREEN | Output | AD7680 SPI Clock |
| P15 | AOUT | YELLOW | - | Analog Output (not used by P2) |

### Integration with System

```
Magnetic Tile Sensor → Multiplexer → AD7680 → P2 (SPI) → Sensor COGs → FIFO_SENSOR
```

**Output:** 64 × 16-bit readings per frame (128 bytes) to FIFO_SENSOR

---

## COG Allocation

### Dual COG Architecture

**Sensor subsystem uses 2 COGs:**

1. **PASM Acquisition COG**
   - **Role:** High-speed sensor scanning and ADC readout
   - **Type:** PASM2 assembly (coginit)
   - **Criticality:** Hard real-time (timing-critical hardware interface)

2. **FIFO Manager COG**
   - **Role:** Frame buffer coordination and FIFO integration
   - **Type:** Spin2 (cogspin)
   - **Criticality:** Soft real-time (memory coordination)

### Why Two COGs?

**Separation of Concerns:**
- **PASM COG:** Focuses on precise hardware timing (SPI, settling, counter control)
- **Manager COG:** Handles Hub RAM coordination (FIFO operations, frame allocation)

**Mailbox Coordination:**
- Manager provides empty frame buffer pointer
- PASM fills buffer with sensor data
- Manager commits completed frame to FIFO_SENSOR

**Benefits:**
- Clean separation of timing-critical code
- Easier debugging (Spin2 vs PASM)
- FIFO operations don't interfere with sensor timing

---

## Data Flow

### Frame Acquisition Pipeline

```
┌────────────────────────────────────────────────────────────────┐
│               FIFO Manager COG (Spin2)                         │
│                                                                │
│  1. fifo.getNextFrame()      → Get empty buffer from pool     │
│  2. mailbox_frame_ptr := ptr → Pass to PASM COG               │
│  3. mailbox_go_flag := 1     → Signal PASM to capture         │
│  4. Wait for mailbox_go_flag == 0 (PASM done)                 │
│  5. fifo.commitFrame()       → Post to FIFO_SENSOR            │
│     (or releaseFrame if FIFO full)                            │
└────────────────────────────────────────────────────────────────┘
                               ↓ (mailbox)
┌────────────────────────────────────────────────────────────────┐
│               PASM Acquisition COG                             │
│                                                                │
│  1. Wait for mailbox_go_flag == 1                             │
│  2. Read mailbox_frame_ptr                                    │
│  3. Reset counter (CLRb pulse)                                │
│  4. For each sensor 0-63:                                     │
│     a. Advance counter (CCLK pulse)                           │
│     b. Wait for analog settling (5µs)                         │
│     c. CS low (capture analog value)                          │
│     d. Wait 2µs (critical settling time)                      │
│     e. Bit-bang 20 SPI clocks @ 2.5 MHz                       │
│     f. Extract 16-bit value, apply remapping                  │
│     g. Write to frame buffer at logical position              │
│  5. mailbox_go_flag := 0 (signal done)                        │
└────────────────────────────────────────────────────────────────┘
```

---

## Hardware Scanning

### Subtile Reading Order

**Hardware Scans Subtiles Non-Sequentially:**
```
Scan Order:   0 → 2 → 1 → 3
Physical:     TL  TR  BL  BR  (Top-Left, Top-Right, Bottom-Left, Bottom-Right)
```

**Frame Buffer Offsets (words):**
```
Subtile 0: offset 0   (sensors 0-15   → frame positions varies)
Subtile 1: offset 32  (sensors 16-31  → frame positions varies)
Subtile 2: offset 4   (sensors 32-47  → frame positions varies)
Subtile 3: offset 36  (sensors 48-63  → frame positions varies)
```

### Pixel Remapping

**Within Each Subtile:**
- Serpentine scanning pattern (alternating left-right, right-left rows)
- Requires lookup table to convert counter position → logical grid position

**Mapping Tables (in DAT section):**
```spin2
subtile_order   BYTE    0, 2, 1, 3             ' Scan sequence
subtile_offset  BYTE    0, 4, 32, 36           ' Frame buffer base offsets
pixel_order     BYTE    26, 27, 18, 19, ...    ' Position mapping within subtile
```

**Example:**
```
Counter at position 0, subtile 0 → Frame buffer index 26 → Row 3, Col 2
Counter at position 1, subtile 0 → Frame buffer index 27 → Row 3, Col 3
```

### Logical 8×8 Output

**Final Frame Structure (what display sees):**
```
Frame buffer (WORD array[64]):
[0]  = Row 0, Col 0
[1]  = Row 0, Col 1
...
[7]  = Row 0, Col 7
[8]  = Row 1, Col 0
...
[63] = Row 7, Col 7
```

---

## Timing Analysis

### Per-Sensor Timing (Bit-Banged SPI)

| Operation | Time | Clocks @ 200MHz | Criticality |
|-----------|------|-----------------|-------------|
| Counter advance (CCLK pulse) | 1µs | 200 | Required |
| Multiplexer settling | 5µs | 1000 | **CRITICAL** |
| CS low (analog capture) | 2µs | 400 | **CRITICAL** |
| SPI transfer (20 clocks @ 2.5 MHz) | 8µs | 1600 | Required |
| Processing overhead | ~1µs | 200 | Minimal |
| **Total per sensor** | **~17µs** | **~3400** | - |

**Critical Timing Requirements:**
1. **Multiplexer Settling (5µs):** Must allow analog signal to stabilize after switching sensors
2. **Analog Capture Delay (2µs):** AD7680 captures analog value on CS falling edge, needs settling
3. **SPI Timing (400ns period):** Stay within AD7680 specification (2.5 MHz max)

### Frame-Level Timing

**64 Sensors per Frame:**
```
Frame time = 64 sensors × 17µs = 1,088µs = 1.09ms
Maximum frame rate = 1 / 1.09ms ≈ 918 fps (theoretical)
```

**Current Target: 2000 fps (0.5ms period)**
- Frame time: 1.09ms actual
- **Gap:** Need to optimize by 2.2× for 2000 fps

**Possible Optimizations:**
1. **Reduce multiplexer settling** - Test if 2-3µs is sufficient (vs 5µs)
2. **Use Smart Pins for SPI** - Hardware SPI could be faster than bit-bang
3. **Pipeline operations** - Start next counter advance during SPI transfer
4. **PASM optimization** - Minimize instruction count in inner loop

**Achievable Rates:**
- **Current implementation:** ~918 fps (confirmed by timing)
- **With 3µs settling:** ~1200 fps (64 × 13µs = 832µs)
- **With Smart Pin SPI:** ~1500 fps (if SPI overhead reduced)
- **Target 2000 fps:** Requires aggressive optimization

---

## Baseline Calibration

### Zero-Field Reference

**Purpose:** Capture sensor readings with no magnetic field present to establish baseline

**Calibration Process:**
```spin2
PUB calibrate_baseline()
  ' Temporarily stop acquisition
  acquisition_mode := MODE_STOPPED
  WAITMS(10)

  ' Read all 64 sensors in sequence
  reset_counter_test()
  advance_counter_test()
  repeat i from 0 to 63
    baseline[i] := read_single_sensor_bitbang()
    if i < 63
      advance_counter_test()

  baseline_valid := TRUE
```

**Storage:**
```spin2
VAR
  WORD baseline[64]        ' Per-sensor baseline values
  LONG baseline_valid      ' TRUE if calibrated
```

**Usage (in PASM acquisition):**
```pasm2
' Read sensor value
call    #read_adc_bitbang
mov     sensor_val, adc_result

' If baseline valid, subtract baseline
rdlong  temp, baseline_valid_ptr
tjz     temp, #no_baseline
rdword  baseline_val, baseline_addr
sub     sensor_val, baseline_val

no_baseline
' Store to frame buffer
wrword  sensor_val, frame_addr
```

**When to Calibrate:**
- System startup (after sensor COGs running)
- User command (manual re-calibration)
- Temperature change (future enhancement)
- After hardware power cycle

---

## Acquisition Modes

### Mode Definitions

```spin2
CON
  MODE_STOPPED      = 0    ' No acquisition
  MODE_LIVE         = 1    ' Normal live acquisition
  MODE_HIGH_SPEED   = 2    ' Maximum frame rate
  MODE_DEBUG        = 3    ' Debug with verbose output
  MODE_TEST_PATTERN = 4    ' Generate test patterns (no hardware read)
```

### Current Implementation

**MODE_TEST_PATTERN (4):**
- Used during initial startup
- Generates synthetic patterns for testing FIFO pipeline
- No actual sensor hardware accessed
- Useful for display subsystem testing

**Future Modes:**
- **MODE_LIVE:** Standard operation with baseline subtraction
- **MODE_HIGH_SPEED:** Minimal processing, maximum frame rate
- **MODE_DEBUG:** Additional telemetry and validation

---

## Performance Monitoring

### Statistics Available

```spin2
VAR
  LONG frame_count          ' Total frames captured
  LONG error_count          ' SPI/sensor errors
  LONG last_frame_time      ' Timestamp of last frame
  LONG min_frame_time       ' Minimum time between frames
  LONG max_frame_time       ' Maximum time between frames
```

### Error Detection

**SPI Format Validation:**
- AD7680 sends 4 leading zeros before 16-bit data
- PASM checks if bits 19-16 are all zero
- Increments error_count if format invalid

**Error Types:**
- **Format Error:** Leading zeros not zero (hardware issue)
- **FIFO Full:** commitFrame fails (downstream bottleneck)

---

## Mailbox Protocol

### Shared Variables (Hub RAM)

```spin2
VAR
  LONG mailbox_frame_ptr    ' Frame buffer pointer (Manager → PASM)
  LONG mailbox_go_flag      ' Handshake: 1=capture, 0=done
```

### Protocol Sequence

**Manager COG (Spin2):**
```spin2
PRI fifo_manager_loop() | framePtr
  repeat
    ' Get empty frame buffer
    framePtr := fifo.getNextFrame()
    if framePtr == 0
      waitms(1)
      next

    ' Provide to PASM and signal
    mailbox_frame_ptr := framePtr
    mailbox_go_flag := 1

    ' Wait for PASM completion
    repeat until mailbox_go_flag == 0

    ' Commit or release
    if fifo.commitFrame(fifo.FIFO_SENSOR, framePtr) < 0
      fifo.releaseFrame(framePtr)
```

**PASM COG:**
```pasm2
acquisition_loop
    ' Wait for work
    rdlong  temp, mailbox_go_addr
    tjz     temp, #acquisition_loop

    ' Get frame pointer
    rdlong  frame_ptr, mailbox_ptr_addr

    ' [Scan all 64 sensors, fill frame buffer]
    call    #scan_all_sensors

    ' Signal completion
    wrlong  zero, mailbox_go_addr
    jmp     #acquisition_loop
```

**Synchronization:**
- Manager blocks waiting for PASM (`repeat until mailbox_go_flag == 0`)
- PASM blocks waiting for Manager (`tjz temp, #acquisition_loop`)
- No polling overhead - efficient COG sleep while waiting

---

## Error Handling

### FIFO Full Condition

**Symptom:** `commitFrame()` returns negative value

**Response:**
```spin2
if fifo.commitFrame(fifo.FIFO_SENSOR, framePtr) < 0
  ' FIFO full - downstream can't keep up
  fifo.releaseFrame(framePtr)    ' Return buffer to pool
  ' Frame dropped, continue acquisition
```

**Prevention:**
- Proper decimation ratios (match sensor rate to display capacity)
- FIFO depth sizing (16 frames for sensor FIFO)

### ADC Format Errors

**Detection:**
```pasm2
' Check leading zeros (bits 19-16 should be 0000)
test    adc_val, ##$F0000 wz
if_nz   add     error_count, #1    ' Increment error counter
```

**Response:**
- Log error to error_count variable
- Use raw value anyway (data may still be valid)
- Investigate if error rate exceeds threshold

---

## Testing & Validation

### Unit Tests

**Pin Connectivity Test:**
```spin2
PUB test_pin_toggle(cycles)
  ' Binary counting pattern on all 5 control pins
  ' Each pin toggles at unique frequency
  ' Visible on logic analyzer for pin identification
```

**Single Sensor Read:**
```spin2
PUB read_single_sensor_bitbang() : value
  ' Test reading from specific sensor position
  ' Validates: counter control, SPI timing, ADC communication
```

**Full Frame Scan:**
```spin2
PUB read_all_sensors_test(buffer_ptr)
  ' Read all 64 sensors in sequence
  ' Validates: full scanning cycle, settling times
```

### Integration Tests

**Frame Pipeline:**
1. Start sensor COGs
2. Verify frame_count incrementing
3. Monitor FIFO_SENSOR depth
4. Check for error_count increases

**Performance Validation:**
```spin2
PUB get_performance_stats(stats_ptr)
  LONG[stats_ptr][0] := frame_count
  LONG[stats_ptr][1] := error_count
  LONG[stats_ptr][2] := current_fps   ' Calculated from min_frame_time
```

**Expected Results:**
- Frame rate: ~375-918 fps (depending on optimization)
- Error count: 0 (or very low)
- FIFO depth: 2-4 frames typical

---

## Known Limitations

### Current Constraints

1. **Frame Rate:** ~918 fps maximum (vs 2000 fps target)
   - Multiplexer settling time dominates (5µs × 64 = 320µs)
   - SPI bit-bang overhead (~8µs × 64 = 512µs)

2. **Bit-Banged SPI:** Software timing vs hardware Smart Pins
   - More CPU cycles consumed
   - Less consistent timing

3. **No Pipeline Overlap:** Sequential sensor operations
   - Could overlap counter advance with SPI transfer
   - Would require careful PASM optimization

4. **Fixed Timing Constants:** Not adaptive
   - Settling times hardcoded
   - May be over-conservative

---

## Future Enhancements

### Performance Optimizations

**Level 1: Timing Tuning (Quick Wins)**
- Reduce multiplexer settling from 5µs → 2-3µs (test with hardware)
- Optimize PASM inner loop (minimize instructions)
- **Estimated gain:** 918 fps → 1200 fps

**Level 2: Smart Pin SPI (Moderate Effort)**
- Use P2 Smart Pins for hardware SPI
- Configure P_SYNC_RX mode for MISO
- Free PASM cycles during transfer
- **Estimated gain:** 1200 fps → 1500 fps

**Level 3: Pipeline Overlap (Advanced)**
- Start next counter advance during current SPI transfer
- Requires careful timing coordination
- **Estimated gain:** 1500 fps → 1800+ fps

**Level 4: Dual ADC Support (Hardware Change)**
- Read two sensors simultaneously
- Requires second AD7680 and additional pins
- **Estimated gain:** 1800 fps → 2000+ fps

### Feature Additions

**Temperature Compensation:**
- Monitor P2 internal temperature
- Auto-calibrate if drift detected
- Periodic baseline refresh

**Multi-Sensor Support:**
- Multiple 8×8 tiles
- Separate sensor COG pairs per tile
- Aggregated or comparative displays

**Adaptive Settling:**
- Measure actual settling time per sensor
- Use minimum safe settling time
- Dynamic adjustment based on signal quality

---

## Related Documents

- **System Architecture:** `DOCs/Architecture/System-Architecture.md`
- **OLED Driver:** `DOCs/Architecture/OLED-Driver-Architecture.md`
- **HDMI/PSRAM:** `DOCs/Architecture/HDMI-PSRAM-Architecture.md`
- **Image Processing:** `DOCs/Architecture/Image-Processing-Architecture.md`
- **Hardware Pinout:** `DOCs/MagneticTile-Pinout.taskpaper`

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-04 | Claude + Stephen | Initial sensor architecture specification |
