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
| **0° (Default)** | `$65` | BOTTOM | Standard orientation, (0,0) at top-left |
| **90°** | `$76` | RIGHT | Rotated 90° clockwise |
| **180°** | `$62` | TOP | Upside down |
| **270°** | `$71` | LEFT | Rotated 90° counter-clockwise |

**ORIENTATION_270 Details (Ribbon LEFT - Project Configuration):**
- Remap value: `$71`
  - Bit 7:6 = `01` → 65K BGR color format (⚠️ Note: BGR not RGB!)
  - Bit 6 = `1` → 65K color mode
  - Bit 5 = `1` → Enable COM split odd/even
  - Bit 4 = `1` → Reverse COM scan direction (bottom to top)
  - Bit 0 = `1` → Column address remap enabled

**Critical Implementation Details for ORIENTATION_270:**

1. **Color Format**: SSD1351 expects **BGR565**, not RGB565
   - Bit packing: `[B4:B0][G5:G0][R4:R0]` (blue MSB, red LSB)
   - Must swap red/blue channels during color conversion

2. **Pixel Ordering**: Must send pixels in **row-major order**
   - Hardware expects: row 0 (all columns), row 1 (all columns), etc.
   - Incorrect column-major order causes incomplete/scrambled fills

3. **Coordinate Transformation**: Columns are **horizontally mirrored**
   - Buffer column 0 → Physical right edge
   - Buffer column 7 → Physical left edge
   - Software must reverse: `x = (7 - col) * CELL_WIDTH`

4. **Hardware Offset**: Display has built-in 2-cell offset
   - ROW_OFFSET = -32 (pixels) required to align corners
   - COLUMN_OFFSET = 0 for this orientation
   - **Note**: With 270° rotation, ROW affects horizontal (columns), COLUMN affects vertical (rows)

**⚠️ Orientation-Specific Offsets:**
Testing has confirmed values for ORIENTATION_270 only. Other orientations (0°, 90°, 180°) will require diagnostic testing to determine their specific offset values. The coordinate transformation and offset requirements are orientation-dependent.

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