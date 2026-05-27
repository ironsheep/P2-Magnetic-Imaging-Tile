# Object Architecture & COG Allocation
**Magnetic Imaging Tile — P2 Functional Decomposition**

**Version:** 1.0
**Status:** Ideal decomposition derived purely from requirements + intent.
**Method:** Bottom-up from system requirements, ignoring any prior cog assignments or implementation conventions in the existing codebase.

---

## 1. Document Purpose

This document specifies the **object topology** and **cog allocation** for the P2 Magnetic Imaging Tile system as a *functional decomposition*. It does **not** specify:

- Sensor pinout or ADC selection (those live inside `SensorAcquirer`)
- Color formulas or palette choices (those live inside `ColorMapper`)
- HDMI scan timing or PSRAM access protocol (those live inside their respective drivers)
- System clock frequency or smart-pin divisors (those are tuning knobs)

The decomposition is **deliberately independent** of those implementation choices. Swapping the AD7680 for a P2 smart-pin ADC, or moving from 250 MHz to 340 MHz, must not require redrawing any of the boxes below — only re-tuning inside them.

---

## 2. Requirements (the design surface)

Distilled from the body of documents in this directory. Numbered for traceability.

### Functional
- **R1 Acquire.** Continuously sample 64 hall-effect sensors at the highest deterministic rate the hardware permits.
- **R2 Display small.** Render the field on a portable 128×128 OLED.
- **R3 Display large.** Render the field on a 640×480 HDMI display for demo/teaching.
- **R4 Visual coherence.** Both displays must use the same color mapping and orientation for any given sensor value.
- **R5 Process.** Run real-time DSP on the full-rate sensor stream (Kalman, FFT, peak-hold, motion vectors).
- **R6 Log.** Stream or archive frames externally (UART, USB, SD).
- **R7 Command.** Accept interactive commands (mode switch, calibrate, dump, reset).
- **R8 Calibrate.** Subtract a per-sensor baseline captured at startup.
- **R9 Annotate.** Overlay legends, stats, and instructional text on the HDMI output.

### Non-functional
- **R10 Deterministic.** Sample timing, pixel timing, and display refresh must be jitter-free.
- **R11 Continuous.** Acquisition never pauses for display, processing, or I/O.
- **R12 Decoupled.** Each consumer (small display, large display, DSP, logger) runs at its own natural rate; no consumer slows another.
- **R13 Latent.** End-to-end sensor-to-screen latency ≤ one HDMI frame (~16.7 ms).
- **R14 Extensible.** Adding a new consumer (e.g. WiFi stream, second display) must not require modifying any existing producer or consumer.

### Intent
- **I1.** Display rate ≪ acquisition rate. The acquisition pipeline must not be paced by the display.
- **I2.** DSP wants every sample; displays want one in every N. The bus must fan-out at differentiated rates.
- **I3.** Several consumers may want to *share* the same frame instance. Copying is waste; pointer + refcount is the right discipline.
- **I4.** Each external interface (sensor SPI, OLED SPI, HDMI TMDS, PSRAM bus, UART) is a hard timing contract owned by one piece of code. Two cogs touching the same external pins is a defect class.
- **I5.** A maintainer should be able to read the code and immediately know who *owns* each pin, each cog, each hub region, each lock. Single owner per resource is non-negotiable.

---

## 3. Functional Units (derived from requirements)

Each requirement is satisfied by one or more functional units. Each unit has one responsibility.

| # | Unit | Satisfies | One-sentence responsibility |
|---|------|-----------|-----------------------------|
| U1 | **Application** | R7, R8, R14 (composition root) | Boots the system, configures clock, instantiates and starts subsystems, handles user commands and mode transitions. |
| U2 | **FrameFifoManager** | R11, R12, R3, I3 | Owns the frame pool, the typed FIFO queues, consumer registration, refcounts, and producer-to-consumer wake-up. |
| U3 | **SensorAcquirer** | R1, R8, R10, R11 | Drives the sensor mux + ADC, applies per-sensor calibration, maps raw read order into the canonical frame layout, publishes frames to a sensor FIFO. |
| U4 | **PsramBroker** | R3 (frame buffer) | Serialises all PSRAM read/write traffic through a per-cog mailbox protocol; nobody else touches the PSRAM pins. |
| U5 | **PsramGraphics** | R3, R9 | Stateless drawing primitives (rect, line, text, cell, region) that translate logical draws into PSRAM transfers via U4. |
| U6 | **HdmiSignalGenerator** | R3, R10 | Generates 640×480@60 TMDS by streaming the PSRAM frame buffer line-by-line through the P2 streamer; owns the HDMI pins. |
| U7 | **HdmiRenderer** | R3, R4, R9 | Consumes frames from the HDMI FIFO; renders the sensor grid + overlays into the PSRAM frame buffer via U5. |
| U8 | **OledRenderer** | R2, R4, R10 | Consumes frames from the OLED FIFO; renders into a local 128×128 pixel buffer; streams via SPI; owns the OLED pins. |
| U9 | **SignalProcessor** | R5 | Consumes every sensor frame (no decimation); runs filters/FFT/peak-hold via the CORDIC pipeline; publishes derived frames to a processed-frame FIFO. |
| U10 | **CommsHandler** | R6, R7 | Owns the UART (and SD if present); parses inbound commands and pushes them to U1; streams decimated frames out. |
| U11 | **ColorMapper** | R4 | Stateless mapping from sensor value to RGB888 / RGB565 with shared gamma/range constants. |
| U12 | **SensorTopology** | R1 (correctness) | Stateless tables that translate hardware read order to canonical (row, col) and apply any required rotation/flip. |
| U13 | **FontRenderer** | R9 | Stateless bitmap-font glyph rendering. |

**13 units. 7 are inherently active (need their own cog); 5 are stateless libraries; 1 is a singleton with no dedicated cog. U1 (Application) needs a cog because it runs the Spin2 control flow.** Total cogs = 8. ✅

---

## 4. Object Archetype Assignment

Each unit maps to exactly one of the canonical Spin2 archetypes. The archetype dictates how the unit is built, where its state lives, and how callers use it.

| Unit | Archetype | State location | Cog? |
|------|-----------|----------------|------|
| U1 Application | top-level application | VAR (per-instance, but only one instance exists) | Yes (cog 0 implicit) |
| U2 FrameFifoManager | **singleton** | DAT (shared across all callers); lock-protected | No — runs in callers' cogs |
| U3 SensorAcquirer | **dual-cog driver** | VAR (Spin2 API) + DAT (PASM kernel + parameter block) | Yes |
| U4 PsramBroker | **dual-cog driver** with per-cog mailboxes | DAT (mailbox array) + cog-local PASM service loop | Yes |
| U5 PsramGraphics | **library** with per-cog init | per-cog mailbox handle in VAR | No |
| U6 HdmiSignalGenerator | **PASM-only object** | DAT (PASM kernel + parameter block) | Yes |
| U7 HdmiRenderer | **driver object** | VAR (cog id, FIFO handle, mode) | Yes |
| U8 OledRenderer | **dual-cog driver** | VAR (Spin2 API) + DAT (PASM render + SPI kernel) | Yes |
| U9 SignalProcessor | **dual-cog driver** | VAR + DAT (PASM CORDIC pipeline) | Yes |
| U10 CommsHandler | **driver object** | VAR (ring buffers, baud, parser state) | Yes |
| U11 ColorMapper | **library** | DAT (LUT data, computed at compile time or first call) | No |
| U12 SensorTopology | **library** | DAT (constant remap tables) | No |
| U13 FontRenderer | **library** | DAT (font bitmaps) | No |

**Key invariant:** the singleton (U2) and the libraries (U5, U11, U12, U13) have **no cog of their own**. They execute in whichever cog called them. That is why they cannot do blocking I/O or long computation — they steal from their caller.

---

## 5. COG Allocation

Each cog is assigned the **one** unit that *forces* it to be cog-resident. The forcing reason is given so the assignment can be defended in review and so a future change can be evaluated against the same criterion.

| COG | Resident unit | Forcing reason |
|-----|---------------|----------------|
| 0 | **Application** (U1) | The Spin2 control flow that owns startup, mode dispatch, and user-command sequencing must live somewhere. It is the composition root; it cannot be a passive library. |
| 1 | **SensorAcquirer** (U3) | Deterministic ADC settle/conversion timing per sensor. Any interruption corrupts a sample. The mux counter, the SPI transfer, and the FIFO commit form one indivisible sequence per sensor. |
| 2 | **PsramBroker** (U4) | The HDMI signal generator demands continuous PSRAM line reads at video-rate cadence; any cog can request a transfer at any time. A central broker must be always-resident to service those requests on the next round-robin slot. |
| 3 | **HdmiSignalGenerator** (U6) | Pixel clock is hardware-locked to system clock ÷ 10. The streamer must be driven within strict line-time and sync-time budgets; missing a deadline corrupts the picture. No other work can share this cog. |
| 4 | **HdmiRenderer** (U7) | Must wake on every HDMI-rate frame (~60 Hz), pull sensor data from a FIFO, transform 64 cells + overlays, and write them into PSRAM through U5 — all within one HDMI frame. Sharing with Application would inject Spin2 GC/parse jitter. |
| 5 | **OledRenderer** (U8) | Must wake on every OLED-rate frame (~55 Hz), render into the local pixel buffer, then sit blocking on SPI for the SPI transfer duration. The blocking SPI phase forbids sharing this cog with any non-trivial work. |
| 6 | **SignalProcessor** (U9) | Wakes on *every* sensor frame (full rate, no decimation) to run filters/FFT through the CORDIC pipeline. Throughput requirement is several × the display cogs, so it cannot share. |
| 7 | **CommsHandler** (U10) | UART RX must accept commands at arbitrary times without dropping bytes; UART TX must drain at the baud rate without blocking other cogs. Buffered I/O wants its own cog. |

**Cog binding rule:** every cog assignment is forced by *one specific timing or ownership constraint*. None is a "convenience" cog. Removing any unit from the system would free its cog; merging two units would violate the constraint that justified the split.

### What was *not* given its own cog (and why)

- **FrameFifoManager (U2):** stateless operations on shared DAT. Locks make it safe; calls run in caller's cog. Giving it a cog would mean two extra context-switches (caller → broker → caller) on the hot path.
- **Decimation:** is *not* a separate unit. It is a behaviour of `commitFrame()` inside U2: when a producer commits, the manager checks per-FIFO decimation counters and fans the frame pointer into the right subset of FIFOs. Adding a dedicated decimator cog would buy nothing and add latency.
- **Calibration:** is *not* a separate unit. It is a mode of U3. The PASM acquisition loop applies `raw - baseline[i] + mid` inline before publishing.
- **Educational overlay:** is *not* a separate unit. It is content rendered by U7. Static labels are drawn once at startup; dynamic stats are redrawn per frame in U7's wake-up handler.
- **ColorMapper / SensorTopology / FontRenderer / PsramGraphics:** are libraries; they execute in the caller's cog. Putting them on their own cog would force every drawing primitive to cross a cog boundary.

---

## 6. Object Composition Tree

The composition shows *who instantiates whom* and *who depends on whom*. Cog-resident units are bold; libraries are italic; the singleton is underlined.

```
Application (cog 0)                                      [top-level]
├── OBJ fifo    : "frame_fifo_manager"                   ←singleton (U2)
├── OBJ colors  : "color_mapper"                         ←library  (U11)
├── OBJ topo    : "sensor_topology"                      ←library  (U12)
├── OBJ fonts   : "font_renderer"                        ←library  (U13)
│
├── OBJ psram   : "psram_broker"          → starts cog 2 (U4)
├── OBJ sensor  : "sensor_acquirer"       → starts cog 1 (U3)
│       └── uses topo, fifo, colors
├── OBJ hdmisig : "hdmi_signal_generator" → starts cog 3 (U6)
│       └── uses psram (PSRAM line reads)
├── OBJ hdmiren : "hdmi_renderer"         → starts cog 4 (U7)
│       ├── OBJ gfx : "psram_graphics"     ←library (U5) — per-cog init
│       │       └── uses psram, fonts
│       └── uses fifo, colors
├── OBJ oled    : "oled_renderer"         → starts cog 5 (U8)
│       └── uses fifo, colors
├── OBJ dsp     : "signal_processor"      → starts cog 6 (U9)
│       └── uses fifo
└── OBJ comms   : "comms_handler"         → starts cog 7 (U10)
        └── uses fifo (to stream out)
```

**Composition rules**

- Application *only* instantiates direct children; it never reaches into a grandchild.
- The singleton is referenced by every cog that needs frames; its DAT is the single source of truth for pool state.
- Libraries are duplicated as `OBJ` entries in every parent that uses them. The compiler resolves duplicates to a single image; semantically each parent has its own handle.
- `psram_graphics` is a library, but it carries a per-cog mailbox handle in VAR. Every renderer that draws into PSRAM calls `gfx.start()` once in its cog to bind its mailbox slot. The mailbox handle is private to that cog instance.

---

## 7. Inter-COG Communication

Five primitives. Each has one purpose; mixing them is a smell.

### 7.1 Frame pipe (bulk data, fan-out, refcounted)

The primary data path. One producer publishes a frame pointer; one or more consumers wake on COGATN and read it.

```
Producer cog                                  Consumer cog(s)
─────────────                                 ───────────────
fifo.acquireFrame()  ──► returns ptr from
                         free list, refcount=0
   ... fill frame ...

fifo.commitToMultiple(ptr, fifo_mask) ──► increments refcount once per
                                          target FIFO it lands in;
                                          enqueues ptr into each;
                                          COGATN to each registered consumer

                                          ╔══════════════════╗
                                          ║  WAITATN (sleep) ║
                                          ╚══════════════════╝
                                                  ▼
                                          ptr = fifo.dequeueEventDriven(my_fifo)
                                          ... read frame ...
                                          fifo.releaseFrame(ptr) ──► decrements
                                                                    refcount; returns
                                                                    to free list at zero
```

**Invariants enforced by U2:**

- A FIFO has exactly **one registered consumer cog**.
- A frame pointer in any FIFO has **refcount ≥ 1** until every consumer has released it.
- `acquireFrame()` returns `0` when the pool is empty; the caller must drop the frame (back-pressure rule: producers are non-blocking; the slowest consumer can starve, never stall the producer).
- Decimation counters live in U2 per-FIFO; the producer does not know any consumer's rate.

**FIFO inventory:**

| FIFO id | Producer | Consumer | Rate |
|---------|----------|----------|------|
| `FIFO_SENSOR` (internal handoff to fan-out) | U3 | U2's `commitToMultiple` only | producer rate |
| `FIFO_HDMI`   | U2 fan-out | U7 (HdmiRenderer) | ~60 Hz (decimated) |
| `FIFO_OLED`   | U2 fan-out | U8 (OledRenderer) | ~55 Hz (decimated) |
| `FIFO_DSP`    | U2 fan-out | U9 (SignalProcessor) | full rate |
| `FIFO_COMMS`  | U2 fan-out | U10 (CommsHandler) | configurable |
| `FIFO_PROCESSED` | U9 | optional U7 (alt mode) | DSP rate |

### 7.2 PSRAM mailbox (shared device, no fan-out)

`PsramBroker` (U4) owns the PSRAM pins. Every cog that wants to read or write PSRAM gets a private 12-byte mailbox slot at `start()` time. The cog writes `{hub_addr, psram_addr, length_signed}` into its slot; U4 polls slots in round-robin and services them. Sign of `length` indicates direction.

**Invariants:**

- No cog directly drives P40–P57.
- One mailbox per cog. The mailbox slot is acquired at `gfx.start()` and never released.
- Transfers are atomic per mailbox; a cog cannot issue a second transfer until U4 zeroes the length field.

### 7.3 Lock (only for U2)

Two locks live in `FrameFifoManager`:

- `pool_lock` — protects the free-list and refcount updates.
- `queue_lock` — protects the FIFO ring buffers.

Held for a few instructions only (head/tail pointer update). No other unit creates or holds locks.

### 7.4 COGATN (wake-up, no payload)

Used exclusively by U2 to wake a consumer when `commitToMultiple` enqueues a frame for that consumer's FIFO. Each consumer registers its cog id once via `fifo.registerConsumer(FIFO_ID, cogid())`. From then on, every commit that targets that FIFO sends `COGATN` to that cog.

**Rule:** COGATN is *only* used by FIFO commit signalling. No ad-hoc cog-to-cog attention.

### 7.5 Smart-pin / CORDIC / streamer events (intra-cog)

Each cog uses `SETSE`/`WAITSE` and `WAITX` for its internal hardware coordination (SPI transfer complete, CORDIC result ready, streamer line done). These never cross cog boundaries.

---

## 8. Resource Ownership

A maintainer can answer "who owns X?" by reading this table. No exceptions.

| Resource | Sole owner |
|---|---|
| P0–P7 (HDMI pins) | U6 HdmiSignalGenerator |
| P8–P15 (sensor interface) | U3 SensorAcquirer |
| P16–P23 (OLED pins) | U8 OledRenderer |
| P24–P39 (free) | reserved |
| P40–P57 (PSRAM bus) | U4 PsramBroker |
| P58–P63 (UART/USB candidates) | U10 CommsHandler |
| Cog id mapping | U1 Application (assigns at `start()`) |
| Frame pool (hub) | U2 FrameFifoManager |
| HDMI frame buffer (PSRAM) | U4 broker; U7 is the only writer; U6 is the only reader |
| OLED pixel buffer (hub, 32 KB) | U8 OledRenderer |
| Color LUTs | U11 ColorMapper (DAT) |
| Sensor remap tables | U12 SensorTopology (DAT) |
| Font bitmaps | U13 FontRenderer (DAT) |
| Locks 0–15 | U2 reserves 0 and 1; the rest are unused |
| System clock setting | U1 Application (set once at boot) |
| CORDIC | shared; U9 is the heavy user |

**Pin group invariant:** every owner takes its 8-pin group with `FLTL` then `WRPIN`, configures Smart Pins, and never relinquishes. No transient pin reuse.

---

## 9. Data Flow Topology

```
                              ┌──────────────────────────────────────┐
                              │   FrameFifoManager  (singleton, U2)  │
                              │   pool ▸ FIFOs ▸ COGATN dispatch     │
                              └──────────────────────────────────────┘
                                        ▲                  ▲
                       commitToMultiple │                  │ registerConsumer
                                        │                  │ dequeueEventDriven
                                        │                  │ releaseFrame
        ┌───────────────┐   commit      │                  │
        │  cog 1: U3    │───────────────┘                  │
        │  Sensor       │                                  │
        │  Acquirer     │                                  │
        └───────────────┘                                  │
                                                           │
   ┌────────────────────┬────────────────────┬─────────────┴───────┬──────────────┐
   │                    │                    │                     │              │
   ▼ FIFO_HDMI          ▼ FIFO_OLED          ▼ FIFO_DSP             ▼ FIFO_COMMS  │
┌──────────┐        ┌──────────┐         ┌────────────┐         ┌──────────┐     │
│ cog 4    │        │ cog 5    │         │ cog 6      │         │ cog 7    │     │
│ HdmiRen  │        │ OledRen  │         │ Signal     │─────────┤ Comms    │     │
│ (U7)     │        │ (U8)     │         │ Processor  │         │ Handler  │     │
└──────────┘        └──────────┘         │ (U9)       │         │ (U10)    │     │
   │                   │                  └────────────┘         └──────────┘     │
   │ gfx.FillCell      │ SPI to OLED         │                       │            │
   │ via U5 mailbox    │ pins                │ FIFO_PROCESSED        │ UART       │
   ▼                   ▼                     ▼                       ▼            │
┌─────────────┐    ┌─────────────┐                                                │
│  cog 2:     │    │  P16-P23    │                                                │
│  PsramBroker│    │  OLED       │                                                │
│  (U4)       │    └─────────────┘                                                │
│  pin owner: │                                                                   │
│  P40-P57    │                                                                   │
└─────────────┘                                                                   │
       ▲                                                                          │
       │ PSRAM line reads                                                         │
       │                                                                          │
┌─────────────┐                                                                   │
│  cog 3:     │                                                                   │
│  HdmiSignal │──► P0-P7 (TMDS)                                                   │
│  (U6)       │                                                                   │
└─────────────┘                                                                   │
                                                                                  │
┌───────────────────────────────────────────────────────────────────────────────┐ │
│  cog 0: Application (U1) — startup, mode, calibration UI, command dispatch ◄──┘ │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Observations:**

- U3 is the **only producer** into the pipeline. Any future producer (replay file, simulator) only has to satisfy the `commitToMultiple` contract.
- U7, U8, U9, U10 are **independent consumers**. Removing any one does not affect the others. Adding a new consumer (e.g. WiFi streamer) is one extra FIFO id, one extra cog, zero changes elsewhere — **R14 satisfied by construction**.
- U4 (PSRAM) is a **shared service**, not part of the frame pipe. The frame pipe carries pointers + 128-byte sensor frames in hub. PSRAM carries the rendered HDMI framebuffer (image bytes), which is large and would be wasteful to route through the frame pipe.

---

## 10. Hub Memory Plan

A single-owner map of the 512 KB hub. Boundaries are alignable; exact sizes are tuned during integration.

| Range | Size | Owner | Purpose |
|-------|------|-------|---------|
| `$00000–$0FFFF` | 64 KB | toolchain | Spin2 interpreter, code, vectors |
| `$10000–$1FFFF` | 64 KB | per-cog | Stacks (8 × 4 KB), local VARs |
| `$20000–$2FFFF` | 64 KB | U2 | Frame pool: 32 frames × ~256 B + headers + free list + FIFO rings |
| `$30000–$3FFFF` | 64 KB | U8 | OLED pixel buffer (32 KB) + color LUT (8 KB) + cell origin LUT |
| `$40000–$4FFFF` | 64 KB | U9 | DSP working buffers (Kalman state, FFT scratch, history buffers) |
| `$50000–$5FFFF` | 64 KB | U10 | Comms ring buffers (UART RX, UART TX, log staging) |
| `$60000–$7FFFF` | 128 KB | reserved | Future consumers (pattern library, replay buffer) |

The frame pool size sets the worst-case latency consumers can absorb before starving. 32 frames × ~1.3 ms producer interval = ~42 ms of headroom.

---

## 11. Performance Axes (what the design optimises)

The design is held to budgets on five axes. The architecture is correct only if each axis has a clear bottleneck and the bottleneck lives in the cog responsible for that axis.

| Axis | Bottleneck cog | Bottleneck cause | Budget |
|------|---------------|------------------|--------|
| **Acquisition rate** | cog 1 (U3) | ADC SPI transfer time + analog settle | hardware ceiling ≈ 1330 fps |
| **OLED refresh** | cog 5 (U8) | SPI bytes-on-wire at 20 MHz | ≈ 55 fps; bytes-on-wire is the floor |
| **HDMI refresh** | cog 3 (U6) | VGA pixel clock | exactly 60 Hz |
| **HDMI render** | cog 4 (U7) | PSRAM mailbox bandwidth via U4 | must fit one frame (≤16.7 ms) |
| **DSP throughput** | cog 6 (U9) | CORDIC pipeline depth, 8-clock slot per cog | one full-rate frame per producer interval |
| **Command latency** | cog 0 (U1) | UART byte arrival + parser | ≤ 1 user-frame (subjective) |
| **Sensor-to-screen latency** | sum of stages | producer interval + render time + PSRAM line stream | ≤ 16.7 ms |

**Key property:** each axis has its own cog. Improving acquisition rate cannot regress display rate (different cog). Adding DSP work cannot stall the displays (different cog). This is the point of the decomposition.

---

## 12. Boot & Lifecycle Sequence

`Application.main()` executes a fixed sequence so the system is fully wired before any data flows.

```
1. Set _clkfreq (clock).
2. fifo.init()                         ; allocate pool, build free list, create locks
3. colors.init() / topo.init() / fonts ; library compile-time data already present
4. psram.start()                       ; cog 2 — must precede any PSRAM user
5. hdmisig.start()                     ; cog 3 — needs psram
6. hdmiren.start()                     ; cog 4 — needs psram, fifo, colors
   gfx.start()  inside hdmiren cog    ; binds its PSRAM mailbox
   fifo.registerConsumer(FIFO_HDMI, my_cogid)
7. oled.start()                        ; cog 5
   fifo.registerConsumer(FIFO_OLED, my_cogid)
8. dsp.start()                         ; cog 6
   fifo.registerConsumer(FIFO_DSP, my_cogid)
9. comms.start()                       ; cog 7
   fifo.registerConsumer(FIFO_COMMS, my_cogid)
10. sensor.start()                     ; cog 1 — LAST, because once it starts,
                                         frames begin flowing and any unregistered
                                         consumer would miss them
11. Application enters command loop.
```

**Lifecycle invariants:**

- Every `start()` returns a cog id ≥ 0 on success; Application aborts on any failure.
- Every `start()` is idempotent: calling twice stops the existing cog and restarts.
- `stop()` releases the cog, returns locks if held, and clears the consumer registration.
- Calibration is a mode transition driven by Application: it pauses U3, captures one quiescent frame, computes the baseline table, hands the baseline pointer to U3, resumes U3.

---

## 13. Invariants (the contract the architecture relies on)

A new contributor should read these before touching code.

- **I-A** A cog owns its pin group exclusively. No code outside that cog touches those pins.
- **I-B** A FIFO has exactly one registered consumer cog. Changing it requires `stop()` of the current consumer.
- **I-C** Frame pointers in the pool have refcount ≥ 1 from `commit` to last `release`. Refcount reaching zero is the only way a frame returns to the free list.
- **I-D** Producers never block on consumers. If `commitToMultiple` cannot allocate, frames are dropped at the slowest consumer's FIFO, not at the producer.
- **I-E** PSRAM is accessed only through U4's mailbox protocol.
- **I-F** COGATN is used only by U2's commit path. Any other use is a defect.
- **I-G** Libraries (U5, U11, U12, U13) are stateless across calls *except* U5's per-cog mailbox handle (held in caller's VAR).
- **I-H** The system clock is set once by U1 at boot and never changed.
- **I-I** No object holds a lock across a hub access boundary it didn't initiate (no `RDLONG/WRLONG` while a non-U2 lock is held; the locks U2 holds are released within ≤10 instructions).

---

## 14. Extensibility Worked Examples

These demonstrate that R14 is satisfied by construction.

**Add a WiFi streamer (cog 7+) → 0 changes to existing units except cog reallocation.**
1. Implement `WifiStreamer` (driver archetype).
2. Add `FIFO_WIFI` to U2's enum and decimation table.
3. In Application boot: `wifi.start()`, `fifo.registerConsumer(FIFO_WIFI, my_cogid)`.
4. Update `fifo_mask` U2 uses on commit to include FIFO_WIFI.

No producer (U3) change. No other consumer change.

**Add a second OLED → instantiate U8 twice with different pin group.**
1. `oled_a : "oled_renderer"` on P16-P23
2. `oled_b : "oled_renderer"` on P24-P31
3. Two `registerConsumer` calls with two distinct FIFO ids.
4. Use one more cog.

**Swap AD7680 for P2 smart-pin ADC → change inside U3 only.**
1. `SensorAcquirer.start()` configures a smart-pin ADC instead of the SPI ADC.
2. `SensorTopology` (U12) is unaffected — the mapping is about read order, not ADC type.
3. Color mapping (U11) is unaffected — sensor values are still 16-bit unsigned.
4. Zero change to any other cog or FIFO contract.

**Add educational overlays → change inside U7 only.**
- U7 already draws cells; it adds text/legend draws via U5/U13 in the same per-frame routine.

---

## 15. What the Architecture Does *Not* Address

These are explicitly out of scope and must be specified elsewhere:

- Exact ADC type, SPI dividers, settle delays. → live inside U3.
- Exact color formula, palette, gamma. → live inside U11.
- HDMI scan timing constants, streamer mode word. → live inside U6.
- PSRAM command protocol, page boundaries. → live inside U4.
- Font glyph table, anti-aliasing strategy. → live inside U13.
- Specific DSP algorithms (Kalman gains, FFT size). → live inside U9.
- Command grammar. → lives inside U10/U1.

If the architecture has done its job, *changing any of the above changes one file and one file only*.

---

## 16. Open Questions

These shape implementation but not the decomposition. They should be resolved during integration:

1. Frame size in the pool: 128 B (just sensor data) or larger (includes timestamp, sequence number, calibration flags)? Recommend a fixed-size header + 128 B payload.
2. Pool size: 32 frames is a guess. Final number depends on slowest consumer's worst-case stall.
3. Whether U9 publishes to its own FIFO_PROCESSED or whether U7 has a mode that reads FIFO_DSP and FIFO_HDMI fused. Either works; the cleaner choice is two FIFOs.
4. Whether comms parser belongs in U10 or U1. Default: parser in U10, semantic dispatch in U1 over a small command-mailbox.
5. How the calibration baseline is shared with U3 — pointer in DAT (singleton) or VAR (passed at start)? Default: pointer field in U3's VAR, set by Application before `sensor.start()`.

---

## Appendix A — Cross-reference of Units to Existing Files

For migration. The current codebase already realises most of these units; this table shows where each unit lives today and the action needed.

| Unit | Existing file (if any) | Action |
|------|------------------------|--------|
| U1 Application | `mag_tile_viewer.spin2` | Trim to composition root; pull command parsing into U10 |
| U2 FrameFifoManager | `isp_frame_fifo_manager` | Add `commitToMultiple` with per-FIFO decimation counters |
| U3 SensorAcquirer | `isp_tile_sensor.spin2` | Already a driver; ensure FIFO commit is the only output |
| U4 PsramBroker | `psram_driver.spin2` | Already mailbox-based; no functional change |
| U5 PsramGraphics | `isp_psram_graphics.spin2` | Already a library; verify per-cog `start()` discipline |
| U6 HdmiSignalGenerator | `isp_hdmi_640x480_24bpp.spin2` | Already PASM-only; no change |
| U7 HdmiRenderer | `isp_hdmi_display_engine.spin2` | Move overlay rendering here; consumer-only role |
| U8 OledRenderer | `isp_oled_single_cog.spin2` | Already a driver; consumer-only role |
| U9 SignalProcessor | — | New; subscribes to FIFO_DSP |
| U10 CommsHandler | — | New; UART + SD if present |
| U11 ColorMapper | scattered between OLED + HDMI files | Extract to one library; both renderers use it |
| U12 SensorTopology | `unified_sensor_map` inside U3 | Extract to library so U9 / future consumers can also use it |
| U13 FontRenderer | `isp_hub75_fonts.spin2` | Already a library |

---

## Appendix B — Decision Provenance

For each major design decision, this appendix records *what* drove it and *how certain* it is. The intent is that a reader can audit my reasoning and replace a "JUDGEMENT" call without unraveling the architecture.

**Confidence levels:**

- **HARD** — Forced by a P2 hardware fact or Spin2 language requirement. The decision cannot reasonably be otherwise.
- **STRONG** — Documented best practice in P2KB *or* a well-established systems-engineering principle. Departing would need an explicit reason.
- **JUDGEMENT** — A choice between two viable options. I picked one; the other could be argued.

**Source codes used in the tables:**

- **P2KB** — Drawn from the P2 Knowledge Base. Specific keys are cited.
- **PRJ** — Drawn from documents in this directory.
- **SE** — General systems-engineering principle (SRP, DRY, information hiding, composition root, dataflow patterns). Not P2-specific.
- **REASONING** — My own pattern recognition / synthesis across the above. The places where I did the most independent thinking.

### B.1 Cog allocation — per cog

| Cog | Decision | Source(s) | Confidence | Alternative considered & why rejected |
|-----|----------|-----------|------------|---------------------------------------|
| 0 | Application owns this cog | P2KB `p2kbArchCog` (Spin2 launches `main()` from cog 0); P2KB `p2kbSpin2ObjectArchetypes` (top-level archetype) | HARD | None — a composition root must exist somewhere |
| 1 | SensorAcquirer is its own cog | P2KB `p2kbArchCog` (2-clock determinism, no preemption); PRJ (`MagSensor-Driver-Theory-of-Operation.md` — ADC SPI + settle is uninterruptible) | HARD | Share with Application — rejected because Spin2 interpreter timing is variable and an interrupted SPI transfer corrupts samples |
| 2 | PsramBroker is its own cog | PRJ (`HDMI-Driver-Theory-of-Operation.md` — mailbox protocol). REASONING: P2 has no DMA controller independent of cogs; a shared hardware bus needs an always-resident arbiter | STRONG | Cog-less shared-lock scheme — rejected because pin direction handoff between cogs and contention windows get ugly |
| 3 | HdmiSignalGenerator is its own cog | P2KB `p2kbArchStreamerIndex` (streamer is per-cog hardware); PRJ (HDMI pixel clock = sysclock / 10) | HARD | None — the streamer is intrinsically one cog |
| 4 | HdmiRenderer is its own cog | SE (don't mix variable-latency control flow into a per-frame render path); REASONING (Application has command parsing + calibration UI with unbounded timing) | STRONG | Share with cog 0 — rejected on jitter grounds; would couple frame timing to user input |
| 5 | OledRenderer is its own cog | PRJ (`OLED-Driver-Theory-of-Operation.md` — 17 ms blocking SPI per frame) | STRONG | Share if SPI moves to streamer/DMA — *legitimate alternative*; flagged as future re-evaluation if the SPI bus goes hardware-streaming |
| 6 | SignalProcessor is its own cog | P2KB `p2kbArchCordic` (54-stage pipeline, 8-clock per-cog slot, 7-deep in-flight per cog) | STRONG | Share with HdmiRenderer — rejected on throughput grounds: DSP wants every frame, displays want one in every N |
| 7 | CommsHandler is its own cog | SE (buffered async I/O needs its own thread of control); REASONING (UART alone could be smart-pin from any cog, but SD/USB/parsing push it over) | STRONG | Inline UART into cog 0 with smart-pin TX/RX — *legitimate alternative if* SD and USB are dropped from scope |

**Key invariant of this allocation:** every cog has a *one-sentence forcing reason*. If you cannot state the forcing reason in one sentence, the cog is misallocated.

### B.2 Object boundary decisions

| Decision | Source(s) | Confidence | Notes |
|----------|-----------|------------|-------|
| `FrameFifoManager` is a **singleton** (DAT-shared, lock-protected) | P2KB `p2kbSpin2ObjectArchetypes` (singleton archetype) | STRONG | Required because the frame pool is system-wide state |
| `PsramBroker`, `HdmiSignalGenerator`, `HdmiRenderer` are **three separate** objects | SE (Single Responsibility Principle: bus, timing, content all change for different reasons) | STRONG | A "HDMI subsystem" mega-object would couple three timing domains |
| `PsramGraphics` is a **library**, not a cog-resident object | P2KB `p2kbSpin2ObjectArchetypes` (library archetype); REASONING (its backend is already cog-resident, so it has nothing to host) | STRONG | |
| Decimation lives **inside the FIFO commit**, not in its own stage | REASONING (decimation state is one counter per FIFO; adding a stage adds latency, not value) | JUDGEMENT | Alternative: a dedicated "Decimator" cog. Rejected — buys nothing. |
| Calibration is a **mode** of `SensorAcquirer`, not its own unit | REASONING (the baseline table and the raw samples live in the same cog; separating forces cross-cog data sharing) | STRONG | |
| `ColorMapper` is **shared** between `HdmiRenderer` and `OledRenderer` | R4 visual coherence; SE (DRY) | STRONG | If only one display existed, this would inline into that display's renderer |
| `SensorTopology` is a **library separate from SensorAcquirer** | SE (constants and logic separable) | **JUDGEMENT** | Only one consumer today (U3). Borderline call — see Appendix C |
| `FontRenderer` is a **library separate from HdmiRenderer** | SE (glyph rendering is its own concern) | **JUDGEMENT** | Only one consumer today (U7). Borderline call — see Appendix C |
| Frame pool size = 32 frames | REASONING (slowest consumer stall × producer interval, with margin) | JUDGEMENT | Will be tuned in integration |

### B.3 Communication primitive choices

| Decision | Source(s) | Confidence |
|----------|-----------|------------|
| Use `COGATN` / `WAITATN` for producer-consumer wake-up | P2KB `p2kbArchCogAttention` (2-clock signal, zero hub bandwidth, instant wake) | HARD — this *is* the P2 idiom |
| Use a single hub-resident frame pool with refcounts | SE (dataflow / pool pattern); REASONING | STRONG — standard dataflow design |
| Use two locks in `FrameFifoManager` (pool, queue) | P2KB `p2kbArchHub` (16 locks available, atomic test-and-set) | STRONG |
| Use `SETSE` / `WAITSE` for intra-cog hardware events | P2KB `p2kbArchEventSystem` | HARD — `WAITSE` is the right tool for smart-pin completion |
| Per-cog mailbox slots for `PsramBroker` | PRJ (existing PSRAM driver pattern); REASONING (no shared bus arbiter hardware) | STRONG |
| Single producer per FIFO; single consumer per FIFO | SE invariant; simplifies refcount / wake correctness | STRONG |

### B.4 Where I leaned outside P2KB

These are the architectural moves I made from general systems engineering, not from anything in P2KB. They are the most fragile decisions in this doc because they depend on my pattern recognition, not on a citable reference.

- **Producer-consumer with refcounted shared frames + multi-FIFO fan-out.** The whole spine of the data flow. Comes from dataflow systems (GStreamer, ROS topics, Akka streams). P2KB does not document this pattern.
- **"Single owner per resource" invariant for pins / cogs / locks / hub regions.** Systems-engineering hygiene. Not in P2KB.
- **"Single forcing reason per cog" heuristic.** My own rule, derived from the SRP applied to cog allocation specifically.
- **"Information hiding justifies separation even with one consumer."** Parnas, 1972. Used to defend `PsramGraphics` against the "only one consumer, inline it" objection.
- **Composition root pattern (Application as wiring layer only).** Standard DI guidance. Spin2's `OBJ` block makes this almost free.
- **The "promote when needed" recommendation for `SensorTopology` and `FontRenderer`.** YAGNI applied to library extraction.

---

## Appendix C — Post-Decomposition Audit

After deriving 13 units, the discipline is to walk back through them and ask **"is this really worth being its own object?"** for each one. Honest answers, including which calls are speculative.

The audit question is sharpest for objects with **only one consumer today**, because reuse — usually the strongest justification for a library — does not apply.

| Unit | Consumers (today) | Could be inlined? | Decision | Justification |
|------|-------------------|-------------------|----------|---------------|
| U1 Application | — (it *is* the root) | No | **Keep** | Composition roots are not optional |
| U2 FrameFifoManager | 6 (every producer/consumer cog) | No | **Keep** | True multi-consumer shared state |
| U3 SensorAcquirer | The pipeline | No | **Keep** | Owns a pin group + a cog |
| U4 PsramBroker | 2+ (U6 reads, U5 writes via U7) | No | **Keep** | Owns a pin group + a cog |
| U5 PsramGraphics | 1 (U7 today) | **Yes** | **Keep separate** | **Justification: information hiding.** If inlined into U7, the renderer would directly format PSRAM mailbox commands. Separating means U7's code reads as "draw a rect"; mailbox protocol stays in U5. This is encapsulation, not reuse, and it survives "but there's only one consumer" because the cost would be a leaky abstraction. |
| U6 HdmiSignalGenerator | 1 (HDMI display) | No | **Keep** | Owns a pin group + a cog |
| U7 HdmiRenderer | 1 (HDMI display) | No | **Keep** | Owns a cog |
| U8 OledRenderer | 1 (OLED display) | No | **Keep** | Owns a pin group + a cog |
| U9 SignalProcessor | optional (U7 alt mode + future) | No | **Keep** | Owns a cog |
| U10 CommsHandler | 1 (the UART) | No | **Keep** | Owns a pin group + a cog |
| U11 ColorMapper | 2 (U7, U8) | No | **Keep** | Required for R4 visual coherence; two consumers, so reuse is real |
| U12 SensorTopology | 1 (U3) | **Yes** | **Borderline — promote when needed** | The remap tables are constants; could be a DAT inside U3 today. Reasons to keep separate: independent test-ability, future consumers (DSP wanting reverse mapping, diagnostics). Reasons to inline: only one consumer today, no protocol to encapsulate (unlike U5). **Honest answer:** start inlined in U3; promote to library when a second consumer appears. |
| U13 FontRenderer | 1 (U7) | **Yes** | **Borderline — promote when needed** | Same shape as U12. **Honest answer:** start inlined in U7; promote when OLED adds text or a second renderer needs glyphs. |

### Audit outcome

**Three borderline calls: U5, U12, U13.**

- **U5 stays separate** because protocol encapsulation is a stronger justification than reuse.
- **U12 and U13 should start inlined** and be promoted to libraries only when a second consumer materialises. Calling them out as their own units in the architecture doc is fine *as a placeholder*, but treating them as required separations would be speculative.

The audit also confirms that **the rest of the units are forced by either resource ownership (a pin group + a cog) or by multi-consumer sharing (U2, U11)**. None of them is decorative.

### What the audit guards against

- **Premature library extraction.** Easy mistake when designing top-down. The "promote when needed" rule pushes back.
- **Hidden-coupling objects.** Easy mistake when a "shared" object turns out to have one real consumer. The audit forces that to be explicit.
- **Cog inflation.** Every cog must have a one-sentence forcing reason; the audit pass on cogs (B.1) is the equivalent discipline.

---

## Appendix D — Guidance Gaps

This appendix lists the spots where I had to reason without P2KB support. The intent is to help target future P2KB additions on object/cog shape — Stephen noted P2KB has thin coverage on this today.

### D.1 Patterns P2KB does not currently document, that I leaned on heavily

These are patterns I synthesised from general dataflow / concurrency systems and applied to the P2. Documenting them in P2KB with worked examples would prevent each future P2 architect from re-deriving them.

- **Producer-consumer frame pipeline with refcounted pool + multi-FIFO fan-out.**
  P2KB `p2kbSpin2ObjectArchetypes` lists `buffered_io_object`, but only as a single-producer-single-consumer ring buffer. The real pattern in any multi-output real-time P2 system is *one producer, refcounted pool, multiple typed FIFOs, one consumer per FIFO, COGATN wake-up*. This pattern is the spine of the magnetic-tile viewer and would be the spine of any video, audio, or sensor-fusion system on the P2.

- **Per-cog mailbox protocol for shared hardware drivers.**
  PSRAM is the canonical case. Each cog claims a private mailbox slot at `start()`; the driver round-robins. This pattern reappears for SD, multi-channel DAC, network controllers — anything one bus, many users. P2KB has no archetype for it; I called mine a "dual-cog driver with per-cog mailboxes" but that's a stretch of an existing archetype.

- **Decimation as a property of the bus, not a stage.**
  When should multi-rate fan-out fold into the producer's commit vs. live in its own cog/stage? Documenting the criterion ("if state is bounded and computation is cheap, fold; otherwise stage") would prevent unnecessary cogs.

- **The "single forcing reason per cog" heuristic.**
  A simple maintenance rule: every cog must be defensible by a one-sentence forcing reason — timing, ownership, blocking I/O, throughput. If you cannot state it, the cog is wrong. Worth promoting to a P2KB best-practice page.

- **Cog-allocation worked example for an 8-cog system.**
  P2KB archetypes show individual objects in isolation. The hardest decisions are at *system composition*: which combination of archetypes fits eight cogs together. A 3-4 worked examples (real-time video; multi-sensor fusion; protocol bridge) would be highly leveraged content.

### D.2 Specific judgement calls I had to make without P2KB

These are the questions where I picked one of two viable answers based on my own pattern recognition. Future P2 architects will face the same forks.

- *When does an object with one consumer still deserve to be separate?* — I used three different criteria for U5, U12, U13 and got different answers for each. A documented rule would help.
- *When is a stage in a pipeline worth its own cog vs. a thread-of-control inside an existing cog?* — Effectively asking what justifies cog spend.
- *How big should the frame pool be?* — Function of worst-case slowest-consumer stall; nobody documents the formula.
- *When should a library hold per-cog state (like U5's mailbox handle) and when should it be fully stateless?* — A small typology would help.
- *When should COGATN signalling be reserved (as I did — only U2 uses it) vs. shared across the system?* — I picked "reserved" for clarity, but the alternative is defensible.

### D.3 P2KB content that was decisive

For balance — the places where P2KB *did* drive my decisions:

| P2KB key | What it gave me |
|----------|----------------|
| `p2kbSpin2ObjectArchetypes` | The seven archetypes. Every U1–U13 maps to one. **Single most useful page in P2KB for this work.** |
| `p2kbArchHub` | Egg-beater 8-clock rotation, deterministic hub access cost, 16 locks, ATN flags, hub-resident FIFO. Grounds "hub access is cheap and predictable; design around it." |
| `p2kbArchCog` | 512-long cog RAM + 512-long LUT, 2-clock instruction timing, pipeline behaviour. Grounds the dual-cog (Spin2 API + PASM kernel) archetype. |
| `p2kbArchCogAttention` | `COGATN`/`WAITATN`/`POLLATN` semantics. *This is the P2 idiom* for producer-consumer wake-up; without it, you'd build the same pattern with locks and polling, badly. |
| `p2kbArchEventSystem` | `SETSE`/`WAITSE` for smart-pin events. Grounds intra-cog hardware completion without busy-wait. |
| `p2kbArchCordic` | 54-stage pipelined CORDIC with 8-clock per-cog issue. Directly justifies giving DSP its own cog (to keep that pipeline full from one cog's POV). |
| `p2kbArchStreamerIndex` | Streamer is per-cog hardware, intrinsically tied to one cog. Forces the HdmiSignalGenerator cog allocation. |

### D.4 Honest assessment of my non-P2KB reasoning

The architecture's correctness rests on three layers of authority:

1. **Hard P2 facts** (from P2KB and the silicon docs) — these are reliable.
2. **Existing project docs** — these tell me the workload, the pin map, the bandwidths. Reliable for *what the system must do*, but they contain implementation patterns I was asked to ignore.
3. **My own systems-engineering reasoning** — these are the JUDGEMENT calls in Appendix B.

Layer 3 is the riskiest. The biggest layer-3 leaps in this doc:

- **The fan-out-with-refcounts pattern as the spine.** If this is wrong for some reason I cannot see (e.g., refcount contention on locks), the whole pipeline shape changes.
- **The decision to fold decimation into commit rather than a stage.** Could be wrong if decimation logic gets complex (e.g., adaptive rates, jitter rejection).
- **The borderline calls in Appendix C.** Two of thirteen units may not exist in the final code; my justification for them is admittedly thin.

I would weight these less heavily than the cog-allocation decisions, which are mostly forced by hardware.

---

## Document History

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | 2026-05-26 | Initial functional decomposition. Derived from requirements; ignored prior cog assignments. |
| 1.1 | 2026-05-26 | Added Appendix B (decision provenance with confidence levels), Appendix C (post-decomposition audit identifying U5/U12/U13 as borderline calls), Appendix D (guidance gaps where P2KB could grow). |
