#!/usr/bin/env python3
"""
Sensor Log Analyzer - Parse debug logs and generate heatmap summaries
Extracts sensor readings and displays them as ASCII heatmaps.

Usage:
    python3 analyze_sensor_log.py <logfile> [--threshold 30000] [--frames N]
"""

import sys
import re
from collections import defaultdict
from datetime import datetime

# ANSI color codes for terminal heatmap
COLORS = {
    'reset': '\033[0m',
    'black': '\033[40m',
    'red': '\033[41m',
    'green': '\033[42m',
    'yellow': '\033[43m',
    'blue': '\033[44m',
    'magenta': '\033[45m',
    'cyan': '\033[46m',
    'white': '\033[47m',
    'bright_red': '\033[101m',
    'bright_green': '\033[102m',
}

def value_to_char(value, threshold=30000):
    """Convert sensor value to ASCII character for heatmap"""
    if value < 20000:
        return '.'  # Below baseline
    elif value < 25000:
        return '-'  # Low
    elif value < threshold:
        return 'o'  # Medium
    elif value < 35000:
        return 'O'  # Elevated
    elif value < 40000:
        return '#'  # High
    else:
        return '@'  # Very high (magnet detected)

def value_to_color(value, threshold=30000):
    """Convert sensor value to ANSI color code"""
    if value < 20000:
        return COLORS['black']
    elif value < 25000:
        return COLORS['blue']
    elif value < threshold:
        return COLORS['cyan']
    elif value < 35000:
        return COLORS['yellow']
    elif value < 40000:
        return COLORS['red']
    else:
        return COLORS['bright_red']

def parse_log_file(filename, threshold=30000, max_frames=None):
    """Parse log file and extract frames with sensor data"""
    frames = []
    current_frame = {}
    current_row = 0
    frame_time = None

    # Pattern to match sensor value lines
    # Format: WORD[framePtr][i*8+N] = VALUE
    value_pattern = re.compile(r'WORD\[framePtr\]\[i\*8\+(\d+)\]\s*=\s*([\d_]+)')
    row_pattern = re.compile(r'Row i = (\d+):')
    time_pattern = re.compile(r'\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)\]')
    sensor_data_pattern = re.compile(r'Sensor data')

    with open(filename, 'r') as f:
        for line in f:
            # Extract timestamp
            time_match = time_pattern.search(line)
            if time_match:
                line_time = time_match.group(1)

            # Check for new frame start
            if sensor_data_pattern.search(line):
                # Save previous frame if it has data
                if current_frame and any(current_frame.values()):
                    frames.append({
                        'time': frame_time,
                        'data': dict(current_frame)
                    })
                    if max_frames and len(frames) >= max_frames:
                        break
                # Start new frame
                current_frame = {row: [20000]*8 for row in range(8)}  # Default baseline
                frame_time = line_time if time_match else None
                current_row = 0
                continue

            # Check for row indicator
            row_match = row_pattern.search(line)
            if row_match:
                current_row = int(row_match.group(1))
                continue

            # Check for sensor value
            value_match = value_pattern.search(line)
            if value_match and current_frame:
                col = int(value_match.group(1))
                value_str = value_match.group(2).replace('_', '')
                value = int(value_str)
                if 0 <= current_row < 8 and 0 <= col < 8:
                    current_frame[current_row][col] = value

    # Don't forget the last frame
    if current_frame and any(current_frame.values()):
        frames.append({
            'time': frame_time,
            'data': dict(current_frame)
        })

    return frames

def print_frame_heatmap(frame, threshold=30000, use_color=True):
    """Print a single frame as ASCII heatmap"""
    print(f"\nTime: {frame['time']}")
    print("     Col:  0   1   2   3   4   5   6   7")
    print("         +---+---+---+---+---+---+---+---+")

    data = frame['data']
    for row in range(8):
        row_str = f"Row {row}: |"
        for col in range(8):
            value = data[row][col]
            char = value_to_char(value, threshold)
            if use_color and value >= threshold:
                color = value_to_color(value, threshold)
                row_str += f"{color} {char} {COLORS['reset']}|"
            else:
                row_str += f" {char} |"
        print(row_str)
        print("         +---+---+---+---+---+---+---+---+")

def print_summary(frame, threshold=30000):
    """Print positions of high values (above threshold)"""
    data = frame['data']
    high_values = []
    for row in range(8):
        for col in range(8):
            value = data[row][col]
            if value >= threshold:
                high_values.append((row, col, value))

    if high_values:
        print(f"\nHigh values (>={threshold}):")
        for row, col, value in sorted(high_values, key=lambda x: -x[2]):
            quadrant = "UL" if row < 4 and col < 4 else \
                       "UR" if row < 4 and col >= 4 else \
                       "LL" if row >= 4 and col < 4 else "LR"
            print(f"  Row {row}, Col {col} ({quadrant}): {value:,}")
    else:
        print("\nNo high values detected (baseline frame)")

def analyze_movement(frames, threshold=30000):
    """Analyze magnet movement across frames"""
    print("\n" + "="*60)
    print("MOVEMENT ANALYSIS")
    print("="*60)

    positions = []
    prev_quadrant = None

    for i, frame in enumerate(frames):
        data = frame['data']
        # Find centroid of high values
        total_row = 0
        total_col = 0
        total_weight = 0

        for row in range(8):
            for col in range(8):
                value = data[row][col]
                if value >= threshold:
                    weight = value - threshold
                    total_row += row * weight
                    total_col += col * weight
                    total_weight += weight

        if total_weight > 0:
            centroid_row = total_row / total_weight
            centroid_col = total_col / total_weight

            quadrant = "UL" if centroid_row < 4 and centroid_col < 4 else \
                       "UR" if centroid_row < 4 and centroid_col >= 4 else \
                       "LL" if centroid_row >= 4 and centroid_col < 4 else "LR"

            if quadrant != prev_quadrant:
                print(f"Frame {i+1} ({frame['time']}): Magnet in {quadrant} quadrant (centroid: {centroid_row:.1f}, {centroid_col:.1f})")
                prev_quadrant = quadrant
                positions.append({
                    'frame': i+1,
                    'time': frame['time'],
                    'quadrant': quadrant,
                    'centroid_row': centroid_row,
                    'centroid_col': centroid_col
                })

    return positions

def find_interesting_frames(frames, threshold=30000):
    """Find frames where magnet position changes significantly"""
    interesting = []
    prev_centroid = None

    for i, frame in enumerate(frames):
        data = frame['data']
        # Calculate centroid
        total_row = 0
        total_col = 0
        total_weight = 0
        max_value = 0

        for row in range(8):
            for col in range(8):
                value = data[row][col]
                if value >= threshold:
                    weight = value - threshold
                    total_row += row * weight
                    total_col += col * weight
                    total_weight += weight
                    max_value = max(max_value, value)

        if total_weight > 0:
            centroid = (total_row / total_weight, total_col / total_weight)

            # Check if position changed significantly (more than 1.5 cells)
            if prev_centroid is None or \
               abs(centroid[0] - prev_centroid[0]) > 1.5 or \
               abs(centroid[1] - prev_centroid[1]) > 1.5:
                interesting.append(i)
                prev_centroid = centroid
        elif prev_centroid is not None:
            # Magnet left the tile
            interesting.append(i)
            prev_centroid = None

    return interesting

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_sensor_log.py <logfile> [--threshold N] [--frames N] [--no-color]")
        print("\nOptions:")
        print("  --threshold N  Set threshold for magnet detection (default: 30000)")
        print("  --frames N     Limit to first N frames")
        print("  --no-color     Disable color output")
        print("  --summary      Show only summary, skip individual frames")
        sys.exit(1)

    filename = sys.argv[1]
    threshold = 30000
    max_frames = None
    use_color = True
    summary_only = False

    # Parse arguments
    i = 2
    while i < len(sys.argv):
        if sys.argv[i] == '--threshold' and i+1 < len(sys.argv):
            threshold = int(sys.argv[i+1])
            i += 2
        elif sys.argv[i] == '--frames' and i+1 < len(sys.argv):
            max_frames = int(sys.argv[i+1])
            i += 2
        elif sys.argv[i] == '--no-color':
            use_color = False
            i += 1
        elif sys.argv[i] == '--summary':
            summary_only = True
            i += 1
        else:
            i += 1

    print(f"Parsing {filename}...")
    frames = parse_log_file(filename, threshold, max_frames)
    print(f"Found {len(frames)} frames")

    if not frames:
        print("No sensor data found in log file")
        sys.exit(1)

    # Find frames with significant position changes
    interesting = find_interesting_frames(frames, threshold)

    if summary_only:
        # Just show movement analysis and quadrant summary
        quadrant_summary(frames, threshold)
        analyze_movement(frames, threshold)
    else:
        print(f"\nShowing {len(interesting)} frames with position changes")
        print("Legend: . (baseline) - (low) o (med) O (elevated) # (high) @ (very high)")
        print("="*60)

        for idx in interesting[:20]:  # Limit to 20 interesting frames
            print_frame_heatmap(frames[idx], threshold, use_color)
            print_summary(frames[idx], threshold)

        # Movement summary
        analyze_movement(frames, threshold)

    # Always show quadrant summary
    quadrant_summary(frames, threshold)

    print("\n" + "="*60)
    print("QUADRANT CENTROID VERIFICATION")
    print("="*60)
    print("\nQuadrant boundaries (buffer positions):")
    print("  UL: rows 0-3, cols 0-3  |  UR: rows 0-3, cols 4-7")
    print("  LL: rows 4-7, cols 0-3  |  LR: rows 4-7, cols 4-7")
    print("\nExpected centroid locations when magnet at quadrant center:")
    print("  Physical UL center -> Buffer centroid ~(1.5, 1.5)")
    print("  Physical UR center -> Buffer centroid ~(1.5, 5.5)")
    print("  Physical LR center -> Buffer centroid ~(5.5, 5.5)")
    print("  Physical LL center -> Buffer centroid ~(5.5, 1.5)")

def quadrant_summary(frames, threshold=30000):
    """Summarize which quadrant each significant frame falls into"""
    print("\n" + "="*60)
    print("QUADRANT SUMMARY (per significant frame)")
    print("="*60)
    print("\nFrame | Centroid (row, col) | Quadrant | Cells Lit")
    print("-" * 55)

    for i, frame in enumerate(frames):
        data = frame['data']
        total_row = 0
        total_col = 0
        total_weight = 0
        cell_count = 0

        for row in range(8):
            for col in range(8):
                value = data[row][col]
                if value >= threshold:
                    weight = value - threshold
                    total_row += row * weight
                    total_col += col * weight
                    total_weight += weight
                    cell_count += 1

        if total_weight > 0 and cell_count >= 3:  # Only significant activations
            centroid_row = total_row / total_weight
            centroid_col = total_col / total_weight

            # Determine quadrant from centroid
            if centroid_row < 4 and centroid_col < 4:
                quadrant = "UL"
            elif centroid_row < 4 and centroid_col >= 4:
                quadrant = "UR"
            elif centroid_row >= 4 and centroid_col < 4:
                quadrant = "LL"
            else:
                quadrant = "LR"

            print(f"{i+1:5} | ({centroid_row:4.1f}, {centroid_col:4.1f})       | {quadrant:8} | {cell_count:3}")

if __name__ == '__main__':
    main()
