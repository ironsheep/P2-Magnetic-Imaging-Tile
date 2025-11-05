# Architecture Documentation

This folder contains the complete architecture documentation for the P2 Magnetic Imaging Tile system.

## Document Overview

### System-Level

- **[System-Architecture.md](System-Architecture.md)** - Complete system overview
  - COG allocation and data flow
  - FIFO structure and timing
  - Performance targets and migration path
  - **START HERE** for understanding the overall system

### Component-Level

- **[Sensor-Architecture.md](Sensor-Architecture.md)** - Sensor acquisition subsystem
  - Dual COG architecture (PASM + Manager)
  - Hardware scanning and timing
  - Baseline calibration
  - Performance: 918 fps current, 2000 fps target

- **[OLED-Driver-Architecture.md](OLED-Driver-Architecture.md)** - OLED display subsystem
  - Single consolidated COG
  - Smart Pin SPI streaming (Level 1)
  - Performance: 62.5 fps sustainable
  - Future: Streamer/DMA optimization (Level 2) → 74 fps

- **[HDMI-PSRAM-Architecture.md](HDMI-PSRAM-Architecture.md)** - HDMI display subsystem
  - Three COG chain (PSRAM Driver, Streamer, Manager)
  - FillRect rendering to PSRAM
  - Performance: 60 fps (hardware-locked)

- **[Image-Processing-Architecture.md](Image-Processing-Architecture.md)** - Image processing subsystem (future)
  - Multi-frame analysis with sliding window
  - 5 visualization modes (8×8 to 32×32)
  - Temporal super-resolution
  - Results FIFO architecture

## Reading Order

### For Understanding the System:
1. System-Architecture.md (overview)
2. Sensor-Architecture.md (data source)
3. OLED-Driver-Architecture.md (display output 1)
4. HDMI-PSRAM-Architecture.md (display output 2)
5. Image-Processing-Architecture.md (future processing)

### For Implementation:
1. System-Architecture.md → Migration Path section
2. Sensor-Architecture.md → Current implementation details
3. Component-specific docs as needed for each phase

## Key Concepts

### COG Allocation (Target)

| COG | Role | Document |
|-----|------|----------|
| COG 0 | Main → Decimator | System-Architecture.md |
| COG 1 | PSRAM Driver | HDMI-PSRAM-Architecture.md |
| COG 2 | HDMI Streamer | HDMI-PSRAM-Architecture.md |
| COG 3 | Available (future: Processing) | Image-Processing-Architecture.md |
| COG 4 | HDMI Manager | HDMI-PSRAM-Architecture.md |
| COG 5 | OLED Consolidated | OLED-Driver-Architecture.md |
| COG 6-7 | Available (sensor/communications) | System-Architecture.md |

### FIFO Structure

| FIFO | Producer | Consumer | Document |
|------|----------|----------|----------|
| FIFO_SENSOR (0) | Sensor COGs | Main Decimator | Sensor-Architecture.md |
| FIFO_HDMI (2) | Main Decimator | HDMI Manager | HDMI-PSRAM-Architecture.md |
| FIFO_OLED (3) | Main Decimator | OLED Manager | OLED-Driver-Architecture.md |
| FIFO_RESULTS (1) | Processing COG (future) | Main Router | Image-Processing-Architecture.md |

### Performance Targets

| Component | Current | Target | Limiting Factor |
|-----------|---------|--------|-----------------|
| Sensor | 918 fps | 2000 fps | Multiplexer settling |
| HDMI | 60 fps | 60 fps | Display refresh rate (hardware) |
| OLED | 62.5 fps | 60 fps | SPI streaming time |
| Processing | - | 60 fps | Design target (future) |

## Implementation Phases

### Phase 1: Basic System ✓ (Current)
- Main as simple decimator
- Get sensor → displays working end-to-end
- Validate FIFO coordination

### Phase 2: OLED Consolidation (Next)
- Merge OLED manager + streaming into single COG
- Free COG 6
- Document: OLED-Driver-Architecture.md

### Phase 3: HDMI Optimization (After Phase 2)
- Remove unused Graphics COG
- Free COG 3
- Document: HDMI-PSRAM-Architecture.md

### Phase 4: Processing COG (Future)
- Add multi-frame analysis
- Implement 5 visualization modes
- Add Results FIFO
- Document: Image-Processing-Architecture.md

## Document Status

All architecture documents are **Version 1.0** as of 2025-11-04.

These documents represent the **design specification** for the system and should be kept synchronized with implementation changes.

## Related Documentation

- Hardware: `../MagneticTile-Pinout.taskpaper`
- Reference Implementation: `../REF-Implementation/`
- Hardware Schematics: `../hardware-boards/`

---

**Last Updated:** 2025-11-04
