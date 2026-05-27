# Object Architecture As-Built
**Magnetic Imaging Tile — what the code actually does, vs. the plan**

**Companion to:** `Object-Architecture-and-Cog-Allocation.md` (v1.1, the *ideal* decomposition)
**Status:** Snapshot of `main` as of 2026-05-26. Numbers cite specific files and lines.

---

## 1. Document purpose

The planning document derives an 8-cog, 13-unit ideal decomposition from requirements. This document records **what we shipped** and **why** the shipped system diverges from that ideal. It is not a critique of the plan: most divergences are deliberate scope cuts, and where they aren't, they are concrete places to circle back to.

Read this doc with the planning doc open. Section numbers loosely parallel its sections so you can compare side-by-side.

---

## 2. The headline differences

| Topic | Plan | As-built | Why |
|---|---|---|---|
| Cogs in use | 8 (all 7 functional units + cog 0 Application) | **6** — Application, Sensor, PSRAM driver, HDMI signal, HDMI renderer, OLED renderer | Two units never built. |
| `SignalProcessor` (U9) | Dedicated cog 6, full-rate consumer | **Not yet built** | DSP is on the product trajectory (a magnetic-field *analyzer* needs filtering / track / FFT, not just rendering). Cog 6 is intentionally reserved. |
| `CommsHandler` (U10) | Dedicated cog 7, UART command parser | **Not yet built** | Status flows through Spin2 `debug()` today; runtime control is on the trajectory. Cog 7 is intentionally reserved. |
| `FrameFifoManager` API | `commitToMultiple(ptr, fifo_mask)` with refcounted shared frames, fan-out + COGATN per consumer | **Per-FIFO `commitFrame(fifoID, ptr)`**, frames are **copied** by main COG, no refcount field exists | Plan's pattern was not implemented; main COG `WORDMOVE`s the frame into a fresh pool slot per consumer FIFO. |
| Decimation | Folded into `FrameFifoManager.commitFrame` (per-FIFO counters) | **A Spin2 stage in cog 0** (`normal_decimation_loop()` in `mag_tile_viewer.spin2:286`) | Plan's "decimation is a property of the bus" never landed; cog 0 hand-routes frames into HDMI/OLED FIFOs. |
| `Application` (U1) | Pure composition root; mode/UI/command parsing punted to U10 | **Composition root + decimator + calibration UI** (349 lines, `mag_tile_viewer.spin2`) | Without U10, the command-ish surface lives here, plus the fan-out stage. |
| `ColorMapper` (U11) | Shared library; both renderers call it | **Duplicated** — `field_to_color()` in HDMI engine, `value_to_color()` + `init_color_lut()` in OLED driver | Same constants (`SENSOR_MID=20500`, `COLOR_RANGE=20500`, `GRAY_BASE=32`) cut-and-pasted into both. Visual coherence (R4) is preserved by convention, not by construction. |
| `SensorTopology` (U12) | Library | **Inlined** in `isp_tile_sensor.spin2` as `unified_sensor_map[64]` BYTE table | Matches Appendix C ("start inlined, promote when needed"). Only one consumer. |
| `FontRenderer` (U13) | Library | **Library** (`isp_hub75_fonts.spin2`), used by `isp_psram_graphics.spin2` only | Matches plan; OLED has no text path so the library remains single-consumer. |
| `PsramBroker` (U4) | Dedicated cog 2, per-cog mailbox protocol | **Matches plan** — `psram_driver.spin2` cog with 8×3-long mailbox at `cmd_list`, polled round-robin | One of the cleanest plan-to-code matches. |
| `PsramGraphics` (U5) | Library with per-cog `start()` that binds a mailbox slot | **Matches plan** — `isp_psram_graphics.spin2:69` does `psram_ptr := psram.pointer() + cogid() * 12` | Per-cog mailbox handle lives in VAR exactly as specified. |
| `HdmiSignalGenerator` (U6) | Dedicated cog, owns P0–P7, streams from PSRAM | **Matches plan** — `isp_hdmi_640x480_24bpp.spin2`, PASM-only, COGEXEC_NEW | One-to-one match. |
| `HdmiRenderer` (U7) | Dedicated consumer cog, draws into PSRAM via U5 | **Matches plan** — `isp_hdmi_display_engine.spin2` cog, uses `gfx` + draws static labels and dynamic stats | Plan's "overlay rendering belongs here" is honoured: `DrawStaticLabels()`, `DrawDynamicStats()`. |
| `OledRenderer` (U8) | Dedicated consumer cog, blocking SPI | **Matches plan** — `isp_oled_single_cog.spin2` cog, inline-PASM render + inline-PASM SPI stream | Plan's "single-cog driver, owns SPI pins" honoured. |
| `SensorAcquirer` (U3) | Dedicated cog, calibration as a mode | **Matches plan** — `isp_tile_sensor.spin2` cog. Inline PASM applies `raw - baseline[i] + SENSOR_MID` in `.store_sensor_value` (sensor file line ~597). Hits ~1370 fps. | Calibration-as-mode landed exactly as specified. |
| Pool size & shape | 32 frames × ~256B payload + header | 32 frames × **128B** (sensor data only, no header) | Header was never needed; 128B is exactly the 64-WORD sensor frame. |
| Frame pool locking | Two locks — `pool_lock` + `queue_lock` | **One lock** (`isp_frame_fifo_manager.spin2:56`) covers both free-list and queue updates | No measured contention forced the split. |
| COGATN / WAITATN | Used for *every* consumer wake-up | **Used by HDMI consumer only**. OLED consumer polls with `fifo.dequeue(...)` (`isp_oled_single_cog.spin2:1061`) | Asymmetric — HDMI was upgraded first; OLED dequeue path was never migrated. |
| Hub memory plan | Hand-allocated ranges per owner ($00000–$7FFFF) | **Compiler-allocated**; OLED's 32KB pixel buffer + 8KB color LUT + cell-origin LUT live in its VAR | The plan's bookkeeping is informal in code, conceptually correct in layout. |

---

## 3. Cog allocation as-built

```
COG 0  Application + Decimator + Calibration UI    (mag_tile_viewer.spin2)
COG 1  SensorAcquirer  (isp_tile_sensor.spin2)
COG 2  PSRAM driver    (psram_driver.spin2)         ← matches U4 plan
COG 3  HDMI signal     (isp_hdmi_640x480_24bpp.spin2) via COGEXEC_NEW
COG 4  HDMI renderer   (isp_hdmi_display_engine.spin2)
COG 5  OLED renderer   (isp_oled_single_cog.spin2)
COG 6  -- free --
COG 7  -- free --
```

**Two cogs are unspent.** Adding `SignalProcessor` (cog 6) and `CommsHandler` (cog 7) later would not displace anything that ships today.

### Cog 0 carries more than the plan intended

`mag_tile_viewer.spin2` is **not** a pure composition root. It owns three jobs:

1. **Composition** — `main()` lines 70–174 instantiate FIFO, HDMI engine, OLED, sensor; configure modes; trigger baseline capture.
2. **Decimation/fan-out** — `normal_decimation_loop()` (line 286) and `slow_scan_loop()` (line 189). For each sensor frame, this loop:
   - dequeues from `FIFO_SENSOR`
   - increments per-FIFO counters (`hdmi_counter`, `oled_counter`)
   - decides `sendHDMI`/`sendOLED` by `(counter // decimation) == 0`
   - acquires a fresh pool frame, `WORDMOVE`s 128 bytes, and `commitFrame`s to each target FIFO
   - `releaseFrame`s the original sensor frame
3. **Calibration UI** — the 5-second countdown, capture trigger, stuck-pixel reporting (lines 138–166).

This is the most concrete way the as-built system diverges from the plan: **the fan-out is a Spin2 stage in cog 0 that copies frames**, not a refcount fan-out inside `commitToMultiple()`.

---

## 4. `FrameFifoManager` as-built

The plan specifies a single-producer / many-consumer refcounted pool with `commitToMultiple()` doing fan-out and COGATN dispatch. The shipped manager is simpler and busier.

### Shape

```
producer (sensor cog)
    framePtr := fifo.getNextFrame()       ; one pool slot
    ... fill ...
    fifo.commitFrame(FIFO_SENSOR, framePtr)   ; one FIFO

decimator (cog 0, main)
    framePtr := fifo.dequeue(FIFO_SENSOR)
    if sendHDMI
        hdmiPtr := fifo.getNextFrame()    ; second pool slot
        WORDMOVE(hdmiPtr, framePtr, 64)   ; copy 128 B
        fifo.commitFrame(FIFO_HDMI, hdmiPtr)
    if sendOLED
        oledPtr := fifo.getNextFrame()    ; third pool slot
        WORDMOVE(oledPtr, framePtr, 64)   ; copy 128 B
        fifo.commitFrame(FIFO_OLED, oledPtr)
    fifo.releaseFrame(framePtr)
```

Every frame that goes to both displays consumes **three** pool slots and pays for **two 128-byte copies**. The plan's refcount approach would use one pool slot and zero copies.

### API delta vs. plan

| Plan name | As-built name | Notes |
|---|---|---|
| `acquireFrame()` | `getNextFrame()` | Same intent, returns 0 on timeout (1 s). |
| `commitToMultiple(ptr, mask)` | **absent** | Fan-out is the decimator's job, not the manager's. |
| `commitFrame(fifoID, ptr)` | `commitFrame(fifoID, ptr)` | Per-FIFO single-target commit; this is what the manager actually exposes. |
| `dequeueEventDriven(fifo)` | `dequeueEventDriven(fifoID)` | Implemented (line 357). Uses inline `waitatn`. |
| `dequeue(fifo)` (polling) | `dequeue(fifoID)` | Implemented; polls every 1 ms, 1 s timeout. |
| `registerConsumer(fifo, cogid)` | `registerConsumer(fifoID, consumerCogID)` | Implemented; commit path calls `notifyConsumer(cog)` → `COGATN(1 << cog)`. |
| `releaseFrame(ptr)` | `releaseFrame(ptr)` | Returns slot to free list; **no refcount decrement** (there is no refcount). |
| `checkFreeListIntegrity()` | `checkFreeListIntegrity()` | Not in plan. Diagnostic that walks `freeList` looking for out-of-range pointers. |

### Defensive accretion

Inside `isp_frame_fifo_manager.spin2`, ~40 % of the code is bounds-checking that the plan does not anticipate. Every `getNextFrame`, `commitFrame`, `dequeue`, `releaseFrame` validates:

- `framePtr` is in `[poolStart, poolEnd)` (the pool address window)
- head/tail indices are `< MAX_FRAMES` or `< FIFO_DEPTH`

Each violation emits a `FIFO FATAL:` debug line and either zeroes the offending counter or drops the pointer. This grew in response to a real corruption episode (see commit history around the "WATCHPOINT" comments in `mag_tile_viewer.spin2:204–280`). It is load-bearing for stability today; removing it would need a re-investigation of the root cause that made it necessary.

### One lock, not two

The plan reserves `pool_lock` and `queue_lock`. The shipped manager has one (`lock`, line 56). Every public method takes that one lock; critical sections are short (a few `LONG` updates). There's no measured contention that would justify splitting, and adding a second lock would complicate the corruption-bounds-check path.

### COGATN wake-up: half-deployed

- **HDMI renderer** (cog 4) `registerConsumer(FIFO_HDMI, cogid())` + `dequeueEventDriven(FIFO_HDMI)` — wakes on `WAITATN`.
- **OLED renderer** (cog 5) calls `fifo.dequeue(FIFO_OLED)` — polls every 1 ms.

Both work; the OLED loop is 17 ms/frame anyway so the extra ms of poll latency is not visible. But the system is **not** symmetric the way the plan describes. Migrating OLED to event-driven is a 3-line change.

---

## 5. Units not yet built (and how they fit the trajectory)

The product target is a magnetic-field *analyzer*, not just a viewer. The units below are on that trajectory. Their absence today is sequencing, not scope reduction — and the cogs they will eventually occupy are intentionally reserved.

### `SignalProcessor` (U9, cog 6)
The plan reserves a cog for full-rate DSP (Kalman / FFT / peak-hold via CORDIC) feeding a separate `FIFO_PROCESSED`. **None of this exists in the source tree yet.** No FIFO_DSP, no CORDIC code, no Kalman state.

Trajectory: this is the unit that turns a viewer into an analyzer. Track-the-magnet, isolate-a-frequency, peak-hold-over-time, motion-vector estimation — all live here. The plan's Section 14 worked example for "add a WiFi streamer" applies symmetrically: U9 drops into cog 6 with one new FIFO id and zero changes to producer or existing consumers (if the refcount-fanout migration in §10 has happened first — otherwise it adds another consumer to the copy-and-commit decimator).

### `CommsHandler` (U10, cog 7)
No UART parser, no command grammar, no SD card. Status flows out via Spin2 `debug()` to the IDE-side terminal. Mode flags (`TEST_MODE`, `SLOW_SCAN_MODE`, `AUTO_CALIBRATE`, etc.) are compile-time `CON` constants in `mag_tile_viewer.spin2:13–28`.

Trajectory: an instrument needs runtime control — changing modes without a flash cycle, streaming frames to a host for offline analysis, scripted capture/playback, possibly an SD card archive. Compile-time `CON` flags are sufficient for the bench, insufficient for an instrument. The plan's "open question 4" (parser location, semantic dispatch) still needs an answer, but the unit itself is on the path.

### `ColorMapper` (U11) as a shared library
Plan: one library, both renderers use it, R4 visual coherence is guaranteed by construction.
As-built: the `field_to_color()` formula is **textually duplicated** in `isp_hdmi_display_engine.spin2:351` and `isp_oled_single_cog.spin2:973`, plus baked into the OLED's `init_color_lut()` (line 665). All three use the same `SENSOR_MID=20500`, `COLOR_RANGE=20500`, `GRAY_BASE=32` — but the constants live in three places.

Why this matters more as the product grows: every time the color mapping changes (it has changed at least twice — the `Removed gray_fade` and `symmetric COLOR_RANGE` fixes both dated 2025-12-26), the change must land in three files. Analysis features (heat-map modes, threshold overlays, isolated-frequency rendering, false-color palettes) will push more changes through this surface. Extraction now is cheaper than extraction after another consumer appears.

Why not extracted yet: the OLED uses a pre-computed 4096-entry RGB565 LUT (different output format from HDMI's RGB888). A shared library either exposes both `lookup_rgb565(val)` and `lookup_rgb888(val)`, or factors out `field_to_intensity(val)` as the shared atom and lets each renderer format-convert. Either is straightforward; the work just hasn't been done.

### Single owner per pin group — held
- P0–P7 owned by HDMI signal cog (P2 streamer hardware)
- P8–P15 owned by sensor cog
- P16–P23 owned by OLED cog
- P40–P57 owned by PSRAM driver cog

This invariant from the plan (Section 8) is intact in the as-built system, and will remain enforceable as U9/U10 land (DSP touches no external pins; comms claims P58–P63).

---

## 6. Composition tree as-built

```
mag_tile_viewer.spin2 (cog 0)
├── OBJ fifo         : "isp_frame_fifo_manager"      ← shared DAT singleton (U2)
├── OBJ hdmi_engine  : "isp_hdmi_display_engine"     → starts cog 4 (U7)
│       ├── OBJ fifo : "isp_frame_fifo_manager"      ← same DAT
│       ├── OBJ gfx  : "isp_psram_graphics"          ← library (U5)
│       │       ├── OBJ psram : "PSRAM_driver_RJA_Platform_1b" → starts cog 2 (U4)
│       │       ├── OBJ hdmi  : "isp_hdmi_640x480_24bpp"      → starts cog 3 (U6)
│       │       └── OBJ fonts : "isp_hub75_fonts"             ← library (U13)
│       ├── OBJ stack_check : "isp_stack_check"      ← stack overflow detector
│       └── OBJ sensor : "isp_tile_sensor"           ← imported only for is_stuck()
├── OBJ oled         : "isp_oled_single_cog"         → starts cog 5 (U8)
│       ├── OBJ fifo : "isp_frame_fifo_manager"      ← same DAT
│       ├── OBJ stack_check
│       └── OBJ sensor : "isp_tile_sensor"           ← imported only for is_stuck()
└── OBJ sensor       : "isp_tile_sensor"             → starts cog 1 (U3)
        ├── OBJ fifo : "isp_frame_fifo_manager"      ← same DAT
        └── OBJ stack_check
```

**Deviations from the plan's tree:**

- The plan has the Application reach only direct children. The as-built tree shows **`isp_hdmi_display_engine` reaches into `isp_tile_sensor`** to call `sensor.is_stuck(idx)`. Same with the OLED. This is a cross-cog read into the sensor's stuck-pixel table — read-only, but it punctures the "Application instantiates direct children only" rule. The shared DAT in `isp_tile_sensor.spin2` makes this safe (stuck_pixel[] is written only during calibration on cog 0, read by display cogs after).
- `isp_psram_graphics` is *not* in `mag_tile_viewer`'s `OBJ` block — it's only referenced by `isp_hdmi_display_engine`. That matches the plan: only the HDMI renderer draws into PSRAM.
- `isp_stack_check` is a runtime utility (sentinel-based stack overflow detector) that the plan does not contemplate. Each long-lived cog wraps key call sites in `stack_check.checkStack(...)` — defensive code born from real overflows.

---

## 7. Resource ownership as-built

| Resource | Owner today | Matches plan? |
|---|---|---|
| P0–P7 (HDMI TMDS) | HDMI signal cog (`isp_hdmi_640x480_24bpp`) | Yes |
| P8–P15 (sensor SPI + mux) | Sensor cog (`isp_tile_sensor`) | Yes |
| P16–P23 (OLED SPI) | OLED cog (`isp_oled_single_cog`) | Yes |
| P40–P57 (PSRAM bus) | PSRAM driver cog (`psram_driver`) | Yes |
| Frame pool (hub) | FIFO manager DAT, shared singleton | Yes |
| HDMI frame buffer (PSRAM) | PSRAM driver owns bus; HDMI renderer is only writer; HDMI signal is only reader | Yes |
| OLED pixel buffer | OLED renderer VAR (32 KB) | Yes |
| Color LUT (OLED) | OLED renderer VAR (8 KB) — *no shared ColorMapper* | Diverges (see §5) |
| Sensor remap table | Sensor cog DAT (`unified_sensor_map`) | Yes (inlined per Appendix C) |
| Font bitmaps | `isp_hub75_fonts` library DAT | Yes |
| Locks | One lock in FIFO manager | Plan said two |
| Stuck-pixel table | Sensor cog VAR, **read by HDMI + OLED** | Diverges from "single owner reads its own DAT" |
| System clock | Set once in `mag_tile_viewer.spin2:11` (`_CLKFREQ = 250_000_000`) | Yes |
| Cog 6, cog 7 | Unallocated | n/a (plan would use these) |

---

## 8. Invariants — what holds, what drifted

Reproducing the plan's invariant list (Section 13), with status:

| Invariant | Status | Notes |
|---|---|---|
| **I-A** Cog owns its pin group exclusively | **HOLDS** | No cross-cog pin touches in the source. |
| **I-B** FIFO has exactly one registered consumer cog | **HOLDS** | `sensorConsumerCog`, `hdmiConsumerCog`, `oledConsumerCog` are each set once. |
| **I-C** Refcount ≥ 1 from commit to last release | **NA** | No refcount exists; each FIFO entry is a unique pool slot owned by exactly one consumer. |
| **I-D** Producers never block on consumers | **HOLDS** | Sensor cog drops if `FIFO_SENSOR` is full (`commitFrame < 0` → `releaseFrame`); decimator drops if `FIFO_HDMI`/`FIFO_OLED` is full. |
| **I-E** PSRAM accessed only through U4's mailbox | **HOLDS** | All PSRAM I/O goes through `isp_psram_graphics`, which writes the 3-long mailbox. |
| **I-F** COGATN used only by FIFO commit | **HOLDS** | Only `notifyConsumer()` in the FIFO manager emits `COGATN`. |
| **I-G** Libraries are stateless except U5's per-cog mailbox handle | **HOLDS for U5/U13.** `isp_stack_check` has no per-cog state. | Color mapping isn't in a library, so this isn't tested by the as-built system. |
| **I-H** System clock set once at boot | **HOLDS** | `_CLKFREQ = 250_000_000`, never reconfigured. |
| **I-I** No lock held across hub access boundary | **HOLDS** | Critical sections in FIFO manager are just head/tail/count updates. |

The most interesting line is **I-C**. The plan's correctness model is built on refcounts; the as-built model replaces refcount with per-consumer copies. Both produce a correct "one frame, one consumer ownership" guarantee. The shipped model trades hub bandwidth for simpler code.

---

## 9. Why the divergences

Grouped by category. Each row tries to be honest about whether the deviation is *deferred work*, *deliberate scope*, or *the plan was over-built for what we needed*.

| Divergence | Why | Category |
|---|---|---|
| No `SignalProcessor` | Sequencing — the visualization path was built first; DSP is next on the trajectory | Not yet built |
| No `CommsHandler` | Sequencing — bench debug via Spin2 `debug()` was sufficient to ship the viewer; runtime control is next | Not yet built |
| `commitToMultiple` + refcount missing | Plan landed after the FIFO manager was already shipping; switching now would require careful migration of every commit/release call site, and the copy-based scheme works | Deferred — would reduce hub bandwidth and pool pressure |
| Decimation is a Spin2 stage in cog 0 | Followed naturally from "no `commitToMultiple`": somebody has to choose which FIFOs each frame goes to | Consequence of the above |
| Application carries decimation + calibration UI | Same root cause | Consequence |
| ColorMapper duplicated, not extracted | OLED and HDMI use different output formats (RGB565 LUT vs. RGB888 inline); single-consumer-each made extraction feel like ceremony | Deferred — extraction is straightforward, just unprioritized |
| One lock vs. two | No measured contention; bounds-check error paths assume one lock | Plan was over-built for measured contention |
| OLED dequeue still polls | Pre-dates the COGATN migration that HDMI got; OLED's frame budget (17 ms) hides the polling latency | Deferred — small, mechanical change |
| Hub map not hand-placed | Compiler placement happens to land inside the plan's intended ranges; explicit placement would buy nothing today | Plan was prescriptive where it didn't need to be |
| Display cogs reach into sensor's `is_stuck()` table | Stuck-pixel rendering is a display concern; computing it is a calibration concern. The shared-DAT read happens to be safe (write-once on cog 0, read-only on display cogs) but punctures composition-root purity | Pragmatic; would be cleaner as a separate "sensor health" library |
| Defensive bounds-checking throughout FIFO manager | Born from a real corruption incident; the plan's clean invariants don't survive that without the checks | Necessary scar tissue — keep until the root cause is fully understood |
| Stack overflow sentinel in every long-lived cog | Born from real stack overflows; the plan doesn't contemplate Spin2 stack sizing surprises | Necessary — keep |

---

## 10. Convergence path — verdicts

Each candidate change with an honest verdict. **Verdicts assume the system is heading to a complete magnetic-field-analysis product**, not staying at today's visualization snapshot. Several of these change calculus once you take the trajectory into account.

| # | Change | Effort | Verdict | Why |
|---|---|---|---|---|
| 1 | **Migrate OLED dequeue to event-driven.** Add `registerConsumer(FIFO_OLED, cogid())`; swap `dequeue` for `dequeueEventDriven`. ~3 LOC. | Trivial | **Do it.** | Removes one inconsistency between display cogs. No scope dependency, no behavior risk, pure cleanup. Cheaper to do alone than as part of a larger refactor. |
| 2 | **Extract `ColorMapper` as a library.** Move constants + formula to `isp_color_mapper.spin2`; expose `lookup_rgb888(val)` and `lookup_rgb565(val)` (or factor `field_to_intensity()` as the shared atom). | Small (~½ day) | **Do it.** | The duplication has already rotted twice. Analysis features (heat-map modes, threshold overlays, false-color palettes, isolated-frequency rendering) will push more changes through this surface — each one is a 3-file synchronized edit today. Restores R4 by construction. |
| 3 | **Add `commitToMultiple(ptr, fifo_mask)` + refcount to `FrameFifoManager`.** Add per-slot refcount, change `getNextFrame`/`releaseFrame` to inc/dec, fold decimation counters into the manager, migrate every commit site. | Large (multi-day, high blast radius) | **Do it — but *before* adding more consumers, not after.** | Today's pool pressure is borderline (32 slots ≈ worst case with 2 consumers). Adding DSP, comms, logging, or a second display under the current copy-and-commit scheme multiplies in-flight slot demand and copy cost — every new consumer makes the migration harder, not easier. The refcount pattern is the kind of change that must happen *atomically* across every commit/release call site; doing it with 2 consumers in flight is ~5× cheaper than doing it with 4. **This is the highest-leverage step on the list, and the one most often miscategorized as "later."** |
| 4 | **Trim `mag_tile_viewer.spin2` toward composition root.** | Medium | **Bundle with #3.** | Once `commitToMultiple` exists, the decimator dissolves into FIFO state and the main file shrinks. Calibration UI (the 5-second countdown, capture trigger, stuck-pixel summary) legitimately belongs at the composition root for an instrument — it's a device lifecycle event, not a comms feature. Don't move it for purity's sake. |
| 5 | **Add `CommsHandler` (cog 7).** Command grammar, runtime mode dispatch, parameter set/get, telemetry stream, eventually SD/USB. | Medium | **On the path. Sequence after the first feature that demands runtime control.** | Triggers: changing modes without a flash cycle, pushing frames to a host for offline analysis, scripted capture/playback. Compile-time `CON` flags are fine for the bench, insufficient for an instrument. The plan's "open question 4" (parser location, semantic dispatch) needs an answer — recommend parser in U10, semantic dispatch into U1 via a small command mailbox. |
| 6 | **Add `SignalProcessor` (cog 6) + `FIFO_DSP`.** Plug in once the first DSP requirement is specified (Kalman track, FFT band, peak hold, motion vector, etc.). | Medium | **On the path. Sequence with the first DSP feature.** | The product is "analyze magnetic field," not "display magnetic field." A viewer without DSP is the unfinished form of the product. Plan's Section 14 shows the wiring is small once a real algorithm exists — *provided* the FIFO manager already supports refcount-fanout (step 3). |

**Sequencing summary.** Steps 1 and 2 are no-regret and can land any time. Step 3+4 should land *before* steps 5 and 6, because each consumer added under the current scheme makes step 3 harder. Steps 5 and 6 are not optional in the final product, but each is feature-triggered.

**The trap to avoid.** "The as-built copy-and-commit works fine, defer the refactor" is a true statement *for today's two consumers* and a costly statement *for the four-consumer trajectory*. The refcount migration is a one-time cost that compounds; the copy-and-commit cost is per-consumer-per-frame forever.

---

## 11. What the plan got right (and what survived divergence)

The doc so far catalogues gaps. The asymmetry matters: most of the plan held up.

- **Pin-ownership invariant (plan Section 8).** 100% intact. P2 hardware enforces parts of it (streamer locks pins; smart-pin owners can't share), but the plan's *naming* made it auditable. No cross-cog pin contention exists; it would be immediately visible if it did.

- **Cog-allocation *logic* (plan Section 5, Appendix B.1).** Only 6 of 8 cogs are populated, but every populated cog still passes the plan's "one forcing reason" test. The two empty cogs are reserved for units the plan named (U9, U10) — they aren't accidentally empty. The discipline scaled correctly to a partial deployment.

- **`PsramBroker` (U4) design.** Mailbox protocol, round-robin polling, per-cog 3-long slot, sign-of-length indicates direction. Plan and code match nearly verbatim.

- **`PsramGraphics` (U5) per-cog mailbox handle.** `psram_ptr := psram.pointer() + cogid() * 12` (line 69) is precisely the per-cog VAR state the plan describes. The discipline of `start()` binding the slot at cog-init time held.

- **Sensor calibration as a *mode* of U3.** Plan rejected separation; code rejected it too. Inline-PASM baseline correction in `.store_sensor_value` is the cleanest expression of "baseline lives where the samples live."

- **Appendix C "promote when needed."** Vindicated for U12 (SensorTopology stayed inlined; no second consumer appeared). U13 (FontRenderer) stayed a library — the lower-risk default; no harm done.

- **Appendix D.4 self-assessment.** The plan explicitly named the refcount-fanout pattern as "the riskiest layer-3 leap." Reality agreed — that is precisely the pattern that didn't make it from plan to code. The plan was honest about its own fragility, which is what made the divergence diagnosable.

- **Section 13 invariants.** Most still describe the system accurately. I-A, I-B, I-D, I-E, I-F, I-G (for built libraries), I-H, I-I all hold. The invariants describe *what is true* rather than *what was implemented* — and that distinction is what made them survive a different implementation path.

**The pattern.** Plan elements anchored in P2 hardware reality (pin ownership, streamer cog, PSRAM bus arbitration) survived 100%. Plan elements anchored in distributed-systems patterns (refcount-fanout, multi-FIFO with shared frames) survived less well — those required code-level discipline that hadn't yet accreted when the FIFO manager was first written.

---

## 12. Lessons — transferable principles

Distilled from the audit. Intended to be portable to the next P2 project and to the next architectural plan.

1. **Refcount-based zero-copy must be designed in from day one.** Retrofitting refcounts into a working FIFO manager touches every commit, every release, and every error-path bounds-check. The cost of the migration is high; the cost of a 128-byte copy is negligible. The right time to choose refcount-fanout is *before* the first consumer ships. After that, the cost of correctness during migration usually outweighs the savings — and grows with every additional consumer.

2. **Defensive bounds-checking born from real incidents is load-bearing.** The fix isn't to remove the checks; it's to understand the root cause that made them necessary. The incident write-up matters more than the diff. Until the root cause is established, treat the checks as scar tissue worth keeping.

3. **Single-consumer libraries are speculative; YAGNI usually wins.** Appendix C's "start inlined, promote when needed" is the right default. SensorTopology proved this right. The mirror lesson: **multi-consumer code that shares constants should be a library *immediately*** — ColorMapper's three-file duplication has already cost two synchronized edits, and the analysis surface will push more.

4. **Compile-time mode flags are fine until they aren't.** The "until they aren't" trigger is concrete (changing modes without a flash cycle, host-side analysis, scripted capture). Don't build comms speculatively; build it when the trigger fires. But name the unit in the plan so its absence is visible.

5. **The plan is still useful even when the code diverges.** It tells you what you *haven't built yet* (vs. accidentally not built), names invariants that should hold regardless of implementation, and gives a vocabulary for evaluating future changes. "We don't have CommsHandler yet" is a clearer state than "we don't have UART command parsing somewhere."

6. **"Single forcing reason per cog" survives any cog count.** It's a rule about *justification*, not about cog count. Every populated cog should have its one-sentence reason; every unpopulated cog should be a named-but-unbuilt unit, not a cog you forgot.

7. **Per-cog mailbox protocols are the right pattern for shared bus hardware on P2.** Round-robin polling, 3-long mailbox per cog, sign of length = direction. Should appear in any P2 system with one bus and multiple users.

8. **Inline PASM inside Spin2 methods is the right tool for tight per-frame work.** Sensor's calibration-in-acquisition (eliminated ~800 µs/frame); OLED's render-to-buffer + SPI stream. Plan's "dual-cog driver" archetype doesn't quite describe this — it's a *single*-cog driver with inline `ORG`/`END` blocks. Worth promoting to its own archetype in P2KB.

9. **Plans without a phased-evolution framing produce over-built-looking targets.** The plan describes the destination, not the journey. A "Phase 1 / Phase 2 / Phase 3" timeline would prevent readers from misinterpreting unbuilt units as "deferred" or "out of scope" — they're "next."

---

## 13. Cost of staying as-built — concrete numbers

For each major divergence, what does it actually cost in the running system, both today and on the trajectory?

1. **Copy-and-commit hub bandwidth.**
   128-byte `WORDMOVE` per consumer per frame. At 2 consumers (~60 fps HDMI + ~55 fps OLED) → ~14 KB/sec of hub traffic from the copies. P2 hub at 250 MHz delivers tens of MB/s per cog.
   **Today: ~0.04% of one cog's hub bandwidth — effectively zero.**
   **Trajectory: scales linearly with consumer count. At 4 consumers, still ≪ 1% — bandwidth is not the argument for migration.**

2. **Pool pressure under load.** *This is the cost that matters.*
   32 frame slots. Each decimator iteration temporarily holds 3 slots (the dequeued sensor frame + 2 fresh copies) before releasing the sensor frame. With FIFO depth 16 across three FIFOs, worst-case in-flight demand is 48 slots; the system avoids exhaustion because consumers drain faster than producers and `getNextFrame()` drops cleanly on its 1-second timeout.
   **Today: pool *must* be ≥32 slots. With refcount-fanout, ~16 would suffice (~2 KB hub saved).**
   **Trajectory: at 4 consumers, the as-built scheme needs ~64-slot pool just for headroom; refcount-fanout still fits in ~16.** This is the real argument for migrating *before* more consumers exist.

3. **OLED polling latency.**
   1 ms `waitms` between dequeue attempts when FIFO empty. OLED frame budget: 17 ms.
   **Today: up to 1 ms (~6%) of frame budget — invisible to viewer.**

4. **ColorMapper constant duplication.**
   `SENSOR_MID`, `COLOR_RANGE`, `GRAY_BASE`, formula duplicated across three locations. Has been synchronized through at least two changes (2025-12-26 commits).
   **Today: 2 minutes of careful 3-file editing per change. Bug surface: any missed file produces an R4 violation — HDMI and OLED disagree on color.**
   **Trajectory: analysis features will push more color-mapping changes than the viewer did; bug surface grows.**

5. **Cogs 6 and 7 idle.**
   Two cogs and their stacks unallocated.
   **Today: ~8 KB hub reserved. Opportunity benefit: DSP and comms drop in without cog reshuffling.**

6. **Defensive bounds-checking in `FrameFifoManager`.**
   ~200 LOC of validation. ~20–30 instructions per FIFO op happy path.
   **Today: ~1 µs per FIFO op. Insurance against an unexplained corruption mode — worth every cycle until the root cause is established.**

**Pattern across all six.** The as-built system pays for *simplicity*, not *performance*. Hub bandwidth is cheap on the P2; correctness scar tissue is justified by past pain; cogs are the constrained resource (and two are still free). The convergence work in §10 buys *cleanliness* today and *headroom* for tomorrow's consumers — not capacity for today's.

---

## 14. Meta-review — how well did a source-blind agent decompose this system?

The planning doc was produced by an agent given the P2 Knowledge Base and the project's documentation directory, but **no access to the source tree**. The exercise was a calibration: how does an agent with P2KB + project docs reason about functional decomposition for the P2? This audit is the report card.

### Where the agent was strong

- **Hardware-anchored decisions: ~100% correct.** Pin-group ownership, HDMI signal cog (streamer is intrinsically per-cog), PSRAM as a shared-bus arbiter cog, sensor cog as deterministic SPI owner. Every cog-allocation decision the plan labeled HARD or STRONG in Appendix B.1 matches the code. The agent correctly translated P2 silicon facts into architectural decisions.

- **Pattern selection from P2KB archetypes.** Singleton (U2), library (U5, U11–U13), PASM-only object (U6), dual-cog driver (U3, U4, U8, U9), driver object (U7, U10), top-level application (U1). The catalogue is correct and consistent; each unit's archetype is the right call given its responsibility.

- **Meta-disciplines that should be standard for *any* architecture agent.** These are the transferable habits, separate from the decomposition itself:
  - **Confidence grading (Appendix B).** HARD / STRONG / JUDGEMENT labels on each decision tell the reviewer exactly which calls to scrutinize. This alone is worth more than most architectural details.
  - **Post-decomposition audit (Appendix C).** The agent walked back through its own 13 units asking "is this really worth being its own object?" and correctly flagged U5/U12/U13. The "promote when needed" rule for U12 was vindicated by what the code did.
  - **Honest guidance-gap call-outs (Appendix D).** The agent named the patterns it had to synthesize from outside P2KB and explicitly flagged Appendix D.4 as the riskiest leap. Reality agreed. **An agent that knows what it doesn't know is more useful than one that's uniformly confident.**

  A future P2 architecture agent should produce all three of these by default, regardless of project. They're the meta-discipline, not the answer.

### Where the agent could improve

- **Greenfield framing produced an over-finished-looking target.** The plan describes the destination, not the journey. With no source visibility, the agent had no way to know that a working subset already existed and had its own constraints. A "Phase 1 → Phase 2 → Phase 3" appendix would have made absent units read as "next" rather than "missing," and would have surfaced the *cost of migration vs. cost of carrying* as an explicit decision axis.

- **Pattern choices were architecturally elegant but implementation-cost-blind.** The refcount-fanout-via-`commitToMultiple` design is the right end state, but the agent didn't acknowledge that retrofitting it into a working FIFO manager is expensive — *and gets more expensive with every consumer added*. A "cost-to-retrofit" axis alongside HARD/STRONG/JUDGEMENT (call it LOW/MEDIUM/HIGH) would have made this visible and changed the sequencing recommendations.

- **Shared-library decisions didn't account for output-format divergence.** Plan correctly identified `ColorMapper` as a shared library for R4 visual coherence — but didn't notice that OLED uses an 8 KB RGB565 LUT while HDMI uses an inline RGB888 formula. The library has to expose two APIs (or factor `field_to_intensity()` as a thinner shared atom). An agent with source visibility would have caught this.

- **Pool sizing asserted without a derivation.** Plan picked "32 frames × ~256 B" without showing the formula. With more consumers, pool size should be parametric in `(consumers × FIFO_depth) + safety_margin`. An agent confident enough to recommend a number should be confident enough to derive it.

- **Single-cog-driver-with-inline-PASM missing as an archetype.** Sensor and OLED use inline `ORG`/`END` blocks inside Spin2 methods for tight per-frame work — neither pure-Spin2 nor full dual-cog. P2KB's archetype list (`p2kbSpin2ObjectArchetypes`) doesn't cover this; the agent honored the existing archetypes and correctly flagged the gap in D.1, but couldn't fix the source of the gap.

- **"Application is pure composition root" is too clean for instruments.** A real magnetic-field analyzer has at-boot calibration rituals and a startup UX (countdowns, prompts) that legitimately live near `main()` — they're device-lifecycle events, not comms features. The plan's guidance is right for the fan-out logic but wrong for the calibration UX. An agent could distinguish "logic that should move" from "logic that belongs at the composition root."

- **Decimation-as-bus-property loses observability.** Folding decimation into `commitFrame()` is elegant but makes the per-FIFO decision invisible in `debug()`. The as-built Spin2 stage is uglier but lets you watch counters directly. Observability deserves a seat at the table alongside elegance.

### What would improve the next agent

The fixes split cleanly into **prompt/workflow gaps** (which the agent could not fix on its own) and **knowledge-base gaps** (which the agent itself can help fill):

**Prompt/workflow:**
- **Source visibility, or explicit greenfield-vs-brownfield framing.** "Design as if existing code may need to be migrated" would have prompted the phased-evolution thinking. The agent didn't lack reasoning — it lacked context. This is workflow, not capability.
- **"Cost-to-retrofit" as a required confidence axis.** Make it a checklist item alongside HARD/STRONG/JUDGEMENT.
- **A "phased evolution" appendix as standard output.** Forces the agent to think in steps, not states.

**P2KB feedback loop — the agent's Appendix D.1 already enumerated this list:**
- Document the **producer-consumer with refcounted pool + multi-FIFO fan-out** pattern as a canonical P2 idiom (currently absent from `p2kbSpin2ObjectArchetypes`).
- Document the **per-cog mailbox protocol for shared bus hardware** as a named archetype (PSRAM is the worked example).
- Document the **single-cog driver with inline-PASM blocks inside Spin2 methods** archetype — distinct from the existing dual-cog driver.
- Document the **decimation-as-bus-property vs. decimation-as-stage** trade-off, with the criterion for choosing.
- Add a **cog-allocation worked example for an 8-cog system** showing how archetypes compose at the system level (the agent flagged this gap explicitly and it remains the highest-leverage P2KB addition for system-level reasoning).

Filling these gives the next agent the authority to recommend these patterns and the human reviewer the citation to accept them.

### Overall verdict

The plan was **architecturally sound and self-aware**. Hardware-anchored decisions were correct at essentially 100%; pattern-level decisions were correct in roughly the 80% range; and the agent's honest map of its own weak spots in Appendix D made the audit easy. The single most useful trait was the meta-discipline — confidence grading, post-decomposition audit, and acknowledgement of guidance gaps. These transfer across projects and should be expected by default.

The single most addressable weakness was the greenfield assumption. The fixes are workflow-level (source visibility, brownfield prompting, phased-evolution requirement) rather than capability-level. The agent did not lack reasoning; it lacked context.

**The exercise is repeatable.** The plan's quality is high enough that an audit (this document) is the right way to use it — not "did the code follow the plan?" but "where does the plan disagree with the code, and which side should win?" That framing keeps both the plan and the audit honest.

---

## 15. Sources

- Code as of `main`, 2026-05-26.
- `mag_tile_viewer.spin2` (349 lines) — composition + decimator + calibration UI.
- `isp_frame_fifo_manager.spin2` (524 lines) — singleton, one lock, no refcount.
- `isp_tile_sensor.spin2` (972 lines) — sensor cog, inline PASM + inline calibration.
- `isp_hdmi_display_engine.spin2` (383 lines) — HDMI consumer cog, event-driven.
- `isp_oled_single_cog.spin2` (1120 lines) — OLED consumer cog, polling.
- `isp_psram_graphics.spin2` (1103 lines) — per-cog mailbox library.
- `psram_driver.spin2` (297 lines) — PSRAM cog, 8×3-long mailbox.
- `isp_hdmi_640x480_24bpp.spin2` (202 lines) — HDMI signal cog.
- Companion: `Object-Architecture-and-Cog-Allocation.md` v1.1 (the plan being audited).

---

## Document history

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-05-26 | First as-built audit. Pairs with planning doc v1.1. |
| 1.1 | 2026-05-26 | Reframed unbuilt units as "not yet built on the trajectory" (vs. "out of scope"). Added §10 convergence verdicts, §11 plan wins, §12 transferable lessons, §13 cost-of-staying-as-built with numbers, §14 meta-review of the source-blind agent exercise. |
