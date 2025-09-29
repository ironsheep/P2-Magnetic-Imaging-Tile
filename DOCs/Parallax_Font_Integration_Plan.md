# Parallax Font Integration Plan

## Overview
Integrate the Parallax TrueType font into the P2 Magnetic Imaging Tile display system for professional text rendering on the 24-bit HDMI output.

## Implementation Steps

### 1. Locate the Parallax TrueType Font File
- Find the official Parallax TTF font file
- Document font characteristics (style, weight, features)

### 2. Convert TTF to Bitmap Data
- Use LVGL Font Converter (https://lvgl.io/tools/fontconverter)
- Recommended settings:
  - Size: 16, 24, or 32 pixels for readability
  - BPP: 4 or 8 for anti-aliasing on 24-bit display
  - Character range: Basic Latin (0x20-0x7F) for ASCII
- Alternative: TTF2BMH for memory-efficient monochrome bitmaps

### 3. Prepare Binary Font Data
- Extract bitmap arrays from C header output
- Save as .bin file for direct inclusion in Spin2

### 4. Create Spin2 Font Structure
```spin2
DAT
' Font metadata
font_width      long    16
font_height     long    24
font_bpp        long    4   ' 4-bit anti-aliasing
font_first_char long    32  ' space character
font_last_char  long    126 ' tilde character

' Include bitmap data using FILE operator
font_data       FILE    "parallax_font_24pt.bin"
```

### 5. Implement Font Rendering Routines
- Create character drawing function with anti-aliasing support
- Implement text string rendering
- Add color blending for smooth edges on 24-bit display
- Support for transparent background rendering

### 6. Integration with Display System
- Integrate font renderer with existing HDMI display driver
- Coordinate with magnetic field visualization rendering
- Ensure proper layering of text over graphics

### 7. Add Display Features
- Text overlays for sensor values (magnetic field strength)
- Status information display:
  - Frame rate indicator
  - Sensitivity mode (normal/10x amplified)
  - Calibration status
- Coordinate grid labels for 8x8 sensor array
- Title and mode indicators

### 8. Testing and Optimization
- Test multiple font sizes (16pt, 24pt, 32pt)
- Verify anti-aliasing quality at different BPP settings
- Performance testing with real-time display updates
- Memory usage optimization if needed

## Technical Considerations

### Memory Management
- Font data can reside in HUB RAM or PSRAM
- Consider caching frequently used rendered text
- Selective character set loading to minimize memory usage

### Rendering Performance
- Pre-render static text elements
- Use dedicated COG for text rendering if needed
- Optimize blending algorithms for real-time updates

### Display Quality
- Anti-aliased fonts (4-8 bpp) for professional appearance
- Proper color blending with background
- Consistent spacing and alignment

## Tools and Resources

### Conversion Tools
- **LVGL Font Converter**: Best for quality, supports anti-aliasing
- **TTF2BMH**: Memory efficient, monochrome output
- **Font2Bitmap**: Browser-based alternative

### Workflow
1. TTF → Font Converter → C Array
2. C Array → Binary extraction → .bin file
3. .bin file → Spin2 FILE inclusion → DAT section
4. DAT section → Rendering routines → HDMI display

## Expected Outcomes
- Professional Parallax branding on displays
- Clear, readable sensor data overlays
- Polished user interface for magnetic field visualization
- Consistent visual design across all display modes