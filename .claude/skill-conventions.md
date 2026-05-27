# Project skill conventions

Slot values for the central skill set. Filled by `bootstrap-conventions` on 2026-05-27.

## Identity

```yaml
USER_NAME: Stephen
PROJECT_NAME: P2-Magnetic-Imaging-Tile
```

## Build & test

```yaml
BUILD_COMMAND: cd src && pnut-ts -d mag_tile_viewer.spin2
TEST_COMMAND: cd src && pnut-ts -d test_fifo_regression.spin2
CANONICAL_TEST_TARGET: P2 Edge module with 32MB PSRAM (P2-EC32MB) flashed via PropPlug
```

## Build version

```yaml
BUILD_VERSION_LOCATION: src/mag_tile_viewer.spin2
BUILD_VERSION_KEY: BUILD_VERSION
BUILD_VERSION_EXAMPLE: "0.5.0"
```

## Doc paths

```yaml
PLAN_DIR: DOCs/plans/
PLAN_ARCHIVE_DIR: DOCs/plans/archive/
ANALYSIS_DIR: DOCs/analysis/
PUNCH_LIST_DOC: DOCs/PUNCH-LIST.md
RELEASE_NOTES_DOC: CHANGELOG.md
SPEC_DOC: DOCs/System-Specification.md
```

Optional voicing guides omitted — none authored yet. `CHANGELOG.md` voicing guide is on the punch list.

## Filename patterns

Omitted — use skill defaults:

- `PLAN_FILENAME_PATTERN`: `<NAME>-SPRINT-PLAN.md`
- `PLAYBOOK_FILENAME_PATTERN`: `<NAME>-TEST-PLAYBOOK.md`
- `CLOSEOUT_FILENAME_PATTERN`: `<YYYY-MM-DD>-<NAME>-Sprint-Closeout.md`
- `RETROSPECTIVE_FILENAME_PATTERN`: `<YYYY-MM-DD>-<NAME>-Retrospective.md`
- `PUNCH_LIST_ARCHIVE_PATTERN`: `PUNCH-LIST-<YYYY-MM-DD>-archive.md`

## Audience & vocabulary

```yaml
RELEASE_NOTES_AUDIENCE: developers
TEST_FLEET_DESCRIPTION: the connected P2 Edge board
```

## Tracking-readiness

```yaml
PROJECT_INIT_DATE: 2025-09-27
```

## P2 development cycle

Declarative path — the skill constructs raw `pnut-ts` / `pnut-term-ts` invocations from these slots.

```yaml
P2_WORK_DIR: src/
SPIN2_TOP_FILE: mag_tile_viewer.spin2
P2_CLOCK_FREQ: 250_000_000
P2_LOG_DIR: src/logs/
```

All other P2 slots omitted — accept defaults:

- `P2_USB_DEVICE`: auto-detect (single PropPlug attached)
- `RUN_TIMEOUT_SECONDS`: 60
- `P2_DEBUG_BAUD`: 2_000_000
- `P2_INCLUDE_PATHS`: none (everything is in `src/`)
- `P2_END_MARKER`: `END_SESSION` (tool built-in)
- `P2_DEBUG_MASK`: unset
- `P2_COMPAT_COMPILE_COMMAND`: unset
- `P2_COMPILE_COMMAND` / `P2_FLASH_COMMAND`: unset (declarative path)
