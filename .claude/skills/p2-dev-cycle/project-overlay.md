# {{PROJECT_NAME}} overlay — p2-dev-cycle

Additive rules layered on top of the central `p2-dev-cycle` skill.
These do not replace any central step — they augment specific anchors.

## Augments §1 — Compile

**Query p2kb-mcp before hypothesizing on Spin2 compile errors.** When
the compiler reports an unfamiliar instruction, symbol, operator
behavior, or language feature, run `p2kb_get("<term or phrase>")`
before guessing. The MCP carries authoritative Spin2 / PASM2 reference
keyed to the running pnut-ts behavior — checking it first routinely
saves an iteration of trial-and-error fixes.

**Spin2 identifier-collision pitfalls.** When the compile error reads
like a name collision, missing-identifier, or "unexpected symbol" near
a parameter or local declaration, suspect `DOCs/policy/SPIN2-AUTHORING-GUIDE.md`
Rule 1.3 first. Known collisions in this project's idiom:
`bool`, `string`, `send`, `cogId`, `result` (and any case-variant
thereof, since Spin2 is case-insensitive). Rename per the guide's
"Use instead" column.

**The Spin2 Authoring Guide is the compile bar.** Beyond the central
pitfalls list, `DOCs/policy/SPIN2-AUTHORING-GUIDE.md` Parts 1 (Language
Rules) and 5 (Coding Practices) document every silent-bug-producing
pattern in this project's idiom (Unicode in code, `=>` vs `>=`,
empty-string `@""`, typed-pointer version directive, etc.). When a
compile error or a runtime symptom doesn't yield to the central
diagnostic arsenal, scan the guide for the matching rule before
escalating.

## Augments §5 — Diagnose

**Typed-pointer rename as a default workaround.** When the failure
mode is "obscure compile error near a `^Type pName` declaration that
doesn't immediately point at the pointer itself," apply the central
skill's workaround (rename the pointer) without further diagnosis —
this matches Spin2 Authoring Guide Rule 1.7 and is the standard
remedy in this codebase.

**Garbage in terminal output is rarely hardware.** When DEBUG baud
is verified against `{{P2_DEBUG_BAUD}}` and the terminal still shows
garbled output, the next hypotheses in this project are (in order):
(1) non-ASCII characters in `debug()` strings — Spin2 Authoring Guide
Rule 1.1 forbids them; (2) the project ran from FLASH instead of the
intended RAM download (the central skill's boot-from-flash signal
applies); (3) actual hardware fault. Burn (1) and (2) before reaching
for a multimeter.
