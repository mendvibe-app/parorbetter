# Design — Effort-Based Swing Input

**Status:** concept, not an epic. No code until the mechanic is agreed.
**Scope:** this is bigger than one phase. It touches the core input loop, not just the flight
model, and probably deserves its own multi-part track alongside (not inside) the flight
rebuild.

---

## The problem, stated precisely

Today, three things that should be coupled are not:

| Quantity | Who sets it | Measured? |
|---|---|---|
| Direction | Player, by aiming | yes |
| **Distance / power** | **The game**, from aim distance ÷ club_max | — |
| Effort (backswing length) | Player, by how far they drag | **yes — but discarded** |

`backswing_len` is captured every swing (`tempo_gesture.gd:804`) and used *only* as a floor
check for the balance penalty. It never touches distance. Distance is entirely a function of
where the aim marker sits, computed once, before the swing starts.

The player's physical input — how hard they actually swing — currently changes nothing about
where the ball goes. Only tempo *ratio* (back:through timing) is graded. A full-effort drag
and a deliberately soft one, executed with identical timing, produce an identical shot.

**This is why swinging harder for more distance produces bad shots.** The player is trying to
play a skill the mechanic doesn't model. That instinct is correct golf; the game just has no
slot for it.

---

## Why this matters more than a tuning pass

It's not that the numbers are wrong — it's that a real, correctly-instinctive input is
discarded. Every other correction in this rebuild fixed a formula. This one adds a missing
control.

It also explains two things we treated separately and shouldn't have:

- **"I can't choose 85% vs 100%"** — because power was never a player input, only an aim
  output.
- **The unreachable overswing penalty** — `force_factor`'s mash tax exists to punish
  overswinging, but nothing the player does is currently "overswinging." It's a penalty for a
  choice the player can't make.

Both resolve for free if effort becomes real.

---

## The proposed mechanic

**Two independent, already-separate signals become the two real inputs. Nothing new is
invented; one existing signal stops being thrown away.**

- **Tempo ratio** (already graded) → contact quality. Did you sequence the swing correctly.
- **Backswing amplitude** (already measured, currently wasted) → **swing power delivered.**
  How much swing you actually made.

Aim keeps setting **direction** and produces a **target distance** — what the shot calls for.
That target distance, run through the existing solve, produces a **target amplitude**: the
backswing length that would deliver exactly that power. The player is now swinging *at* a
size, not just *at* a rhythm.

### Why this is real golf, not a new video-game system

Tour Tempo's core finding: downswing duration is roughly fixed by the kinetic sequence;
backswing length is what varies with intended power, and ratio holds close to 3:1 across
effort levels. A committed three-quarter swing and a full send are both roughly 3:1 — they
differ in amplitude, not ratio. That is exactly the split this proposes: ratio grades
technique, amplitude delivers power. The game already builds its short-game shot types
(pitch, chip, flop, and now punch) on exactly this idea — different lane, different target,
same graded ratio. This generalizes that pattern to the full swing instead of only shot types.

### Confirmed against every comparable golf game the project already treats as reference

This split — amplitude sets power, a separate signal sets quality/direction — is not one
design option among several. It is the converged solution across forty years of golf-game
input design, arcade and mobile alike:

| Game | Amplitude → | Separate axis → |
|---|---|---|
| PGA Tour 2K25 (EvoSwing) | Stick pull-back length sets power | Separate meter stops set path push/pull and hook/slice |
| Golden Tee | Trackball backswing distance sets power | Forward-swing angle sets direction/curve |
| Golf Clash | Drag length sets power | Separate release-timing meter sets accuracy |
| WGT (3-click) | First click sets power | Second/third click sets accuracy and curve |

None of these use one signal for both power and quality. All of them separate "how far did
you pull back" from "how well did you time the release."

Golden Tee's own manual states the amplitude/speed split explicitly: *"the speed of the back
swing makes no difference to the shot, it's the amount of back swing that matters."* Speed of
the pull is discarded; only its length counts for power. That is precisely `backswing_len`
(amplitude) versus tempo ratio (timing/speed) in this codebase — the same split, independently
arrived at by both real-golf mechanics (Tour Tempo) and every major golf game's control
scheme.

**This resolves the open "smaller vs. bigger" question below.** Aim does not need to become
vague, and amplitude does not need to fight it for control of distance. The converged pattern
is: amplitude is the real power dial, tempo ratio is the real quality dial, and they are fully
independent — aim keeps setting direction, and distance stops being computed from aim and
starts being read off the swing the player actually makes.

### The tension becomes literal, not simulated

Real golf's actual skill — "reach for more and tempo gets harder to hold" — currently doesn't
exist mechanically; it's implied by flavor text ("Through too quick for that backswing"). If
amplitude becomes real, it can become **structurally true**: a longer backswing is
harder to time consistently (more distance to cover in the same downswing window), so
overswinging naturally strains tempo control rather than needing an artificial penalty bolted
on. The existing tempo tolerance math may already produce some of this for free — needs
verification, not assumption.

### Existing architecture that already fits

This is not a new subsystem. It's the punch fix, generalized:

- Per-shot-type lane geometry already exists (`address_hint`, `top_hint`, `_uses_short_lane`)
- Per-shot-type tempo targets already exist (`target_ratio`)
- A "swing bigger than needed costs you" tax already exists (`force_factor`, the 0.94/0.88
  mash constants) — it's just currently driven by an invisible quantity instead of the
  player's actual swing

Nothing here requires inventing new mechanics. It requires making the amplitude the pad
already measures actually mean something.

---

## What has to change (high level — not a build spec yet)

This list is for scoping the size of the work, not an implementation plan.

1. **A mapping from backswing amplitude to power.** Roughly linear off the pad, calibrated per
   shot type the way lane length already is.
2. **Aim's role shifts.** It still sets direction. Whether it still sets an exact target
   distance (with amplitude as an accuracy/execution layer around that target) or whether aim
   becomes a looser "general direction and rough range" while amplitude does the real work is
   the single biggest open question below.
3. **`recommended_power` / `resolve_distance` relationship.** Phase 4 just made these one
   clean owner of *target* distance. That doesn't go away — it becomes "what distance does
   this club and this amplitude produce," queried the other direction.
4. **Every shot-type lane** (full, pitch, chip, flop, punch) needs an amplitude-to-power
   mapping, not just a length floor.
5. **Tempo tolerance may need to scale with amplitude** if the "bigger swing, harder to time"
   tension is meant to emerge structurally rather than being asserted.
6. **UI/feedback.** The player needs to see the target amplitude (the swing size the shot
   calls for) the way they currently see the tempo guide, or this is unplayable blind.
7. **Club Coach, ghost guide, and dispersion data** are all currently keyed on
   power-from-aim. All would need to shift interpretation.

This is easily the largest single change since the flight rebuild started, and it changes the
core input loop rather than a formula underneath it. It should run as its own track, not as a
sub-phase of the flight work.

---

## Decided

**1. Overswing is visible and deliberate, with a cost.** The player sees the target/pocket
amplitude and chooses to exceed it, the same way a real golfer chooses to "go for it." This
makes `force_factor`'s existing mash tax mean something for the first time — right now it
punishes a choice nobody can make.

**2. Everything must match.** No shot type can stay on the old aim-solved-power model while
others move to amplitude. Punch's shot-type-by-shot-type rollout does not apply here — a
mixed state (full swing effort-based, pitch still aim-based) would be worse than either
model alone, since the player would be learning two different mental models for one input
gesture. This is a coordinated system change, not an incremental one.

**3. Flat replacement.** No mode toggle, no legacy setting. New feel is the feel.

These three decisions turn this from a design question into a scoped initiative — see the
companion roadmap doc for phasing.

---

## What I'd suggest as a starting scope

Land it on **full swings first** (open question 2 above still stands — short game can follow
once this is proven). Aim sets direction and shows the *player's* target line; the game can
still suggest a recommended club and a suggested backswing length as a coaching aid the way it
currently shows a tempo ghost — but the swing the player actually makes, not the aim marker,
is what determines distance. That mirrors every comparable exactly: a suggested/ghost target
to help you learn the club, real control lives in the pull.

---

## Not proposing yet

- Line numbers, function signatures, or a branch. This needs your steer on the four questions
  above first.
- Any change to Phase 5 sequencing. This can run in parallel with or after the flight rebuild
  phases — it's a different system.
