# Compiler Listing Enhancement Proposal

## Problem Statement

When debugging memory corruption issues in multi-COG P2 applications, developers need to correlate runtime memory addresses with compiled symbol locations. The current listing file output includes:
- CON constants with values
- OBJ references with indices
- PUB/PRI method references
- VAR offsets (for top-level object only)
- Hex dump of compiled binary

**Missing:** DAT section symbol information, which is critical for debugging memory corruption in singleton objects, FIFO managers, shared buffers, and other DAT-based data structures.

## Proposed Enhancements

### 1. DAT Section Symbol Table (High Priority)

For each object, emit a table of DAT section symbols with their offsets and sizes:

```
=== DAT Section: isp_frame_fifo_manager (Object 0) ===
Offset    Size      Type      Name
------    ----      ----      ----
0x0000    4096      BYTE[]    framePool
0x1000    128       LONG[]    freeList
0x1080    4         LONG      freeHead
0x1084    4         LONG      freeTail
0x1088    4         LONG      freeCount
0x108C    64        LONG[]    sensorFIFO
0x10CC    4         LONG      sensorHead
0x10D0    4         LONG      sensorTail
0x10D4    4         LONG      sensorCount
0x10D8    64        LONG[]    hdmiFIFO
0x1118    4         LONG      hdmiHead
...
Total DAT size: 4468 bytes
```

**Why this matters:** When a debug message shows `sensorHead = 1,357,860,489` (corrupt value) at runtime address `$5CCC`, developers can:
1. Calculate the expected offset: `$5CCC - object_base`
2. Verify it matches `sensorHead`'s offset (0x10CC)
3. Identify adjacent symbols that might be overwriting it

### 2. Object Memory Layout Summary (Medium Priority)

Provide a consolidated view of how objects are arranged:

```
=== Object Memory Layout ===
Index  Object Name                    Code Size  DAT Size   VAR Size
-----  -----------                    ---------  --------   --------
0      isp_frame_fifo_manager         892        4468       0
1      isp_hdmi_display_engine        1456       264        296
2      isp_oled_single_cog            2104       268        312
3      isp_tile_sensor                1844       408        152
...

Total: OBJ=23368  VAR=50180
```

**Why this matters:** Helps identify which object's data is near a corrupted address, and whether buffer overruns from one object could affect another.

### 3. VAR Section Symbols for All Objects (Medium Priority)

Extend VAR symbol listing to child objects (currently only top-level):

```
=== VAR Section: isp_hdmi_display_engine (Object 1) ===
Offset    Size      Type      Name
------    ----      ----      ----
0x0000    4         LONG      cog_id
0x0004    4         LONG      frame_count
0x0008    4         LONG      display_mode
0x000C    32        LONG[]    color_palette
0x002C    4         LONG      current_frame_ptr
...
```

### 4. Runtime Base Addresses (Medium Priority)

If determinable at compile time, show where each object's sections will be placed at runtime:

```
=== Runtime Address Map ===
Object 0 (isp_frame_fifo_manager):
  DAT base: $0CD0   DAT end: $1D98   (size: 4468)
  VAR base: N/A     VAR end: N/A     (size: 0)

Object 1 (isp_hdmi_display_engine):
  DAT base: $1D98   DAT end: $1EA0   (size: 264)
  VAR base: $5B50   VAR end: $5C78   (size: 296)
...
```

**Why this matters:** Allows direct correlation between runtime debug output addresses and object data without manual calculation.

### 5. PASM Label Offsets Within DAT (Low Priority)

For inline PASM code in DAT sections, show label offsets:

```
=== PASM Labels: isp_tile_sensor (Object 3) ===
DAT Offset   COG Addr   Name
----------   --------   ----
0x0100       $000       .main_start
0x0124       $009       .store_sensor_value
0x0168       $01A       .advance_subtile
0x0180       $020       .pipelined_loop
```

### 6. Cross-Reference: Address to Symbol Lookup (Low Priority)

An optional reverse lookup table for quick address-to-symbol mapping:

```
=== Address Cross-Reference ===
$0CD0-$1CD0   framePool (Object 0, DAT)
$1CD0-$1D50   freeList (Object 0, DAT)
$1D50-$1D54   freeHead (Object 0, DAT)
$1D54-$1D58   freeTail (Object 0, DAT)
...
```

**Why this matters:** When you see a corrupt pointer like `$1D52`, you can immediately identify it points into `freeHead`.

## Implementation Suggestions

### Minimal Implementation (Highest Value, Lowest Effort)

Just add DAT symbol offsets to the existing symbol table output, following the current format:

```
TYPE: DAT_BYTE_ARRAY    OFFSET: 00000000  SIZE: 00001000  NAME: FRAMEPOOL,01
TYPE: DAT_LONG_ARRAY    OFFSET: 00001000  SIZE: 00000080  NAME: FREELIST,01
TYPE: DAT_LONG          OFFSET: 00001080  SIZE: 00000004  NAME: FREEHEAD,01
TYPE: DAT_LONG          OFFSET: 00001084  SIZE: 00000004  NAME: FREETAIL,01
TYPE: DAT_LONG          OFFSET: 00001088  SIZE: 00000004  NAME: FREECOUNT,01
TYPE: DAT_LONG_ARRAY    OFFSET: 0000108C  SIZE: 00000040  NAME: SENSORFIFO,01
TYPE: DAT_LONG          OFFSET: 000010CC  SIZE: 00000004  NAME: SENSORHEAD,01
TYPE: DAT_LONG          OFFSET: 000010D0  SIZE: 00000004  NAME: SENSORTAIL,01
TYPE: DAT_LONG          OFFSET: 000010D4  SIZE: 00000004  NAME: SENSORCOUNT,01
...
```

This follows the existing `TYPE: xxx  VALUE: xxx  NAME: xxx` format and would be:
- Straightforward to implement (data is already available during compilation)
- Easy to parse programmatically
- Consistent with existing listing format
- Immediately useful for debugging

### Full Implementation

Add new listing sections with formatted tables as shown above, emitted after the existing symbol table but before the hex dump. Sections could be enabled/disabled via compiler flags:

```
pnut_ts -l -Ldat -Lvar -Lmap source.spin2
```

Where:
- `-Ldat` enables DAT section symbol tables
- `-Lvar` enables VAR section symbols for all objects
- `-Lmap` enables runtime address map

## Use Case Example

**Scenario:** Debugging shows `sensorHead` contains garbage value `0x50ED5E89` instead of expected index `0-15`.

**With current listing:** Developer cannot determine where `sensorHead` lives in memory or what's adjacent to it.

**With enhanced listing:** Developer sees:
```
=== DAT Section: isp_frame_fifo_manager (Object 0) ===
Offset    Size      Type      Name
------    ----      ----      ----
...
0x1088    4         LONG      freeCount
0x108C    64        LONG[]    sensorFIFO      <-- 16 LONGs ending at 0x10CB
0x10CC    4         LONG      sensorHead      <-- offset 0x10CC
0x10D0    4         LONG      sensorTail
...
```

Combined with runtime debug showing `@sensorHead = $5CCC`, developer can:
1. Confirm `$5CCC` is the correct address (base + 0x10CC)
2. See that `sensorFIFO[15]` ends at offset 0x10C8 (the LONG at 0x10C8-0x10CB), just before `sensorHead`
3. Suspect an array bounds overflow if `sensorFIFO` index exceeds 15
4. Check if `LONG[@sensorFIFO][16]` would write to `sensorHead`'s location

## Summary

| Enhancement | Priority | Complexity | Debugging Value |
|-------------|----------|------------|-----------------|
| DAT symbol offsets | High | Low | Critical for memory corruption |
| Object layout summary | Medium | Low | Helpful for multi-object issues |
| VAR symbols for all objects | Medium | Medium | Useful for VAR corruption |
| Runtime base addresses | Medium | Medium | Direct address correlation |
| PASM label offsets | Low | Medium | Useful for PASM debugging |
| Address cross-reference | Low | Medium | Quick reverse lookup |

The DAT symbol offset enhancement alone would significantly improve debugging capabilities for complex multi-COG applications with shared data structures. The minimal implementation (extending existing TYPE/VALUE/NAME format) provides maximum value with minimum implementation effort.
