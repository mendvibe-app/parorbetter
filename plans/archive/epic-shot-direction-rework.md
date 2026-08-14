# Epic: Shot Direction Rework — Swipe Leads, Tempo Modulates

## Status: SHIPPED
Closed: 2026-08-09 — landed in `02facf3` (swipe-led path; gated transition pull; `path_error == intended_shape`). Kept for history; do not re-implement.
Related open QA: `correction-swipe-sign-convention.md` (sign playtest still open).

## Depends on: none (independent of distance-tuning and practice-swing epics)

---

## 1. The problem, in plain terms

Right now the game has two systems both trying to answer "which way did the ball go" — the player's swipe gesture, and the tempo timing grade — and they were never reconciled. Tempo currently wins most of the time, including a term that overrides swipe direction entirely on hard-hit shots regardless of what the player actually swiped. A player can swipe hard right (intending a fade) and watch the ball fly left, with no way to know why.

This was confirmed via 6 real playtest shots and a full code recon (see `recon-prompt-path-error.md` and its report). Root cause: `TempoGrade.grade()` computes a `path_error` value purely from tempo ratio error (`sign(actual_ratio − target_ratio)`), completely independent of the swipe-derived `intended_shape`. Both get blended in `ball_physics.gd`, with `path_error` weighted higher (50% vs 40% on the main term) plus an extra sign-only push scaled by shot power that ignores swipe entirely.

## 2. Grounding this in real golf

We pulled current instruction/launch-monitor sourcing before deciding on a fix, because this mechanic is central to the "real golf, not arcade" principle.

**What actually determines ball direction in real golf:**
Launch monitor data is consistent across sources: face angle at impact — not swing path — determines the large majority of where the ball starts. <cite index="5-1">Face angle determines about 75-85% of your ball's starting direction with irons, and up to 85% with driver.</cite> <cite index="8-1">Face angle controls where the ball starts. Club path controls how the ball curves. Face-to-path controls how much it curves.</cite> Path is the shot-shaping tool, not the primary direction control — exactly the lever a golfer uses on purpose to hit a draw or a fade.

**What a rushed transition actually produces — and it isn't a hook:**
The current formula assumes rushed tempo = ball goes left ("hook"), always. Real swing instruction doesn't support that. <cite index="9-1">A quick, anxious transition from backswing to downswing almost always produces an over-the-top move — the upper body outpaces the lower body and the club gets thrown over the top, creating an outside-in path.</cite> The outcome of that outside-in path depends on face angle relative to it: <cite index="9-1">an outside-in path causes a slice only when the clubface is open relative to path; if the face is square to the path, the result is a pull — a straight shot that goes left.</cite> So a rushed transition doesn't have one fixed directional signature. It biases the *path* toward outside-in, which then interacts with whatever the face (aim/swipe) was doing — pull if they match, slice if they don't. "Rushed = deterministic hook" isn't a real pattern; it's an oversimplification the current code baked in as if it were physics.

**Design implication:** tempo shouldn't generate its own independent, competing direction signal. It should *modulate the player's own swipe input* toward an outside-in bias when rushed — the same way a real rushed transition biases a real golfer's actual path, without magically overriding what their body was otherwise doing.

## 3. Design principle for the fix

- **Swipe (path relative to aim) leads direction.** This is the player's intentional shot-shaping tool, same as a real golfer's path-vs-face choice. A well-executed shot should let the player shape it on purpose.
- **Tempo doesn't get its own vote on direction.** Instead, rushing biases the swipe path toward outside-in (a real, bounded nudge, not a coin-flip override). Lingering/hanging tempo has no clean real-world directional signature (it shows up as fat contact / hanging back, not a left-right pattern), so it gets **no direction modulation** — only its existing effects on contact/balance.
- **Balance loss becomes unpredictability, not a deterministic verdict.** Real bad balance produces mishits and inconsistency, not a reliable curve direction. Replace the current deterministic amplification with bounded randomness/dispersion.
- **Contact quality still gates how much of your intent comes through** — this already exists (`_shape_authority`, PERFECT 1.0 → MISS 0.12) and is well-grounded; keep it as-is.
- **Net feel:** nail your tempo and contact → your swipe comes through clean, you can genuinely work the ball. Rush it → your shape drifts toward a real pull/slice tendency and gets less precise, exactly like a real golfer who's out of sync — not a random opposite-direction verdict.

## 4. Current architecture (for reference)

```
TempoGesture sample
  ├─► TempoGrade.grade() → path_error (SIGN FROM TEMPO ERR, independent of swipe)
  ├─► shot_routine: swing_shape (from swipe) blended with hole bias → intended_shape
  └─► ShotResult.make(power, bal, path_error, contact, intended_shape)
        └─► ball_physics.gd:
              lateral = path_error*0.50 + intended_shape*0.40   (× stability × force)
              lateral += force * 0.18 * sign(path_error)         ← swipe has ZERO input here
              spin    = path_error*(1.05−stab*0.45) + intended_shape*0.55
```

Files: `scripts/shot/tempo_grade.gd` (~218–265), `scripts/shot/shot_routine.gd` (~429–471), `scripts/shot/shot_result.gd`, `scripts/ball/ball_physics.gd` (~507–571).

Putt/chip already bypass this entirely (own line via `PuttStroke`) — **out of scope, unaffected by this epic.**

## 5. Proposed architecture

```
TempoGesture sample
  ├─► TempoGrade.grade() → transition_pull (bounded outside-in bias, RUSHED ONLY, 0 if not rushed)
  ├─► shot_routine:
  │     swing_shape        (from swipe, unchanged)
  │     swing_shape -= transition_pull            ← tempo nudges swipe, doesn't fight it
  │     swing_shape += balance_dispersion(bal)     ← bounded randomness, only when bal < 0.35
  │     shape = blend(suggested_shape, swing_shape, shape_authority(contact))   ← unchanged blend math
  └─► ShotResult.make(power, bal, shape, contact, shape)   ← ONE unified value, not two competing ones
        └─► ball_physics.gd:
              lateral = shape * 0.85   (× stability × force)   ← swipe/shape now owns direction
              spin    = shape * 0.95   (× existing scales)
              (force-sign-only push term REMOVED — no real-golf basis, was overriding swipe outright)
```

## 6. Concrete changes

### 6.1 `scripts/shot/tempo_grade.gd` — replace the path calculation

**Current (~lines 262–265):**
```gdscript
# Path: slight errors → mild curve; disaster → wild. Amplify only on true lurch.
var path := clampf(signf(err if absf(err) > 0.01 else 0.0) * abs_n * 0.35, -1.0, 1.0)
if bal < 0.35:
    path = clampf(path * (1.0 + (0.35 - bal)), -1.0, 1.0)
```

**Proposed:**
```gdscript
# Transition pull: a rushed transition (ratio under target) tends to produce an
# over-the-top / outside-in path in real golf — NOT a fixed hook or slice, since
# the resulting shot depends on face angle (the player's swipe), same as real ball
# flight laws. We only bias the player's own path toward outside-in here; we do not
# assign an independent direction. Lingering tempo (ratio over target) has no clean
# real-world directional signature (shows up as fat/hang-back, not left/right) so it
# gets no pull — PROVISIONAL: revisit if playtesting shows lingering needs one too.
var rushed_amt := clampf(-err / maxf(base, 0.01), 0.0, 1.0)  # 0 if not rushed
var pull_max := TRANSITION_PULL_MAX_PITCH if is_pitch_type(shot_type) else TRANSITION_PULL_MAX_FULL
var transition_pull := rushed_amt * pull_max
```

Add constants near the top of the file with the other tunables:
```gdscript
## How hard a fully-rushed transition biases path toward outside-in (real-golf-
## grounded: over-the-top move, not a hook). PROVISIONAL — playtest target.
const TRANSITION_PULL_MAX_FULL := 0.20
const TRANSITION_PULL_MAX_PITCH := 0.12
## Max random dispersion added to shape when balance craters below 0.35.
## Replaces the old deterministic path amplification — bad balance should feel
## unpredictable, not like a reliable extra hook.
const BALANCE_DISPERSION_MAX := 0.15
```

Update the `grade()` return dictionary (~line 315 area) to return `transition_pull` instead of `path` for full/pitch/punch. Putt/chip are ungraded here (they use `PuttStroke`) — no change needed for them.

### 6.2 `scripts/shot/shot_routine.gd` — apply pull + dispersion to swing_shape, drop the second signal

**Current (~438–457):**
```gdscript
var shape := suggested_shape
var swing_shape := 0.0
if shot_type != "putt" and shot_type != "chip":
    var lat := float(sample.get("max_lateral", 0.0))
    swing_shape = clampf(lat / 0.18, -1.0, 1.0)
    if GameState.force_perfect:
        shape = suggested_shape
        swing_shape = 0.0
    else:
        var auth := _shape_authority(contact)
        shape = clampf(suggested_shape * 0.45 + swing_shape * 0.75 * auth, -1.0, 1.0)
        if punch_mode:
            shape *= 0.55
    verdict["swing_shape"] = swing_shape
    verdict["shape_blend"] = shape
    GameState.last_tempo_metrics = verdict
```

**Proposed (insert the pull + dispersion step before the blend, keep the rest of the structure the same):**
```gdscript
var shape := suggested_shape
var swing_shape := 0.0
if shot_type != "putt" and shot_type != "chip":
    var lat := float(sample.get("max_lateral", 0.0))
    swing_shape = clampf(lat / 0.18, -1.0, 1.0)
    if GameState.force_perfect:
        shape = suggested_shape
        swing_shape = 0.0
    else:
        # Tempo modulates the player's own path — nudge toward outside-in when
        # rushed, add bounded randomness when balance is poor. Never assigns an
        # independent direction; swipe/aim still lead.
        var pull := float(verdict.get("transition_pull", 0.0))
        var dispersion := 0.0
        if bal < 0.35:
            dispersion = randf_range(-1.0, 1.0) * TempoGrade.BALANCE_DISPERSION_MAX * ((0.35 - bal) / 0.35)
        var modulated_shape := clampf(swing_shape - pull + dispersion, -1.0, 1.0)
        var auth := _shape_authority(contact)
        shape = clampf(suggested_shape * 0.45 + modulated_shape * 0.75 * auth, -1.0, 1.0)
        if punch_mode:
            shape *= 0.55
    verdict["swing_shape"] = swing_shape
    verdict["shape_blend"] = shape
    verdict["transition_pull"] = verdict.get("transition_pull", 0.0)  # keep for debug/coach
    GameState.last_tempo_metrics = verdict
```

`path` variable (currently pulled from `verdict["path_error"]` at line ~431) should be replaced by `shape` for full/pitch/punch shot types when calling `ShotResult.make()` — i.e. pass `shape` as both the path and shape argument, so there is only one direction signal from here on:

```gdscript
var path: float = shape if shot_type != "putt" and shot_type != "chip" else float(verdict["path_error"])
```
(Putt/chip keep their existing independent `PuttStroke`-derived `path_error` — unaffected.)

### 6.3 `scripts/ball/ball_physics.gd` — collapse to one direction input, drop the sign-only push

**Current (~564–571):**
```gdscript
# path_error = tempo miss; intended_shape = hole bias + swing path blend (shot_routine).
var lateral := (result.path_error * 0.50 + result.intended_shape * 0.40) * stab_term * force_mul
var spin_term := (
    result.path_error * (1.05 - result.stance_stability * 0.45)
    + result.intended_shape * 0.55
)
lateral += force * 0.18 * (1.0 if result.path_error >= 0.0 else -1.0)
```

**Proposed:**
```gdscript
# Full/pitch/punch: path_error and intended_shape are now the SAME unified value
# (swipe modulated by tempo pull/dispersion) — see shot_routine.gd. Putt keeps its
# own independent path_error from PuttStroke, unaffected by this branch's weighting.
var lateral := result.intended_shape * 0.85 * stab_term * force_mul
var spin_term := result.intended_shape * 0.95 * (1.0 + force * 0.7)
# (sign-only force push REMOVED — had zero swipe input, was the main override culprit)
```

Leave the putt branch (~523–527) and the forced-power distance wobble (~507–508) as-is — both are outside this epic's scope; confirm during implementation that ~507–508 doesn't inadvertently double-count the new unified value in a way that reintroduces a direction bias into distance (should be fine since it was already tied to `path_error` at a modest weight, and `path_error` now equals the swipe-led value — just verify no regression during driver/pitch playtest).

### 6.4 Club Coach + debug UI — no code changes needed, but confirm behavior

- `club_coach_log.gd` and the "hook bias" label already just log whatever ends up in `path_error`. Once `path_error` reflects the real, swipe-led outcome, the "hook bias" stat will self-correct over time as new shots log in — no separate fix required, but call this out to Matt: **existing history will still show the old skew until it ages out**, so don't be alarmed if Club Coach still says "hook bias" on old data right after this ships.
- `debug_controls.gd`'s "Path" line and "Shape swipe → blend" line already read the right fields — after this change they should converge (Path should stop being a mystery number disconncted from Shape). Consider adding `pull` to the debug shape line during playtest only, e.g. `"Shape swipe %+.2f → pull %+.2f → blend %+.2f"`, to make the modulation visible while verifying — can be stripped after playtest confirms it's working, or kept if useful long-term.

## 7. Acceptance criteria (using our real repro shots)

| Repro shot | Swipe | Tempo | Old Path (bug) | Expected Path after fix |
|---|---|---|---|---|
| Shot 2 (2.5:1, tgt 3, rushed) | not logged (pitch mode, N/A) | rushed | -0.15 | should track much closer to swipe/hole intent; only a bounded pull, not a standalone -0.15 |
| Shot 3 (3.2:1, tgt 3, on/lingering) | — | over target | +0.09 | shape should reflect swipe/hole only — no pull applied, since err ≥ 0 |
| Shot 4 (2.2:1, tgt 3, rushed, high transV) | -0.11 | rushed | -0.24 | modest leftward pull added to -0.11 swipe, should land noticeably less extreme than -0.24 unless swipe itself was also strongly negative |
| **Shot 5 (2.8:1, tgt 3, rushed, swipe +0.36)** | **+0.36** | rushed | **-0.09 (full sign flip — the smoking gun)** | **should stay net positive** — swipe leads, tempo only pulls it down by a bounded amount, expect roughly +0.10 to +0.25, NOT a flip to negative |
| Shot 7 (2.9:1, tgt 3, mildly rushed, swipe -0.25) | -0.25 | mildly rushed | -0.02 | small additional leftward pull on an already-negative swipe — should land somewhat more negative than -0.25, not near-zero |

**The core acceptance test is Shot 5**: a strongly-right swipe (+0.36) must never flip to a negative final path just because tempo was rushed. If it does, the fix isn't done.

Additional criteria:
- [ ] Club Coach path-avg for a test player who deliberately swipes right on every full swing (regardless of tempo) should trend positive over ~20 shots, not stay stuck negative.
- [ ] A deliberately rushed transition with a neutral (0.0) swipe should show a small, bounded negative path — never larger in magnitude than `TRANSITION_PULL_MAX_FULL` (0.20) — confirming it's a nudge, not a dominant force.
- [ ] A deliberately lingering/slow transition (ratio over target) should show zero tempo-driven path modulation — direction should match swipe/hole bias exactly (contact-quality shape authority still applies).
- [ ] Balance below 0.35 should introduce visible shot-to-shot randomness in direction on repeated identical swipes — not a repeatable deterministic skew.
- [ ] Putt and chip behavior unchanged — confirm no regression, since they don't touch any of this.

## 8. Out of scope

- Distance/power tempo tax (already fixed in the earlier PERFECT/GOOD flattening epic) — untouched here.
- Putt/chip path logic (`PuttStroke`) — untouched.
- Overclubbing / floor-committed-power work — untouched.
- Any change to `suggested_shape` (hole-defined shape bias) generation — untouched.

## 9. Provisional tuning values (playtest targets, not final)

| Constant | Proposed | Notes |
|---|---|---|
| `TRANSITION_PULL_MAX_FULL` | 0.20 | Max leftward nudge from a fully-rushed full swing. Tune down if it still feels too punishing, up if rushing feels consequence-free. |
| `TRANSITION_PULL_MAX_PITCH` | 0.12 | Pitch has a snappier target ratio (2:1) already; smaller pull. |
| `BALANCE_DISPERSION_MAX` | 0.15 | Random jitter ceiling when balance < 0.35. |
| lateral weight on `intended_shape` | 0.85 | Was split 0.50/0.40 across two competing signals; now one signal owns it. Reduced slightly from a naive 0.50+0.40=0.90 sum to leave room for the pull/dispersion already baked into that single value. |
| spin weight on `intended_shape` | 0.95 | Same reasoning, was 1.05(ish)+0.55 split. |

Matt: these five numbers are the ones to watch during playtest — everything else in this doc is structural, not tunable.

## 10. Playtest order

1. **Neutral swipe, varied tempo** — confirm rushed pulls left modestly, lingering doesn't pull at all, on-time is clean.
2. **Strong intentional swipe (both directions), rushed tempo** — this is the Shot 5 regression test. Confirm swipe direction survives.
3. **Balance-cratered shots** — confirm dispersion feels like "lost control," not a reliable extra curve.
4. **Driver, then a mid-iron, then wedge/pitch** — per your existing isolation practice, check each shot-type band separately since pull_max differs by type.
5. **Club Coach over ~20+ shots per club** — confirm "hook bias" stat starts trending toward whatever the player is actually swiping, not staying artificially negative.
6. Putt/chip sanity check — confirm zero regression (should be untouched, but verify).

---

*Grounding sources: Trackman/Titleist Learning Lab face-angle contribution data (75–85% of starting direction); Skillest, MyGolfSpy, Foy Golf Academy, and Coach Harvey instructional sources on rushed-transition → over-the-top → pull/slice mechanics.*
