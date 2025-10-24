# Automated Test Runner - Usage Guide

## Overview

The `run-test.sh` script automates the P2 test workflow:
1. Compiles your Spin2 program
2. Downloads to P2 and runs in background
3. Monitors log output in real-time
4. Auto-exits when test completes or timeout expires
5. Clean shutdown

## Basic Usage

```bash
./run-test.sh <program.spin2> [timeout_seconds] [end_marker]
```

## Examples

### Auto-exit on END_SESSION marker (recommended)
```bash
./run-test.sh test_tile_sensor_adc.spin2 60 "END_SESSION"
```
- Runs test
- Auto-exits when "END_SESSION" appears in debug output
- Falls back to 60-second timeout if marker not found

### Timeout only
```bash
./run-test.sh test_oled_minimal.spin2 30
```
- Runs for 30 seconds then auto-exits

### Manual exit (infinite)
```bash
./run-test.sh test_grid_8x8.spin2
```
- Runs until you press Ctrl-C
- No timeout

## How END_SESSION Works

For automated tests, add this to your Spin2 code when tests finish:

```spin2
debug("END_SESSION")  ' Script detects this and auto-exits
```

### Example Test Structure

```spin2
PUB main()
    debug("Starting tests...")

    ' Test 1: Quick validation
    test_something()

    ' Test 2: More validation
    test_something_else()

    ' Automated tests done
    debug("END_SESSION")  ' Script stops here

    ' Optional: Interactive testing (won't run in automated mode)
    repeat
        show_live_data()
        waitms(100)
```

## Features

✅ **Auto-compile** - Runs pnut_ts with -d flag
✅ **Auto-detect PropPlug** - Finds first available device
✅ **Real-time monitoring** - Live log output with colors
✅ **Smart exit** - Marker detection OR timeout OR Ctrl-C
✅ **Clean shutdown** - Proper SIGTERM to pnut-term-ts
✅ **Error handling** - Compilation failures, missing files, etc.

## Output Colors

- 🔵 **Blue** - Info messages (compiling, monitoring)
- 🟢 **Green** - Success (compilation, test completion)
- 🟡 **Yellow** - Warnings (timeout, user abort)
- 🔴 **Red** - Errors (compilation failed, file not found)

## Workflow Integration

### Quick Test Cycle
```bash
# Edit code in editor
vim src/test_tile_sensor_adc.spin2

# Run automated test
./run-test.sh test_tile_sensor_adc.spin2 30 "END_SESSION"

# Check results, repeat
```

### Continuous Integration
```bash
#!/bin/bash
# Run all tests in sequence
./run-test.sh test_tile_sensor_adc.spin2 60 "END_SESSION" || exit 1
./run-test.sh test_tile_sensor_scan.spin2 90 "END_SESSION" || exit 1
./run-test.sh test_tile_sensor_stability.spin2 300 "END_SESSION" || exit 1

echo "All tests passed!"
```

## Troubleshooting

### "No PropPlug detected"
```bash
# Check connections
pnut-term-ts -n

# Should show:
# P2 device found on port: /dev/cu.usbserial-P9cektn7 (P9cektn7)
```

### "Compilation failed"
- Check syntax errors in your Spin2 code
- Script will show pnut_ts error output

### "No log file created"
- pnut-term-ts may have failed to start
- Check PropPlug connection
- Try running pnut-term-ts manually

### Script hangs forever
- Make sure your test outputs "END_SESSION" when done
- Or specify a timeout value
- Press Ctrl-C to abort

## Advanced: Multiple Tests

Create a test suite:

```bash
#!/bin/bash
# test-suite.sh

TESTS=(
    "test_tile_sensor_adc.spin2:30:END_SESSION"
    "test_tile_sensor_scan.spin2:60:END_SESSION"
    "test_oled_minimal.spin2:20:TEST_COMPLETE"
)

for test_spec in "${TESTS[@]}"; do
    IFS=':' read -r program timeout marker <<< "$test_spec"
    echo "Running $program..."

    if ! ./run-test.sh "$program" "$timeout" "$marker"; then
        echo "FAIL: $program"
        exit 1
    fi

    echo "PASS: $program"
    sleep 2  # Brief pause between tests
done

echo "All tests passed!"
```

## Tips

1. **Always use END_SESSION** for automated tests - faster than waiting for timeout
2. **Set timeout as safety net** - prevents infinite hangs
3. **Keep tests focused** - One test program per feature
4. **Use descriptive markers** - "TEST_1_COMPLETE", "CALIBRATION_DONE", etc.
5. **Check exit codes** - Script returns 0 on success, non-zero on error

---

*This script is part of the P2 Magnetic Imaging Tile project test infrastructure.*
