# P2-Magnetic-Imaging-Tile — Punch List

Active outstanding items for the project. Closed items get swept into the dated archive under `DOCs/plans/archive/` at sprint closeout.

---

## Outstanding

### OLED: centralize panel offset via CMD_DISPLAY_OFFSET (Fix B)
- **What:** Replace the per-call `ROW_OFFSET = -32` adjustment in `set_window()` with a one-time `CMD_DISPLAY_OFFSET = $20` in `init_display()`. Once that's set, `set_window()` and `set_window_raw()` collapse into a single routine, and every caller stops having to know about the panel/controller RAM offset.
- **Why:** Defer-only-if-needed. The 60 Hz sprint adopted Fix A (call `set_window_raw()` in `display_frame_fast()`) because it's a one-liner. Fix B is structurally cleaner but rewrites the per-cell window path's assumptions; only worth doing if the dual-API (set_window vs set_window_raw) starts producing bugs or confusion.
- **Where:** `src/isp_oled_single_cog.spin2` — `init_display()` (around line 847) and the two `set_window*` routines (lines 973 and 991).
- **Verification:** Single test pattern at known panel coordinates; visually confirm alignment after the change.

### OLED: render/transmit overlap (item 4 of 60 Hz plan)
- **What:** Run pre-render and SPI streaming concurrently so frame time = `max(render, transmit)` instead of their sum. Targets ~74 fps from ~66 fps.
- **Why deferred:** Render and stream both live in the OLED COG's inline PASM today. Concurrency requires either (a) splitting streaming back into a dedicated COG (similar to the older `isp_oled_driver.spin2` two-COG design) or (b) moving to the P2 streamer-DMA path like the HDMI driver. Both are larger structural changes than items 1–3 combined. Gated on measurement showing items 1–3 don't already cross 60 Hz with adequate margin.
- **Where:** `src/isp_oled_single_cog.spin2` — `display_frame_fast()` (line 384) and the `display_loop()` consumer pattern (around line 1145). Likely needs a second pixel buffer and a small stream sub-COG.
- **Verification:** Frame timing measurements (`test_oled_performance.spin2`) show frame time approaches the 13.1 ms SPI floor.

### Write the system-wide project specification
- **What:** Author `DOCs/System-Specification.md` — a top-level architectural target describing the project as a whole: scope, performance targets, the sensor → decimation → display pipeline, the cog allocation, the data flow, and the interfaces between subsystems. This is the document that says "here is where we are heading," distinct from the per-subsystem theory-of-operations docs.
- **Why:** The project currently has many per-subsystem documents (sensor driver, HDMI driver, OLED driver, visualization) but no single system-wide target spec. The `SPEC_DOC` slot in `.claude/skill-conventions.md` points at a stub awaiting this content.
- **Where:** `DOCs/System-Specification.md` (currently a stub).
- **Sources to draw from:** the theory-of-operations docs in `DOCs/Theory-of-Operations/`, the architecture docs in `DOCs/Architecture/`, and the as-built status in `DOCs/status-reports/Object-Architecture-As-Built.md`.

### Author CHANGELOG voicing guide
- **What:** Write a short voicing guide for `CHANGELOG.md` entries — audience, tone, level of technical detail, what gets a bullet, what doesn't.
- **Why:** Standardize the changelog voice across build wrap-ups so it stays useful as the project ages.
- **Where:** Probably `DOCs/policy/CHANGELOG-VOICING-GUIDE.md`. When created, update `.claude/skill-conventions.md` to set `HELP_VOICING_GUIDE` or a new dedicated slot.
