# P2-Magnetic-Imaging-Tile — Punch List

Active outstanding items for the project. Closed items get swept into the dated archive under `DOCs/plans/archive/` at sprint closeout.

---

## Outstanding

### Write the system-wide project specification
- **What:** Author `DOCs/System-Specification.md` — a top-level architectural target describing the project as a whole: scope, performance targets, the sensor → decimation → display pipeline, the cog allocation, the data flow, and the interfaces between subsystems. This is the document that says "here is where we are heading," distinct from the per-subsystem theory-of-operations docs.
- **Why:** The project currently has many per-subsystem documents (sensor driver, HDMI driver, OLED driver, visualization) but no single system-wide target spec. The `SPEC_DOC` slot in `.claude/skill-conventions.md` points at a stub awaiting this content.
- **Where:** `DOCs/System-Specification.md` (currently a stub).
- **Sources to draw from:** the theory-of-operations docs in `DOCs/Theory-of-Operations/`, the architecture docs in `DOCs/Architecture/`, and the as-built status in `DOCs/status-reports/Object-Architecture-As-Built.md`.

### Author CHANGELOG voicing guide
- **What:** Write a short voicing guide for `CHANGELOG.md` entries — audience, tone, level of technical detail, what gets a bullet, what doesn't.
- **Why:** Standardize the changelog voice across build wrap-ups so it stays useful as the project ages.
- **Where:** Probably `DOCs/policy/CHANGELOG-VOICING-GUIDE.md`. When created, update `.claude/skill-conventions.md` to set `HELP_VOICING_GUIDE` or a new dedicated slot.
