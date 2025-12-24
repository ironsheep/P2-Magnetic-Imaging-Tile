# Magnetic Sensor Color Mapping Specification

**Document Version:** 1.0
**Last Updated:** 2025-12-23
**Status:** Calibrated from bipolar magnet testing

## Overview

This document defines the mathematically correct mapping from magnetic sensor ADC values to display colors, ensuring consistency between OLED and HDMI displays.

## ADC Characteristics

### Hardware Configuration
- **ADC Type:** AD7940 (14-bit) / AD7680 (16-bit)
- **Output Format:** Unsigned integer
- **Reference:** Internal, ratiometric to supply

### Full ADC Range Design (Updated 2025-12-23)

The system maps the **full ADC range** (0-65535) to colors, not just the observed range.
This ensures stronger magnets in the future will still produce valid colors.

| Parameter | Decimal | Hexadecimal | Description |
|-----------|---------|-------------|-------------|
| SENSOR_MIN | 0 | 0x0000 | ADC minimum (theoretical full negative saturation) |
| SENSOR_MID | 20,500 | 0x5014 | Zero field baseline (observed neutral point) |
| SENSOR_MAX | 65,535 | 0xFFFF | ADC maximum (theoretical full positive saturation) |
| NEGATIVE_RANGE | 20,500 | - | SENSOR_MID - SENSOR_MIN |
| POSITIVE_RANGE | 45,035 | - | SENSOR_MAX - SENSOR_MID |

### Observed Values (Calibrated 2025-12-23)

During bipolar magnet testing, actual values observed:
- Strong negative pole: ~1,000
- No field (baseline): ~20,500
- Strong positive pole: ~41,000

### Range Analysis

```
Full 16-bit ADC range with asymmetric color mapping:

0x0000                    0x5014                              0xFFFF
   │                         │                                   │
   0                      20,500                              65,535
   MIN                      MID                                 MAX
   │◄───────────────────────►│◄─────────────────────────────────►│
          20,500 counts               45,035 counts
        (negative range)            (positive range)
           RED colors               GREEN colors
```

**Design Rationale:**
- Uses full ADC range to accommodate stronger magnets in future
- Baseline (20,500) is asymmetric within full range
- Negative range (20,500) is smaller than positive range (45,035)
- Color intensity is normalized independently for each range
- ADC outputs **unsigned** values, not signed

## Color Mapping Formula

### Target Color Scheme

| Field Polarity | Intensity | RGB Color |
|----------------|-----------|-----------|
| Strong negative | 100% | (255, 0, 0) - Bright Red |
| Weak negative | 50% | (128, 16, 16) - Dark Red |
| Neutral (zero) | 0% | (32, 32, 32) - Dark Gray |
| Weak positive | 50% | (16, 128, 16) - Dark Green |
| Strong positive | 100% | (0, 255, 0) - Bright Green |

### Mathematical Formulas

#### Constants (Full ADC Range)
```
SENSOR_MIN = 0           // ADC minimum
SENSOR_MID = 20500       // Observed zero-field baseline
SENSOR_MAX = 65535       // ADC maximum
NEGATIVE_RANGE = 20500   // SENSOR_MID - SENSOR_MIN
POSITIVE_RANGE = 45035   // SENSOR_MAX - SENSOR_MID
GRAY_BASE = 32           // Neutral gray intensity
```

#### Piece-wise Linear Mapping

**For sensor_val < SENSOR_MID (Negative Field → Red):**
```
intensity = 255 × (SENSOR_MID - sensor_val) / NEGATIVE_RANGE
          = 255 × (20500 - sensor_val) / 20500

gray_fade = GRAY_BASE × sensor_val / NEGATIVE_RANGE
          = 32 × sensor_val / 20500

R = intensity
G = gray_fade
B = gray_fade

Simplified:
R = 255 × (20500 - sensor_val) / 20500
G = 32 × sensor_val / 20500
B = G
```

**For sensor_val ≥ SENSOR_MID (Positive Field → Green):**
```
intensity = 255 × (sensor_val - SENSOR_MID) / POSITIVE_RANGE
          = 255 × (sensor_val - 20500) / 45035

gray_fade = GRAY_BASE × (SENSOR_MAX - sensor_val) / POSITIVE_RANGE
          = 32 × (65535 - sensor_val) / 45035

R = gray_fade
G = intensity
B = gray_fade

Simplified:
R = 32 × (65535 - sensor_val) / 45035
G = 255 × (sensor_val - 20500) / 45035
B = R
```

### Verification Table (Full ADC Range)

| sensor_val | Field | R | G | B | Visual |
|------------|-------|---|---|---|--------|
| 0 | Max - | 255 | 0 | 0 | Bright Red |
| 5,125 | 75% - | 191 | 8 | 8 | Red |
| 10,250 | 50% - | 128 | 16 | 16 | Dark Red |
| 15,375 | 25% - | 64 | 24 | 24 | Dim Red |
| 20,500 | Neutral | 0/32 | 32/0 | 32 | Dark Gray* |
| 31,884 | 25% + | 24 | 64 | 24 | Dim Green |
| 43,268 | 50% + | 16 | 128 | 16 | Dark Green |
| 54,651 | 75% + | 8 | 191 | 8 | Green |
| 65,535 | Max + | 0 | 255 | 0 | Bright Green |

*Note: There is a small color discontinuity at the neutral point due to
asymmetric ranges. This creates a visible polarity transition marker.

## Display-Specific Implementation

### OLED (RGB565)

**Color Depth:**
- Red: 5 bits (32 levels)
- Green: 6 bits (64 levels)
- Blue: 5 bits (32 levels)

**Effective Resolution:**
- Negative field: 19,500 / 32 = **609 sensor units per red step**
- Positive field: 20,500 / 64 = **320 sensor units per green step**

**Implementation:** Pre-computed 4096-entry LUT
- Input: Scaled 12-bit index (0-4095)
- Scaling: `index = ((sensor_val - 1000) × 4095) / 40000`
- Output: RGB565 color (pre-computed from formula above)

### HDMI (24-bit RGB)

**Color Depth:**
- Red: 8 bits (256 levels)
- Green: 8 bits (256 levels)
- Blue: 8 bits (256 levels)

**Effective Resolution:**
- Negative field: 19,500 / 256 = **76 sensor units per red step**
- Positive field: 20,500 / 256 = **80 sensor units per green step**

**Implementation:** Direct calculation per pixel
- No LUT needed - compute RGB directly from formula
- Output format: 0xRRGGBBAA (alpha = 0xFF)

## Neutral Dead-band (Optional)

To prevent noise from causing color flicker at baseline:

```
NEUTRAL_LOW  = SENSOR_MID - 500 = 20000
NEUTRAL_HIGH = SENSOR_MID + 500 = 21000
```

Any sensor_val in range [20000, 21000] maps to neutral gray (32, 32, 32).

This creates a 1000-count (2.5% of range) dead-band where small variations don't cause color changes.

## Code Implementation

### Spin2 Reference Implementation

```spin2
CON
  ' Full ADC range design - accommodates stronger magnets
  SENSOR_MIN = 0          ' ADC minimum
  SENSOR_MID = 20500      ' Observed zero-field baseline
  SENSOR_MAX = 65535      ' ADC maximum
  NEGATIVE_RANGE = 20500  ' SENSOR_MID - SENSOR_MIN
  POSITIVE_RANGE = 45035  ' SENSOR_MAX - SENSOR_MID
  GRAY_BASE = 32

PRI sensor_to_rgb(sensor_val) : r, g, b | intensity, gray_fade
  '' Convert sensor value to RGB using unified linear mapping

  ' Clamp to valid ADC range
  sensor_val := SENSOR_MIN #> sensor_val <# SENSOR_MAX

  if sensor_val < SENSOR_MID
    ' Negative field: Red with fading gray
    intensity := ((SENSOR_MID - sensor_val) * 255) / NEGATIVE_RANGE
    gray_fade := (sensor_val * GRAY_BASE) / NEGATIVE_RANGE
    r := intensity
    g := gray_fade
    b := gray_fade
  else
    ' Positive field: Green with fading gray
    intensity := ((sensor_val - SENSOR_MID) * 255) / POSITIVE_RANGE
    gray_fade := ((SENSOR_MAX - sensor_val) * GRAY_BASE) / POSITIVE_RANGE
    r := gray_fade
    g := intensity
    b := gray_fade
```

### HDMI Color Packing

```spin2
PRI sensor_to_hdmi_color(sensor_val) : color | r, g, b
  '' Returns color in RRGGBBAA format for HDMI
  r, g, b := sensor_to_rgb(sensor_val)
  color := (r << 24) | (g << 16) | (b << 8) | $FF
```

### OLED RGB565 Conversion

```spin2
PRI rgb_to_rgb565_bgr(r, g, b) : color
  '' Convert 8-bit RGB to 16-bit BGR565 for SSD1351
  '' SSD1351 expects BGR byte order
  color := ((b >> 3) << 11) | ((g >> 2) << 5) | (r >> 3)
```

## Calibrated Field Display (Optional)

### Sensor Specifications (DRV5053VA)

The SparkFun Magnetic Imaging Tile uses the **DRV5053VA** Hall effect sensor:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Sensitivity | -90 mV/mT | Highest sensitivity variant |
| Null Field Output | 1.0V | At 3.3V supply |
| Saturation Field | ±9 mT | Linear range limit |
| Linear Range | 0.19V to 1.81V | Output voltage |

### Calibration Constants

```
ADC reference:     3.3V
ADC resolution:    16-bit (0-65535)
Sensitivity:       -90 mV/mT

Counts per mT = 65535 × (0.090 / 3.3) = 1,787 counts/mT
Baseline:      20,500 counts (observed zero-field)

Conversion formula:
  Field (mT) = (ADC_reading - 20500) / 1787

Saturation limits:
  Negative: 20500 - (9 × 1787) = ~4,400 counts = -9 mT
  Positive: 20500 + (9 × 1787) = ~36,600 counts = +9 mT
```

### Display Scale

With ±9 mT range and 255 color intensity levels:
- Each intensity step = 9 mT / 255 = 0.035 mT = 35 µT
- Visible resolution: ~35 µT per color change

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.1 | 2025-12-23 | Added DRV5053VA calibration constants |
| 1.0 | 2025-12-23 | Initial specification from bipolar magnet calibration |
