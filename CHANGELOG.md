# Changelog

All notable changes to P2-Magnetic-Imaging-Tile will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Multi-resolution field visualization (8×8 / 16×16 / 32×32) with selectable
  interpolation kernels (nearest / bilinear / Catmull-Rom / Lanczos-3) and
  color-transfer modes (bipolar / high-gain / log / gradient). See
  `DOCs/plans/MULTI-RESOLUTION-FIELD-VISUALIZATION-SPRINT-PLAN.md`.
- Runtime mode-switch control interface (compile-time selection first).

### Added
- OLED single-COG driver (`isp_oled_single_cog`) consolidating the earlier
  two-COG design.
- OLED continuous-mode 32-bit SYNC_TX full-frame streaming path
  (`display_frame_fast` / `stream_pixel_buffer`) and an SCLK-rate diagnostic
  (`measure_sclk_rate`). Committed; on-board re-measurement of the 60 Hz target
  still pending.

## [0.6.0] - 2026-05-28

### Changed
- Brought all tracked Spin2 sources into full conformance with
  `DOCs/policy/SPIN2-AUTHORING-GUIDE.md` (doc blocks, single-exit control flow,
  ASCII-only debug, named constants).

## [0.5.0] - 2025-12

### Added
- Inline-PASM sensor calibration integrated into the acquisition loop — **3.7×
  acquisition speedup, ~375 → ~1,370 fps**.
- HDMI text display: static labels plus a dynamic statistics overlay.
- Stuck-pixel detection and improved calibration user experience.

### Fixed
- Symmetric bipolar color range for equal red/green response.
- Color-overflow handling in the value-to-color mapping.
