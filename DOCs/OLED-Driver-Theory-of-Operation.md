# OLED Driver Theory of Operation
**Magnetic Imaging Tile - isp_oled_single_cog.spin2**

## Document Version
- **Version:** 1.0
- **Date:** 2025-11-29
- **Status:** Implementation Documentation (Post-Optimization)

## Overview

The OLED driver (`isp_oled_single_cog.spin2`) is a high-performance, single-COG solution for displaying magnetic field visualizations on a 128x128 SSD1351 OLED display. Through careful optimization, the driver achieves **55 fps** sustained display rate while consuming only a single COG resource.

### Key Achievements
- **55 fps** sustained frame rate (measured)
- **Single COG** operation (consolidated from earlier multi-COG design)
- **~18 ms** total frame time (620 us render + 17 ms SPI transfer)
- **32 KB** pixel buffer with pre-computed lookup tables
- **Smart Pin** SPI for hardware-assisted transmission

---

## Architecture Overview

### Data Flow
```
Sensor FIFO ─────────────────────────────────────────────────────────────┐
     │                                                                   │
     ▼                                                                   │
┌─────────────────────────────────────────────────────────────────────┐  │
│                          OLED Driver COG                            │  │
│                                                                     │  │
│  ┌──────────────┐    ┌───────────────┐    ┌──────────────────────┐ │  │
│  │ Frame        │    │ PASM Render   │    │ PASM SPI Stream      │ │  │
│  │ Dequeue      │───▶│ to Pixel      │───▶│ to Display           │ │  │
│  │ (fifo.dequeue)    │ Buffer        │    │ (stream_pixel_buffer)│ │  │
│  └──────────────┘    │ (620 us)      │    │ (17 ms)              │ │  │
│                      └───────────────┘    └──────────────────────┘ │  │
│                              │                     │                │  │
│                              ▼                     ▼                │  │
│                      ┌──────────────┐      ┌──────────────┐        │  │
│                      │ pixel_buffer │      │ SPI Smart    │        │  │
│                      │ 32KB         │      │ Pins (MOSI,  │        │  │
│                      │ (16384 words)│      │ SCLK)        │        │  │
│                      └──────────────┘      └──────────────┘        │  │
│                              ▲                     │                │  │
│                      ┌───────┴───────┐             │                │  │
│                      │               │             │                │  │
│              ┌───────────────┐ ┌───────────────┐   │                │  │
│              │ color_lut    │ │ cell_origin_  │   │                │  │
│              │ (4096 entries│ │ lut (64       │   │                │  │
│              │ 8KB)         │ │ entries)      │   │                │  │
│              └───────────────┘ └───────────────┘   │                │  │
└─────────────────────────────────────────────────────────────────────┘  │
                                                     │                   │
                                                     ▼                   │
                                            ┌──────────────┐             │
                                            │ SSD1351      │             │
                                            │ 128x128 OLED │             │
                                            │ Display      │             │
                                            └──────────────┘             │
                                                                         │
Frame Release ◄──────────────────────────────────────────────────────────┘
```

### Memory Layout
| Buffer | Size | Type | Purpose |
|--------|------|------|---------|
| pixel_buffer | 32 KB | WORD[16384] | Pre-rendered 128x128 RGB565 frame |
| color_lut | 8 KB | WORD[4096] | 12-bit sensor → RGB565 color mapping |
| cell_origin_lut | 128 bytes | WORD[64] | Pre-computed cell pixel offsets |
| display_cog_stack | 256 bytes | LONG[64] | COG execution stack |

---

## Performance Analysis

### Timing Breakdown (Measured at 250 MHz)

| Phase | Duration | Description |
|-------|----------|-------------|
| FIFO Dequeue | ~10 us | Lock acquisition + pointer retrieval |
| **PASM Render** | **620 us** | Sensor → pixel buffer with LUT lookups |
| Window Setup | ~40 us | Set row/column commands (6 SPI bytes) |
| **SPI Stream** | **17 ms** | 32,768 bytes at 20 MHz SPI |
| Frame Release | ~10 us | Lock + pointer update |
| **Total** | **~18 ms** | **~55 fps** |

### SPI Transmission Analysis

**Theoretical minimum:**
- 32,768 bytes x 8 bits = 262,144 bits
- At 20 MHz: 262,144 / 20,000,000 = **13.1 ms**

**Measured actual: ~17 ms**

**Gap analysis (from logic analyzer):**
- Byte transmission time: 364 ns (8 bits at 20 MHz = 400 ns theoretical)
- Inter-byte gap: ~3.3 us (PASM loop overhead)
- Inter-pixel gap: slightly larger (pixel consists of 2 bytes)

**Overhead breakdown:**
- Total gap time: 32,768 bytes x 3.3 us ≈ 108 ms (if all gaps were 3.3 us)
- Actual measured: ~4 ms overhead (optimized with waitse1 events)
- Efficiency: ~77% of theoretical SPI bandwidth utilized

---

## Key Optimizations

### 1. Pre-computed Color Lookup Table (color_lut)

**Problem:** Converting 12-bit sensor values to RGB565 colors requires floating-point-like math (normalization, gradient calculation).

**Solution:** Pre-compute all 4096 possible colors at initialization.

```spin2
' At init time (once):
repeat i from 0 to 4095
  normalized := (i * 511) / 4095
  ' ... calculate RGB ...
  color_lut[i] := color

' At render time (per sensor, 64x per frame):
color_val := color_lut[sensor_value]  ' Single memory read
```

**Benefit:** Eliminates 64 expensive calculations per frame.

### 2. Pre-computed Cell Origin Lookup Table (cell_origin_lut)

**Problem:** Each sensor cell's pixel position depends on orientation, requiring coordinate transformation math.

**Solution:** Pre-compute all 64 cell origins at initialization.

```spin2
' At init time:
repeat row from 0 to 7
  repeat col from 0 to 7
    get_cell_origin(row, col, @px, @py)
    pixel_offset := (py * WIDTH) + px
    cell_origin_lut[sensor_idx] := pixel_offset

' At render time:
cell_origin := cell_origin_lut[sensor_idx]  ' Single memory read
```

**Benefit:** Eliminates orientation math from hot render loop.

### 3. Inline PASM Render (render_to_pixel_buffer)

**Problem:** Spin2 rendering was taking 4 ms per frame.

**Solution:** Convert render loop to inline PASM with unrolled pixel writes.

```pasm2
.cell_loop
  rdword  sensor_val, ptra++        ' Read sensor
  ; ... clamp to 12-bit ...
  rdword  color_val, sensor_val     ' LUT lookup
  rdword  cell_origin, pa           ' Get cell position

.row_loop
  ; 16 unrolled wrword instructions per row
  wrword  color_val, row_ptr
  add     row_ptr, #2
  ; ... repeat 16x ...
  add     cell_origin, row_stride
  djnz    row_count, #.row_loop

  djnz    pb, #.cell_loop
```

**Result:** Render time reduced from **4 ms to 620 us** (6.5x improvement).

### 4. Event-Based SPI Waiting (waitse1)

**Problem:** Polling `PINR(pin_sclk)` in a tight loop wastes cycles and introduces latency.

**Solution:** Use P2 event system to wait efficiently for Smart Pin completion.

```pasm2
' Configure event for SCLK IN flag rise
mov     pa, sclk_pin
or      pa, #%01_000000       ' Positive edge event
setse1  pa

.pixel_loop
  ; Send high byte
  wypin   byte_val, mosi_pin
  akpin   sclk_pin            ' Clear stale IN flag
  wypin   #8, sclk_pin        ' Trigger 8 clocks
  waitse1                     ' Wait for completion (low-power)

  ; Send low byte (immediately after waitse1)
  ; ... same pattern ...
```

**Key insight:** `akpin` is required to clear stale Smart Pin IN flags before each transfer.

**Benefit:** More efficient waiting, slightly improved gap timing.

### 5. Full-Screen Window with set_window_raw

**Problem:** The display hardware applies `ROW_OFFSET = -32` which causes invalid window coordinates for full-screen streaming.

**Discovery:** `set_window(0, 0, 127, 127)` was calculating rows -32 to 95 (invalid).

**Solution:** Created `set_window_raw()` that bypasses offset application for full-screen operations.

```spin2
PRI set_window_raw(x1, y1, x2, y2)
'' Set active drawing window without applying offsets
'' Used for full-screen streaming
  send_command(CMD_SET_COLUMN)
  send_data(x1)    ' No COLUMN_OFFSET
  send_data(x2)
  send_command(CMD_SET_ROW)
  send_data(y1)    ' No ROW_OFFSET
  send_data(y2)
  send_command(CMD_WRITE_RAM)
```

**Note:** Cell-by-cell rendering (slow method) still uses `set_window()` with offsets for per-cell positioning.

---

## Smart Pin Configuration

### SCLK Pin (Clock Generation)
```spin2
' P_PULSE mode: generates N pulses when triggered
PINSTART(pin_sclk, P_OE | P_PULSE, clk_period | (clk_period >> 1) << 16, 0)
```
- **Mode:** P_PULSE (hardware pulse generator)
- **Period:** Calculated for 20 MHz at system clock
- **Trigger:** `WYPIN pin_sclk, #8` generates exactly 8 clock pulses

### MOSI Pin (Data Transmission)
```spin2
' P_SYNC_TX mode: shifts out data synchronized to external clock
PINSTART(pin_mosi, P_OE | P_SYNC_TX | ((pin_sclk - pin_mosi) & %111) << 24, %1_00000 | 7, 0)
```
- **Mode:** P_SYNC_TX (synchronous serial transmit)
- **Clock source:** Linked to SCLK pin via offset in bits 24-26
- **Shift register:** 8 bits, MSB first (after REV instruction)

### Bit Reversal
The SSD1351 expects MSB-first data, but Smart Pin transmits LSB-first. Solution: reverse bits before transmission.

```pasm2
mov     byte_val, pixel_val
shr     byte_val, #8          ' Get high byte
shl     byte_val, #24         ' Position at top of register
rev     byte_val              ' Reverse all 32 bits (MSB now at bit 0)
wypin   byte_val, mosi_pin    ' Load into shift register
```

---

## Color Mapping

### Sensor Value to Color Conversion

**Input:** 12-bit sensor value (0-4095)
**Output:** 16-bit RGB565 color (BGR format for SSD1351)

**Color Gradient:**
```
Sensor Value    Color           Meaning
    0           Blue (000F)     Strong negative field
  1024          Cyan            Moderate negative
  2048          Green (07E0)    Neutral (zero field)
  3072          Yellow          Moderate positive
  4095          Red (F800)      Strong positive field
```

**RGB565 Format (BGR for SSD1351):**
```
Bits: BBBB_BGGG_GGGR_RRRR
      15-11: Blue (5 bits)
      10-5:  Green (6 bits)
      4-0:   Red (5 bits)
```

**Conversion formula:**
```spin2
color := ((b >> 3) << 11) | ((g >> 2) << 5) | (r >> 3)
```

---

## Display Orientation System

### Physical Setup
The system supports four display orientations based on ribbon cable position:

| Constant | Ribbon Position | Remap Value | Use Case |
|----------|-----------------|-------------|----------|
| ORIENTATION_0 | BOTTOM | $73 | Hardware default |
| ORIENTATION_90 | LEFT | $72 | **Default for this project** |
| ORIENTATION_180 | TOP | $70 | Inverted mounting |
| ORIENTATION_270 | RIGHT | $71 | Alternative orientation |

### Coordinate Transformation

The sensor array layout doesn't directly match the display layout. A two-stage transformation corrects this:

**Stage 1: Sensor-to-Display Normalization**
```spin2
temp_row := col    ' 90 degree rotation
temp_col := row
```

**Stage 2: Orientation-Specific Positioning**
```spin2
case orientation
  ORIENTATION_90:  ' Ribbon LEFT (project default)
    px := (7 - temp_col) * CELL_WIDTH
    py := (7 - temp_row) * CELL_HEIGHT
```

The `cell_origin_lut` pre-computes these transformations for all 64 cells at initialization.

---

## Frame Display Methods

### Method 1: display_frame() - Cell-by-Cell (Slow)

**Use case:** Testing, debugging, baseline measurement

**Approach:**
1. For each sensor (64 iterations)
2. Read sensor value, convert to color
3. Set 16x16 window for this cell
4. Send 256 pixels via SPI
5. Deassert CS between cells

**Performance:** ~130 ms per frame (~7 fps)

**Bottleneck:** Window setup overhead per cell (64 x ~40 us = 2.6 ms just for commands)

### Method 2: display_frame_fast() - Full-Buffer (Optimized)

**Use case:** Production, real-time display

**Approach:**
1. **Phase 1 (PASM):** Render all 64 sensors to pixel_buffer (620 us)
2. **Phase 2 (PASM):** Stream entire 32KB buffer to display (17 ms)

**Performance:** ~18 ms per frame (**55 fps**)

**Key advantages:**
- Single window setup (one set of commands)
- CS stays asserted for entire transfer (no per-cell overhead)
- PASM execution for both phases

---

## Integration with System

### FIFO Interface
```spin2
' Blocking dequeue from OLED FIFO
framePtr := fifo.dequeue(fifo.FIFO_OLED)

' Process frame...

' Return frame to pool
fifo.releaseFrame(framePtr)
```

### Decimation Requirements

At 55 fps OLED capability, the decimator must limit input rate:

| Sensor Rate | Decimation | OLED Rate | Margin |
|-------------|------------|-----------|--------|
| 375 fps | 7 | 53.6 fps | Safe (headroom) |
| 375 fps | 6 | 62.5 fps | May drop frames |

**Recommended:** Decimation = 7 (conservative, allows FIFO to stay empty)

---

## Hardware Pin Assignments

| Signal | P2 Pin | Function | Direction |
|--------|--------|----------|-----------|
| MOSI | P16 | SPI Data (Smart Pin SYNC_TX) | Output |
| SCLK | P18 | SPI Clock (Smart Pin PULSE) | Output |
| CS | P20 | Chip Select (GPIO) | Output |
| DC | P22 | Data/Command (GPIO) | Output |
| RST | P23 | Reset (GPIO) | Output |

---

## Debug Output

Key timing is reported after frame 6 for test programs:

```
OLED: Frame timing summary (6 frames)
  Last: 18143 us = 55 fps
  Min: 18089 us = 55 fps
  Max: 18201 us = 54 fps
```

---

## Future Optimization Opportunities

### 1. Streamer/DMA Transfer
- Could eliminate CPU involvement during SPI transfer
- Potential improvement: 17 ms → 13.5 ms (theoretical limit)
- Would require pre-processing for bit reversal

### 2. 32x32 Sensor Grid Support
- Current architecture is parameterized (CELL_WIDTH, CELL_HEIGHT)
- Would require: larger cell_origin_lut (1024 entries), smaller cells (4x4 pixels)
- Performance: Render would increase, SPI stays same

### 3. Differential Updates
- Only update changed cells
- Best for static/slow-changing fields
- Tradeoff: Comparison overhead vs SPI savings

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-29 | Initial documentation after optimization to 55 fps |

---

## Related Documents

- **Hardware Specification:** `DOCs/OLED-Display-Hardware.md`
- **Architecture Design:** `DOCs/Architecture/OLED-Driver-Architecture.md`
- **System Integration:** `DOCs/Architecture/System-Architecture.md`
