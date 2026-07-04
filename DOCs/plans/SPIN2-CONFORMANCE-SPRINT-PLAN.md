# Spin2 Conformance Sweep — Sprint Plan

**Goal:** Bring every Spin2 source file we author into full conformance with `DOCs/policy/SPIN2-AUTHORING-GUIDE.md` so future agent-driven work has a stable, predictable baseline.

**Doc bar:** Full conformance (Option A) — every PUB and PRI gets a complete doc block per the guide's Part 4. Where good prose already exists, preserve it; where missing, write from reading the code.

**Delivery:** One commit at sprint end. Every in-scope file MUST compile cleanly (current baseline: 38/38 in-scope files green).

**Risk profile:** Static refactor. No new features. No behavior changes. Where control-flow restructure is required (early-return → single-exit), behavior must be identical.

---

## § Key decisions (resolved 2026-05-27)

These were decided before the plan was finalized; affected deliverables reference them inline.

- **Outgoing build number:** `0.6.0` (minor bump from `0.5.0`). Agreed at sprint-start because Q1's full-sweep rename of `cogId`/`string`/`send` includes PUB methods — that's a public-API change even though only internal consumers exist. The actual `BUILD_VERSION` constant in `src/mag_tile_viewer.spin2` is bumped at sprint closeout by `build-wrapup`, not in this sprint's commits.
- **Version directive:** None — no in-scope file uses a versioned feature. Resolved per guide §3.1.1 rule 3 (audit confirmed: no typed pointers, no STRUCT, no LSTRING, no new-style DEBUG).
- **Built-in collision renames (`cogId`, `string`, `send`):** Full sweep — rename declaration sites AND every consumer in this sprint's single commit. See §5.
- **File-header template:** `isp_oled_single_cog.spin2`. Use its `''` header layout, copyright/email block, and overall shape; fix the `Author.....` (singular) → `Authors....` (plural) mismatch in the template before propagating. See §2.
- **PUB-before-PRI fix for `isp_psram_graphics.spin2`:** In scope this sprint. Real method relocation (large diff, behavior-equivalent). See §7d.

---

## § Sprint-start entry checks (2026-05-27)

Recorded by the `sprint-start` skill at execution kickoff. The exit baseline at `sprint-closeout` must not regress against these numbers.

**Tracking-readiness — READY.** todo-mcp tasks: 0. todo-mcp context: 0 keys / 0 bytes. Auto-memory: 2 files (+ MEMORY.md at 2 lines, far under the 150-line audit threshold). Pruned the now-superseded `project_session_resume_2026-05-27.md` checkpoint memory; sprint memory `project_spin2_conformance_sweep_2026-05.md` retained. No leftover pending/in-progress tasks to fold in.

**Baseline-health — GREEN, no regressions to fix before the sprint.**
- Build (`pnut-ts -d mag_tile_viewer.spin2`): clean, 0 warnings.
- Test (`pnut-ts -d test_fifo_regression.spin2`): compiles clean. Runtime execution requires the canonical P2 Edge target and is not part of the entry baseline.
- In-scope compile sweep: **38/38 in-scope files compile cleanly with `pnut-ts -d`.** This is the load-bearing baseline for this refactor sprint — each per-file edit must keep this 38/38 green.
- Skipped/gated — named explicitly per §3 of the baseline-health skill: the 4 broken-at-HEAD test files (`test_fifo_pipeline.spin2`, `test_hdmi_via_graphics.spin2`, `test_oled_performance.spin2`, `test_pin_toggle.spin2`) are not exercised this sprint, by §1 scope decision. They are not silently "passing" — they will not compile until separately fixed, and that fix is out of scope here.

**Outgoing build number — pinned at `0.6.0`** (decided at plan time per §Key decisions; confirmed at sprint-start). `BUILD_VERSION` constant in `src/mag_tile_viewer.spin2` stays at `0.5.0` through the sweep and is bumped to `0.6.0` by `build-wrapup` at closeout.

---

## § 1. Sprint scope

**In scope — 38 files in `src/`:**

Libraries (11):
- `isp_frame_fifo_manager.spin2`, `isp_frame_transform.spin2`, `isp_hdmi_640x480_24bpp.spin2`, `isp_hdmi_display_engine.spin2`, `isp_oled_driver_bitbang.spin2`, `isp_oled_driver.spin2`, `isp_oled_manager.spin2`, `isp_oled_single_cog.spin2`, `isp_psram_graphics.spin2`, `isp_stack_check.spin2`, `isp_tile_sensor.spin2`

Top-level app (1):
- `mag_tile_viewer.spin2`

Regression / perf tests (4):
- `test_fifo_regression.spin2`, `test_fifo_stress.spin2`, `test_framerate.spin2`, `test_tile_sensor_adc.spin2`

Display tests (8):
- `test_chip_hdmi.spin2`, `test_grid_8x8.spin2`, `test_hdmi_chip_pattern.spin2`, `test_hdmi_hub_pattern.spin2`, `test_hdmi_minimal.spin2`, `test_hdmi_simple_fill.spin2`, `test_hdmi_text_only.spin2`, `test_psram_300mhz.spin2`

OLED tests (5):
- `test_oled_alignment.spin2`, `test_oled_minimal.spin2`, `test_oled_simple.spin2`, `test_oled_single_cog.spin2`, `test_outa_debug.spin2`

Pin / PSRAM / sensor tests (9):
- `test_p8_only.spin2`, `test_pin_binary.spin2`, `test_pin_direct.spin2`, `test_pin_mapping.spin2`, `test_pins_8_12.spin2`, `test_pins_mask.spin2`, `test_pin_toggle_simple.spin2`, `test_psram_only.spin2`, `test_psram_readback.spin2`

**Excluded — vendor / imported (5) — DO NOT MODIFY:**

`PSRAM_driver_RJA_Platform_1b.spin2`, `ref_hdmi_640x480_24bpp.spin2`, `chip_hdmi_640x480.spin2`, `psram_driver.spin2`, `isp_hub75_fonts.spin2`

**Excluded — broken at HEAD, set aside by user (4) — NOT TOUCHED THIS SPRINT:**

`test_fifo_pipeline.spin2` (deleted-object ref), `test_hdmi_via_graphics.spin2` (signature mismatch), `test_oled_performance.spin2` (calls private method), `test_pin_toggle.spin2` (calls non-existent method)

**Inventory check:** 38 in-scope + 5 vendor + 4 broken = 47 total `.spin2` files in `src/`. Matches `ls src/*.spin2 | wc -l`.

---

## § 2. File preamble — `''` file header (no version directive)

**Why:** Guide §3.1 (file layout — header block at top), §4.2 (file header is `''` with File/Purpose/Authors/E-mail/Started/Updated). The `''` header makes the file's purpose visible in the extracted API document.

**Version directive — resolved per guide §3.1.1.** Audit confirmed zero in-scope files use any feature requiring a `{Spin2_v##}` directive:
- No typed pointer syntax (`^BYTE`/`^WORD`/`^LONG`/`^structname` — would require v45)
- No `STRUCT` declarations
- No `LSTRING` literals
- No backtick-prefixed DEBUG window invocations

Per the new §3.1.1 rule 3, no directive will be added to any of the 38 in-scope files. If a future feature is adopted, the directive gets added at that moment (rule 1) and bumped if a higher-requiring feature joins later (rule 2).

**Header current state (audit):** Only `isp_stack_check.spin2` has a strictly conforming `''` header. The other 37 use a mix of: no header, informal `'` comment headers, or `''` headers with `Author....` singular vs the required `Authors....` plural.

**Template choice (resolved):** `isp_oled_single_cog.spin2` is the template. Before propagating, fix its `Author.....` (singular) → `Authors....` (plural) so the template itself matches §4.2. The richer copyright/email block in that file's header is preserved across all 38.

**Target:** Every in-scope file begins with (header starts on line 1, no directive above it):

```
'' =================================================================================================
''
''   File....... <filename>.spin2
''   Purpose.... <one-sentence purpose>
''   Authors.... Stephen M Moraco
''               -- Copyright (c) 2025 Iron Sheep Productions, LLC
''               -- see below for terms of use
''   E-mail..... stephen@ironsheep.biz
''   Started.... <month year>
''   Updated.... <month year>
''
'' =================================================================================================
```

Purpose lines come from the existing file's content. Started/Updated dates come from `git log --follow --diff-filter=A` for created and `git log -1` for last modified.

**Verification:** Compile every file after edit. Confirm no file in scope has `{Spin2_v##}` on line 1 (per §3.1.1 rule 3, none should). Spot-check 3 files visually against the §4.2 example header.

**Guide rules enforced:** §3.1 (file layout), §3.1.1 (when to use `{Spin2_v##}` — rule 3: no directive when no versioned features used), §4.2 (file header structure), §4.1 (`''` is the correct marker for doc-extracted content).

---

## § 3. Block declaration labels — `' ---- Label ----` on every CON/DAT/VAR/OBJ

**Why:** Guide rule §4.5 — block-declaration comments appear in VS Code Outline. They are navigation aids and require the `---- Label ----` dash format. Bare `CON` / `DAT` / `VAR` / `OBJ` lines show up as anonymous nodes in the Outline.

**Current state:** Every in-scope file has at least 1 unlabeled block declaration. Top offenders:
- `isp_psram_graphics.spin2` — 6 unlabeled blocks
- `isp_oled_single_cog.spin2` — 4
- `test_fifo_stress.spin2` — 4
- 14 files — 3 each
- 13 files — 2 each
- 8 files — 1 each

Audit-confirmed: zero files have decorative borders (`═══`, `───`) on block declaration lines, so no border-stripping needed. The ad-hoc plan's "strip decorative borders" task is a no-op.

**Target:** Every `CON`, `DAT`, `VAR`, `OBJ` declaration carries a `' ---- <Label> ----` tag describing what's in the block:

```
CON ' ---- Pin Assignments ----
DAT ' ---- Singleton State ----
VAR ' ---- Per-instance State ----
OBJ ' ---- Subsystem Objects ----
```

Where a file has a public-API CON block (error codes, mode enums, sizes), add `{Spin2_Doc_CON}` directive on the FIRST LINE INSIDE the block (not on the declaration line itself — guide §4.5).

**Verification:** `grep -E '^(CON|DAT|VAR|OBJ)\s*$' src/*.spin2` should match only excluded files.

**Guide rules enforced:** §4.5 (block declaration labels, `{Spin2_Doc_CON}` placement), §4.9 (no horizontal lines inside CON blocks — audit confirmed no current violations).

---

## § 4. Method documentation — PUB and PRI doc blocks

**Why:** Guide §4.3 (PUB style), §4.4 (PRI style). PUB doc-comments use `''` and are extracted to `.txt` API documents and IntelliSense. PRI doc-comments use `'` and are internal-only. Both require the same structure: description → blank separator → `@param`/`@returns` → blank line → `' Local Variables:` → `@local` tags → blank line → code.

**Current state (audit):**
- PUB methods (in-scope): ~170+ across 38 files. Top counts:
  - `isp_psram_graphics.spin2` — 18 PUB
  - `isp_oled_driver.spin2` — 18 PUB
  - `isp_tile_sensor.spin2` — 16 PUB
  - `isp_frame_fifo_manager.spin2` — 14 PUB
  - `isp_oled_driver_bitbang.spin2` — 12 PUB
  - `isp_oled_single_cog.spin2` — 9 PUB
  - `isp_oled_manager.spin2` — 8 PUB
  - `isp_stack_check.spin2` — 7 PUB
- PRI methods (in-scope): ~110+. Top counts:
  - `isp_oled_single_cog.spin2` — 17 PRI
  - `isp_oled_driver.spin2` — 10 PRI
  - `isp_oled_driver_bitbang.spin2` — 9 PRI
  - `isp_psram_graphics.spin2` — 8 PRI
  - `isp_hdmi_display_engine.spin2` — 7 PRI
- Audit-confirmed: zero PRI methods use `''` (FORBIDDEN per §4.4) — no marker-swap needed.

**Target structure per PUB:**

```
PUB methodName(param1, param2) : returnVar | local1, local2
'' One-sentence description starting with a verb.
''
'' @param param1 - description of param1
'' @param param2 - description of param2
'' @returns returnVar - description of what comes back

' Local Variables:
' @local local1 - description
' @local local2 - description

    <method body — blank line before first executable line>
```

Same shape for PRI, with `'` instead of `''` for description / `@param` / `@returns` (locals always use `'`).

**Rules to honor (§4.3, §4.4):**
- Blank `''` separator after description even when there are no `@param`/`@returns` (void methods get description + blank `''` + blank line + body).
- No `@param` for nonexistent params, no `@returns` for void methods, no `@local` when there are no locals.
- Blank line before first line of code is REQUIRED.
- Every `@param` name matches a signature param exactly. Every `@returns` name matches a return variable exactly.
- Same parameter name → identical description across all methods (Rule 2.5).

**Preserve existing prose** where it's adequate. Write fresh descriptions where missing — read the code, describe what it does in one sentence.

**Verification:** Spot-check a representative library (`isp_tile_sensor.spin2`) and a representative test (`test_fifo_regression.spin2`) against the §4.3/§4.4 examples after the sweep. Compile each file after editing.

**Guide rules enforced:** §4.1 (comment types), §4.3 (PUB doc block), §4.4 (PRI doc block), §2.5 (same parameter name = same description).

---

## § 5. Identifier rehabilitation

**Why:** Guide rules §1.3 (no built-in name collisions), §2.1 (no single-letter names), §2.2 (no generic container names), §2.3 (return variables named for the data they carry), §1.5/§1.6 (no shadowing of methods/DAT/VAR).

**Current state (audit):**

| Violation | Files | Sites |
|---|---|---|
| `success` as return variable (§2.3) | `isp_oled_single_cog.spin2`, `isp_tile_sensor.spin2` | 2 |
| `success` as local var (§2.2) | `mag_tile_viewer.spin2` | 1 |
| `cogId` identifier (§1.3 — collides with COGID) | 10 in-scope files | ~10–15 |
| `string` identifier (§1.3 — collides with STRING()) | 4 in-scope files | ~4–6 |
| `send` identifier (§1.3 — collides with SEND) | 7 in-scope files | ~7–12 |
| Generic locals (`temp`, `value`, `data`, `result`, `buf`, `info`, `ret`) | 8 files | ~13 sites |
| Single-letter sig params (excluding `i`/`idx`/`x`/`y` loop indices) | `isp_oled_driver.spin2` | 1+ |
| `bool` as identifier (§1.3) | 0 | 0 |

**Target renames (full-sweep scope per Key Decisions):**

- `success` (return var) → `status`
- `success` (local) → `status` or context-specific name
- `cogId` → `workerCog`, `myCogId` (context-dependent)
- `string` → `pStr`, `pText`, `textBuf` (context-dependent)
- `send` → `sendData`, `transmit` (context-dependent)
- `temp`/`value`/`data`/`result`/`buf`/`info`/`ret` → name-the-data per guide §2.2 table
- Single-letter sig params → describe-the-data (guide §2.1 examples: `pEntry`, `maxEntries`)

**Rename scope:** Full sweep — when a renamed identifier is a PUB method on a driver object, every caller in the codebase is updated in the same patch. No two-step migration; the working tree must compile clean at every intermediate commit-able state.

**Shadowing check (§1.5, §1.6):** As a sweep deliverable, verify no local var name matches a PUB/PRI method or DAT/VAR name in the same file. Audit not yet run — discovery work for the executor.

**Built-in collision check (§1.3 — full list):** Beyond `cogId`/`bool`/`string`/`send`, the executor verifies no identifier collides with PASM2 instruction mnemonics or other Spin2 reserved words in each touched file.

**Verification:** Each rename must compile. After all renames land, build every in-scope file and `test_fifo_regression.spin2` to confirm caller-side updates are complete.

**Guide rules enforced:** §1.3, §1.5, §1.6, §2.1, §2.2, §2.3, §2.5.

---

## § 6. Single exit point — eliminate early returns

**Why:** Guide §5.2 — early `return` makes `debug()` instrumentation unreliable because debug calls placed after early returns silently never execute. Single-exit guarantees the last line runs on every path. §5.3 — never `return` from inside a `repeat` loop; use `quit` with a status variable.

**Current state (audit — early `return X` statements per file):**

| File | Count |
|---|---|
| `isp_frame_fifo_manager.spin2` | **33** |
| `isp_tile_sensor.spin2` | **12** |
| `isp_oled_single_cog.spin2` | 5 |
| `isp_oled_manager.spin2` | 5 |
| `test_tile_sensor_adc.spin2` | 3 |
| `test_fifo_stress.spin2` | 3 |
| `isp_oled_driver.spin2` | 3 |
| `isp_hdmi_display_engine.spin2` | 3 |
| `isp_psram_graphics.spin2` | 2 |
| `isp_oled_driver_bitbang.spin2` | 1 |
| `isp_hdmi_640x480_24bpp.spin2` | 1 |
| `isp_frame_transform.spin2` | 1 |

The ad-hoc plan underestimated this — `isp_frame_fifo_manager.spin2` has 33 early returns (not 10), and `isp_tile_sensor.spin2` (12) wasn't called out at all.

**Target pattern:** Replace each early `return X` with assignment-and-fall-through:

```
' BEFORE
PRI doThing() : status
    if not preCheck()
        return E_BAD_PRECHECK
    status := work()
    if status < 0
        return status
    status := SUCCESS

' AFTER
PRI doThing() : status
    status := E_BAD_PRECHECK
    if preCheck()
        status := work()
        if status >= 0
            status := SUCCESS
```

For early returns inside `repeat` loops, set the status variable and use `quit`. For doubly-nested loops, set the status, `quit` the inner loop, check status, `quit` the outer loop.

**Special attention — `isp_frame_fifo_manager.spin2`:** With 33 early returns, the restructuring is substantial. The executor MUST compile after each method restructured (not at end-of-file) so a broken pattern is caught immediately.

**Behavior preservation:** Restructured code must behave identically. The acceptance test: any debug output a method produced before restructure produces the same output after.

**Verification:** `grep -cE "^\s*return\s+\S" src/*.spin2` should drop to 0 for every in-scope file. Compile after every file. Run `test_fifo_regression.spin2` after the fifo manager is restructured — it's the integration test for that file.

**Guide rules enforced:** §5.2, §5.3.

---

## § 7. Coding practices — magic numbers, boolean precision, default-assign returns, PUB-before-PRI

**Why:** Guide §5.1 (return variables must be explicitly assigned), §5.4.1 (boolean precision — TRUE/FALSE, not 1/0), §5.7 (no magic numbers), §3.2 (PUB before PRI).

**§ 7a. Magic number cleanup (§5.7)**

Audit — loop bounds `repeat ... from 0 to <bare integer>` per file:

| File | Sites |
|---|---|
| `test_grid_8x8.spin2` | 14 |
| `test_oled_single_cog.spin2` | 10 |
| `isp_oled_manager.spin2` | 7 |
| `isp_psram_graphics.spin2` | 6 |
| `isp_oled_single_cog.spin2` | 5 |
| `isp_hdmi_display_engine.spin2` | 5 |
| `isp_tile_sensor.spin2` | 4 |
| `isp_oled_driver.spin2` | 4 |
| 6 more files with 2 each | 12 |

Target: every loop bound becomes a named CON (`PIXELS_PER_ROW`, `MAX_FRAMES`, `DISPLAY_HEIGHT - 1`, etc.). Magic numbers in protocol values (hex constants), display dimensions (640, 480, 128), timeouts, and array sizes also get named CONs. Permitted bare literals: 0, -1, 4 (LONG-to-byte factor) — per guide §5.7 table.

**§ 7b. Boolean precision (§5.4.1)**

Audit: only `isp_frame_fifo_manager.spin2` flagged (returns/assigns bare `1` or `0` in suspect contexts). Verify each site is actually a boolean (not a count/status). Where it's a boolean, replace with `TRUE`/`FALSE`. Where it's a count, leave alone.

**§ 7c. Default-assign return variables (§5.1)**

Sweep deliverable: every declared return variable must be explicitly assigned at method entry to a sensible default (typically an error code or sentinel). No implicit zero-init.

Audit not run per-method — discovery work for executor. Common pattern after sweep:

```
PUB doSomething() : status
    status := E_NOT_INITIALIZED          ' explicit default
    ...
```

**§ 7d. PUB-before-PRI reorganization (§3.2)**

Audit: only `isp_psram_graphics.spin2` violates Rule 3.2 (first PRI at line 317, then a PUB at line 418). Per Key Decisions, fix in this sprint: relocate the late-arriving PUB methods above the PRI section. Behavior is unchanged; the diff is large. Compile immediately after relocation to verify nothing broke.

**Verification:** Compile after every change. After §7d, confirm `grep -n '^PUB \|^PRI ' src/isp_psram_graphics.spin2` shows all PUBs before all PRIs.

**Guide rules enforced:** §3.2, §5.1, §5.4.1, §5.7.

---

## § 8. Object constant references (Rule 2.4 audit)

**Why:** Guide §2.4 — when a file declares an object via `OBJ`, any constant defined by that object MUST be referenced through the object prefix, NEVER copied into a local `CON` block. Local copies silently drift out of sync.

**Current state:** 28 in-scope files have an `OBJ` block. Per-file Rule 2.4 audit not yet run — discovery work for the executor.

**Target:** For each file with an `OBJ` block, walk its `CON` block(s) and identify any local constant whose value duplicates a constant from a referenced object. Each duplicate is removed; the call sites switch to `obj.CONSTANT_NAME`. Local CONs that are not duplicates stay.

**Worth a special note:** Test files frequently `OBJ` a driver to call its public API. Test files MUST use the driver's named constants in assertions (Rule 6.1/6.2). This is the same rule applied to tests — verify each test file references the driver's `SUCCESS`/error-code/limit constants via the OBJ prefix.

**Verification:** Spot-check one library + one test for Rule 2.4 compliance. If the audit finds 0 violations across all 28 OBJ-using files, document that finding in the closeout — the ad-hoc plan suspected this, and zero violations would be a clean result.

**Guide rules enforced:** §2.4, §6.1, §6.2.

---

## § 9. Verification and commit

**Why:** A static refactor must not regress the compile baseline (38/38 in-scope files green today). One commit makes the sweep easy to revert or cherry-pick.

**Steps:**

1. **Compile all 38 in-scope files in one batch.** Any failure blocks commit until fixed.

   ```bash
   cd src && for f in <38-file-list>; do pnut-ts "$f" || echo "FAIL: $f"; done
   ```

2. **Walk Part 7 checklist** of the guide against one representative library (`isp_tile_sensor.spin2`) and one representative test (`test_fifo_regression.spin2`). Document any deviation in the closeout.

3. **`git diff --stat` review** — confirm scope matches expectations:
   - 38 files modified
   - No vendor files touched (`PSRAM_driver_RJA_Platform_1b`, `ref_hdmi_640x480_24bpp`, `chip_hdmi_640x480`, `psram_driver`, `isp_hub75_fonts`)
   - No broken-aside files touched (`test_fifo_pipeline`, `test_hdmi_via_graphics`, `test_oled_performance`, `test_pin_toggle`)

4. **Single commit** with message summarizing the sweep:

   ```
   Conform 38 Spin2 sources to SPIN2-AUTHORING-GUIDE.md

   - Phase 1: {Spin2_v47} directive + conforming '' file header on every file.
   - Phase 2: '' ---- Label ---- on every CON/DAT/VAR/OBJ; {Spin2_Doc_CON}
     on public-API CON blocks.
   - Phase 3: Complete Part 4 doc blocks on every PUB and PRI.
   - Phase 4: Identifier rehab — success→status, cogId/string/send renamed,
     generic locals replaced with descriptive names.
   - Phase 5: All early returns replaced with single-exit-point control flow
     (33 in isp_frame_fifo_manager, 12 in isp_tile_sensor, ...).
   - Phase 6: Magic numbers → named CONs; boolean precision (TRUE/FALSE);
     default-assigned return variables; PUB-before-PRI ordering.
   - Phase 7: Verified no local CON duplicates an OBJ-referenced constant.

   All 38 in-scope files compile clean. Vendor/imported files (5) and
   broken-aside test files (4) unchanged.
   ```

5. **Update `BUILD_VERSION`** in `mag_tile_viewer.spin2` from `"0.5.0"` to `"0.6.0"` (sprint closeout bump — handled by build-wrapup, NOT part of this sprint's plan but noted here for the executor's awareness).

**Verification:** `git status` shows clean working tree. `git log -1` shows the single commit.

**Guide rules enforced:** Part 7 (final checklist).

---

## § 10. Out of scope — explicitly noted

These belong to other workflows and MUST NOT be done in this sprint:

- **Hardware testing.** This is a static refactor. No download to P2, no `pnut-term-ts` runs. If Stephen wants hardware verification of a specific file post-sweep, it's a separate request.
- **CHANGELOG.md update.** Handled by `build-wrapup` skill at sprint closeout, not by the sweep itself.
- **PUNCH-LIST.md changes.** The two open items (write system spec, write CHANGELOG voicing guide) are independent of this sweep.
- **Sprint retrospective.** Handled by `sprint-retrospective` skill after closeout.
- **CLAUDE.md.** Already updated (2026-05-27) before this sprint started; not re-touched here.

---

*Plan authored 2026-05-27. Ad-hoc source: `~/.claude/plans/delightful-painting-raccoon.md` (8 phases, validated and refined against per-file audits). All open questions resolved; gate clear.*

---

## § Task cross-reference (generated 2026-05-27)

Generated by the `plan-to-tasks` skill from the §Sprint-start entry checks gate. Sprint tag: `spin2-conformance`. Task `seq` reflects the foundational→dependent execution order (rework-analysis pass complete — standards before application, discovery before utilization, settled-code before docs).

| Plan § | Deliverable | Task | seq | Estimate |
| --- | --- | --- | --- | --- |
| §2 | File preamble (`''` header on every file) | «#1» | 1 | 3h 20m |
| §3 | Block declaration labels (`' ---- Label ----`) | «#2» | 2 | 2h |
| §8 | Object constant references (Rule 2.4 audit + cleanup) | «#3» | 3 | 3h |
| §5 | Identifier rehabilitation (renames + shadowing audit) | «#4» | 4 | 4h |
| §6 | Single exit point (eliminate early returns) | «#5» | 5 | 6h |
| §7a | Magic number cleanup (loop bounds, dimensions, …) | «#6» | 6 | 3h |
| §7b | Boolean precision (TRUE/FALSE not 1/0) | «#7» | 7 | 30m |
| §7c | Default-assign return variables | «#8» | 8 | 3h |
| §7d | PUB-before-PRI relocation in `isp_psram_graphics.spin2` | «#9» | 9 | 1h |
| §4 | Method documentation (PUB/PRI doc blocks — LAST code-edit task) | «#10» | 10 | 10h |
| §9 | Verification and final commit | «#11» | 11 | 1h |

Total estimate: ~36h 50m. §1 (scope) is referenced by every task; not a task itself. §10 (out of scope) is enforced inside tasks rather than scheduled.

**Ordering rationale:** §2/§3 establish file-level standards. §8 deletes duplicate CONs before §5 can rename them or §4 can document them. §5 settles identifier names before §6 restructures bodies and before §4 writes `@param`/`@returns` tags. §6 settles method bodies (which may eliminate locals) before §4 writes `@local` tags. §7a/b/c make narrower edits that don't shift signatures. §7d relocates one file's methods before §4 documents them. §4 lands LAST among code-edits so every `@param`/`@returns`/`@local` is written once against final code. §9 is the closing gate.
