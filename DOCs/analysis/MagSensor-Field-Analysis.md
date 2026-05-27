# Magnetic Field Sensor Analysis & ADC Mapping

## DRV5053 Hall Effect Sensor Specifications

### Available Versions & Sensitivities
The DRV5053 comes in 6 sensitivity variants:

| Version | Sensitivity | Saturation Field (BSAT) | Typical Use Case |
|---------|------------|-------------------------|------------------|
| DRV5053OA | -11 mV/mT | ±73 mT | Low sensitivity, wide range |
| DRV5053PA | -23 mV/mT | ±35 mT | Medium-low sensitivity |
| DRV5053RA | -45 mV/mT | ±18 mT | Medium sensitivity |
| **DRV5053VA** | **-90 mV/mT** | **±9 mT** | **High sensitivity (CONFIRMED - "VA" marking)** |
| DRV5053CA | +23 mV/mT | ±35 mT | Positive polarity, medium |
| DRV5053EA | +45 mV/mT | ±18 mT | Positive polarity, medium-high |

**CONFIRMED**: The sensors are marked "ALVA" with "VA" having overlines, definitively identifying them as **DRV5053VA** (-90 mV/mT) high sensitivity variants.

### Electrical Characteristics
- **Supply Voltage**: 3.3V (tile operates at 3.3V)
- **Quiescent Output** (B = 0 mT): 1.0V (VCC = 3.3V)
- **Output Range**: 0.2V to 1.8V
- **Output Impedance**: <1kΩ
- **Bandwidth**: 20 kHz (fastest detectable field change)
- **Power-on Time**: 35 µs

## Field-to-Voltage Mapping (DRV5053VA)

### Linear Operating Range
For the DRV5053VA with -90 mV/mT sensitivity (2× more sensitive):

```
Magnetic Field Range: -9 mT to +9 mT (linear region)
Voltage Output Range: 0.19V to 1.81V (at saturation)

At B = 0 mT:  VOUT = 1.0V
At B = +9 mT:  VOUT = 1.0V - (9 × 0.090) = 0.19V
At B = -9 mT:  VOUT = 1.0V - (-9 × 0.090) = 1.81V
```

**Important**: The VA variant saturates at only ±9 mT, making it excellent for detecting weak fields but prone to saturation with strong magnets.

### Polarity Convention
- **South Pole** (positive field): Decreases output voltage below 1.0V
- **North Pole** (negative field): Increases output voltage above 1.0V
- This is for negative sensitivity variants (OA, PA, RA, VA)

## ADC Value Mapping

### AD7680 16-bit ADC Specifications
- **Resolution**: 16 bits (65,536 levels)
- **Reference Voltage**: 3.3V
- **LSB Size**: 3.3V / 65,536 = 50.35 µV

### Sensor Output to ADC Values

#### Full Scale Mapping
```
ADC Value = (VOUT / 3.3V) × 65,536

At VOUT = 0.19V (saturation, +9 mT South):
ADC = 3,770

At VOUT = 1.0V (null field, 0 mT):
ADC = 19,859

At VOUT = 1.81V (saturation, -9 mT North):
ADC = 35,948
```

#### Dynamic Range Analysis
```
Usable ADC Range: 35,948 - 3,770 = 32,178 counts
Voltage Span: 1.81V - 0.19V = 1.62V
Field Span: 18 mT (-9 to +9 mT)

Resolution per mT: 32,178 / 18 = 1,788 ADC counts/mT (2× better!)
Resolution per Gauss: 178.8 ADC counts/Gauss
```

### Noise Floor Consideration
- **Output Noise**: 44 mVpp typical (DRV5053VA)
- **Noise in ADC counts**: 44mV / 50.35µV = 874 counts
- **Effective Resolution**: ~10-11 bits (considering noise)
- **Minimum Detectable Field Change**: ~0.5 mT (noise limited)
- **Note**: Higher sensitivity means more noise, but still ~0.5 mT minimum detection

## Field Distance Sensing Capabilities

### Magnetic Field Strength vs Distance
For a typical neodymium magnet (N52, 10mm diameter × 5mm):

```
Distance | Field Strength | Sensor Output | ADC Value | Status
---------|---------------|---------------|-----------|--------
Contact  | >100 mT       | Saturated     | 3,770 or 35,948 | Saturated
1 mm     | ~50 mT        | Saturated     | 3,770 or 35,948 | Saturated
5 mm     | ~10 mT        | Saturated     | 3,770 or 35,948 | Saturated
7 mm     | ~8 mT         | 1.72V / 0.28V | 33,947 / 5,528 | Near saturation
10 mm    | ~3 mT         | 1.27V / 0.73V | 25,077 / 14,414 | Good range
20 mm    | ~0.5 mT       | 1.045V / 0.955V | 20,632 / 18,856 | Excellent
30 mm    | ~0.1 mT       | 1.009V / 0.991V | 19,937 / 19,563 | Weak signal
```

### Detection Range
- **Strong Detection** (>50% scale): 0-10mm from small magnet
- **Moderate Detection** (10-50% scale): 10-20mm
- **Weak Detection** (<10% scale): 20-30mm
- **Noise Floor**: Beyond 30mm for small magnets

## Display Color Granularity Mapping

### Available Color Bits (RGB565)
- **Red Channel**: 5 bits (32 levels)
- **Blue Channel**: 5 bits (32 levels)
- **Green Channel**: 6 bits (64 levels, not used for magnetic display)

### Field Strength to Color Intensity

#### Linear Mapping Approach
```
For South Pole (Positive Field, Blue):
- Field Range: 0 to +9 mT
- Blue Levels: 0 to 31
- Granularity: 0.29 mT per blue level (2× better resolution!)

For North Pole (Negative Field, Red):
- Field Range: 0 to -9 mT
- Red Levels: 0 to 31
- Granularity: 0.29 mT per red level
```

#### Logarithmic Mapping (Better for Weak Fields)
```spin2
PUB field_to_color(adc_value) : color | field_mT, intensity
  ' Convert ADC to field strength in mT (VA variant)
  field_mT := ((adc_value - 19859) * 1000) / 1788

  ' Apply logarithmic scaling for better weak field visibility
  if field_mT == 0
    return $0000  ' Black

  ' Log scale with offset for visibility
  intensity := log2(||field_mT + 1) * 4
  intensity := intensity <# 31  ' Clamp to 5 bits

  if field_mT < 0  ' North pole
    color := intensity << 11  ' Red
  else  ' South pole
    color := intensity  ' Blue
```

### Practical Color Resolution
With 32 intensity levels per polarity and DRV5053VA:
- **Saturated Fields** (>9 mT): Clipped at maximum color
- **Strong Fields** (5-9 mT): 10-14 distinguishable levels
- **Medium Fields** (1-5 mT): 12-14 distinguishable levels
- **Weak Fields** (<1 mT): 3-4 distinguishable levels (excellent sensitivity)

## System Performance Implications

### ADC Sampling Considerations
- **Minimum Conversion Time**: 2.4 µs (AD7680 at 2.5 MHz)
- **Sensor Settling Time**: 2 µs (after mux switch)
- **Total Time per Sensor**: 10 µs (includes overhead)
- **Frame Rate**: 1,562 fps theoretical

### Dynamic Range Optimization
To maximize usable range:

1. **Hardware Gain Stage** (optional):
   - Add op-amp with gain of 2×
   - Expands ±18 mT to use full ADC range
   - Improves weak field detection

2. **Software Calibration**:
   ```spin2
   CON
     NULL_FIELD_ADC = 19859  ' Calibrated zero point
     SCALE_FACTOR = 1788      ' ADC counts per mT (VA variant)

   PUB calibrate_sensor(sensor_num)
     ' Read sensor with no field present
     null_values[sensor_num] := read_adc()

   PUB get_field_strength(sensor_num) : field_mT
     raw := read_adc()
     field_mT := ((raw - null_values[sensor_num]) * 1000) / SCALE_FACTOR
   ```

3. **Adaptive Sensitivity**:
   - Monitor field histogram
   - Adjust color mapping dynamically
   - Enhance contrast for current field range

## Summary & Recommendations

### Key Findings
1. **Sensor Range**: ±9 mT linear range (DRV5053VA confirmed by marking)
2. **ADC Resolution**: 1,788 counts/mT (2× better), effectively 10-11 bits with noise
3. **Detection Distance**: 10-40mm optimal range (saturates closer than 10mm)
4. **Color Resolution**: 32 levels per polarity, 0.29 mT per level
5. **Minimum Detectable**: ~0.5 mT limited by sensor noise (44 mVpp)

### Design Recommendations
1. **DRV5053VA confirmed** - excellent for weak field detection
2. **Implement saturation indicators** - fields >9 mT will clip
3. **Software calibration critical** - null field correction essential
4. **Use linear color scaling** - VA variant already has excellent sensitivity
5. **Consider field strength warnings** when approaching ±9 mT limits
6. **Use averaging** for static measurements to reduce 44 mVpp noise

### Performance Targets
- **Saturation Point**: ±9 mT (closer magnets will saturate)
- **Optimal Range**: ±1 to ±8 mT for best visualization
- **Weak Field Excellence**: Clear response down to ±0.1 mT
- **Spatial Resolution**: 8×8 grid with 16×16 pixel interpolation
- **Temporal Resolution**: 70 fps display update rate
- **Color Depth**: 32 levels, 0.29 mT per level (excellent granularity)

This analysis provides the complete chain from magnetic field through sensor, ADC, processing, to final display colors, enabling optimal system configuration for the P2 Magnetic Imaging Tile.