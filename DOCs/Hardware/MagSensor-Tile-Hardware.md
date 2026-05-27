# SparkFun Magnetic Imaging Tile V3 - Hardware Specifications

## Overview
The SparkFun Magnetic Imaging Tile V3 is an 8×8 array of Hall effect sensors designed for real-time magnetic field visualization. This document details the hardware specifications and interface requirements for integration with the Propeller 2 microcontroller.

## Sensor Array Architecture

### Physical Layout
- **Array Configuration**: 8×8 grid (64 sensors total)
- **Sensor Type**: Hall effect magnetic field sensors
- **Arrangement**: 4 subtiles (quadrants), each 4×4 sensors
- **PCB Layout**: Serpentine trace routing within each subtile

### Subtile Organization
```
+--------+--------+
| Tile 0 | Tile 2 |
| (4x4)  | (4x4)  |
+--------+--------+
| Tile 1 | Tile 3 |
| (4x4)  | (4x4)  |
+--------+--------+
```

## Hardware Components

### Sensor Selection System
- **Multiplexer**: Hardware-based sequential sensor selection
- **Counter**: Binary counter for address generation
- **Control Signals**:
  - CCLK: Counter clock (advance to next sensor)
  - CLRb: Counter clear (reset to first sensor)

### Analog-to-Digital Conversion
- **Primary ADC**: AD7680 16-bit external ADC (IC marking: C39/29Z)
  - Resolution: 16 bits
  - Interface: SPI (bit-banged)
  - Sample Rate: Up to 100 ksps
  - Maximum SPI Clock: 2.5 MHz
- **Alternative**: P2 internal ADC (12-bit)
  - Direct analog input via AOUT pin
  - Lower resolution but simpler interface

## Interface Pinout

### P2 Pin Assignments

**Pin Group**: 8 (P8-P15)

| P2 Pin | Signal | Wire Color | Function |
|--------|--------|------------|----------|
| P8 (+0) | CS | Violet | AD7680 Chip Select (active low) |
| P9 (+1) | CCLK | White | Counter Clock (sensor advance) |
| P10 (+2) | MISO | Blue | AD7680 Data Output |
| P11 (+3) | CLRb | Gray | Counter Clear (active low) |
| P12 (+4) | SCLK | Green | AD7680 Clock (max 2.5 MHz) |
| P14 (+6) | AOUT | Yellow | Analog Output (sensor signal) |
| GND | GND | Black | Ground Reference |
| 3.3V | VCC | Red | Power Supply |

- Pin group allocation allows efficient Smart Pin configuration
- Separate from HDMI display interface (Pin Group 0: P0-P7)
- Separate from OLED display interface (Pin Group 16: P16-P23)

## Sensor Readout Sequence

### Basic Operation
1. **Reset**: Assert CLRb low to reset counter to sensor 0
2. **Release Reset**: Set CLRb high
3. **First Sensor**: Pulse CCLK once to select sensor 0
4. **Read Cycle**:
   - Initiate ADC conversion
   - Read ADC result
   - Pulse CCLK to advance to next sensor
5. **Frame Complete**: After 64 reads, repeat from step 1

### Subtile Reading Order
- Hardware dictates subtile order: 0 → 2 → 1 → 3
- Each subtile contains 16 sensors in serpentine pattern
- Total sequence: 64 clock pulses per complete frame

### Sensor Reading Strategy and Benefits

#### Non-Sequential Reading Pattern
The hardware doesn't read sensors in simple left-to-right, top-to-bottom order. Instead, it uses a sophisticated pattern:
```
Reading Order: Subtile 0 → Subtile 2 → Subtile 1 → Subtile 3

Visual Layout:          Reading Sequence:
+--------+--------+     +---1st--+---2nd--+
| Tile 0 | Tile 2 |     | (1-16) | (17-32) |
+--------+--------+     +--------+--------+
| Tile 1 | Tile 3 |     | (33-48)| (49-64) |
+--------+--------+     +---3rd--+---4th--+
```

#### Benefits of This Approach

**1. Minimizing Magnetic Crosstalk**
- Adjacent sensors can influence each other when energized
- By reading diagonal quadrants (0→2), we maximize physical distance between consecutively read sensors
- This allows magnetic fields from previous readings to dissipate before reading nearby sensors

**2. Thermal Management**
- Each sensor draws ~3-5mA when active
- Reading pattern distributes thermal load across the PCB
- Prevents localized heating that could affect sensor accuracy

**3. Power Supply Stability**
- Distributes current draw spatially across the board
- Reduces localized voltage drops in power distribution
- Improves measurement consistency

**4. Settling Time Optimization**
- While sensor N is being read, sensors far from N are settling
- When we return to that region, they've had maximum settling time
- Example: While reading Tile 2, Tile 1 has maximum time to stabilize

#### Serpentine Pattern Within Subtiles
Each 4×4 subtile uses serpentine routing:
```
Row 0: →→→→  (left to right)
Row 1: ←←←←  (right to left)
Row 2: →→→→  (left to right)
Row 3: ←←←←  (right to left)
```

**Benefits:**
- Minimizes trace length on PCB
- Reduces parasitic capacitance
- Improves signal integrity
- Simplifies PCB routing

### Pixel Remapping
Due to serpentine PCB layout and non-sequential reading, sensor data requires remapping:
```
Physical Read Order → Spatial Position → Display Pixels
- Account for serpentine within subtiles
- Rearrange subtiles to correct positions
- Apply row reversals where needed
```

This remapping is done in software to present a spatially correct image despite the optimized hardware reading pattern.

## Hardware-Software Mapping Analysis

### Actual Hardware Layout (From Schematic)
Each quadrant uses identical channel-to-position mapping:

```
Physical Layout (All Quadrants):
     Col0   Col1   Col2   Col3
Row0  x/9   x/11  x/13  x/15   (odd high channels)
Row1  x/8   x/10  x/12  x/14   (even high channels)
Row2  x/6   x/4   x/2   x/0    (even low channels)
Row3  x/7   x/5   x/3   x/1    (odd low channels)

Where x = quadrant number (1-4)
```

### Software Pixel Mapping (From Arduino Code)
```c
pixelOrder[] = {26, 27, 18, 19, 10, 11, 2, 3, 1, 0, 9, 8, 17, 16, 25, 24}
```

This array maps counter values 0-15 to pixel positions in the display buffer.

### Critical Analysis
The hardware layout does NOT follow a simple serpentine pattern as the documentation suggests. Instead:

1. **Hardware Pattern**: Alternating odd/even channels in a complex 2D arrangement
2. **Software Assumption**: May be based on a different PCB revision or serpentine layout
3. **Implication**: The pixelOrder[] array in the Arduino code may not correctly map to this hardware

### Reading Sequence Through Hardware
When counter increments 0→15, the physical scan path is:
```
Start: 1/0 (row 2, col 3) → 1/1 (row 3, col 3) → 1/2 (row 2, col 2) →
       1/3 (row 3, col 2) → 1/4 (row 2, col 1) → 1/5 (row 3, col 1) →
       1/6 (row 2, col 0) → 1/7 (row 3, col 0) → 1/8 (row 1, col 0) →
       1/9 (row 0, col 0) → 1/10 (row 1, col 1) → 1/11 (row 0, col 1) →
       1/12 (row 1, col 2) → 1/13 (row 0, col 2) → 1/14 (row 1, col 3) →
       1/15 (row 0, col 3)
```

This creates maximum separation between consecutive reads - a sophisticated anti-crosstalk design.

### P2 Implementation Note
**IMPORTANT**: The P2 implementation will need to verify the actual hardware mapping and potentially create a new pixelOrder[] array that matches the specific PCB version in use. The existing Arduino code mapping may not be correct for all hardware revisions.

## Theory of Operations

### System Overview
The Magnetic Imaging Tile operates through a sophisticated cascaded addressing system that sequentially reads 64 Hall effect sensors while minimizing electromagnetic interference between measurements. This design prioritizes measurement accuracy over software simplicity.

### Signal Flow Architecture

#### 1. Command Generation (P2 → Counter)
The Propeller 2 controls the entire system through just two signals:
- **CCLK** (P41): Advances the counter to the next sensor
- **CLRb** (P43): Resets counter to sensor 0

#### 2. Address Generation (SN74HC590A Counter)
**Physical IC Confirmed**: TI 33AKL1M / HC590A (scope inspection)
The 8-bit counter generates a 6-bit address (Q0-Q5) that controls sensor selection:
- **Q0-Q3**: Channel select (S0-S3) - selects 1 of 16 sensors within a quadrant
- **Q4-Q5**: Quadrant select - feeds the decoder

#### 3. Quadrant Selection (SN74LVC1G139 Decoder)
**Physical IC Confirmed**: C40 (6-pin package, scope inspection)
The 2-to-4 decoder receives Q4-Q5 and generates four enable signals:
- **Q4=0, Q5=0** → EN1 active (Upper Left Quadrant)
- **Q4=0, Q5=1** → EN2 active (Upper Right Quadrant)
- **Q4=1, Q5=0** → EN3 active (Lower Left Quadrant)
- **Q4=1, Q5=1** → EN4 active (Lower Right Quadrant)

#### 4. Sensor Multiplexing (4× CD74HC4067)
**Physical ICs Confirmed**: hp4067 / 42kG4 / AT77 (scope inspection)
Each quadrant has its own 16:1 analog multiplexer:
- Receives S0-S3 (channel select) from counter Q0-Q3
- Receives EN signal from decoder
- Routes selected Hall sensor output to common analog bus

### Physical Sensor Layout (Per Schematic)

**AUTHORITATIVE REFERENCE**: This layout is based on the actual PCB schematic and represents the true hardware connections.

#### Channel-to-Position Mapping (All Quadrants)
```
Physical 4×4 Grid Position:
        Col0    Col1    Col2    Col3
Row0    Ch9     Ch11    Ch13    Ch15    (top row)
Row1    Ch8     Ch10    Ch12    Ch14
Row2    Ch6     Ch4     Ch2     Ch0
Row3    Ch7     Ch5     Ch3     Ch1     (bottom row)
```

#### Complete 8×8 Sensor Array
```
Quadrant EN1 (Upper Left)    |    Quadrant EN2 (Upper Right)
1/9  1/11  1/13  1/15        |    2/9  2/11  2/13  2/15
1/8  1/10  1/12  1/14        |    2/8  2/10  2/12  2/14
1/6  1/4   1/2   1/0         |    2/6  2/4   2/2   2/0
1/7  1/5   1/3   1/1         |    2/7  2/5   2/3   2/1
-----------------------------|------------------------------
Quadrant EN3 (Lower Left)    |    Quadrant EN4 (Lower Right)
3/9  3/11  3/13  3/15        |    4/9  4/11  4/13  4/15
3/8  3/10  3/12  3/14        |    4/8  4/10  4/12  4/14
3/6  3/4   3/2   3/0         |    4/6  4/4   4/2   4/0
3/7  3/5   3/3   3/1         |    4/7  4/5   4/3   4/1
```

### Counter Sequence to Physical Position

When the counter increments from 0 to 63, it reads sensors in this order:

#### Counter Values 0-15 (EN1 - Upper Left):
```
Counter  Channel  Physical Position (Row,Col)  Sensor ID
0        0        (2,3)                       1/0
1        1        (3,3)                       1/1
2        2        (2,2)                       1/2
3        3        (3,2)                       1/3
4        4        (2,1)                       1/4
5        5        (3,1)                       1/5
6        6        (2,0)                       1/6
7        7        (3,0)                       1/7
8        8        (1,0)                       1/8
9        9        (0,0)                       1/9
10       10       (1,1)                       1/10
11       11       (0,1)                       1/11
12       12       (1,2)                       1/12
13       13       (0,2)                       1/13
14       14       (1,3)                       1/14
15       15       (0,3)                       1/15
```

Then continues with EN2, EN3, and EN4 in the same pattern.

### Design Rationale

#### Anti-Crosstalk Optimization
The channel mapping creates maximum physical separation between consecutive reads:
- **Sequential channels** (0→1→2→3) are never adjacent
- **Path jumps** across the quadrant between reads
- **Magnetic fields** have time to dissipate before nearby sensors are read

#### Example Read Sequence Path
```
0: Start at (2,3) - middle right
1: Jump to (3,3) - bottom right
2: Jump to (2,2) - middle center
3: Jump to (3,2) - bottom center
```
Each read is physically separated from the previous, minimizing interference.

### P2 Implementation Mapping

For correct spatial display, the P2 must remap the hardware sequence to display positions:

```spin2
' Hardware channel to display position mapping for upper-left quadrant
' Index = channel number (0-15), Value = display position in 8x8 grid
quadrant1_map byte  19, 27, 18, 26, 17, 25, 16, 24,  ' Ch 0-7
                    8,  0,  9,  1, 10,  2, 11,  3   ' Ch 8-15

' Apply offset based on quadrant (0, 4, 32, 36)
```

### Key Implementation Notes

1. **Trust the Schematic**: The physical connections shown in the schematic are the ground truth
2. **Counter Controls Everything**: Simple increment from 0-63 reads all sensors
3. **Hardware Does the Work**: Complex routing minimizes software overhead
4. **Remapping Required**: Software must translate hardware sequence to spatial positions
5. **Maximum Speed**: ~1,500 fps limited by ADC settling time, not digital switching

## Timing Specifications

### AD7680 ADC Detailed Timing Analysis
**Physical IC Confirmed**: C39/29Z (8-pin package, scope inspection)

#### Critical ADC Parameters (from AD7680 datasheet)
- **Maximum SPI Clock**: 2.5 MHz
- **Minimum Conversion Time**: 20 SCLK cycles (8µs @ 2.5MHz)
- **CS to SCLK Setup (t2)**: 10ns minimum
- **Quiet Time (tQUIET)**: 100ns minimum between conversions
- **Data Access Time (t4)**: 35-80ns after SCLK falling edge
- **Track-and-Hold Acquisition**: 400ns (sine wave ≤10kHz), 1.5µs (full-scale step)

#### Key Timing Insight
The CS falling edge performs two critical functions simultaneously:
1. **Captures** the current analog value into track-and-hold
2. **Initiates** the conversion process

This means the analog signal MUST be fully settled BEFORE CS falls - we cannot pipeline sensor switching with conversion.

#### Minimum Timing Per Sensor
```
1. CCLK pulse to advance mux     : 200ns
2. Analog settling time           : 1,500-2,000ns
   - Mux switching               : ~200ns
   - Hall sensor stabilization   : ~500ns
   - ADC input cap charging      : ~500ns
   - Safety margin               : ~300-800ns
3. CS setup time                 : 10ns
4. Conversion (20 × 400ns)       : 8,000ns
5. CS hold and quiet time        : 100ns
----------------------------------------
TOTAL PER SENSOR                 : ~10,000ns (10µs)
```

#### Maximum Theoretical Performance
- **Single Sensor Rate**: 100 kHz (10µs cycle)
- **Full Frame (64 sensors)**: 640µs minimum
- **Maximum Frame Rate**: 1,562 fps theoretical
- **Data Throughput**: 200 KB/sec @ 16-bit resolution

### Hardware Multiplexer Architecture

#### Cascaded Switching System
The magnetic tile uses a sophisticated three-stage multiplexing architecture:

1. **Stage 1: Binary Counter (SN74HC590A)**
   - 8-bit binary counter with output register
   - Inputs: CCLK (counter clock), CCLR (clear)
   - Outputs: Q0-Q5 (6 bits used for addressing)
   - Function: Generates sequential addresses for sensor selection

2. **Stage 2: Address Decoder (SN74LVC1G139)**
   - 2-to-4 line decoder
   - Inputs: A, B (from counter Q4, Q5)
   - Outputs: EN1-EN4 (region enable signals)
   - Function: Decodes upper address bits to select one of four regions

3. **Stage 3: Analog Multiplexers (4× CD74HC4067)**
   - 16-channel analog multiplexer/demultiplexer (×4)
   - Inputs: S0-S3 (from counter Q0-Q3), EN (from decoder)
   - Output: Analog signal from selected Hall sensor
   - Function: Routes one of 16 sensor signals per region to output

#### Component Timing Specifications

##### SN74HC590A Binary Counter
*Source: TI SN74HC590A Datasheet, search results from TI.com*
- **Propagation Delay (tpd)**: 20ns typical @ 3.3V
- **Maximum Clock Frequency**: 60 MHz typical
- **CCLK Pulse Width**: min 100ns high, 100ns low
- **Operating Voltage**: 2V to 6V
- **Setup/Hold Times**: ~10ns typical

##### SN74LVC1G139 2-to-4 Decoder
*Source: TI SN74LVC1G139 Datasheet + Physical Inspection*
- **Confirmed IC Marking**: C40 (6-pin package, scope verified)
- **Propagation Delay**: "Very short" - designed for high-performance
- **Estimated tpd**: 3-5ns @ 3.3V (LVC family typical)
- **Operating Voltage**: 1.65V to 5.5V
- **Drive Current**: 24mA @ 3.3V

##### CD74HC4067 16-Channel Analog Multiplexer (×4)
*Source: TI CD74HC4067 Datasheet + Physical Inspection*
- **Confirmed IC Marking**: hp4067 / 42kG4 (G4 underlined) / AT77 (scope verified)
- **Switch Propagation Delay (tPHL, tPLH)**:
  - @ 4.5V: 15ns (25°C)
  - @ 3.3V: ~25ns (estimated)
- **Enable Turn-On Time (tPZH, tPZL)**:
  - @ 4.5V: 55ns (25°C)
  - @ 3.3V: ~90ns (estimated)
- **Operating Voltage**: 2V to 6V
- **On Resistance (RON)**: ~70Ω @ 4.5V

#### Total Cascaded Propagation Delay

**Worst-Case Path Analysis (@ 3.3V, 25°C):**
```
1. CCLK rising edge to counter output     : 20ns  (SN74HC590A)
2. Counter output to decoder output       : 5ns   (SN74LVC1G139)
3. Decoder EN to mux enable               : 90ns  (CD74HC4067 enable)
4. Address change to mux output           : 25ns  (CD74HC4067 switch)
5. Analog signal propagation              : 10ns  (PCB traces)
------------------------------------------------
TOTAL DIGITAL PROPAGATION                 : ~150ns

Plus analog settling:
6. Hall sensor output stabilization       : 500ns (estimated)
7. RC settling (70Ω × 30pF ADC input)    : 100ns
------------------------------------------------
TOTAL SETTLING TIME                       : ~750ns minimum
```

**Optimized Timing Strategy:**
- EN1-EN4 change only every 16 sensors (less critical)
- S0-S3 change every sensor (critical path)
- When only S0-S3 change: ~25ns digital + 500ns analog = 525ns
- When EN changes: ~150ns digital + 600ns analog = 750ns

### Hall Effect Sensor Specifications (DRV5053VA)
*Source: TI DRV5053 Datasheet + Physical Inspection*

#### DRV5053VA High-Sensitivity Analog-Bipolar Hall Effect Sensor
- **Confirmed Variant**: DRV5053VA (IC marking "ALVA" with VA overlined)
- **Manufacturer**: Texas Instruments
- **Type**: Analog bipolar Hall effect sensor - high sensitivity
- **Sensitivity**: -90 mV/mT (2× more sensitive than RA variant)
- **Linear Range**: ±9 mT before saturation (±90 Gauss)
- **Operating Voltage**: 2.5V to 38V (3.3V on tile)
- **Output**: 0.19V to 1.81V (1.0V at zero field)
- **Bandwidth**: ≥20 kHz (internal filtering)
- **Estimated Response Time**: ~50µs (based on 20 kHz BW)
- **Settling Time**: ~25-50µs (estimated from bandwidth)
- **Supply Current**: ~3-5mA typical
- **Output Noise**: 44 mVpp typical (higher than other variants)
- **Temperature Stability**: ±10% sensitivity over temperature

#### Timing Implications
- **Bandwidth-Limited Response**: 1/(2π × 20kHz) ≈ 8µs rise time
- **Practical Settling**: 25-50µs for full-scale step response
- **In Our Application**: Hall sensor response (~50µs) << ADC cycle (10,000µs)
- **Conclusion**: Hall sensors are 200× faster than needed

### Combined System Timing Constraints

#### Multiplexer vs ADC Timing Comparison
| Component | Switching Time | Settling Time | Total |
|-----------|---------------|---------------|-------|
| Multiplexer System | 150ns | 600ns | 750ns |
| ADC Acquisition | - | 1,500ns | 1,500ns |
| ADC Conversion | 8,000ns | - | 8,000ns |

#### System Bottleneck Analysis
1. **Multiplexer switching**: 750ns worst case
2. **ADC settling requirement**: 1,500-2,000ns (dominates)
3. **ADC conversion**: 8,000ns fixed
4. **Total minimum**: 10,000ns per sensor

**Conclusion**: The ADC's analog settling requirement (2µs) is the dominant timing constraint, not the multiplexer cascade (750ns). The multiplexer is ~2.7× faster than required.

### Maximum Clocking Analysis

#### CCLK Maximum Frequency
Based on component limits:
- **Counter max**: 60 MHz (SN74HC590A specification)
- **System requirement**: 100 kHz (10µs per sensor)
- **Actual usage**: 100 kHz << 60 MHz (600× margin)

#### Timing Safety Margins
- Multiplexer cascade: 750ns used, 2,000ns available (267% margin)
- CCLK frequency: 100 kHz used, 60 MHz capable (600× margin)
- Digital propagation: 150ns used, 2,000ns available (1,333% margin)

The system is analog-settling limited, not digitally limited.

### P2 Precision Timing Advantages
The Propeller 2's deterministic timing allows:
- **Exact SPI Clock**: 2.5 MHz using Smart Pins
- **Precise Settling Delays**: 2ns resolution with WAITX
- **Zero Jitter**: No interrupt-induced timing variations
- **Parallel Processing**: Dedicated cog for acquisition

### Optimal P2 Acquisition Sequence
```spin2
' Maximum performance sensor read sequence
' Optimized for P2's deterministic timing
PUB read_sensor_optimal() : value | t
  t := CNT                    ' Capture start time

  ' 1. Advance multiplexer (200ns total)
  OUTH(CCLK_PIN)
  WAITX(#10)                  ' 100ns @ 200MHz (20 clocks)
  OUTL(CCLK_PIN)
  WAITX(#10)                  ' 100ns low

  ' 2. Critical settling period (2µs)
  WAITX(#400)                 ' 2000ns @ 200MHz

  ' 3. Capture and convert (CS falling = sample point)
  OUTL(CS_PIN)
  WAITX(#2)                   ' 10ns CS to SCLK setup

  ' 4. Clock out 20 bits @ 2.5MHz (exactly 400ns per clock)
  repeat 20
    OUTL(SCLK_PIN)
    WAITX(#40)                ' 200ns low (40 clocks @ 200MHz)
    OUTH(SCLK_PIN)
    value := (value << 1) | INA(MISO_PIN)
    WAITX(#40)                ' 200ns high

  ' 5. Complete transaction
  OUTH(CS_PIN)
  WAITX(#20)                  ' 100ns quiet time

  ' Total time: exactly 10.11µs per sensor
  return value >> 4           ' Remove 4 leading zeros
```

### Theoretical vs Practical Performance

#### Theoretical Maximums
- **ADC Spec**: 100 kSPS (single input, continuous)
- **Multiplexer**: >1 MHz switching capability
- **P2 Processing**: 50 MIPS per cog @ 200MHz
- **SPI Bandwidth**: 2.5 MHz (312.5 KB/sec)

#### System Constraints
- **Analog Settling**: 2µs hard minimum after switching
- **Conversion Time**: 8µs fixed (20 clocks @ 2.5MHz)
- **Overhead**: ~110ns (CS setup + quiet time)
- **Cannot Pipeline**: Sample point fixed at CS edge

#### Achievable Performance
| Mode | Per Sensor | Full Frame (64) | Frame Rate |
|------|------------|-----------------|------------|
| Maximum | 10µs | 640µs | 1,562 fps |
| Conservative | 12µs | 768µs | 1,302 fps |
| Safe Margin | 15µs | 960µs | 1,042 fps |
| Reference Arduino | ~50µs | 3,200µs | 312 fps |

### Performance Testing Protocol
*To be completed with actual hardware measurements*

1. **Baseline Test**: Measure actual settling times
2. **Optimization Test**: Reduce margins systematically
3. **Stability Test**: Verify readings at maximum rate
4. **Temperature Test**: Check drift effects on timing
5. **Documentation**: Record actual vs theoretical

### Future Optimization Opportunities
- **Smart Pin SPI**: Hardware-accelerated SPI transfers
- **FIFO Usage**: Stream data via Hub FIFO
- **Parallel ADCs**: Use internal ADC simultaneously
- **Predictive Sampling**: Compensate for known delays

## Signal Characteristics

### Analog Output (AOUT) - DRV5053VA Confirmed
- **Voltage Range**: 0.19V to 1.81V (linear region)
- **Null Field Output**: 1.0V @ 3.3V supply
- **Sensitivity**: -90 mV/mT (high sensitivity variant)
- **Linear Range**: ±9 mT before saturation
- **Output Impedance**: <1kΩ
- **ADC Resolution**: 1,788 counts/mT with AD7680

### Digital Signals
- **Logic Levels**: 3.3V CMOS
- **Rise/Fall Times**: <10ns typical
- **Drive Current**: 4mA per output

## Power Requirements
- **Supply Voltage**: 3.3V ±5%
- **Current Consumption**:
  - Active scanning: ~50mA
  - Idle state: ~20mA
- **Decoupling**: 0.1µF ceramic capacitor required

## Environmental Specifications
- **Operating Temperature**: -20°C to +70°C
- **Magnetic Field Range**: ±100mT typical
- **Interference**: Shield from strong AC magnetic fields

## Communication Protocol

### Serial Data Format
- **Baud Rate**: 115200 bps
- **Data Format**: 8N1 (8 data bits, no parity, 1 stop bit)
- **Frame Format**:
  ```
  value1 value2 value3 value4 value5 value6 value7 value8\n
  [repeated for 8 rows]
  *\n
  ```
- **Value Range**: -8192 to +8191 (14-bit signed)

### Command Set
| Command | Action |
|---------|--------|
| L | Start live mode (continuous frames) |
| S | Stop acquisition |
| 1 | High-speed mode 1 (buffered) |
| 2 | High-speed mode 2 (buffered) |
| 3 | High-speed mode 3 (buffered) |
| 4 | High-speed mode 4 (buffered) |
| P | Pixel test pattern |

## Integration Notes

### P2 Cog Allocation (Suggested)
- **Cog 0**: Main control and serial communication
- **Cog 1**: Sensor scanning and ADC interface
- **Cog 2**: Display output (separate OLED driver)
- **Cog 3**: Data processing and calibration

### Memory Requirements
- **Raw Frame**: 64 × 2 bytes = 128 bytes
- **Calibration Data**: 64 × 2 bytes = 128 bytes
- **Frame Buffer**: Variable (10-100 frames typical)
- **Total Estimate**: 8-16KB for data acquisition subsystem

## References
- Original Arduino Implementation: See `DOCs/REF-Implementation/`
- Sensor Datasheet: Available from SparkFun product page
- AD7680 Datasheet: See `DOCs/AD7680.pdf`
- Maximum ADC SPI Clock: 2.5 MHz (per AD7680 datasheet)