# Swing-Input Phase 5 — Reconcile the Aim-Solve Path

**Track:** swing-input-rework-roadmap.md, Phase 5 of 7
**Branch:** `feature/aim-solve-reconciliation`, from main
**Gameplay change:** likely none if scoped correctly — this phase is about what a stale
number is *used for*, not about changing any shot's outcome.

---

## The roadmap undersold this phase, the same way it undersold flight Phase 4

The roadmap called this "retire the aim-solve path" and assumed `recommended_power()` /
`solve_committed_power()` had already faded into a coaching-hint role once amplitude took
over power. **Traced all eleven call sites — that assumption is wrong.** These functions are
still fully authoritative for nearly everything about *aim*, not power:

| Call site | What it decides |
|---|---|
| `hole_controller.gd:1522` (`_begin_range_swing`) | Where the aim marker lands, aim radius |
| `hole_controller.gd:1545` (`_aim_force_preview`) | Force-tax preview shown to the player |
| `hole_controller.gd:1575` | `_aim_lock_yards` — the aim marker's locked distance |
| `hole_controller.gd:2182` | Tree-clearance preview distance (`_aim_tree_clearance`'s input) |
| `hole_controller.gd:2233` | "Committed total yards" — the honest-preview readout |
| `aim_control.gd:27` | Where the aim point sits when overclubbed |
| `shot_routine.gd:165` | `committed_power` → feeds the on-pad advisory target marker |

**One genuine confusion this phase must resolve:** `committed_power` is simultaneously used as
a real physics input in some places (aim marker position, tree-clearance preview, force-tax
preview) and as a pure UI advisory in exactly one place (the target marker on the swing pad,
via `amplitude_for_power(committed_power, pad_type)`). Those are fundamentally different
roles wearing the same variable name, and that's what "retire the aim-solve path" actually
needs to untangle — not delete the functions, reconcile their two jobs.

**What's already correct and needs no work:** `club_coach_log.gd` only records
`actual_yards`, `path_error`, tempo ratio, and contact tier — all downstream of the real,
amplitude-driven shot. Nothing in Club Coach reads a stale aim-solved number. That part of
the roadmap's acceptance criterion is already true.

---

## Why this matters even though power is already correct

Every one of the seven call sites above still assumes **aim distance determines what the shot
will do** — because before this rework, it did. Now, for full/pitch/flop/punch/chip/putt,
distance actually comes from the player's pull, not from where they aimed. That means:

- **The aim marker, the tree-clearance preview, and the force-tax preview are all previewing
  a shot the player didn't necessarily swing.** They show what *would* happen if the player's
  amplitude matched their aim exactly — which, per swing-input Phase 1's own finding, isn't
  guaranteed (that's the entire "overswing is a real, visible choice" mechanic).
- This isn't necessarily wrong — a preview based on "if you execute the recommended pull" is
  reasonable, the same way a real caddie's yardage assumes a normal strike. But it needs to be
  **honest about what it's previewing**, and right now nothing distinguishes "this is what the
  aim implies" from "this is what will actually happen."

---

## The actual shape of this phase

Not deletion. **Three separated roles, currently tangled into one:**

1. **Advisory target** — what pull length would match this aim. Already correctly wired via
   `amplitude_for_power(committed_power, pad_type)` feeding the pad marker. Keep as-is.
2. **Preview distance** — what the aim marker shows, what tree-clearance preview uses, what
   the "committed total yards" readout displays. Currently computed from `solve_committed_power`
   as if it were the real shot. **This should stay computed the same way** — it's a reasonable
   assumption for a preview — but needs to be labeled/treated as a preview based on hitting the
   target, not silently presented as fact.
3. **Force-tax preview** (`_aim_force_preview`) — shows whether the *recommended* pull would
   trigger the mash tax. Should stay tied to `solve_committed_power`'s recommendation, since
   that's specifically previewing "if you pull to the target, does it cost you" — which is a
   legitimate question distinct from "what will you actually do."

**None of these are wrong to keep computing from `solve_committed_power`.** The fix is making
sure nothing downstream (Club Coach, confirmed clean; any other stat tracking) accidentally
treats a preview value as an actual outcome, and that the UI itself doesn't overstate the
preview's certainty now that amplitude — not aim — decides the real shot.

---

## Investigation before any code

1. **Confirm nothing besides Club Coach reads these values expecting them to equal the actual
   outcome.** Full grep, not just the sites already found — report the complete list of
   consumers of `solved["power"]`, `solved["true_pct"]`, and `recommend` across all seven
   sites.
2. **Check whether the aim marker/lock distance ever visibly disagrees with the actual shot
   outcome in a way that reads as a bug** rather than "you didn't pull to the target." If the
   UI currently implies "the ball will land here" rather than "aim for here," that's a real
   finding, not a hypothetical.
3. **Decide, and report the reasoning:** does the UI need copy or visual treatment change
   (e.g., "target" language instead of implying certainty), or is the current framing already
   honest enough given the target marker exists on the pad? This is a legibility judgment, not
   a pure code question — report your read, don't assume.

---

## Out of scope

- Any change to how amplitude drives power. Settled in Phases 1–4.
- Any change to `force_factor`, `POWER_POCKET`, or the mash tax mechanics themselves.
- Club Coach — confirmed already correct, no changes needed.
- The swing-input pad legibility findings (target/ceiling visual hierarchy, meter/path
  separation, impact/follow-through visibility). Separate track, separate epic.
- Deleting `recommended_power()`/`solve_committed_power()`. They're load-bearing for aim
  previews and stay that way.

---

## Acceptance criteria

1. Every consumer of `solve_committed_power`/`recommended_power` is accounted for and
   classified as one of: advisory target (correct, unchanged), legitimate preview (correct,
   possibly needs clearer framing), or a bug (previously undiscovered, needs fixing).
2. Club Coach confirmed to read only actual-outcome data — regression-checked, not just
   re-asserted.
3. If any UI copy/treatment changes, it's reported with before/after, not silently altered.
4. All `*_check.py` pass.
5. Flight goldens unchanged — this phase touches aim/preview logic, not physics.

---

## Playtest verification

1. Aim at a target, note the preview (aim marker, tree-clearance line, force-tax indicator).
   Swing with a pull that deliberately doesn't match the advisory target — pull shorter, then
   pull longer on separate shots. Confirm the actual outcome differs from the preview in a way
   that reads as "I did something different from the recommendation," not as a bug.
2. Aim at a target where the recommendation would trigger mash tax. Confirm the force-tax
   preview correctly flags it before the swing.
3. Play several holes normally. The target feeling: previews should read as guidance, not as
   guaranteed outcomes — since outcomes now depend on the swing, not the aim.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- This phase may turn out to need very little code change and mostly investigation +
  reporting + possibly UI copy. Don't invent a bigger refactor than the findings support.
- If investigation item 2 finds a real disagreement-reads-as-bug case, that's the actual
  priority of this phase — report it clearly and propose the smallest fix, not a redesign.
