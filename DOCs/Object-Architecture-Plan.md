# P2 Magnetic Field Viewer - Spin2 Object Architecture Plan

## Overview
This document defines the object-oriented architecture for the P2 Magnetic Field Viewer application, breaking down the system into clean, reusable Spin2 objects with well-defined interfaces and responsibilities.

## Core Architecture Principles

### Design Philosophy
1. **Single Responsibility**: Each object has one clear purpose
2. **COG Encapsulation**: Objects manage their own COG resources
3. **Clean Interfaces**: Public methods define clear contracts
4. **Loose Coupling**: Objects interact through defined interfaces, not internals
5. **Fixed Resources**: Pre-allocated buffers, no dynamic memory

### System Block Diagram
```
┌─────────────────────────────────────────────────────────┐
│                     main.spin2 (COG 0)                   │
│  ┌─────────────────────────────────────────────────┐    │
│  │              Shared Buffer Pool (HUB RAM)        │    │
│  │        [0][1][2][3][4][5][6][7] (8 frames)      │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
     ↑               ↑              ↑              ↑
     │               │              │              │
┌────┴──────┐ ┌──────┴──────┐ ┌────┴──────┐ ┌────┴──────┐
│  scanner  │ │    oled     │ │   hdmi    │ │ processor │
│   .spin2  │ │  .spin2     │ │  .spin2   │ │  .spin2   │
│  (COG 1)  │ │  (COG 2)    │ │  (COG 3)  │ │  (COG 4)  │
└───────────┘ └─────────────┘ └───────────┘ └───────────┘
```

## Object Definitions

### 1. main.spin2 - System Controller
**Purpose**: Top-level coordination and resource management

**COG Usage**: COG 0 (main COG)

**Responsibilities**:
- Initialize all hardware
- Create and manage shared buffer pool
- Start/stop child objects
- Handle user interface
- Coordinate display modes
- System-wide error handling

**Public Interface**:
```spin2
PUB main()
PUB set_display_mode(mode)
PUB get_system_stats() : sensorFPS, oledFPS, hdmiFPS, bufferUtil
PUB handle_command(cmd)
PUB emergency_stop()
```

**Key Variables**:
```spin2
OBJ
  scanner  : "sensor_scanner"
  oled     : "oled_display"
  hdmi     : "hdmi_display"
  pool     : "buffer_pool"
  proc     : "data_processor"
  debug    : "debug_terminal"

VAR
  long displayMode
  long systemStatus
```

### 2. sensor_scanner.spin2 - Sensor Acquisition
**Purpose**: Continuous sensor scanning and data acquisition

**COG Usage**: COG 1 (dedicated)

**Responsibilities**:
- Configure sensor hardware pins
- Continuous scanning at maximum rate
- Direct scan into provided buffers
- Track acquisition statistics
- Handle ADC communication

**Public Interface**:
```spin2
PUB start(poolPtr, csPin, cclkPin, misoPin, clrbPin, sclkPin) : success
PUB stop()
PUB get_stats() : framesScanned, currentFPS, errors
PUB set_rate(targetFPS)
PUB calibrate() : baseline[64]
```

**Internal Structure**:
```spin2
DAT
  ' PASM2 code for high-speed scanning
  scanner_engine
              org     0
  scan_loop   ' Reset counter
              ' Scan 64 sensors
              ' Read ADC
              ' Store to buffer
              jmp     #scan_loop
```

### 3. oled_display.spin2 - OLED Display Driver
**Purpose**: 128×128 OLED display management

**COG Usage**: COG 2 (dedicated)

**Responsibilities**:
- Initialize SSD1351 OLED controller
- Configure smart pins for SPI
- Render frames to display
- Manage refresh rate (60 fps target)
- Handle display modes (heatmap, vectors, etc.)

**Public Interface**:
```spin2
PUB start(poolPtr, mosiPin, sclkPin, csPin, dcPin, rstPin) : success
PUB stop()
PUB set_mode(vizMode)
PUB set_brightness(level)
PUB get_stats() : framesDisplayed, currentFPS, dropped
PUB show_message(text)
```

**Display Modes**:
```spin2
CON
  MODE_HEATMAP = 0    ' Standard field strength
  MODE_VECTORS = 1    ' Direction arrows
  MODE_PEAK    = 2    ' Peak hold
  MODE_DIFF    = 3    ' Differential (changes only)
```

### 4. hdmi_display.spin2 - HDMI Display Driver
**Purpose**: High-resolution HDMI output

**COG Usage**: COG 3 (dedicated)

**Responsibilities**:
- Configure HDMI smart pins
- Generate 512×512 display at 240 fps
- Multi-pane layout management
- Professional visualization modes
- Scale sensor data to display resolution

**Public Interface**:
```spin2
PUB start(poolPtr, hdmiBasePin) : success
PUB stop()
PUB set_layout(layoutMode)
PUB set_pane(paneNum, contentType)
PUB get_stats() : framesDisplayed, currentFPS
PUB enable_overlay(overlayType)
```

**Layout Options**:
```spin2
CON
  LAYOUT_SINGLE = 0   ' Full screen field view
  LAYOUT_DUAL   = 1   ' Split screen
  LAYOUT_QUAD   = 2   ' Four panes
  LAYOUT_PIP    = 3   ' Picture in picture
```

### 5. buffer_pool.spin2 - Buffer Management
**Purpose**: Thread-safe buffer pool management

**COG Usage**: None (methods only, runs in caller's COG)

**Responsibilities**:
- Manage 8 pre-allocated frame buffers
- Atomic get/release operations
- Track buffer states
- Prevent buffer conflicts
- Monitor utilization

**Public Interface**:
```spin2
PUB init(bufferPtr, numBuffers, bufferSize)
PUB get_free_buffer() : bufferAddr | timeout
PUB mark_ready(bufferAddr)
PUB get_ready_buffer() : bufferAddr
PUB release_buffer(bufferAddr)
PUB get_utilization() : percentUsed
PUB reset_all()
```

**Buffer States**:
```spin2
CON
  STATE_FREE     = 0  ' Available for use
  STATE_FILLING  = 1  ' Scanner writing
  STATE_READY    = 2  ' Data ready
  STATE_READING  = 3  ' Display reading
```

### 6. data_processor.spin2 - Signal Processing
**Purpose**: Optional data filtering and analysis

**COG Usage**: COG 4 (optional)

**Responsibilities**:
- Filtering (Kalman, moving average)
- FFT frequency analysis
- Motion detection
- Peak/valley tracking
- Pattern recognition

**Public Interface**:
```spin2
PUB start(poolPtr) : success
PUB stop()
PUB enable_filter(filterType)
PUB set_filter_params(params)
PUB get_fft_result() : spectrum[32]
PUB get_motion_vectors() : vectors[64]
PUB detect_pattern() : patternID
```

### 7. debug_terminal.spin2 - Debug Output
**Purpose**: Development and diagnostic display

**COG Usage**: COG 5 (optional)

**Responsibilities**:
- Terminal-based status display
- Performance metrics
- Error reporting
- System health monitoring
- Interactive debugging

**Public Interface**:
```spin2
PUB start(statsPtr) : success
PUB stop()
PUB set_verbosity(level)
PUB log_error(source, code, message)
PUB show_buffer_hex(bufferAddr)
PUB enable_scope_mode(sensorNum)
```

## Inter-Object Communication

### Communication Methods

#### 1. Shared Buffer Pool (Primary Data Path)
```spin2
' All objects reference the same buffer pool
' Scanner writes, displays read
' Pool object manages synchronization
```

#### 2. Direct Method Calls (Control Path)
```spin2
' Main object calls methods on children
oled.set_mode(MODE_HEATMAP)
scanner.set_rate(1000)
```

#### 3. Shared Statistics Block (Monitoring)
```spin2
VAR
  ' Global statistics structure
  long stats[32]
    ' [0] = scanner FPS
    ' [1] = OLED FPS
    ' [2] = HDMI FPS
    ' [3] = buffer utilization
    ' [4] = error count
    ' etc...
```

### Synchronization Strategy

#### Lock-Free Design
```spin2
' Use atomic operations where possible
' Single writer, multiple readers
' State machines prevent conflicts
```

#### Buffer Handoff Protocol
```spin2
Scanner: get_buffer() → scan() → mark_ready()
Display: get_ready() → display() → release()
```

## Configuration Management

### Pin Configuration Structure (8-Pin Groups)

#### Configuration A: Standard P2 Board (No PSRAM)
```spin2
CON
  ' Pin allocations for standard P2 board
  ' All pin groups available

  ' Pin Group 0: HDMI Display
  HDMI_BASE  = 0      ' P0-P7 for HDMI output

  ' Pin Group 8: Magnetic Tile Sensor
  TILE_BASE  = 8      ' P8-P15 for sensor interface

  ' Pin Group 16: OLED Display
  OLED_BASE  = 16     ' P16-P23 for OLED SPI
```

#### Configuration B: P2 Edge with 32MB PSRAM + 16MB FLASH
```spin2
CON
  ' Pin allocations for P2 Edge w/32MB PSRAM + 16MB FLASH
  ' PSRAM: 4× 8MB AP Memory APS6404L-3SQR-ZR chips
  ' FLASH: 16MB non-volatile storage
  ' RAM uses P40-P57 (16-bit bus, >300 MB/s burst)

  ' Pin Group 0: HDMI Display
  HDMI_BASE  = 0      ' P0-P7 for HDMI output

  ' Pin Group 8: Magnetic Tile Sensor
  TILE_BASE  = 8      ' P8-P15 for sensor interface

  ' Pin Group 16: OLED Display
  OLED_BASE  = 16     ' P16-P23 for OLED SPI

  ' Pin Group 24: Available for expansion
  ' P24-P31 available for future use

  ' Pin Group 32: Available for expansion
  ' P32-P39 available for future use

  ' PSRAM INTERFACE (P2 Edge 32MB) - RESERVED:
  ' 4× 8MB PSRAM chips (APS6404L-3SQR-ZR)
  ' Each chip has 4-bit SIO bus, combined for 16-bit total
  ' P40-P43: PSRAM Bank 0 SIO[3:0] - NOT AVAILABLE
  ' P44-P47: PSRAM Bank 1 SIO[3:0] - NOT AVAILABLE
  ' P48-P51: PSRAM Bank 2 SIO[3:0] - NOT AVAILABLE
  ' P52-P55: PSRAM Bank 3 SIO[3:0] - NOT AVAILABLE
  ' P56:     PSRAM CLK (Common)    - NOT AVAILABLE (up to 133MHz)
  ' P57:     PSRAM CE (Common)     - NOT AVAILABLE (chip enable)

  ' FLASH INTERFACE (16MB) - RESERVED:
  ' P58-P63: Flash SPI interface - Check specific pins

  ' Memory Architecture:
  ' - 32MB PSRAM for video buffers, large data
  ' - 16MB FLASH for program/data storage
  ' - 512KB HUB RAM for real-time processing

DAT
  ' Detailed pin assignments within groups
  pinConfig
    ' HDMI Display - Group 0 (P0-P7)
    hdmi_base   byte 0   ' Pins 0-3 for HDMI TMDS signals
    hdmi_red    byte 0   ' +0 - Red differential pair
    hdmi_green  byte 1   ' +1 - Green differential pair
    hdmi_blue   byte 2   ' +2 - Blue differential pair
    hdmi_clock  byte 3   ' +3 - Clock differential pair
    ' Pins 4-7 available for HDMI audio or other features

    ' Magnetic Tile - Group 8 (P8-P15)
    tile_base   byte 8
    cs_pin      byte 8   ' +0 - AD7680 Chip Select (active low)
    cclk_pin    byte 9   ' +1 - Counter Clock (SN74HC590A)
    miso_pin    byte 10  ' +2 - AD7680 Data Out
    clrb_pin    byte 11  ' +3 - Counter Clear (active low)
    sclk_pin    byte 12  ' +4 - AD7680 Serial Clock
    ' byte 13 unused     ' +5 - Available
    aout_pin    byte 14  ' +6 - Analog Out from Mux
    ' byte 15 unused     ' +7 - Available

    ' OLED Display - Group 16 (P16-P23)
    oled_base   byte 16
    oled_mosi   byte 16  ' +0 - SPI MOSI (Data to OLED)
    ' byte 17 unused     ' +1 - Available (no MISO needed)
    oled_sclk   byte 18  ' +2 - SPI Clock
    ' byte 19 unused     ' +3 - Available
    oled_cs     byte 20  ' +4 - Chip Select (active low)
    ' byte 21 unused     ' +5 - Available
    oled_dc     byte 22  ' +6 - Data/Command select
    oled_rst    byte 23  ' +7 - Reset (active low)

    ' P2 Edge Memory Interface Pins - NOT AVAILABLE FOR USER:
    ' PSRAM (32MB = 4× 8MB APS6404L-3SQR-ZR chips):
    '   P40-P43: Bank 0 SIO[3:0] (4-bit QSPI data)
    '   P44-P47: Bank 1 SIO[3:0] (4-bit QSPI data)
    '   P48-P51: Bank 2 SIO[3:0] (4-bit QSPI data)
    '   P52-P55: Bank 3 SIO[3:0] (4-bit QSPI data)
    '   P56: PSRAM CLK (Common to all 4 banks, up to 133MHz)
    '   P57: PSRAM CE (Common chip enable)
    ' FLASH (16MB):
    '   P58-P63: Flash SPI interface (verify exact pins)
```

### System Configuration
```spin2
CON
  ' System parameters
  BUFFER_COUNT = 8
  BUFFER_SIZE  = 128  ' 64 words

  ' Performance targets
  TARGET_SENSOR_FPS = 1000
  TARGET_OLED_FPS   = 60
  TARGET_HDMI_FPS   = 240

  ' Feature flags
  ENABLE_PROCESSOR = true
  ENABLE_DEBUG     = true
```

## Object Lifecycle

### Startup Sequence
```spin2
PUB main() | success
  ' 1. Initialize buffer pool
  pool.init(@bufferMemory, BUFFER_COUNT, BUFFER_SIZE)

  ' 2. Start scanner (producer)
  scanner.start(@pool, @pinConfig)

  ' 3. Start displays (consumers)
  if oled_connected()
    oled.start(@pool, @pinConfig.oled_mosi)

  if hdmi_connected()
    hdmi.start(@pool, pinConfig.hdmi_base)

  ' 4. Optional processors
  if ENABLE_PROCESSOR
    processor.start(@pool)

  ' 5. Debug terminal
  if ENABLE_DEBUG
    debug.start(@stats)
```

### Shutdown Sequence
```spin2
PUB shutdown()
  ' Stop in reverse order
  debug.stop()
  processor.stop()
  hdmi.stop()
  oled.stop()
  scanner.stop()  ' Stop producer last
  pool.reset_all()
```

## Error Handling Strategy

### Error Categories
1. **Hardware Errors**: Pin conflicts, missing devices
2. **Resource Errors**: Buffer exhaustion, COG allocation
3. **Timing Errors**: Missed deadlines, overruns
4. **Data Errors**: Invalid readings, corruption

### Error Response
```spin2
PUB handle_error(source, code) | response
  case code
    ERROR_BUFFER_FULL:
      ' Skip frames until buffer available
      scanner.skip_frames(10)

    ERROR_DISPLAY_TIMEOUT:
      ' Reset display
      oled.reset()

    ERROR_ADC_FAILURE:
      ' Attempt recalibration
      scanner.calibrate()

    ERROR_CRITICAL:
      ' Emergency stop
      shutdown()
```

## Memory Layout

### HUB RAM Usage (512KB Total):
```
$00000-$0FFFF (64KB):  Stack/Variables/Object code
$10000-$103FF (1KB):   Frame Buffer Pool (8 × 128 bytes)
$10400-$107FF (1KB):   Statistics Block
$10800-$10FFF (2KB):   Configuration Data
$11000-$18FFF (32KB):  OLED Display Buffer
$19000-$20FFF (32KB):  HDMI Line Buffer (if no PSRAM)
$21000-$7FFFF (380KB): Available for expansion
```

### PSRAM Usage (32MB Total - P2 Edge Only):
```
$0000_0000-$007F_FFFF (8MB):  HDMI Frame Buffer 0
$0080_0000-$00FF_FFFF (8MB):  HDMI Frame Buffer 1 (double buffer)
$0100_0000-$017F_FFFF (8MB):  Sensor History Buffer (thousands of frames)
$0180_0000-$01FF_FFFF (8MB):  Processing/Pattern Library

PSRAM Performance:
- 133MHz max QSPI clock
- 16-bit bus width (4-bit × 4 chips)
- >300 MB/s burst transfer rate
- Ideal for video buffers and large datasets
```

### FLASH Usage (16MB Total - P2 Edge Only):
```
$0000_0000-$000F_FFFF (1MB):  Boot loader & main program
$0010_0000-$001F_FFFF (1MB):  HDMI driver & display objects
$0020_0000-$003F_FFFF (2MB):  Pattern library & calibration data
$0040_0000-$00FF_FFFF (12MB): Data logging & user storage
```

## P2 Edge Memory Architecture Benefits

### For Magnetic Imaging Application
The P2 Edge 32MB PSRAM + 16MB FLASH configuration provides significant advantages:

1. **Massive Frame Buffering**:
   - Store 131,072 frames in PSRAM (32MB ÷ 256 bytes/frame)
   - At 1,440 fps, that's 91 seconds of continuous capture
   - Enable advanced time-domain analysis and pattern recognition

2. **True Double-Buffered HDMI**:
   - Dedicated 8MB frame buffers eliminate tearing
   - 512×512 @ 24bpp = 768KB per frame (plenty of headroom)
   - Smooth 240 fps display independent of sensor acquisition

3. **Pattern Library Storage**:
   - 16MB FLASH holds thousands of magnetic signatures
   - Fast pattern matching without HUB RAM consumption
   - Persistent calibration data across power cycles

4. **High-Speed Data Transfer**:
   - >300 MB/s burst rate enables real-time processing
   - 16-bit bus width matches sensor frame size perfectly
   - DMA-style transfers free COGs for computation

## Performance Considerations

### COG Utilization Targets
| COG | Object | Target Load | Actual Load | Headroom |
|-----|--------|-------------|-------------|----------|
| 0 | main | 20% | TBD | 80% |
| 1 | scanner | 70% | TBD | 30% |
| 2 | oled | 25% | TBD | 75% |
| 3 | hdmi | 20% | TBD | 80% |
| 4 | processor | 50% | TBD | 50% |
| 5 | debug | 10% | TBD | 90% |
| 6 | (free) | - | - | 100% |
| 7 | (free) | - | - | 100% |

## Testing Strategy

### Unit Tests (Per Object)
- Pin configuration validation
- Buffer management integrity
- Timing compliance
- Error injection response

### Integration Tests
- Full system startup
- Mode transitions
- Buffer flow under load
- Multi-display synchronization

### Performance Tests
- Maximum frame rates
- Latency measurement
- Buffer utilization
- Thermal stability

## Questions for Design Review

1. **Object Boundaries**: Are these divisions appropriate?
2. **Buffer Ownership**: Should buffers be in main or pool object?
3. **Configuration**: How should pin assignments be passed?
4. **Statistics**: Shared memory block or method calls?
5. **Error Recovery**: Centralized or distributed?
6. **Optional Features**: Compile-time or runtime enable?

## Next Steps

1. Finalize object interfaces based on feedback
2. Create object file templates
3. Implement buffer_pool.spin2 first (foundation)
4. Implement sensor_scanner.spin2 (data source)
5. Add display objects (consumers)
6. Integration and testing

---

This plan provides the framework for discussion. Let's refine the object boundaries and interfaces before proceeding with implementation.