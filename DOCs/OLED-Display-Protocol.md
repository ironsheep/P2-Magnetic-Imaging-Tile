# SSD1351 OLED Display Communication Protocol

## Overview
This document provides the complete protocol specification for interfacing the Propeller 2 with the Waveshare 1.5inch RGB OLED module using the SSD1351 controller. The display uses a 7-pin SPI interface for all communication.

## 7-Pin Interface Connection

### Pin Assignments

**Pin Group**: 24 (P24-P31)

```
Display Pin | Function    | P2 Pin  | Direction | Description
------------|-------------|---------|-----------|------------------
1. VCC      | Power       | 3.3V    | Output    | 3.3V power supply
2. GND      | Ground      | GND     | -         | Ground reference
3. DIN      | MOSI        | P24 (+0)| Output    | SPI data (Master Out)
4. SCL      | SCLK        | P26 (+2)| Output    | SPI clock
5. CS       | Chip Select | P28 (+4)| Output    | Active low select
6. DC       | Data/Cmd    | P30 (+6)| Output    | H=Data, L=Command
7. RST      | Reset       | P31 (+7)| Output    | Active low reset
```

## SPI Communication Protocol

### SPI Configuration
- **Mode**: SPI Mode 0 (CPOL=0, CPHA=0)
- **Bit Order**: MSB First
- **Clock Speed**: Up to 20MHz (recommend 10MHz for stability)
- **Data Width**: 8-bit transfers

### Basic Communication Sequence
```
1. Set CS low (select device)
2. Set DC low for command, high for data
3. Send byte(s) via SPI
4. Set CS high (deselect device)
```

### P2 Smart Pin Configuration (Suggested)
```spin2
' Configure Smart Pins for hardware SPI
' SCLK pin - transition mode
wrpin ##P_TRANSITION | P_OE, SCLK_PIN
wxpin ##$0000_0008, SCLK_PIN  ' 8 transitions = 4 clocks

' MOSI pin - synchronous TX mode
wrpin ##P_SYNC_TX | P_OE, MOSI_PIN
wxpin ##%0_00001_0, MOSI_PIN  ' 8-bit, start/stop mode
```

## Initialization Sequence

### Power-On Reset Procedure
```
1. Power up VCC (3.3V)
2. Wait 1ms minimum
3. Set RST low
4. Wait 10µs minimum
5. Set RST high
6. Wait 120ms for internal initialization
7. Send initialization commands
```

### Required Initialization Commands
```
Step | Command | Data      | Description
-----|---------|-----------|--------------------------------
1    | 0xFD    | 0x12      | Unlock commands
2    | 0xFD    | 0xB1      | Unlock OLED driver
3    | 0xAE    | -         | Display OFF (sleep mode)
4    | 0xB3    | 0xF1      | Set clock divider (241)
5    | 0xCA    | 0x7F      | Set multiplex ratio (127)
6    | 0xA0    | 0x74      | Set remap and color depth
7    | 0x15    | 0x00,0x7F | Set column address (0-127)
8    | 0x75    | 0x00,0x7F | Set row address (0-127)
9    | 0xA1    | 0x00      | Set display start line
10   | 0xA2    | 0x00      | Set display offset
11   | 0xB5    | 0x00      | Set GPIO (disabled)
12   | 0xAB    | 0x01      | Enable internal regulator
13   | 0xB1    | 0x32      | Set phase length
14   | 0xBE    | 0x05      | Set VCOMH voltage
15   | 0xA6    | -         | Normal display mode
16   | 0xC1    | 0xC8,     | Set contrast for RGB
     |         | 0x80,     | (Red=200, Green=128, Blue=200)
     |         | 0xC8      |
17   | 0xC7    | 0x0F      | Master contrast (maximum)
18   | 0xB4    | 0xA0,     | Set VSL
     |         | 0xB5,     | (external VSL)
     |         | 0x55      |
19   | 0xB6    | 0x01      | Set second precharge period
20   | 0xAF    | -         | Display ON
```

## Command Reference

### Display Control Commands
| Command | Parameters | Function |
|---------|------------|----------|
| 0xAE | None | Display OFF |
| 0xAF | None | Display ON |
| 0xA4 | None | Display all pixels OFF |
| 0xA5 | None | Display all pixels ON |
| 0xA6 | None | Normal display |
| 0xA7 | None | Inverse display |

### Addressing Commands
| Command | Parameters | Function |
|---------|------------|----------|
| 0x15 | start, end | Set column address (0-127) |
| 0x75 | start, end | Set row address (0-127) |
| 0x5C | data... | Write RAM (followed by pixel data) |

### Timing Commands
| Command | Parameters | Function |
|---------|------------|----------|
| 0xB1 | phase | Set reset/precharge period |
| 0xB3 | divider | Set display clock divider |
| 0xB6 | period | Set second precharge period |

## Pixel Data Format

### 16-bit Color Mode (RGB565)
```
Bit:  15 14 13 12 11 | 10 9 8 7 6 5 | 4 3 2 1 0
      R4 R3 R2 R1 R0 | G5 G4 G3 G2 G1 G0 | B4 B3 B2 B1 B0
      [   Red 5-bit  ] [  Green 6-bit   ] [ Blue 5-bit ]
```

### Color Conversion
```spin2
PUB rgb888_to_rgb565(r, g, b) : color
  ' Convert 8-bit RGB to 16-bit RGB565
  color := ((r & $F8) << 8) | ((g & $FC) << 3) | (b >> 3)
```

## Writing Pixel Data

### Single Pixel Write
```
1. Set column address (0x15): start_col, end_col
2. Set row address (0x75): start_row, end_row
3. Send write command (0x5C)
4. Send pixel data (2 bytes per pixel, MSB first)
```

### Full Screen Update
```spin2
PUB clear_screen(color)
  send_command($15, $00, $7F)  ' Columns 0-127
  send_command($75, $00, $7F)  ' Rows 0-127
  send_command($5C)             ' Write RAM

  repeat 128 * 128
    send_data(color >> 8)       ' MSB
    send_data(color & $FF)      ' LSB
```

### Optimized Block Transfer
```spin2
PUB draw_block(x, y, width, height, buffer_addr)
  send_command($15, x, x + width - 1)
  send_command($75, y, y + height - 1)
  send_command($5C)

  ' Use P2 FIFO for fast transfer
  wrfast ##0, buffer_addr
  repeat width * height
    rfword pa
    send_data(pa >> 8)
    send_data(pa & $FF)
```

## Performance Optimization

### Maximum Transfer Rates
- **Theoretical Maximum**: 20MHz SPI = 2.5MB/s
- **Full Frame (16-bit)**: 128×128×2 = 32,768 bytes
- **Maximum FPS**: ~76 fps (theoretical)
- **Practical FPS**: 30-60 fps (with overhead)

### P2-Specific Optimizations
1. **Use Smart Pins**: Hardware SPI for maximum speed
2. **FIFO Transfers**: Use WRFAST/RFWORD for block data
3. **Double Buffering**: Prepare next frame while displaying current
4. **Partial Updates**: Only update changed regions

### Timing Considerations
```
Operation           | Time Required
--------------------|---------------
Command byte        | 800ns @ 10MHz
Data byte          | 800ns @ 10MHz
Full screen clear  | ~26ms
8×8 block update   | ~102µs
Single pixel       | ~3.2µs
```

### System Frame Rate Analysis

#### Complete Timing Chain
```
Operation              | Time @ 20MHz SPI | Notes
-----------------------|------------------|------------------
SPI Transfer (32KB)    | 13.1 ms         | 128×128×2 bytes
Sensor Acquisition     | 0.64 ms         | 64 sensors × 10µs
Pixel Rendering (LUT)  | 0.49 ms         | With pre-computed tables
Pixel Rendering (calc) | 6.53 ms         | Without LUT optimization
Total Frame Time (LUT) | 14.23 ms        | All operations
Total (without LUT)    | 20.27 ms        | Slower rendering
```

#### Maximum Achievable Frame Rates
| Configuration | Frame Time | Max FPS | Bottleneck |
|--------------|------------|---------|------------|
| With LUT optimization | 14.23 ms | 70.3 fps | SPI transfer (92% of time) |
| Without LUT | 20.27 ms | 49.3 fps | SPI transfer (65% of time) |
| Theoretical (SPI only) | 13.1 ms | 76.3 fps | Physical limit |
| Display at 10MHz SPI | 26.2 ms | 38.2 fps | Reduced clock speed |

#### Performance Breakdown (with LUT)
- **SPI Transfer**: 92.0% of frame time
- **Sensor Acquisition**: 4.5% of frame time
- **Pixel Rendering**: 3.5% of frame time

The SPI interface is the primary bottleneck, consuming 13.1ms per frame even at maximum 20MHz clock speed. The LUT-based rendering optimization provides 13× faster pixel generation but only improves overall frame rate by 1.42× due to SPI dominance.

## Magnetic Field Visualization Protocol

### Color Mapping Strategy
```spin2
PUB field_to_color(field_value) : color | intensity
  ' Map magnetic field strength to color
  ' Negative = Red, Positive = Green, Zero = Black

  if field_value == 0
    return $0000  ' Black

  intensity := ||field_value
  intensity := intensity #> 0 <# 31  ' Clamp to 5-bit

  if field_value < 0
    color := intensity << 11  ' Red gradient
  else
    color := intensity << 6   ' Green gradient
```

### Real-Time Update Sequence
1. Read 64 sensors from magnetic tile
2. Convert to 8×8 color values
3. Scale to 128×128 display (16× interpolation)
4. Send to display using block transfer
5. Target: 30 fps minimum

### Display Zones
```
Display Layout (128×128):
+------------------+
|  Magnetic Field  |  (0,0) to (127,95)
|   Visualization  |  Main 8×8 grid scaled
+------------------+
| Status/Info Bar  |  (0,96) to (127,127)
|                  |  Frame rate, sensitivity
+------------------+
```

## Error Handling

### Communication Failures
- Check CS, DC, RST signal integrity
- Verify SPI clock and data timing
- Implement timeout on transfers
- Add retry mechanism for initialization

### Display Issues
| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| No display | Power/Reset issue | Check VCC, reset sequence |
| Garbled display | SPI timing | Reduce clock speed |
| Wrong colors | Data format | Verify RGB565 encoding |
| Partial display | Address range | Check column/row settings |

## Debug Interface

### P2 Debug Output
```spin2
PUB debug_spi_transfer(cmd, data)
  debug("SSD1351: CMD=$", hex(cmd), " DATA=$", hex(data))

PUB verify_display_ready() : ready
  ' Read status (if supported by hardware)
  ' Return true if display initialized
```

## References
- SSD1351 Datasheet: Controller specifications
- Waveshare Wiki: Module-specific details
- P2 Smart Pin Documentation: Hardware SPI configuration