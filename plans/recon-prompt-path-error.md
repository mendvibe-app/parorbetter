# Recon: Shot direction is driven by tempo timing, not swing path

## Context

Debug playtesting surfaced that on-screen shot direction ("Path" in the debug HUD, and the actual ball's lateral flight) does not appear to be primarily driven by the player's swipe gesture. It appears to be driven mostly by tempo ratio error instead. This recon is to confirm the mechanism end-to-end, map every consumer of the two relevant values, and flag anything else nearby that looks off — **no fixes yet, just findings**.

## What we already traced

- `scripts/shot/tempo_grade.gd` (`grade()`, around line 218 and 263):
  `err := r - target` (actual back:through ratio minus target ratio)
  `path := clampf(signf(err) * abs_n * 0.35, -1.0, 1.0)`
  amplified further if `bal < 0.35`.
  This `path` becomes `verdict["path_error"]`.

- `scripts/shot/shot_routine.gd` (around line 431–456):
  Separately, `swing_shape` is derived from the gesture's `max_lateral` sample, blended with the hole's `suggested_shape` into `shape` (debug-labeled "Shape swipe → blend").
  `shape` is passed into `ShotResult.make()` as `p_shape` → becomes `result.intended_shape`.
  The *tempo-derived* `path` (not `shape`) is passed as `p_path` → becomes `result.path_error`.

- `scripts/ball/ball_physics.gd` (around line 507–571):
  Comment at line 564 confirms: `path_error = tempo miss; intended_shape = hole bias + swing path blend`.
  Both feed into final lateral flight, roughly:
  `lateral = path_error * 0.50 + intended_shape * 0.40` (plus a second weighted term ~1.05 / 0.55)
  **plus** an additional solo directional push: `force * 0.18 * (1.0 if path_error >= 0.0 else -1.0)` — this uses only the *sign* of `path_error`, scaled by shot power, independent of `intended_shape`.

- Net effect: because most swings (per Club Coach log) run tempo ratio under target more often than not (negative `err`), the tempo-driven path term structurally biases nearly every full-swing club toward hook/left — this shows up in the Club Coach `path avg` hook bias across almost every club except putter. On high-power shots, the solo force-scaled push can be strong enough to override the swipe direction entirely (confirmed repro: swipe +0.36 / blend +0.27, final path -0.09).

## What to confirm / map

1. **Full call graph for `path_error` and `intended_shape`.** Grep every read site of both fields (not just `ball_physics.gd`) — confirm there isn't a third consumer we haven't seen (UI tracer color, shot report copy, club coach logging, aim assist, etc). Report every file/line.

2. **Is `intended_shape` used anywhere else meaningfully**, or is `ball_physics.gd` its only real consumer? If it's only ~40% weight in one formula, confirm there's no compounding elsewhere that would change that picture.

3. **Confirm the exact weighting math in `ball_physics.gd` lines ~507–571** — pull the full function(s), not just the grep hits, and lay out precisely how `path_error`, `intended_shape`, `force`, and `stance_stability` combine into final lateral distance. We want the real relative influence of tempo-vs-swipe, not an approximation.

4. **Check shot types individually**: full swing, pitch, punch, chip, putt. `shot_routine.gd` already exempts putt/chip from the `swing_shape` blend ("Putt/chip already own line via PuttStroke"). Does `path_error`'s tempo-driven formula still apply to putt/chip, or is it also bypassed there? We want a clean per-shot-type matrix of "does tempo timing affect this shot type's direction, does swipe affect it."

5. **Confirm whether this is documented/intentional anywhere** — comments, commit history, design docs in the repo — that tempo timing is *supposed* to steer shot direction (e.g., as a stand-in for "rushed transition opens/closes the face" real-golf logic), versus whether this looks like an unintentional side effect of two systems being combined without realizing they'd fight each other.

6. **Range Mode / practice mode**: confirm whether this same `path_error` formula runs in Range Mode (a recent playtest shot in Range Mode logged no Tempo/Shape lines at all in the debug — flag why, and whether Range Mode shots get *any* path_error applied, tempo-derived or otherwise).

7. **Any other reads of `err` or `transition_ratio`/`transV`** that might have similar "silently steers a different visible metric" behavior — we ruled out `transition_ratio` (the debug's "transV") as a factor in `path`, but worth a scan for other places tempo-adjacent internals leak into player-facing outcomes without being reflected in the value the player actually controlled.

## Output format

A short written report (not a diff, not a fix) with:
- File + line references for every finding above
- The per-shot-type matrix from #4
- A plain statement of whether this looks intentional or unintentional, with your reasoning
- Any additional oddities spotted while in this code, flagged separately and not acted on

Do not change any code in this pass.
