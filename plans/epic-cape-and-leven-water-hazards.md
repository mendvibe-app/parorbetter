# Epic: Cape Hole + Leven Diagonal Water Hazards

Two new water hazard shapes, both real named golf-course templates, both built as
extensions of hazard placement + the already-shipped Sharpened Dogleg Corner elbow
geometry. No fairway data model changes. Ship and playtest Phase 1 (Leven) standalone
before touching Phase 2 (Cape) — Cape reuses Phase 1's rotated-water primitive, so a
broken Phase 1 breaks Phase 2 too.

## Why these two, and why together

Today water can only ever be one of three shapes per hole, and all three are placed at
a single point, axis-aligned: `ROLE_ISLAND_RING` (fixed 3-box ring), `ROLE_CARRY`
(straight band perpendicular to the fairway), `ROLE_EDGE` (a small fixed oval off to one
side). None of them can angle across the fairway or follow its curve, so we can never
build the "closer to the water = better angle in" decision that defines real risk/reward
water holes.

Both new shapes are real, named course-design templates (not invented for this doc):

- **Leven template**: a hazard cutting diagonally across the fairway landing zone. The
  tougher landing spot (closer to the hazard) earns the better angle into the green.
- **Cape template** (C.B. Macdonald, e.g. Mid Ocean Club No. 5, Pebble 18, Sawgrass 18):
  the fairway kicks toward a lake that runs the length of the hole. Hug the shoreline off
  the tee for a short angle in; play away and face a longer, harder second shot.

Leven is the cheap, standalone version of that same decision. Cape is the full version,
and it's built by literally doubling Leven's diagonal panel to match the two-segment
elbow that `_use_sharp_dogleg()` already draws. That's why they're one doc.

## Current code (grounded)

- `scripts/course/hole_data.gd:15-20` — hazard roles are strings: `greenside`,
  `landing`, `carry`, `edge`, `island_ring`. No diagonal/angled role exists.
- `scripts/course/hole_controller.gd:848-870` (`_add_water_sprite`) — the only water
  placement primitive. Builds an axis-aligned `Sprite2D` + `Area2D`/`RectangleShape2D` at
  a center point. **No rotation is ever applied** — this is the actual reason nothing can
  angle across the fairway today.
- `scripts/course/hole_controller.gd:666-711` — `_fairway_center_at(along)` /
  `_elbow_fairway_x(along)`: when `_use_sharp_dogleg()` is true (dogleg layout + toggle,
  on by default per `scripts/autoload/game_state.gd:101`), the fairway is two straight
  segments meeting at `hole.corner_position`, blended by `hole.corner_tightness`. This is
  the exact geometry Cape needs to follow — we don't need new curve math, just two water
  panels laid over the two segments that already exist.
- `scripts/course/hole_generator.gd:753-756` — dogleg bunkers already snap to the
  **inside of the corner** (`side = -1` for `DOGLEG_LEFT`, `1` for `DOGLEG_RIGHT`) — this
  is the same side real Cape holes put the water on ("fairway kicks toward the hazard").
  Both new hazards reuse this side convention, not a new one.
- `scripts/course/hole_generator.gd:781-793` (`_build_hazards`) — water branch only ever
  appends one spec. `_cull_hazards(out, 3)` at line 794 already allows up to 3 total
  hazards per hole, so adding a second water spec isn't blocked, just never attempted.
- Archetypes with `prefer_dogleg: true` and high `water` weight already exist and are
  unused for this: `risk_reward` (par 4, water 1.55, hazard_side 0.92, bend 1.45) and
  `hazard_gauntlet` (par 5, water 1.65). `classic_dogleg` (par 4, water 0.9) is the
  natural home for Leven-only holes that don't need the full Cape treatment.

## Phase 1 — Leven diagonal carry

**New hazard role**: `HoleData.ROLE_DIAGONAL := "diagonal"` alongside the existing role
constants at `hole_data.gd:16-20`.

**New primitive**: extend `_add_water_sprite` (or add `_add_water_sprite_rotated`) to
accept a `rotation_deg: float` and apply it to both the `Sprite2D.rotation` and the
`Area2D.rotation` — the `CollisionShape2D`/`RectangleShape2D` inherits the parent
`Area2D`'s rotation for free, no polygon math needed.

**New placement function** `_place_diagonal_creek(along, half_h, angle_deg, side)`:
same center-point logic as today's `_place_carry_creek` (`hole_controller.gd:828-839`),
but instead of a fixed axis-aligned rect spanning `_fairway_half * 2 + 80`, build a
narrower band (fairway width, not padded as wide) rotated by `angle_deg`, biased toward
`side` so the "closer to the corner cut = shorter" read is legible. Reuse the same
soft-reject-toward-tee logic against `_clears_green()` that `_place_carry_creek`
already has.

**Provisional tuning** (playtest targets, not final):
- `angle_deg`: 28–35° off the tee→green axis. Steeper reads as more punishing; shallower
  reads as barely different from the existing straight carry.
- `along`: on dogleg layouts, lock to `corner_position ± 0.05` (same convention the
  corner-guarding sand already uses at `hole_generator.gd:775`). On non-dogleg layouts,
  fall back to `rng.randf_range(0.42, 0.62)` like today's carry creek.

**Generator hookup**: in `_build_hazards` (`hole_generator.gd:781-793`), add a branch —
when `layout` is `DOGLEG_LEFT`/`DOGLEG_RIGHT` and a coin flip favors diagonal over the
existing straight carry, emit `_haz("water", HoleData.ROLE_DIAGONAL, side, corner_position, size, 0)`
instead of `ROLE_CARRY`. Start this at ~40% of the water roll on dogleg holes so straight
carries stay in rotation too — total replacement removes a shape you already have working.

## Phase 2 — Cape shoreline

**Gate**: only fires when `_use_sharp_dogleg()` is true. This is a hard dependency, not
a nice-to-have — the shoreline is built by matching the elbow's two segments, and
without the sharp corner there's no elbow to match (the smooth 3-point curve has no
straight segments to lay a panel over).

**New hazard role**: `HoleData.ROLE_SHORELINE := "shoreline"`.

**New placement function** `_place_shoreline(side, corner_position, corner_tightness, pinch)`:
1. Sample `_fairway_center_at(along)` at `along = 1.0` (tee), `along = corner_position`
   (the elbow), and `along = 0.0` (green end) — the same three points
   `_elbow_fairway_x` already uses internally.
2. Build two diagonal water panels with the Phase 1 rotated primitive, one per segment
   (tee→corner, corner→green), each offset outward from the fairway edge on `side` by
   `_fairway_half + margin`, rotated to match that segment's own bearing so it hugs the
   fairway edge instead of sitting parallel to the hole's long axis.
3. `pinch` (0.0–1.0, new provisional tunable) controls which end hugs tighter: `0.0` =
   tight near the green (classic "green juts near the water" Cape read), `1.0` = tight
   near the tee (rewards an early aggressive cut, per Mid Ocean's actual shape). Start at
   `0.3` — slightly green-weighted, matching the majority of the named examples found.
4. Skip/shrink the green-end panel if it would violate `_clears_green()` — same
   safety rule every other hazard placement already follows.

**Generator hookup**: in `_build_hazards`, gate `ROLE_SHORELINE` behind
`layout == DOGLEG_LEFT or DOGLEG_RIGHT` AND `arch.get("force_cape", false)` — a new
archetype flag rather than a random roll, since this is a hole *identity*, not a random
hazard. Set `force_cape: true` on `risk_reward` (par 4) and `hazard_gauntlet` (par 5).
Both already have `prefer_dogleg: true` and the highest `water` weights in the table, so
they're already trying to be this hole — we're just giving them the shape to match.

**Provisional tuning**: shoreline `margin` (distance water sits from the fairway edge)
start at 6–10px tighter than the existing corner bunker's placement so the water visibly
guards the same cut line the bunker used to, not a separate wider swath.

## Explicitly out of scope

- **Greenside water wrap** ("green surrounded on three sides" — the full historical Cape
  definition). `ROLE_GREENSIDE` today only handles `kind == "tree"` or `kind == "sand"`
  (`hole_controller.gd:745-751`) — water was never wired into that branch. Real, but a
  separate future epic once the shoreline itself is confirmed to feel right.
- Split/optional fairways — still a separate, bigger future epic per prior discussion.
- Any change to `_fairway_center_x`, `_elbow_fairway_x`, or `corner_tightness` math —
  Phase 2 only *reads* these, never modifies them.
- Extending either hazard to `CHUTE`, `BI_TIER`, or `ISLAND` layouts.
- New art assets — reuse `TEX_WATER_CREEK` for Phase 1, `TEX_WATER` tiled/scaled for
  Phase 2's panels, for now. Flag for a follow-up art pass once shapes are confirmed fun.

## Acceptance criteria

- Leven diagonal carry visibly angles across the fairway (not perpendicular) and reads
  as "cut it closer, save yards" on `classic_dogleg` and `risk_reward` holes.
- Cape shoreline only ever appears on dogleg layouts with sharp corners active; never
  spawns on smooth-bend or non-dogleg holes.
- Shoreline visibly follows the elbow — the two panels should look like one continuous
  lake bending at the corner, not two disconnected rectangles.
- Water collision (`entered_hazard`, `_lie == "Water"`) works identically for both new
  shapes — no new penalty/drop logic needed, this is placement-only.
- `_clears_green()` and pin-clearance rules hold for both; no hazard ever silently
  swallows the green or the cup.
- No regression to existing `ROLE_CARRY` / `ROLE_EDGE` / `ROLE_ISLAND_RING` holes.

## Playtest order

1. Leven diagonal carry alone, several dogleg holes, before touching Phase 2 at all —
   confirm the angle reads correctly and the risk/reward decision is legible.
2. Cape shoreline on `risk_reward` (par 4) — confirm the two panels join cleanly at the
   corner and `pinch` feels right at the 0.3 starting value.
3. Cape shoreline on `hazard_gauntlet` (par 5) — longer hole, confirm the shoreline
   doesn't overwhelm a hole that already has more hazards in play.
4. Confirm `_cull_hazards` cap of 3 isn't silently dropping the shoreline on holes that
   also roll bunkers/trees — check `hole_generator.gd:794` output for Cape holes.
