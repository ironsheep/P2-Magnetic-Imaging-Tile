# System Architecture
**Magnetic Imaging Tile - Complete System**

## Document Version
- **Version:** 2.0
- **Date:** 2025-11-04
- **Status:** Design Specification
- **Supersedes:** Version 1.0 (2025-10-21)

## Overview

The P2 Magnetic Imaging Tile system is a real-time magnetic field visualization platform that captures data from an 8×8 sensor array at up to 2000 fps and displays the results on dual output devices (HDMI 640×480 @ 60fps and OLED 128×128 @ 60fps). The architecture uses a FIFO-based pipeline with autonomous COG chains to achieve maximum throughput across all subsystems.

## Design Philosophy

### Maximum Performance Goals
1. **Sensor Acquisition:** Maximum sustainable frame rate (target: 2000 fps)
2. **HDMI Display:** 60 fps sustained (hardware-limited by display refresh)
3. **OLED Display:** 60 fps sustained (matched to processing capacity)
4. **Non-Blocking Operation:** Sensor never blocked by display processing

### Architectural Principles
1. **Autonomous COG Chains:** Display pipelines run independently in parallel
2. **Zero-Copy Buffers:** Frame data passed by reference, not copied
3. **FIFO-Based Coordination:** Lock-protected queues for inter-COG communication
4. **Hardware Acceleration:** Leverage P2 Smart Pins, Streamer, and CORDIC where applicable

---

## COG Allocation

### Target Architecture (5 COGs + 3 Available)

| COG | Role | Type | Criticality | Notes |
|-----|------|------|-------------|-------|
| **COG 0** | Main → Decimator | Coordination | Soft RT | Routes frames from sensor to displays |
| **COG 1** | PSRAM Driver | Hardware | Hard RT | 62.5 Mlong/s DMA, required for HDMI |
| **COG 2** | HDMI Streamer | Hardware | Hard RT | 60Hz video timing, P2 Streamer |
| **COG 3** | ~~Graphics~~ **FREE** | - | - | **Eliminated** - unused anti-aliasing |
| **COG 4** | HDMI Manager | Display Chain | Soft RT | Autonomous, renders 8×8 grid via PSRAM |
| **COG 5** | OLED Consolidated | Display Chain | Soft RT | Single COG: dequeue + convert + stream |
| **COG 6** | **Available** | - | - | Freed by OLED consolidation |
| **COG 7** | **Available** | - | - | Frame processor moved to COG 0 |

**Available for Future:**
- COG 3: Processing COG (multi-frame analysis)
- COG 6: Sensor FIFO manager or second sensor
- COG 7: Additional processing or communications

### Previous vs Current Comparison

**Previous Architecture (Version 1.0):**
```
COG0: Main (monitoring only)
COG1: Tile Sensor
COG2: Decimator
COG3: OLED Display
COG4: HDMI Display
COG5-7: Available
```

**Current Architecture (Version 2.0):**
```
COG0: Main → Decimator ✓
COG1: PSRAM Driver ✓
COG2: HDMI Streamer ✓
COG3: [FREE]
COG4: HDMI Manager ✓
COG5: OLED Consolidated ✓
COG6-7: [FREE]
+ Sensor COGs: TBD
```

**Key Changes:**
1. Frame Processor/Decimator moved to Main COG (simple routing logic)
2. OLED consolidated from 2 COGs → 1 COG
3. Graphics COG eliminated (completely unused anti-aliasing PASM)
4. Sensor architecture to be documented separately

---

## Data Flow Architecture

### FIFO Structure

```
                    ┌─────────────────┐
                    │  Sensor COG(s)  │
                    │   (See Sensor   │
                    │  Architecture)  │
                    └────────┬────────┘
                             │ Raw 8×8 frames (2000 fps capable)
                             ↓
                    ┌────────────────────┐
                    │   FIFO_SENSOR (0)  │
                    │   Depth: 16 frames │
                    │   Size: 128 bytes  │
                    └────────┬───────────┘
                             │
                    ┌────────▼────────┐
                    │   Main COG 0    │
                    │   (Decimator)   │
                    │   Simple routing│
                    └────┬──────┬─────┘
                         │      │
         ┌───────────────┘      └───────────────┐
         │ 1:33 decimation                     │ 1:32 decimation
         │ (2000÷33 ≈ 60 fps)                  │ (2000÷32 = 62.5 fps)
         ↓                                      ↓
┌─────────────────┐                    ┌─────────────────┐
│  FIFO_HDMI (2)  │                    │  FIFO_OLED (3)  │
│  Depth: 4       │                    │  Depth: 4       │
│  Size: 128 B    │                    │  Size: 128 B    │
└────────┬────────┘                    └────────┬────────┘
         │                                      │
         ↓                                      ↓
┌──────────────────┐                   ┌──────────────────┐
│  HDMI Manager    │                   │  OLED Manager    │
│     (COG 4)      │                   │     (COG 5)      │
│   Autonomous     │                   │   Autonomous     │
│   Renders 8×8    │                   │   Single COG     │
│   via FillRect   │                   │   Consolidated   │
└────────┬─────────┘                   └────────┬─────────┘
         │                                      │
         │ FillRect → PSRAM                    │ SPI stream
         ↓                                      ↓
┌──────────────────┐                   ┌──────────────────┐
│  PSRAM Graphics  │                   │   SSD1351 OLED   │
│  + HDMI Stream   │                   │   128×128 RGB565 │
│  (COG 1, 2)      │                   │   (Smart Pins)   │
└──────────────────┘                   └──────────────────┘
    640×480 RGB888                          128×128 RGB565
    60 fps (locked)                         60 fps (matched)
```

### Future: Processing COG Addition

```
                    ┌─────────────────┐
                    │   Sensor COG    │
                    └────────┬────────┘
                             ↓
                    ┌────────────────────┐
                    │   FIFO_SENSOR (0)  │
                    └────────┬───────────┘
                             │
                    ┌────────▼────────────┐
                    │  Processing COG 3   │
                    │  (Multi-frame)      │
                    │  • 33-frame window  │
                    │  • 5 modes          │
                    │  • Super-resolution │
                    └────────┬────────────┘
                             │ Composites (8×8 to 32×32)
                             ↓
                    ┌────────────────────┐
                    │  FIFO_RESULTS (1)  │ ← NEW
                    │  Depth: 4 frames   │
                    │  Size: up to 2KB   │
                    └────────┬───────────┘
                             │
                    ┌────────▼────────┐
                    │   Main COG 0    │
                    │   (Router)      │
                    │   Routes results│
                    └────┬──────┬─────┘
                         │      │
                         ↓      ↓
                    HDMI      OLED
```

---

## Frame Pipeline Timing

### Sensor Acquisition
- **Hardware Capability:** 2000 fps (0.5ms per frame)
- **Target Rate:** TBD pending sensor COG documentation
- **Output:** Raw 64 × 16-bit readings (128 bytes per frame)
- **See:** `DOCs/Architecture/Sensor-Architecture.md` (TBD)

### Main Decimator (COG 0)
- **Input:** FIFO_SENSOR at sensor rate
- **Processing:** Simple counter-based decimation
- **Operations per frame:**
  ```spin2
  ' Minimal processing time
  if (frame_counter // 33) == 0
    fifo.enqueue(FIFO_HDMI, framePtr)    ' ~50µs
  if (frame_counter // 32) == 0
    fifo.enqueue(FIFO_OLED, framePtr)    ' ~50µs
  else
    fifo.releaseFrame(framePtr)          ' ~50µs
  ```
- **Total time:** <200µs per frame (negligible vs 500µs sensor period)
- **Output rates:**
  - HDMI: 2000 ÷ 33 ≈ 60.6 fps
  - OLED: 2000 ÷ 32 = 62.5 fps

### HDMI Chain (COG 4 → COG 1, 2)

**COG 4: HDMI Manager**
- **Input:** FIFO_HDMI @ 60 fps (blocking dequeue)
- **Processing:** Render 8×8 grid to PSRAM
  - 64 cells × FillRect (30×30 pixels each)
  - Each FillRect: ~30µs (900 bytes ÷ 62.5 Mlong/s)
  - Total rendering: ~2.4ms
- **Output:** Updates PSRAM frame buffer
- **Frame release:** Returns to FIFO pool
- **See:** `DOCs/Architecture/HDMI-PSRAM-Architecture.md`

**COG 1: PSRAM Driver**
- **Role:** Hardware DMA between Hub RAM ↔ PSRAM
- **Performance:** 62.5 Mlong/s (250 MB/s)
- **Service:** All COGs via mailbox polling

**COG 2: HDMI Streamer**
- **Role:** 60Hz video timing, reads PSRAM → HDMI
- **Timing:** Hardware-locked to display refresh
- **Cannot exceed 60 fps** (VESA 640×480 standard)

**Total HDMI latency:** 2.4ms rendering + 16.67ms display = ~19ms

### OLED Chain (COG 5)

**Consolidated Single COG:**
- **Input:** FIFO_OLED @ 62.5 fps (blocking dequeue)
- **Processing breakdown:**
  1. Dequeue frame: <0.1ms
  2. Convert 64 sensors → RGB565: ~1ms
  3. Build 32KB display buffer: ~1ms
  4. Stream via SPI (Smart Pins): ~14ms
  5. Release frame: <0.1ms
- **Total:** ~16ms per frame = **62.5 fps maximum**
- **Sustainable:** Yes (input rate matches capacity)
- **See:** `DOCs/Architecture/OLED-Driver-Architecture.md`

**Performance Analysis:**
- Input: 62.5 fps (16ms period)
- Processing: 16ms
- **Utilization: 100%** (perfectly matched)
- FIFO depth variance: 0-1 frames typical

---

## Memory Architecture

### Hub RAM Allocation

**Frame Buffer Pool:**
```
FIFO_SENSOR:  16 frames × 128 bytes  = 2,048 bytes
FIFO_HDMI:     4 frames × 128 bytes  =   512 bytes
FIFO_OLED:     4 frames × 128 bytes  =   512 bytes
                                Total: 3,072 bytes
```

**Display Buffers:**
```
HDMI row buffer:     1 row × 640 × 4 bytes  = 2,560 bytes
OLED frame buffer:   128 × 128 × 2 bytes    = 32,768 bytes
                                      Total: 35,328 bytes
```

**Total System RAM:** ~38 KB (out of 512 KB available = 7.4% used)

### PSRAM Allocation (32 MB)

**HDMI Frame Buffer:**
```
640 × 480 × 4 bytes (RGB888 + padding) = 1,228,800 bytes
Double buffering (optional):            = 2,457,600 bytes
```

**Available:** 29+ MB for future use (image capture, processing buffers, etc.)

---

## Performance Targets & Analysis

### Sensor Throughput
- **Goal:** Maximum sustainable rate
- **Constraint:** TBD pending sensor COG documentation
- **Decimator overhead:** <200µs per frame (negligible)
- **Bottleneck:** Sensor hardware and FIFO management

### Display Frame Rates

| Display | Target | Actual | Headroom | Limiting Factor |
|---------|--------|--------|----------|-----------------|
| HDMI | 60 fps | 60 fps | 0% | Hardware refresh rate |
| OLED | 60 fps | 62.5 fps | +4% | SPI streaming time |

### FIFO Depth Utilization

**Steady State (properly decimated):**
```
FIFO_SENSOR:  2-4 frames typical (sensor burst tolerance)
FIFO_HDMI:    0-1 frames (consumer matches producer)
FIFO_OLED:    0-1 frames (consumer matches producer)
```

**FIFO Full Conditions:**
- FIFO_SENSOR: If sensor rate exceeds decimator capacity (unlikely)
- FIFO_HDMI: If HDMI rendering exceeds 16.67ms (unlikely at 2.4ms)
- FIFO_OLED: If OLED processing exceeds 16ms (matched, should not occur)

**Recovery:** Automatic frame drop at FIFO full (oldest discarded)

---

## Component Architectures (Cross-Reference)

### Sensor Architecture (TBD)
**Document:** `DOCs/Architecture/Sensor-Architecture.md`

**Requirements:**
- High-speed acquisition (2000 fps target)
- 8×8 sensor array scanning
- Baseline calibration support
- Pixel remapping (hardware → logical order)
- FIFO_SENSOR output

**To Be Documented:**
1. COG allocation strategy
2. ADC interface (internal vs external)
3. Counter control logic
4. Timing analysis
5. Calibration procedures

### OLED Driver
**Document:** `DOCs/Architecture/OLED-Driver-Architecture.md`

**Key Features:**
- Single consolidated COG (Level 1: Smart Pins)
- 62.5 fps sustainable performance
- Future optimization: Level 2 (Streamer/DMA) → 74 fps

**Responsibilities:**
1. Frame acquisition (blocking dequeue)
2. Sensor → RGB565 conversion
3. 32KB buffer construction
4. SPI streaming (PASM2 + Smart Pins)
5. Frame release

### HDMI/PSRAM Display
**Document:** `DOCs/Architecture/HDMI-PSRAM-Architecture.md`

**Key Features:**
- 3 COGs: PSRAM Driver (1), HDMI Streamer (2), Manager (4)
- Graphics COG (3) eliminated (unused)
- 60 fps locked to display refresh
- FillRect rendering: 2.4ms per frame

**Responsibilities:**
1. Frame acquisition from FIFO_HDMI
2. 8×8 grid rendering to PSRAM (64 × FillRect)
3. Color mapping (field value → RGB888)
4. Autonomous operation (non-blocking)

### Image Processing (Future)
**Document:** `DOCs/Architecture/Image-Processing-Architecture.md`

**Key Features:**
- Dedicated Processing COG (future: COG 3)
- 33-frame sliding window
- 5 visualization modes
- New FIFO_RESULTS for composites

**Modes:**
1. Max Precision (8×8, 5.7× SNR improvement)
2. Enhanced Detail (16×16 interpolated)
3. Ultra Detail (32×32 super-resolution)
4. Transient Detector (peak + activity)
5. Scan Trail (panoramic accumulation)

**Performance:** All modes sustainable at 60 fps output

---

## Migration Path

### Phase 1: Basic System (8×8 Simple Decimation)
**Status:** Next implementation phase

**Goals:**
- Get sensor → FIFO → displays working end-to-end
- Validate FIFO coordination
- Confirm frame routing

**Changes:**
1. Main COG becomes decimator (move frame processor logic from COG7)
2. Keep existing HDMI stack as-is
3. Keep existing OLED stack as-is
4. Focus on data flow validation

**Success Criteria:**
- Sensor data visible on both displays
- No FIFO overflow/underflow
- Stable frame rates

### Phase 2: OLED Consolidation
**Status:** After Phase 1 working

**Goals:**
- Free COG 6
- Simplify OLED architecture
- Validate single-COG performance

**Changes:**
1. Merge `isp_oled_manager.spin2` + `isp_oled_driver.spin2`
2. Single COG: dequeue → convert → stream
3. Remove COG 6 allocation

**Success Criteria:**
- OLED maintains 60 fps
- Frame processing <16ms verified
- COG 6 available for other use

### Phase 3: HDMI Optimization
**Status:** After Phase 2 working

**Goals:**
- Free COG 3
- Clean up unused code

**Changes:**
1. Remove Graphics COG launch in `isp_psram_graphics.spin2`
2. Remove unused PASM code (@GraphicsEntry, smooth_pixel, smooth_line)
3. Verify HDMI continues working with FillRect-only rendering

**Success Criteria:**
- HDMI maintains 60 fps
- No visual artifacts
- COG 3 available for other use

### Phase 4: Processing COG (Future)
**Status:** After Phase 1-3 complete

**Goals:**
- Enable multi-frame visualization modes
- Add temporal super-resolution
- Provide multiple viewing modes

**Changes:**
1. Add FIFO_RESULTS to FIFO manager
2. Create Processing COG (assign to COG 3)
3. Implement Mode 1 (8×8 averaging) first
4. Add additional modes incrementally
5. Add mode switching mechanism

**Success Criteria:**
- All 5 modes functional
- Performance targets met (60 fps output)
- User can switch modes via command

---

## Error Handling & Recovery

### FIFO Management

**Overflow Conditions:**
```spin2
PUB enqueue(fifoNum, framePtr) | head_next
  ' If FIFO full, drop oldest frame
  if getQueueDepth(fifoNum) => MAX_DEPTH[fifoNum]
    DEBUG("FIFO ", udec(fifoNum), " FULL - dropping frame")
    releaseFrame(framePtr)
    return false
  ' Normal enqueue
  ...
  return true
```

**Underflow Protection:**
```spin2
PUB dequeue(fifoNum) | framePtr
  ' Block until frame available
  repeat until getQueueDepth(fifoNum) > 0
    ' Sleep efficiently while waiting
  ' Return frame pointer
  ...
  return framePtr
```

### COG Failure Detection

**Startup Validation:**
```spin2
PRI validate_system_startup()
  if psram_cog < 0
    DEBUG("FATAL: PSRAM driver failed")
    abort

  if hdmi_cog < 0
    DEBUG("FATAL: HDMI driver failed")
    abort

  if oled_cog < 0
    DEBUG("FATAL: OLED driver failed")
    abort
```

### Performance Monitoring

**Frame Rate Tracking:**
```spin2
VAR
  LONG frames_processed[4]      ' Per-FIFO counters
  LONG frames_dropped[4]        ' Per-FIFO drop counters
  LONG last_report_time

PRI report_statistics() | elapsed, fps
  elapsed := getms() - last_report_time
  if elapsed => 5000  ' Every 5 seconds
    repeat i from 0 to 3
      fps := (frames_processed[i] * 1000) / elapsed
      DEBUG("FIFO ", udec(i), ": ", udec(fps), " fps, ",
            udec(frames_dropped[i]), " dropped")
    last_report_time := getms()
    longfill(@frames_processed, 0, 4)
    longfill(@frames_dropped, 0, 4)
```

---

## Testing Strategy

### Unit Testing (Component Level)

**OLED Chain:**
1. Test pattern generation (solid colors, gradients)
2. Frame rate measurement (verify 60+ fps)
3. SPI timing validation (logic analyzer)
4. Buffer overflow handling

**HDMI Chain:**
1. Test pattern rendering (checkerboard, stripes)
2. PSRAM write/read verification
3. 60Hz timing lock confirmation
4. Multi-cell rendering performance

**Decimator:**
1. Frame counting accuracy
2. Decimation ratio verification (1:32, 1:33)
3. FIFO enqueue/dequeue balance
4. Frame release correctness

### Integration Testing (System Level)

**End-to-End Pipeline:**
1. Sensor → Both displays simultaneously
2. Known test patterns through full pipeline
3. Frame synchronization verification
4. Long-duration stability test (hours)

**Performance Testing:**
1. Maximum sensor rate testing
2. FIFO depth monitoring under load
3. Frame drop rate measurement
4. COG utilization analysis

**Stress Testing:**
1. Rapid sensor data changes
2. All displays at maximum rate
3. FIFO intentionally flooded
4. COG restart/recovery

---

## Known Limitations & Future Work

### Current Limitations

1. **HDMI Frame Rate:** Locked to 60 fps (display refresh rate)
   - Cannot display faster sensor updates
   - Could write to PSRAM at higher rate but causes tearing

2. **OLED Frame Rate:** SPI limited to ~62 fps
   - Smart Pin implementation: 14ms streaming time
   - Future Streamer/DMA: could reach 74 fps

3. **Simple Decimation:** Current Phase 1 wastes 32/33 frames
   - No multi-frame processing
   - No temporal averaging or super-resolution

4. **Single Sensor Support:** Architecture assumes one 8×8 sensor
   - Multiple sensors would require additional COGs
   - FIFO manager supports up to 8 FIFOs (could expand)

### Future Enhancements

**Processing COG (Phase 4):**
- Multi-frame temporal analysis
- Super-resolution via motion tracking
- Adaptive algorithms (peak detection, filtering)

**OLED Performance (Post-Phase 2):**
- Implement Streamer/DMA for SPI (Level 2)
- Achieve 74 fps maximum
- Free COG cycles during streaming

**Multi-Sensor Support:**
- Add sensor FIFO manager COG
- Support multiple 8×8 tiles
- Aggregate or compare magnetic fields

**Advanced Rendering:**
- Differential updates (only changed regions)
- Compression for static areas
- Color map customization

**Communication Protocol:**
- USB or WiFi data export
- Remote control of modes/parameters
- Real-time data streaming to PC

---

## Related Documents

- **System Overview:** This document
- **Sensor:** `DOCs/Architecture/Sensor-Architecture.md` (TBD)
- **OLED Driver:** `DOCs/Architecture/OLED-Driver-Architecture.md`
- **HDMI/PSRAM:** `DOCs/Architecture/HDMI-PSRAM-Architecture.md`
- **Image Processing:** `DOCs/Architecture/Image-Processing-Architecture.md`
- **FIFO Manager:** `DOCs/Architecture/FIFO-Architecture.md` (TBD)
- **Hardware:** `DOCs/MagneticTile-Pinout.taskpaper`

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-21 | Claude + Stephen | Initial architecture (5 COGs: main monitor, sensor, decimator, 2 displays) |
| 2.0 | 2025-11-04 | Claude + Stephen | Major revision: Main as decimator, OLED consolidation, Graphics COG eliminated, 3 COGs freed |
