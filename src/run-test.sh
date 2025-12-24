#!/bin/bash
#
# run-test.sh - Compile and run P2 test with automatic timeout or end-of-test detection
#
# Usage: ./run-test.sh <base_name> <timeout_seconds> [end_pattern]
#
# Parameters:
#   base_name       - Base name of source file (without .spin2 extension)
#   timeout_seconds - Maximum time to run before automatic shutdown
#   end_pattern     - Optional regex pattern that signals end of test (default: "TEST COMPLETE")
#
# Examples:
#   ./run-test.sh mag_tile_viewer 30
#   ./run-test.sh test_fifo_regression 10 "All tests passed"
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default end-of-test pattern
DEFAULT_END_PATTERN="END_SEQUENCE"

# PropPlug serial number (change if different)
PROPPLUG_SERIAL="P9cektn7"

# Parse arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo "Usage: $0 <base_name> <timeout_seconds> [end_pattern]"
    echo ""
    echo "Parameters:"
    echo "  base_name       - Base name of source file (without .spin2 extension)"
    echo "  timeout_seconds - Maximum time to run before automatic shutdown"
    echo "  end_pattern     - Optional regex pattern that signals end of test"
    exit 1
fi

BASE_NAME="$1"
TIMEOUT_SECONDS="$2"
END_PATTERN="${3:-$DEFAULT_END_PATTERN}"

SOURCE_FILE="${BASE_NAME}.spin2"
BIN_FILE="${BASE_NAME}.bin"

echo -e "${YELLOW}=== P2 Test Runner ===${NC}"
echo "Source file:  $SOURCE_FILE"
echo "Timeout:      $TIMEOUT_SECONDS seconds"
echo "End pattern:  '$END_PATTERN'"
echo ""

# Step 1: Validate source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo -e "${RED}Error: Source file '$SOURCE_FILE' not found${NC}"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Source file exists"

# Step 2: Compile with debug flag
echo ""
echo -e "${YELLOW}Compiling...${NC}"
if ! pnut_ts -d "$SOURCE_FILE" 2>&1; then
    echo -e "${RED}Error: Compilation failed${NC}"
    exit 1
fi

# Verify bin file was created
if [ ! -f "$BIN_FILE" ]; then
    echo -e "${RED}Error: Binary file '$BIN_FILE' was not created${NC}"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Compilation successful"

# Step 3: Run pnut-term-ts with timeout and pattern detection
echo ""
echo -e "${YELLOW}Starting test (timeout: ${TIMEOUT_SECONDS}s)...${NC}"
echo "Press Ctrl+C to abort manually"
echo "---"

# Start pnut-term-ts in background
pnut-term-ts -u -r "$BIN_FILE" -p "$PROPPLUG_SERIAL" > /dev/null 2>&1 &
PNUT_PID=$!

# Monitor for timeout or end pattern (check log files)
START_TIME=$(date +%s)
TEST_RESULT="timeout"

# Get initial log file list to detect new logs
INITIAL_LOGS=$(ls logs/debug_*.log 2>/dev/null | sort)

while true; do
    # Check if pnut-term-ts is still running
    if ! kill -0 $PNUT_PID 2>/dev/null; then
        TEST_RESULT="process_ended"
        break
    fi

    # Find the newest log file created after we started
    CURRENT_LOG=$(ls -t logs/debug_*.log 2>/dev/null | head -1)

    # Check for end pattern in the current log file
    if [ -n "$CURRENT_LOG" ] && grep -q "$END_PATTERN" "$CURRENT_LOG" 2>/dev/null; then
        TEST_RESULT="pattern_matched"
        echo ""
        echo -e "${GREEN}[END PATTERN DETECTED]${NC} '$END_PATTERN'"
        break
    fi

    # Check for timeout
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
        TEST_RESULT="timeout"
        echo ""
        echo -e "${YELLOW}[TIMEOUT]${NC} ${TIMEOUT_SECONDS} seconds elapsed"
        break
    fi

    # Small sleep to avoid busy-waiting
    sleep 0.5
done

# Clean shutdown of pnut-term-ts
if kill -0 $PNUT_PID 2>/dev/null; then
    echo ""
    echo "Stopping pnut-term-ts..."
    kill -TERM $PNUT_PID 2>/dev/null
    sleep 1
    # Force kill if still running
    if kill -0 $PNUT_PID 2>/dev/null; then
        kill -9 $PNUT_PID 2>/dev/null
    fi
fi

# Wait for process to fully terminate
wait $PNUT_PID 2>/dev/null

echo "---"
echo ""
echo -e "${YELLOW}=== Test Complete ===${NC}"
echo "Result: $TEST_RESULT"

# Find the most recent log file
LATEST_LOG=$(ls -t logs/debug_*.log 2>/dev/null | head -1)
if [ -n "$LATEST_LOG" ]; then
    echo "Log file: $LATEST_LOG"
fi

exit 0
