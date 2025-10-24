#!/usr/bin/env bash
# test-download.sh - Automated P2 download and test script
# Usage: ./test-download.sh <binary_file> [timeout_seconds]

BINARY="${1:-src/test_oled_minimal.bin}"
TIMEOUT="${2:-8}"
DEVICE="P9cektn7"

echo "=== P2 Download Test Script ==="
echo "Binary:  $BINARY"
echo "Device:  $DEVICE"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Kill any existing instances
pkill -9 pnut-term-ts 2>/dev/null || true
killall -9 pnut-term-ts 2>/dev/null || true
sleep 1

# Start download in background
echo "Starting download..."
pnut-term-ts -r "$BINARY" -p "$DEVICE" &
PID=$!
echo "Process PID: $PID"

# Sleep for timeout duration
sleep "${TIMEOUT}"

# Kill the process tree
echo "Timeout reached, killing process..."
kill -TERM $PID 2>/dev/null || true
sleep 0.5
kill -9 $PID 2>/dev/null || true

# Make absolutely sure everything is dead
pkill -9 pnut-term-ts 2>/dev/null || true
killall -9 pnut-term-ts 2>/dev/null || true
sleep 1

echo "Process killed."

# Show the latest log
echo ""
echo "=== Latest Log Output ==="
LATEST_LOG=$(ls -t1 logs/*.log | head -1)
echo "Log file: $LATEST_LOG"
echo ""
cat "$LATEST_LOG"
