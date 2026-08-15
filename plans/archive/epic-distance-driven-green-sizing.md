# Epic: Distance-driven green sizing

**Status: SHIPPED 2026-08-15** (`feature/rough-pacing-greens-stack`). Device feel is playtest.
**Scope:** `hole_generator.gd` green sizing only.
**Risk:** Medium — green size feeds pin placement, green book, and putting difficulty.

---

## 1. The problem

Green size currently scales off course-progression difficulty `t`, not off approach
length.

**`scripts/course/hole_generator.gd:332`**
```gdscript
var green_size := lerpf(0.95, 0.22, t) + size_bias + rng.randf_range(-0.04, 0.04)
```

So easy holes get big greens and hard holes get small ones, regardless of the shot being
played into them. That's backwards from real architecture, where target size is a
function of approach shot length.

Real principle, from Brauer's conversion of the USGA Slope Rating field research:
<cite index="19-1">approach shot accuracy is related to length; target size must increase
proportionally to approach shot length, with a slight jump over 180 yards, and bogey
players need about 20 percent more depth than width for all approach shots.</cite>

Consequence in-game: a 182-yd par 3 early in a round gets a huge green, and a 120-yd
wedge hole late gets a tiny one. Both are inverted. Targets feel arbitrary rather than
earned.

## 2. Secondary finding: every green shape is wider than it is deep

`_green_radii()` (`:669`) applies these multipliers — `rx` is lateral, `ry` is along the
hole:

| Shape | rx mult | ry mult |
|---|---|---|
| Oval | 1.05–1.25 | 0.85–1.00 |
| Kidney | 1.10–1.35 | 0.75–0.95 |
| Tiered | 0.95–1.15 | 0.70–0.90 |
| L-shaped | 1.15–1.40 | 0.65–0.85 |
| Peninsula | 0.85–1.05 | 0.85–1.05 |
| Complex | 0.90–1.20 | 0.65–0.88 |

Every shape except Peninsula is **wider than deep**. Real playability sizing wants the
opposite: depth ≈ 1.2 × width, because distance dispersion exceeds direction dispersion
for most players. Brauer's worked example — <cite index="19-1">a 160-yard shot sized for
a bogey player gives a main target 26 yards wide by 31 yards deep.</cite>

Deeper-than-wide forgives distance error and punishes aim error; wider-than-deep does
the reverse.

**DECIDED — flip to deeper-than-wide.** Standing principle applies: course design is
grounded in real golf, and USGA averages are the default when a call is ambiguous. The
real-world answer here is unambiguous (depth ≈ 1.2 × width), so we take it rather than
inventing a game-specific aspect.

New multipliers — same silhouette variety, aspect inverted, each shape normalized so
`rx × ry = 1.0` (see §5):

| Shape | rx mult | ry mult |
|---|---|---|
| Oval | 0.85–1.00 | 1.05–1.25 |
| Kidney | 0.75–0.95 | 1.10–1.35 |
| Tiered | 0.70–0.90 | 0.95–1.15 |
| L-shaped | 0.65–0.85 | 1.15–1.40 |
| Peninsula | 0.85–1.05 | 0.85–1.05 |
| Complex | 0.65–0.88 | 0.90–1.20 |

Peninsula stays square-ish — island greens are genuinely round in the real world
(TPC Sawgrass 17 is near-circular), so it needs no flip.

**Watch for on playtest:** this makes greens taller and narrower on a portrait screen.
Approach camera framing was tuned against wide-and-shallow greens. If the green now
overruns the frame on long approaches, that's the pending approach-camera-zoom
correction surfacing, not a bug in this epic — do not fix it here.

## 3. The curve

Anchored on the single hard real-world data point (160 yd → 26 × 31 yd, bogey main
target), with a maintenance floor and a sanity ceiling.

```
width_yd = 0.1625 × approach_yd      # 26/160
depth_yd = 0.1940 × approach_yd      # 31/160
area     = π × (width/2) × (depth/2)
floor    = 4,300 sq ft               # Brauer's cup-rotation minimum
ceiling  = 9,000 sq ft               # Chambers Bay — largest modern U.S. Open venue
```

Scale both axes by `sqrt(target_area / area)` when clamped.

### Resulting table

| Approach | Width yd | Depth yd | Area sq ft | `rx` px | `ry` px | |
|---|---|---|---|---|---|---|
| 80 | 22.6 | 26.9 | 4,300 | 25.4 | 30.3 | floored |
| 100 | 22.6 | 26.9 | 4,300 | 25.4 | 30.3 | floored |
| 120 | 22.6 | 26.9 | 4,300 | 25.4 | 30.3 | floored |
| 140 | 22.8 | 27.1 | 4,362 | 25.6 | 30.5 | crossover |
| 160 | 26.0 | 31.0 | 5,697 | 29.2 | 34.9 | |
| 180 | 29.2 | 34.9 | 7,211 | 32.9 | 39.2 | |
| 200 | 32.5 | 38.8 | 8,902 | 36.6 | 43.6 | |
| 220 | 32.7 | 39.0 | 9,000 | 36.8 | 43.8 | capped |

Two independent validations that the curve is right:

- At 160 yd it lands on **5,697 sq ft**, and the USGA's measured U.S. average green is
  <cite index="13-1">5,600–5,700 sq ft.</cite> We did not tune for that.
- The floor/proportional crossover falls at **140 yd** naturally — below that, real
  courses are governed by cup rotation and ball-mark recovery, not shot dispersion.
  Brauer notes exactly this: <cite index="19-1">proportional sizing makes greens with
  short approach shots too small to recover from numerous ball marks.</cite>

### Versus what we generate today

| `base` px | Current W × D yd | Current sq ft |
|---|---|---|
| 22 (small) | 22.5 × 18.0 | 2,860 |
| 30 | 30.7 × 24.5 | 5,318 |
| 35 | 35.8 × 28.6 | 7,239 |
| 40 | 40.9 × 32.7 | 9,454 |
| 48 (large) | 49.1 × 39.3 | **13,614** |

Current range: **2,860 – 13,614 sq ft.** Proposed: **4,300 – 9,000.**

The top end today is nearly as large as <cite index="10-1">the 18th at the Old Course
(15,570 sq ft)</cite> and well past <cite index="13-1">Chambers Bay's ~9,000, the largest
of any modern U.S. Open venue.</cite> That is the outlier worth killing. The small end
(2,860) is fine on its own — <cite index="17-1">Pebble Beach averages 3,500</cite> — but
it should be *earned by a short approach*, not handed out by difficulty index.

## 4. Defining "approach distance"

Not the same as hole yardage except on par 3s. Using our own bag (`BAG`, Driver 260 max,
Hybrid 210):

```gdscript
## PLAYTEST TARGET — expected shot lengths used to derive the approach a green is sized for.
const EXPECTED_DRIVE_YD := 235.0   ## solid but not maxed Driver
const EXPECTED_LAYUP_YD := 210.0   ## Hybrid second on a par 5

static func _approach_yards(par: int, yardage: float) -> float:
    var appr := yardage
    if par >= 4:
        appr -= EXPECTED_DRIVE_YD
    if par >= 5:
        appr -= EXPECTED_LAYUP_YD
    return clampf(appr, 60.0, 220.0)
```

Sanity check against the table:

| Hole | Approach | Green |
|---|---|---|
| 182-yd par 3 | 182 | ~7,350 sq ft — large, and earned |
| 120-yd par 3 | 120 | 4,300 sq ft — floor, small target |
| 400-yd par 4 | 165 | ~6,050 sq ft |
| 340-yd par 4 | 105 | 4,300 sq ft — floor |
| 520-yd par 5 | 75 | 4,300 sq ft — floor |

Note the emergent behavior: **par 5s and short par 4s almost always get floor-sized
greens**, long par 3s and long par 4s get the big ones. That matches real course
architecture and it gives the round a rhythm it currently lacks.

## 5. Implementation

### Phase 1 — Replace the sizing driver

`hole_generator.gd:332` — `green_size` stops reading `t` and starts reading approach
distance. Keep `size_bias` from `arch` and the small rng jitter so architect archetypes
and variety survive; they now modulate a realistic base instead of defining it.

`_green_radii()` (`:669`) takes target width/depth in px rather than a single `base`,
and the shape multipliers become **area-preserving aspect variations** rather than
absolute sizes — i.e. normalize each shape's `rx × ry` product to 1.0 so a Kidney and an
Oval sized for the same approach cover the same area with different silhouettes.

That normalization is the important part. Today an L-shaped green at a given `base` has
a different area than an Oval at the same `base`, so shape secretly changes difficulty.

### Phase 2 — Aspect flip

Apply the inverted multiplier table from §2.

Ship this as a **separate PR from Phase 1**, even though both are decided. Phase 1
changes how big greens are; Phase 2 changes what shape they are. Bundling them means a
playtest that feels off can't be traced to either one. One phase, one PR, one playtest
pass.

Do not ship Phase 1 with the old aspect silently attached to the new areas as a
permanent state — greens that are the right size and the wrong shape are harder to
diagnose later. Phase 1 is a waypoint, not a resting place.

---

## 6. Out of scope — do not touch

- `fairway_width` generation (`:337`). Our 30–73 yd range is defensible; real fairways
  run <cite index="9-1">25 to 65 yards, medium 35 to 45,</cite> and the wide end exists
  in the real world. Separate decision, separate epic.
- `_classify_lie()`, ball physics, putting, green book contour generation.
- The rough/first-cut terrain work in `correction-rough-base-layer.md`. Different PR.
- Camera framing constants.
- `pin_offset` generation — but see risk below.

## 7. Predicted outcome — check these on device

Modeled over a representative 18 (four par 3s at 130/155/175/195, ten par 4s at
340–485, four par 5s at 505–565):

| | Current | New |
|---|---|---|
| Average green | 8,425 sq ft | **6,219 sq ft** (-26%) |
| Average putt length | — | **≈ -14%** (scales as √area) |

If the device playtest doesn't feel roughly 15% tighter on the greens, the
implementation is wrong — not the curve.

### ⚠ New risk found while modeling: size compression at the rails

On that same 18, **7 holes land exactly on the floor and 4 exactly on the ceiling**.
That's 11 of 18 greens at one of two identical sizes. The curve buys realism and
accidentally spends variety.

Two mitigations, both required:

1. **Apply `size_bias` and rng jitter AFTER the clamp, not before.** Jitter-then-clamp
   collapses everything back onto the rails; clamp-then-jitter preserves spread. This is
   an ordering detail and it is easy to get backwards. Get it right.
2. **Consider a soft ceiling** — compress asymptotically toward 9,000 rather than hard
   clamping, so 440-yd and 485-yd par 4s still differ. Long par 4s are the worst
   offenders because `_approach_yards()` already clamps at 220, so the cap is
   double-compressing. Flag for Matt if the hard clamp reads flat on playtest.

Note the par 5s all sitting at floor is *correct* and should not be mitigated — you're
hitting a wedge in, the target should be small. That's the rhythm this epic is buying.

## 7b. Other risks to check before merge

- **Pin placement.** `pin_offset` is generated against green radii. Smaller max greens
  mean pins sit closer to edges. Verify no pin lands in the fringe or off-surface.
- **Green book.** `_build_green_book()` samples the surface; confirm it still resolves at
  the new floor size.
- **Island greens.** Peninsula shape is the only currently square-ish aspect; check the
  water ring geometry still clears the new radii.

## 8. Acceptance criteria

- Generate 100 holes. No green below 4,300 or above 9,000 sq ft.
- **Variety check:** across one generated 18, no more than 3 greens share the same area
  within 2%. If the floor or ceiling is stacking holes, the jitter ordering is wrong
  (§7).
- Average green area across a generated 18 lands near 6,200 sq ft.
- Green area correlates with computed approach distance, not with `t`. Plot it; the
  scatter should be a curve with a flat floor, not noise.
- A 180-yd par 3 and a 400-yd par 4 produce greens within ~15% of each other in area.
- A 520-yd par 5 produces a floor-sized green.
- Two greens of different shapes sized for the same approach have areas within 5% of
  each other.
- Regression: play 18 holes. Pins never sit off the putting surface. Green book
  resolves on every hole including the smallest.

## 9. Handoff notes

- Aspect ratio (§2) is **decided**: deeper than wide, per USGA bogey-player data.
- Floor (4,300) and ceiling (9,000) are **decided**: both are real-world figures, not
  invented. Flagged `## PLAYTEST TARGET` anyway — real numbers can still feel wrong on a
  phone.
- Shorter putts are **decided and desired**. Greens have felt too big and average putts
  too long throughout playtesting. The -14% average putt length is the intended outcome,
  not a side effect to be compensated for. Do not add anything to claw it back.
- Agent reads this doc and confirms understanding before writing code.
- Phase 1 and Phase 2 are separate PRs with a device playtest between them.
- Only `scripts/course/hole_generator.gd` is in scope.
- Every new constant gets a `## PLAYTEST TARGET` comment.
