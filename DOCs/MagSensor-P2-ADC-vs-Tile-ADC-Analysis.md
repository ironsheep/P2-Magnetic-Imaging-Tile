# P2 ADC vs Magnetic Tile ADC Analysis

## UPDATE: Advanced Three-Pin ADC Technique Discovery

### Reference Implementation Analysis (REF-ADC/ThreePinADC.spin2)
Found an advanced ADC implementation that achieves **17-bit resolution** using a three-pin constant-impedance instrumentation ADC technique. This significantly changes our performance analysis.

## Current Hardware Configuration

### Magnetic Tile AD7940 ADC
- **Resolution**: 14-bit fixed
- **Sampling Rate**: Up to 100 ksps
- **Interface**: SPI (bit-banged currently)
- **Pins Used**: CS, SCLK, MISO (3 pins)
- **Current Implementation**: External ADC via SPI

### Available P2 ADC via AOUT Pin
- **Pin**: P6 (AOUT from magnetic tile)
- **Signal**: Analog output from magnetic tile's Hall sensor multiplexer
- **Direct Access**: Analog voltage available for P2 smart pin ADC

## P2 Smart Pin ADC Capabilities

### Resolution Options
The P2's ADC resolution is configurable based on sampling period:
- **8-bit**: 128 clock periods (fastest)
- **10-bit**: ~512 clock periods
- **12-bit**: ~2048 clock periods
- **14-bit**: 8192 clock periods (matches AD7940)

### Sampling Modes
1. **SINC2 Sampling** - Complete conversions, good for DC measurements
2. **SINC2 Filtering** - Software differencing required
3. **SINC3 Filtering** - Higher ENOB for dynamic signals (best for magnetic fields)
4. **Bitstream Capture** - Raw ADC data

### Performance Calculations

At 250 MHz system clock:
- **8-bit mode**: 1.95 Msps (128 clocks/sample)
- **10-bit mode**: ~488 ksps
- **12-bit mode**: ~122 ksps
- **14-bit mode**: ~30.5 ksps

## Performance Comparison

### AD7940 (Current)
- **Advantages**:
  - Guaranteed 14-bit performance
  - 100 ksps with full resolution
  - Proven implementation from Arduino reference
  - Independent of P2 clock variations

- **Disadvantages**:
  - Requires 3 pins for SPI
  - Additional COG overhead for SPI bit-banging
  - Fixed resolution

### P2 Smart Pin ADC
- **Advantages**:
  - No additional pins needed (uses existing AOUT)
  - Flexible resolution/speed tradeoffs
  - Hardware-based (no COG needed for conversion)
  - Could achieve higher frame rates at lower resolutions
  - SINC3 filtering ideal for magnetic field measurements

- **Disadvantages**:
  - 14-bit mode limited to ~30 ksps
  - Resolution/speed tradeoff required
  - Calibration may be needed

## Recommended Hybrid Approach

### Multi-Mode Operation
Implement both ADC options with runtime selection:

1. **High-Resolution Mode** (AD7940)
   - 14-bit @ 100 ksps
   - For precise measurements
   - Maximum ~1500 fps theoretical

2. **High-Speed Mode** (P2 ADC)
   - 12-bit @ 122 ksps → ~1900 fps
   - 10-bit @ 488 ksps → ~7600 fps
   - 8-bit @ 1.95 Msps → ~30,000 fps (demo/visualization)

3. **Balanced Mode** (P2 ADC)
   - 12-bit SINC3 filtering
   - Better noise rejection for magnetic fields
   - ~1900 fps with good quality

## Implementation Strategy

### Phase 1: Baseline with AD7940
- Complete current implementation
- Establish performance baseline
- Verify sensor data quality

### Phase 2: P2 ADC Integration
- Add P2 ADC support on P6 (AOUT)
- Implement SINC3 filtering mode
- Create runtime ADC selection

### Phase 3: Advanced Features
- Your mentioned "advanced ADC form" for higher resolution
- Possible oversampling techniques
- Adaptive resolution based on activity

## Key Considerations

1. **Frame Rate Requirements**
   - Display update: ~60 fps (HDMI), ~30 fps (OLED)
   - Processing needs: Higher rates enable better filtering
   - User experience: Smooth real-time response

2. **Resolution Needs**
   - Magnetic field dynamics: 10-12 bits often sufficient
   - Scientific measurement: 14-bit preferred
   - Visualization: 8-10 bits acceptable

3. **Power/Performance**
   - P2 ADC uses less power (no external chip)
   - Fewer pins = more resources for other features
   - Hardware ADC frees COG for processing

## Advanced Three-Pin ADC Technique

### Key Features (from ThreePinADC.spin2)
- **17-bit effective resolution** (exceeds AD7940's 14-bit!)
- Uses 3 contiguous pins tied together
- Constant-impedance instrumentation ADC
- Rotating pin configuration for noise cancellation
- Advanced filtering with moving-boxcar averaging

### How It Works
1. **Three-Pin Rotation**: Each measurement cycle rotates through configurations:
   - Cycle 1: A=Gio, B=Vio, C=Sig
   - Cycle 2: A=Vio, B=Sig, C=Gio
   - Cycle 3: A=Sig, B=Gio, C=Vio

2. **SINC2 Filtering**: 128 clocks/sample with stabilization
3. **Differential Measurement**: Computes (Sig - Gio) / (Vio - Gio)
4. **Programmable Resolution**: Control via cycle count (1 to ~10,000)
5. **Optional Filtering**: Power-of-2 boxcar averaging (up to 2^13 samples)

### Performance at 320 MHz
- **Sample Rate**: Varies with cycle count
  - 1 cycle: ~78 ksps (lower resolution)
  - 100 cycles: ~780 sps (17-bit resolution)
  - 1000 cycles: ~78 sps (maximum resolution)

### Application to Magnetic Tile

**Option 1: Direct AOUT Measurement**
- Use single P6 pin with standard ADC modes
- 8-14 bit resolution as analyzed above

**Option 2: Three-Pin Enhancement**
- Dedicate P6, P7, P8 (or any 3 contiguous pins)
- Connect all three to AOUT through matched resistors
- Achieve up to 17-bit resolution
- Better noise immunity through differential measurement

### Implementation Considerations
1. **Pin Requirements**: 3 pins vs 1 pin tradeoff
2. **Calibration**: Requires ground (Gio) and reference (Vio) voltages
3. **Processing**: More complex but runs entirely in PASM
4. **Flexibility**: Resolution vs speed adjustable in real-time

## Revised Recommendation

### Three-Tier ADC Strategy

1. **Ultra-High Resolution Mode** (Three-Pin ADC)
   - 17-bit resolution @ ~780 sps
   - For precision calibration and research
   - 3 pins dedicated to AOUT

2. **Balanced Mode** (P2 Single-Pin ADC)
   - 12-bit SINC3 @ 122 ksps
   - General purpose operation
   - Single pin (P6) only

3. **High-Speed Mode** (P2 Single-Pin ADC)
   - 8-10 bit @ 488+ ksps
   - Real-time visualization
   - Single pin (P6) only

4. **Legacy Mode** (AD7940)
   - 14-bit @ 100 ksps
   - Arduino-compatible reference
   - When SPI ADC specifically needed

### Implementation Priority

**Phase 1**: Implement Three-Pin ADC
- Adapt ThreePinADC.spin2 for magnetic tile
- Use P6-P8 connected to AOUT
- Establish 17-bit baseline performance

**Phase 2**: Optimize for Speed
- Add single-pin fast modes
- Runtime switching between modes
- Performance profiling

**Phase 3**: Production Configuration
- Select optimal mode based on testing
- Possibly eliminate AD7940 entirely
- Document resolution/speed tradeoffs

## Conclusion

The Three-Pin ADC technique fundamentally changes the equation. With 17-bit resolution available using just the P2's smart pins, the external AD7940 becomes optional rather than essential. This technique offers:

- **Superior resolution** (17-bit vs 14-bit)
- **No external components** (besides resistors)
- **Complete software control** of resolution/speed tradeoff
- **Proven implementation** ready to adapt

This is likely the "advanced ADC form" you mentioned - it's a game-changer for high-resolution measurements while maintaining the flexibility for high-speed operation when needed.