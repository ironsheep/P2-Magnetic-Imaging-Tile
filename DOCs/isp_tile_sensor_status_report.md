# isp_tile_sensor.spin2 - Implementation Status Report

**Date**: 2025-01-18
**File**: src/isp_tile_sensor.spin2
**Purpose**: Magnetic Imaging Tile sensor interface with FIFO architecture

---

## Executive Summary

The current implementation has **good overall structure** but contains **critical bugs** that prevent it from functioning. The main issues are:

1. **Broken Smart Pin SPI** - Incorrect pin modes and timing
2. **Non-functional FIFO calls** - Can't call Spin2 methods from PASM this way
3. **Wrong timing calculations** - ADC wait times off by 50×
4. **Missing bit-banged SPI** - No fallback implementation
5. **No error detection** - Can't verify sensor data validity

**Status**: 🔴 Non-functional - requires significant fixes before testing

---

## Detailed Analysis

### ✅ WORKING COMPONENTS

#### 1. Pin Assignment Logic (Lines 107-112)
```spin2
abs_pin_cs := pin_group + PIN_CS      ' Correct
abs_pin_cclk := pin_group + PIN_CCLK  ' Correct
abs_pin_miso := pin_group + PIN_MISO  ' Correct
abs_pin_clrb := pin_group + PIN_CLRB  ' Correct
abs_pin_sclk := pin_group + PIN_SCLK  ' Correct
abs_pin_aout := pin_group + PIN_AOUT  ' Correct
```
**Status**: ✅ Works correctly
**Note**: Pin offsets match hardware documentation

#### 2. Sensor Mapping Arrays (Lines 78-87)
```spin2
subtile_order   BYTE    0, 2, 1, 3           ' Correct anti-crosstalk order
subtile_offset  BYTE    0, 4, 32, 36         ' Correct frame buffer offsets
pixel_order     BYTE    26, 27, 18, 19...    ' Serpentine remapping
```
**Status**: ✅ Matches Arduino reference implementation
**Note**: May need verification with actual hardware

#### 3. Counter Control (Lines 377-391)
```pasm2
reset_sensor_counter
    drvl    clrb_pin                    ' Pulse CLRb low
    waitx   #COUNTER_SETUP_DELAY        ' 50 clocks = 250ns @ 200MHz
    drvh    clrb_pin
    waitx   #COUNTER_SETUP_DELAY
    ret

advance_sensor_counter
    drvh    cclk_pin                    ' Pulse CCLK high
    waitx   #COUNTER_SETUP_DELAY
    drvl    cclk_pin
    waitx   #COUNTER_SETUP_DELAY
    ret
```
**Status**: ✅ Logic appears sound
**Timing**: 50 clocks @ 200MHz = 250ns (well within requirements)

#### 4. Frame Buffer Mapping Logic (Lines 342-360)
**Status**: ✅ Correctly implements subtile ordering and pixel remapping
**Note**: Depends on working ADC read function

#### 5. Public API Methods
- `start()`, `stop()`, `set_acquisition_mode()` ✅
- `get_frame_count()`, `get_error_count()` ✅
- `get_performance_stats()` ✅
- `get_frame_position()` ✅ (useful for debugging)

---

### 🔴 CRITICAL ISSUES

#### 1. Smart Pin SPI Configuration (Lines 232-240)
**BROKEN - CRITICAL**

```spin2
' CURRENT CODE (WRONG):
wrpin(abs_pin_sclk, P_TRANSITION)              ' ❌ Wrong mode!
wxpin(abs_pin_sclk, clkfreq / SPI_CLOCK_FREQ / 2)  ' ❌ Wrong calculation
```

**Problems**:
- `P_TRANSITION` is for single edge transitions, NOT continuous clocking
- Should use `P_NCO_FREQ` mode for clock generation
- Clock period calculation incorrect

**Required Fix**:
```spin2
' CORRECT APPROACH:
' Option 1: Use P_PULSE mode for clock bursts
wrpin(abs_pin_sclk, P_PULSE | P_OE)
wxpin(abs_pin_sclk, period_value)

' Option 2: Bit-bang the clock (more reliable for debugging)
' See fix recommendations below
```

**Impact**: 🔴 ADC will not receive proper clock signals

---

#### 2. PASM ADC Read Function (Lines 393-415)
**BROKEN - CRITICAL**

```pasm2
read_ad7680
    drvl    cs_pin
    waitx   #SENSOR_SETTLE_DELAY        ' ❌ Only 20 clocks = 100ns!

    dirl    miso_pin
    dirh    miso_pin
    wypin   #0, sclk_pin                ' ❌ What does this do?

    waitx   #48                         ' ❌ 240ns, need 8µs!

    rdpin   sensor_value, miso_pin
    shr     sensor_value, #4
    and     sensor_value, ##$FFFF

    drvh    cs_pin
    ret
```

**Problems**:

1. **Timing Disaster**:
   - Line 397: `waitx #SENSOR_SETTLE_DELAY` = 20 clocks = **100ns**
   - **Need: 2µs (2000ns)** for analog settling
   - **Off by 20×!**

2. **SPI Clock Missing**:
   - Line 405: `waitx #48` = 48 clocks = **240ns** @ 200MHz
   - **Need: 8µs** for 20 SPI clock cycles @ 2.5MHz
   - **Off by 33×!**
   - No actual clock generation visible!

3. **Smart Pin Confusion**:
   - `wypin #0, sclk_pin` - unclear what this does
   - No visible clock edge generation
   - MISO smart pin may not be clocking data in

**Required Fix**: Complete rewrite needed (see recommendations)

---

#### 3. FIFO Interface Calls (Lines 301-316)
**BROKEN - CRITICAL**

```pasm2
get_frame_buffer
    mov     temp, ##fifo.getNextFrame   ' ❌ Can't call Spin2 from PASM!
    call    temp                        ' ❌ This won't work!
    mov     frame_ptr, temp
    ret

commit_frame_buffer
    mov     temp, #fifo.FIFO_SENSOR     ' ❌ Invalid syntax
    mov     temp2, frame_ptr
    mov     temp3, ##fifo.commitFrame   ' ❌ Can't call Spin2!
    call    temp3                       ' ❌ This won't work!
    ret
```

**Problems**:
- Can't directly call Spin2 methods from PASM
- Need to use `callpa`/`callpb` to invoke hub exec
- Or restructure to use direct memory access
- These calls will crash or return garbage

**Options**:
1. **Use simple frame buffer** - Allocate fixed buffer, bypass FIFO for now
2. **Hub exec interface** - Proper Spin2 method calling from PASM
3. **Direct memory** - Access FIFO structures directly (complex)

**Impact**: 🔴 Cannot acquire frames, system non-functional

---

#### 4. Variable Offset Error (Line 261)
**BUG - HIGH**

```pasm2
' CURRENT CODE (WRONG):
mov     acq_mode_ptr, param_ptr
add     acq_mode_ptr, #12        ' ❌ Wrong offset!
```

**VAR section layout**:
```spin2
LONG    cog_id              ' Offset 0
LONG    pin_group           ' Offset 4
LONG    frame_count         ' Offset 8
LONG    error_count         ' Offset 12
LONG    acquisition_mode    ' Offset 16  ← Should be #16!
```

**Fix**:
```pasm2
add     acq_mode_ptr, #16        ' Correct offset
```

**Impact**: 🔴 Reading wrong memory location for mode

---

### ⚠️ MISSING FEATURES

#### 1. Bit-Banged SPI Alternative
**Status**: ⚠️ Not implemented

**Need**: Alternative SPI implementation for:
- Debugging Smart Pin issues
- Guaranteed timing control
- Fallback option

**Priority**: 🔴 CRITICAL for initial testing

---

#### 2. Error Detection
**Status**: ⚠️ Not implemented

**Need**:
- ADC value validation (not stuck at 0 or max)
- Frame timing measurement
- Per-frame error flags
- Error statistics tracking

**Priority**: 🔴 HIGH - needed for Goal 2

---

#### 3. Test Mode / Main Cog Operation
**Status**: ⚠️ Not implemented

**Need**:
- Ability to run acquisition in main cog for debugging
- Single sensor test method
- Direct value readout without FIFO

**Priority**: 🔴 CRITICAL for initial testing

---

#### 4. Calibration Framework
**Status**: ⚠️ Not implemented

**Need**:
- Baseline measurement storage
- Background subtraction
- Sensor characterization data

**Priority**: 🟡 MEDIUM - Phase 3

---

## Timing Analysis

### Current vs. Required Timing

| Operation | Current | Required | Status |
|-----------|---------|----------|--------|
| Sensor settle | 100ns | 2,000ns | ❌ 20× too fast |
| ADC conversion wait | 240ns | 8,000ns | ❌ 33× too fast |
| Counter pulse | 250ns | 200ns | ✅ OK |
| Total per sensor | ~500ns | ~10,000ns | ❌ 20× too fast |

**Consequence**: Code will read garbage data, ADC won't have time to convert

---

## Required Fixes - Priority Order

### 🔴 CRITICAL - Must Fix for Basic Operation

1. **Fix ADC read timing** (src/isp_tile_sensor.spin2:393-415)
   - Increase SENSOR_SETTLE_DELAY from 20 to 400 clocks (2µs)
   - Fix SPI clock generation
   - Proper 20-bit transfer implementation

2. **Implement bit-banged SPI** (new function)
   - Manual clock generation with waitx
   - Bit-by-bit data read from MISO
   - Known-good timing

3. **Fix FIFO interface** (src/isp_tile_sensor.spin2:301-316)
   - Temporary: Use fixed frame buffer
   - Later: Proper hub exec calls

4. **Fix variable offset** (src/isp_tile_sensor.spin2:261)
   - Change #12 to #16

5. **Add test mode methods**
   - `read_single_sensor()` - Main cog test
   - `read_raw_frame()` - Main cog 64-sensor scan
   - Bypass FIFO for initial testing

### 🟡 HIGH - Needed for Reliability

6. **Add error detection**
   - Value range checking
   - Frame timing measurement
   - Error counting

7. **Smart Pin SPI fix** (if we want to use it)
   - Correct P_NCO_FREQ mode
   - Proper clock period calculation
   - Verification against bit-bang

### 🟢 MEDIUM - Needed for Production

8. **Calibration framework**
9. **Performance optimization**
10. **Full FIFO integration**

---

## Recommended Approach

### Phase 1: Get ANY reading working
1. Implement bit-banged SPI in main cog (not PASM yet)
2. Test single sensor read
3. Verify reasonable values

### Phase 2: Full scan working
1. Add bit-banged SPI to PASM
2. Implement 64-sensor scan with fixed buffer
3. Verify all sensors respond

### Phase 3: Production features
1. Fix Smart Pin SPI (optional)
2. Integrate with FIFO
3. Add error detection
4. Separate cog operation

---

## Code Quality Assessment

| Aspect | Rating | Notes |
|--------|--------|-------|
| Structure | ⭐⭐⭐⭐ | Well organized, good separation |
| Documentation | ⭐⭐⭐⭐ | Excellent comments |
| API Design | ⭐⭐⭐⭐ | Clean, intuitive |
| PASM Logic | ⭐⭐⭐ | Good flow, needs fixes |
| Timing | ⭐ | Critical errors |
| Error Handling | ⭐ | Non-existent |
| Testability | ⭐ | No test hooks |

**Overall**: 🟡 Good foundation, critical bugs prevent operation

---

## Next Steps

1. ✅ **Create this status report** (DONE)
2. 🔴 **Implement bit-banged SPI read** (Next)
3. 🔴 **Add main cog test methods**
4. 🔴 **Fix timing constants**
5. 🔴 **Fix variable offset**
6. 🟡 **Create test program** (`test_tile_sensor_adc.spin2`)

---

## Files to Create

```
src/isp_tile_sensor.spin2              ← Fix this (main implementation)
src/test_tile_sensor_adc.spin2         ← NEW: Single sensor test
src/test_tile_sensor_scan.spin2        ← NEW: Full scan test
src/test_tile_sensor_stability.spin2   ← NEW: Long-run test
```

---

## Conclusion

The implementation has **excellent structure** and **good documentation**, but contains **critical timing and interface bugs** that prevent any operation. The FIFO interface is non-functional, the ADC timing is off by 20-30×, and there's no way to test individual components.

**Immediate action**: Implement bit-banged SPI and add test methods to get ANY sensor reading working.

**Estimated effort to minimal operation**: 2-3 hours of focused work on ADC interface.

---

*Report generated during Phase 1, Goal 1 analysis*
