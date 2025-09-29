# Magnetic Field Viewer - Application Architecture

## Document Purpose
This living document defines the software architecture for the P2 Magnetic Imaging Tile viewer application, from minimal viable product through advanced implementations. It serves as both a roadmap and idea repository for the project evolution.

## Architecture Philosophy

### Core Principles
1. **Continuous Acquisition**: Sensor scanning never stops
2. **Decoupled Display**: Display updates independent of acquisition
3. **Progressive Enhancement**: Start simple, add features without disrupting core
4. **Observable System**: Built-in diagnostics and monitoring
5. **Deterministic Timing**: Predictable, jitter-free operation

### Design Goals
- **Primary**: Real-time magnetic field visualization at 60+ fps
- **Secondary**: Maximum sensor acquisition rate characterization
- **Tertiary**: Advanced processing and analysis capabilities

## Implementation Stages

### Stage 1: Minimal Viable Product (3 Cogs)

The simplest working implementation that proves the concept.

```
┌─────────────────────────────────────────────────┐
│                   HUB RAM                        │
│  ┌────────────┐  ┌────────────┐  ┌──────────┐  │
│  │Frame Buffer│  │  Display   │  │  Stats   │  │
│  │  (256B)    │  │Buffer(32KB)│  │  (256B)  │  │
│  └────────────┘  └────────────┘  └──────────┘  │
└─────────────────────────────────────────────────┘
       ▲               ▲               ▲
       │               │               │
┌──────┴────┐  ┌───────┴────┐  ┌──────┴────┐
│  COG 1    │  │   COG 0    │  │  COG 2    │
│  Sensor   │  │    Main    │  │   Debug   │
│  Scanner  │  │  Display   │  │ Terminal  │
└───────────┘  └────────────┘  └───────────┘
```

#### COG 0: Main Controller & Display
```spin2
PUB main()
  ' Initialize hardware
  init_pins()
  init_oled()

  ' Launch scanner cog
  scanner_cog := coginit(1, @sensor_scanner, @frame_buffer)

  ' Launch debug terminal
  debug_cog := coginit(2, @debug_terminal, @stats_block)

  ' Main loop - display updates
  repeat
    if new_frame_available()
      render_frame_to_oled()
      update_statistics()
```

#### COG 1: Continuous Sensor Scanner
```spin2
DAT
  org 0
sensor_scanner
  ' Autonomous scanning loop
  ' Never stops, always acquiring
  ' Writes to circular buffer
  ' Updates frame counter
```

#### COG 2: Debug Terminal
```spin2
PUB debug_terminal()
  ' Update debug display at 10 Hz
  ' Show FPS, latency, field stats
  ' No impact on main operation
```

**Capabilities:**
- ✅ 60 fps display
- ✅ 1000+ fps sensor acquisition
- ✅ Real-time statistics
- ✅ Basic visualization

**Limitations:**
- ❌ No filtering
- ❌ No advanced processing
- ❌ Single visualization mode

### Stage 2: Enhanced System (5 Cogs)

Adds processing capabilities and improved buffering.

```
┌─────────────────────────────────────────────────────────┐
│                        HUB RAM                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │  Frame   │  │ Process  │  │ Display  │  │ Config │ │
│  │FIFO (4KB)│  │Buffer(1K)│  │Buff(32K) │  │ (512B) │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
└─────────────────────────────────────────────────────────┘
       ▲             ▲             ▲             ▲
       │             │             │             │
┌──────┴──┐  ┌───────┴──┐  ┌──────┴──┐  ┌─────┴──┐  ┌────────┐
│ COG 1   │  │  COG 3   │  │ COG 4   │  │ COG 0  │  │ COG 2  │
│ Scanner │→ │Processor │→ │Renderer │→ │Display │  │ Debug  │
└─────────┘  └──────────┘  └─────────┘  └────────┘  └────────┘
```

#### COG 3: Data Processor (New)
```spin2
PUB data_processor()
  repeat
    if raw_frame_available()
      ' Apply filtering
      kalman_filter(@raw_frame, @filtered_frame)
      ' Detect motion
      compute_motion_vectors()
      ' Track peaks
      update_peak_hold()
      ' Signal renderer
      filtered_frame_ready := true
```

#### COG 4: Display Renderer (New)
```spin2
PUB display_renderer()
  ' Dedicated rendering with LUT
  ' Multiple visualization modes
  ' Smooth interpolation
```

**New Capabilities:**
- ✅ Kalman filtering
- ✅ Motion detection
- ✅ Peak hold display
- ✅ Multiple display modes
- ✅ 32-frame FIFO buffer

### Stage 3: Advanced System (7-8 Cogs)

Full-featured system with advanced processing.

```
┌───────────────────────────────────────────────────────────────┐
│                          HUB RAM (512KB)                       │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌──────┐ ┌─────┐│
│ │Sensor  │ │Process │ │Display │ │Pattern │ │ Log  │ │Comm ││
│ │Buffer  │ │Buffer  │ │Buffer  │ │Library │ │Buffer│ │Buff ││
│ └────────┘ └────────┘ └────────┘ └────────┘ └──────┘ └─────┘│
└───────────────────────────────────────────────────────────────┘
     ▲          ▲          ▲          ▲         ▲        ▲
     │          │          │          │         │        │
┌────┴───┐ ┌────┴───┐ ┌────┴───┐ ┌────┴───┐ ┌──┴──┐ ┌──┴──┐
│COG 0-1 │ │COG 2-3 │ │ COG 4  │ │ COG 5  │ │COG 6│ │COG 7│
│Scanner │ │  DSP   │ │Display │ │Pattern │ │ Log │ │Comm │
│  Pair  │ │  Pair  │ │        │ │  Match │ │     │ │     │
└────────┘ └────────┘ └────────┘ └────────┘ └─────┘ └─────┘
```

#### COG PAIR 0-1: Dual Scanner Pipeline
```spin2
' COG 0 scans sensors 0-31
' COG 1 scans sensors 32-63
' Shared LUT for timing constants
' Achieves 2× acquisition rate
```

#### COG PAIR 2-3: DSP Engine
```spin2
' COG 2: FFT processing
' COG 3: Digital filtering
' Shared LUT for coefficients
' Real-time frequency analysis
```

#### COG 5: Pattern Recognition
```spin2
PUB pattern_matcher()
  ' Gesture detection
  ' Magnetic signature matching
  ' Anomaly detection
  ' ML inference
```

#### COG 6: Data Logger
```spin2
PUB data_logger()
  ' SD card interface
  ' Compression
  ' Timestamping
  ' Circular logging
```

#### COG 7: Communications
```spin2
PUB comm_handler()
  ' USB/Serial interface
  ' Command processing
  ' Remote control
  ' Data streaming
```

**Advanced Capabilities:**
- ✅ 3000+ fps acquisition (dual scanner)
- ✅ FFT frequency analysis
- ✅ Gesture recognition
- ✅ Data logging to SD
- ✅ Remote control interface
- ✅ Pattern library matching

## Buffer Architecture

### Frame Buffer Options

#### Option A: Simple Double Buffer
```spin2
VAR
  word buffer1[64]  ' Active acquisition
  word buffer2[64]  ' Display processing
  byte activeBuffer
```
**Use When:** Minimal latency required, simple system

#### Option B: Ring Buffer FIFO
```spin2
CON
  FIFO_DEPTH = 32
VAR
  word frameRing[64 * FIFO_DEPTH]
  long writePtr, readPtr
```
**Use When:** Need to absorb timing variations

#### Option C: Smart Adaptive Buffer
```spin2
VAR
  word fastBuffer[64 * 8]    ' High-speed burst
  word avgBuffer[64]         ' Running average
  long statistics[64 * 4]    ' Min/max/mean/stdev
```
**Use When:** Advanced processing required

## Visualization Modes

### Implemented Modes

#### 1. Standard Heat Map
- Linear color mapping
- Red = North, Blue = South
- Real-time updates

#### 2. Peak Hold Display
- Shows maximum values
- Decay timer
- Reset button

#### 3. Differential Mode
- Shows changes only
- Highlights motion
- Adjustable threshold

#### 4. Vector Field Display
- Arrows show field direction
- Length shows magnitude
- 3D projection option

### Planned Modes (Ideas Repository)

#### 5. Frequency Analysis
- FFT spectrum per sensor
- Waterfall display
- Identify oscillating fields

#### 6. Time History
- Scrolling time plot
- Selected sensor history
- Triggerable capture

#### 7. 3D Surface Plot
- Wireframe or solid
- Rotating view
- Height = field strength

#### 8. Particle Simulation
- Virtual iron filings
- Physics simulation
- Educational mode

## Communication Protocol

### Command Interface
```
Commands (via Serial/USB):
- 'M' <mode>: Set display mode
- 'F' <fps>: Set frame rate
- 'A' <count>: Set averaging
- 'R': Reset peaks
- 'C': Calibrate sensors
- 'S': Get statistics
- 'D': Dump frame data
- 'L': Start/stop logging
```

### Data Streaming Format
```
Frame Header (8 bytes):
  [0-1]: Magic (0x4D46)  'MF'
  [2-3]: Frame number
  [4-5]: Timestamp (ms)
  [6]: Flags
  [7]: Checksum

Frame Data (128 bytes):
  [0-127]: 64 × 16-bit sensor values

Frame Footer (4 bytes):
  [0-3]: CRC32
```

## Performance Targets

### Minimum Requirements
- Display: 30 fps minimum
- Latency: <50ms sensor to display
- Accuracy: ±0.5 mT
- Stability: 24-hour continuous operation

### Stretch Goals
- Display: 120 fps
- Latency: <10ms
- Sensor rate: 3000 fps
- Advanced processing in real-time

## Memory Map

```
HUB RAM Allocation (512KB Total):

$00000-$0FFFF (64KB):  System/Stack/Variables
$10000-$17FFF (32KB):  Display Buffer 1
$18000-$1FFFF (32KB):  Display Buffer 2
$20000-$21FFF (8KB):   Sensor Frame Buffers
$22000-$23FFF (8KB):   Processing Buffers
$24000-$25FFF (8KB):   Pattern/Gesture Library
$26000-$27FFF (8KB):   Debug/Statistics
$28000-$3FFFF (96KB):  Data Logging Buffer
$40000-$7FFFF (256KB): Reserved/Available
```

## Development Roadmap

### Phase 1: Core Implementation ✓
- [x] Hardware connectivity verified
- [x] Basic sensor reading
- [x] OLED display working
- [ ] Stage 1 architecture complete

### Phase 2: Performance Optimization
- [ ] Characterize maximum frame rates
- [ ] Optimize timing loops
- [ ] Implement FIFO buffering
- [ ] Add debug terminal

### Phase 3: Enhanced Features
- [ ] Multiple visualization modes
- [ ] Filtering and averaging
- [ ] Peak detection
- [ ] Motion tracking

### Phase 4: Advanced Capabilities
- [ ] Pattern recognition
- [ ] Gesture detection
- [ ] Data logging
- [ ] Remote interface

### Phase 5: Polish & Production
- [ ] Power optimization
- [ ] Error handling
- [ ] User interface
- [ ] Documentation

## Ideas Parking Lot

### Future Enhancements (Brainstorming)
- **Magnetic Signature Library**: Store and match object signatures
- **Auto-Calibration**: Compensate for Earth's field
- **Temperature Compensation**: Adjust for thermal drift
- **Multi-Tile Sync**: Combine multiple tiles for larger array
- **AR Overlay**: Project field lines on camera view
- **Sound Synthesis**: Convert field patterns to audio
- **Machine Learning**: Train models for object recognition
- **Wireless Streaming**: WiFi/Bluetooth data transmission
- **Cloud Analytics**: Upload patterns for analysis
- **Educational Games**: Interactive learning experiences

### Performance Ideas
- **Predictive Scanning**: Anticipate field changes
- **Compressed Sensing**: Reduce data with smart sampling
- **Hardware Triggering**: External sync input
- **Differential ADC Mode**: Increase sensitivity
- **Dynamic Range Switching**: Auto-gain control

### Display Ideas
- **Holographic Mode**: Simulated 3D without glasses
- **Persistence Mode**: Trails showing movement history
- **Split Screen**: Multiple views simultaneously
- **Picture-in-Picture**: Zoom window
- **Augmented Labels**: Identify common objects

## Testing & Validation

### Unit Tests Required
- [ ] Sensor addressing correct
- [ ] ADC communication reliable
- [ ] Frame buffer integrity
- [ ] Display update smooth
- [ ] Timing requirements met

### Integration Tests
- [ ] End-to-end latency
- [ ] Multi-cog synchronization
- [ ] Buffer overflow handling
- [ ] Error recovery
- [ ] Long-term stability

### Performance Tests
- [ ] Maximum frame rate
- [ ] Minimum latency
- [ ] Power consumption
- [ ] Thermal limits
- [ ] Memory usage

## Configuration Management

### Compile-Time Options
```spin2
CON
  ' Feature Flags
  ENABLE_DEBUG = true
  ENABLE_FILTERING = true
  ENABLE_LOGGING = false
  ENABLE_PATTERNS = false

  ' Performance Settings
  TARGET_SENSOR_FPS = 1000
  TARGET_DISPLAY_FPS = 60
  FIFO_DEPTH = 32

  ' Hardware Configuration
  P2_CLOCK_MHZ = 200  ' Adjust based on characterization
```

### Runtime Configuration
```spin2
DAT
  config_block
    sensor_fps    long  1000
    display_fps   long  60
    avg_frames    long  4
    filter_enable long  1
    display_mode  long  0
```

## Success Metrics

### Technical Metrics
- Sensor frame rate achieved: _____ fps
- Display frame rate achieved: _____ fps
- End-to-end latency: _____ ms
- Power consumption: _____ mW
- Operating temperature: _____ °C

### User Experience Metrics
- Response feels: [Instant|Quick|Acceptable|Sluggish]
- Display quality: [Excellent|Good|Acceptable|Poor]
- Stability: [Rock solid|Stable|Occasional issues|Unstable]
- Features: [Exceeds needs|Meets needs|Adequate|Insufficient]

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2024-11-DD | System | Initial architecture document |
| | | | |

---

This is a living document. Update as the project evolves and new ideas emerge.