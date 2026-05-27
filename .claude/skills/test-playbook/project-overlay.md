# {{PROJECT_NAME}} overlay — test-playbook

Additive rules layered on top of the central `test-playbook` skill.

## Augments §2 — Exercise format

**Test-side instrumentation discipline.** Production library code in
this project (`isp_*.spin2`) is kept debug-free as a hard rule —
every `debug()` call lives in the *test* code, wrapped around the
library invocations the test exercises. When authoring an exercise
that calls a library method, the exercise wraps the call with a
preceding `debug()` (announcing the call + arguments) and a following
`debug()` (logging the return value). This produces a transcript that
shows what the library was asked to do and what it answered, without
ever requiring debug code inside the library.

The full rationale and examples live in `CLAUDE.md` under
"Debug Instrumentation Policy" — the playbook follows that policy.

**ASCII-only in `debug()`.** Per `DOCs/policy/SPIN2-AUTHORING-GUIDE.md`
Rule 1.1, every `debug()` string in exercise code uses only printable
ASCII (`0x20`–`0x7E`). No emoji status markers (no `✓`, `✗`, `⚠️`).
Use `PASS` / `FAIL` / `OK` / `ERROR` / `+` / `-` instead. Non-ASCII
characters break the terminal display silently (the terminal flips
into hex-dump mode) and break the build under `pnut-ts -d`.

**Multi-COG exercises label cogs by role.** When an exercise exercises
concurrent behavior across cogs (FIFO producer/consumer, decimator
pipeline, parallel display drivers), every `debug()` string in cog
code begins with the role label (`PRODUCER:`, `CONSUMER:`, `SENSOR:`,
`HDMI:`, `OLED:`). The auto-prefixed `CogN` is sequential; the role
label is semantic. The combined output reads as a semantic transcript
that anyone can follow without first deducing which cog runs what:

```
Cog1  PRODUCER: Calling getNextFrame()...
Cog1  PRODUCER: Returned frame at 0x00012345
Cog2  CONSUMER: Calling dequeue()...
Cog2  CONSUMER: Returned frame at 0x00012345
```

`test_fifo_regression.spin2` is the reference exercise — new
multi-cog playbooks should mirror its labeling.

## Augments §4 — Account for the verification surface's nature

**Most exercises in this project require hardware.** P2 work without
`{{CANONICAL_TEST_TARGET}}` attached is limited to compile-time
validation. Mark every exercise's hardware-dependency explicitly so
the playbook reader knows which exercises can run in CI / a container
(compile-only) and which need a board attached (download + log
observation). The hardware-only exercises are the majority — that is
not a defect of the playbook, it is the shape of the project.
