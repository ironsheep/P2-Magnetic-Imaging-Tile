# Recommendation to the P2KB Agent — What the Magnetic-Imaging-Tile Project Can Contribute to Functional Decomposition

**From:** P2 Magnetic Imaging Tile project (Stephen M. Moraco)
**To:** the P2 Knowledge Base maintainer agent
**Re:** the `architecture_decomposition` reasoning layer (12 entries, `p2kbArchDecomposition*` / `p2kbArch{Force}*`)
**Date:** 2026-06-30
**KB baseline compared against:** index v3.5.0, mcp v1.4.0 (1060 entries / 58 categories; `architecture_decomposition` = 12 entries). If the layer has advanced since, re-check Part A and the Part D changeset before acting.
**Status:** recommendation / contribution memo — no KB content changed by this document

---

## 0. Why this memo exists, and the one fact that frames it

The P2KB now carries a **generative theory of P2 functional decomposition**: two axes (logical
cohesion/coupling co-designed with physical allocation onto the resource lattice), four forces
(resource ownership, data-flow contract, rate adaptation, altitude layering), five cross-cutting
forces (C1-C5), a three-plane seam model (data/control/event), an evaluation vocabulary
(coupling integer, connascence, back-pressure min-cut), a resource-budget artifact, a
first-contact procedure, and a worked derivation (the robot dog). It is a serious, well-tiered
body of work and most of this memo is *agreement* with it.

The framing fact: **this project independently derived much of that framework before the layer
existed, and recorded the holes it had to fill by hand.** The project's
`DOCs/Architecture/Object-Architecture-and-Cog-Allocation.md` Appendix D is literally titled
*"Guidance Gaps"* and opens: *"The intent is to help target future P2KB additions on object/cog
shape — Stephen noted P2KB has thin coverage on this today."* That appendix cites only
`p2kbSpin2ObjectArchetypes`, `p2kbArchCog`, `p2kbArchHub`, `p2kbArchCogAttention`,
`p2kbArchCordic`, `p2kbArchStreamerIndex` — **none of the `p2kbArchDecomposition*` keys**, because
they did not yet exist when it was written.

That gives the KB a rare asset: a **natural before/after experiment.** A practitioner predicted
the gaps (Appendix D), the KB has since built a framework, and the project then **shipped the
system and audited where the code diverged from the derived plan** (`DOCs/status-reports/
Object-Architecture-As-Built.md`). The audit is field evidence the KB's layer is currently
asserted-but-not-validated against. This memo maps the three together:

1. **Part A** — gaps the KB's new layer already closed (credit + project validation).
2. **Part B** — what this project can contribute *up* to the KB (the substance), ranked.
3. **Part C** — where the KB would, in turn, improve this project (bidirectional honesty).
4. **Part D** — hand-off: the concrete changeset, self-graded confidence per item, terminology reconciliation, and a scope guard.
5. **Appendix** — evidence index, every claim to a `file` + `KB key`.

Authority tiers below use the KB's own legend (PHYSICS / PRINCIPLE / HEURISTIC / PATTERN /
EXAMPLE) so any accepted item drops straight into an entry.

---

## Part A — Gaps the KB's new layer already closed (and the project corroborates)

Three of the project's five hand-rolled "Appendix D" patterns are now **covered** by the layer.
Recording this matters: it tells the KB which of its new entries are load-bearing in the field.

| Project Appendix-D gap (pre-layer) | KB entry that now covers it | Project corroboration |
|---|---|---|
| "Single owner per resource for pins/cogs/locks/hub" — called *"systems-engineering hygiene, not in P2KB"* | **Force 1, resource ownership** (`p2kbArchResourceOwnership`) — now a PHYSICS-grade correctness rule (OR'd pins, no bus mutex) | As-built: this invariant **held 100%** in shipped code; the audit's strongest single finding. The KB correctly promoted it from "hygiene" to "correctness." |
| "When does a one-consumer object still deserve separation?" (the U5/U12/U13 fork) | **Force 4 altitude/axis-of-change** + **C4 testability seam** + Parnas information-hiding in the canon | Project used three *different* ad-hoc criteria and got three answers; the KB now supplies the single unifying rule (split at a unit-conversion / information-hiding / testability seam, not at a reuse count). |
| "Per-cog state vs stateless library" | **Force 1 singleton-vs-instance** (DAT singleton vs VAR instance, decided by sharing topology) | Project's FrameFifoManager (DAT singleton) and PsramGraphics (per-cog VAR mailbox handle) are exactly the two cases the rule now predicts. |

**Takeaway for the KB:** the parts of the layer anchored in silicon (Force 1, the DAT/VAR split)
are precisely the parts a practitioner *could not* derive confidently without you and that
*survived contact with hardware*. That is the layer working as designed.

---

## Part B — What this project can contribute up to the KB

Ranked by leverage. Each item states the gap, the project evidence, the proposed content, and
where it slots.

### B1 — A worked **streaming-domain** derivation (fills a gap the KB itself flagged). HIGHEST.

**The gap, in the KB's own words.** `p2kbArchCrossCuttingForces` carries a `breadth_gap_note`:

> "high-bandwidth streaming domains (video, audio, fast-ADC capture via the streamer/DMA) are a
> distinct domain type with their own decomposition (a streamer-owning cog with double-buffered
> hub hand-off). This layer does not yet carry a worked streaming example; the spatial-computing
> entry covers the relevant mechanisms and smells."

The only worked derivation today (`p2kbArchWorkedDerivationRobotDog`) is a **control-plane
machine**: two I2C buses, mailbox *words*, no bulk movement, "hub bandwidth modest." It exercises
Forces 1/2-control/3-slew/4 and the cross-cutting objects — but it never exercises the **data
plane**, the **streamer**, **hub-bandwidth pressure**, the **funnel smell**, or
**rate-domain decimation**. Those are exactly the forces a streaming design lives or dies on.

**This project is that missing domain, end to end.** A fast-ADC capture pipeline:

```
SensorAcquirer (cog 1, ~1370 fps, inline-PASM ADC)  -- DATA-plane producer
   -> FIFO_SENSOR (hub frame pool)
   -> Decimator (cog 0: fan-out + per-FIFO rate reduction)   -- the rate-domain crossing
   -> FIFO_HDMI / FIFO_OLED
   -> HdmiRenderer (cog 4) -> PSRAM framebuffer -> HdmiSignalGenerator (cog 3, STREAMER) -> TMDS
   -> OledRenderer (cog 5, inline-PASM SPI stream)
   + PsramBroker (cog 2): one shared PSRAM bus, per-cog mailbox arbitration
```

It walks the first-contact procedure to a **defensibly different** object set than the robot dog,
which is the whole point of a second worked example: it proves the *grammar* generalizes rather
than the *catalogue* repeating.

**Recommendation.** Author `p2kbArchWorkedDerivationStreamingPipeline` (EXAMPLE tier, same
illustrative-not-normative contract as the robot dog), deriving a fast-ADC -> fan-out -> dual-display
streaming machine. It should make visible the three things the robot dog cannot:

- **The data plane as the dominant plane.** Frames are bulk (128 B), rate-defined (1370 fps in,
  ~60 fps out), and move through a hub frame pool — the streamer/FIFO path, not mailbox words.
- **A producer-pinned-to-a-cog-by-determinism cut.** SensorAcquirer owns its cog because *"any
  interruption corrupts a sample"* (a HARD, PHYSICS-grade cut) — the streaming analogue of Force 1
  that the robot dog's lazy buses never show.
- **A streamer-owning cog** (HdmiSignalGenerator: pixel clock = sysclock/10, *"the streamer is
  intrinsically one cog"*) — the concrete form of the "streamer-owning cog with double-buffered hub
  hand-off" the KB names but never derives.

The full, walkable derivation that satisfies this recommendation follows in B1.1, formatted for
direct transcription into the entry.

#### B1.1 — The worked derivation (drop-in for `p2kbArchWorkedDerivationStreamingPipeline`)

The following walks the first-contact procedure on this machine, step by step, each step tagged
with the force/plane that drives it — the same schema as `p2kbArchWorkedDerivationRobotDog`
(`reading_contract` -> `the_machine` -> `derivation_steps` 1-9 -> `resource_budget` ->
`what_to_notice`). It is written so the P2KB agent can transcribe it directly into a YAML entry.
**Authority tier: EXAMPLE — illustrative-not-normative**, frozen at one point in time. Objects are
named by ROLE, not by file.

**`reading_contract`** — This entire derivation is an illustration of the streaming/data-plane
domain. The forces, the procedure, and the evaluation vocabulary are the normative content; this
exercises them. A different streaming machine (audio I2S, camera DVP, logic capture) yields a
different but equally sound result. Read it to see the data plane and the streamer drive the cut;
never copy an object boundary into another machine — run the procedure against that machine.

**`the_machine`** (the only input the derivation starts from):
- A **fast-ADC capture front-end**: an 8x8 Hall-sensor tile read through a hardware multiplexer and
  one serial ADC, bit-banged over a 5-wire interface (CS P0, counter-clock CCLK P1, MISO P2,
  counter-clear CLRb P3, SCLK P4, analog AOUT P6). The 64 sensors are stepped by the mux counter and
  read in a strict serpentine sequence; each sample has a settle+convert deadline. Capture runs at
  ~333-375 fps sustained (up to ~1370 fps capable).
- A **PSRAM bus** holding the display framebuffer, electrically shared by more than one cog.
- An **HDMI output** (TMDS, 640x480 @ 60 Hz, pixel clock = sysclock/10).
- An **OLED panel** over SPI (~17 ms blocking transfer per frame; panel max ~55 fps).
- A **UART** host link (115200 baud, single-char command set L / 1-4 / S / P).
- A future **DSP** consumer (CORDIC-based) that wants *every* frame at full rate.
Nothing about the object set is given; it is derived below.

**`derivation_steps`**

- **Step 1 — Enumerate the wires** *(Force 1, resource ownership)*. Serialized, stateful resources:
  (a) the tile acquisition interface (mux counter + ADC SPI + AOUT) — one timing-exact serial
  sequence; (b) the PSRAM bus; (c) the HDMI TMDS pins; (d) the OLED SPI bus; (e) the UART.
  **Output:** five serialized resources.
- **Step 2 — Triage against the smart pins** *(physical axis / smart-pin absorption)*. HDMI pixel
  generation is **streamer-absorbed** (per-cog hardware, not a smart pin but hardware nonetheless).
  UART maps cleanly to a **smart-pin async-serial** mode. OLED SPI maps to a **smart-pin sync-serial**
  mode — *candidate, deferred* (see B10: chosen as inline-PASM streaming for the 17 ms blocking
  budget, with the smart-pin path recorded as the re-evaluation trigger). The tile acquisition
  *sequence* (step mux -> settle -> convert -> shift-in, x64 in serpentine order) is a multi-step
  stateful protocol no single smart-pin mode covers — it **survives triage** and needs a deterministic
  software owner. **Output:** HDMI -> streamer; UART -> smart-pin; OLED SPI -> smart-pin (deferred);
  the acquisition sequence remains for cog ownership.
- **Step 3 — Assign owners** *(Force 1)*. Group by wire + timing budget:
  - Tile front-end: sole device on its bus, behind a hard per-sample deadline ("any interruption
    corrupts a sample") -> **one owning cog (SensorAcquirer), VAR-instance transport** (nothing
    shares the wire). *HARD / PHYSICS cut.*
  - PSRAM bus: shared by the renderer (writes) and the signal generator (reads) -> a **resident
    broker cog** owns it, arbitrating via **per-cog mailbox slots** (B5). Forced by PHYSICS: the P2
    has no cog-independent DMA, so a shared bus needs an always-resident arbiter cog.
  - HDMI TMDS: the streamer is intrinsically one cog; pixel clock = sysclock/10 cannot be perturbed
    -> **its own cog**, nothing shares it. *HARD.*
  - OLED SPI: ~17 ms blocking per frame -> **its own cog**, so the blocking paces nothing else.
  - Composition root -> **cog 0**. DSP (CORDIC) and UART/SD comms -> **two reserved cogs**.
  **Output:** cog map = {0 app, 1 sensor, 2 PSRAM broker, 3 HDMI-signal, 4 HDMI-render, 5 OLED;
  6 reserved DSP, 7 reserved comms} — 6 used, 2 reserved.
- **Step 4 — List the cadences** *(Force 3, rate adaptation)*. SensorAcquirer ~333-375 fps; HDMI
  content ~62.5 fps (panel 60 Hz); OLED ~53.6 fps (panel ~55 fps max); future DSP **every frame**.
  The mismatch is the domain's whole point: **one fast producer, several slower consumers at
  *different* rates, plus one full-rate consumer.** **Output:** a rate-domain boundary at the
  producer->display fan-out; three distinct downstream cadences; one full-rate path.
- **Step 5 — Resolve rate conflicts** *(Force 1 x Force 3 tension — but the dual of the robot dog's)*.
  Here the cadences live on **different consumer cogs**, not on one shared bus, so the robot dog's
  resolution (cooperative tasks within one owning cog) **does not apply**. The streaming resolution
  is a **buffered fan-out**: a hub frame pool feeding **per-consumer typed FIFOs**, each decimated to
  its consumer's rate (1-in-6 HDMI, 1-in-7 OLED; full-rate DSP). This is the rate adapter, and it
  corresponds to no chip and no feature — it fell out of the rate *mismatch*. **Output:** a shared
  frame pool + typed FIFOs + per-FIFO decimation as the rate-domain decoupler.
- **Step 6 — Draw the seams** *(Force 2, per plane)*. The fan-out seam decomposed into three planes:
  - **DATA plane:** 128-byte frames move producer -> consumers through a hub **frame pool with typed
    ring FIFOs** (FIFO_SENSOR / FIFO_HDMI / FIFO_OLED, depth 16, 32-slot pool). Bulk movement, not
    mailbox words. *Contract: buffered fan-out (refcount vs copy — see B2; shipped copy-and-commit).*
  - **CONTROL plane:** `getNextFrame` / `commitFrame` / `releaseFrame`, single-writer-per-slot, the
    frame pointer bounds-checked before the lock is taken; one lock guards pool+queue.
  - **EVENT plane:** **COGATN/WAITATN** wakes the HDMI consumer (2-clock signal, zero hub
    bandwidth); the OLED consumer **polls** (the lazy case).
  - The renderer -> PSRAM -> signal-generator path is a *separate* control-plane seam (broker
    mailboxes, B5). **Output:** the per-seam, per-plane contracts.
- **Step 7 — Layer each branch** *(Force 4, axis of change)*. Sensor branch by unit conversion:
  raw 14-bit counts (transport) -> mux-index -> sensor-index **serpentine remap** + calibration
  `raw - baseline[i] + mid` (semantic) -> bipolar **color** (policy/visualization). Calibration is a
  **mode of the acquirer, not a tier** (baseline table and raw samples live in the same cog;
  separating would force cross-cog data sharing). **Force-4 memory-escape, exercised in the field:**
  the acquirer *folds* transport + chip-read + calibration into one **inline-PASM** loop on the
  496-register cog — a stated tier collapse that saved ~800 us/frame; the collapse is documented, so
  the lost seam is a deliberate trade. **Output:** layered stacks, with one recorded collapse.
- **Step 8 — Place the cross-cutting objects** *(C1-C5, plus the proposed C6)*. **C1 safety:** lighter
  than the robot dog (no actuators) — per-cog **stack-overflow sentinels**. **C2 translation:** the
  single-char serial command set is an external vocabulary -> a **command parser at the edge**.
  **C3 config:** per-tile **calibration baselines** + the **serpentine topology map** (per-board data)
  isolated from logic. **C4 testability:** per-layer bring-up (mux scan -> ADC read -> topology remap
  -> colorize -> display), each runnable alone; the FIFO regression test. **C5 lifecycle:** the
  Application as **sequencer** — PSRAM/HDMI bring-up before renderers, cog launch order, pre-seeded
  stacks. **C6 observability (proposed, B4):** decimation kept as a *visible* Spin2 stage rather than
  folded into commit; test-side instrumentation around FIFO calls. **Output:** cross-cutting objects
  placed relative to the tree.
- **Step 9 — Reconcile against budget and deadline** *(force tensions + resource budget)*. The
  binding line is **hub bandwidth**, which the robot dog never reached (see table). The hardest
  deadlines — the HDMI pixel clock (sysclock/10) and the per-sample ADC settle — are each isolated on
  a dedicated cog so nothing perturbs them. The design **fits**; deferred items (refcount fan-out,
  smart-pin OLED SPI, DSP/comms cogs) are *named, not forgotten*. **Output:** the final object-and-cog
  set, validated against the lattice and the two hardest deadlines.

**`resource_budget`** (the artifact, filled as steps 3-5 assigned owners):

| Resource | Limit | This design | Note |
|---|---|---|---|
| Cogs | 8 | 6 used, 2 reserved | each used cog has a one-sentence forcing reason (B6) |
| Smart pins | 64 | tile (6) + OLED SPI + HDMI TMDS + UART | OLED SPI is a smart-pin-absorption candidate (deferred, B10) |
| Locks | 16 | **1** (frame pool + queue) | plan wanted 2; simplified in the field |
| CORDIC | 1 shared | reserved for DSP (cog 6) | not yet contended |
| **Hub bandwidth** | egg-beater 8-clk rotation | **the binding constraint** | 128 B/frame pool traffic + 640x480x3 @ 60 Hz framebuffer via the **streamer** (not mailbox words -> avoids the hub-saturation smell) + PSRAM traffic; copy-and-commit adds 2 x 128 B/frame (B2 cost) |
| Cog RAM | 512 longs / 496 regs | acquirer folds 3 tiers into inline PASM | the Force-4 memory-escape (step 7) |

**`what_to_notice`** (the streaming-domain analogues of the robot dog's three):
1. The producer is pinned to a cog by **determinism (sample integrity)**, not by bus ownership — the
   streaming form of Force 1 the robot dog's lazy buses never show.
2. The rate adapter is a **buffered fan-out** (pool + typed FIFOs + decimation), **not**
   cooperative-tasks-in-a-cog — because the cadences live on different consumer cogs, not one shared
   bus. The robot-dog resolution does not transfer; the grammar produces a different, equally sound
   adapter. *This is the single clearest proof that the layer is a grammar, not a catalogue.*
3. **Hub bandwidth is the binding budget line** (the robot dog's was cogs). The streamer carries bulk
   pixels and the frame pool carries bulk samples; the copy-vs-refcount choice (B2) is a
   bandwidth/pool-pressure trade visible *only* in this domain.
4. The one dynamic connascence crossing a cog boundary is the FIFO's **execution-order** requirement
   (commit/publish ordering) — the project's real corruption incident — tamed by commit discipline,
   exactly as `p2kbArchEvaluationVocabulary` prescribes.

This single contribution closes the KB's own stated breadth gap with a complete, shipped, walkable
derivation — the streaming counterpart the robot dog cannot supply.

### B2 — Name the **fan-out data-flow contract** and the refcount-vs-copy trade (Force 2 extension). HIGH.

**The gap.** `p2kbArchDataFlowContracts` enumerates contracts: blocking call / latest-wins mailbox
/ ring buffer / request-ack / lock-free published telemetry. It does **not** name the contract this
project's entire spine is built on: **one producer -> a refcounted shared-frame pool -> multiple
typed FIFOs -> one consumer per FIFO -> COGATN wake-up.** The project flagged this in Appendix D.1
as *"the spine of the magnetic-tile viewer and would be the spine of any video, audio, or
sensor-fusion system on the P2,"* noting `buffered_io_object` exists only as single-producer/
single-consumer.

**The project's hard-won evidence (this is the part the KB cannot get anywhere else).** The plan
chose **refcount zero-copy** (one frame, N consumers, pointer + refcount). The shipped code chose
**copy-and-commit** (duplicate the frame into one slot per consumer). The as-built audit
*quantifies* the trade and draws the lesson:

- Copy-and-commit costs *"three pool slots and two 128-byte copies per dual-display frame"*; at 4
  consumers it needs a *~64-slot pool* where refcount would need *~16*. The real cost is **pool
  pressure, not bandwidth.**
- **Lesson 1 (verbatim):** *"Refcount-based zero-copy must be designed in from day one.
  Retrofitting refcounts into a working FIFO manager touches every commit, every release, and
  every error-path bounds-check. The right time to choose refcount-fanout is before the first
  consumer ships."* This is an **irreversibility** property — a Force-2 contract choice that cannot
  be deferred.

**Recommendation.** Add to `p2kbArchDataFlowContracts` a sixth named contract — **"fan-out
publication (refcounted pool vs per-consumer copy)"** — PRINCIPLE tier, with:
- the choice rule: *refcount when frames are large and consumer count grows; copy-and-commit when
  frames are small or the pool can absorb N x depth and you value commit/release simplicity;*
- a HEURISTIC escape: *the cost is pool slots ~ (consumers x FIFO_depth) under copy vs ~ depth
  under refcount;*
- the **irreversibility note**, which is genuinely new evaluation content: *some Force-2 contracts
  are cheap to change post-ship (latest-wins <-> buffered) and some are not (introducing a refcount
  rewrites every seam). Decide the expensive ones at derivation time.*

### B3 — A fold-vs-stage criterion for decimation, plus the **observability reversal** (Force 3). HIGH.

**The gap.** `p2kbArchRateAdaptation` covers rate-domain crossing (3a), slew/easing (3b), and
one-bus-many-cadences (cooperative tasks in a cog). It does **not** address the question the project
calls out in Appendix D.1: *when does multi-rate fan-out decimation fold into the producer's
commit, vs. live in its own cog/stage?*

**The project's evidence — and a documented reversal.** The plan folded decimation **into
`commitFrame()`** (*"not a separate unit... adding a dedicated decimator cog would buy nothing and
add latency"* — graded JUDGEMENT). The shipped code **reversed this** to a visible Spin2 stage in
cog 0. The as-built meta-review states why, and it is the seed of a new idea:

> *"Decimation-as-bus-property loses observability. Folding decimation into `commitFrame()` is
> elegant but makes the per-FIFO decision invisible in `debug()`. The as-built Spin2 stage is
> uglier but lets you watch counters directly."*

**Recommendation.** Add to `p2kbArchRateAdaptation` a HEURISTIC sub-rule for **decimation
placement**: *fold rate-reduction into the producer's commit when the decimation state is bounded
(a counter per output) and the computation is cheap; promote it to a visible stage/cog when the
policy is non-trivial (averaging, peak-hold, adaptive/jitter-rejecting rates) **or when the
rate-domain decision must be observable at runtime.*** State the escape both ways. This is also the
hand-off point to B4.

### B4 — **Observability** as a missing evaluation axis (new lens, or cross-cutting force C6). HIGH / novel.

**The gap, and why it is real.** The KB's `p2kbArchEvaluationVocabulary` judges a cut with three
tools — coupling integer, connascence, back-pressure min-cut — **all of which optimize correctness
and performance.** None of them can express *"this cut is right but you cannot watch it work."* Yet
across three independent project artifacts, runtime observability behaves exactly like a
decomposition force that legitimately overrides elegance:

- The **decimation reversal** (B3): a less-coupled, more-elegant cut (fold into commit) was
  *rejected in the field* purely for observability.
- `CLAUDE.md` mandates **test-side instrumentation**: *"Keep production libraries clean of test
  instrumentation... Debug never executes inside critical sections."* This is an
  observability-driven placement rule for where instrumentation lives relative to the structural
  tree — i.e., it *spans or guards* the tree, the KB's own definition of a cross-cutting force.
- `SPIN2-AUTHORING-GUIDE.md` §5.2 requires a **single exit point per method**, justified
  *specifically* so *"a `debug()` placed after an early return silently never executes... a single
  exit point guarantees all end-of-method instrumentation is always reached."* A structural rule
  whose entire rationale is observability.

The KB's existing `C4 testability seam` is close but distinct: C4 is *bring-up isolation* (can I
exercise this layer standalone before assembly?). This is *runtime observability* (can I watch this
seam's decisions in `debug()` on live hardware, in production?). They cut differently — the
decimation reversal passed C4 (the folded version was perfectly testable) and still failed
observability.

**Recommendation (pick one, prefer the first).**
- **Option 1 — a fourth evaluation lens** in `p2kbArchEvaluationVocabulary`: *observability of a
  cut* — "after this boundary is drawn, can each side's decisions be made visible at runtime
  without violating a critical section?" with the P2-specific note that `debug()`/COGATN make this
  cheap and that folding a decision into an atomic commit hides it. PRINCIPLE tier.
- **Option 2 — a cross-cutting force C6, "observability / instrumentation seam"** in
  `p2kbArchCrossCuttingForces`, placed (like the others) after the structural tree, hosting the
  test-side-instrumentation and single-exit-point disciplines as its concrete manifestations.

This is the project's strongest *novel* contribution: a force the KB does not currently model,
evidenced by a real design that was changed in production to satisfy it.

### B5 — The **per-cog mailbox broker** pattern: one bus, many *cogs* (Force 1 / archetype). MEDIUM-HIGH.

**The gap.** Force 1's singleton transport covers *one cog, many register-level callers* (the
robot-dog DAT singleton). The project surfaces the orthogonal case the KB has no archetype for:
**one serialized bus shared by many *cogs*, arbitrated by a resident broker cog with a private
mailbox slot per client cog** (`psram_ptr := psram.pointer() + cogid() * 12`; sign of length
encodes direction; broker round-robins). The as-built calls this *"one of the cleanest
plan-to-code matches"* and the audit promotes it to a reusable P2 idiom; Appendix D.1 notes
*"P2KB has no archetype for it."* It recurs for SD cards, multi-channel DAC, network controllers —
anything one-bus/many-cog where the P2's lack of an independent DMA controller forces a
*cog* to be the arbiter.

**Recommendation.** Add a PATTERN-tier entry (generative skeleton, marked non-normative) —
**"shared-bus broker with per-cog mailboxes"** — and cross-link it from `p2kbArchResourceOwnership`
as the resolution when Force 1's owned resource must serve *multiple cogs* rather than multiple
in-cog callers. Ground it in the PHYSICS the project cites: P2 has no cog-independent DMA, so a
shared hardware bus needs an always-resident arbiter cog.

### B6 — The **"one forcing sentence per cog"** positive test (resource budget). MEDIUM.

**The gap.** `p2kbArchResourceBudget` has the *negative* signal — *"running out of cogs means too
coupled; re-cut, don't cram."* The project contributes the matching *positive* gate, which it
elevated to a stated invariant: *"every cog has a one-sentence forcing reason. If you cannot state
the forcing reason in one sentence, the cog is misallocated."* It is operationalized in the plan's
Appendix B.1 as a per-cog table (timing / ownership / blocking / throughput), and the as-built
confirms it caught cog inflation (the design shipped on **6 cogs, with 2 deliberately reserved**,
not 8 filled for the sake of it).

**Recommendation.** Add to `p2kbArchResourceBudget` a HEURISTIC: alongside each "cog assigned" row,
require a one-sentence forcing reason drawn from a closed set {determinism, resource ownership,
blocking I/O, throughput/pipeline}; a row without one is a re-cut signal *before* you run out of
cogs (the positive complement to the existing negative trigger).

### B7 — A concrete **frame-pool sizing** relationship (data-plane buffer sizing). MEDIUM.

**The gap.** The KB points at the theory — the data plane cites *synchronous dataflow (buffer
sizing)* and Lee & Messerschmitt — but gives no P2-concrete formula. The project asked the exact
question in Appendix D.2 (*"How big should the frame pool be? Nobody documents the formula"*) and
the as-built now supplies an empirical anchor: *pool >= slowest-consumer-stall x producer-rate*,
and under copy-and-commit fan-out, *pool ~ consumers x FIFO_depth* (shipped at 32 slots for a
2-consumer design; would need ~64 at 4 consumers).

**Recommendation.** Add a worked sizing note to the data-plane treatment (in
`p2kbArchDataFlowContracts` or `p2kbArchRateAdaptation`), HEURISTIC tier, tying buffer depth to
consumer count and worst-case stall, with the copy-vs-refcount multiplier from B2.

### B8 — **Empirical validation of the authority-tier hierarchy** (the natural experiment). MEDIUM / meta.

The KB's foundational thesis is that physics-anchored cuts are non-negotiable and pattern-anchored
cuts are negotiable — encoded as the PHYSICS > PRINCIPLE > HEURISTIC tiering. This project is a
**field test of that thesis**, and it passed: the as-built audit's headline finding is

> *"Plan elements anchored in P2 hardware reality (pin ownership, streamer cog, PSRAM bus
> arbitration) survived 100%. Plan elements anchored in distributed-systems patterns
> (refcount-fanout, multi-FIFO with shared frames) survived less well."*

The plan even pre-graded every decision HARD / STRONG / JUDGEMENT with source tags (P2KB / PRJ / SE
/ REASONING) — a confidence taxonomy that maps cleanly onto the KB tiers — and the **HARD/PHYSICS
decisions are the ones that survived to code; the JUDGEMENT decisions are the ones that diverged.**

**Recommendation.** Cite this as a real-world corroboration in `p2kbArchDecompositionMethod` (the
generative-theory entry) when it argues "object shape is derived, not chosen": the project is
evidence that the *derived-from-hardware* cuts are stable and the *chosen-from-pattern* cuts drift,
which is the method's central claim observed in production.

### B9 — Adopt the **as-built divergence audit** as a recommended methodological artifact. MEDIUM / meta.

The KB teaches *forward* derivation (the first-contact procedure produces an object-and-cog set).
This project adds the *backward* half that makes the forces falsifiable: after shipping, **audit
where the code diverged from the derived plan, grade survival by authority tier, and feed the
result back.** The pairing of `Object-Architecture-and-Cog-Allocation.md` (the derivation) with
`Object-Architecture-As-Built.md` (the audit) is the template. The KB glossary already says its
canon *"is a starting set; when a system pushes past it, name the new discipline and grow an
entry"* — the as-built audit is the **mechanism** for noticing when that happens.

**Recommendation.** Add to the first-contact procedure (or as a short companion entry) a closing,
post-ship step: *pair every derivation with an as-built audit that records which cuts survived and
which diverged, tagged by the authority tier of the reasoning behind each.* This is how the KB's
tiers stay honest rather than asserted — every project that does it returns evidence like B8.

### B10 — A documented **smell-with-escape** instance for the catalog (negative-but-honest). LOW.

`p2kbArchSpatialComputing` lists *"bit-banging an absorbable protocol"* as a smell. The project's
OledRenderer streams SPI via **inline PASM** rather than a smart-pin SPI mode — the smell's
signature is present. But the project did *not* trip blindly into it: Appendix B.1 records the cog-5
decision as STRONG with an explicit escape condition — *"Share if SPI moves to streamer/DMA —
legitimate alternative; flagged as future re-evaluation if the SPI bus goes hardware-streaming."*

This is a useful catalog instance precisely because it shows the KB's own discipline working: *a
smell is a signature to check against, not a verdict.* Here the signature fired, the engineer
evaluated it against the 17 ms-per-frame blocking constraint, chose inline-PASM deliberately, and
**documented the escape condition and the re-evaluation trigger.** 

**Recommendation.** If the smell catalog ever carries worked instances, this is a clean one: a real
case where the bit-bang signature is present and the HEURISTIC escape is correctly exercised and
recorded — reinforcing that smells inform, not condemn.

---

## Part C — Where the KB would, in turn, sharpen this project (bidirectional)

For honesty and to show the comparison ran both ways: the layer is *ahead* of this project's own
docs in four places, and adopting it would improve the project.

- **Connascence vocabulary.** The project reasons in "coupling" (a vibe); the KB's
  `p2kbArchEvaluationVocabulary` offers connascence as a typed, countable tool. The project's real
  corruption incident (the `*** CORRUPTION AFTER ... ***` scar tissue in `mag_tile_viewer`) is
  textbook **connascence of execution order across a cog boundary** — the FIFO's "bump the seq
  counter last" requirement. The KB names and tames exactly that failure (publish-last converts
  dynamic -> static). The project would have had the vocabulary to predict the bug.
- **The three planes (data/control/event) per seam.** The project treats the frame-pool seam as
  one thing. Splitting it the KB's way — data plane (the 128 B frame bytes), control plane
  (commit/release/refcount discipline), event plane (COGATN wake) — and designing each separately
  is sharper than the project's current single-mechanism FIFO treatment.
- **Smart-pin absorption triage (first-contact step 2).** Running the KB's step-2 triage would have
  forced the OLED-SPI smart-pin question to the surface at *derivation* time rather than as a
  deferred B.1 footnote.
- **The reference canon.** The project's author reached intuitively for GStreamer/ROS-style
  dataflow; the KB names the durable canon underneath it (Kahn process networks, synchronous
  dataflow, latency-insensitive design, GALS, systolic arrays). Citing those would let the next
  architect reach for the literature instead of re-deriving.

---

## Part D — Hand-off: changeset, confidence, and reconciliation

This part makes the memo actionable for a maintainer agent: the concrete KB edit per item, how
much to trust each one, the terminology merge the glossary's `reconciliation_rule` requires, and
what to leave alone.

### D.1 Proposed changeset, with self-graded confidence

Confidence uses *this project's* own idiom (the same scale its Appendix B grades decisions by), so
you know which items are forced and which are judgement calls worth your scrutiny:
**HARD** = forced by a silicon fact or by the KB's own stated gap; **STRONG** = well-grounded in
canon or shipped evidence, departing needs a reason; **JUDGEMENT** = one defensible option of
several — push on it.

| Item | Action | Target KB key | Proposed canonical name / form | Confidence |
|---|---|---|---|---|
| B1 | **CREATE** | `p2kbArchWorkedDerivationStreamingPipeline` (new EXAMPLE entry; B1.1 is the drop-in body) | "Worked derivation (EXAMPLE) — a fast-ADC streaming pipeline, end to end" | **HARD** — fills the KB's own `breadth_gap_note`; derivation is shipped |
| B2 | **EDIT** | `p2kbArchDataFlowContracts` | add 6th contract: **"fan-out publication"** (refcount-pool vs per-consumer-copy) + irreversibility note | **STRONG** |
| B3 | **EDIT** | `p2kbArchRateAdaptation` | HEURISTIC sub-rule: **decimation placement** (fold-into-commit vs visible stage) | **STRONG** |
| B4 | **EDIT** (prefer lens) | `p2kbArchEvaluationVocabulary` (4th lens) *or* `p2kbArchCrossCuttingForces` (new **C6**) | **"observability of a cut"** | **JUDGEMENT** — novel; reconcile vs C4 first (see D.3) |
| B5 | **CREATE** + cross-link | new PATTERN entry; link from `p2kbArchResourceOwnership`; consider archetype in `p2kbSpin2ObjectArchetypes` | **"shared-bus broker with per-cog mailboxes"** (one bus, many *cogs*) | **STRONG** |
| B6 | **EDIT** | `p2kbArchResourceBudget` | HEURISTIC: **"one forcing sentence per cog"** (positive complement to "out of cogs") | **STRONG** |
| B7 | **EDIT** | `p2kbArchDataFlowContracts` or `p2kbArchRateAdaptation` | HEURISTIC: **frame-pool sizing** (depth x consumers; copy/refcount multiplier) | **JUDGEMENT** — empirical anchor, not a derived formula |
| B8 | **EDIT** | `p2kbArchDecompositionMethod` | add field-corroboration citation (tiers validated in production) | **STRONG** |
| B9 | **EDIT** | `p2kbArchFirstContactProcedure` (or companion entry) | closing practice: **pair derivation with an as-built audit** | **STRONG** |
| B10 | **EDIT** (optional) | `p2kbArchSpatialComputing` | worked smell-with-escape instance (inline-PASM SPI) | **JUDGEMENT** — low priority |

If you take only three: **B1** (the worked derivation), **B2** (the fan-out contract +
irreversibility), **B4** (observability). They are the items the layer cannot currently express.

### D.2 Terminology reconciliation (merge by force, do not duplicate)

The glossary's `reconciliation_rule` says to merge by the underlying force, not the label. This
project's docs predate your canonical names, so here is the mapping — adopt your names, not ours:

| This project's term | KB canonical name to reconcile it to |
|---|---|
| "decimation" / "frame skipping" | rate adaptation — rate-domain crossing (Force 3) |
| "multi-FIFO fan-out" / "refcounted pool" | data-flow contract (Force 2); proposed sub-type "fan-out publication" |
| "single owner per resource" | resource ownership (Force 1) |
| "one forcing reason per cog" | resource budget — positive test (proposed, B6) |
| "coupling" (used loosely) | coupling integer **and** connascence (evaluation vocabulary) |
| "per-cog mailbox broker" | resource ownership — cross-cog resolution (proposed PATTERN, B5) |
| "calibration as a mode, not a unit" | C3 per-unit configuration + Force-4 (a mode, not a tier) |
| **"observability / debug visibility"** | **no current KB term — this is the genuine new-force candidate (B4)** |

### D.3 Scope guard — what to leave alone, and the one caution

- **Do not disturb** the parts the project independently validated (Part A): Force 1 / DAT-vs-VAR,
  the three-plane seam model, and connascence. They survived contact with hardware here; treat
  this memo as evidence *for* them, not a request to change them.
- **The worked derivation (B1.1) is EXAMPLE / illustrative-not-normative.** Carry the banner across
  verbatim. No object boundary in it is a rule; if a future reader copies one into another machine,
  that is the failure mode the reading_contract exists to prevent.
- **B4 is the only genuine new-force proposal — apply `reconciliation_rule` deliberately.** Confirm
  it is *not* already covered by `C4 testability seam` before adding it. It is not: C4 is *bring-up
  isolation* (exercise a layer standalone before assembly); B4 is *runtime observability of a live
  decision in production*. The decimation reversal passed C4 and still failed observability — that
  divergence is the proof they are different forces. Prefer the lightest landing (a 4th evaluation
  lens) over minting a force; escalate to C6 only if the lens cannot hold the test-side-
  instrumentation and single-exit-point disciplines that cluster under it.

---

## Appendix — Evidence index

Every claim above traces to a project source and (where relevant) the KB key it bears on.

| # | Claim | Project source | KB key it touches |
|---|---|---|---|
| B1 | Streaming domain is the KB's own flagged gap; this project is that domain | `DOCs/status-reports/Object-Architecture-As-Built.md` (cog map, 6 cogs); `DOCs/Architecture/Object-Architecture-and-Cog-Allocation.md` B.1 (cogs 1/3 HARD) | `p2kbArchCrossCuttingForces` (breadth_gap_note); `p2kbArchWorkedDerivationRobotDog`; `p2kbArchSpatialComputing` |
| B2 | Refcount zero-copy vs copy-and-commit; pool-pressure cost; "design in from day one" | As-Built Lesson 1 + cost section; Allocation-doc D.1, B.4 (fan-out as most-fragile) | `p2kbArchDataFlowContracts` |
| B3 | Decimation fold-vs-stage; the observability reversal | As-Built meta-review (decimation observability); Allocation-doc B.2 (JUDGEMENT, fold into commit) | `p2kbArchRateAdaptation` |
| B4 | Observability as an evaluation force | As-Built (decimation reversal); `CLAUDE.md` test-side instrumentation policy; `SPIN2-AUTHORING-GUIDE.md` §5.2 single exit point | `p2kbArchEvaluationVocabulary`; `p2kbArchCrossCuttingForces` |
| B5 | Per-cog mailbox broker (one bus, many cogs) | As-Built (`psram_ptr := psram.pointer() + cogid()*12`, "cleanest match"); Allocation-doc D.1, B.3 | `p2kbArchResourceOwnership` |
| B6 | "One forcing sentence per cog" positive test | Allocation-doc B.1 invariant + Appendix C cog-inflation guard; As-Built (6 cogs, 2 reserved) | `p2kbArchResourceBudget` |
| B7 | Frame-pool sizing relationship | Allocation-doc D.2 + B.2 (pool=32); As-Built cost section (~64 at 4 consumers) | `p2kbArchDataFlowContracts` / `p2kbArchRateAdaptation` |
| B8 | Authority-tier hierarchy validated in the field | As-Built headline finding; Allocation-doc Appendix B confidence+source grading | `p2kbArchDecompositionMethod` |
| B9 | As-built audit as a recommended practice | The plan + as-built doc pairing itself | `p2kbArchFirstContactProcedure` (glossary "grow an entry") |
| B10 | Documented smell-with-escape (OLED inline-PASM SPI) | Allocation-doc B.1 cog 5 (STRONG + escape condition) | `p2kbArchSpatialComputing` (smell catalog) |
| C | KB ahead of project: connascence, three planes, smart-pin triage, canon | `mag_tile_viewer.spin2` corruption scar tissue; `isp_frame_fifo_manager.spin2` single-FIFO seam | `p2kbArchEvaluationVocabulary`; `p2kbArchDataFlowContracts`; `p2kbArchFirstContactProcedure` |

**One-line summary for the KB agent:** this project's highest-value contributions are (1) the
**worked streaming derivation** the layer explicitly lacks, (2) the **fan-out contract + refcount
irreversibility** lesson for Force 2, and (3) **observability as an evaluation force** the current
vocabulary cannot express — each backed by a shipped system and an honest as-built divergence audit
that doubles as field validation of the layer's own authority-tier thesis.
