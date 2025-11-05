# OLED Driver Architecture
**Magnetic Imaging Tile - Display Subsystem**

## Document Version
- **Version:** 1.0
- **Date:** 2025-11-04
- **Status:** Design Specification

## Overview

The OLED driver subsystem is responsible for consuming magnetic sensor frames from the OLED FIFO and displaying them on the 128×128 SSD1351 OLED display. This document describes the consolidated single-COG architecture that handles frame acquisition, conversion, and hardware streaming.

## Design Goals

1. **Maximum Display Frame Rate** - Achieve highest possible refresh rate for magnetic field visualization
2. **Single COG Efficiency** - Consolidate all OLED operations into one COG to free hardware resources
3. **Non-Blocking Operation** - Process frames without impacting sensor acquisition pipeline
4. **Future Performance Path** - Architecture supports progressive optimization from Smart Pins → Streamer/DMA

---

## System Context

### Input Source
- **Source:** OLED FIFO (managed by `isp_frame_fifo_manager`)
- **Data Format:** 64 WORDs (128 bytes) - 8×8 sensor array, 16-bit values per sensor
- **Value Range:** 0-4095 (12-bit ADC readings from magnetic tile sensor)

### Output Destination
- **Hardware:** SSD1351 128×128 RGB OLED Display
- **Interface:** SPI (MOSI, SCLK, CS, DC, RST on pins P16-P23)
- **Protocol:** RGB565 format (16-bit per pixel = 2 bytes)
- **Frame Size:** 128 × 128 × 2 = 32,768 bytes per full frame

### System Integration
```
Sensor (2000 fps) → Decimator (Main COG) → OLED FIFO → OLED COG → Display (67 fps max)
                         ↓ 1:30
                    (67 fps to OLED)
```

---

## COG Allocation

### Current Architecture: Single Dedicated COG

**COG Responsibilities:**
1. Frame acquisition from OLED FIFO (blocking dequeue)
2. Sensor data conversion (64 WORDs → RGB565 color mapping)
3. Display buffer construction (32KB frame buffer)
4. Hardware streaming to OLED via SPI
5. Frame resource management (release back to pool)

**Why Single COG:**
- OLED display is persistent (non-refreshing) - updates only on new data
- Processing time (~16ms) well-matched to input rate (~15ms between frames)
- Smart Pins handle SPI timing in hardware - minimal COG overhead during transmission
- Consolidation frees COGs for sensor and other display operations

---

## Functional Responsibilities

### 1. Frame Acquisition
**Method:** Blocking dequeue from OLED FIFO
```
framePtr := fifo.dequeue(FIFO_OLED)
```
- Blocks when FIFO empty (COG sleeps efficiently)
- Returns immediately when frame available
- Zero-copy architecture - operates on frame pointer

### 2. Data Conversion
**Process:** Magnetic field values → Visual representation

**Input:** 64 × 16-bit sensor readings (0-4095 range)

**Output:** 128×128 RGB565 bitmap (32,768 bytes)

**Color Mapping Algorithm:**
- Blue-dominant: Field < 1024 (lower quarter)
- Cyan → Green: 1024 ≤ Field < 2048
- Green → Yellow: 2048 ≤ Field < 3072
- Red-dominant: Field ≥ 3072 (upper quarter)

**RGB565 Format:**
```
Bits: RRRR_RGGG_GGGB_BBBB
      15-11: Red (5 bits)
      10-5:  Green (6 bits)
      4-0:   Blue (5 bits)
```

**Spatial Mapping:**
- Each sensor maps to 16×16 pixel cell
- 8×8 sensor grid → 128×128 display
- Row-major order maintained

### 3. Display Buffer Construction
**Strategy:** Build complete 32KB frame buffer before streaming

**Process:**
```
For each of 64 sensors (row 0-7, col 0-7):
  1. Read sensor value from frame
  2. Convert to RGB565 color
  3. Fill corresponding 16×16 cell in display buffer
  4. Store as little-endian bytes (low byte, high byte)
```

**Memory Layout:**
```
BYTE frame_buffer[32768]  // 128 × 128 × 2 bytes
```

**Performance:** ~2ms for conversion + buffer fill (simple math + memory writes)

### 4. Hardware Streaming
**Method:** PASM2 inline streaming using Smart Pins

**Smart Pin Configuration:**
- **MOSI (P16):** P_SYNC_TX mode (synchronous serial transmit)
- **SCLK (P18):** P_PULSE mode (automatic clock generation)
- **SPI Mode:** Mode 0 (CPOL=0, CPHA=0)
- **Clock Rate:** 20 MHz (SSD1351 maximum specification)

**Streaming Loop (PASM2):**
```pasm2
.byte_loop
  rdbyte    data_byte, frame_ptr      ; Read byte from buffer
  mov       temp, data_byte
  shl       temp, #2                   ; Lookup bit-reversed value
  add       temp, lut_base
  rdlong    rev_val, temp
  wypin     rev_val, #PIN_MOSI         ; Load into Smart Pin shifter
  wypin     #8, #PIN_SCLK              ; Trigger 8 clock pulses
.wait_sclk
  testp     #PIN_SCLK wc                ; Wait for transmission complete
  if_nc jmp #.wait_sclk
  add       frame_ptr, #1
  djnz      byte_count, #.byte_loop
```

**Performance:** ~14ms for 32,768 bytes
- SPI transmission: 32,768 bytes × 8 bits ÷ 20 MHz = 13.1ms (theoretical)
- Overhead: ~0.9ms (loop management, bit-reversal lookups)

### 5. Frame Management
**Completion:**
```
fifo.releaseFrame(framePtr)
```
- Returns frame buffer to free pool
- Enables frame reuse by sensor/processor
- Lock-protected operation

---

## Performance Analysis

### Current Performance: Smart Pin Implementation

**Frame Processing Breakdown:**
| Operation | Time | Notes |
|-----------|------|-------|
| FIFO dequeue | <0.1ms | Blocking, immediate when available |
| Sensor → RGB565 conversion | ~1ms | 64 color calculations |
| Buffer construction | ~1ms | 16,384 pixel writes (2 bytes each) |
| SPI streaming (PASM) | ~14ms | Hardware-limited (20 MHz SPI) |
| Frame release | <0.1ms | Lock + pointer update |
| **Total per frame** | **~16ms** | **Maximum ~63 fps** |

**COG Utilization During Streaming:**
- Smart Pins handle bit-level timing autonomously
- COG executes: read byte → bit-reverse lookup → wypin → poll completion
- Actual COG "busy" time: ~20% (rest is polling hardware)
- **Headroom available** for optimization

### Input Rate vs Processing Capacity

**Sensor Production:**
- Base rate: 2000 fps (0.5ms per frame)
- Decimation to OLED: 1:30
- **Delivery rate: 67 fps** (15ms between frames)

**OLED Consumption:**
- Processing time: ~16ms per frame
- **Consumption rate: ~63 fps**

**Steady State:**
- Input: 67 fps
- Output: 63 fps
- **Gap: +4 fps accumulation** (slightly over capacity)

**FIFO Behavior:**
- Depth: 16 frames
- Fill rate: 4 frames per second net accumulation
- **FIFO full after: ~4 seconds**
- Post-fill: 4 fps dropped (96% efficiency)

### Recommended Decimation Rate

**Target:** Match OLED processing capacity

**Calculation:**
- OLED capacity: 63 fps
- Sensor rate: 2000 fps
- **Optimal decimation: 1:32** (2000 ÷ 32 = 62.5 fps)

**Result:**
- Input: 62.5 fps
- Output: 63 fps
- **Sustainable indefinitely** with no FIFO accumulation
- Minor underutilization (~0.5 fps margin) provides safety buffer

---

## Performance Optimization Roadmap

### Level 1: Smart Pin Implementation (CURRENT)

**Status:** Implemented

**Mechanism:**
- P2 Smart Pins handle SPI timing in hardware
- PASM2 loop feeds bytes to Smart Pins
- CPU polls for transmission completion

**Performance:**
- **~63 fps maximum** (16ms per frame)
- Bottleneck: CPU loop overhead + polling
- COG ~20% utilized during streaming

**Advantages:**
- Reliable, well-understood
- Works with any SPI device
- Debugging support via debug statements

**Limitations:**
- CPU must service every byte transmission
- Polling introduces latency
- Cannot achieve theoretical SPI bandwidth

---

### Level 2: Streamer/DMA Implementation (FUTURE)

**Status:** Design specification

**Mechanism:**
- P2 Streamer engine (hardware DMA) transfers memory → Smart Pins
- Configure once, transfer entire 32KB frame autonomously
- Zero CPU intervention during transmission

**P2 Streamer Configuration:**
```pasm2
' Configure streamer for Smart Pin output
wrlong    ##$B000_0000 | PIN_MOSI, #$7F8    ; Streamer command
setq      #(32768/4)-1                       ; Transfer 8192 longs
wrlong    frame_buffer_addr, #$7FC           ; Start address
```

**Expected Performance:**
- **Theoretical:** 32,768 bytes ÷ 20 MHz = **13.1ms per frame** (~76 fps)
- **Practical:** ~13.5ms (accounting for setup) = **~74 fps**
- **Improvement:** +17% frame rate vs Smart Pin polling

**COG Utilization:**
- **Setup phase:** Configure streamer (~10 instructions)
- **Transfer phase:** Zero CPU - streamer operates autonomously
- **COG freed** for other work during 13ms transfer
- Could handle frame conversion for **next frame** while streaming current

**Implementation Requirements:**
1. Streamer mode configuration for SPI output
2. Frame buffer alignment (long-aligned)
3. Bit-reversal handled by streamer or pre-processing
4. Completion detection (streamer done interrupt or polling)

**Potential Advanced Pipeline:**
```
Frame N:   Dequeue → Convert → Stream (streamer active)
Frame N+1:         Dequeue → Convert (during N streaming)
```
- Overlap conversion of next frame with streaming of current
- Could approach **~14ms per frame** (conversion + streaming in parallel)
- **Maximum: ~71 fps**

**Challenges:**
1. Streamer bit-order handling (may require pre-reversal pass)
2. Smart Pin + Streamer interaction testing
3. Error handling (no byte-level control during transfer)
4. Requires PASM2 expertise for streamer setup

---

### Level 3: Future Enhancements (SPECULATIVE)

**Differential Updates:**
- Only update changed cells (vs full frame)
- Track previous frame, compare sensor values
- Potential 8× reduction in transfer time for static scenes
- Tradeoff: Comparison overhead vs SPI savings

**Compression:**
- Run-length encoding for uniform regions
- Requires smart buffering + decompression
- Best for low-complexity magnetic fields

**Double Buffering:**
- Maintain two 32KB buffers
- Build next frame while streaming current
- Requires 64KB RAM total (acceptable on P2 with 512KB)

---

## Implementation Notes

### Hardware Dependencies

**Fixed Pin Assignments:**
- P16: MOSI (SPI Data)
- P18: SCLK (SPI Clock)
- P20: CS (Chip Select)
- P22: DC (Data/Command)
- P23: RST (Reset)

**SSD1351 Display Requirements:**
- RGB565 format mandatory
- Column/row addressing before write
- Persistent GRAM (no refresh needed)
- 20 MHz SPI maximum (datasheet specification)

### Memory Requirements

**Per-Frame Buffers:**
- Sensor input: 128 bytes (64 WORDs) - from FIFO pool
- Display buffer: 32,768 bytes (RGB565 frame) - VAR allocation
- **Total: ~33 KB per OLED COG**

**Optimization:** Could eliminate display buffer if streaming directly from converted values, but loses opportunity for Level 2 DMA streaming.

### Error Handling

**FIFO Empty:**
- `fifo.dequeue()` blocks indefinitely
- Acceptable: COG sleeps efficiently, wakes when data arrives

**FIFO Full (upstream):**
- Decimator detects full FIFO on `commitFrame()`
- Frame dropped, not OLED's concern

**SPI Transmission Errors:**
- None expected with Smart Pins (hardware-managed)
- Visual artifacts would indicate hardware issues

---

## Testing & Validation

### Performance Metrics

**Frame Rate Measurement:**
```
frame_count++
if frame_count // 60 == 0:
  report_fps = 60_000 / elapsed_ms
```

**FIFO Depth Monitoring:**
```
depth = fifo.getQueueDepth(FIFO_OLED)
```
- Should remain 0-2 frames at steady state
- Climbing depth indicates over-production

### Visual Validation

**Test Patterns:**
1. Solid colors (verify full screen writes)
2. Checkerboard (verify cell mapping)
3. Gradient (verify color mapping accuracy)
4. Known magnetic field (verify sensor → display pipeline)

**Debug Output:**
```
DEBUG: OLED frame_count, depth, corner_values[4]
```

---

## Migration Path

### Phase 1: Consolidation (IMMEDIATE)
- Merge existing Cog5 + Cog6 into single COG
- Keep current Smart Pin PASM streaming implementation
- Validate 63 fps performance
- Adjust decimation to 1:32

### Phase 2: Optimization (FUTURE)
- Implement Streamer/DMA transfer
- Validate 74 fps performance
- Benchmark COG utilization improvement

### Phase 3: Advanced (LONG-TERM)
- Differential updates for static scenes
- Adaptive decimation based on FIFO depth
- Double-buffered pipeline

---

## Related Documents

- **Hardware:** `DOCs/OLED-Display-Hardware.md`
- **Sensor Pipeline:** `DOCs/Sensor-Architecture.md` (TBD)
- **FIFO Manager:** `DOCs/FIFO-Architecture.md` (TBD)
- **System Architecture:** `DOCs/System-Architecture.md` (TBD)

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-04 | Claude + Stephen | Initial architecture specification |
