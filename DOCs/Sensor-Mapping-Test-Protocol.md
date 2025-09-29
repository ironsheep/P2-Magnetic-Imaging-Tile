# Magnetic Tile Sensor Mapping Test Protocol

## Purpose
Verify that the hardware sensor positions match our documented mapping by using controlled magnetic field testing with visual feedback.

## Test Principle
By holding the counter at specific values, we can continuously read a single sensor while physically moving a magnet across the tile. The OLED display will show which pixel responds, allowing us to verify the sensor's physical location matches our mapping documentation.

## Test Setup

### Required Equipment
- P2 development board with magnetic tile connected
- OLED display showing real-time sensor values
- Small neodymium magnet (known polarity marked)
- Physical grid overlay or ruler for the sensor tile
- Documentation of expected mapping

### Software Requirements
```spin2
' Test mode: Hold counter at specific value
PUB test_single_sensor(sensor_num) | value
  ' Clear counter
  OUTL(CLRb_PIN)
  waitus(1)
  OUTH(CLRb_PIN)

  ' Clock to desired sensor (0-63)
  repeat sensor_num
    OUTH(CCLK_PIN)
    waitus(1)
    OUTL(CCLK_PIN)
    waitus(1)

  ' Continuously read this sensor
  repeat
    value := read_adc()
    display_single_pixel(sensor_num, value)
    if key_pressed()
      quit  ' Exit on keypress
```

## Test Procedure

### Phase 1: Quadrant Verification
Verify which physical quadrant each EN signal controls:

1. **Set counter to 0** (EN1, Channel 0)
   - Move magnet across entire tile
   - Verify response only in upper-left quadrant
   - Document which physical sensor responds

2. **Set counter to 16** (EN2, Channel 0)
   - Move magnet across entire tile
   - Verify response only in upper-right quadrant
   - Document which physical sensor responds

3. **Set counter to 32** (EN3, Channel 0)
   - Move magnet across entire tile
   - Verify response only in lower-left quadrant
   - Document which physical sensor responds

4. **Set counter to 48** (EN4, Channel 0)
   - Move magnet across entire tile
   - Verify response only in lower-right quadrant
   - Document which physical sensor responds

### Phase 2: Detailed Mapping Verification

For each quadrant, verify the channel-to-position mapping:

#### Upper-Left Quadrant (EN1) Test Sequence
```
Counter  Expected Position  Verify Location
0        Row 2, Col 3      Middle-right of quadrant
1        Row 3, Col 3      Bottom-right of quadrant
2        Row 2, Col 2      Middle-center of quadrant
3        Row 3, Col 2      Bottom-center of quadrant
...continue for all 16 channels
```

#### Test Steps:
1. Set counter to test value (0-15 for first quadrant)
2. Move magnet slowly across the quadrant
3. Note which physical sensor shows response
4. Compare to expected position
5. Record any discrepancies

### Phase 3: Cross-Talk Verification

Test that non-adjacent sensors in the read sequence are physically separated:

1. **Set counter to 0** (sensor 1/0)
   - Place magnet directly on responding sensor
   - Note signal strength

2. **Advance counter to 1** (sensor 1/1)
   - Keep magnet in same physical position
   - Verify minimal/no signal (sensors should be physically separated)

3. **Continue sequence** (2, 3, 4...)
   - Verify each consecutive read is physically distant from previous

## Expected Results vs Actual Mapping

### Expected (From Schematic):
```
Physical Layout (All Quadrants):
     Col0   Col1   Col2   Col3
Row0  Ch9   Ch11   Ch13   Ch15
Row1  Ch8   Ch10   Ch12   Ch14
Row2  Ch6   Ch4    Ch2    Ch0
Row3  Ch7   Ch5    Ch3    Ch1
```

### Test Recording Template:
```
Test Date: _________
Tester: _________
Hardware Version: _________

Counter | Expected Sensor | Expected Position | Actual Position | Match? | Notes
--------|-----------------|-------------------|-----------------|--------|-------
0       | 1/0             | Q1:R2,C3         |                 | [ ]    |
1       | 1/1             | Q1:R3,C3         |                 | [ ]    |
2       | 1/2             | Q1:R2,C2         |                 | [ ]    |
...
```

## Display Mapping Verification

### Visual Test Pattern
Create a test pattern that lights up one sensor at a time:
1. Display should show single lit pixel
2. Physical magnet position should correlate with display position
3. If using correct mapping, physical and display positions align

### Incorrect Mapping Symptoms:
- Magnet in upper-left but display shows different quadrant
- Magnet movement doesn't match display movement direction
- Multiple pixels respond when expecting single pixel
- No response in expected location

## Test Automation

### Automated Scan Mode
```spin2
PUB automated_test() | sensor, start_time
  ' Scan all 64 sensors with pause for manual verification
  repeat sensor from 0 to 63
    clear_display()

    ' Show which sensor we're testing
    display_text("Testing sensor: ", sensor)
    display_text("Expected: ", get_expected_position(sensor))

    ' Hold this sensor for 5 seconds
    start_time := CNT
    repeat while (CNT - start_time) < (CLKFREQ * 5)
      test_single_sensor(sensor)

    ' Wait for confirmation
    wait_for_keypress()
```

## Success Criteria

### Mapping is Correct When:
1. Each counter value activates exactly one physical sensor
2. Physical sensor locations match documented positions
3. Sequential counter values show physical separation (anti-crosstalk design)
4. All 64 sensors respond and are unique
5. Display mapping shows correct spatial relationship

### Mapping Needs Correction When:
1. Physical positions don't match documentation
2. Multiple sensors respond to single counter value
3. Dead spots (no response) at expected positions
4. Display shows activity in wrong location

## Corrective Actions

If mapping doesn't match:

1. **Document Actual Mapping**: Create new map based on test results
2. **Update Software**: Modify pixelOrder[] array to match reality
3. **Verify Schematic**: Check if PCB matches schematic
4. **Check Connections**: Verify all signals properly connected
5. **Test Different Board**: Confirm if issue is specific to one board

## Alternative Test Method

### Binary Search Mapping
If completely unknown mapping:
1. Set counter to 0
2. Systematically probe each physical position with magnet
3. Record which counter value responds at each position
4. Build complete mapping table from scratch

## Notes

- Temperature may affect sensor sensitivity - test at room temperature
- Strong magnets may activate adjacent sensors - use moderate field strength
- Allow sensors to stabilize between tests
- Document any anomalies for troubleshooting
- Save test results for future reference

This physical verification method provides ground truth for the sensor mapping and ensures the P2 implementation correctly interprets the hardware layout.