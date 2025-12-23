# Magnetic Tile Sensor Mapping Test Protocol

**Document Version:** 1.1
**Last Updated:** 2025-12-23
**Status:** Updated with orientation terminology and test results

## Purpose
Verify that the hardware sensor positions match our documented mapping by using controlled magnetic field testing with visual feedback.

## Test Principle
By holding the counter at specific values, we can continuously read a single sensor while physically moving a magnet across the tile. The OLED display will show which pixel responds, allowing us to verify the sensor's physical location matches our mapping documentation.

## Physical Orientation Reference

**CRITICAL: All position references use this orientation:**

```
                    TOP (away from connector)
              ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
              │ TL  │     │     │     │     │     │     │ TR  │  row 0
              ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
              │     │     │     │     │     │     │     │     │  row 1
              │     │                 ...                │     │  ...
              │     │     │     │     │     │     │     │     │  row 6
              ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
              │ BL  │     │     │     │     │     │     │ BR  │  row 7
              └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
                col 0                                   col 7
                    BOTTOM (connector edge)
```

**Terminology:**
- **Connector Edge** = BOTTOM of the tile (where the ribbon cable attaches)
- **Top-Left (TL)** = Upper-left corner when viewing with connector at bottom
- **Top-Right (TR)** = Upper-right corner when viewing with connector at bottom
- **Bottom-Left (BL)** = Lower-left corner (near connector, left side)
- **Bottom-Right (BR)** = Lower-right corner (near connector, right side)

**Quadrant Layout (Physical):**
```
┌────────────┬────────────┐
│  Upper-Left│ Upper-Right│   ← TOP (rows 0-3)
│   (UL)     │    (UR)    │
├────────────┼────────────┤
│ Lower-Left │Lower-Right │   ← BOTTOM (rows 4-7)
│   (LL)     │    (LR)    │
└────────────┴────────────┘
   cols 0-3     cols 4-7
        CONNECTOR EDGE
```

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

**Hardware Reading Order (from counter bit decoding):**
```
Counter Bits [5:4] → EN Signal → Physical Quadrant
     00 (0-15)    →    EN1    → Upper-Left  (UL)
     01 (16-31)   →    EN2    → Upper-Right (UR)
     10 (32-47)   →    EN3    → Lower-Left  (LL)
     11 (48-63)   →    EN4    → Lower-Right (LR)
```

**Note:** Software subtile_order array remaps this to: UL → UR → LL → LR for anti-crosstalk

1. **Set counter to 0** (EN1, Channel 0)
   - Move magnet across entire tile
   - Verify response only in **Upper-Left** quadrant (physical rows 0-3, cols 0-3)
   - Document which physical sensor responds

2. **Set counter to 16** (EN3, Channel 0)
   - Move magnet across entire tile
   - Verify response only in **Lower-Left** quadrant (physical rows 4-7, cols 0-3)
   - Document which physical sensor responds

3. **Set counter to 32** (EN2, Channel 0)
   - Move magnet across entire tile
   - Verify response only in **Upper-Right** quadrant (physical rows 0-3, cols 4-7)
   - Document which physical sensor responds

4. **Set counter to 48** (EN4, Channel 0)
   - Move magnet across entire tile
   - Verify response only in **Lower-Right** quadrant (physical rows 4-7, cols 4-7)
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

## Test Results Log

### Test Session: 2025-12-23

**Configuration:**
- P2 @ 250 MHz
- AD7940 14-bit ADC (external)
- SLOW_SCAN_MODE enabled (2 second intervals)
- 90° CCW rotation correction applied

#### Full Tile Corner Test (Post-Rotation)

| Physical Corner | Expected Buffer Position | Actual Buffer Position | Status |
|----------------|-------------------------|----------------------|--------|
| Top-Left       | Row 0, Cols 0-1         | Row 0, Cols 0-1      | PASS   |
| Top-Right      | Row 0, Cols 6-7         | Row 0, Cols 6-7      | PASS   |
| Bottom-Right   | Row 7, Cols 6-7         | Row 7, Cols 6-7      | PASS   |
| Bottom-Left    | Row 7, Cols 0-1         | Row 7, Cols 0-1      | PASS   |

**Result:** Full tile rotation correction working correctly.

#### Upper-Left Quadrant Corner Test

| Quadrant Corner | Expected Position | Actual Position | Status |
|----------------|-------------------|-----------------|--------|
| Top-Left       | Row 0, Cols 0-1   | Row 0, Cols 0-1 | PASS   |
| Top-Right      | Row 0, Cols 2-3   | Row 0, Cols 2-3 | PASS   |
| Bottom-Right   | Row 3, Cols 2-3   | Row 5, Cols 2-3 | FAIL   |
| Bottom-Left    | Row 3, Cols 0-1   | Row 5, Cols 0-1 | FAIL   |

**Finding:** Within-quadrant mapping has vertical offset error. Bottom half of quadrant appears ~2 rows lower than expected.

**Root Cause Analysis:**
The `pixel_order[]` lookup table doesn't match the actual hardware channel-to-position mapping from the schematic. The schematic shows:
```
Counter  Channel  Physical Position (Row,Col within quadrant)
0        0        (2,3)
1        1        (3,3)
2        2        (2,2)
...
8        8        (1,0)
9        9        (0,0)
...
```

Current `pixel_order[]`: `26, 27, 18, 19, 10, 11, 2, 3, 1, 0, 9, 8, 17, 16, 25, 24`
Required mapping (from schematic): Different pattern

**Next Step:** Derive unified 64-entry mapping table from hardware schematic that combines subtile ordering, channel mapping, and rotation correction into a single lookup.

## Notes

- Temperature may affect sensor sensitivity - test at room temperature
- Strong magnets may activate adjacent sensors - use moderate field strength
- Allow sensors to stabilize between tests
- Document any anomalies for troubleshooting
- Save test results for future reference

This physical verification method provides ground truth for the sensor mapping and ensures the P2 implementation correctly interprets the hardware layout.