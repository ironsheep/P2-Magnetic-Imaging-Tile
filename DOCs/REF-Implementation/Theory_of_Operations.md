# Theory of Operations: SparkFun Magnetic Imaging Tile - Example1_BasicReadings

## Overview

The Example1_BasicReadings Arduino sketch provides a comprehensive interface for the SparkFun Magnetic Imaging Tile V3, an 8x8 array of Hall effect sensors capable of visualizing magnetic fields in real-time. The code implements multiple operational modes and data acquisition strategies optimized for different use cases.

## Hardware Architecture

### Sensor Array Organization
- **64 Hall Effect Sensors**: Arranged in an 8x8 grid with 4mm spacing
- **4 Subtiles**: Physical organization into quadrants for efficient readout
- **Sequential Multiplexing**: Hardware counter controls which sensor is active

### Interface Connections
- **Analog Input (A1)**: Primary ADC input for magnetic field readings
- **Digital Control Lines**:
  - PIN_CLR (8): Counter clear/reset signal
  - PIN_CLK (9): Counter increment clock
- **SPI Interface for AD7940**:
  - MISO (12): Data input from external 14-bit ADC
  - CS (10): Chip select
  - CLK (13): SPI clock

## Data Acquisition Methods

### 1. Internal ADC Mode
- **Resolution**: Platform-dependent (typically 10-12 bit)
- **Sampling**: 2-sample averaging for noise reduction
- **Speed**: Moderate, limited by Arduino analogRead() performance

### 2. External AD7940 ADC Mode
- **Resolution**: 14-bit precision
- **Interface**: Bit-banged SPI implementation
- **Speed**: Optimized for high frame rates (up to 2000 fps)
- **Data Format**: 16-bit reads with 14-bit useful data

## Operational Modes

### MODE_LIVE (L)
- **Purpose**: Real-time visualization
- **Operation**: Continuous frame capture and immediate serial output
- **Use Case**: Interactive magnetic field observation

### MODE_HIGHSPEED1 (H/1)
- **Purpose**: Maximum frame rate capture
- **Operation**: Records MAX_FRAMES at full speed, then playback
- **Frame Rate**: ~2000 fps (hardware limited)
- **Memory**: Uses full available frame buffer

### MODE_HIGHSPEED2-4 (2/3/4)
- **Purpose**: Controlled frame rate capture
- **Frame Rates**:
  - Mode 2: ~1000 Hz (1ms delay)
  - Mode 3: ~500 Hz (2ms delay)
  - Mode 4: ~250 Hz (4ms delay)
- **Use Case**: Synchronized acquisition with external events

### MODE_PIXEL (P)
- **Purpose**: Single pixel testing and calibration
- **Operation**: Reads individual sensor for diagnostic purposes

### MODE_IDLE (S)
- **Purpose**: Standby state
- **Operation**: No active data acquisition, awaits user commands

## Frame Buffer Management

### Memory Allocation
- **Arduino Uno/Nano**: 2 frames maximum (limited 2KB RAM)
- **SAMD21/Teensy/ChipKit**: 100-500 frames (32KB+ RAM available)

### Data Storage Options
- **16-bit Mode**: Full resolution storage (default)
- **8-bit Mode**: Compressed storage (4x more frames, 2-bit right shift)

### Frame Structure
```
Frame[64] = {
  [0-7]:   Row 0 (sensors 0-7)
  [8-15]:  Row 1 (sensors 8-15)
  ...
  [56-63]: Row 7 (sensors 56-63)
}
```

## Sensor Readout Sequence

### Hardware Control Flow
1. **Counter Reset**: Assert PIN_CLR to initialize multiplexer
2. **Initial Increment**: Single clock pulse to start sequence
3. **Sequential Reading**: For each of 4 subtiles:
   - Read 16 sensors in predetermined order
   - Clock PIN_CLK after each reading to advance multiplexer
4. **Data Mapping**: Apply pixelOrder[] and subtileOrder[] lookup tables

### Pixel Ordering Algorithm
- **pixelOrder[]**: Maps physical sensor sequence to logical grid positions
- **subtileOrder[]**: Defines quadrant reading sequence (0,2,1,3)
- **subtileOffset[]**: Base addresses for each quadrant (0,4,32,36)

## Serial Communication Protocol

### Command Interface
- **Baud Rate**: 115200
- **Commands**: Single character triggers
  - 'L': Live mode
  - 'H'/'1': High-speed mode 1
  - '2'-'4': High-speed modes 2-4
  - 'S': Stop/idle
  - 'P': Pixel test

### Data Output Format
```
val0 val1 val2 ... val7
val8 val9 val10 ... val15
...
val56 val57 val58 ... val63
*
```
- Space-separated decimal values
- 8 values per line (one row)
- Asterisk (*) marks frame end

## Performance Characteristics

### Frame Rate Limitations
- **ADC Speed**: Primary bottleneck for data acquisition
- **Serial Bandwidth**: Secondary limitation for live streaming
- **Memory Access**: Minimal impact due to efficient buffering

### Platform Optimization
- **ChipKit MAX32**: Original target platform, 128KB RAM
- **SAMD21**: Modern alternative with comparable performance
- **Arduino Uno**: Functional but severely memory-constrained

## Use Cases and Applications

### Scientific Visualization
- Real-time magnetic field imaging
- Motor and transformer analysis
- Permanent magnet characterization

### High-Speed Capture
- Transient magnetic event recording
- 60Hz transformer field analysis
- Moving magnet tracking

### Educational Demonstrations
- Magnetic field visualization for teaching
- Interactive physics experiments
- STEM outreach activities

## Implementation Notes

### Critical Timing Considerations
- Minimal delays in sensor readout loop for maximum frame rate
- Optimized counter control signals (commented delays removed)
- Platform-specific serial interface selection

### Memory Management
- Conditional compilation for 8-bit vs 16-bit storage
- Platform-aware frame buffer sizing
- Efficient data copying during high-speed capture

### Error Handling
- Hardware initialization verification
- Serial communication timeout handling
- Mode state management and recovery