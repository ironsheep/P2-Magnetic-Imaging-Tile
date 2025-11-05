# HDMI/PSRAM Display Architecture
**Magnetic Imaging Tile - Display Subsystem**

## Document Version
- **Version:** 1.0
- **Date:** 2025-11-04
- **Status:** Design Specification

## Overview

The HDMI/PSRAM subsystem provides high-resolution 640×480 @ 60Hz display output for magnetic field visualization. The system uses external PSRAM (32MB) as a framebuffer, with P2 hardware streaming the video signal to HDMI in real-time.

## Design Goals

1. **Real-Time Video Output** - Maintain strict 60Hz timing for flicker-free display
2. **High-Performance Graphics** - Fast drawing operations for magnetic field updates
3. **Maximum Frame Rate** - Process sensor frames as quickly as displays can refresh
4. **Minimal COG Usage** - Free COGs for sensor acquisition and processing

---

## System Context

### Input Source
- **Source:** HDMI FIFO (managed by `isp_frame_fifo_manager`)
- **Data Format:** 64 WORDs (128 bytes) - 8×8 sensor array, 16-bit values per sensor
- **Value Range:** 0-4095 (12-bit ADC readings from magnetic tile sensor)

### Output Destination
- **Hardware:** HDMI-capable display (640×480 @ 60Hz)
- **Interface:** P2 pins 0-7 (HDMI pin group)
- **Format:** RGB888 (32-bit per pixel: RRGGBBAA)
- **Framebuffer:** 32MB PSRAM (640 × 480 × 4 bytes = 1,228,800 bytes per frame)

### System Integration
```
Sensor (2000 fps) → Decimator (Main COG) → HDMI FIFO → HDMI Manager → Display (60 Hz)
                         ↓ 1:N                       (process + render)
                    (N fps to HDMI)
```

---

## Current COG Allocation

### COG 1: PSRAM Driver **[REQUIRED]**

**File:** `PSRAM_driver_RJA_Platform_1b.spin2`

**Timing Criticality:** **HARD REAL-TIME**
- Memory interface timing critical (250-340 MHz operation)
- Transfers one long every 4 clocks (extremely fast)
- Cannot tolerate interruption or timing slip

**I/O Pattern:**
- **Direct hardware:** PSRAM chip interface (pins 40-57: data bus, clock, chip select)
- **Coordination:** 8 × 3-long mailboxes (one per COG)

**Work Characteristics:**
- Continuous polling of all 8 mailbox sets
- Executes DMA transfers when mailbox[2] becomes non-zero
- Bidirectional: Hub ↔ PSRAM transfers

**Mailbox Interface:**
```
long[mailbox_ptr][0] = Hub RAM address
long[mailbox_ptr][1] = PSRAM address
long[mailbox_ptr][2] = transfer count (negative = write, positive = read, 0 = done)
```

**Performance:**
- Transfer rate: 1 long per 4 clocks @ 250 MHz = 62.5 million longs/second
- Theoretical bandwidth: 250 MB/s
- Practical: ~200 MB/s (accounting for command overhead)

**COG Requirement:** **ABSOLUTELY REQUIRED**
- Hardware timing cannot be managed by Spin2
- Multiple clients (HDMI streamer, graphics operations) depend on it
- Real-time video output depends on predictable transfer timing

---

### COG 2: HDMI Video Streamer **[REQUIRED]**

**File:** `isp_hdmi_640x480_24bpp.spin2`

**Timing Criticality:** **HARD REAL-TIME**
- **60 Hz video refresh** - must output exactly 525 lines per frame, 800 pixels per line
- Pixel clock: 25.175 MHz (P2 250 MHz ÷ 10)
- Horizontal timing: 640 visible + 16 front + 96 sync + 48 back = 800 total pixels
- Vertical timing: 480 visible + 10 front + 2 sync + 33 back = 525 total lines
- **Frame time: 16.67ms** (cannot slip or video will tear/flicker)

**I/O Pattern:**
- **Direct hardware:** P2 Streamer → HDMI pins (pins 0-7)
- **Memory access:** Issues PSRAM read commands via mailbox for each scanline
- **Hardware-assisted:** P2's built-in streamer handles pixel output timing

**Work Characteristics:**
```pasm2
.field
  ; 33 back porch lines
  ; 480 visible lines - for each:
    ; Output sync pulse (96 pixels)
    ; Output back porch (48 pixels)
    ; Issue PSRAM read command for 640 pixels
    ; Stream pixels via P2 streamer
    ; Output front porch (16 pixels)
  ; 10 front porch lines
  ; 2 sync lines
```

**Performance:**
- Reads 640 longs per scanline from PSRAM
- 480 scanlines per frame
- Total: 307,200 longs per frame = 1,228,800 bytes
- Transfer time per scanline: ~10µs (640 longs @ 62.5 Mlong/s)
- Scanline time: 31.77µs (800 pixels @ 25.175 MHz)
- **PSRAM bandwidth usage: 31% per scanline**

**COG Requirement:** **ABSOLUTELY REQUIRED**
- 60Hz timing cannot be maintained from Spin2
- P2 Streamer must run from dedicated COG
- Video tearing/artifacts if timing slips

---

### COG 3: Graphics PASM Driver **[UNUSED - CAN ELIMINATE]**

**File:** `isp_psram_graphics.spin2` (GraphicsEntry)

**Status:** **COMPLETELY UNUSED**

**Analysis:**
The Graphics COG implements anti-aliased drawing primitives:
- `smooth_pixel` - anti-aliased pixel rendering
- `smooth_line` - anti-aliased line drawing

**Problem:** None of these methods are called by the actual application!

**What's Actually Used:**
- `FillRect()` - writes directly to PSRAM via mailbox (Spin2)
- `DrawHLine()` / `DrawVLine()` - write directly to PSRAM (Spin2)
- `DrawSensorGrid()` - calls line methods (Spin2)
- `FillSensorCell()` - calls FillRect() (Spin2)
- `DrawChar()` - calls FillRect() for each pixel (Spin2)

**Evidence:** No code calls `SmoothPixel()` or `SmoothLine()` methods.

**COG Requirement:** **NONE - ELIMINATE THIS COG**

**Savings:** **1 COG freed immediately!**

---

### COG 4: HDMI Display Manager Loop **[COORDINATION - MERGEABLE]**

**File:** `isp_hdmi_display_engine.spin2` (display_loop)

**Timing Criticality:** **NOT TIME-CRITICAL**
- Event-driven: waits for frames from FIFO
- No real-time constraints
- Processing happens between frame arrivals

**I/O Pattern:**
- **Zero direct I/O** - all operations via method calls
- Reads from HDMI FIFO (shared memory with locks)
- Calls graphics methods (which use PSRAM mailbox)

**Work Characteristics:**
```spin2
repeat
  framePtr := fifo.dequeue(FIFO_HDMI)  // Blocks waiting for data

  // Process 64 sensor cells
  repeat row from 0 to 7
    repeat col from 0 to 7
      sensorVal := WORD[framePtr][sensorIdx]
      cellColor := field_to_color(sensorVal)
      gfx.FillSensorCell(row, col, ..., cellColor)  // Calls FillRect()

  fifo.releaseFrame(framePtr)
```

**Performance per Frame:**
| Operation | Time | Notes |
|-----------|------|-------|
| FIFO dequeue | <0.1ms | Blocking, immediate when available |
| Color calculations (64×) | ~0.5ms | Simple palette lookup |
| FillRect calls (64×) | ~5ms | PSRAM writes for 64 cells |
| Frame release | <0.1ms | Lock + pointer update |
| **Total per frame** | **~5.6ms** | **Maximum ~180 fps** |

**COG Requirement:** **NOT REQUIRED**
- No real-time constraints
- Could run in Main COG polling loop
- Or keep as dedicated COG for parallelism

**Decision:** Depends on performance goals (see analysis below)

---

## Graphics Operation Performance

### FillRect() Analysis

**Implementation:**
```spin2
PUB FillRect(x1, y1, x2, y2, color)
  longfill(@row[x1], color, x2-x1+1)  // Fill line buffer

  repeat y from y1 to y2
    long[psram_ptr][0] := @row[x1]    // Hub source
    long[psram_ptr][1] := y * 640 + x1 // PSRAM dest
    long[psram_ptr][2] := -(x2-x1+1)   // Write count
    repeat while long[psram_ptr][2]    // Wait for PSRAM driver
```

**Timing for 30×30 pixel cell:**
- Line fill: ~30 longs = <0.5µs (Hub RAM)
- PSRAM writes: 30 longs per line × 30 lines = 900 longs total
- Transfer time: 900 longs @ 62.5 Mlong/s = 14.4µs
- Loop overhead: ~16µs
- **Total per cell: ~30µs**

**64 cells per frame:**
- 64 × 30µs = 1.92ms for all cell fills
- Plus color calculations: 0.5ms
- **Total frame processing: ~2.4ms**

**This is FAST!** Much faster than the 5.6ms I estimated above. The bottleneck is actually the loop overhead and FIFO operations, not PSRAM writes.

---

## Performance Analysis

### HDMI Frame Rate Calculation

**Display Refresh:** 60 Hz (fixed by video timing)

**Frame Processing Time:** ~2.4ms per sensor frame

**Maximum Input Rate:**
- If HDMI manager runs in dedicated COG: limited by 60 Hz display = **60 fps**
- PSRAM can handle updates faster, but display only refreshes 60 times/sec

**Recommended Decimation:**
- Sensor rate: 2000 fps
- HDMI target: 60 fps (display refresh limit)
- **Optimal decimation: 1:33** (2000 ÷ 33 ≈ 60 fps)

### Parallelism Considerations

**If HDMI Manager in Dedicated COG (Current):**
```
Sensor COG: Produces frames continuously (0.5ms each @ 2000 fps)
     ↓
Main COG: Decimates and routes (minimal overhead)
     ↓ (every 33rd frame)
HDMI COG: Processes frame (2.4ms) + waits for next (13.3ms idle)
```
- **Advantage:** Sensor never blocked by HDMI processing
- **Disadvantage:** Uses dedicated COG for mostly-idle work

**If HDMI Manager in Main COG:**
```
Main COG:
  - Decimates frames (polling sensor FIFO)
  - Every 33rd: Process HDMI frame (2.4ms)
  - During 2.4ms: Sensor produces 5 frames → accumulate in sensor FIFO
  - Main catches up between HDMI frames
```
- **Advantage:** Frees COG 4
- **Disadvantage:** Sensor FIFO must absorb burst accumulation
- **Risk:** If FIFO fills, frames dropped

**Analysis:** With FIFO depth of 16 frames and 2.4ms processing gaps, this should work fine.

---

## COG Consolidation Recommendations

### Immediate Actions

#### 1. Eliminate Graphics COG (COG 3) **[HIGH PRIORITY]**

**Action:** Remove `coginit(@GraphicsEntry)` call from graphics driver

**Code Change:**
```spin2
' In isp_psram_graphics.spin2 start() method:
' REMOVE this line:
'   cog := 1+coginit(COGEXEC_NEW, @GraphicsEntry, @command)

' Graphics COG is unused - all operations go directly to PSRAM
```

**Savings:** **1 COG freed immediately**

**Risk:** None - COG is not used anywhere

**Testing:** Verify no behavioral change (should be identical)

---

#### 2. Move HDMI Manager to Main COG **[OPTIONAL]**

**Action:** Move `display_loop()` logic into main polling loop

**Pseudo-code:**
```spin2
PUB main()
  ' Initialize all subsystems...

  ' Main becomes decimator + HDMI manager
  repeat
    ' Check sensor FIFO
    framePtr := fifo.dequeue(FIFO_SENSOR)  // Non-blocking poll
    if framePtr
      route_to_displays(framePtr)          // Decimation logic

    ' Check HDMI FIFO
    hdmiPtr := fifo.dequeue(FIFO_HDMI)     // Non-blocking poll
    if hdmiPtr
      process_hdmi_frame(hdmiPtr)          // Render to display

    ' Check OLED FIFO
    oledPtr := fifo.dequeue(FIFO_OLED)     // Non-blocking poll
    if oledPtr
      process_oled_frame(oledPtr)          // Render to display
```

**Savings:** **1 COG freed** (COG 4)

**Risk:** Main COG blocked during frame processing (~2.4ms bursts)

**Mitigation:** FIFO depth (16 frames) absorbs accumulation

**Decision:** **Recommend implementing** - benefits outweigh risks

---

### Resulting COG Usage

**After Consolidation:**
- **COG 0**: Main (Decimator + HDMI Manager + OLED Manager)
- **COG 1**: PSRAM Driver (required - hardware interface)
- **COG 2**: HDMI Video Streamer (required - 60Hz timing)
- **COG 3**: ~~Graphics PASM~~ **ELIMINATED**
- **COG 4**: ~~HDMI Display Loop~~ **MOVED TO MAIN**
- **COG 5**: OLED SPI Streaming (required for performance)
- **COG 6**: ~~OLED Display Loop~~ **MOVED TO MAIN**
- **COG 7**: ~~Frame Processor~~ **MOVED TO MAIN**

**Total COGs Used: 3** (Main + PSRAM + HDMI Streamer + OLED Streaming)

**COGs Available: 5** (for sensor + future expansion)

---

## Future Optimization Opportunities

### Level 1: Current Implementation
- Direct PSRAM writes via mailbox
- Spin2 drawing routines
- **Performance:** ~2.4ms per frame rendering

### Level 2: PASM Drawing Routines (Future)
- Implement FillRect in PASM (if needed for speed)
- Would reduce per-cell time from 30µs to ~15µs
- **Total frame time:** ~1.2ms (vs 2.4ms)
- **Benefit:** 2× faster rendering
- **When:** Only if 60 fps proves insufficient

### Level 3: P2 Streamer for Graphics (Advanced)
- Use streamer to transfer pixel data PSRAM
- Similar to OLED Level 2 optimization
- Zero-copy block transfers
- **Complexity:** High (requires careful setup)

---

## Hardware Dependencies

### PSRAM Interface
- **Pins 40-57:** 16-bit data bus + control signals
- **P2 Edge module:** 32MB PSRAM (P2-EC32MB configuration)
- **Timing:** Tuned for 250-340 MHz operation

### HDMI Interface
- **Pins 0-7:** HDMI output (bit-DAC mode)
- **Configuration:** 75-ohm 1-bit DACs for TMDS signaling
- **Timing:** 25.175 MHz pixel clock (P2 250 MHz ÷ 10)

### Display Requirements
- **Resolution:** 640×480 @ 60Hz (VESA standard)
- **Format:** RRGGBBAA (32-bit per pixel in PSRAM)
- **Compatibility:** Any HDMI display supporting 640×480 VGA timing

---

## Memory Usage

### PSRAM Framebuffer
- **Size:** 640 × 480 × 4 bytes = 1,228,800 bytes (~1.2 MB)
- **Available:** 32 MB total (2% usage for single frame)
- **Potential:** Could support multiple framebuffers, back-buffering, etc.

### Hub RAM
- **Pixel line buffers:** 2 × 640 × 4 = 5,120 bytes (alternating scanlines)
- **Graphics row buffer:** 640 × 4 = 2,560 bytes (for FillRect operations)
- **Total:** ~8 KB for HDMI subsystem

---

## Testing & Validation

### Performance Metrics

**Frame Rate Measurement:**
```spin2
frame_count++
if frame_count // 60 == 0
  elapsed_ms := getms() - start_ms
  fps := 60_000 / elapsed_ms
  debug("HDMI FPS: ", udec(fps))
```

**FIFO Depth Monitoring:**
```spin2
depth := fifo.getQueueDepth(FIFO_HDMI)
```
- Should remain 0-2 frames at steady state
- Climbing depth indicates over-production

### Visual Validation

**Test Patterns:**
1. Grid rendering (verify line drawing)
2. Color palette test (all 8 colors)
3. Text rendering (labels, statistics)
4. Sensor grid (64 cells with test data)

**Debug Output:**
```
DEBUG: HDMI frame=N cells=[TL,TR,BL,BR] depth=D
```

---

## Migration Path

### Phase 1: Eliminate Graphics COG (IMMEDIATE)
1. Remove `coginit(@GraphicsEntry)` from graphics driver
2. Verify all operations still work (they use PSRAM directly)
3. **Result: 1 COG freed** (COG 3)

### Phase 2: Consolidate Display Managers (NEXT)
1. Move HDMI display loop to main COG
2. Move OLED display loop to main COG
3. Move frame processor logic to main COG
4. Implement polling-based frame routing
5. **Result: 3 more COGs freed** (COG 4, 6, 7)

### Phase 3: Optimize if Needed (FUTURE)
1. Benchmark actual frame rates
2. If < 60 fps for HDMI, implement PASM drawing
3. Monitor FIFO depths under load
4. Adjust decimation ratios as needed

---

## Related Documents

- **OLED Architecture:** `DOCs/OLED-Driver-Architecture.md`
- **Hardware:** `DOCs/HDMI-Display-Hardware.md` (TBD)
- **Sensor Pipeline:** `DOCs/Sensor-Architecture.md` (TBD)
- **FIFO Manager:** `DOCs/FIFO-Architecture.md` (TBD)
- **System Architecture:** `DOCs/System-Architecture.md` (TBD)

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-04 | Claude + Stephen | Initial architecture specification |
