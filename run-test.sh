#!/bin/bash
# =================================================================================================
#   File....... run-test.sh
#   Purpose.... Automated P2 test execution with smart log monitoring
#   Author..... Stephen M Moraco (with Claude Code assistance)
#   Started.... Jan 2025
#
#   USAGE:
#     ./run-test.sh <program.spin2> [timeout_seconds] [end_marker]
#
#   EXAMPLES:
#     ./run-test.sh test_tile_sensor_adc.spin2 30
#     ./run-test.sh test_tile_sensor_adc.spin2 60 "END_SESSION"
#     ./run-test.sh test_oled_minimal.spin2 10 "TEST_COMPLETE"
#
#   BEHAVIOR:
#     1. Compiles the program with pnut_ts -d
#     2. Downloads and runs in background with pnut-term-ts
#     3. Monitors log file for output
#     4. Exits when:
#        - End marker string detected in log (if specified)
#        - Timeout expires (if specified)
#        - User presses Ctrl-C
#     5. Clean shutdown of terminal session
#
# =================================================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default parameters
PROGRAM=""
TIMEOUT=0           # 0 = infinite
END_MARKER=""
PROPPLUG=""

# Parse arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}ERROR: Program name required${NC}"
    echo "Usage: $0 <program.spin2> [timeout_seconds] [end_marker]"
    echo ""
    echo "Examples:"
    echo "  $0 test_tile_sensor_adc.spin2 30"
    echo "  $0 test_tile_sensor_adc.spin2 60 \"END_SESSION\""
    exit 1
fi

PROGRAM=$1
TIMEOUT=${2:-0}
END_MARKER=${3:-""}

# Validate program file exists
if [ ! -f "src/$PROGRAM" ]; then
    echo -e "${RED}ERROR: File not found: src/$PROGRAM${NC}"
    exit 1
fi

# Get PropPlug ID (use first available)
echo -e "${BLUE}Detecting PropPlug...${NC}"
# Extract the ID from format: "USB #1 [/dev/tty.usbserial-P6yh4spg]"
PROPPLUG=$(pnut-term-ts -n 2>/dev/null | grep "USB #" | head -1 | sed -n 's/.*usbserial-\([^]]*\).*/\1/p')

if [ -z "$PROPPLUG" ]; then
    echo -e "${RED}ERROR: No PropPlug detected${NC}"
    echo "Run: pnut-term-ts -n"
    exit 1
fi

echo -e "${GREEN}Found PropPlug: $PROPPLUG${NC}"
echo ""

# Compile program
echo -e "${BLUE}Compiling $PROGRAM...${NC}"
cd src
if ! pnut_ts -d "$PROGRAM"; then
    echo -e "${RED}Compilation failed${NC}"
    cd ..
    exit 1
fi
cd ..

BINARY="src/${PROGRAM%.spin2}.bin"
if [ ! -f "$BINARY" ]; then
    echo -e "${RED}ERROR: Binary not created: $BINARY${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Compilation successful${NC}"
echo ""

# Start pnut-term-ts in background
echo -e "${BLUE}Starting download and execution...${NC}"
pnut-term-ts -r "$BINARY" -p "$PROPPLUG" &
PNUT_PID=$!

# Give it time to start and create log file
sleep 2

# Find the latest log file
LOGFILE=$(ls -t1 logs/*.log 2>/dev/null | head -1)

if [ -z "$LOGFILE" ]; then
    echo -e "${RED}ERROR: No log file created${NC}"
    kill -TERM $PNUT_PID 2>/dev/null
    exit 1
fi

echo -e "${GREEN}Log file: $LOGFILE${NC}"
echo -e "${BLUE}Monitoring output...${NC}"
echo -e "${YELLOW}(Ctrl-C to abort)${NC}"
echo ""
echo "================================================================"

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "================================================================"
    echo -e "${BLUE}Shutting down...${NC}"
    kill -TERM $PNUT_PID 2>/dev/null || true
    wait $PNUT_PID 2>/dev/null || true
    echo -e "${GREEN}Test session ended${NC}"
}

trap cleanup EXIT INT TERM

# Monitor log file with timeout and end marker detection
START_TIME=$(date +%s)
MARKER_FOUND=0

tail -f "$LOGFILE" 2>/dev/null | while IFS= read -r line; do
    echo "$line"

    # Check for end marker
    if [ -n "$END_MARKER" ]; then
        if echo "$line" | grep -q "$END_MARKER"; then
            echo ""
            echo -e "${GREEN}✓ End marker detected: $END_MARKER${NC}"
            MARKER_FOUND=1
            kill -TERM $PNUT_PID 2>/dev/null || true
            break
        fi
    fi

    # Check for timeout
    if [ $TIMEOUT -gt 0 ]; then
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))

        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo ""
            echo -e "${YELLOW}⏱  Timeout reached ($TIMEOUT seconds)${NC}"
            kill -TERM $PNUT_PID 2>/dev/null || true
            break
        fi
    fi
done

# Wait a moment for clean shutdown
sleep 1

exit 0
