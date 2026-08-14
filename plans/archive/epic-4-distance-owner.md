# Epic 4 — One Owner for Distance

**Phase:** 4 of 8 (see `flight-model-rebuild-roadmap.md`)
**Branch:** `feature/distance-owner`, from main after the bag-calibration corrections
**Gameplay change:** the aim preview becomes truthful at high power. Ball flight is unchanged.

---

## The roadmap undersold this phase

The plan described Phase 4 as an invisible refactor — collapse scattered multipliers, no
behaviour change, enable Phase 5. Reading the code, it is more than that: **there are two
different distance formulas in the game, and the one driving the aim preview is missing
terms.**

```gdscript
// launch_velocity() — what the ball actually does
power_mul = power * lie_multiplier * contact_multiplier * lerp(1.0, 0.94, force)
total_yards = club_max * power_mul
total_yards *= lerp(1.0, 0.88, force) * (1.0 + path_error * force * 0.04)

// estimate_carry_yards() — what the player is shown
y = club_max * power * lie_multiplier          // no force taxes at all
```

The preview omits both force penalties. Below 0.92 power `force` is zero and the two agree.
Above it they diverge:

| Power | Preview says | Ball actually goes | Gap |
|---|---|---|---|
| 0.92 | 216 | 216 | 0 |
| 0.94 | 221 | 211 | 4.5% |
| 0.96 | 226 | 206 | 8.8% |
| **1.00** | **235** | **194** | **17.3%** |

**At full power the plan overstates by 17%.** That is the "Plan X → Actual Y" gap seen on
full-power shots during playtest, and it is not a physics problem — it is two copies of a
formula that drifted apart.

### The second finding: distance is not monotonic in power

Driver total, by power:

| Power | 0.86 | 0.88 | 0.90 | **0.92** | 0.94 | 0.96 | 1.00 |
|---|---|---|---|---|---|---|---|
| Yards | 224 | 229 | 234 | **239** | 234 | 228 | 215 |

**Maximum distance is at 0.92. Swinging 100% goes 23 yards shorter than swinging 92%.**

Two consequences:

1. **`club_max_yards` is unreachable.** The driver is defined as 260 but can never exceed 239.
   Every "max" in the bag is ~8% above what the club can actually do.
2. **`recommended_power()` inverts a non-monotonic function.** Asking "what power reaches X
   yards?" has two answers above 0.92, and the current implementation
   (`remaining / (club_max * lie_mul)`) is the inverse of the *preview* formula, not the real
   one — so it inherits the same error.

The overswing penalty itself is good design and grounded: overswinging costs distance in real
golf. This epic does not remove it. It makes the game tell the truth about it.

---

## The change

One function owns total distance. Everything else calls it.

```gdscript
## THE single owner of total shot distance. No other code may compute or scale total_yards.
## Inputs are everything that legitimately affects distance; the caller supplies what it
## knows. Pre-swing callers (aim preview, power solver) pass contact = GOOD, since contact
## quality is not knowable until the swing is graded — that is the one honest unknown.
static func resolve_distance(
	club_max_yards: float,
	power: float,
	lie: String,
	severity: String = "",
	contact: int = ShotResult.ContactQuality.GOOD,
	shot_type: String = "full",
	path_error: float = 0.0
) -> float:
```

It must reproduce `launch_velocity()`'s current arithmetic exactly: lie multiplier, contact
multiplier, the `0.94` mash tax, the `0.88` distance tax, the `path_error` term, and the flop
cap. Nothing new, nothing dropped, same order of operations.

### Call sites

| Caller | Today | After |
|---|---|---|
| `launch_velocity()` | inline formula | `resolve_distance(...)` with real contact and path_error |
| `estimate_carry_yards()` | short incomplete formula | `resolve_distance(...)` with GOOD contact, zero path_error |
| `recommended_power()` | inverts the incomplete formula | inverts `resolve_distance` (see below) |
| `shot_report.gd` | recomputes `force_factor` for display | leave — it reports components, doesn't decide distance |
| `putt_stroke.gd` | own path | leave — putts return early and are out of scope |

### Inverting a non-monotonic function

`recommended_power()` must not return a power above the distance-maximising point. If a target
is beyond what the club can reach, the honest answer is **the power that maximises distance**,
not 1.0 — recommending a full swing that travels 23 yards shorter is actively bad advice.

Two acceptable approaches; **report which you pick and why**:

- Solve numerically against `resolve_distance()` and clamp to the maximising power.
- Derive the maximising power from `POWER_POCKET_HI` and clamp analytically.

Either way, the contract is: `recommended_power()` never returns a power whose resolved
distance is less than a lower power's.

---

## Out of scope

- **Removing or retuning the overswing penalty.** The `0.94` and `0.88` constants stay exactly
  as they are. This epic makes them honest, not smaller.
- **`club_max_yards` being unreachable.** Real finding, logged, but changing the bag is the
  deferred Part B. Note it in the PR.
- Putting, apex, hang time, carry fraction, canopies.
- The `path_error` term's magnitude. Preserved as-is.
- Flight, roll, spin, and the plan/simulation termination logic. Phase 5.

---

## Acceptance criteria

1. **Flight behaviour is byte-identical.** `launch_velocity()` returns exactly what it does
   today for every input. This is a pure consolidation on the launch side.
2. **All flight goldens unchanged at 15/15**, same values, not merely passing.
3. `estimate_carry_yards()` and `launch_velocity()` return the same total for the same inputs
   when contact is GOOD and path_error is zero. **Assert this across the full bag at powers
   0.5, 0.8, 0.92, 0.96, and 1.0** — it is the contract this epic establishes.
4. `recommended_power()` never returns a power whose resolved distance is below that of a
   lower power.
5. No code outside `resolve_distance()` multiplies or scales `total_yards`. Grep and confirm.
6. All `*_check.py` pass.

---

## Playtest verification

1. **Aim at a target and swing at 100%.** The plan and the actual should now agree — this is
   the visible fix. Previously the plan overstated by up to 17%.
2. Swing at ~85%. Nothing should change; the two formulas already agreed below 0.92.
3. Confirm the game never recommends a power above ~0.92 for a long shot.
4. Play three holes. Ball flight must feel identical — only the numbers on screen change.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch only `scripts/ball/ball_physics.gd` and `scripts/ball/flight_model_check.py`, plus any
  check file that breaks (report first).
- **Criterion 1 is the hard one.** If `launch_velocity()` output moves by even a rounding
  step, the consolidation is wrong. Compare before and after across the bag before claiming
  success.
- Report the `recommended_power()` inversion approach and your reasoning.
- Report anything else that touches `total_yards` that this epic missed.
