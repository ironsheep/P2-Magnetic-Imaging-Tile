# Visualization Theory of Operations
**Magnetic Imaging Tile - P2 Display System**

## Document Version
- **Version:** 1.0
- **Date:** 2025-12-26
- **Status:** Implementation Documentation

## Overview

This document describes the theory of operations for visualizing magnetic sensor data on the P2 Magnetic Imaging Tile system. It covers color mapping design, display implementations, known artifacts, and performance considerations.

### Display Targets
| Display | Resolution | Color Depth | Interface | Max FPS |
|---------|------------|-------------|-----------|---------|
| OLED (SSD1351) | 128x128 | RGB565 (16-bit) | SPI | ~55 fps |
| HDMI | 640x480 | RGB888 (24-bit) | DVI | 60 fps |

### Design Goals
1. **Intuitive visualization**: Red for negative field, green for positive, gray for neutral
2. **Consistent appearance**: Both displays show the same colors for the same field values
3. **High performance**: Maximize frame rate without sacrificing visual quality
4. **Full dynamic range**: Handle any field strength within sensor capability

---

## Color Mapping Design

### Bipolar Color Scheme

The visualization uses a bipolar color scheme centered on the zero-field baseline:

```
Strong Negative    Neutral    Strong Positive
     RED      <--- GRAY --->    GREEN
   (0-255)        (32)         (0-255)
```

### ADC Value Mapping

The DRV5053VA Hall effect sensors produce values across the full 16-bit ADC range:

| ADC Value | Field | Color |
|-----------|-------|-------|
| 0 | Maximum negative | Bright Red (255,0,0) |
| 20,500 | Zero field (baseline) | Dark Gray (32,32,32) |
| 65,535 | Maximum positive | Bright Green (0,255,0) |

### Asymmetric Range Design

The observed baseline (20,500) is not centered in the ADC range, creating asymmetric color scaling:

```
ADC Range:
0 ←──── 20,500 ────────────────────────→ 65,535
  NEGATIVE_RANGE    │     POSITIVE_RANGE
     (20,500)       │        (45,035)
                    │
         More sensitive    Less sensitive
         to negative       to positive
```

**Implication:** Negative fields appear more saturated than equivalent positive fields. This is a deliberate design choice to use the full ADC range for future stronger magnets.

### Color Formula

The current implementation uses a two-component formula:

```
For sensor_val < SENSOR_MID (negative field):
    intensity = (SENSOR_MID - sensor_val) * 255 / NEGATIVE_RANGE
    gray_fade = sensor_val * GRAY_BASE / NEGATIVE_RANGE
    R = intensity, G = gray_fade, B = gray_fade

For sensor_val >= SENSOR_MID (positive field):
    intensity = (sensor_val - SENSOR_MID) * 255 / POSITIVE_RANGE
    gray_fade = (SENSOR_MAX - sensor_val) * GRAY_BASE / POSITIVE_RANGE
    R = gray_fade, G = intensity, B = gray_fade
```

---

## Display Implementations

### OLED Implementation (LUT-Based)

The OLED uses a **pre-computed 4096-entry color lookup table** for maximum performance:

```
Startup:
  ┌─────────────────────────────────────┐
  │ init_color_lut()                    │
  │   for i = 0 to 4095:                │
  │     sensor_val = (i * 65535) / 4095 │
  │     color = compute_color(sensor_val)│
  │     color_lut[i] = rgb_to_rgb565(color)│
  └─────────────────────────────────────┘

Runtime (PASM):
  ┌─────────────────────────────────────┐
  │ For each pixel:                     │
  │   index = scale_to_12bit(sensor_val)│
  │   color = color_lut[index]          │  ← Single table lookup!
  │   write_to_buffer(color)            │
  └─────────────────────────────────────┘
```

**Performance:** Zero runtime color computation - all math done at startup.

### HDMI Implementation (Direct Calculation)

The HDMI driver computes colors per-pixel at runtime:

```
Runtime:
  ┌─────────────────────────────────────┐
  │ For each pixel:                     │
  │   color = field_to_color(sensor_val)│  ← ~6 instructions
  │   write_to_framebuffer(color)       │
  └─────────────────────────────────────┘
```

**Performance:** Simple formula executes quickly; could be converted to LUT if needed.

---

## Known Artifacts

### Banding Artifact (Light-Dark-Light Rings)

**Symptom:** Concentric bands of alternating brightness appear around the magnetic field centroid, visible on both OLED and HDMI displays.

**Visual Pattern:**
```
        Moving outward from magnet center:

        [BRIGHT] → [LIGHTER] → [DARKER] → [LIGHTER] → [DIM]
           ↑           ↑           ↑           ↑
        centroid    band 1      band 2      band 3
```

#### Root Cause Analysis

The banding results from **dual quantization mismatch** between two calculations:

**Problem 1: Different step intervals**
```
intensity steps every:  ~80 ADC counts  (255 levels / 20,500 range)
gray_fade steps every: ~640 ADC counts  (32 levels / 20,500 range)
```

**Problem 2: RGB565 further quantizes**
```
Red channel:   intensity >> 3  (32 levels from 256)
Green channel: gray_fade >> 2  (64 levels from 256)
Blue channel:  gray_fade >> 3  (32 levels from 256)
```

**Result:** The intensity and gray_fade components quantize at different ADC boundaries, causing:
- Where intensity drops a level but gray_fade hasn't → darker band
- Where gray_fade increases but intensity stays → lighter band

#### Example Quantization Analysis

| Distance | sensor_val | intensity | gray_fade | R (>>3) | G (>>3) | Appearance |
|----------|------------|-----------|-----------|---------|---------|------------|
| Center | 5,000 | 192 | 7 | 24 | 0 | Bright red |
| Near | 12,000 | 106 | 18 | 13 | 2 | Red |
| Medium | 16,000 | 56 | 24 | 7 | 3 | **Lighter** (gray adds) |
| Far | 18,500 | 24 | 28 | 3 | 3 | **Darker** (equal R,G) |
| Edge | 19,800 | 8 | 30 | 1 | 3 | **Lighter** (gray dominates) |

The non-monotonic relationship between distance and perceived brightness causes visible banding.

---

## Solutions for Banding

### Option 1: Remove gray_fade (Simple)

Eliminate the gray_fade component entirely:

```spin2
if sensor_val < SENSOR_MID
  r := ((SENSOR_MID - sensor_val) * 255) / NEGATIVE_RANGE
  g := GRAY_BASE  ' Constant background
  b := GRAY_BASE
else
  r := GRAY_BASE
  g := ((sensor_val - SENSOR_MID) * 255) / POSITIVE_RANGE
  b := GRAY_BASE
```

**Pros:** Simple, eliminates banding completely
**Cons:** Less aesthetic gradient, abrupt color transitions

### Option 2: Synchronized gray_fade

Make gray_fade track intensity so they quantize together:

```spin2
' Express gray_fade as function of same base value
distance := SENSOR_MID - sensor_val  ' Same base for both
intensity := (distance * 255) / NEGATIVE_RANGE
gray_fade := GRAY_BASE - ((distance * GRAY_BASE) / NEGATIVE_RANGE)
```

**Pros:** Maintains gradient aesthetic
**Cons:** Still has RGB565 quantization on OLED

### Option 3: Perceptually Uniform Gradient (Recommended)

Pre-compute a LUT using **perceptually uniform** color transitions:

```spin2
PRI init_perceptual_lut() | i, t, r, g, b
  '' Build perceptually uniform color gradient
  '' Uses gamma correction and smooth interpolation

  repeat i from 0 to 4095
    ' Normalize to -1.0 to +1.0 range
    t := (i - 2048) * 1000 / 2048  ' Fixed-point -1000 to +1000

    if t < 0
      ' Negative: Red gradient with gamma
      r := gamma_correct(abs(t) * 255 / 1000)
      g := GRAY_BASE
      b := GRAY_BASE
    else
      ' Positive: Green gradient with gamma
      r := GRAY_BASE
      g := gamma_correct(t * 255 / 1000)
      b := GRAY_BASE

    color_lut[i] := rgb_to_rgb565(r, g, b)

PRI gamma_correct(linear) : corrected
  '' Apply gamma 2.2 correction for perceptual uniformity
  '' Uses pre-computed gamma table or approximation
  corrected := (linear * linear) / 255  ' Approximation: gamma ~2.0
```

**Pros:** Smooth gradients, no banding, professional appearance
**Cons:** Slightly more complex LUT generation

---

## Performance Considerations

### LUT-Based Rendering (OLED)

**Startup Cost:**
- LUT generation: ~50ms for 4096 entries
- Memory: 8KB (4096 x 2 bytes RGB565)
- One-time cost, no impact on runtime

**Runtime Cost:**
- Per-pixel: 1 table lookup (~4 cycles)
- Per-frame (64 pixels): ~256 cycles
- **Negligible** - limited by SPI transfer speed, not computation

### Direct Calculation (HDMI)

**Runtime Cost:**
- Per-pixel: ~20-30 cycles (current formula)
- Per-frame (64 sensors x 400 display pixels): ~500,000 cycles
- At 250 MHz: ~2ms per frame
- **Acceptable** for 60 fps target

### Adding LUT to HDMI (Optional Optimization)

If HDMI performance becomes critical:

```spin2
VAR
  long hdmi_color_lut[65536]  ' 256KB - fits in Hub RAM

PRI init_hdmi_lut()
  repeat i from 0 to 65535
    hdmi_color_lut[i] := compute_color(i)

PRI render_hdmi_pixel(sensor_val) : color
  return hdmi_color_lut[sensor_val]  ' Single lookup
```

**Trade-off:** 256KB RAM for zero-computation rendering

---

## Implementation Status

### Color Mapping Fix (Option 3) - IMPLEMENTED 2025-12-26

- [x] Update `init_color_lut()` in `isp_oled_single_cog.spin2` - gamma correction added
- [x] Update `field_to_color()` in `isp_hdmi_display_engine.spin2` - gamma correction added
- [x] Removed gray_fade component to eliminate dual-quantization banding
- [ ] Test with various magnet strengths
- [ ] Verify visual consistency between OLED and HDMI
- [ ] Update `MagSensor-Color-Mapping-Specification.md`

### Per-Sensor Calibration - IMPLEMENTED 2025-12-26

After implementing the color mapping fix, analysis revealed that **banding also exists in the raw sensor data** due to per-sensor baseline variation (manufacturing tolerances in the Hall effect sensors).

**Root Cause:** Each DRV5053VA sensor has a slightly different zero-field reading. Without calibration, these differences appear as bands in the display regardless of color mapping.

**Solution Implemented:**
- Added `capture_baseline()` API in `isp_tile_sensor.spin2`
- Added `apply_calibration()` that normalizes each sensor to SENSOR_MID
- Added `AUTO_CALIBRATE` flag in `mag_tile_viewer.spin2`
- Calibration captures a frame with no magnet, stores per-sensor baselines, then applies: `calibrated = raw - baseline[i] + SENSOR_MID`

**Usage:**
1. At startup, system prompts user to remove magnets
2. After 5 seconds, baseline frame is captured
3. All subsequent frames are automatically calibrated

### Performance Validation

- [ ] Measure OLED frame rate before/after
- [ ] Measure HDMI frame rate before/after
- [ ] Profile LUT generation time at startup
- [ ] Verify memory usage within budget
- [ ] Test calibration accuracy with multiple baseline captures

---

## Related Documents

- **Color Mapping Specification:** `DOCs/MagSensor-Color-Mapping-Specification.md`
- **OLED Driver Theory:** `DOCs/OLED-Driver-Theory-of-Operation.md`
- **HDMI Driver Theory:** `DOCs/HDMI-Driver-Theory-of-Operation.md`
- **Sensor Driver Theory:** `DOCs/MagSensor-Driver-Theory-of-Operation.md`
- **Arduino Reference:** `DOCs/REF-Implementation/Processing_Visualization_Theory_of_Operations.md`

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-26 | Initial document. Documented banding artifact root cause (dual quantization mismatch). Added three solution options with performance analysis. Recommended Option 3 (perceptually uniform gradient) with LUT for zero runtime cost. |
| 1.1 | 2025-12-26 | Implemented gamma-corrected color mapping (Option 3). Discovered additional banding source in raw sensor data due to per-sensor baseline variation. Implemented per-sensor calibration system with `capture_baseline()` API and automatic calibration at startup. |
