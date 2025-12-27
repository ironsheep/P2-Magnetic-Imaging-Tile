# HDMI Display Content Enhancement Proposal

**Date:** 2025-12-26
**Purpose:** Improve pedagogical value of the HDMI display for educational demonstrations

---

## Current Display Analysis

### Existing Content

```
+------------------------------------------------------------------+
|                    Magnetic Imaging Tile Display        (title)   |
|                                                                   |
|       0   1   2   3   4   5   6   7                   Min: 20450  |
|     +---+---+---+---+---+---+---+---+                  Max: 20560  |
|   0 |   |   |   |   |   |   |   |   |                  Avg: 20505  |
|   1 |   |   |   |   |   |   |   |   |                  Frame: 1234 |
|   2 |   |   | (8x8 sensor grid)     |                              |
|   3 |   |   |   |   |   |   |   |   |                              |
|   4 |   |   |   |   |   |   |   |   |                              |
|   5 |   |   |   |   |   |   |   |   |                              |
|   6 |   |   |   |   |   |   |   |   |                              |
|   7 |   |   |   |   |   |   |   |   |                              |
|     +---+---+---+---+---+---+---+---+                              |
|                                                                   |
|  Mode: LIVE                                                       |
+------------------------------------------------------------------+
```

### Pedagogical Weaknesses

1. **No color legend** - Viewer doesn't know what red/green means
2. **Raw ADC values** - "Min: 20450" is meaningless to a student
3. **No context** - What is this device? What am I seeing?
4. **No guidance** - How should I interact with it?
5. **No physics connection** - Missed opportunity to teach

---

## Display Layout Proposal

### Screen Regions (640x480)

| Region | X Range | Y Range | Purpose |
|--------|---------|---------|---------|
| Title Bar | 0-640 | 0-25 | Title and branding |
| Physics Zone | 0-180 | 30-200 | Educational text |
| Sensor Grid | 200-464 | 100-364 | Visualization (unchanged) |
| Color Legend | 480-630 | 100-280 | Field polarity guide |
| Live Stats | 480-630 | 290-380 | Current readings |
| Activity Zone | 0-180 | 210-460 | Suggested experiments |
| Status Bar | 200-640 | 450-475 | Mode and frame info |

---

## Proposed Content

### 1. Title Bar (Enhanced)

**Current:**
```
Magnetic Imaging Tile Display
```

**Proposed:**
```
MAGNETIC FIELD IMAGER
64 Hall Effect Sensors | 60 fps | P2 @ 250 MHz
```

**Rationale:** Adds technical context, establishes this as a real-time sensor array.

---

### 2. Physics Zone (Left Side - NEW)

**Content Block 1: What You're Seeing**
```
+------------------------+
|  WHAT YOU SEE          |
|                        |
|  Each square shows     |
|  magnetic field        |
|  strength at that      |
|  point in space.       |
|                        |
|  GREEN = North pole    |
|          (field INTO   |
|           sensor)      |
|                        |
|  RED = South pole      |
|        (field OUT OF   |
|         sensor)        |
|                        |
|  GRAY = No field       |
|         (neutral)      |
+------------------------+
```

**Alternative - Compact Version:**
```
FIELD POLARITY
  GREEN: North (+B)
  RED:   South (-B)
  GRAY:  Zero field
```

---

### 3. Color Legend (Right Side - VISUAL)

**Proposed: Vertical Gradient Bar with Labels**

```
    FIELD
    STRENGTH
      |
     +N+  <-- Bright Green (strong N)
      |
      |   <-- Medium Green
      |
     [ ]  <-- Gray (zero)
      |
      |   <-- Medium Red
      |
     -S-  <-- Bright Red (strong S)
      |
```

**Implementation:** Draw a vertical color bar (20x180 pixels) showing the actual gradient used in rendering, with text labels.

**Pedagogical Value:** Immediately communicates the color mapping without explanation.

---

### 4. Live Stats (Enhanced)

**Current:**
```
Min: 20450
Max: 20560
Avg: 20505
Frame: 1234
```

**Proposed - Option A (Scaled to mT):**
```
LIVE READINGS
--------------
Peak-:  -2.5 mT   [red]
Peak+:  +3.2 mT   [green]
Range:   5.7 mT
Avg:     0.1 mT   [gray]

Baseline: 20500
Frame: 1234
```

**Proposed - Option B (Relative Scale):**
```
FIELD INTENSITY
----------------
Strongest: ||||||||| 87%
Weakest:   ||        12%
Average:   |||       25%

Frame: 1234 @ 60 fps
```

**Rationale:** Raw ADC counts are meaningless. Percentages or calibrated units communicate real information.

---

### 5. Activity Zone (Left Side - NEW)

**Suggested Experiments Panel:**

```
TRY THIS:
---------

1. BAR MAGNET
   Point N pole down
   What shape appears?

2. TWO MAGNETS
   Place them together
   See the interaction!

3. FIELD LINES
   Tilt magnet slowly
   Watch field shift

4. DISTANCE
   Move magnet up/down
   See strength change
```

**Alternative - Rotating Tips:**
Display one tip at a time, rotating every 5-10 seconds:

```
TIP: Move magnet closer
     to see stronger field
```

---

### 6. Status Bar (Enhanced)

**Current:**
```
Mode: LIVE
```

**Proposed:**
```
LIVE  |  Cal: OK  |  60 fps  |  Stuck: 0  |  Baseline: 20500
```

**Or with warnings:**
```
LIVE  |  CAL: 5s ago  |  58 fps  |  STUCK: 2 pixels (magenta)
```

---

## Implementation Considerations

### Screen Real Estate

The current grid is 264x264 pixels centered at (332, 232). This leaves:

- **Left margin:** 200 pixels (ample for text)
- **Right margin:** 176 pixels (tight but usable)
- **Bottom margin:** 116 pixels (room for status + tips)

### Font Requirements

Current font is 5x7 dithered. For the proposed content:
- **Title:** 8x8 or larger for visibility
- **Section headers:** 5x7 bold (uppercase works well)
- **Body text:** 5x7 standard (current font is fine)
- **Values:** 5x7, right-aligned for numerics

### Dynamic vs Static Content

| Element | Type | Update Rate |
|---------|------|-------------|
| Title | Static | Never |
| Physics text | Static | Never |
| Color legend | Static | Never |
| Live stats | Dynamic | Per frame |
| Activity tips | Semi-static | Every 5 sec |
| Status bar | Dynamic | Per frame |

**Optimization:** Draw static elements ONCE at startup (already done), only update dynamic regions per frame.

---

## Visual Mockup

```
+------------------------------------------------------------------+
|       MAGNETIC FIELD IMAGER - 64 Hall Sensors @ 60 fps           |
+------------------------------------------------------------------+
| FIELD POLARITY   |    0  1  2  3  4  5  6  7    |    FIELD      |
|                  |  +---+---+---+---+---+---+---+|  STRENGTH     |
| GREEN = North    |0 |   |   |   |   |   |   |   ||    +N+       |
|  (into sensor)   |1 |   |   |   |   |   |   |   ||     |        |
|                  |2 |   |   |   |   |   |   |   ||     |        |
| RED = South      |3 |   |   | GRID |   |   |   ||   [===]      |
|  (out of sensor) |4 |   |   |   |   |   |   |   ||     |        |
|                  |5 |   |   |   |   |   |   |   ||     |        |
| GRAY = Zero      |6 |   |   |   |   |   |   |   ||     |        |
|                  |7 |   |   |   |   |   |   |   ||    -S-       |
|------------------|  +---+---+---+---+---+---+---+|              |
| TRY THIS:        |                               |  LIVE STATS  |
|                  |                               |  Peak-: -2mT |
| Place magnet     |                               |  Peak+: +3mT |
| on tile center   |                               |  Avg:   0 mT |
| - N pole down    |                               |              |
+------------------------------------------------------------------+
| LIVE | Calibrated | 60 fps | Frame: 12345                        |
+------------------------------------------------------------------+
```

---

## Recommended Implementation Priority

### Phase 1: Essential (Immediate Value)
1. Add vertical color legend bar with N/S labels
2. Add brief "GREEN = North, RED = South" text
3. Convert stats to percentage or relative scale

### Phase 2: Educational Enhancement
4. Add "What You See" explanation block
5. Add rotating experiment tips

### Phase 3: Polish
6. Enhanced status bar with calibration info
7. Magnet interaction hints based on detected patterns

---

## Alternative: Minimalist Approach

If screen clutter is a concern, consider a **tooltip mode** that overlays explanatory text when no magnet is detected:

**Idle State (no field detected):**
```
                PLACE MAGNET ON SENSOR

                GREEN = North pole (field in)
                RED   = South pole (field out)
```

**Active State (field detected):**
```
                [Normal display with just grid + stats]
```

---

## Code Changes Required

1. **New constants for layout positions:**
```spin2
CON
  ' Left panel (physics text)
  PHYSICS_X      = 10
  PHYSICS_Y      = 40

  ' Color legend (right side)
  LEGEND_X       = 490
  LEGEND_TOP_Y   = 100
  LEGEND_BOT_Y   = 280
  LEGEND_WIDTH   = 20
```

2. **New method: DrawColorLegend()**
```spin2
PRI DrawColorLegend() | y, fieldVal, color
  ' Draw vertical gradient bar
  repeat y from LEGEND_TOP_Y to LEGEND_BOT_Y
    ' Calculate field value for this Y position
    fieldVal := ((LEGEND_BOT_Y - y) * 65535) / (LEGEND_BOT_Y - LEGEND_TOP_Y)
    color := field_to_color(fieldVal)
    gfx.DrawHLine(LEGEND_X, LEGEND_X + LEGEND_WIDTH, y, color)

  ' Labels
  gfx.DrawText(LEGEND_X + 25, LEGEND_TOP_Y, @"+N", $00FF00FF)
  gfx.DrawText(LEGEND_X + 25, LEGEND_BOT_Y, @"-S", $FF0000FF)
```

3. **Update DrawStaticLabels() with educational content**

---

## Summary

The current display is functional but misses significant pedagogical opportunities. The proposed enhancements:

- **Explain the visualization** with color legend and polarity labels
- **Contextualize readings** with meaningful units or percentages
- **Guide exploration** with suggested experiments
- **Connect to physics** by using proper terminology (North/South, field lines)

These changes transform the display from "technically impressive" to "educationally valuable" while maintaining the real-time performance characteristics.
