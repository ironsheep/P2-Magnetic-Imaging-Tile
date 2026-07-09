# Multi-Resolution Field Visualization — Sprint Plan

**Project:** P2-Magnetic-Imaging-Tile
**Author:** Stephen M Moraco / Claude (Opus 4.8)
**Status:** Planned — ready for `sprint-start`
**Plan type:** Sprint plan (ship commitment), not a study.

---

## 1. Purpose and framing

The system today acquires the 8×8 Hall-effect array at ~1,370 fps and renders
a **native 8×8** blocky field on both the OLED (128×128 SPI) and HDMI (640×480)
displays. This sprint turns that fixed 8×8 viewer into a **magnetic-field
exploration instrument**: a set of compile-time-selectable processing modes,
each chosen to make a *specific physical aspect* of the field visible —
**near-field structure**, **far-field structure**, and **field strength /
dynamic range** — not merely to demonstrate interpolation for variety's sake.

The richness is organized on **three independent axes**, each an independent
compile-time `#define` today and an independent runtime knob later:

| Axis | Symbol | Choices | Physical question it controls |
|---|---|---|---|
| **A — Resolution** | `FIELD_RES` | `8` / `16` / `32` | Reconstruction density between the 64 real samples |
| **B — Reconstruction kernel** | `FIELD_KERNEL` | `NEAREST` / `BILINEAR` / `CATMULL` / `LANCZOS3` | **Sharp ↔ smooth** — the near-field vs far-field *spatial* control |
| **C — Color transfer** | `FIELD_COLOR` | `BIPOLAR` / `HIGHGAIN` / `LOG` / `GRADIENT` | **Amplitude & structure reveal** — where field *strength* and derived structure become visible |

Any `(A, B, C)` triple is a legal build. The three axes are read by different
subsystems (A by the decimator + FIFO + both displays; B by the decimator; C by
both display render paths), so they compose without interaction.

### Measured exit goal

**OLED sustains ≥ 60 fps on the board**, confirmed by `measure_sclk_rate()`
reporting true ~20 MHz SCLK and `test_oled_performance.spin2` reporting
≥ 60 fps. (Sensor already exceeds target at ~1,370 fps; HDMI is locked at
60 Hz by VGA timing.)

### Scope discipline

This sprint implements **only** the non-deferred subset. The deferred items
(§ Deferred) are **architecturally anticipated** — each lands at a named extension
point that this sprint builds — and are **named in `DOCs/System-Specification.md`
as intended future work** (§12). Nothing deferred is half-built here.

---

## 2. Architecture and data flow

```
Sensor COG (isp_tile_sensor)          ~1,370 fps, native 8×8, calibrated in PASM
   │  64-WORD frame
   ▼
Sensor FIFO
   │
   ▼
Decimator / Processor COG  ── reads FIELD_RES (A) + FIELD_KERNEL (B)
   │   • decimate to display cadence (unchanged mechanism)
   │   • upsample 8×8 → N×N via shared polyphase resampler   ← NEW
   │   N×N-WORD frame  (N = FIELD_RES)
   ├──────────────► HDMI FIFO ──► HDMI Engine  ── reads A + FIELD_COLOR (C)
   │                                • scanline render N×N into PSRAM  ← NEW
   │                                • analytical overlay (legend, peak)  ← NEW
   └──────────────► OLED FIFO ──► OLED Driver  ── reads A + FIELD_COLOR (C)
                                    • render N×N into 128×128 pixel buffer ← CHANGED
                                    • smart-pin SYNC_TX stream @ 20 MHz    ← VERIFIED/FIXED
```

**Key invariant that de-risks the sprint:** the OLED always streams a full
128×128 pixel buffer (32 KB) regardless of `FIELD_RES`. So OLED frame time
depends **only** on SPI transfer efficiency, never on the selected resolution.
"OLED to 60 Hz" (§5) and "add resolutions" (§3, §4) are therefore independent
and cannot interfere.

### COG allocation (unchanged from current)

| COG | Component | Sprint impact |
|---|---|---|
| 0 | Main / decimator (`mag_tile_viewer`) | Gains resampler call + Axis-A/B dispatch (§3) |
| 1 | Sensor (`isp_tile_sensor`) | None |
| 2 | HDMI engine (`isp_hdmi_display_engine`) | Scanline render + overlay (§6, §7) |
| 3 | OLED driver (`isp_oled_single_cog`) | N×N render + SPI verify (§5) |
| 4 | PSRAM driver | None |
| 5 | HDMI video | None |

The resampler (§2 object) runs **inline in the decimator COG** — it is a code
object, not a COG of its own. No new COG is allocated; all 8 are already in use
or reserved and the interpolation cost (§below) fits the decimator's budget.

---

## 3. Guide and reference dependencies (read before writing code)

Per the project `sprint-plan` overlay, `DOCs/policy/SPIN2-AUTHORING-GUIDE.md`
is required reading because every deliverable touches `src/*.spin2`. Sections
this sprint depends on:

- **Part 4** — every new PUB/PRI gets a complete doc block (`''` PUB / `'` PRI,
  `@param`/`@returns`/`@local`). All new methods in §2, §5, §6, §7.
- **§5.2 single-exit-point** — the new resampler kernels and render loops use
  one exit so the trailing `debug()` runs on every path.
- **CON for magic numbers** — kernel tap counts, phase counts, grid dimensions,
  coefficient scale factors all become named `CON`.
- **§1.1 ASCII-only** in `debug()` — the new diagnostics (SCLK measure, resampler
  self-test) print PASS/FAIL/us, never Unicode.
- **§6.2 naming** — grid-dimension locals must not shadow `WIDTH`/`HEIGHT`.

Authoritative P2KB references pulled during planning (quoted where used):

- **Preprocessor** (`p2kbSpin2PreprocessorOverview`, v47+): `#define`, `#ifdef`,
  `#elseifdef`, `#else`, `#endif`, `#error`, `#include`; 8-level nesting; symbol
  names case-sensitive; `-D symbol` command-line define (v48+). Confirms the
  compile-time mechanism and the `#error` guard for illegal axis combinations.
- **Smart Pin %11100 Sync Serial Transmit** (`p2kbArchSmartPin11100SyncSerialTransmit`):
  "MANDATORY FOR SPI: the B-input provides the clock… YOU MUST route clock from
  the correct pin (`P_PLUS1_B`, `P_PLUS2_B`, …)." Continuous-mode init order:
  enable pin first, prime shifter, load buffer (double-buffered/gapless), then
  poll IN. MSB-first needs `SHL #(32-bits)` + `REV`. This is the §5 audit
  checklist.
- **QVECTOR** (`p2kbPasm2Qvector`): Cartesian→polar via 54-stage CORDIC;
  `GETQX` = magnitude (length), `GETQY` = angle; results 55 clocks after issue;
  one CORDIC op issuable per 8-clock hub window. This is the §7 gradient-magnitude
  primitive: feed `(dB/dx, dB/dy)` → `GETQX` = |∇B|.

---

## 4. Testing & certification ladder

**Principle: every piece is proven in isolation before it is wired to the next.**
The sprint builds a chain (config → resampler → color → FIFO → decimator →
displays → system), and each link gets a **standalone, self-checking regression
harness** that must go green before the link above it is allowed to consume it.
No stage is integrated on faith; a defect is caught at the rung where it lives,
not three layers up in a full-system flame-out.

This follows the project testing policy (CLAUDE.md): **test instrumentation
lives in the test file, never in the production library**; debug is **ASCII-only**
(PASS/FAIL/us); multi-COG tests label roles (PRODUCER/CONSUMER) and verify data
integrity with **sequence numbers + checksums**. `test_fifo_regression.spin2` is
the exemplar this ladder extends.

### Shared test scaffolding — `test_field_support.spin2` (built first) 🆕

Per the skill's "plan reusable fixtures as shared from the start" rule, one
shared test-support object serves every rung — so golden-compare and synthetic
inputs are written once, not re-invented per test:

- **Synthetic 8×8 generators** (known content): `gen_ramp()`, `gen_impulse(r,c)`,
  `gen_checkerboard()`, `gen_constant(v)`, `gen_edge_step()`.
- **Golden-compare:** `assert_grid_eq(actualPtr, goldenPtr, count, tol, label)` →
  prints `label: PASS` or `label: FAIL @ idx N (got G, want W)`.
- **Integrity:** `frame_checksum(ptr, count)` and sequence-number stamping,
  reused from the FIFO regression pattern.

Golden expected-value tables (the analytic results for each kernel/color on each
synthetic input) are computed on the host and baked as `DAT` tables in the
relevant test file — the P2 asserts against them; it does not recompute the
reference.

### Per-arm test discipline (add the arm → add its proof, in the same task)

Every `FIELD_KERNEL` and `FIELD_COLOR` `case` arm is a deterministic function, so
its output is **predictable in closed form**. The standing rule for this sprint
(and for the deferred arms in § Deferred):

> **No `case` arm is complete until its golden test case(s) are in the harness —
> at least one representative example plus its edge case(s).** Adding an arm
> without its vector is an unfinished task, not a passing one.

Because the scaffolding is shared, adding an arm's proof is a **table addition**
(one input row + its baked golden row), not a new test program. This is what lets
us layer arms in one at a time and *prove each before the next*.

### Golden-vector catalog (these are hand-computed — demonstrating predictability)

**Resampler (§2, rung T2).** All kernels are separable, so 1-D reasoning suffices;
weights are a partition of unity (sum to 1):

| Input | NEAREST | BILINEAR | CATMULL | LANCZOS3 | What it proves |
|---|---|---|---|---|---|
| **Constant** `V` everywhere | `V` | `V` | `V` | `V` | Coefficient sum = 1 (catches a mis-scaled table) |
| **Linear ramp** e.g. src `0,100` → 2× | `0,0` (block) | `0,50,100` | `0,50,100` (exact) | `≈0,50,100` (±tol) | Phase placement; bilinear/Catmull exact on linear |
| **Unit impulse** (one src =`1`, rest `0`) | block of `1`s | triangular `…,½,1,½,…` | cubic weights **incl. negative lobes** | sinc lobes **incl. negatives** | Directly asserts each kernel's coefficient table |
| **Impulse at border** | — | — | edge-replicate, **no wrap** to far edge | edge-replicate | Edge handling |
| **Steep step** near `SENSOR_MAX` | no overshoot | no overshoot | overshoot **clamped** to `[MIN,MAX]` | larger overshoot **clamped** | Clamp path |

The impulse row is the strongest test: for a 4× upsample the sub-phase outputs
*equal the kernel coefficients themselves*, so a wrong tap or sign is caught
immediately.

**Color (§7, rung T3).** Point-wise, so each is a single hand-computable value
(`GRADIENT` is the one spatial case):

| Input | Expected | What it proves |
|---|---|---|
| `BIPOLAR(SENSOR_MID)` | neutral midpoint | Zero-field = neutral |
| `BIPOLAR(MID+Δ)` vs `BIPOLAR(MID−Δ)` | green-ramp vs red-ramp, **mirror-symmetric channels** | Symmetric bipolar mapping |
| `BIPOLAR(±full)` | full green / full red, **no wraparound** | Clamp |
| `HIGHGAIN(small Δ)` | visibly colored where `BIPOLAR(small Δ)` is near-black | Far-field gain pulls weak signal up |
| `LOG(Δ)` and `LOG(10·Δ)` | both non-black **and** non-saturated | Dynamic-range compression (near+far visible together) |
| `GRADIENT` on a constant-slope ramp grid | **uniform** \|∇B\| → uniform color | Gradient of linear field is constant |
| `GRADIENT` via `QVECTOR(3,4)` | `GETQX = 5` (and `(dx,0)→\|dx\|`) | CORDIC magnitude correct, pipelined-latency respected |

### The rungs (each is a sprint deliverable — authoring the harness is plan work)

| Rung | Certifies | Harness | Method | Pass gate |
|---|---|---|---|---|
| **T1** | §8 config | `run-test.sh` preset-matrix mode (host/compile) | Compile all 6 presets; assert illegal combos emit the expected `#error` | Every preset green; every illegal combo fails as intended |
| **T2** | §2 resampler | `test_field_interpolate.spin2` | Golden-vector: each kernel × {2×,4×} vs baked `DAT` goldens | All kernels match within Q-tolerance; originals reproduced exactly; edge-replicate; overshoot clamped |
| **T3** | §7 color | `test_field_color.spin2` | Golden LUT values (BIPOLAR/HIGHGAIN/LOG); GRADIENT |∇B| vs analytic magnitude | Each mode's golden PASS; zero-field→neutral; QVECTOR magnitude within tolerance |
| **T4** | §4 FIFO | `test_fifo_regression.spin2` + `test_fifo_stress.spin2` (extended) | Run at `FRAME_SIZE` = 128 / 512 / 2048; multi-COG producer/consumer, seq+checksum | Green at all three sizes; free-list/Knuth bookkeeping intact; zero integrity failures |
| **T5** | §3 decimator | `test_decimator_pipeline.spin2` (supersedes broken `test_fifo_pipeline.spin2`) | Synthetic sensor frames → decimator → assert upsampled, sequence-correct frames reach BOTH display FIFOs at configured cadence | Correct N×N content + sequence at both FIFOs; cadence matches decimation ratios; no sensor-FIFO backpressure |
| **T6** | §5 OLED | `measure_sclk_rate()` + `test_oled_performance.spin2` + `test_oled_alignment.spin2` + N×N tiling pattern | Measured (SCLK, fps) + visual/programmatic tiling | SCLK ~20 MHz; **fps ≥ 60**; RES=32 tiles 128×128 with no seam/remainder |
| **T7** | §6 HDMI | `test_hdmi_scanline.spin2` | Known N×N pattern → verify 264-px tiling has no gaps at non-integer cell widths; render within budget | No seams/gaps at RES=16,32; render keeps pace (no HDMI-FIFO backpressure) |
| **T8** | full system | `test-playbook` (authored via the `test-playbook` skill) | Each of the 6 presets end-to-end on both displays | Every preset renders its intended reveal on both displays; `P_RAW` matches pre-sprint baseline |

### Integration order (the ladder is climbed bottom-up)

```
T1 (config compiles) → T2 (resampler) → T3 (color) → T4 (FIFO @ all sizes)
   → T5 (decimator wires resampler+FIFO) → T6 (OLED) ∥ T7 (HDMI)
   → T8 (full system per preset)
```

Each rung must be green before the next consumes it. **T2 and T3 are pure-math,
board-optional, self-checking — the cheapest, highest-value nets, run first.**
The `P_RAW` (`RES 8 / NEAREST / BIPOLAR`) build is the byte-for-byte regression
anchor threaded through T4, T5, and T8 — it proves the new machinery reduces
exactly to today's behavior when the axes are set to baseline.

---

## 5. Deliverables

Each section is a coherent work package. Sections map to `plan-to-tasks`
boundaries. No estimates, priority, or day-counts appear here — a plan carries
none. Each deliverable names the ladder rung (§4) that certifies it — that rung's
harness is itself a deliverable of this sprint.

---

### § 1 — Baseline measurement gate (OLED truth) 🔴 gating

**Why:** The 60 Hz-sprint OLED rewrite (`display_frame_fast` + continuous
SYNC_TX stream, commit `c18e558`) is committed but **never measured on
hardware**. We must not build on an unverified baseline, and §5's "fix to
60 Hz" needs a starting number.

**Current code:** `measure_sclk_rate()` at `isp_oled_single_cog.spin2:760`
already issues an `SCLK_MEASURE_PULSES` burst, times it via `GETCT`, and prints
`SCLK measure: N pulses took NNN ticks -> NNNNNNNN Hz`. Called once from
`init_hardware()` at `isp_oled_single_cog.spin2:745`. Frame timing (min/max/avg
cycles) already instrumented in `display_frame_fast()` at
`isp_oled_single_cog.spin2:398`.

**Target behavior:** Flash the current top (`mag_tile_viewer.spin2`) and
`test_oled_performance.spin2` to the P2 Edge board. Record:
1. Actual SCLK Hz reported by `measure_sclk_rate()` — expect ~20 MHz.
2. OLED frames/sec from `test_oled_performance.spin2`.
3. Visual correctness of first frames (alignment; the `ror/rev` wire-order math).

**Integration points:** none (measurement only). Output feeds §5's decision:
if SCLK is already ~20 MHz and fps ≥ 60, §5 reduces to "confirm and document";
if SCLK is throttled or fps < 60, §5 executes the full smart-pin audit.

**Verification:**
- *Normal:* diagnostic prints a sane SCLK (~20 MHz) and a frame rate; numbers
  recorded in `DOCs/analysis/Performance-Analysis.md`.
- *Edge:* SCLK reads materially below 20 MHz (e.g. the stale "208 kHz" the old
  `isp_oled_driver.spin2:169` comment feared) → flagged as the §5 root cause.
- *Error:* no OLED output / garbled hex-mode terminal → capture and treat as a
  §5 blocker (wire order or DC/CS mis-sequence), not a measurement pass.

---

### § 2 — Shared polyphase separable resampler (`isp_field_interpolate.spin2`) 🆕

**Why:** All four kernels (`NEAREST`, `BILINEAR`, `CATMULL`, `LANCZOS3`) are the
**same separable multiply-accumulate** differing only by a small
compile-time-constant coefficient table, because we upsample by **fixed integer
ratios** (8→16 = 2×, 8→32 = 4×). The fractional phases are a tiny known set
(`{0, ½}` for 2×; `{0, ¼, ½, ¾}` for 4×), so sinc/cubic are never evaluated at
runtime — the weights are constants. This makes one shared engine serve every
technique, and makes each future kernel "a coefficient table + a case arm."

**Current code:** No interpolation exists anywhere (`grep` for
`interpolat|bilinear|bicubic` returns only doc comments). The
`MODE_AVERAGING`/`MODE_PEAK` arms in `mag_tile_viewer.spin2:80-81` and
`isp_frame_transform.spin2:151-159` are unrelated *temporal* stubs (deferred, § Deferred).

**Target behavior:** A new **shared object** `src/isp_field_interpolate.spin2`
exposing:
- `upsample(srcPtr, dstPtr)` — reads the native 8×8 (64-WORD) grid at `srcPtr`,
  writes the `FIELD_RES × FIELD_RES`-WORD grid at `dstPtr`.
- Implemented as **two separable 1-D polyphase passes** (rows, then columns),
  inline PASM MAC, per-axis tap window fed from a **phase-coefficient table**
  selected by `FIELD_KERNEL`.
- Kernels and tap counts:
  - `NEAREST` — 1-tap (block replicate); identity at `FIELD_RES = 8`.
  - `BILINEAR` — 2-tap.
  - `CATMULL` (Catmull-Rom cubic) — 4-tap; interpolates the data points, gentle
    overshoot → clamp to sensor range.
  - `LANCZOS3` — 6-tap; sharpest; ring overshoot → clamp. Shipped at
    `FIELD_RES = 32` only.
- Coefficients are **fixed-point** (scale `Q15` or similar named `CON`), baked
  as `DAT` tables per kernel×ratio. Edge handling: clamp source index at grid
  borders (replicate edge sample) — no wrap.
- A `self_test()` PRI (test-side per project policy; see below) that upsamples a
  known ramp and asserts corner/edge/interior values.

**Shared-component rationale (skill §2):** both display engines *could* each
carry their own upsampler, but the decimator owns upsampling (Stephen's
architecture: algorithms live in the decimator, richer data flows through the
FIFO). One shared object, called once per frame in the decimator, feeds both
displays identical data. Built shared from the start — never "refactor to shared
later."

**Certified by:** rung **T2** — `test_field_interpolate.spin2` golden vectors
(catalog in §4). Each kernel arm lands with its impulse + constant + edge/clamp
vectors in the same task per the per-arm discipline.

**Integration points:** called by §3 (decimator). Coefficient tables and the
tap-window MAC are the **extension point** for deferred kernels (§ Deferred:
smoothstep, B-spline, Mitchell — each a new table + case arm).

**Verification** (self-test lives in a test harness, not the library, per
CLAUDE.md debug-instrumentation policy):
- *Normal:* upsample a linear ramp 8→16 and 8→32; interior interpolated values
  match the analytic weighted sum within fixed-point tolerance; the 4 original
  corner samples reproduce exactly (all kernels are interpolating).
- *Edge:* border cells use edge-replicate, not wrap — a bright edge sample does
  not bleed to the opposite edge; `LANCZOS3`/`CATMULL` overshoot is clamped to
  `[SENSOR_MIN, SENSOR_MAX]`.
- *Error:* `FIELD_KERNEL = LANCZOS3` with `FIELD_RES = 8` (identity — kernel has
  no phases to apply) → compile-time `#error "LANCZOS3 requires FIELD_RES >= 16"`.

---

### § 3 — Decimator integration and Axis-A/B dispatch 🔧

**Why:** The decimator (routing COG) is where Stephen wants the processing
algorithms to live, producing the upsampled frames that flow through the FIFO.

**Current code:** Decimation + routing runs **inline in the main COG**, not in
the standalone `isp_frame_transform.spin2` (which is an unused parallel object
with a stale `DECIMATION = 9`). The live loop is `mag_tile_viewer.spin2` main
(`PUB main()` at `:88`, decimation `case` at `:351`,
`DEFAULT_HDMI_DECIMATION/OLED_DECIMATION` at `:75-76`). It `wordmove`s the
native 64-WORD frame into HDMI- and OLED-bound copies (compare the
`FRAME_WORD_COUNT` copies in `isp_frame_transform.spin2:168,180`).

**Target behavior:**
- After decimation selects a frame for a display, the decimator calls
  `interp.upsample(sensorPtr, displayPtr)` (§2) instead of a plain `wordmove`,
  producing an `N×N`-WORD frame into the display-bound buffer.
- `NEAREST` at `FIELD_RES = 8` is the identity path (equivalent to today's
  `wordmove`) — the native baseline preset compiles to current behavior.
- The kernel is selected by `FIELD_KERNEL` (§1 config). Dispatch is written as a
  `case`/`case`-ready structure **pinned by the compile-time define**, matching
  the P2KB preprocessor guidance ("compile-time config selecting among
  runtime-ready case arms") so § Deferred's push-button runtime control is a one-line
  change, not a rewrite. This `case` is the **runtime-selection extension point**.

**Certified by:** rung **T5** — `test_decimator_pipeline.spin2` (synthetic
sequence-numbered frames through the decimator to both display FIFOs). The
`P_RAW` identity path is the byte-for-byte regression anchor.

**Integration points:** consumes §2 (`isp_field_interpolate`), §1-config
(`FIELD_RES`, `FIELD_KERNEL`); produces frames sized per §4. Both display FIFOs
receive already-upsampled `N×N` data.

**Verification:**
- *Normal:* with `FIELD_RES=8, FIELD_KERNEL=NEAREST`, output is byte-identical to
  the current viewer (regression anchor). With `FIELD_RES=32, CATMULL`, both
  FIFOs carry 1024-WORD smoothed frames.
- *Edge:* decimation cadence unchanged — both displays still receive frames at
  their configured rates; the upsample adds per-frame cost but must not drop the
  sensor FIFO into backpressure (watch for `HDMI/OLED FIFO FULL!` and the sensor
  `waitus(10)` backpressure path noted in Performance-Analysis).
- *Error:* upsample into an undersized display buffer → guarded by §4's
  compile-time frame-size derivation (buffer is always `N×N`); a mismatch is a
  compile error, not a runtime overrun.

---

### § 4 — FIFO frame-size generalization 🔧

**Why:** Upsampled frames are larger than the native 128-byte frame
(16×16 = 512 B, 32×32 = 2 KB). The frame pool must carry them.

**Current code:** `isp_frame_fifo_manager.spin2:29` `FRAME_SIZE = 128`
(hardcoded "64 sensors × 2 bytes"); `:30` `MAX_FRAMES = 32`; single shared
`framePool byte[MAX_FRAMES * FRAME_SIZE]` at `:44`. All three FIFOs
(`FIFO_SENSOR/HDMI/OLED`, `:24-26`) draw from this one pool. `FRAME_WORD_COUNT =
64` in `isp_frame_transform.spin2:35`; the `wordmove` copies in
`:168,180` move 64 words.

**Producer/consumer inventory (skill §2, required for a data-model change):**
- **Writers of a pool frame:** sensor COG (native 64 W, always); decimator
  (upsampled `N×N` W → HDMI/OLED copies, §3).
- **Readers:** HDMI engine (`isp_hdmi_display_engine`, §6), OLED driver
  (`isp_oled_single_cog`, §5). Each currently assumes 64 W (`SENSOR_GRID_SIZE=8`
  loops) — both updated in §5/§6 to read `N×N`.
- **Shape:** every consumer reads `FIELD_RES × FIELD_RES` WORDs after this sprint;
  the sensor frame stays native 64 W (a sub-region of the larger slot).

**Target behavior:**
- `FRAME_SIZE` becomes a compile-time expression derived from the shared config:
  `FRAME_SIZE = FIELD_RES * FIELD_RES * 2` (128 / 512 / 2048 B). Single shared
  pool retained → worst case `32 × 2048 = 64 KB` of the 512 KB hub. Sensor
  frames occupy only their native 128 B of the larger slot (harmless slack).
- **Decision (resolved, flag if disagree):** keep the **single shared pool**
  sized to `FIELD_RES`, rather than splitting a small sensor pool from a large
  display pool. Rationale: 64 KB worst case is a bounded fraction of hub; a split
  pool adds allocation complexity for no functional gain at these sizes.

**Certified by:** rung **T4** — `test_fifo_regression.spin2` +
`test_fifo_stress.spin2` extended to run at `FRAME_SIZE` = 128 / 512 / 2048 with
sequence+checksum integrity, before the resampler is wired in at T5.

**Integration points:** `FRAME_SIZE` derives from §1-config; all pointer
arithmetic in the FIFO already uses `FRAME_SIZE` (`:104,174,228,306,432,527,601`)
so it generalizes without per-site edits. §3's upsample target is `FRAME_SIZE`.

**Verification:**
- *Normal:* `FIELD_RES=32` → pool initializes 32 frames of 2048 B; free-list
  walk (`:103-104`) covers the full pool; regression test
  `test_fifo_regression.spin2` passes at the new frame size.
- *Edge:* `FIELD_RES=8` → `FRAME_SIZE=128`, identical to today; the FIFO
  regression suite is the guard that Knuth free-list bookkeeping (`:107-108`)
  still holds at both sizes.
- *Error:* hub over-allocation at some future larger `MAX_FRAMES × FRAME_SIZE`
  → add a compile-time `#warn`/comment documenting the 64 KB ceiling and the
  hub budget; not exceeded at shipped sizes.

---

### § 5 — OLED: verify/repair smart-pin SPI to 60 Hz, render N×N 🎯 measured goal

**Why:** The measured sprint exit is OLED ≥ 60 fps. Stephen's hypothesis: early,
incomplete P2KB smart-pin-SPI guidance may have produced a throttled or subtly
wrong SYNC_TX configuration. We now have authoritative guidance and an on-board
measurement to settle it.

**Current code:**
- Smart-pin init in `init_hardware()`: SCLK as `P_PULSE` (`isp_oled_single_cog.spin2:736`);
  MOSI as `P_OE | P_SYNC_TX | ((pin_sclk - pin_mosi) & %111) << 24` (`:740`).
  With SCLK=P18, MOSI=P16 the bit-math yields `P_PLUS2_B` — i.e. the **mandatory
  B-input clock routing is present** (this is *not* the obvious bug).
- Continuous-mode stream in `stream_pixel_buffer()` (`:629`): `wrpin` mode,
  `wxpin XCFG_SYNC_TX_CONT_32` (`:664`), `dirh`, then `wypin` priming
  (`:678,683`), IN-flag poll (`:695`), per-long `rflong/ror #16/rev` MSB-first
  prep. Restores start-stop 8-bit after the burst (`:711-713`).
- Grid render in `render_to_pixel_buffer()` (`:450`) is **inline PASM hardwired
  to 64 cells** (`cell_count := 64` at `:472`) walking `cell_origin_lut[64]`
  (`:173`), each cell a 16×16 pixel block (`CELL_WIDTH/HEIGHT = WIDTH/8` at
  `:68-69`).

**Target behavior — two parts:**

**(5a) SPI verification/repair to true 20 MHz / 60 fps.** Using §1's measurement,
audit the SYNC_TX path against the authoritative
`%11100 Sync Serial Transmit` reference:
- Confirm clock routing (`P_PLUS2_B`) and edge polarity match the SSD1351's
  expected SPI mode (CPOL/CPHA); apply `P_INVERT_A`/`P_INVERT_B` only if the
  measurement/scope shows wrong-edge latching.
- Confirm the continuous-mode init order matches the reference (enable → prime →
  buffer → poll IN); confirm the double-buffered feed never starves (the IN-flag
  poll at `:695` must keep ahead of the shifter — buffer underrun shows as
  tearing/banding).
- Confirm `clk_period` (`:731`) yields 20 MHz at 250 MHz CLKFREQ and the
  companion `P_PULSE` SCLK burst length (`TOTAL_FRAME_PULSES`) exactly matches
  the streamed long count.
- If the measurement shows the config is already correct and ≥ 60 fps, this
  reduces to documenting the confirmed baseline.

**(5b) Generalize render to N×N.** Parameterize `render_to_pixel_buffer()` and
the LUTs on `FIELD_RES`:
- `SENSOR_GRID_SIZE` (`:66`) → `FIELD_RES`; `CELL_WIDTH/HEIGHT = 128 / FIELD_RES`
  (16 / 8 / 4 px — all integer, since 128 = 8·16 = 16·8 = 32·4).
- `cell_count`, `cell_origin_lut[]` (`init_cell_origin_lut()` at `:220`) sized
  `FIELD_RES²`.
- The inline-PASM cell fill loop (`:483+`) generalized to `FIELD_RES²` cells of
  `CELL_WIDTH×CELL_HEIGHT` px. Full-frame 128×128 stream (§2-invariant)
  unchanged — so 5b does **not** change OLED frame time.
- Color transfer applied here comes from §7 (Axis C).

**Certified by:** rung **T6** — `measure_sclk_rate()` (SCLK ~20 MHz),
`test_oled_performance.spin2` (**fps ≥ 60**), `test_oled_alignment.spin2` + a
known N×N tiling pattern (no seam/remainder at RES=32).

**Integration points:** reads §1-config (`FIELD_RES`, `FIELD_COLOR`); consumes
§4-sized frames; uses §7 color module. `stream_pixel_buffer()` is untouched by
5b (resolution-independent).

**Verification:**
- *Normal:* `measure_sclk_rate()` reports ~20 MHz; `test_oled_performance.spin2`
  reports **≥ 60 fps**; `FIELD_RES=32` renders a smooth 32×32 field with correct
  alignment.
- *Edge:* at `FIELD_RES=32`, 4×4-px cells tile the 128×128 buffer exactly with no
  remainder row/column; first-frame alignment matches `FIELD_RES=8`.
- *Error:* buffer underrun (COG falls behind shifter) → tearing/banding; guarded
  by keeping the fill loop ≪ the SPI budget (per Performance-Analysis, ~14-tick
  COG loop vs ~400-tick SPI budget per long) and by the §1 visual check.

---

### § 6 — HDMI: scanline render, N×N grid, analytical overlay 🔧 largest chunk

**Why:** HDMI renders the grid with **per-cell `FillRect`**. At `FIELD_RES=32`
that is 1,024 `FillRect` calls per frame — too many to render within the 60 Hz
budget. HDMI is also the display with room for text and lines, so it hosts the
Axis-C analytical annotations.

**Current code:**
- Render loop `isp_hdmi_display_engine.spin2:237-252`: nested `row/col` `0..7`
  → `gfx.FillSensorCell(...)` per cell. `SENSOR_GRID_SIZE=8` at `:24`,
  `CELL_SIZE=30`, `CELL_GAP=3`, `GRID_X/Y` at `:28-31`. Grid area = 8·33 = 264 px.
- `gfx.FillSensorCell` (`isp_psram_graphics.spin2:272`) → `FillRect` (`:138`)
  → per-row PSRAM writes. `DrawSensorGrid` at `:244`.
- Color: `field_to_color()` at `isp_hdmi_display_engine.spin2:401`.
- Stats overlay already exists: `CalculateFrameStats` (`:299`), `DrawDynamicStats`
  (`:327`), `DrawText`/`DrawTextCentered` (`isp_psram_graphics.spin2:366,392`).

**Target behavior:**
- **Scanline renderer** for the grid: for each of the 264 grid-area pixel rows,
  compute each pixel's `N×N` cell value → color once, write the whole row to
  PSRAM in one operation. Replaces `64/256/1024` `FillRect` calls with 264 row
  writes (constant regardless of `FIELD_RES`) — the optimization
  Performance-Analysis §"scanline rendering" already identified. Cell size =
  `264 / FIELD_RES` (33 / 16.5 / 8.25 px — use fixed-point cell mapping so
  non-integer cell widths tile without gaps).
- `SENSOR_GRID_SIZE` → `FIELD_RES` in the render path; cell-index from pixel via
  fixed-point step.
- **Analytical overlay (Axis-C support):** a **color-scale legend** (the active
  `FIELD_COLOR` mapping as a labeled gradient bar) and a **numeric peak/min
  readout** drawn via existing `DrawText`. For `FIELD_COLOR=GRADIENT`, the legend
  labels |∇B|; for `LOG`, labels the log scale.

**Certified by:** rung **T7** — `test_hdmi_scanline.spin2` (known N×N pattern →
264-px tiling has no gaps at non-integer cell widths; render within budget, no
FIFO backpressure). `P_RAW` scanline output matches the pre-sprint per-cell
render.

**Integration points:** reads §1-config (`FIELD_RES`, `FIELD_COLOR`); consumes
§4-sized frames; uses §7 color module for pixel color and legend. New scanline
routine lives in `isp_psram_graphics.spin2` (shared graphics object) as
`FillSensorGridScanline(...)` so it's reusable and testable.

**Verification:**
- *Normal:* `FIELD_RES=8` scanline output visually matches the current per-cell
  render (regression); `FIELD_RES=32` renders 1024 distinct cells with no seams;
  legend + peak readout correct and readable.
- *Edge:* non-integer cell width at `FIELD_RES=16,32` (16.5 / 8.25 px) tiles the
  264-px area with no gap or overrun (fixed-point accumulation, last cell clamps
  to the boundary).
- *Error:* render must complete within the HDMI content budget (~15 ms per
  Performance-Analysis) so the engine keeps pace with its FIFO — measure with the
  engine's existing stack/timing instrumentation; a too-slow scanline shows as
  HDMI FIFO backpressure.

---

### § 7 — Shared color-transfer module (Axis C) (`isp_field_color.spin2`) 🆕

**Why:** Axis C is where field **strength** and **derived structure** become
visible. Four transfer functions ship this sprint; each answers one of Stephen's
three questions. Both displays must map identically, so the transfer logic is
shared.

**Current code:** Two independent linear-bipolar mappers exist —
`value_to_color()` (OLED, via `color_lut[4096]` built by `init_color_lut()` at
`isp_oled_single_cog.spin2:219`) and `field_to_color()` (HDMI,
`isp_hdmi_display_engine.spin2:401`). The "10× amplified" concept and bipolar
red/green are described in `DOCs/MagSensor-Color-Mapping-Specification.md`. No
log, high-gain-as-a-mode, or gradient mapping exists.

**Target behavior — new shared object `src/isp_field_color.spin2`:**
- `build_transfer_lut(dstPtr, mode)` — builds a 4096-entry (or field-range)
  RGB565 LUT for the pure point-wise transfers, selected by `FIELD_COLOR`:
  - `BIPOLAR` — existing symmetric red(neg)/green(pos); honest relative strength.
  - `HIGHGAIN` — deviation × gain before mapping; pulls weak **far-field** signal
    into visible range (generalizes the "10×" concept into a mode).
  - `LOG` — `sign · log(1 + k·|dev|)` compressed; shows strong **near-field peak
    and weak far-field tail simultaneously** (dynamic range).
- **`GRADIENT`** is *spatial*, not a point LUT: computed at render time on the
  `N×N` grid. Central differences `(dB/dx, dB/dy)` per interior cell →
  **`QVECTOR` → `GETQX` = |∇B|** (CORDIC magnitude; issue one op per 8-clock hub
  window, retrieve 55 clocks later — **pipeline across cells** so the 55-clock
  latency overlaps). |∇B| → intensity color. Highlights where the field changes
  fastest → **localizes near-field sources / pole edges**. Border cells use
  one-sided differences.
- Both `value_to_color`/`field_to_color` refactored to consult the shared LUT
  (point-wise modes) or call the shared gradient helper (`GRADIENT`).

**Shared-component rationale:** OLED and HDMI must agree on the mapping; a shared
LUT builder + gradient helper avoids two drifting copies. Built shared from the
start.

**Certified by:** rung **T3** — `test_field_color.spin2` golden values (catalog
in §4): BIPOLAR/HIGHGAIN/LOG LUT values + GRADIENT |∇B| via `QVECTOR`. Each
color arm lands with its example + edge case in the same task.

**Integration points:** reads `FIELD_COLOR`; called by §5 (OLED render) and §6
(HDMI render + legend). The `FIELD_COLOR` `case` is the **Axis-C extension
point** for § Deferred's `CONTOUR` mode (adds one arm + an HDMI line-drawing overlay).

**Verification:**
- *Normal:* each of the four modes produces the expected visual — `BIPOLAR`
  symmetric; `HIGHGAIN` saturates a strong source while revealing a weak one;
  `LOG` shows both peak and tail; `GRADIENT` rings the source location.
- *Edge:* `GRADIENT` border cells (one-sided difference) do not produce spurious
  edge halos; `LOG`/`HIGHGAIN` clamp to RGB565 range without wraparound; zero-field
  frame maps to the neutral midpoint in every mode.
- *Error:* `QVECTOR` result read before 55 clocks → wrong magnitude; guarded by
  the pipelined issue/retrieve structure with an explicit latency comment and a
  self-test asserting |∇B| of a known ramp.

---

### § 8 — Compile-time mode configuration (`isp_field_config.spin2` shared include) 🆕

**Why:** The three axes must be selected once, consumed by many objects
(decimator, FIFO, both displays), and validated for illegal combinations — with
a clean path to becoming runtime knobs.

**Current code:** No conditional compilation is used anywhere in `src/*.spin2`
(`grep` for `#ifdef|#define` returns nothing). Configuration is scattered as
per-object `CON` (`SENSOR_GRID_SIZE` in three files, decimation defaults in the
viewer).

**Target behavior:** A shared, `#include`-able config file
`src/isp_field_config.spin2` holding:
- The three axis symbols with a single active `#define` each (`FIELD_RES_32`,
  `FIELD_KERNEL_CATMULL`, `FIELD_COLOR_LOG`, …), plus derived `CON`s
  (`FIELD_RES`, `FRAME_SIZE`, tap counts).
- **Guards** via `#error` for illegal combinations (e.g. `LANCZOS3` with
  `FIELD_RES < 16`; missing default per the P2KB "missing_default_case"
  anti-pattern) and a `#error` if no axis value is defined.
- Named **preset bundles** (documented, one active) that each answer a question:

| Preset | RES | KERNEL | COLOR | Reveals |
|---|---|---|---|---|
| `P_RAW` | 8 | NEAREST | BIPOLAR | Ground truth — what the sensors read |
| `P_STRENGTH` | 16 | BILINEAR | BIPOLAR | Honest relative strength, mild smoothing |
| `P_NEAR_SHARP` | 32 | LANCZOS3 | BIPOLAR | Near-field sharp reconstruction |
| `P_NEAR_LOCATE` | 32 | BILINEAR | GRADIENT | Pinpoint source via |∇B| |
| `P_FAR_SMOOTH` | 32 | CATMULL | HIGHGAIN | Far-field weak signal |
| `P_FAR_RANGE` | 32 | CATMULL | LOG | Full dynamic range: near + far together |

- Full `FIELD_RES∈{16,32} × FIELD_KERNEL∈{BILINEAR,CATMULL}` and the four color
  modes remain independently selectable beyond the presets.

**Runtime-ready design:** the config resolves to `CON`/`#define` values that the
decimator (§3) and displays (§5,§6,§7) consume through `case` dispatch. § Deferred's
runtime control replaces the compile-time pin with a live variable feeding the
same `case` — **no dispatch rewrite**.

**Certified by:** rung **T1** — the preset-matrix build gate (compile all 6
presets green; assert every illegal combo emits its intended `#error`).

**Integration points:** `#include`d by `isp_field_interpolate`,
`isp_frame_fifo_manager`, `mag_tile_viewer`, `isp_hdmi_display_engine`,
`isp_oled_single_cog`. (Confirm `pnut-ts` `#include` resolution of a `.spin2`
config across the object set during §-start; the P2KB preprocessor overview
documents `#INCLUDE` support.)

**Verification:**
- *Normal:* each of the six presets compiles green and produces its intended
  build; `pnut-ts -d mag_tile_viewer.spin2` succeeds for every preset.
- *Edge:* switching a single axis (e.g. `FIELD_COLOR` only) recompiles without
  touching other axes — proves independence.
- *Error:* an illegal combo (`LANCZOS3`+`RES 8`) and an empty selection each
  fail at compile time with the intended `#error` message — a build that
  can't misconfigure silently.

---

### § 9 — System Specification (`DOCs/System-Specification.md`) 📄 doc deliverable

> **Update (2026-07-09):** the spec has since been **authored** during a
> documentation-reconciliation pass and is now the living design-intent doc. This
> deliverable is therefore reduced to *keeping it current* — updating the "shipped
> modes" and moving items out of its Deferred/Roadmap section as they land — not
> authoring from scratch.

**Why:** The project has per-subsystem docs but no system-wide target spec, and
`SPEC_DOC` in `.claude/skill-conventions.md` points at the current stub. Stephen
designated this sprint's goals as the authoritative project intent: "these are
the goals for the project, and so the system specification — if it doesn't say
this, it should be updated."

**Current code/doc:** `DOCs/System-Specification.md` is a 550-byte stub;
`DOCs/PUNCH-LIST.md` already lists "Write the system-wide project specification."

**Target behavior:** Author the full spec: scope and two purposes (low-cost
visualizer; max-frame-rate exploration); the sensor→decimate→interpolate→display
pipeline; the **three exploration axes** and the near/far/strength intent; the
per-display roles (OLED = rich reconstructed color image; HDMI = annotated
analytical view); performance targets (sensor ~1,370 fps, HDMI 60 Hz, **OLED
≥ 60 fps**); COG allocation; interfaces between subsystems; and a **"Deferred /
Roadmap"** section (§ Deferred content) naming the anticipated future work and the
extension points built for it.

**Integration points:** draws from `DOCs/Theory-of-Operations/`,
`DOCs/Architecture/`, `DOCs/status-reports/Object-Architecture-As-Built.md`, and
this plan. Removes the punch-list "write the spec" item at closeout.

**Verification:**
- *Normal:* spec states all three axes, the modes shipped, the measured OLED
  goal, and the deferred roadmap; a reader can derive "where we are heading" from
  it alone.
- *Edge:* spec and code agree on shipped modes (spec does not claim contour/
  temporal/runtime as present — they appear only under Deferred).
- *Error:* n/a (doc) — reviewed against the as-built at closeout.

---

### § 10 — Conformance, docs refresh, and version 📄

**Why:** New/touched `*.spin2` are born conforming; the performance doc and
changelog reflect reality.

**Target behavior:**
- All new files (`isp_field_interpolate`, `isp_field_color`, `isp_field_config`)
  and all touched files brought to `SPIN2-AUTHORING-GUIDE.md` (Part 4 doc blocks,
  §5.2 single-exit, CON for magic numbers, ASCII-only debug). `pnut-ts -d` green
  for every in-scope file and every shipped preset.
- Update `DOCs/analysis/Performance-Analysis.md` with the §1 measured OLED
  numbers and the interpolation/render cost of the new modes (correcting the
  stale "OLED ~55 fps / display_frame_fast disabled" text — that path is now
  live).
- `BUILD_VERSION` bump handled by `build-wrapup` at closeout (currently "0.5.0"
  in `mag_tile_viewer.spin2:47`).

**Verification:**
- *Normal:* every in-scope file and preset compiles green; guide-conformance
  spot-check passes.
- *Edge:* the `NEAREST/RES 8` regression build is byte-compatible with pre-sprint
  behavior (proves no regression to the shipped baseline).
- *Error:* any file left non-conforming or any preset failing to compile blocks
  closeout.

---

## 6. Deferred / roadmap (this sprint builds the seams; does NOT implement)

Each item below is **architecturally anticipated** — it lands at a named
extension point this sprint creates — and is **written into
`DOCs/System-Specification.md` §Deferred as intended future work**. None is
partially built here.

| Deferred item | Extension point built this sprint | Lands as |
|---|---|---|
| **Contour / isoline color mode** | Axis-C `FIELD_COLOR` `case` (§7) + HDMI overlay hook (§6) | One color `case` arm + HDMI line-drawing overlay |
| **Temporal modes** (multi-frame averaging, peak-hold) | Decimator processing `case` (§3), already stubbed as `MODE_AVERAGING`/`MODE_PEAK` | New processing-mode arms feeding the same upsample path |
| **Additional kernels** (smoothstep/cosine, B-spline, Mitchell) | Polyphase coefficient-table dispatch (§2) | New `DAT` coefficient table + `FIELD_KERNEL` arm |
| **Runtime push-button control** | Compile-time-pinned `case` dispatch on all three axes (§3,§5,§6,§7,§8) | Replace `#define` pins with live variables feeding the same `case`s |

**Per-arm test discipline carries to the roadmap:** when any deferred kernel or
color arm is later added, it lands with its golden test vector(s) in the shared
harness in the same task (§4 rule) — the arm is not "done" until its example +
edge case are asserting green. The shared scaffolding (`test_field_support.spin2`)
makes each future proof a table addition.

---

## 7. Verification summary (sprint-level)

Verification is the **§4 certification ladder** — each rung (T1…T8) is
self-checking and gates the rung above it; nothing is wired together until its
inputs are proven. Sprint-level anchors:

- **Bottom-up gates:** T1 config → T2 resampler → T3 color → T4 FIFO → T5
  decimator → T6 OLED ∥ T7 HDMI → T8 system. Each green before the next.
- **Golden-vector nets (cheapest, first):** T2/T3 assert each algorithm arm
  against hand-computed goldens (catalog in §4); every new `case` arm ships with
  its own example + edge case in the same task.
- **Regression anchor:** `P_RAW` (`RES 8 / NEAREST / BIPOLAR`) reproduces
  pre-sprint behavior — threaded through T4, T5, T7, T8 and
  `test_fifo_regression.spin2`.
- **Measured goal:** OLED ≥ 60 fps on the P2 Edge board (T6) via
  `measure_sclk_rate()` (~20 MHz SCLK) and `test_oled_performance.spin2`.
- **Feature proof:** all six presets compile green (T1) and each renders its
  intended reveal on both displays (T8); the illegal/empty configs fail at
  compile time.
- **Test-playbook** (authored separately via the `test-playbook` skill) enumerates
  the T8 per-preset board exercises.

## 8. Open questions

None. Scope, the three-axis model, the shipped mode set, the deferred set and
its extension points, and the measured OLED goal are all confirmed. Research is
complete; this plan is ready for `sprint-start`.
