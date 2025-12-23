# ADC Implementation Strategy for Magnetic Imaging Tile

## Executive Summary

We have identified four distinct ADC approaches for the magnetic imaging tile, ranging from the existing AD7940 external ADC to an advanced three-pin technique capable of 17-bit resolution. The P2's built-in capabilities can potentially exceed the external ADC's performance while providing greater flexibility.

## Available ADC Options

### 1. AD7940 External ADC (Current Baseline)
- **Resolution**: 14-bit fixed
- **Sample Rate**: 100 ksps maximum
- **Interface**: SPI (bit-banged)
- **Pins Required**: 3 (CS, SCLK, MISO)
- **Pros**:
  - Proven Arduino implementation
  - Consistent performance
  - Hardware guaranteed specs
- **Cons**:
  - Fixed resolution
  - Requires COG for SPI
  - External component cost

### 2. P2 Single-Pin ADC (Standard Smart Pin Mode)
- **Resolution**: 8-14 bit (configurable)
- **Sample Rates** (at 250 MHz):
  - 8-bit: 1.95 Msps
  - 10-bit: 488 ksps
  - 12-bit: 122 ksps
  - 14-bit: 30.5 ksps
- **Pin Required**: 1 (P6 - AOUT)
- **Pros**:
  - No external components
  - Hardware-based (no COG needed)
  - Flexible resolution/speed tradeoff
- **Cons**:
  - Lower speed at 14-bit than AD7940
  - May need calibration

### 3. P2 Three-Pin ADC (Advanced Instrumentation Technique)
- **Resolution**: Up to 17-bit effective
- **Sample Rates** (at 320 MHz):
  - Low resolution: ~78 ksps
  - 17-bit: ~780 sps
  - Maximum: ~78 sps
- **Pins Required**: 3 contiguous (e.g., P6-P8)
- **Pros**:
  - Exceeds all other options in resolution
  - Differential measurement reduces noise
  - Software-controlled resolution
  - No external ADC needed
- **Cons**:
  - Uses 3 pins
  - More complex implementation
  - Lower speed at high resolution

### 4. Hybrid Approach
- **Concept**: Use multiple techniques based on mode
- **Implementation**: Runtime switching between methods
- **Benefits**: Optimal performance for each use case

## Pin Assignment Options

### Current Pin Usage
```
P0-P7:   HDMI Display
P8-P15:  Magnetic Tile Sensor Interface
  P8:  CS (AD7940)
  P9:  CCLK (Counter Clock)
  P10: MISO (AD7940 Data)
  P11: CLRb (Counter Clear)
  P12: SCLK (AD7940 Clock)
  P14: AOUT (Analog from tile) <-- KEY PIN
P16-P23: OLED Display
P40-P57: PSRAM (P2 Edge)
```

### Proposed ADC Pin Configurations

#### Option A: Minimal Change (Single-Pin ADC)
- Use P14 (AOUT) only
- Keep AD7940 as backup on P8, P10, P12
- No hardware changes needed

#### Option B: Three-Pin ADC Primary
- Use P14-P16 for three-pin ADC
- Requires moving OLED to P24-P31
- Maximizes ADC resolution

#### Option C: Flexible Configuration
- P14: Single-pin ADC modes
- P14-P16: Three-pin mode (when OLED not needed)
- P8,P10,P12: AD7940 fallback

## Performance Analysis by Use Case

### 1. Research/Calibration Mode
- **Requirement**: Maximum precision, slow speed acceptable
- **Solution**: Three-pin ADC at 17-bit @ 780 sps
- **Frame Rate**: ~12 fps (sufficient for calibration)

### 2. Normal Operation Mode
- **Requirement**: Good resolution, moderate speed
- **Solution**: Single-pin 12-bit @ 122 ksps
- **Frame Rate**: ~1,900 fps

### 3. High-Speed Demo Mode
- **Requirement**: Visual smoothness, lower resolution acceptable
- **Solution**: Single-pin 8-bit @ 1.95 Msps
- **Frame Rate**: ~30,000 fps

### 4. Arduino Compatibility Mode
- **Requirement**: Match original implementation
- **Solution**: AD7940 14-bit @ 100 ksps
- **Frame Rate**: ~1,500 fps

## Implementation Phases

### Phase 1: Baseline Verification (Current Sprint)
1. Complete display test patterns ✓
2. Implement AD7940 interface
3. Verify sensor multiplexing
4. Establish performance baseline

### Phase 2: P2 ADC Integration
1. Implement single-pin ADC on P14
2. Add SINC3 filtering mode
3. Create ADC mode switching
4. Performance comparison with AD7940

### Phase 3: Advanced ADC Implementation
1. Adapt ThreePinADC.spin2 for magnetic tile
2. Hardware modification (add resistors if needed)
3. Implement rotation algorithm
4. Calibration procedures

### Phase 4: Optimization & Selection
1. Profile all ADC modes
2. Select optimal defaults
3. Implement auto-ranging
4. Document final configuration

## Software Architecture

### ADC Manager Object Structure
```
isp_adc_manager.spin2
  ├── AD7940 driver (SPI)
  ├── Single-pin ADC driver
  ├── Three-pin ADC driver
  └── Mode selection/switching
```

### Interface Design
```spin2
PUB set_adc_mode(mode)
  ' MODE_AD7940     = 0  ' External 14-bit
  ' MODE_SINGLE_8   = 1  ' P2 8-bit fast
  ' MODE_SINGLE_12  = 2  ' P2 12-bit balanced
  ' MODE_SINGLE_14  = 3  ' P2 14-bit precision
  ' MODE_THREE_PIN  = 4  ' P2 17-bit ultra

PUB read_sensor(sensor_num) : value
  ' Returns scaled 16-bit value regardless of ADC mode

PUB get_actual_resolution() : bits
  ' Returns current effective resolution

PUB get_sample_rate() : sps
  ' Returns current samples per second
```

## Decision Matrix

| Use Case | Best ADC Option | Resolution | Speed | Notes |
|----------|----------------|------------|-------|-------|
| Initial Testing | AD7940 | 14-bit | 100 ksps | Known baseline |
| Research | Three-Pin | 17-bit | 780 sps | Maximum precision |
| Production | Single-Pin | 12-bit | 122 ksps | Best balance |
| Demo/Show | Single-Pin | 8-bit | 1.95 Msps | Smooth visuals |
| Compatibility | AD7940 | 14-bit | 100 ksps | Arduino match |

## Risk Mitigation

### Hardware Risks
- **Three-pin connection**: Test with breadboard first
- **OLED pin conflict**: Have alternate pin assignment ready
- **Noise coupling**: Use shielded cable for AOUT

### Software Risks
- **Timing conflicts**: Dedicate COG for each ADC mode
- **Resolution changes**: Abstract through common interface
- **Calibration drift**: Implement auto-calibration

## Testing Protocol

### ADC Comparison Tests
1. **Static Input Test**: Fixed voltage, measure noise
2. **Dynamic Range Test**: Full scale sweep
3. **Linearity Test**: Multiple points across range
4. **Noise Floor Test**: Shorted input measurement
5. **Temperature Drift**: Monitor over time

### Performance Benchmarks
1. **Frame Rate**: Each mode at max speed
2. **CPU Usage**: COG utilization per mode
3. **Power Consumption**: Current draw comparison
4. **Latency**: Input to display time

## Recommendations

### Immediate Actions
1. **Keep AD7940** implementation as baseline
2. **Test P14 single-pin** ADC in parallel
3. **Prepare pin headers** for three-pin option

### Short-term Goals
1. **Implement ADC manager** with mode switching
2. **Create performance test suite**
3. **Document optimal settings** per use case

### Long-term Vision
1. **Three-pin ADC** as primary for production
2. **Remove AD7940** to reduce cost/complexity
3. **Patent potential** for three-pin magnetic sensing?

## Conclusion

The P2's ADC capabilities, especially the three-pin instrumentation technique, offer superior performance compared to the external AD7940. The ability to achieve 17-bit resolution with software-controlled speed tradeoffs provides unprecedented flexibility for the magnetic imaging tile application.

The recommended path forward is to implement all ADC options with runtime switching, then optimize based on real-world testing. The modular architecture allows easy comparison and future enhancement.