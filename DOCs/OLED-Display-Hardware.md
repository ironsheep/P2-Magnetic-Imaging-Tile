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

**Pin Group**: 24 (P24-P31)

| P2 Pin | Signal | Function | Direction | Description |
|--------|--------|----------|-----------|-------------|
| P24 (+0) | DIN | MOSI | Output | SPI data output to display |
| P26 (+2) | CLK | SCLK | Output | SPI clock signal |
| P28 (+4) | CS | Chip Select | Output | Active low chip select |
| P30 (+6) | DC | Data/Command | Output | High=Data, Low=Command |
| P31 (+7) | RST | Reset | Output | Active low reset signal |
| GND | GND | Ground | - | Ground reference |
| 3.3V | VCC | Power | - | 3.3V power supply |

- Pin group allocation allows efficient Smart Pin configuration
- Separate from magnetic tile interface (Pin Group 48)

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
- Target: 30-60 fps for smooth visualization
- Maximum theoretical: >100 fps with optimized SPI transfer
- Practical limit determined by sensor scan rate

### Memory Requirements
- Full frame buffer: 128×128×2 bytes = 32KB (16-bit color)
- Double buffering recommended for smooth updates
- P2 Hub RAM allocation: ~64KB for display subsystem

## References
- [Waveshare Wiki Page](https://www.waveshare.com/wiki/1.5inch_RGB_OLED_Module)
- [SSD1351 Datasheet](https://www.waveshare.com/w/upload/5/5b/SSD1351-Revision_1.3.pdf)
- Module supports both 3.3V and 5V operation but voltage must be consistent across all pins