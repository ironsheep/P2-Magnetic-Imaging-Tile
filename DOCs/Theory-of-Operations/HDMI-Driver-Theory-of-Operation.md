# HDMI Display Driver Theory of Operation
**Magnetic Imaging Tile - HDMI Visualization System**

## Document Version
- **Version:** 1.1
- **Date:** 2025-12-23
- **Status:** Implementation Documentation

## Overview

The HDMI display system provides real-time 640×480 @ 60Hz video output for visualizing magnetic field sensor data. The implementation uses a multi-layer architecture with dedicated COGs for video generation and display rendering.

### Key Specifications
- **Resolution:** 640 × 480 pixels @ 60 Hz refresh
- **Pixel Format:** 32-bit RRGGBBAA (with RGB24 streaming)
- **Frame Buffer:** 1.2 MB in external PSRAM
- **COG Usage:** 2 COGs (HDMI signal generation + Display engine)
- **Latency:** < 16.7 ms (single frame)
- **FIFO Interface:** Event-driven with COGATN/WAITATN (zero-power wait)

---

## System Architecture

### Object Hierarchy

```
┌──────────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                              │
│                  mag_tile_viewer.spin2                            │
│           (System orchestration, FIFO routing)                    │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                    DISPLAY ENGINE LAYER                           │
│               isp_hdmi_display_engine.spin2                       │
│        (Frame consumption, sensor-to-color mapping)               │
│                         ▲                                         │
│                         │                                         │
│    Uses: isp_frame_fifo_manager (frame input)                     │
│          isp_psram_graphics (drawing operations)                  │
│          isp_stack_check (overflow detection)                     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                    GRAPHICS LAYER                                 │
│                isp_psram_graphics.spin2                           │
│         (Drawing primitives, text rendering)                      │
│                         ▲                                         │
│                         │                                         │
│    Uses: isp_hub75_fonts (bitmap fonts)                           │
│          isp_hdmi_640x480_24bpp (HDMI driver)                     │
│          psram_driver.spin2 (PSRAM access)                        │
└──────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌────────────────────────┐     ┌─────────────────────────────────┐
│    HDMI SIGNAL COG     │     │         PSRAM DRIVER COG        │
│isp_hdmi_640x480_24bpp  │     │       psram_driver.spin2        │
│ (Video timing/output)  │     │  (Memory read/write commands)   │
└────────────────────────┘     └─────────────────────────────────┘
           │                                 │
           ▼                                 ▼
    P0-P7 HDMI Pins                   P40-P57 PSRAM Pins
```

### COG Allocation

| COG | Function | Object | Notes |
|-----|----------|--------|-------|
| 0 | Main/Decimator | mag_tile_viewer | Frame routing, FIFO management |
| 1 | Sensor Acquisition | isp_tile_sensor | SPI ADC, 64-sensor readout |
| 2 | PSRAM Driver | psram_driver | Shared memory interface |
| 3 | HDMI Signal Generator | isp_hdmi_640x480_24bpp | Video timing, streaming |
| 4 | HDMI Display Engine | isp_hdmi_display_engine | Rendering, color mapping |
| 5 | OLED Driver | isp_oled_single_cog | Secondary display |
| 6-7 | Available | - | Reserved for expansion |

---

## Object Details

### 1. isp_hdmi_display_engine.spin2

**Purpose:** Consumes frames from HDMI FIFO and renders sensor data visualization.

**Responsibilities:**
- Register as HDMI FIFO consumer for event-driven wake-ups
- Dequeue frames using WAITATN (zero-power sleep until data available)
- Convert 16-bit sensor values to display colors
- Render 8×8 sensor grid with color-coded cells
- Update frame counter and statistics

**Key Methods:**
```spin2
PUB start(hdmi_base_pin) : ok     ' Start display engine COG
PUB stop()                         ' Stop display engine
PUB set_display_mode(mode)         ' Configure visualization mode
PUB get_frame_count() : count      ' Get frames rendered
```

**Color Mapping Pipeline:**
```
Sensor Value (0-65535) → Palette Index (0-7) → RRGGBBAA Color

Palette:
  Index 0: $000080FF - Strong negative (dark blue)
  Index 1: $0000FFFF - Negative (bright blue)
  Index 2: $0080FFFF - Weak negative (cyan)
  Index 3: $00FF00FF - Neutral (green)
  Index 4: $80FF00FF - Weak positive (yellow-green)
  Index 5: $FFFF00FF - Positive (yellow)
  Index 6: $FF8000FF - Strong positive (orange)
  Index 7: $FF0000FF - Very strong positive (red)
```

**Grid Configuration:**
```spin2
GRID_X      = 200       ' Grid top-left X position
GRID_Y      = 100       ' Grid top-left Y position
CELL_SIZE   = 30        ' Size of each sensor cell in pixels
CELL_GAP    = 3         ' Gap between cells in pixels
```

### 2. isp_psram_graphics.spin2

**Purpose:** Provides graphics primitives for drawing to PSRAM frame buffer.

**Initialization Pattern:**
```spin2
' From main COG (once):
gfx.init(HDMI_BASE_PIN)    ' Initialize hardware

' From each COG that draws:
gfx.start()                ' Initialize per-COG PSRAM mailbox
```

**Key Drawing Methods:**
```spin2
PUB FillRect(rx1, ry1, rx2, ry2, rcolor)      ' Filled rectangle
PUB DrawHLine(lx1, lx2, ly, lcolor)            ' Horizontal line
PUB DrawVLine(vx, vy1, vy2, vcolor)            ' Vertical line
PUB DrawBox(bx1, by1, bx2, by2, bcolor)        ' Box outline
PUB DrawSensorGrid(base_x, base_y, cell_size, gap)  ' 8×8 grid
PUB FillSensorCell(row, col, base_x, base_y, cell_size, gap, color)
PUB cls(clr)                                    ' Clear screen
```

**Text Rendering:**
```spin2
PUB SetFont(font_id)              ' Select font
PUB DrawChar(x, y, ch, color)     ' Single character
PUB DrawText(x, y, pString, clr)  ' String of text
PUB DrawTextCentered(centerX, y, pString, clr)  ' Centered text
```

**PSRAM Communication:**
```spin2
' Each COG gets its own 12-byte mailbox in PSRAM driver:
psram_ptr := psram.pointer() + cogid() * 12

' Write command to PSRAM:
long[psram_ptr][0] := @source_buffer  ' Hub source address
long[psram_ptr][1] := psram_address   ' PSRAM destination
long[psram_ptr][2] := -count          ' Negative = Hub→PSRAM
repeat while long[psram_ptr][2]       ' Wait for completion
```

### 3. isp_hdmi_640x480_24bpp.spin2

**Purpose:** Generates VGA-compliant 640×480 @ 60Hz HDMI video signal.

**Video Timing (Standard VGA):**
```
Horizontal:
  ├── 640 visible ──┤── 16 front ──┤── 96 sync ──┤── 48 back ──┤
  └────────────────────────── 800 total ────────────────────────┘

Vertical:
  ├── 480 visible ──┤── 10 front ──┤── 2 sync ──┤── 33 back ──┤
  └───────────────────────── 525 total ─────────────────────────┘

Pixel Clock: 25.175 MHz (250 MHz / 10)
Refresh: 60 Hz
```

**Critical Streamer Configuration:**
```spin2
' CORRECT - RGB24 streaming mode (WORKS)
m_vi long $B0860000 + xpix    ' Visible (rflong rgb24)

' WRONG - 32-bit mode (causes black screen)
' m_vi long $7F810000 + xpix  ' DON'T USE THIS
```

**PSRAM Integration:**
```pasm
' Per-line PSRAM read command:
cmd_hub := pix_bas              ' Hub RAM destination (double-buffered)
cmd_ram := ram_bas + line*640   ' PSRAM source (frame buffer)
cmd_len := 640                  ' Pixels per line
```

**Double-Buffering:**
- Two alternating 640-long pixel buffers in Hub RAM
- PSRAM loads next line while current line streams to HDMI
- Eliminates tearing artifacts

### 4. psram_driver.spin2

**Purpose:** Provides shared access to 32MB external PSRAM for all COGs.

**Hardware Configuration:**
```spin2
CS_PIN = 57        ' PSRAM Chip Select
CK_PIN = 56        ' PSRAM Clock
Data:  P40-P55     ' 16-bit data bus
```

**Command Interface:**
```spin2
' Each COG uses a 3-long command structure:
' ptr := psram.pointer() + cogid() * 12

long[ptr][0] = hub_address      ' Hub RAM byte address
long[ptr][1] = psram_address    ' PSRAM long address
long[ptr][2] = transfer_length  ' +N = read, -N = write

' Driver zeroes long[2] when transfer completes
```

**Performance:**
- One long transfers every 4 clocks
- Half-page blocks to keep CS active < 8µs
- Round-robin COG polling with priority support
- Tuned for 250-340 MHz operation

### 5. isp_hub75_fonts.spin2

**Purpose:** Provides bitmap fonts for text rendering.

**Available Fonts:**
```spin2
TEXT_FONT_5x7           ' Standard 5×7 font
TEXT_FONT_5x7_DITH      ' 5×7 with dithering (anti-aliased)
TEXT_FONT_5x7_DITH_DCNDR ' 5×7 dithered with descenders (default)
TEXT_FONT_8x8A          ' 8×8 font variant A
TEXT_FONT_8x8B          ' 8×8 font variant B
```

**Dithered Font Rendering:**
- 2 bits per pixel for anti-aliasing
- Pixel values: 0/2=transparent, 1=50% brightness, 3=full brightness

---

## Data Flow

### Frame Display Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                     SENSOR FIFO                                  │
│              (64 WORDs = 128 bytes per frame)                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (Decimator routes every Nth frame)
┌─────────────────────────────────────────────────────────────────┐
│                      HDMI FIFO                                   │
│          (Buffered frames awaiting display)                      │
│                                                                  │
│  On commitFrame():                                               │
│    1. Frame added to FIFO queue                                  │
│    2. COGATN sent to registered HDMI consumer COG                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ fifo.dequeueEventDriven(FIFO_HDMI)
                                (WAITATN sleeps until COGATN received)
┌─────────────────────────────────────────────────────────────────┐
│              HDMI DISPLAY ENGINE (COG 4)                         │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ For each sensor (0-63):                                   │   │
│  │   1. Read sensor value from frame buffer                  │   │
│  │   2. Map value to color via field_to_color()              │   │
│  │   3. Call gfx.FillSensorCell(row, col, ..., color)        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ PSRAM write commands
┌─────────────────────────────────────────────────────────────────┐
│                    PSRAM FRAME BUFFER                            │
│              (640 × 480 × 4 bytes = 1.2 MB)                      │
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  Address 0x00000: Line 0 (640 × 4 = 2560 bytes)         │   │
│   │  Address 0x00A00: Line 1                                 │   │
│   │  ...                                                     │   │
│   │  Address 0x12B800: Line 479                              │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ PSRAM read commands (per scan line)
┌─────────────────────────────────────────────────────────────────┐
│              HDMI SIGNAL GENERATOR (COG 3)                       │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Per visible line:                                         │   │
│  │   1. Request 640 longs from PSRAM                         │   │
│  │   2. Stream via XCONT to HDMI pins                        │   │
│  │   3. Generate H/V sync pulses                             │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                      P0-P7 HDMI Output
                     (640×480 @ 60 Hz)
```

---

## Pin Assignments

### HDMI Output (Pin Group 0: P0-P7)

| Pin | Signal | Description |
|-----|--------|-------------|
| P0 | DATA2- | TMDS Data Channel 2 (negative) |
| P1 | DATA2+ | TMDS Data Channel 2 (positive) |
| P2 | DATA1- | TMDS Data Channel 1 (negative) |
| P3 | DATA1+ | TMDS Data Channel 1 (positive) |
| P4 | DATA0- | TMDS Data Channel 0 (negative) |
| P5 | DATA0+ | TMDS Data Channel 0 (positive) |
| P6 | CLK- | TMDS Clock (negative) |
| P7 | CLK+ | TMDS Clock (positive) |

**Pin Configuration:** `%10111_1000_0100_10_00000_0` (75-ohm 1-bit DACs)

### PSRAM (Pin Group 5: P40-P57)

| Pin Range | Signal | Description |
|-----------|--------|-------------|
| P40-P55 | DATA[15:0] | 16-bit bidirectional data bus |
| P56 | CK | PSRAM Clock |
| P57 | CS | PSRAM Chip Select |

---

## Critical Implementation Notes

### 1. Streamer Mode (RGB24 vs 32-bit)

**CRITICAL:** Frame buffer uses 32-bit RRGGBBAA, but streamer MUST use RGB24 mode:

```spin2
' CORRECT - displays properly:
m_vi long $B0860000 + xpix    ' rflong RGB24 mode

' WRONG - causes black screen:
m_vi long $7F810000 + xpix    ' rflong 32-bit mode
```

The streamer reads 32-bit values but only outputs the RGB24 portion to pins. The alpha channel is stored in memory but ignored during streaming.

### 2. Color Format

All colors must be 32-bit RRGGBBAA:
```spin2
$FF0000FF  ' Red (fully opaque)
$00FF00FF  ' Green
$0000FFFF  ' Blue
$FFFFFFFF  ' White
$000000FF  ' Black

' WRONG (appears as wrong color):
$FFFFFF    ' Missing alpha byte!
```

### 3. Pin Initialization Sequence

Pins must be cleared before reconfiguring:
```pasm
fltl    pin_grp             ' Float all 8 pins
wrpin   #0, pin_grp         ' Clear pin modes
wrpin   ##pin_cfg, pin_grp  ' Configure for HDMI
drvl    pin_grp             ' Drive pins low
```

### 4. Multi-COG Graphics Initialization

```spin2
' Main COG (once):
gfx.init(HDMI_BASE_PIN)    ' Start PSRAM & HDMI hardware

' Each graphics COG:
gfx.start()                ' Get per-COG PSRAM mailbox
```

### 5. PSRAM Guard Checks

All drawing methods should validate psram_ptr:
```spin2
if psram_ptr == 0
  debug("ERROR: psram_ptr is NULL!")
  return
```

---

## Event-Driven FIFO Interface

The HDMI display engine uses P2's COGATN/WAITATN mechanism for zero-power, zero-jitter frame synchronization.

### Initialization Pattern

```spin2
' In display_loop() - register for event-driven wake-ups
fifo.registerConsumer(FIFO_HDMI, cogid())

repeat
  ' WAITATN sleeps until decimator sends COGATN
  framePtr := fifo.dequeueEventDriven(FIFO_HDMI)

  if framePtr <> 0
    ' Render all 64 sensor cells...
    repeat row from 0 to 7
      repeat col from 0 to 7
        sensorVal := WORD[framePtr][row * 8 + col]
        cellColor := field_to_color(sensorVal)
        gfx.FillSensorCell(row, col, GRID_X, GRID_Y, CELL_SIZE, CELL_GAP, cellColor)

    ' Release frame back to pool
    fifo.releaseFrame(framePtr)
```

### Comparison: Polling vs Event-Driven

| Aspect | Polling (Old) | Event-Driven (Current) |
|--------|---------------|------------------------|
| Power | COG runs continuously | COG sleeps between frames |
| Jitter | 0-1ms polling interval | ~4 clock cycles wake latency |
| CPU Load | 100% during idle | Near-zero during idle |
| Wake Mechanism | Loop with waitus() | WAITATN instruction |
| Independence | N/A | Each FIFO has own consumer |

### Benefits of Event-Driven Architecture

1. **Zero-Power Waiting**: COG executes WAITATN and halts until COGATN received
2. **Zero Jitter**: Wake-up latency is ~4 clock cycles (~16ns at 250MHz)
3. **Independent FIFOs**: HDMI and OLED consumers are notified separately
4. **Automatic Rate Matching**: Display runs at exact decimated rate (no polling delays)
5. **Producer-Driven Timing**: Sensor/decimator controls display update rate

---

## Performance Characteristics

| Metric | Value |
|--------|-------|
| Frame buffer size | 1,228,800 bytes (1.2 MB) |
| Pixel clock | 25.175 MHz |
| Frame rate | 60 Hz |
| Line time | 31.77 µs (800 pixels) |
| Visible line time | 25.42 µs (640 pixels) |
| PSRAM bandwidth | ~18 MB/s per COG |
| FillRect (30×30) | ~30 µs |
| Full frame clear | ~50 ms |

---

## Troubleshooting

### Black Screen
1. Verify streamer mode is `$B0860000` (RGB24)
2. Check pin clearing sequence before configuration
3. Confirm PSRAM driver is running
4. Verify correct pin group (0 for HDMI)

### Wrong Colors
1. Ensure 32-bit RRGGBBAA format (include alpha byte)
2. Check color palette constants
3. Verify sensor-to-color mapping logic

### Tearing/Artifacts
1. Verify double-buffering is working
2. Check PSRAM timing at current clock frequency
3. Ensure COG priority if needed for HDMI

### No Sensor Data Display
1. Verify HDMI FIFO is receiving frames
2. Check decimation ratio (not skipping all frames)
3. Confirm display engine COG started successfully
4. Verify gfx.start() called from display engine COG

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-23 | Initial documentation |
| 1.1 | 2025-12-23 | Added event-driven FIFO interface documentation (COGATN/WAITATN) |
