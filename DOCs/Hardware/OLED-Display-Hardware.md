# Waveshare 1.5inch RGB OLED Module - Hardware Specifications

## Overview
The Waveshare 1.5inch RGB OLED Module is a compact, high-contrast display module featuring an SSD1351 controller. This module provides the primary visual output for the P2 Magnetic Imaging Tile system, displaying real-time magnetic field visualizations.

## Display Specifications

### Physical Characteristics
- **Display Size**: 26.855 × 26.855 mm active area
- **Resolution**: 128 × 128 pixels (RGB)
- **Pixel Dimensions**: 0.045mm (H) × 0.194mm (V)
- **Display Technology**: OLED (Organic Light Emitting Diode)
- **Color Depth**: 65K colors (16-bit) / 262K colors (18-bit)

### Electrical Characteristics
- **Operating Voltage**: 3.3V or 5V (must be consistent across all connections)
- **Current Consumption**:
  - Full white display: ~60mA
  - Full black display: ~4mA
  - Typical operation: 15-30mA

## Controller Details

### SSD1351 Controller
- **Internal RAM**: 128×128×18-bit SRAM display buffer
- **Color Modes**:
  - 65K colors (16-bit RGB565)
  - 262K colors (18-bit RGB666)
- **Interface Options**:
  - 4-wire SPI (default configuration)
  - 3-wire SPI (configurable via hardware modification)
- **Maximum SPI Clock**: 20MHz

## Interface Pinout

### SPI Communication Pins
| Pin | Function | Direction | Description |
|-----|----------|-----------|-------------|
| VCC | Power | Input | 3.3V or 5V power supply |
| GND | Ground | - | Ground reference |
| DIN | MOSI | Input | SPI data input (Master Out, Slave In) |
| SCL | SCLK | Input | SPI clock signal |
| CS | Chip Select | Input | Active low chip select |
| DC | Data/Command | Input | High=Data, Low=Command |
| RST | Reset | Input | Active low reset signal |

### P2 Pin Assignments

**Pin Group**: 16 (P16-P23)

| P2 Pin | Signal | Function | Direction | Description |
|--------|--------|----------|-----------|-------------|
| P16 (+0) | DIN | MOSI | Output | SPI data output to display |
| P18 (+2) | CLK | SCLK | Output | SPI clock signal |
| P20 (+4) | CS | Chip Select | Output | Active low chip select |
| P22 (+6) | DC | Data/Command | Output | High=Data, Low=Command |
| P23 (+7) | RST | Reset | Output | Active low reset signal |
| GND | GND | Ground | - | Ground reference |
| 3.3V | VCC | Power | - | 3.3V power supply |

- Pin group allocation allows efficient Smart Pin configuration
- Separate from magnetic tile interface (Pin Group 8: P8-P15)

## Communication Protocol

### SPI Timing Requirements
- **Data Setup Time**: min 5ns
- **Data Hold Time**: min 5ns
- **Clock Frequency**: max 20MHz
- **CS Setup Time**: min 20ns
- **CS Hold Time**: min 10ns

### Command/Data Protocol
1. Set DC low for command bytes
2. Set DC high for data bytes
3. CS must be low during entire transaction
4. Data sampled on SCL rising edge

### Display Orientation Configuration

**Physical Orientation (Standard Configuration):**
- Ribbon connector positioned at **BOTTOM** when viewing display normally
- Software coordinate (0,0) maps to physical **top-left corner** (opposite edge from ribbon)
- **Display side (front)**: English text label is readable (right-side-up) with ribbon at bottom
- **Component side (back)**: Label orientation differs - runs vertically, would be readable with ribbon at top/left

**⚠️ Important Note on Module Labels:**
The Waveshare module has labels on both sides that are oriented **differently**:
- **Display side**: Label at ribbon connector edge, reads correctly in standard orientation (ribbon at bottom)
- **Component side**: Label to left of ribbon connector, runs vertically, would read correctly if rotated 90° from standard orientation

For consistent orientation, **always use the display side label as reference**, not the component side.

**SSD1351 Remap Register Settings:**

The SSD1351 controller supports four display orientations via the remap register (command `$A0`):

| Orientation | Remap Value | Ribbon Position | Description |
|-------------|-------------|-----------------|-------------|
| **ORIENTATION_0** | `$73` | BOTTOM | Hardware default, (0,0) at top-left |
| **ORIENTATION_90** | `$72` | LEFT | Rotated 90° clockwise, (0,0) at top-left |
| **ORIENTATION_180** | `$70` | TOP | Rotated 180°, (0,0) at top-left |
| **ORIENTATION_270** | `$71` | RIGHT | Rotated 270° clockwise, (0,0) at top-left |

**Design Philosophy (Corrected November 2025):**

The orientation system ensures that **buffer[0,0] always appears at the visual top-left corner** regardless of ribbon position. This provides a consistent coordinate system for application code.

**Understanding Orientation Placement:**

The top-left corner position can be described using two independent axes:

1. **Proximity to Ribbon**: "Next to ribbon" vs "Away from ribbon" (opposite edge)
2. **Left/Right Side**: Which side of the display when viewing normally

This gives four possible positions:
- **ORIENTATION_0** (ribbon BOTTOM): Away from ribbon, LEFT side
- **ORIENTATION_90** (ribbon LEFT): Next to ribbon, LEFT side
- **ORIENTATION_180** (ribbon TOP): Next to ribbon, RIGHT side
- **ORIENTATION_270** (ribbon RIGHT): Away from ribbon, RIGHT side

Note: ORIENTATION_0 and ORIENTATION_270 use the same transformation (`x = (7-col) * 16, y = row * 16`) but different remap registers produce different results. Similarly, ORIENTATION_90 and ORIENTATION_180 share transformations but differ in remap values.

**Critical Implementation Details:**

1. **Remap Register Values**:
   - All values use bit 2=0 (RGB mode) because software handles BGR565 conversion
   - All values use bit 5=1 (COM split odd/even enabled)
   - Values differ in bits 0, 1, 4 to control hardware scan direction and mirroring

2. **Software Coordinate Transformations**:
   Two-stage transformation process for sensor data to display mapping:

   **Stage 1 - Sensor Data Normalization (applied to all orientations):**
   ```
   temp_row := col          ' 90° clockwise rotation
   temp_col := row          ' Swap row/col coordinates
   ```

   **Stage 2 - Orientation-Specific Positioning:**
   - **ORIENTATION_0** (ribbon BOTTOM): `x = (7-temp_col) * 16, y = temp_row * 16`
   - **ORIENTATION_90** (ribbon LEFT): `x = (7-temp_col) * 16, y = (7-temp_row) * 16`
   - **ORIENTATION_180** (ribbon TOP): `x = (7-temp_col) * 16, y = (7-temp_row) * 16`
   - **ORIENTATION_270** (ribbon RIGHT): `x = (7-temp_col) * 16, y = temp_row * 16`

   This two-stage approach separates sensor layout normalization from display orientation control.

3. **Color Format**: Software converts to BGR565
   - `color := ((b >> 3) << 11) | ((g >> 2) << 5) | (r >> 3)`
   - Blue in MSB (bits 15-11), Red in LSB (bits 4-0)
   - Hardware set to RGB mode, software does BGR conversion

4. **Pixel Ordering**: Always send pixels in **row-major order**
   - For each cell: row 0 (all columns), row 1 (all columns), etc.
   - Hardware expects sequential pixel data row-by-row

### Orientation Test Results (November 2025)

**Test Methodology:**
- Test pattern: 4 corner markers (buffer[0]=RED, buffer[7]=YELLOW, buffer[56]=GREEN, buffer[63]=BLUE)
- Diagonal indicator at buffer[9]=RED to mark origin (0,0)
- Cyan background (value=1500) for contrast
- All tests showed perfect corner alignment (no row/column shifts)

**Observed Results:**

| Orientation | Remap Value | Ribbon Position | (0,0) Physical Location | (0,0) Display Color | Notes |
|-------------|-------------|-----------------|-------------------------|---------------------|-------|
| **ORIENTATION_0** | `$65` | BOTTOM | Bottom-Left | BLUE | ⚠️ Expected RED, got BLUE |
| **ORIENTATION_90** | `$76` | RIGHT | Top-Right | BLUE | ⚠️ Expected RED, got BLUE |
| **ORIENTATION_180** | `$62` | TOP | Top-Left | RED | ✓ Color matches buffer[0] |
| **ORIENTATION_270** | `$71` | LEFT | Bottom-Right | RED | ✓ Color matches buffer[0] |

**Key Observations:**

1. **Corner Alignment**: All four orientations show perfect corner alignment (no spatial shifts)

2. **Color Inconsistency (CRITICAL ISSUE)**:
   - ORIENTATION_180 and ORIENTATION_270: Display RED at (0,0) as expected (buffer[0]=RED)
   - ORIENTATION_0 and ORIENTATION_90: Display BLUE at (0,0) instead of RED
   - This suggests buffer[63] (BLUE) is being mapped to (0,0) instead of buffer[0] (RED)

3. **Rotation Anomaly**:
   - Expected: 90° rotations should move (0,0) to **adjacent** corners
   - Observed: ORIENTATION_270 to ORIENTATION_180 moved (0,0) from Bottom-Right to Top-Left (diagonal opposite)
   - This suggests unexpected mirroring or buffer reversal in certain orientations

**Issues Requiring Investigation:**

1. **Color Mapping Reversal**: Why do ORIENTATION_0 and ORIENTATION_90 show buffer[63] instead of buffer[0]?
   - Possible causes: Buffer reading direction, unexpected mirroring, remap register side effects

2. **Coordinate Jump Pattern**: Why does (0,0) jump diagonally instead of rotating to adjacent corners?
   - May indicate combination of rotation + unexpected horizontal/vertical flip

3. **Remap Register Configuration**: Are the remap values (`$65`, `$76`, `$62`, `$71`) correct for intended behavior?
   - Need to verify against SSD1351 datasheet sections on:
     - Bit 0: Column address remap
     - Bit 4: COM scan direction
     - Bit 5: COM split odd/even
     - Combined effects of multiple bits

**Root Cause Analysis (Datasheet Section 10.1.5):**

The remap register (command `$A0`) controls multiple aspects simultaneously:
- **Bit A[0]**: Address increment mode (0=horizontal, 1=vertical RAM access)
- **Bit A[1]**: Column address remap (0=SEG0→127, 1=SEG127→0)
- **Bit A[2]**: Color sequence (0=RGB, 1=BGR)
- **Bit A[4]**: COM scan direction (0=top→bottom, 1=bottom→top)
- **Bit A[5]**: COM split odd/even (always 1 for this display)
- **Bit A[7:6]**: Color depth (01=65K, 10=262K)

**Key Finding**: Combined effects of bits A[0], A[1], and A[4] cause buffer reading order to reverse in certain orientations. When bit A[0] (address increment) is set to vertical mode (1) AND other bits are configured, the hardware reads buffer data from the opposite end.

**Alternative Remap Values Comparison:**

Another source provides these values (comparison with current project values):

| Orientation | Current | Alternative | Bit A[4] Change | Bit A[1] Change | Bit A[0] Change |
|-------------|---------|-------------|-----------------|-----------------|-----------------|
| **0°**      | `$65`   | `$74`       | 0→1 (inverted)  | Same (0)        | 1→0 (inverted)  |
| **90°**     | `$76`   | `$77`       | Same (1)        | Same (1)        | 0→1 (inverted)  |
| **180°**    | `$62`   | `$76`       | 0→1 (inverted)  | 0→1 (added)     | Same (0)        |
| **270°**    | `$71`   | `$75`       | Same (1)        | 0→1 (added)     | Same (1)        |

**Pattern Analysis:**

Current values show **inconsistent bit A[0]** usage:
- 0°: Vertical (1), 90°: Horizontal (0), 180°: Horizontal (0), 270°: Vertical (1)
- This inconsistency correlates with buffer reading order reversal

Alternative values use **consistent pattern**:
- All bits [7:6]=01 (65K), [5]=1 (COM split), [2]=1 (BGR)
- Systematic rotation via bits [4], [1], [0]
- May resolve buffer order issues by maintaining consistent increment mode

**Recommendation**: Test alternative values `$74`, `$77`, `$76`, `$75` to determine if they provide consistent buffer[0]→(0,0) mapping across all orientations.

**Coordinate Mapping (ORIENTATION_270, Ribbon LEFT):**
```
Physical Display (Ribbon at LEFT):
┌────────────────┐
│(7,0)       (7,7)│  ← Top edge
│                 │
R   Display       │
i                 │
b (0,0)       (0,7)│  ← Bottom edge
b └────────────────┘
o
n
```

**Standard Orientation (ORIENTATION_0, Ribbon BOTTOM):**
```
Physical Display (Ribbon at Bottom):
┌────────────────┐
│(0,0)     (127,0)│  ← Top edge
│                 │
│    Display      │
│                 │
│(0,127) (127,127)│  ← Bottom edge
└────────────────┘
      Ribbon
```

## Display Capabilities

### Graphics Features
- Hardware scrolling support
- Programmable frame rate
- Contrast adjustment (256 levels)
- Display rotation (0°, 90°, 180°, 270°)
- Partial display updates
- Hardware acceleration for basic drawing operations

### Color Mapping for Magnetic Visualization
- **Neutral Field**: Black background
- **Positive Field**: Green gradient (0x0000 to 0x07E0)
- **Negative Field**: Red gradient (0x0000 to 0xF800)
- **Intensity Mapping**: Direct correlation to measured field strength

## Integration Considerations

### Power Management
- Display can be powered down via command for power saving
- Implement screen timeout for extended idle periods
- Consider ambient light sensor for automatic brightness adjustment

### Update Rate Requirements
- **Display Refresh Rate**: 60 Hz (hardware limit)
- **SPI Transfer Time**: 2.8ms per full 128×128 frame at 20MHz
- **Maximum Send Rate**: ~357 fps (limited by SPI transfer)
- **Practical Frame Rate**: 60 fps (matched to display refresh rate)
- **Recommended Delay**: 16ms between frames to prevent display flooding
- **Sensor Scan Rate**: Will determine actual update frequency

### Memory Requirements
- Full frame buffer: 128×128×2 bytes = 32KB (16-bit color)
- Double buffering recommended for smooth updates
- P2 Hub RAM allocation: ~64KB for display subsystem

## References
- [Waveshare Wiki Page](https://www.waveshare.com/wiki/1.5inch_RGB_OLED_Module)
- [SSD1351 Datasheet](https://www.waveshare.com/w/upload/5/5b/SSD1351-Revision_1.3.pdf)
- Module supports both 3.3V and 5V operation but voltage must be consistent across all pins