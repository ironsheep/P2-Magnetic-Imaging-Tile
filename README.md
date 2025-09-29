# P2 Magnetic Imaging Tile

![Project Maintenance][maintenance-shield]

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Propeller 2 (P2) implementation for interfacing with the SparkFun Magnetic Imaging Tile V3, providing real-time magnetic field visualization and high-speed data acquisition.

## Overview

The SparkFun Magnetic Imaging Tile V3 is an 8×8 array of Hall effect sensors capable of visualizing magnetic fields in real-time. This project creates a complete P2-based interface system with two primary objectives:

**Primary Purpose**: Create a low-hardware-cost magnetic field visualizer using minimal components (P2 + magnetic tile + OLED display)

**Secondary Purpose**: Determine the maximum achievable frame rate using Propeller 2 hardware with this sensor configuration

## Hardware Components

### Primary Components

- **[SparkFun Magnetic Imaging Tile V3](DOCs/Magnetic-Tile-Hardware.md)** - 8×8 Hall effect sensor array
- **[Waveshare 1.5" RGB OLED Module](DOCs/OLED-Display-Hardware.md)** - 128×128 pixel display
- **Propeller 2 Development Board** - Main controller

### Quick Reference

**Magnetic Tile Connection (Pin Group 40: P40-P47)**
```
Pin    | Function        | Wire Color | Description
-------|-----------------|------------|---------------------------
P40 (+0) | CS           | VIOLET     | AD7940 Chip Select
P41 (+1) | CCLK         | WHITE      | Counter Clock (sensor mux)
P42 (+2) | MISO         | BLUE       | AD7940 Data Input
P43 (+3) | CLRb         | GRAY       | Counter Clear (sensor mux)
P44 (+4) | SCLK         | GREEN      | AD7940 SPI Clock
P46 (+6) | AOUT         | YELLOW     | Analog Input (optional)
GND    | Ground         | BLACK      | Ground connection
3.3V   | VCC            | RED        | Power supply
```

**OLED Display Connection (Pin Group 24: P24-P31)**
```
Pin    | Function        | Description
-------|-----------------|---------------------------
P24 (+0) | DIN          | SPI data output (MOSI)
P26 (+2) | CLK          | SPI clock (SCLK)
P28 (+4) | CS           | Chip Select (active low)
P30 (+6) | DC           | Data/Command select
P31 (+7) | RST          | Reset (active low)
GND    | Ground         | Ground connection
3.3V   | VCC            | Power supply
```

For detailed hardware specifications, see:
- [Magnetic Tile Hardware Documentation](DOCs/Magnetic-Tile-Hardware.md)
- [OLED Display Hardware Documentation](DOCs/OLED-Display-Hardware.md)

## Features

### Data Acquisition

- **Low-Cost Design**: Minimal hardware components for cost-effective implementation
- **Dual ADC Support**: P2 internal ADC and external AD7940 14-bit ADC for performance comparison
- **Maximum Frame Rate Testing**: Benchmark P2 performance limits with this sensor configuration
- **Frame Buffering**: Extensive buffering using P2's 512KB Hub RAM

### Visualization

- **Primary Display**: 128×128 OLED (SPI) for compact real-time visualization
- **Secondary Display**: HDMI output for expanded visualization
- **Debug Logging**: Serial output for driver verification and troubleshooting
- **Dual Sensitivity**: Normal and 10× amplified displays
- **Color Mapping**: Bipolar visualization (red for negative, green for positive fields)
- **Background Calibration**: Adaptive baseline correction for improved accuracy

### Communication

- **SPI Interface**: Direct hardware connection for sensor data and display output
- **Control Interface**: TBD - possibly debug console for device control
- **Live Display**: Real-time magnetic field visualization without external commands

## Operational Modes

**Initial Implementation**: Live continuous scanning with real-time OLED display

| Mode | Description | Frame Rate |
|------|-------------|------------|
| Live Scan | Continuous real-time magnetic field visualization | Limited by display refresh |
| High-Speed | Maximum speed capture and display | Up to 2000 Hz |
| Debug | Single sensor diagnostic via debug console | Variable |

*Note: Command interface for mode switching is under development*

## Data Format

### Frame Structure

Each frame contains 64 sensor readings arranged as an 8×8 grid, processed internally and displayed directly on the OLED screen:

```
[0,0] [0,1] [0,2] [0,3] [0,4] [0,5] [0,6] [0,7]
[1,0] [1,1] [1,2] [1,3] [1,4] [1,5] [1,6] [1,7]
...
[7,0] [7,1] [7,2] [7,3] [7,4] [7,5] [7,6] [7,7]
```

- 64 sensor values per frame
- Real-time color mapping for OLED display
- Internal processing without external data output

## Project Status

**Current Phase**: Documentation and Planning

This project is currently in the initial development phase. Comprehensive documentation has been created based on the Arduino reference implementation:

- ✅ Hardware interface specifications
- ✅ Communication protocol definition
- ✅ System architecture design
- ⏳ P2 source code implementation
- ⏳ VGA/HDMI display system
- ⏳ Testing and validation

## Documentation

Detailed technical documentation is available in the `DOCs/` directory:

### Hardware Specifications
- **[Magnetic Tile Hardware](DOCs/Magnetic-Tile-Hardware.md)** - Detailed sensor array specifications
- **[OLED Display Hardware](DOCs/OLED-Display-Hardware.md)** - Display module specifications

### Reference Implementation
- **[Theory of Operations](DOCs/REF-Implementation/Theory_of_Operations.md)** - Comprehensive system overview
- **[Communication Protocol](DOCs/REF-Implementation/Communication_Protocol.md)** - Hardware interface details
- **[Visualization System](DOCs/REF-Implementation/Processing_Visualization_Theory_of_Operations.md)** - Display implementation guide

### Technical Datasheets
- **[Hardware Schematics](DOCs/Magnetic_Imaging_Tile_Schematic_V10.pdf)** - Circuit diagrams
- **[IC Datasheet](DOCs/AD7680.pdf)** - AD7940 ADC specifications

## Applications

### Scientific Research

- Real-time magnetic field visualization
- Motor and transformer analysis
- Permanent magnet characterization
- Electromagnetic interference detection

### Educational Use

- Physics demonstrations
- STEM outreach activities
- Interactive magnetic field exploration
- Engineering design validation

### Industrial Applications
- Quality control testing
- Magnetic component inspection
- Research and development tools
- Prototype validation

## Development Requirements

### Hardware
- Propeller 2 development board (choose one):
  - [P2 Edge Module with Breakout Board Bundle](https://www.parallax.com/product/p2-edge-module-with-p2-edge-breakout-board-bundle/)
  - [Propeller 2 Mini Starter Bundle](https://www.parallax.com/product/propeller-2-mini-starter-bundle/)
- SparkFun Magnetic Imaging Tile V3 - [SparkFun](https://www.sparkfun.com/sparkfun-magnetic-imaging-tile-8x8.html)
- Waveshare 1.5inch RGB OLED Module - [Waveshare](https://www.waveshare.com/1.5inch-rgb-oled-module.htm)
- HDMI display capability (optional secondary display) - [Amazon](https://www.amazon.com/HMTECH-Raspberry-800x480-Dual-Speaker-Non-Touch/dp/B0C6963887)
  - [P2 Eval Digital Video Out Add-on Board](https://www.parallax.com/product/p2-eval-digital-video-out-add-on-board/) (HDMI adapter for P2)

### Software Tools
- Propeller 2 development environment
- PNut or FlexProp compiler
- Serial terminal application
- Debug console for development and diagnostics

## Getting Started

1. **Hardware Setup**: Connect the magnetic imaging tile to P2 using the pinout above
2. **Display Setup**: Connect 128×128 OLED display via SPI for primary visualization
3. **Compile Code**: Use PNut or FlexProp to compile the P2 source code (when available)
4. **Load Program**: Upload the compiled binary to P2
5. **Operation**: Device will automatically start live scanning and display magnetic fields
6. **Optional**: Connect HDMI display for secondary visualization

## Contributing

This is an open-source project under the MIT License. Contributions are welcome for:
- P2 source code implementation
- Performance optimization
- Feature enhancements
- Documentation improvements
- Testing and validation

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [SparkFun Electronics](https://www.sparkfun.com/) for the Magnetic Imaging Tile hardware design
- [Parallax Inc.](https://www.parallax.com/) for the Propeller 2 microcontroller
- [Original Arduino implementation authors](https://github.com/sparkfun/SparkFun_Magnetic_Imaging_Tile) for reference documentation

## Contact

**Project Maintainer**: Stephen M Moraco
**Organization**: Iron Sheep Productions LLC

For questions, issues, or contributions, please use the project's issue tracking system.

---

> If you like my work and/or this has helped you in some way then feel free to help me out for a couple of :coffee:'s or :pizza: slices or support my work by contributing at Patreon!
>
> [![coffee](https://www.buymeacoffee.com/assets/img/custom_images/black_img.png)](https://www.buymeacoffee.com/ironsheep) &nbsp;&nbsp; -OR- &nbsp;&nbsp; [![Patreon](./DOCs/images/patreon.png)](https://www.patreon.com/IronSheep?fan_landing=true)[Patreon.com/IronSheep](https://www.patreon.com/IronSheep?fan_landing=true)

---

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge
