# P2 Magnetic Imaging Tile

A Propeller 2 (P2) implementation for interfacing with the SparkFun Magnetic Imaging Tile V3, providing real-time magnetic field visualization and high-speed data acquisition.

## Overview

The SparkFun Magnetic Imaging Tile V3 is an 8×8 array of Hall effect sensors capable of visualizing magnetic fields in real-time. This project implements a complete P2-based interface system that can capture magnetic field data at rates up to 2000 fps and provide real-time visualization through VGA/HDMI output.

## Hardware Components

### SparkFun Magnetic Imaging Tile V3
- 64 Hall effect sensors arranged in 8×8 grid (4mm spacing)
- 4 subtiles for efficient readout organization
- Hardware multiplexer for sequential sensor selection
- AD7940 14-bit external ADC for high-precision measurements

### Propeller 2 Interface

#### Pin Connections
**Pin Group**: 48 (P48-P55)

```
Pin    | Function        | Wire Color | Description
-------|-----------------|------------|---------------------------
+0     | CS              | VIOLET     | AD7940 Chip Select
+1     | CCLK            | WHITE      | Counter Clock (sensor mux)
+2     | MISO            | BLUE       | AD7940 Data Input
+3     | CLRb            | GRAY       | Counter Clear (sensor mux)
+4     | SCLK            | GREEN      | AD7940 SPI Clock
+6     | AOUT            | YELLOW     | Analog Input (optional)
GND    | Ground          | BLACK      | Ground connection
3.3V   | VCC             | RED        | Power supply
```

## Features

### Data Acquisition
- **Multiple ADC Support**: P2 internal ADC and external AD7940 14-bit ADC
- **High-Speed Capture**: Up to 2000 fps frame rates
- **Flexible Modes**: Live streaming, high-speed burst capture, single pixel testing
- **Frame Buffering**: Extensive buffering using P2's 512KB Hub RAM

### Visualization
- **Real-Time Display**: VGA/HDMI output for live magnetic field visualization
- **Dual Sensitivity**: Normal and 10× amplified displays
- **Color Mapping**: Bipolar visualization (red for negative, green for positive fields)
- **Background Calibration**: Adaptive baseline correction for improved accuracy

### Communication
- **Serial Interface**: 115200 baud bidirectional communication
- **Command Protocol**: Single character commands for mode control
- **Data Output**: Space-separated ASCII format compatible with existing tools

## Operational Modes

| Mode | Command | Description | Frame Rate |
|------|---------|-------------|------------|
| Live | L | Continuous real-time streaming | Limited by serial bandwidth |
| High-Speed 1 | 1 | Maximum speed burst capture | ~2000 Hz |
| High-Speed 2 | 2 | Controlled rate capture | ~1000 Hz |
| High-Speed 3 | 3 | Controlled rate capture | ~500 Hz |
| High-Speed 4 | 4 | Controlled rate capture | ~250 Hz |
| Stop | S | Idle/standby mode | - |
| Pixel Test | P | Single sensor diagnostic | - |

## Data Format

### Frame Structure
Each frame contains 64 sensor readings arranged as an 8×8 grid:
```
val0 val1 val2 val3 val4 val5 val6 val7
val8 val9 val10 val11 val12 val13 val14 val15
...
val56 val57 val58 val59 val60 val61 val62 val63
*
```
- 8 space-separated values per line (one row)
- 8 lines per frame
- Asterisk (*) marks frame completion

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

- **[Theory of Operations](DOCs/REF-Implementation/Theory_of_Operations.md)** - Comprehensive system overview
- **[Communication Protocol](DOCs/REF-Implementation/Communication_Protocol.md)** - Hardware interface details
- **[Visualization System](DOCs/REF-Implementation/Processing_Visualization_Theory_of_Operations.md)** - Display implementation guide
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
- Propeller 2 development board
- SparkFun Magnetic Imaging Tile V3
- VGA/HDMI display capability
- Serial communication interface

### Software Tools
- Propeller 2 development environment
- PNut or FlexProp compiler
- Serial terminal application
- Optional: Processing IDE for PC-based visualization

## Getting Started

1. **Hardware Setup**: Connect the magnetic imaging tile to P2 using the pinout above
2. **Compile Code**: Use PNut or FlexProp to compile the P2 source code (when available)
3. **Load Program**: Upload the compiled binary to P2
4. **Connect Display**: Attach VGA/HDMI monitor for real-time visualization
5. **Test Communication**: Use serial terminal at 115200 baud to send commands

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

- SparkFun Electronics for the Magnetic Imaging Tile hardware design
- Parallax Inc. for the Propeller 2 microcontroller
- Original Arduino implementation authors for reference documentation

## Contact

**Project Maintainer**: Stephen M Moraco
**Organization**: Iron Sheep Productions LLC

For questions, issues, or contributions, please use the project's issue tracking system.
