# Text Display Implementation Plan
**Magnetic Imaging Tile - HDMI Text Overlay System**

## Document Version
- **Version:** 1.0
- **Date:** 2025-12-26
- **Status:** Planning Document

---

## Executive Summary

This document outlines the plan to implement text display on the HDMI output, rendering static and dynamic labels outside the 8x8 sensor grid region. The infrastructure already exists - this is primarily about enabling and testing the commented-out code.

### Current State

**GOOD NEWS:** Most of the infrastructure is already in place:

1. **Font Library** (`isp_hub75_fonts.spin2`) - 6045 lines, 5 fonts:
   - `TEXT_FONT_5x7` - Basic 5x7 monochrome
   - `TEXT_FONT_8x8A` - 8x8 variant A (7x7 visible)
   - `TEXT_FONT_8x8B` - 8x8 variant B
   - `TEXT_FONT_5x7_DITH` - 5x7 anti-aliased (2-bit per pixel)
   - `TEXT_FONT_5x7_DITH_DCNDR` - 5x7 anti-aliased with descenders (default)

2. **Graphics API** (`isp_psram_graphics.spin2`) - Text methods exist:
   - `SetFont(font_id)` - Select active font
   - `DrawChar(x, y, ch, color)` - Single character
   - `DrawText(x, y, pString, color)` - Draw text string
   - `DrawTextCentered(centerX, y, pString, color)` - Centered text

3. **Display Engine** (`isp_hdmi_display_engine.spin2`) - Has disabled text code:
   - `DrawStaticLabels()` - Private method with full implementation
   - Currently DISABLED at line 179: `'DrawStaticLabels()`

---

## What Was Planned to be Displayed (Recovered Code)

From `isp_hdmi_display_engine.spin2` lines 217-246:

```
Display Layout (640x480):
+------------------------------------------------------------------+
|                                                                  |
|     "Magnetic Imaging Tile Display" (centered, white, y=10)      |
|                                                                  |
|        0   1   2   3   4   5   6   7  (column labels, yellow)    |
|      +---+---+---+---+---+---+---+---+     Min: 1200  (green)    |
|    0 |   |   |   |   |   |   |   |   |     Max: 3000  (red)      |
|    1 |   |   |   |   |   |   |   |   |     Avg: 2100  (cyan)     |
|    2 |   |   |   |   |   |   |   |   |                           |
|    3 |   | 8x8 SENSOR GRID  |   |   |     Frame: 0/10 (white)    |
|    4 |   | (200,100)        |   |   |                            |
|    5 |   | 30px cells + 3px |   |   |                            |
|    6 |   |   |   |   |   |   |   |   |                           |
|    7 |   |   |   |   |   |   |   |   |                           |
|      +---+---+---+---+---+---+---+---+                           |
|                                                                  |
| Mode: TEST_PATTERN (y=460)  FIFOs: S:0 H:1 Free:31               |
+------------------------------------------------------------------+
```

### Text Elements (From Dead Code)

| Element | Position | Color | Purpose |
|---------|----------|-------|---------|
| Title | centerX=320, y=10 | White ($FFFFFFFF) | System identification |
| Row labels 0-7 | x=GRID_X-20, y varies | Yellow ($FFFF00FF) | Row coordinates |
| Column labels 0-7 | y=GRID_Y-15, x varies | Yellow ($FFFF00FF) | Column coordinates |
| Min value | x=480, y=50 | Green ($00FF00FF) | Minimum sensor reading |
| Max value | x=480, y=65 | Red ($FF0000FF) | Maximum sensor reading |
| Avg value | x=480, y=80 | Cyan ($00FFFFFF) | Average sensor reading |
| Frame counter | x=480, y=110 | White ($FFFFFFFF) | Current/total frames |
| Mode status | x=10, y=460 | Yellow ($FFFF00FF) | Operating mode |
| FIFO status | x=200, y=460 | Green ($00FF00FF) | Buffer depths |

---

## Why Text Was Disabled

From `isp_hdmi_display_engine.spin2` lines 177-180:
```spin2
' Add text labels around the display
debug("HDMI Engine Loop: Drawing text labels...", 13, 10)
' TEMPORARILY DISABLED - Testing if grid and sensor display work without text
'DrawStaticLabels()
```

**Likely reasons for disabling:**
1. Testing isolation - verify grid/sensor display works independently
2. Possible stack overflow concerns (stack size was increased from 64 to 128)
3. Potential performance concerns during initial development
4. May have caused crashes or display corruption during debugging

---

## Implementation Approaches

### Approach A: Re-enable Existing Code (Recommended First Step)

Simply uncomment `DrawStaticLabels()` and test. This is the lowest-risk approach.

**Pros:**
- Zero new code needed
- Tests existing infrastructure
- Quick feedback on what works/fails

**Cons:**
- Static text only (Min/Max/Avg are hardcoded placeholders)
- No dynamic updates
- May reveal underlying issues

### Approach B: Staged Enablement with Isolation

Enable text features one at a time to identify any issues:

1. **Phase 1:** Title only (single DrawTextCentered call)
2. **Phase 2:** Add row/column labels (DrawChar in loop)
3. **Phase 3:** Add statistics area (DrawText calls)
4. **Phase 4:** Add status line (bottom text)

**Pros:**
- Identifies exactly where failures occur
- Gradual stack/memory testing
- Clear debugging path

### Approach C: Lightweight Test First (Recommended)

Create a minimal test program that ONLY tests text rendering:

```spin2
' test_hdmi_text.spin2 - Minimal HDMI text test
OBJ
  gfx : "isp_psram_graphics"

PUB main()
  gfx.init(0)      ' HDMI on pin group 0
  gfx.start()      ' Initialize for this COG
  gfx.cls($000000) ' Black background

  ' Test 1: Single character
  gfx.DrawChar(100, 100, "A", $FFFFFFFF)

  ' Test 2: Short string
  gfx.DrawText(100, 120, @"Hello", $FFFF00FF)

  ' Test 3: Centered text
  gfx.DrawTextCentered(320, 200, @"CENTERED", $00FF00FF)

  repeat  ' Hold display
```

**Pros:**
- Minimal COG usage (no sensor, no FIFO)
- Isolated test of graphics subsystem
- Quick compile/run cycle
- Clear pass/fail

---

## Recommended Implementation Plan

### Phase 1: Lightweight Text Test

**Goal:** Verify text rendering works in isolation

**Steps:**
1. Create `test_hdmi_text_only.spin2` with minimal code (above)
2. Compile with debug: `pnut_ts -d test_hdmi_text_only.spin2`
3. Run and verify characters appear on HDMI display
4. Test each font type by calling `gfx.SetFont()`
5. Document any issues (garbled chars, wrong positions, crashes)

**Success Criteria:**
- Text visible at correct positions
- Colors render correctly
- No crashes or display corruption

### Phase 2: Enable Static Labels in Full System

**Goal:** Re-enable `DrawStaticLabels()` in production code

**Steps:**
1. Uncomment line 179 in `isp_hdmi_display_engine.spin2`:
   ```spin2
   DrawStaticLabels()  ' Was commented out
   ```
2. Compile full system: `pnut_ts -d mag_tile_viewer.spin2`
3. Run and observe behavior
4. Monitor debug output for stack overflow warnings
5. Verify grid and text coexist without corruption

**Potential Issues to Watch:**
- Stack overflow in display COG (currently 128 longs)
- PSRAM contention between text and grid rendering
- Timing issues with DrawText during frame updates

### Phase 3: Add Dynamic Statistics

**Goal:** Replace placeholder text with live sensor data

**Changes to `isp_hdmi_display_engine.spin2`:**

```spin2
VAR
  word  frame_min           ' Minimum sensor value in frame
  word  frame_max           ' Maximum sensor value in frame
  long  frame_avg           ' Average sensor value in frame
  byte  stats_text[20]      ' Buffer for formatted text

PRI update_frame_stats(framePtr) | i, val
  '' Calculate min/max/avg for current frame
  frame_min := 65535
  frame_max := 0
  frame_avg := 0

  repeat i from 0 to 63
    val := WORD[framePtr][i]
    if val < frame_min
      frame_min := val
    if val > frame_max
      frame_max := val
    frame_avg += val

  frame_avg /= 64

PRI draw_dynamic_stats()
  '' Redraw statistics with current values
  '' Clear previous text area first, then draw new values

  ' Format and draw Min
  format_number(@stats_text, frame_min)
  gfx.FillRect(480, 50, 600, 60, $00000000)  ' Clear area
  gfx.DrawText(480, 50, @"Min: ", $00FF00FF)
  gfx.DrawText(520, 50, @stats_text, $00FF00FF)

  ' Similar for Max, Avg, Frame counter...
```

### Phase 4: Optimize and Polish

**Performance Optimizations:**
1. Only redraw dynamic text when values change
2. Use double-buffered text areas if needed
3. Consider pre-rendered number sprites for faster updates

**Visual Polish:**
1. Add box around statistics area
2. Consider larger font for title (8x8 instead of 5x7)
3. Add color legend for sensor values
4. Add scale bar for magnetic field strength

---

## Screen Layout Specification

### 640x480 Coordinate System

```
(0,0)                                           (639,0)
  +--------------------------------------------------+
  |  TITLE ZONE (y: 0-30)                            |
  |    - Centered title at y=10                      |
  |    - Column labels at y=GRID_Y-15 (y=85)         |
  +--------------------------------------------------+
  |          | GRID ZONE (x: 200-468, y: 100-364)    |
  | ROW      |                                       |
  | LABELS   |     8x8 SENSOR GRID                   |
  | (x:180)  |     Cell: 30px + 3px gap = 33px       |
  |          |     Total: 8*33 = 264px + grid lines  |
  |          |                                       |
  +----------+---------------------------------------+
  |          | STATS ZONE (x: 480-630, y: 50-130)    |
  |          |   Min/Max/Avg/Frame                   |
  +--------------------------------------------------+
  |  STATUS ZONE (y: 450-479)                        |
  |    - Mode at x=10                                |
  |    - FIFO status at x=200                        |
  +--------------------------------------------------+
(0,479)                                        (639,479)
```

### Grid Dimensions (from code)

```spin2
GRID_X      = 200       ' Grid top-left X position
GRID_Y      = 100       ' Grid top-left Y position
CELL_SIZE   = 30        ' Size of each sensor cell in pixels
CELL_GAP    = 3         ' Gap between cells in pixels

' Calculated:
GRID_WIDTH  = 8 * (30 + 3) + 1 = 265 pixels
GRID_HEIGHT = 8 * (30 + 3) + 1 = 265 pixels
GRID_RIGHT  = 200 + 265 = 465
GRID_BOTTOM = 100 + 265 = 365
```

### Available Text Zones

| Zone | X Range | Y Range | Width | Purpose |
|------|---------|---------|-------|---------|
| Title | 0-640 | 0-30 | Full | Centered title |
| Left margin | 0-180 | 100-365 | 180px | Row labels |
| Top margin | 200-465 | 60-100 | 265px | Column labels |
| Right panel | 475-640 | 50-365 | 165px | Statistics |
| Bottom bar | 0-640 | 440-480 | Full | Mode/status |

---

## Font Selection Recommendations

### For This Application

| Use Case | Recommended Font | Reason |
|----------|-----------------|--------|
| Title | `TEXT_FONT_8x8B` | Larger, more visible |
| Row/Col labels | `TEXT_FONT_5x7` | Compact, fits in margins |
| Statistics | `TEXT_FONT_5x7_DITH_DCNDR` | Anti-aliased, readable |
| Status line | `TEXT_FONT_5x7` | Compact for dense info |

### Font Characteristics

| Font | Size | Style | Anti-alias | Descenders |
|------|------|-------|------------|------------|
| TEXT_FONT_5x7 | 5x7 | Mono | No | No |
| TEXT_FONT_8x8A | 7x7 | Mono | No | No |
| TEXT_FONT_8x8B | 8x8 | Mono | No | Yes |
| TEXT_FONT_5x7_DITH | 5x7 | Mono | Yes (2bpp) | No |
| TEXT_FONT_5x7_DITH_DCNDR | 5x9 | Mono | Yes (2bpp) | Yes |

---

## Testing Strategy

### Test 1: Minimal Text Test (First!)

**File:** `test_hdmi_text_only.spin2`
**Duration:** Quick (< 5 minutes)
**Success:** Text appears, correct colors, no crashes

### Test 2: Full Labels - Static

**File:** `mag_tile_viewer.spin2` with `DrawStaticLabels()` enabled
**Duration:** 10-15 minutes with sensor active
**Verify:**
- Grid still updates normally
- Text doesn't flicker or corrupt
- No stack overflow warnings in debug

### Test 3: Dynamic Statistics

**After Phase 3 implementation**
**Verify:**
- Min/Max/Avg update with sensor data
- Frame counter increments
- Text area doesn't corrupt grid

### Test 4: Performance Measurement

**Measure:**
- Frame rate with text enabled vs disabled
- Stack usage (stack_check reports)
- PSRAM contention (any slowdown?)

---

## Risk Assessment

### Low Risk
- Re-enabling static text (code already tested at some point)
- Fonts library (6000+ lines, mature code)
- Graphics primitives (DrawText/DrawChar work conceptually)

### Medium Risk
- Stack overflow in display COG (128 longs may be tight)
- PSRAM contention during text rendering
- Dynamic text updates causing frame drops

### High Risk
- None identified - all infrastructure exists

### Mitigation

1. **Stack overflow:** Increase `HDMI_STACK_SIZE_LONGS` if needed (e.g., 192 or 256)
2. **PSRAM contention:** Draw static text once at startup, only dynamic text per-frame
3. **Frame drops:** Implement "lazy" updates - only redraw changed values

---

## Implementation Checklist

### Phase 1: Lightweight Test
- [ ] Create `test_hdmi_text_only.spin2`
- [ ] Compile and download
- [ ] Verify text renders correctly
- [ ] Test all font types
- [ ] Document any issues

### Phase 2: Static Labels
- [ ] Uncomment `DrawStaticLabels()` call
- [ ] Test with full system running
- [ ] Monitor stack usage
- [ ] Verify grid + text coexistence
- [ ] Performance baseline (fps with text)

### Phase 3: Dynamic Statistics
- [ ] Add min/max/avg calculation
- [ ] Add frame counter update
- [ ] Implement text clearing/redraw
- [ ] Test performance impact
- [ ] Verify values are accurate

### Phase 4: Polish
- [ ] Optimize update frequency
- [ ] Add visual enhancements
- [ ] Document final layout
- [ ] Update Theory of Operations docs

---

## Appendix: DrawStaticLabels() Current Implementation

From `isp_hdmi_display_engine.spin2` lines 217-246:

```spin2
PRI DrawStaticLabels() | row, col, labelX, labelY
  '' Draw static text labels around the sensor grid display
  '' Includes title, row/column labels, and placeholders for statistics

  ' Title at top center
  gfx.DrawTextCentered(320, 10, @"Magnetic Imaging Tile Display", $FFFFFFFF)  ' White

  ' Row labels (0-7) down left side
  labelX := GRID_X - 20
  repeat row from 0 to 7
    labelY := GRID_Y + row * (CELL_SIZE + CELL_GAP) + 12  ' Centered in cell
    gfx.DrawChar(labelX, labelY, "0" + row, $FFFF00FF)  ' Yellow

  ' Column labels (0-7) across top
  labelY := GRID_Y - 15
  repeat col from 0 to 7
    labelX := GRID_X + col * (CELL_SIZE + CELL_GAP) + 12  ' Centered in cell
    gfx.DrawChar(labelX, labelY, "0" + col, $FFFF00FF)  ' Yellow

  ' Statistics area (top right) - sample placeholders
  gfx.DrawText(480, 50, @"Min: 1200", $00FF00FF)   ' Green
  gfx.DrawText(480, 65, @"Max: 3000", $FF0000FF)   ' Red
  gfx.DrawText(480, 80, @"Avg: 2100", $00FFFFFF)   ' Cyan

  ' Frame counter (top right)
  gfx.DrawText(480, 110, @"Frame: 0/10", $FFFFFFFF)  ' White

  ' Status line (bottom left)
  gfx.DrawText(10, 460, @"Mode: TEST_PATTERN", $FFFF00FF)  ' Yellow
  gfx.DrawText(200, 460, @"FIFOs: S:0 H:1 Free:31", $00FF00FF)  ' Green
```

---

## Appendix: Related Files

| File | Purpose | Lines |
|------|---------|-------|
| `isp_hub75_fonts.spin2` | 5 font definitions | 6045 |
| `isp_psram_graphics.spin2` | Drawing + text API | ~1100 |
| `isp_hdmi_display_engine.spin2` | Display COG | ~280 |
| `isp_hdmi_640x480_24bpp.spin2` | HDMI signal generation | ~500 |

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-26 | Initial planning document. Analyzed existing infrastructure. Recovered disabled text code. Proposed phased implementation. |
