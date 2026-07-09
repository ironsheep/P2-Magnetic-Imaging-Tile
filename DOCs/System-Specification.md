# P2 Magnetic Imaging Tile — System Design & Intent Specification

**Document status:** Living — the single source of project design intent.
**Last reconciled:** 2026-07-09 (against the code as built).
**Maintainer:** Stephen M Moraco / Iron Sheep Productions LLC.

This is the project-wide design-intent specification. It describes **what the
system is, how it is built today, the performance it targets, and where it is
heading.** Where a capability is built, it is stated as built; where it is
intended but not yet built, it is marked **PLANNED**. Per-subsystem depth lives
in `DOCs/Theory-of-Operations/` and `DOCs/Architecture/`; hardware detail lives
in `DOCs/Hardware/`. Where those and this document disagree, the code is
authoritative and this document is corrected.

---

## 1. Purpose & scope

The system interfaces a **SparkFun Magnetic Imaging Tile V3** — an 8×8 array of
Hall-effect sensors — to a **Propeller 2 (P2)** and visualizes the magnetic
field in real time on two displays. It has two stated purposes:

1. **A low-hardware-cost magnetic-field visualizer** — P2 + magnetic tile +
   OLED, minimal parts, real-time.
2. **A benchmark of the maximum achievable frame rate** for this sensor
   configuration on P2 hardware.

A third, standing purpose drives the project's direction: it is a **P2 Knowledge
Base exercise** — the code is authored by Claude against the P2KB, and the
project continuously sharpens both the KB and the P2 codegen it supports.

### Design intent (the direction)

Beyond "display the 8×8 field," the intent is a **field-exploration instrument**:
a set of selectable processing modes, each chosen to make a *specific physical
aspect* of the field visible — **near-field structure**, **far-field
structure**, and **field strength / dynamic range**. That intent is captured in
§7 and is the subject of the (planned) Multi-Resolution Field Visualization
sprint (`DOCs/plans/MULTI-RESOLUTION-FIELD-VISUALIZATION-SPRINT-PLAN.md`).

---

## 2. System overview

```
Magnetic Tile (8x8 Hall array, AD7680 ADC)
        │  SPI @ ~2.5 MHz, hardware-mux scan
        ▼
   Sensor COG ──► Sensor FIFO ──► Main / Decimator COG ──┬─► HDMI FIFO ─► HDMI Engine ─► PSRAM ─► HDMI Video ─► 640x480 @ 60 Hz
   (~1,370 fps,                    (decimate to display   │
    inline-PASM                     cadence; PLANNED:      │
    calibration)                    interpolate to N×N)    └─► OLED FIFO ─► OLED Driver ─► SPI ─► 128x128 SSD1351 OLED
```

The sensor runs flat-out; the decimator throttles each display to its own
cadence. Both displays always run.

---

## 3. Hardware configuration

Authoritative hardware detail: `DOCs/Hardware/`. Pin **groups** (base + offset):

| Group | Pins | Function |
|---|---|---|
| HDMI | **P0–P7** | Digital video out (P2 streamer / 1-bit DACs, TMDS) |
| Magnetic tile | **P8–P15** | CS=P8, CCLK=P9, MISO=P10, CLRb=P11, SCLK=P12 (AD7680 + mux counter) |
| OLED | **P16–P23** | DIN=P16, CLK=P18, CS=P20, DC=P22, RST=P23 (SSD1351 SPI) |
| PSRAM | **P40–P57** | 16-bit data (P40–P55), CK=P56, CS=P57 |

Primary components:
- **SparkFun Magnetic Imaging Tile V3** — 8×8 Hall array, 4 quadrants, hardware
  multiplexer, **AD7680 16-bit ADC** over SPI.
- **Waveshare 1.5" RGB OLED** — 128×128, **SSD1351** controller, RGB565, SPI.
- **P2 Edge module with 32 MB PSRAM (P2-EC32MB)** — main controller + framebuffer
  memory; HDMI via the P2 digital-video add-on.

---

## 4. COG allocation

| COG | Component | Role |
|---|---|---|
| 0 | Main / decimator (`mag_tile_viewer`) | Startup, decimation, frame routing (**inline in this COG**, not a separate transform COG) |
| 1 | Sensor (`isp_tile_sensor`) | 8×8 acquisition, inline-PASM calibration |
| 2 | HDMI engine (`isp_hdmi_display_engine`) | FIFO consumer, renders grid into PSRAM framebuffer |
| 3 | OLED driver (`isp_oled_single_cog`) | FIFO consumer, renders + streams to SSD1351 (**single-COG** design) |
| 4 | PSRAM driver | External-memory controller |
| 5 | HDMI video generator | 640×480 @ 60 Hz streamer output |

---

## 5. Data pipeline

1. **Acquire** — sensor COG scans 64 sensors via the mux counter, reads each
   through the AD7680, applies **baseline calibration inline in PASM**, and
   writes a 64-word (128-byte) frame to the sensor FIFO. Runs flat-out.
2. **Route / decimate** — the main COG dequeues sensor frames and forwards
   selected frames to each display FIFO at that display's cadence (HDMI and OLED
   decimation are independent). Each display gets its own frame copy.
   - **PLANNED:** this stage also interpolates the 8×8 grid up to the selected
     resolution (see §7); the upsampled frame flows through the FIFO to the
     displays.
3. **Render** — each display COG dequeues its frames, maps values to color, and
   renders: the HDMI engine into a PSRAM-backed framebuffer, the OLED driver into
   a 128×128 pixel buffer streamed over SPI.

**Frame pool:** one shared 32-frame pool (`isp_frame_fifo_manager`) serves three
FIFOs (sensor, HDMI, OLED); frame size is 128 bytes today (64 words).

---

## 6. Performance targets & current status

| Subsystem | Hardware ceiling | Current | Target | Status |
|---|---|---|---|---|
| Sensor acquisition | ~1,330 fps (est.) | **~1,370 fps** (measured, Dec 2025) | max throughput | **Exceeds** — inline-PASM calibration, 3.7× over the earlier ~375 fps |
| HDMI display | 60 fps (VGA timing) | 60 fps | 60 fps | **At target** |
| OLED display | ~76 fps (20 MHz SPI floor) | ~55 fps last measured; 60 Hz-optimized path committed but **not yet re-measured on hardware** | **≥ 60 fps** | **Pending measurement** |

The sensor's large headroom (~22× the display rate) is what makes the planned
interpolation work (§7) computationally free — the constraint is display
bandwidth, not compute. Detail: `DOCs/analysis/Performance-Analysis.md`.

---

## 7. Design intent — the field-exploration instrument (PLANNED)

> **Status: PLANNED, not yet built.** The system today renders the native 8×8
> grid only. This section states the intended direction and is the target of the
> Multi-Resolution Field Visualization sprint plan.

The richness is organized on **three independent axes**, each selectable at
compile time initially and via a runtime control (push-button / input device)
later:

| Axis | Choices | The physical question it controls |
|---|---|---|
| **A — Resolution** | 8×8 / 16×16 / 32×32 | Reconstruction density between the 64 real samples |
| **B — Reconstruction kernel** | nearest / bilinear / Catmull-Rom / Lanczos-3 | **Sharp ↔ smooth** — the near-field vs far-field *spatial* control |
| **C — Color transfer** | bipolar / high-gain / log-magnitude / gradient-magnitude | **Amplitude & structure** — where field *strength* and derived structure become visible |

Mapped to the exploration goals:

| To see… | Kernel | Color | Why |
|---|---|---|---|
| **Near-field** (localized, strong, close) | sharp (Lanczos / nearest) | gradient-magnitude | Preserves the peak; \|∇B\| pinpoints the source / pole edge |
| **Far-field** (smooth, weak, spread) | smooth (Catmull-Rom) | high-gain / log | Pulls the weak ~1/r³ tail into visible range; smoothing suppresses sample noise |
| **Field strength / dynamic range** | bilinear / Catmull-Rom | bipolar vs log | Honest relative strength vs. seeing strong and weak together |

**Display roles (intended):** the **OLED** is the rich reconstructed-field color
image (65 K colors, full-frame); the **HDMI** display is the analytical view
(color-scale legend, numeric readout, and — deferred — contour overlays), using
its text/line capability and screen real estate. Both always run the selected
mode.

Interpolation is intended to live in the **decimator COG** (algorithms produce
the upsampled frame that flows through the FIFO), keeping a single implementation
feeding both displays.

---

## 8. Roadmap / deferred capabilities

Intended future work, listed here so the project's direction is captured in one
place. Each is designed to land at an existing extension point without
re-architecting:

- **Multi-resolution rendering (8/16/32) with selectable interpolation kernels** —
  the primary planned sprint (§7).
- **Analytical color modes** — log-magnitude and gradient-magnitude transfer
  functions; **contour / isoline** overlay (deferred within the planned sprint).
- **Temporal processing modes** — multi-frame averaging and peak-hold (the
  decimator already carries stubs for these).
- **Runtime mode selection** — a push-button / input-device control to switch
  resolution, kernel, and color live (compile-time selection first).
- **Command interface** — a serial/debug command path for mode control and
  diagnostics (README lists this as under development).

---

## 9. Related documentation

- **Hardware:** `DOCs/Hardware/` (tile, OLED, HDMI, pinout) and
  `DOCs/Hardware-PDFs/` (datasheets, schematic). Authoritative for hardware.
- **Per-subsystem theory:** `DOCs/Theory-of-Operations/` (sensor, OLED, HDMI,
  visualization).
- **Architecture:** `DOCs/Architecture/` (object model, COG allocation) and
  `DOCs/status-reports/Object-Architecture-As-Built.md`.
- **Performance:** `DOCs/analysis/Performance-Analysis.md`.
- **Reference implementation (Arduino):** `DOCs/REF-Implementation/`.
- **Authoring standard:** `DOCs/policy/SPIN2-AUTHORING-GUIDE.md`.
- **Planned sprint:** `DOCs/plans/MULTI-RESOLUTION-FIELD-VISUALIZATION-SPRINT-PLAN.md`.
