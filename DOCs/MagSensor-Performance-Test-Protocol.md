# Sensor Maximum Frame Rate Characterization Protocol

## Purpose
Determine the absolute maximum frame rate of the magnetic tile sensor array and identify failure modes when timing constraints are violated.

## Test Strategy

### Phase 1: Baseline Performance Verification
Establish known-good operation before pushing limits.

### Phase 2: Progressive Speed Increase
Systematically reduce timing delays until failure occurs.

### Phase 3: Failure Mode Analysis
Characterize how the system degrades when pushed beyond limits.

## Hardware Setup

### Required Test Configuration
```
1. P2 Development Board @ 340 MHz
2. Magnetic Imaging Tile connected
3. OLED display for visual feedback
4. Serial terminal for data logging
5. Oscilloscope on critical signals (optional but recommended):
   - CCLK (P41)
   - CS (P40)
   - SCLK (P44)
   - AOUT (P46)
```

### Test Stimulus
- **Static Test**: Strong neodymium magnet fixed at specific sensor positions
- **Dynamic Test**: Rotating magnetic field source (motor with magnets)
- **Known Pattern**: Checkerboard of magnets for pattern verification

## Spin2 Test Implementation

### Core Test Engine

```spin2
CON
  _CLKFREQ = 340_000_000

  ' Pin definitions
  CS_PIN   = 40
  CCLK_PIN = 41
  MISO_PIN = 42
  CLRb_PIN = 43
  SCLK_PIN = 44
  AOUT_PIN = 46

  ' Test parameters
  MIN_SETTLE_TIME = 50     ' Start with 50 sysclock cycles (~147ns)
  MAX_SETTLE_TIME = 3400   ' Maximum 10µs

VAR
  long frameCount
  long errorCount
  long settleTime
  word referenceFrame[64]
  word currentFrame[64]
  long timestamps[100]
  byte errorMap[64]

PUB main() | testMode
  setup_pins()
  serial.start(115200)
  serial.str(string("Magnetic Tile Performance Characterization", 13, 10))

  ' Get baseline reference
  establish_baseline()

  ' Run test sequence
  repeat testMode from 0 to 4
    case testMode
      0: test_progressive_speedup()
      1: test_minimum_settling()
      2: test_adc_limits()
      3: test_counter_limits()
      4: test_pattern_integrity()

  report_results()

PUB establish_baseline()
  serial.str(string("Establishing baseline with conservative timing...", 13, 10))

  ' Read at known-safe speed (10µs per sensor)
  settleTime := 3400  ' 10µs at 340MHz

  repeat 10
    read_full_frame(@referenceFrame, settleTime)
    waitms(100)

  ' Display reference values
  display_frame(@referenceFrame, string("BASELINE"))

PUB test_progressive_speedup() | speed, stable, iteration
  serial.str(string(13, 10, "TEST 1: Progressive Speed Increase", 13, 10))

  settleTime := MAX_SETTLE_TIME
  stable := true

  repeat while settleTime > MIN_SETTLE_TIME AND stable
    errorCount := 0
    frameCount := 0

    ' Test this speed for 1000 frames
    repeat 1000
      read_full_frame(@currentFrame, settleTime)
      frameCount++

      if not verify_frame(@currentFrame)
        errorCount++

    ' Calculate metrics
    serial.str(string("Settle time: "))
    serial.dec(settleTime * 1000 / 340)  ' Convert to ns
    serial.str(string("ns, FPS: "))
    serial.dec(calculate_fps(settleTime))
    serial.str(string(", Errors: "))
    serial.dec(errorCount)
    serial.str(string("/1000", 13, 10))

    ' Check if still stable (less than 1% errors)
    stable := (errorCount < 10)

    ' Reduce settling time by 5%
    settleTime := settleTime * 95 / 100

PUB test_minimum_settling() | sensor, value, lastValue, changes
  serial.str(string(13, 10, "TEST 2: Minimum Settling Time Analysis", 13, 10))

  ' Test each settling time increment
  repeat settleTime from 100 to 3400 step 100
    changes := 0

    ' Read same sensor multiple times
    repeat sensor from 0 to 63
      set_sensor_address(sensor)
      waitx(settleTime)

      ' Take multiple readings
      lastValue := read_adc_value()
      repeat 10
        value := read_adc_value()
        if ||value - lastValue|| > 100  ' Threshold for stability
          changes++
        lastValue := value

    serial.str(string("Settling "))
    serial.dec(settleTime * 1000 / 340)
    serial.str(string("ns: "))
    serial.dec(changes)
    serial.str(string(" unstable readings", 13, 10))

    if changes == 0
      serial.str(string(">>> MINIMUM SETTLING TIME FOUND: "))
      serial.dec(settleTime * 1000 / 340)
      serial.str(string("ns <<<", 13, 10))
      quit

PUB test_adc_limits() | maxClock, adcClock, errors
  serial.str(string(13, 10, "TEST 3: ADC Clock Speed Limits", 13, 10))

  ' Start at safe 2.5MHz, increase until failure
  maxClock := 2_500_000

  repeat adcClock from 2_500_000 to 5_000_000 step 100_000
    errors := 0

    ' Configure SPI clock divider
    configure_spi_speed(adcClock)

    ' Test 100 frames at this speed
    repeat 100
      read_full_frame(@currentFrame, 2000)  ' Fixed settling

      ' Check for ADC communication errors
      if not verify_adc_data(@currentFrame)
        errors++

    serial.str(string("ADC Clock: "))
    serial.dec(adcClock/1000)
    serial.str(string(" kHz, Errors: "))
    serial.dec(errors)

    if errors > 0
      serial.str(string(" <- ADC LIMIT REACHED"))
      maxClock := adcClock - 100_000
      quit

    serial.str(13, 10)

  serial.str(string("Maximum reliable ADC clock: "))
  serial.dec(maxClock/1000)
  serial.str(string(" kHz", 13, 10))

PUB test_counter_limits() | cclkPeriod, errors
  serial.str(string(13, 10, "TEST 4: Counter Clock Speed Limits", 13, 10))

  ' Test progressively faster counter clocking
  repeat cclkPeriod from 200 downto 10 step 10
    errors := 0

    ' Reset counter
    OUTL(CLRb_PIN)
    waitx(100)
    OUTH(CLRb_PIN)

    ' Clock through all 64 positions quickly
    repeat 64
      OUTH(CCLK_PIN)
      waitx(cclkPeriod/2)
      OUTL(CCLK_PIN)
      waitx(cclkPeriod/2)

    ' Verify we're back at position 0
    if read_sensor_position() <> 0
      errors++

    serial.str(string("CCLK period: "))
    serial.dec(cclkPeriod * 1000 / 340)
    serial.str(string("ns, "))

    if errors > 0
      serial.str(string("COUNTER FAILED!", 13, 10))
      quit
    else
      serial.str(string("OK", 13, 10))

PUB test_pattern_integrity() | pattern, sensor
  serial.str(string(13, 10, "TEST 5: Pattern Integrity at Speed", 13, 10))

  ' Place known magnetic pattern (checkerboard)
  serial.str(string("Place checkerboard magnet pattern and press any key...", 13, 10))
  serial.rx()  ' Wait for user

  ' Read at different speeds and check pattern
  repeat settleTime from 3400 to 340 step -340
    read_full_frame(@currentFrame, settleTime)

    pattern := detect_checkerboard(@currentFrame)

    serial.str(string("Speed: "))
    serial.dec(calculate_fps(settleTime))
    serial.str(string(" fps, Pattern match: "))
    serial.dec(pattern)
    serial.str(string("%", 13, 10))

    if pattern < 80
      serial.str(string(">>> PATTERN DEGRADATION at "))
      serial.dec(calculate_fps(settleTime))
      serial.str(string(" fps", 13, 10))
      quit

' --- Helper Functions ---

PUB read_full_frame(buffer, settling) | sensor
  ' Reset counter to sensor 0
  OUTL(CLRb_PIN)
  waitx(34)  ' 100ns
  OUTH(CLRb_PIN)
  waitx(34)

  ' Read all 64 sensors
  repeat sensor from 0 to 63
    ' Advance counter
    if sensor > 0
      OUTH(CCLK_PIN)
      waitx(34)  ' 100ns high
      OUTL(CCLK_PIN)
      waitx(34)  ' 100ns low

    ' Wait for settling
    waitx(settling)

    ' Read ADC
    word[buffer][sensor] := read_adc_value()

PUB read_adc_value() : value | bit
  ' Bit-bang SPI read at safe speed
  OUTL(CS_PIN)
  waitx(3)  ' 10ns setup

  repeat 20
    OUTL(SCLK_PIN)
    waitx(68)  ' 200ns @ 340MHz
    OUTH(SCLK_PIN)
    value := (value << 1) | INA(MISO_PIN)
    waitx(68)

  OUTH(CS_PIN)

  ' Extract 16-bit value from 20-bit frame
  value >>= 4

PUB verify_frame(buffer) : valid | sensor, expected, tolerance
  valid := true
  tolerance := 500  ' ADC counts tolerance

  ' Check against reference frame
  repeat sensor from 0 to 63
    expected := word[@referenceFrame][sensor]

    if ||word[buffer][sensor] - expected|| > tolerance
      errorMap[sensor]++
      valid := false

PUB verify_adc_data(buffer) : valid | sensor
  valid := true

  ' Check for ADC communication errors
  repeat sensor from 0 to 63
    ' Check for stuck bits (all 0s or all 1s)
    if word[buffer][sensor] == 0 OR word[buffer][sensor] == $FFFF
      valid := false

    ' Check for unrealistic values (outside sensor range)
    if word[buffer][sensor] < 3000 OR word[buffer][sensor] > 40000
      valid := false

PUB detect_checkerboard(buffer) : matchPercent | x, y, expected, matches
  matches := 0

  repeat y from 0 to 7
    repeat x from 0 to 7
      ' Checkerboard pattern expectation
      expected := (x + y) & 1  ' 0 or 1

      ' Check if sensor matches expected (high or low)
      if expected
        if word[buffer][y * 8 + x] > 25000  ' High field
          matches++
      else
        if word[buffer][y * 8 + x] < 15000  ' Low field
          matches++

  matchPercent := matches * 100 / 64

PUB calculate_fps(settleClocks) : fps | totalClocks
  ' Calculate frame rate based on settling time
  totalClocks := settleClocks + 68 + 68*20 + 100  ' settle + overhead + ADC
  totalClocks *= 64  ' 64 sensors

  fps := 340_000_000 / totalClocks

PUB display_frame(buffer, title) | sensor, x, y
  serial.str(string(13, 10, "--- "))
  serial.str(title)
  serial.str(string(" ---", 13, 10))

  repeat y from 0 to 7
    repeat x from 0 to 7
      sensor := y * 8 + x
      serial.hex(word[buffer][sensor], 4)
      serial.str(string(" "))
    serial.str(13, 10)

PUB report_results() | sensor, maxErrors
  serial.str(string(13, 10, "=== PERFORMANCE CHARACTERIZATION COMPLETE ===", 13, 10))

  ' Find maximum frame rate achieved
  serial.str(string("Maximum stable frame rate: TBD fps", 13, 10))

  ' Report problematic sensors
  serial.str(string(13, 10, "Sensor error distribution:", 13, 10))
  maxErrors := 0
  repeat sensor from 0 to 63
    if errorMap[sensor] > 0
      serial.str(string("Sensor "))
      serial.dec(sensor)
      serial.str(string(": "))
      serial.dec(errorMap[sensor])
      serial.str(string(" errors", 13, 10))

      if errorMap[sensor] > maxErrors
        maxErrors := errorMap[sensor]

  if maxErrors == 0
    serial.str(string("No sensor-specific errors detected!", 13, 10))
```

## Failure Modes to Detect

### 1. **Settling Time Violations**
**Symptom**: Readings don't stabilize, values drift between reads
**Detection**: Compare multiple rapid reads of same sensor
**Threshold**: >100 ADC counts variation

### 2. **ADC Communication Failure**
**Symptom**: Corrupted SPI data, stuck bits
**Detection**:
- All 0s or all 1s in data
- Values outside valid range (3,770 - 35,948)
- Parity/checksum errors if available

### 3. **Counter Skipping**
**Symptom**: Wrong sensors being read
**Detection**: Pattern mismatch with known magnetic configuration
**Fix**: Slower CCLK or longer pulses

### 4. **Multiplexer Crosstalk**
**Symptom**: Adjacent sensors influence readings
**Detection**: Checkerboard pattern degradation
**Threshold**: <80% pattern match

### 5. **Analog Bus Saturation**
**Symptom**: All readings converge to similar values
**Detection**: Loss of contrast between sensors
**Measurement**: Standard deviation drops below threshold

## Expected Results

### Theoretical Limits
```
Component Limits:
- Counter (HC590A): 60 MHz max = 16.7ns period
- Decoder (LVC1G139): ~5ns propagation
- Mux (HC4067): ~25ns switch + 90ns enable
- Hall sensor: ~50µs bandwidth limit (slow!)
- ADC: 2.5 MHz SPI, 100 kSPS max

Bottleneck Analysis:
1. Hall sensor bandwidth: 20 kHz = 50µs response
2. ADC settling: 2µs recommended
3. Mux settling: ~500ns analog
4. Digital switching: ~150ns total
```

### Predicted Maximum Frame Rates

| Timing Parameter | Conservative | Aggressive | Bleeding Edge |
|-----------------|--------------|------------|---------------|
| Settling time | 2µs | 1µs | 500ns |
| ADC clock | 2.5 MHz | 3 MHz | 4 MHz |
| Frame rate | 1,300 fps | 1,800 fps | 2,500 fps |
| Reliability | 100% | 95% | 50% |

### Failure Progression

```
1,000 fps: Perfect operation
1,300 fps: Baseline maximum
1,500 fps: Occasional sensor errors
1,800 fps: Pattern degradation begins
2,000 fps: Significant errors
2,500 fps: System breakdown
3,000 fps: Complete failure
```

## Visual Feedback During Test

### OLED Display Shows:
```
╔════════════════════════════╗
║ PERFORMANCE TEST MODE      ║
║                            ║
║ Current FPS: 1,432         ║
║ Settling: 1,850 ns         ║
║ Errors: 2/1000             ║
║                            ║
║ [████████████████░░░░░░░]  ║
║         72% Stable         ║
║                            ║
║ Problem Sensors: 23, 45    ║
╚════════════════════════════╝
```

## Data Logging Format

```csv
# Magnetic Tile Performance Test Log
# Date: 2024-11-DD HH:MM:SS
# P2 Clock: 340 MHz
#
FrameRate,SettlingTime_ns,ADC_Clock_kHz,Errors,Pattern_Match,Notes
1000,2000,2500,0,100,Baseline
1100,1800,2500,0,100,Stable
1200,1600,2500,0,99,Stable
1300,1400,2500,1,98,Minor errors
1400,1200,2500,5,95,Degrading
1500,1000,2500,23,87,Unstable
1600,800,2500,124,72,Failing
```

## Recommendations for Testing

1. **Start Conservative**: Begin with known-good timing
2. **Use Fixed Magnet**: Eliminates variable of moving field
3. **Monitor Temperature**: Performance may vary with heating
4. **Test Multiple Tiles**: Manufacturing variations exist
5. **Document Everything**: This data is valuable for optimization

## Post-Test Analysis

### Key Metrics to Extract:
- **Absolute maximum stable frame rate**
- **Optimal settling time for 99% reliability**
- **Which sensors fail first** (edge effects?)
- **Temperature coefficient** of performance
- **Long-term stability** (does it degrade over hours?)

### Success Criteria:
- ✅ Achieve >1,300 fps reliably
- ✅ Identify exact failure point
- ✅ Understand failure mechanisms
- ✅ Create optimization guidelines

This test protocol will definitively establish the performance envelope of your magnetic imaging tile!