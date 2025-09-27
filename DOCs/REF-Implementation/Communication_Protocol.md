# SparkFun Magnetic Imaging Tile Communication Protocol

## Overview

The SparkFun Magnetic Imaging Tile requires coordinated communication with two separate hardware subsystems to acquire magnetic field measurements from its 8x8 Hall effect sensor array:

1. **Scanning Circuitry**: Hardware multiplexer/counter that selects which sensor is active
2. **AD7940 ADC**: 14-bit Analog-to-Digital Converter that digitizes the sensor output

## Device 1: Scanning Circuitry Protocol

### Hardware Interface
- **PIN_CLR (Digital Pin 8)**: Counter clear/reset signal
- **PIN_CLK (Digital Pin 9)**: Counter increment clock signal

### Control Signals

#### Counter Reset Operation
```
Function: clearCounter()
Purpose: Initialize the hardware counter to sensor position 0

Protocol:
1. Assert PIN_CLR = LOW  (active reset)
2. Deassert PIN_CLR = HIGH (release reset)

Timing: No delays required for modern microcontrollers
```

#### Counter Increment Operation
```
Function: incrementCounter()
Purpose: Advance to the next sensor in the multiplexer sequence

Protocol:
1. Assert PIN_CLK = HIGH   (rising edge trigger)
2. Deassert PIN_CLK = LOW  (complete clock cycle)

Timing: No delays required for modern microcontrollers
```

### Sensor Addressing Scheme
- **Physical Sensors**: 64 total (8x8 grid)
- **Hardware Organization**: 4 subtiles of 16 sensors each
- **Counter Range**: 0-63 (6-bit counter)

## Device 2: AD7940 ADC SPI Protocol

### Hardware Interface
- **AD7940_SPI_CS (Digital Pin 10)**: Chip Select (active LOW)
- **AD7940_SPI_CLK (Digital Pin 13)**: SPI Clock
- **AD7940_SPI_MISO (Digital Pin 12)**: Master In, Slave Out (data)

### SPI Transaction Protocol

#### Idle State
```
CS = HIGH    (ADC disabled)
CLK = HIGH   (clock idle high)
```

#### Data Acquisition Transaction
```
Function: readAD7940()
Purpose: Read 14-bit ADC value from currently selected sensor

Protocol:
1. SETUP PHASE:
   - Set CS = HIGH, CLK = HIGH (ensure idle state)

2. ENABLE PHASE:
   - Set CS = LOW (enable ADC for transaction)

3. DATA PHASE (16 clock cycles):
   For i = 0 to 15:
     a. Read MISO bit
     b. Set CLK = LOW  (falling edge)
     c. Shift bit into result: value = (value << 1) | bit
     d. Set CLK = HIGH (rising edge)

4. DISABLE PHASE:
   - Set CS = HIGH (disable ADC, end transaction)

Return: 16-bit value (14-bit ADC data + status bits)
```

#### SPI Timing Characteristics
- **Clock Mode**: Mode 0 (CPOL=0, CPHA=0)
- **Bit Rate**: Limited by digitalWrite() speed (~100-500 kHz)
- **Data Valid**: On CLK falling edge
- **MSB First**: Most significant bit transmitted first

## Complete Scan Sequence Protocol

### Full Frame Acquisition
```
Function: readTileFrame()
Purpose: Acquire all 64 sensor readings in correct spatial order

INITIALIZATION:
1. clearCounter()        // Reset to sensor 0
2. incrementCounter()    // Advance to sensor 1 (first active sensor)

SCAN LOOP:
For each subtile (0, 2, 1, 3):  // Note: non-sequential order
  For each sensor in subtile (0-15):

    STEP 1: READ SENSOR
    - Call readAD7940()     // SPI transaction with ADC
    - Store raw ADC value

    STEP 2: MAP TO FRAME BUFFER
    - Apply pixelOrder[sensor] lookup
    - Apply subtileOffset[subtile] lookup
    - Store value at: frame[pixelOrder[sensor] + subtileOffset[subtile]]

    STEP 3: ADVANCE TO NEXT SENSOR
    - Call incrementCounter()  // Clock scanning circuitry

END SCAN LOOP

Result: frame[64] array with spatially-correct sensor readings
```

### Physical Subtile Organization
```
8x8 Full Array Layout:
┌─────────┬─────────┐
│ Subtile │ Subtile │
│    0    │    2    │  ← Scanned 1st, 2nd
│  (0-15) │ (16-31) │
├─────────┼─────────┤
│ Subtile │ Subtile │
│    1    │    3    │  ← Scanned 3rd, 4th
│ (32-47) │ (48-63) │
└─────────┴─────────┘

Scan Order:        0  2    (subtileOrder[] = {0, 2, 1, 3})
                   1  3

Frame Offsets:     0  4    (subtileOffset[] = {0, 4, 32, 36})
                  32 36
```

### Physical Sensor Arrangement Within Each Subtile
Each 4x4 subtile follows a **serpentine scanning pattern** to minimize PCB routing complexity:

```
4x4 Subtile Internal Layout (showing frame buffer positions):
┌────┬────┬────┬────┐
│ 10 │ 11 │  2 │  3 │  ← Counter 4,5,6,7
├────┼────┼────┼────┤
│  9 │  8 │  1 │  0 │  ← Counter 10,11,8,9
├────┼────┼────┼────┤
│ 26 │ 27 │ 18 │ 19 │  ← Counter 0,1,2,3
├────┼────┼────┼────┤
│ 25 │ 24 │ 17 │ 16 │  ← Counter 14,15,12,13
└────┴────┴────┴────┘

Hardware Scanning Pattern:
1. Bottom row: left→right (26,27,18,19)
2. Third row: right→left (3,2,11,10)
3. Second row: right→left (1,0,9,8)
4. Top row: left→right (17,16,25,24)
```

### Pixel Remapping Algorithm
```
Hardware Counter Sequence: 0, 1, 2, 3, ..., 15 (within each subtile)
Physical Pixel Mapping:    pixelOrder[] = {26, 27, 18, 19, 10, 11, 2, 3,
                                          1, 0, 9, 8, 17, 16, 25, 24}

Counter-to-Position Mapping:
Counter:  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
Pixel:   26 27 18 19 10 11  2  3  1  0  9  8 17 16 25 24

Example for Subtile 0:
Counter=0 → Pixel 26 → Frame[26+0] = Frame[26]   (bottom-left of subtile)
Counter=1 → Pixel 27 → Frame[27+0] = Frame[27]   (bottom row, next right)
Counter=2 → Pixel 18 → Frame[18+0] = Frame[18]   (continue right)
Counter=3 → Pixel 19 → Frame[19+0] = Frame[19]   (bottom-right of subtile)
Counter=4 → Pixel 10 → Frame[10+0] = Frame[10]   (third row, right-to-left)
...etc

Note: The serpentine pattern reduces electromagnetic interference and
      minimizes trace crossings on the PCB layout.
```

## Inter-Device Synchronization

### Critical Timing Requirements
1. **ADC Settling**: Allow sensor output to stabilize before SPI read
2. **Counter Setup**: Ensure multiplexer switches before ADC acquisition
3. **Frame Coherency**: Complete scan sequence without interruption

### Recommended Implementation
```
For maximum frame rate:
1. Minimize delays between operations
2. Use optimized digitalWrite() implementations
3. Consider DMA for SPI transfers (advanced implementations)
4. Batch process frames for high-speed capture modes

For maximum accuracy:
1. Add small delays after incrementCounter() for settling
2. Multiple ADC samples with averaging
3. Implement ADC oversampling for noise reduction
```

## Error Handling and Diagnostics

### Counter Verification
- Monitor expected vs actual scan positions
- Implement counter state verification
- Reset sequence on detected errors

### ADC Validation
- Check for stuck bits or saturated readings
- Monitor for SPI communication errors
- Validate data range and consistency

### Frame Buffer Integrity
- Verify complete frame acquisition
- Check for missing or duplicated samples
- Implement frame sequence numbering

## Platform-Specific Considerations

### Arduino Uno/Nano
- Limited RAM: Minimize frame buffering
- Slower GPIO: May require timing adjustments
- Serial bottleneck: Consider compressed data formats

### SAMD21/SAMD51
- Fast GPIO: Optimal for high-speed scanning
- Large RAM: Support for extensive frame buffering
- Hardware SPI: Consider using SPI peripheral for ADC

### ChipKit MAX32
- Original target platform
- 128KB RAM: Excellent for frame buffering
- 80MHz CPU: High-performance scanning capability