# HDMI Display Interface - Hardware Configuration & Critical Settings

## Overview
The P2 Magnetic Imaging Tile system outputs video via HDMI at 640×480 @ 60Hz using the P2's built-in video streaming capabilities combined with external PSRAM for frame buffering.

## Hardware Configuration

### Pin Assignment
- **Pin Group**: 0 (P0-P7)
- **Configuration**: 8-pin bit-DAC mode for differential HDMI signaling
- **Pin Mode**: `%10111_1000_0100_10_00000_0` (bit-DAC pins for HDMI)

| Pin | HDMI Signal | Description |
|-----|-------------|-------------|
| P0  | DATA2-  | TMDS Data Channel 2 (negative) |
| P1  | DATA2+  | TMDS Data Channel 2 (positive) |
| P2  | DATA1-  | TMDS Data Channel 1 (negative) |
| P3  | DATA1+  | TMDS Data Channel 1 (positive) |
| P4  | DATA0-  | TMDS Data Channel 0 (negative) |
| P5  | DATA0+  | TMDS Data Channel 0 (positive) |
| P6  | CLK-    | TMDS Clock Channel (negative) |
| P7  | CLK+    | TMDS Clock Channel (positive) |

### Frame Buffer
- **Location**: External PSRAM (32MB P2 Edge Module)
- **Base Address**: 0 (start of PSRAM)
- **Size**: 640 × 480 × 4 bytes = 1,228,800 bytes (1.2MB)
- **Format**: 32-bit RRGGBBAA (Red, Green, Blue, Alpha)
- **PSRAM Pins**: P40-P55 (data), P56 (clock), P57 (CS)

## Video Timing

### VGA 640×480 @ 60Hz Standard Timing
- **Pixel Clock**: 25.175 MHz (achieved via 250 MHz system clock ÷ 10)
- **Horizontal Timing**:
  - Visible: 640 pixels
  - Front porch: 16 pixels
  - Sync pulse: 96 pixels
  - Back porch: 48 pixels
  - **Total: 800 pixels**
- **Vertical Timing**:
  - Visible: 480 lines
  - Front porch: 10 lines
  - Sync pulse: 2 lines
  - Back porch: 33 lines
  - **Total: 525 lines**
- **Refresh Rate**: 60 Hz (800 × 525 × 60 = 25.2 MHz pixel clock)

## ⚠️ CRITICAL Configuration - Streamer Mode

**THIS IS THE KEY TO MAKING HDMI WORK!**

### The Problem
The frame buffer stores 32-bit RGBA data (`$RRGGBBAA`), but the HDMI output requires **RGB24 format streaming**.

### The Solution
Even though memory uses 32-bit format, the **streamer command MUST use RGB24 mode** (`$B0860000`).

**WRONG (causes black screen):**
```spin2
m_vi long $7F810000 + xpix  'visible (rflong 32-bit) - DOES NOT WORK!
```

**CORRECT (displays properly):**
```spin2
m_vi long $B0860000 + xpix  'visible (rflong rgb24) - WORKS!
```

### Why This Works
- Frame buffer: 32-bit RRGGBBAA format in PSRAM (aligned access, easy indexing)
- Streamer: Reads 32-bit values but **outputs only the RGB24 portion** to pins
- Alpha channel: Stored in memory but **ignored during streaming** to HDMI
- Result: Best of both worlds - 32-bit memory efficiency, 24-bit output compatibility

### Streamer Command Breakdown
```
$B0860000 = %10110000_10000110_00000000_00000000

Bits 31-28: 1011 = RFLONG (read longs from hub RAM)
Bits 27-26: 00   = No NCO mode
Bit  25:    0    = Not post-clock
Bit  24:    0    = No DDS mode
Bits 23-18: 000110 = Format: RGB24 (8R, 8G, 8B)
Bits 17-11: 0000000 = Pin group (filled in at runtime)
Bits 10-0:  variable = Pixel count (640 in this case)
```

### Other Streamer Commands (for reference)
```spin2
m_bs long $70810000 + h_front   ' Front porch (16 pixels)
m_sn long $70810000 + h_sync    ' Sync pulse (96 pixels)
m_bv long $70810000 + h_back    ' Back porch (48 pixels)
m_nv long $70810000 + xpix      ' Invisible/blank visible (640 pixels)
```

## Pin Initialization Sequence

**CRITICAL:** Pins must be cleared before reconfiguring to avoid state conflicts:

```pasm2
' Force pins to known state before reconfiguring
fltl    pin_grp                 ' Float all 8 pins (clear any prior config)
wrpin   #0, pin_grp             ' Clear pin modes

' Now configure for HDMI
wrpin   ##pin_cfg, pin_grp      ' Enable HDMI pins as 75-ohm 1-bit DACs
drvl    pin_grp                 ' Drive pins low initially
```

## PSRAM Integration

### Read Command Structure
The HDMI driver issues read commands to PSRAM for each visible line:

```spin2
' Command structure (3 longs):
cmd_hub := pix_bas              ' Hub RAM destination (pixel buffer)
cmd_ram := ram_bas + offset     ' PSRAM source address
cmd_len := xpix                 ' Number of longs to read (640)

' Write command to PSRAM driver mailbox
setq    #3-1
wrlong  cmd_, ram_cmd_
```

### Double-Buffering
- Two alternating 640-long pixel line buffers in Hub RAM
- PSRAM streams next line while current line displays
- Eliminates tearing and ensures smooth video

## Graphics Rendering

### Color Format
All graphics primitives use 32-bit RRGGBBAA:
- Red: bits 31-24
- Green: bits 23-16
- Blue: bits 15-8
- Alpha: bits 7-0 (stored but not used by HDMI streamer)

**Example colors:**
```spin2
$FF0000FF  ' Red
$00FF00FF  ' Green
$0000FFFF  ' Blue
$FFFFFFFF  ' White
$000000FF  ' Black
$0020_00FF ' Dark green (for backgrounds)
```

### Grid Rendering
Grid lines must use proper 32-bit format:

**WRONG:**
```spin2
DrawHLine(x1, x2, y, $FFFFFF)  ' 24-bit - shows as CYAN!
```

**CORRECT:**
```spin2
DrawHLine(x1, x2, y, $FFFFFFFF)  ' 32-bit RGBA white
```

## Troubleshooting

### Black Screen Issues
1. **Check streamer mode** - Must be `$B0860000` (RGB24), not `$7F810000` (32-bit)
2. **Verify pin clearing** - Use `fltl` and `wrpin #0` before reconfiguring
3. **Check color format** - All colors must be 32-bit RRGGBBAA
4. **Confirm PSRAM** - Verify data is actually written (use readback)

### Color Issues
- **CYAN instead of WHITE** - Using 24-bit `$FFFFFF` instead of 32-bit `$FFFFFFFF`
- **No red channel** - Alpha byte missing from color constants
- **Dim colors** - Check alpha channel is $FF (fully opaque)

### Coordinate Issues
- **Grid gaps** - Incorrect endpoint calculations (remove the `-gap` from line endpoints)
- **Off-center fills** - Not using stride properly for cell calculations

## Technical References
- P2 Propeller 2 Datasheet - Smart Streamer section
- VGA 640×480 @ 60Hz standard timing specification
- PSRAM driver by RJA (Platform 1b)
- Original HDMI driver by Chip Gracey (RJA modifications)

## Version History
- **2025-11-03**: Initial documentation - Critical RGB24 streamer mode discovery
