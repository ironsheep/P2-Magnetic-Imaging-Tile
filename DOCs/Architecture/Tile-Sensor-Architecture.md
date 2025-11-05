# Tile Sensor Architecture

## Overview

The tile sensor subsystem interfaces with the SparkFun Magnetic Imaging Tile V3, reading 64 Hall effect sensors arranged in an 8x8 grid. This document explains the architecture, performance requirements, and implementation progression from bit-banged SPI to Smart Pin-based solutions.

## System Requirements

### Frame Rate
- **Target**: 375 frames per second (2.67ms per frame)
- **Hardware capability**: Up to 2000 fps
- **Real-time constraint**: Minimal jitter in frame timing

### Data Path
- **64 sensors** × 16 bits = 128 bytes per frame
- **SPI communication** with AD7940 14-bit ADC
- **Hardware multiplexer** for sensor selection

### Precision Requirements
- **ADC settling time**: ~10 microseconds per sensor
- **SPI clock timing**: Precise bit-banged or Smart Pin generated
- **Counter control**: CCLK and CLRb pulse timing for sensor selection

## Implementation Stages

### Stage 1: Bit-Banged SPI (Current Implementation)

**When Required:**
- Direct control of SPI timing
- Non-standard SPI protocols
- Fast clock rates or sub-microsecond timing precision
- Learning/debugging phase

**Language Choice - Spin2 vs PASM:**

**Spin2 bit-banging viable when:**
- Protocol timing allows ~100ns granularity
- Clock rates < ~5 MHz adequate
- Pin operations (PINH/PINL) sufficient
- GETCT timing with waitms()/waitus() meets needs

**PASM bit-banging required when:**
- Sub-microsecond precision needed (WAITX)
- Clock rates > 5-10 MHz required
- Zero jitter critical
- Spin2 timing demonstrably inadequate

**Current Implementation Uses PASM Because:**
- AD7940 timing requirements unverified in Spin2
- Targeting high frame rates (375+ fps)
- Conservative approach: PASM ensures adequate headroom
- **NOTE**: May be over-engineered; Spin2 might suffice

**Performance Characteristics:**
- Full COG dedicated to sensor reading
- Cycle-accurate timing control
- Maximum flexibility for protocol tuning
- Higher code complexity

**Current PASM Implementation:**
- Lines 467-750 in `isp_tile_sensor.spin2`
- `acquisition_loop`: Main sensor reading loop
- `capture_frame`: Subtile iteration and sensor reading
- `read_ad7680`: Bit-banged SPI communication
- `frame_rate_control`: 375 fps timing using GETCT/WAITCT

### Stage 2: Smart Pin SPI (Future Implementation)

**When Appropriate:**
- Standard SPI protocol requirements met
- Hardware offload desired
- Reduced code complexity needed
- Proven bit-bang implementation working

**Why Spin2 Becomes Viable:**
```
Smart Pins handle:
- Clock generation in hardware
- Bit shifting automatically
- Timing maintained by silicon
- Spin2 just configures and reads results
```

**Performance Characteristics:**
- Smart Pin hardware handles timing
- Spin2 code for configuration and data movement
- COG freed for other tasks (or eliminated)
- Simpler, more maintainable code

**Migration Strategy:**
1. Verify bit-bang version meets all requirements
2. Configure Smart Pins for SPI mode (WRPIN, WXPIN)
3. Replace PASM SPI with Smart Pin configuration
4. Test equivalent timing and data quality
5. Consider moving to Spin2 if no PASM needed elsewhere

### Stage 3: Fully Spin2 (Potential End State)

**When Achievable:**
- Smart Pins handle all timing-critical operations
- No other PASM requirements remain
- Maintainability prioritized over marginal performance

**Architecture:**
```spin2
PRI fifo_manager_loop() | framePtr
  repeat
    ' Get frame buffer
    framePtr := fifo.getNextFrame()

    ' Configure Smart Pins for SPI
    configure_spi_smart_pins()

    ' Read 64 sensors using Smart Pin results
    read_sensor_frame(framePtr)

    ' Commit to FIFO
    fifo.commitFrame(fifo.FIFO_SENSOR, framePtr)

    ' Frame rate timing (Spin2 GETCT adequate for 375fps)
    wait_for_next_frame()
```

**Benefits:**
- Single COG (FIFO manager handles everything)
- Easier debugging and modification
- Readable, maintainable code
- Smart Pins ensure timing precision

## Current Architecture Details

### Component Separation

**FIFO Manager COG (Spin2):**
- Gets empty frame buffers from pool
- Coordinates with acquisition system
- Commits filled frames to SENSOR FIFO
- Simple control flow, no timing constraints

**Acquisition COG (PASM):**
- Bit-banged SPI communication
- Precise sensor timing control
- Hardware pin manipulation
- 375 fps frame rate control

### Test Mode vs. Production Mode

**Production Mode (Real Sensor):**
- PASM acquisition required
- Mailbox handshake: Spin2 ↔ PASM
- Hardware timing critical

**Test Mode (Synthetic Patterns):**
- NO hardware requirements
- NO timing constraints (30 seconds per frame!)
- Should be pure Spin2
- Mailbox overhead unnecessary

### Why Test Patterns Were Incorrectly in PASM

**Original Implementation:**
- Test patterns placed in PASM `generate_test_pattern` subroutine
- Used same acquisition loop as real sensor
- Shared mailbox infrastructure

**Problems:**
- Unnecessary complexity for simple memory operations
- COG vs HUB addressing confusion
- Harder to debug and modify
- Violated "simplicity first" principle

**Correct Approach:**
- Test patterns in Spin2 (fifo_manager_loop)
- Direct frame buffer filling
- No mailbox needed
- PASM only invoked for real sensor mode

## Design Principles

### Abstraction Level Selection

**Use Spin2 when:**
- No sub-microsecond timing required
- No hardware bit-banging needed
- Code clarity and maintainability important
- Standard operations (memory, logic, control flow)

**Use PASM when:**
- Precise timing required (WAITX)
- Direct hardware control needed (pins, Smart Pins)
- Proven performance bottleneck
- Spin2 demonstrably cannot meet requirements

**Use Smart Pins when:**
- Standard protocols (SPI, I2C, UART)
- Hardware offload possible
- Reduces PASM complexity
- Proven reliable for application

### Performance Budget

**At 375 fps (2.67ms per frame):**
- Sensor readout: ~1.0ms (64 sensors × 15μs each)
- Frame processing: ~0.5ms (remapping, baseline)
- Slack time: ~1.17ms
- **Conclusion**: Spin2 + Smart Pins likely sufficient

**At 2000 fps (0.5ms per frame):**
- Sensor readout: ~1.0ms (same)
- **Oversubscribed**: Requires optimization
- **Conclusion**: Bit-bang PASM or hardware parallelism needed

## Migration Path

### Phase 1: Stabilize Bit-Bang (Current)
- ✅ Working PASM sensor acquisition
- ✅ Proven 375 fps capability
- ⚠️ Move test patterns to Spin2

### Phase 2: Validate Smart Pin SPI
- Configure Smart Pins for AD7940 protocol
- Test timing and data quality
- Compare with bit-bang baseline
- Document any protocol limitations

### Phase 3: Hybrid Implementation
- Smart Pins for SPI communication
- Minimal PASM for critical sections only
- Most logic in Spin2

### Phase 4: Pure Spin2 (If Feasible)
- All timing via Smart Pins
- Configuration and control in Spin2
- Simplest, most maintainable solution

## Current Status

**Bit-bang implementation working** ✓

**Next immediate steps:**
1. Move test patterns from PASM to Spin2 ✓
2. Validate test pattern routing through pipeline
3. Test real sensor acquisition remains stable
4. Begin Smart Pin exploration (separate branch)

## References

- Arduino reference implementation: `DOCs/REF-Implementation/Theory_of_Operations.md`
- Pin assignments: `DOCs/MagneticTile-Pinout.taskpaper`
- P2 Smart Pin documentation: Use P2KB for SPI modes
