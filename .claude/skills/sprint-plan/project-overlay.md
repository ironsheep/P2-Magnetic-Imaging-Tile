# {{PROJECT_NAME}} overlay — sprint-plan

Additive rules layered on top of the central `sprint-plan` skill.

## Augments §2 — Code research pass

**Spin2 conformance bar.** When the sprint will touch any `*.spin2`
file under `src/`, `DOCs/policy/SPIN2-AUTHORING-GUIDE.md` is required
reading in the §2 research pass — before plan deliverables are
written, not during the writing.

The plan must call out which sections of the guide the sprint depends
on (e.g. "this sprint adds a new PUB method to `isp_tile_sensor.spin2`
— Part 4 doc-comment rules apply; the new method must follow the §5.2
single-exit-point pattern"). Any intentional deviation from a guide
rule is an explicit numbered decision in the plan with a stated
reason — not a silent omission.

This applies regardless of sprint shape (new feature, bug fix,
refactor, conformance sweep, performance work) because the guide is
authored against silent-bug-producing patterns, not feature shape.

## Augments §4 — Write the plan document

**P2KB lookups before naming Spin2 primitives.** When a plan deliverable
names a specific PASM2 instruction, smart-pin mode, or built-in Spin2
operator that the planner does not already have direct evidence for,
run `p2kb_get("<primitive>")` and quote the authoritative description
into the plan. Plans that name primitives from memory have a higher
rate of mid-sprint surprise; the MCP lookup is cheap insurance.
