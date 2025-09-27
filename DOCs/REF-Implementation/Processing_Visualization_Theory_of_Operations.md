# Theory of Operations: Processing Magnetic Field Visualization Application

## Executive Summary

The Processing visualization application (`magtile_processing_visualization.pde`) provides real-time magnetic field visualization for the SparkFun Magnetic Imaging Tile. It implements a dual-sensitivity display system with background calibration, bidirectional serial communication, and interactive control interface. This document provides comprehensive implementation details for recreating the system on the Propeller 2 platform.

## System Architecture

### Core Components
1. **Serial Communication Engine**: Bidirectional Arduino ↔ Processing data exchange
2. **Data Processing Pipeline**: Parse, calibrate, and normalize sensor readings
3. **Dual Visualization System**: Normal and high-sensitivity magnetic field displays
4. **Interactive Control Interface**: Keyboard-driven mode control and calibration
5. **Background Calibration System**: Adaptive noise reduction and baseline correction

### Application Flow
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Arduino/P2    │───▶│ Serial Data      │───▶│ Processing App  │
│ Sensor Reading  │    │ Transmission     │    │ Visualization   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         ▲                                               │
         │              ┌──────────────────┐             │
         └──────────────│ Control Commands │◀────────────┘
                        │   (L,1-4,S,C)    │
                        └──────────────────┘
```

## Serial Communication Protocol

### Data Reception Format
**Protocol**: Arduino transmits 8x8 frame data as space-separated ASCII values

```
Format per line: "val0 val1 val2 val3 val4 val5 val6 val7\n"
Frame structure:
Line 0: Row 0 sensors (8 values)
Line 1: Row 1 sensors (8 values)
...
Line 7: Row 7 sensors (8 values)
Frame terminator: "*\n"

Example frame transmission:
"245 250 248 252 249 247 251 250\n"
"248 251 249 250 247 252 248 251\n"
...
"250 249 251 248 252 250 247 249\n"
"*\n"
```

### Data Parsing Algorithm
```java
void serialEvent(Serial port) {
  String input = port.readStringUntil(char(10));  // Read until newline

  if (input != null) {
    input = input.trim();
    float[] vals = float(splitTokens(input, " "));  // Parse space-separated values

    if (vals.length == MAX_SIZE) {  // Validate 8 values per line
      // Store row data
      for (int i=0; i<MAX_SIZE; i++) {
        data[curDataIdx][i] = int(vals[i]);
      }
      curDataIdx++;  // Advance to next row
    }

    if (curDataIdx >= MAX_SIZE) {  // Complete frame received
      curDataIdx = 0;  // Reset for next frame
      // Process complete 8x8 frame
    }
  }
}
```

### Command Transmission Protocol
**Direction**: Processing → Arduino
**Format**: Single character + newline

```
Command Set:
'L' + '\n' → Live mode (continuous streaming)
'1' + '\n' → High-speed capture mode 1 (~2000Hz)
'2' + '\n' → High-speed capture mode 2 (~1000Hz)
'3' + '\n' → High-speed capture mode 3 (~500Hz)
'4' + '\n' → High-speed capture mode 4 (~250Hz)
'S' + '\n' → Stop/idle mode
'P' + '\n' → Single pixel test mode
```

## Data Storage and Management

### Primary Data Structure
```java
int MAX_SIZE = 8;
int[][] data = new int[MAX_SIZE][MAX_SIZE];  // Current frame buffer
int curDataIdx = 0;                          // Current row being filled
```

### Calibration Data Structure
```java
int[][] dataCalib = new int[MAX_SIZE][MAX_SIZE];  // Background calibration values
int numCalibFrames = 0;                           // Calibration frame counter
int maxCalibFrames = 200;                         // Frames to average for calibration
int calibrationEnabled = 0;                       // Calibration state flag
int isCalibrated = 0;                            // Background data available flag
```

### Data Flow States
1. **Raw Data Acquisition**: Direct sensor values stored in `data[][]`
2. **Calibration Accumulation**: Values summed in `dataCalib[][]` during calibration
3. **Background Subtraction**: `(data[i][j] - dataCalib[i][j])` for final display

## Visualization Rendering System

### Dual Display Architecture
**Layout**: Two 8x8 grids displayed vertically
- **Top Grid** (Normal Sensitivity): Standard magnetic field visualization
- **Bottom Grid** (High Sensitivity): 10x amplified visualization for weak fields

### Color Mapping Algorithm

#### Normal Sensitivity Display
```java
// ADC scaling constants
float MAX_VALUE = 660.0f;  // ChipKit internal ADC full scale

if (isCalibrated == 1) {
  // Calibrated mode: Background subtraction
  float value = ((float)data[i][j] - (float)dataCalib[i][j]) / MAX_VALUE;
  float intensity = int(255 * value);

  if (value < 0.0) {
    fill(-intensity, 0, 0);  // Red for negative fields
  } else {
    fill(0, intensity, 0);   // Green for positive fields
  }
} else {
  // Uncalibrated mode: Bipolar around midpoint
  float value = (float)data[i][j] / MAX_VALUE;
  float intensity = int(floor(255 * abs(value - 0.50f)));

  if (value < 0.50) {
    fill(intensity, 0, 0);   // Red for below midpoint
  } else {
    fill(0, intensity, 0);   // Green for above midpoint
  }
}
```

#### High Sensitivity Display
```java
// 10x sensitivity amplification (3000 vs 255)
if (isCalibrated == 1) {
  float value = ((float)data[i][j] - (float)dataCalib[i][j]) / MAX_VALUE;
  float intensity = int(3000 * value);  // 10x amplification
} else {
  float value = (float)data[i][j] / MAX_VALUE;
  float intensity = int(floor(3000 * abs(value - 0.50f)));  // 10x amplification
}
```

### Coordinate System and Pixel Mapping
```java
// Grid parameters
int pixelsize = 30;          // 30x30 pixel squares
int offset_x = 10;           // Left margin
int offset_y = 10;           // Top margin (normal display)
int offset_y_high = 450;     // Top margin (high sensitivity display)

// Coordinate transformation
for (int i=0; i<MAX_SIZE; i++) {
  for (int j=0; j<MAX_SIZE; j++) {
    int y = (MAX_SIZE-i) * pixelsize;  // Flip Y-axis (top-to-bottom)
    int x = (MAX_SIZE-j) * pixelsize;  // Flip X-axis (right-to-left)

    rect(x + offset_x, y + offset_y, pixelsize, pixelsize);
  }
}
```

## Background Calibration System

### Calibration Process
**Purpose**: Remove sensor offset variations and environmental background fields
**Method**: Statistical averaging over multiple frames

### Calibration Workflow
```java
1. User presses 'C' key
2. calibrationEnabled = 1
3. For next 200 frames:
   - Accumulate sensor values: dataCalib[i][j] += data[i][j]
4. After 200 frames:
   - Average: dataCalib[i][j] = dataCalib[i][j] / 200
   - Set isCalibrated = 1
   - Switch to background-subtracted display mode
```

### Mathematical Operations
```java
// During calibration accumulation
if (calibrationEnabled == 1) {
  dataCalib[curDataIdx][i] += int(vals[i]);
}

// After calibration completion
void calibration() {
  for (int i=0; i<MAX_SIZE; i++) {
    for (int j=0; j<MAX_SIZE; j++) {
      dataCalib[i][j] = floor((float)dataCalib[i][j] / (float)maxCalibFrames);
    }
  }
  isCalibrated = 1;
}

// During display rendering
float value = ((float)data[i][j] - (float)dataCalib[i][j]) / MAX_VALUE;
```

## User Interface and Control System

### Keyboard Command Interface
```java
Key Mapping:
'l' → Live streaming mode
'1' → 2000Hz high-speed capture
'2' → 1000Hz high-speed capture
'3' → 500Hz high-speed capture
'4' → 250Hz high-speed capture
's' → Stop/idle mode
'c' → Start background calibration
'a' → Clear data buffer
' ' → Save screenshot
'd' → Debug print calibration data
```

### Status Display System
```java
String curText = "status message";

// Status messages displayed on screen
"Live Feed"         // During live mode
"2000Hz capture"    // During high-speed modes
"Calibrating"       // During background calibration
"Idle"             // When stopped
```

### Application Window Layout
```java
Window size: 600x800 pixels

Layout:
┌─────────────────────────────────────────┐
│ Normal Sensitivity Grid (8x8)           │
│ Position: (10, 10)                      │
│ Size: 240x240 pixels (30px per sensor)  │
├─────────────────────────────────────────┤
│ Status Text Area                        │
│ Position: (150, 400)                    │
├─────────────────────────────────────────┤
│ High Sensitivity Grid (8x8)            │
│ Position: (10, 450)                     │
│ Size: 240x240 pixels (30px per sensor)  │
└─────────────────────────────────────────┘
```

## Performance Considerations for P2 Implementation

### Real-Time Processing Requirements
- **Frame Rate**: Up to 2000 fps from Arduino
- **Serial Bandwidth**: 115200 baud (sufficient for ~400 fps continuous)
- **Display Refresh**: 60 fps Processing draw() loop
- **Memory Usage**: Minimal (8x8 arrays = 64 integers per buffer)

### Critical Timing Constraints
1. **Serial Buffer Management**: Must handle burst data from high-speed modes
2. **Frame Synchronization**: Detect complete frames via asterisk markers
3. **Display Lag**: Minimize latency between data arrival and visualization

### P2-Specific Implementation Recommendations

#### Serial Communication
```
P2 UART Configuration:
- Baud Rate: 115200 (matches Arduino)
- Buffer Size: 2KB minimum for burst handling
- Flow Control: None (data is unidirectional bursts)
```

#### Display System
```
P2 VGA/HDMI Output:
- Resolution: 640x480 minimum
- Color Depth: 16-bit minimum (5-6-5 RGB)
- Pixel Size: Scale to available resolution
- Frame Rate: 60 Hz refresh
```

#### Memory Management
```
P2 Hub RAM Allocation:
- Frame Buffer: 64 * 2 bytes = 128 bytes
- Calibration Buffer: 64 * 2 bytes = 128 bytes
- Display Buffer: 640*480*2 = 614KB
- Total: <1MB requirement
```

## Algorithm Implementation Details

### Color Intensity Calculation
```c
// Normal sensitivity (0-255 range)
intensity = (int)(255.0 * normalized_value);

// High sensitivity (0-3000 range, clipped to 255 for display)
intensity = (int)(3000.0 * normalized_value);
if (intensity > 255) intensity = 255;
if (intensity < -255) intensity = -255;
```

### Coordinate Transformation
```c
// Processing coordinate system (origin top-left)
display_x = (7 - sensor_j) * pixel_size + offset_x;
display_y = (7 - sensor_i) * pixel_size + offset_y;

// This creates proper magnetic field orientation with sensor (0,0) at bottom-left
```

### Frame Buffer Management
```c
// Circular buffer for continuous operation
current_frame_index = (current_frame_index + 1) % max_frames;

// Frame completeness detection
if (received_asterisk_marker) {
  frame_ready = true;
  current_row = 0;
}
```

## Error Handling and Robustness

### Serial Communication Errors
- **Incomplete Frames**: Timeout detection and frame reset
- **Parse Errors**: Validate 8 values per line, skip malformed data
- **Buffer Overruns**: Implement circular buffering with overflow protection

### Display System Errors
- **Color Overflow**: Clamp intensity values to valid RGB ranges
- **Invalid Coordinates**: Bounds checking on pixel positions
- **Memory Allocation**: Pre-allocate all display buffers at startup

### User Interface Errors
- **Invalid Commands**: Ignore unrecognized keystrokes
- **State Conflicts**: Prevent simultaneous calibration and capture modes
- **Serial Port Failures**: Graceful degradation with connection loss

This comprehensive theory of operations provides all necessary implementation details for recreating the Processing visualization system on the Propeller 2 platform while maintaining full compatibility with the existing Arduino sensor interface.