# Magnetic Imaging Tile - Performance Analysis

**Version:** 2.0
**Date:** 2025-12-26
**System Clock:** 250 MHz

---

## Executive Summary

This document analyzes the performance characteristics and limitations of the Magnetic Imaging Tile system. The system consists of three major data pipelines:

| Component | Theoretical Max | Current | Target | Status |
|-----------|-----------------|---------|--------|--------|
| Sensor Acquisition | 1,330 fps | **1,370 fps** | Max throughput | **>100% (optimized Dec 2025)** |
| HDMI Display | 60 fps | 60 fps | 60 fps | **At target** |
| OLED Display | 76 fps | ~55 fps | 60 fps | **Below target** |

**Key Finding #1 (RESOLVED):** After moving calibration to inline PASM (Dec 2025), the sensor now achieves **1,366-1,381 fps**, a **3.7x improvement** from the original ~375 fps. This exceeds the theoretical hardware maximum estimate.

**Key Finding #2:** The OLED display is the display bottleneck at ~55 fps, falling short of the 60 fps target by approximately 8%.

**Key Finding #3:** With sensor running at 1,370 fps, there is **massive headroom** for interpolated 16x16 or 32x32 displays, multi-frame averaging, or other advanced processing.

---

## System Architecture

### COG Allocation

| COG | Component | Function |
|-----|-----------|----------|
| 0 | Main (mag_tile_viewer) | Decimation loop, frame routing |
| 1 | Sensor (isp_tile_sensor) | 8x8 Hall sensor acquisition |
| 2 | HDMI Engine (isp_hdmi_display_engine) | FIFO consumer, PSRAM rendering |
| 3 | OLED Driver (isp_oled_single_cog) | FIFO consumer, SPI display |
| 4 | PSRAM Driver | External memory controller |
| 5 | HDMI Video | 640x480 @ 60Hz video generation |

### Data Flow

```
Sensor COG ──┬──> Sensor FIFO ──> Main COG (decimation) ──┬──> HDMI FIFO ──> HDMI Engine ──> PSRAM ──> HDMI Video
             │                                            │
             └── (375 fps raw)                            └──> OLED FIFO ──> OLED Driver ──> SPI ──> 128x128 Display
```

---

## Detailed Component Analysis

### 1. Sensor Acquisition (isp_tile_sensor.spin2)

#### Hardware Configuration
- **ADC:** AD7680 16-bit, SPI interface
- **SPI Clock:** 2.5 MHz (per AD7680 datasheet maximum)
- **Sensors:** 64 (8x8 grid across 4 quadrants)
- **SPI Frame:** 24 bits (4 leading zeros + 16 data + 4 trailing zeros)

#### Timing Analysis

**Per-Sensor SPI Transfer:**
```
SPI time = 24 bits / 2.5 MHz = 9.6 µs
```

**Pipelined Acquisition Strategy:**
The sensor driver uses a pipelined approach where counter advancement overlaps with SPI transfer:

| Sensor | Settle Time | SPI Time | Total | Notes |
|--------|-------------|----------|-------|-------|
| First (0) | 2.0 µs | 9.6 µs | 11.6 µs | Full settle required |
| 1-62 | 0.8 µs | 9.6 µs | 10.4 µs | Counter advances during previous SPI |
| Last (63) | 0.8 µs | 9.6 µs | 10.4 µs | No counter advance |

**Total Frame Time:**
```
Frame time = 11.6 µs + (63 × 10.4 µs) = 666 µs
Theoretical max = 1,502 fps
```

**Measured Performance:**
Due to Spin2 overhead (calibration, FIFO operations, loop control):
```
Actual frame rate ≈ 375 fps (2.67 ms per frame)
Utilization = 666 µs / 2670 µs = 25%
```

#### No Artificial Delays - Running at Maximum Speed

**Important:** The sensor acquisition code contains **NO artificial frame-rate limiting delays**. The sensor runs flat out, as fast as possible. The only waits in the acquisition path are:

| Wait Type | Time | Purpose | Avoidable? |
|-----------|------|---------|------------|
| `SENSOR_SETTLE_DELAY` | 2 µs | Analog settling (first sensor) | No - hardware |
| `RESIDUAL_SETTLE_DELAY` | 0.8 µs | Residual settle (pipelined) | No - hardware |
| `COUNTER_SETUP_DELAY` | 0.25 µs | Counter timing | No - hardware |
| `waitse1` | ~9.6 µs | SPI transfer complete | No - hardware |
| `waitus(10)` | 10 µs | **Only if FIFO empty** | Backpressure |

The 10 µs backpressure wait only triggers when `fifo.getNextFrame()` returns 0 (no free frames), which shouldn't happen under normal operation with 32 frames in the pool.

#### Spin2 Overhead Sources - Detailed Breakdown

The gap between theoretical (1,330 fps) and actual (375 fps) performance represents a **3.5x slowdown**. Here's the detailed breakdown:

| Operation | Time (µs) | Notes |
|-----------|-----------|-------|
| **PASM sensor acquisition** | 750 | Hardware-limited, unavoidable |
| **apply_calibration()** | ~800 | 64 iterations × ~12.5 µs each |
| **fifo.getNextFrame()** | ~80 | Lock spin, bounds checks, pointer ops |
| **fifo.commitFrame()** | ~100 | Lock, validation, COGATN notify |
| **stack_check.checkStack()** | ~20 | Memory read + compare |
| **sensor_loop() overhead** | ~30 | Case statement, method calls |
| **Total Producer Time** | **~1,780 µs** | = **562 fps theoretical** |

But the **main decimation loop** (COG 0) is also a consumer that must keep pace:

| Operation | Time (µs) | Notes |
|-----------|-----------|-------|
| **fifo.dequeue(SENSOR)** | ~100 | Lock acquisition, validation |
| **WORDMOVE × 2** | ~50 | Copy to HDMI + OLED buffers |
| **fifo.getNextFrame() × 2** | ~160 | Two new frames for displays |
| **fifo.commitFrame() × 2** | ~200 | Commit to both FIFOs |
| **fifo.releaseFrame() × 3** | ~120 | Release original + any failures |
| **Debug output (every 30)** | ~30 | Amortized debug() overhead |
| **Total Consumer Time** | **~660 µs** | = **1,515 fps capable** |

**The bottleneck is the PRODUCER (sensor COG), not the consumer.**

#### Why apply_calibration() Is So Expensive

```spin2
repeat i from 0 to 63
  raw := WORD[framePtr][i]           ' Memory read
  calibrated := raw - baseline[i] + SENSOR_MID  ' Two reads + math
  calibrated := 0 #> calibrated <# 65535        ' Clamp operation
  WORD[framePtr][i] := calibrated    ' Memory write
```

Each iteration involves:
- 2 HUB memory reads (framePtr[i], baseline[i])
- 1 HUB memory write
- Subtraction, addition, clamp operators

At ~12.5 µs per iteration × 64 = **800 µs** — more than the PASM sensor acquisition itself!

#### Path to Higher Sensor Frame Rates

To approach the theoretical 1,330 fps limit:

| Optimization | Potential Gain | Effort |
|--------------|----------------|--------|
| **Integrate calibration into PASM** | **+800 µs → ~980 fps** | **Low (5 instructions)** |
| Inline FIFO operations | +200 µs → ~700 fps | Medium |
| Lock-free FIFO design | +100 µs → ~600 fps | High |
| Remove stack_check in production | +20 µs | Trivial |

#### Key Insight: Calibration During Write (Not After)

The current architecture already performs a table lookup for each sensor to map counter index → buffer position. The calibration can be applied **at the same time** with minimal overhead:

**Current (inefficient):**
```
PASM:   Read sensor → lookup position → write RAW value        (750 µs)
Spin2:  Loop 64× → read → calibrate → write back               (800 µs)
Total:  1,550 µs per frame = 645 fps max
```

**Optimized (inline calibration):**
```
PASM:   Read sensor → lookup position → lookup baseline →
        apply calibration → write CALIBRATED value             (800 µs)
Spin2:  Nothing!                                               (0 µs)
Total:  800 µs per frame = 1,250 fps max
```

The additional PASM instructions per sensor:
```pasm
rdword  baseline_val, baseline_ptr   ' Lookup baseline[i]
sub     sensor_val, baseline_val     ' raw - baseline
add     sensor_val, ##SENSOR_MID     ' + SENSOR_MID
fges    sensor_val, #0               ' clamp min to 0
fle     sensor_val, ##65535          ' clamp max to 65535
```

**Cost:** ~50 µs additional (5 instructions × 64 sensors × ~0.16 µs/instruction)
**Savings:** ~800 µs eliminated Spin2 loop
**Net gain:** ~750 µs per frame

#### Revised Performance Projection (With Inline Calibration)

| Operation | Before (µs) | After (µs) |
|-----------|-------------|------------|
| PASM sensor acquisition | 750 | 800 (+calibration) |
| apply_calibration() Spin2 | 800 | **0** (eliminated) |
| FIFO operations | 180 | 180 |
| Other overhead | 50 | 50 |
| **Total (projected)** | **1,780** | **1,030** |
| **Frame Rate (projected)** | **562 fps** | **970 fps** |

#### ACTUAL MEASURED RESULTS (Dec 2025)

After implementing inline PASM calibration:

```
SENSOR FPS: 1,381 (1,000 frames in 724 ms)
SENSOR FPS: 1,366 (1,000 frames in 732 ms)
```

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Measured Frame Rate** | ~375 fps | **1,366-1,381 fps** | **3.7x faster** |
| **Frame Time** | ~2,670 µs | **724-732 µs** | **3.6x faster** |
| **Theoretical Max** | 1,330 fps | 1,330 fps | - |
| **Efficiency** | 28% | **>100%** | Exceeds prediction! |

**The optimization exceeded expectations**, achieving frame rates slightly above the theoretical hardware maximum of 1,330 fps. This suggests the original 750 µs PASM estimate was conservative.

**Conclusion:** Integrating calibration into the PASM acquisition loop was a low-effort, high-impact optimization that increased sensor throughput by **3.7x**, from ~375 fps to ~1,370 fps.

---

### 2. HDMI Display (isp_hdmi_display_engine.spin2 + isp_hdmi_640x480_24bpp.spin2)

#### Video Hardware
- **Resolution:** 640 x 480 pixels
- **Color Depth:** 32-bit (RRGGBBAA)
- **Frame Rate:** 60 Hz (fixed, VGA standard timing)
- **Pixel Clock:** 25.175 MHz (250 MHz / 10)

#### Timing (Hardware)
```
Horizontal: 640 visible + 16 front + 96 sync + 48 back = 800 pixels
Vertical:   480 visible + 10 front + 2 sync + 33 back = 525 lines
Frame time = 800 × 525 / 25.175 MHz = 16.68 ms
Frame rate = 59.94 fps
```

**Video output is locked at 60 fps - this is not a limitation.**

#### Content Rendering Performance

The HDMI Engine renders 64 sensor cells (8x8 grid) per frame:

**Per-Cell Rendering:**
```
Cell size: 30x30 pixels (with 3-pixel gap)
FillSensorCell() → FillRect() → PSRAM writes
```

**FillRect Performance:**
```
Per row: longfill (HUB) + PSRAM write + wait
Row write time: ~8 µs (estimated)
25 rows per cell × 8 µs = 200 µs per cell
64 cells × 200 µs = 12.8 ms per frame
```

**Additional Overhead:**
- CalculateFrameStats(): 64 iterations, ~0.5 ms
- DrawDynamicStats(): 4 FillRect + 4 FormatNumber + 4 DrawText, ~2 ms
- FIFO dequeue: ~0.1 ms

**Total HDMI Frame Time:** ~15 ms = **66 fps capable**

#### Decimation Configuration
```spin2
DEFAULT_HDMI_DECIMATION = 6    ' 375/6 = 62.5 fps
```

**Conclusion:** HDMI content updates at 62.5 fps, slightly exceeding 60 fps requirement. **HDMI meets target.**

---

### 3. OLED Display (isp_oled_single_cog.spin2)

#### Hardware Configuration
- **Controller:** SSD1351
- **Resolution:** 128 x 128 pixels
- **Color Depth:** 16-bit RGB565
- **SPI Clock:** 20 MHz (datasheet maximum)
- **Interface:** Smart Pin SYNC_TX + P_PULSE

#### Theoretical SPI Performance

**Full-Screen Transfer:**
```
Total pixels = 128 × 128 = 16,384
Bytes per pixel = 2 (RGB565)
Total bytes = 32,768
SPI time = 32,768 bytes × 8 bits / 20 MHz = 13.1 ms
Theoretical max = 76.3 fps
```

#### Actual Display Method: `display_frame()`

The current implementation uses **per-cell rendering** with individual window commands:

**Per-Cell Breakdown:**
```
1. set_window() - 6 SPI commands (CS, DC toggles + data)
   - CMD_SET_COLUMN + 2 bytes = ~1.6 µs
   - CMD_SET_ROW + 2 bytes = ~1.6 µs
   - CMD_WRITE_RAM = ~0.5 µs
   - Total setup: ~4 µs with CS/DC transitions: ~10 µs

2. Fill 16×16 = 256 pixels × 2 bytes = 512 bytes
   - SPI time = 512 × 8 / 20 MHz = 204.8 µs

3. CS deassert wait: ~2 µs

Per-cell total: ~217 µs
```

**Frame Rendering:**
```
64 cells × 217 µs = 13.9 ms
Additional overhead:
  - transform_coordinates(): 64 calls × ~5 µs = 0.32 ms
  - value_to_color(): 64 calls × ~10 µs = 0.64 ms
  - FIFO dequeue: ~0.1 ms
  - stuck_pixel check: 64 × ~1 µs = 0.06 ms

Total: ~15 ms per frame = 66 fps
```

#### Measured Performance

```spin2
DEFAULT_OLED_DECIMATION = 7    ' 375/7 = 53.6 fps
' OLED max ~55 fps (measured)
```

The actual measured rate of **~55 fps** is below the calculated 66 fps due to:
1. Smart Pin polling waits in `spi_write_fast()`
2. Spin2 method call overhead (deep call stack)
3. FIFO lock contention
4. Event processing overhead

**Conclusion:** OLED achieves ~55 fps, **8% below the 60 fps target.**

---

## Bottleneck Analysis

### Primary Bottleneck: OLED Per-Cell Window Setup

The single largest inefficiency is the per-cell `set_window()` calls:

```
64 cells × 10 µs window setup = 640 µs wasted
```

This represents 4.6% of frame time, but the overhead compounds with CS/DC transitions.

### Alternative: `display_frame_fast()` (Currently Disabled)

The codebase contains an optimized method using full-screen streaming:

```spin2
PUB display_frame_fast(framePtr)
  ' Phase 1: Pre-render to pixel buffer (PASM)
  render_to_pixel_buffer(framePtr)

  ' Phase 2: Single set_window + stream entire buffer
  set_window(0, 0, WIDTH - 1, HEIGHT - 1)
  stream_pixel_buffer()  ' PASM event-driven
```

**Expected Performance:**
```
Window setup: 1 × 10 µs = 10 µs (vs 640 µs)
PASM render: ~2 ms
SPI stream: 13.1 ms
Total: ~15.1 ms = 66 fps
```

However, comments indicate offset issues with this method:
```spin2
' Display frame using cell-by-cell method (display_frame_fast has offset issues)
display_frame(framePtr)
```

### Secondary Bottleneck: SPI Clock Limit

The SSD1351 datasheet specifies 20 MHz maximum SPI. This is a hard limit that cannot be exceeded.

---

## Optimization Opportunities

### Priority 1: Fix `display_frame_fast()` Offset Issues

**Impact:** ~10% performance improvement
**Effort:** Medium

The ROW_OFFSET (-32) and COLUMN_OFFSET (0) may need adjustment for full-screen mode.

### Priority 2: Reduce Color Conversion Overhead

**Current:** Per-pixel Spin2 calculation
**Proposed:** Pre-computed 4096-entry LUT already exists; ensure it's used in display_loop

### Priority 3: Reduce Display Resolution (Trade-off)

**Option:** Use 96×96 center region (6×6 cells)
**Impact:** 36 cells instead of 64 = 44% reduction in pixels
**Trade-off:** Reduced visual fidelity

### Priority 4: Dual-Buffer Strategy

Render next frame while current frame transmits, hiding render time entirely.

---

## Performance Summary Table

| Metric | Sensor | HDMI | OLED |
|--------|--------|------|------|
| **Hardware Theoretical Max** | 1,330 fps | 60 fps | 76 fps |
| **Before Optimization** | 375 fps | 60 fps | 55 fps |
| **After PASM Calibration (Dec 2025)** | **1,370 fps** | 60 fps | 55 fps |
| **Target** | Max | 60 fps | 60 fps |
| **Efficiency** | **>100%** | 100% | 72% |
| **Status** | **RESOLVED** | **Met** | **8% short** |

### What's Limiting Each Component

| Component | Primary Bottleneck | Root Cause | Status |
|-----------|-------------------|------------|--------|
| Sensor | ~~`apply_calibration()`~~ | ~~64× Spin2 loop (800 µs)~~ | **FIXED** - inline PASM |
| HDMI | Hardware timing | VGA standard = 60 Hz fixed | At target |
| OLED | SPI clock limit | SSD1351 max = 20 MHz (13.1 ms) | 8% short |

### Available Headroom (After Optimization)

```
Sensor measured:        1,370 fps
Display requirement:       60 fps
                        --------
Available headroom:     1,310 fps (22x more than needed!)

Frames per display update: 1,370 / 60 = 22.8 frames

This headroom enables:
  - 16x16 bilinear interpolation: trivial (~12 µs)
  - 32x32 bicubic interpolation: trivial (~192 µs)
  - Multi-frame averaging: 22 frames per display update
  - Advanced filtering/smoothing
```

---

## Recommendations

1. **Investigate `display_frame_fast()` offset issue** - This is the most promising path to 60 fps OLED.

2. **Profile actual bottleneck** - Add timing instrumentation to confirm whether SPI transfer or Spin2 logic is the limiter.

3. **Consider PASM pixel streaming** - The `stream_pixel_buffer()` PASM routine should be faster than Spin2 loops.

4. **Accept 55 fps for OLED** - The 8% shortfall is barely perceptible; 55 fps is adequate for educational demonstrations.

5. **Move calibration to PASM** - This would recover ~800 µs per frame, enabling higher sensor rates.

---

## Path to 16x16 and 32x32 Interpolated Displays

### The Vision

The native 8x8 sensor grid produces a blocky visualization. By mathematically interpolating between sensor readings, we can create smoother 16x16 or 32x32 visualizations that better represent the continuous nature of magnetic fields.

### Time Budget Analysis

At 60 fps display rate, we have **16,667 µs per display frame**. Current utilization:

| Component | Current 8x8 | Available for More |
|-----------|-------------|-------------------|
| Sensor acquisition (PASM) | 750 µs | Fixed |
| Calibration (Spin2) | 800 µs | Could move to PASM |
| FIFO operations | 380 µs | Could optimize |
| **Total sensor time** | **1,930 µs** | **~11.6%** of budget |
| HDMI rendering (8x8) | 12,800 µs | 77% of budget |
| OLED rendering (8x8) | 13,100 µs | 79% of budget |

**Key insight:** At 60 fps, we use only ~12% of our time budget for sensor work. The remaining 88% could support interpolation calculations.

### Interpolation Methods

#### Method 1: Bilinear Interpolation (Recommended for 16x16)

Bilinear interpolation uses weighted averages of the 4 nearest neighbors:

```
P(x,y) = (1-dx)(1-dy)·P00 + dx(1-dy)·P10 + (1-dx)dy·P01 + dx·dy·P11

Where:
  P00, P10, P01, P11 = four surrounding sensor values
  dx, dy = fractional position within cell (0.0 to 1.0)
```

**Computational cost per interpolated pixel:**
- 4 multiplications
- 3 additions
- ~20 P2 clock cycles in PASM = 0.08 µs

**For 16x16 output (256 values from 64 sensors):**
- Only interior 6x6 = 36 cells need interpolation (edges use nearest-neighbor)
- Each cell produces 4 interpolated values (2x2 subdivision)
- 36 cells × 4 values = 144 interpolations
- 144 × 0.08 µs = **11.5 µs** (trivial!)

**For 32x32 output (1,024 values from 64 sensors):**
- 36 interior cells × 16 values (4x4 subdivision) = 576 interpolations
- Edge handling: 28 edge cells × average 8 values = 224 interpolations
- Total: 800 interpolations × 0.08 µs = **64 µs**

#### Method 2: Bicubic Interpolation (Smoother, for 32x32)

Bicubic uses 16 neighbors (4x4 grid) for smoother curves:

```
P(x,y) = Σ Σ aij · Bi(dx) · Bj(dy)  for i,j = -1 to 2

Where B() are cubic basis functions
```

**Computational cost per pixel:**
- 16 multiplications + 12 additions
- ~60 P2 clock cycles in PASM = 0.24 µs

**For 32x32 output:**
- ~800 interpolations × 0.24 µs = **192 µs**

Still negligible compared to display rendering time!

### Display Rendering Impact

The larger consideration is **display rendering time**, not interpolation calculation:

#### HDMI Impact

| Resolution | Cells | Pixels/Cell | PSRAM Writes | Est. Time |
|------------|-------|-------------|--------------|-----------|
| 8x8 | 64 | 900 (30x30) | 64 cells | 12.8 ms |
| 16x16 | 256 | 225 (15x15) | 256 cells | 12.8 ms (same!) |
| 32x32 | 1,024 | 56 (7.5x7.5) | 1,024 cells | 12.8 ms (same!) |

**Key insight:** Total pixel count on HDMI is constant (264x264 grid area). Finer subdivision doesn't change PSRAM write volume — it changes **FillRect call count** and overhead.

Optimization: Use **scanline rendering** instead of per-cell FillRect:
```
For each row of 264 pixels:
  For each interpolated cell in row:
    Calculate color from interpolated value
  Write entire row to PSRAM in one operation
```

This reduces PSRAM operations from 64 cells × 30 rows = 1,920 writes to just 264 row writes.

#### OLED Impact

| Resolution | Interpolated Grid | Display Mapping | Notes |
|------------|------------------|-----------------|-------|
| 8x8 → 8x8 | 64 values | 16x16 pixels/cell | Current |
| 8x8 → 16x16 | 256 values | 8x8 pixels/cell | Smoother |
| 8x8 → 32x32 | 1,024 values | 4x4 pixels/cell | Very smooth |

OLED is 128x128 pixels. For 32x32 interpolated grid:
- Each interpolated cell = 4x4 pixels
- Could use `display_frame_fast()` with pixel buffer pre-filled

### Implementation Strategy

#### Phase 1: 16x16 Bilinear (Low Risk)

1. Add `interpolate_16x16()` function using inline PASM
2. Expand frame buffer from 64 WORDs to 256 WORDs
3. Modify HDMI engine to render 16x16 grid with 15x15 pixel cells
4. Modify OLED engine to render 16x16 grid with 8x8 pixel cells

**Expected overhead:** <100 µs per frame = negligible

#### Phase 2: 32x32 Bicubic (Medium Risk)

1. Add `interpolate_32x32()` function using bicubic in PASM
2. Expand frame buffer to 1,024 WORDs
3. Implement scanline HDMI rendering for efficiency
4. OLED uses 4x4 pixel cells (native 128/32 = 4)

**Expected overhead:** <250 µs per frame = still negligible

### Mathematical Verification

**Can we achieve 60 fps with 32x32 interpolated display?**

```
Time budget per frame: 16,667 µs (at 60 fps)

Sensor acquisition:        750 µs
Calibration (PASM):        200 µs  (optimized from 800)
Interpolation (32x32):     192 µs
FIFO operations:           300 µs
HDMI rendering:         12,800 µs
OLED rendering:         13,100 µs  (SPI-limited)
                        --------
Total (parallel COGs):  ~14,000 µs (OLED is longest)

Margin: 16,667 - 14,000 = 2,667 µs (16% headroom)
```

**Answer: YES, 32x32 interpolation at 60 fps is theoretically achievable.**

The limiting factor remains the **OLED SPI transfer time** (13.1 ms minimum), not computation.

### Summary: Interpolation Feasibility

| Display Mode | Interpolation Time | Display Time | Feasible at 60 fps? |
|--------------|-------------------|--------------|---------------------|
| 8x8 (current) | 0 µs | ~13 ms | Yes (current) |
| 16x16 bilinear | ~12 µs | ~13 ms | **Yes** |
| 32x32 bilinear | ~64 µs | ~13 ms | **Yes** |
| 32x32 bicubic | ~192 µs | ~13 ms | **Yes** |

**The computational overhead for interpolation is negligible. The real work is in the display drivers, which are already limited by hardware (OLED SPI, HDMI PSRAM bandwidth).**

### Pedagogical Benefits of Higher Resolution

1. **Smoother field visualization** - Continuous gradients instead of blocky cells
2. **Better field line representation** - Subtle field variations become visible
3. **Enhanced pole detection** - Fine structure of field near magnet poles
4. **More engaging display** - Higher resolution looks more "scientific"
5. **Interpolation as teaching topic** - Demonstrate signal processing concepts

---

## Appendix: Key Timing Constants

```spin2
' Sensor (isp_tile_sensor.spin2)
SPI_CLOCK_FREQ = 2_500_000        ' 2.5 MHz
SENSOR_SETTLE_DELAY = 500         ' 2 µs @ 250 MHz
RESIDUAL_SETTLE_DELAY = 200       ' 0.8 µs

' OLED (isp_oled_single_cog.spin2)
SPI_FREQ = 20_000_000             ' 20 MHz

' HDMI (isp_hdmi_640x480_24bpp.spin2)
xpix = 640
ypix = 480
h_total = 800
v_total = 525
' Pixel clock = 250 MHz / 10 = 25 MHz
```
