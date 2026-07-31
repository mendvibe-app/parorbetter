class_name HandicapMath
extends RefCounted

## Simplified course rating + stroke index + rolling handicap (not USGA-certified).
## Slope-style number ~55–155 (avg ~113) from mean hole complexity 0–1.

const SLOPE_MIN := 55.0
const SLOPE_MAX := 155.0
const SLOPE_REF := 113.0
## Mean complexity that maps to SLOPE_REF (slightly above 0.5 — generators ramp).
const COMPLEXITY_AT_REF := 0.58


static func course_slope(complexities: Array) -> float:
	if complexities.is_empty():
		return SLOPE_REF
	var sum := 0.0
	for c in complexities:
		sum += clampf(float(c), 0.0, 1.0)
	var mean := sum / float(complexities.size())
	# Linear map: 0 → 55, COMPLEXITY_AT_REF → 113, 1 → 155.
	var slope: float
	if mean <= COMPLEXITY_AT_REF:
		slope = lerpf(SLOPE_MIN, SLOPE_REF, clampf(mean / COMPLEXITY_AT_REF, 0.0, 1.0))
	else:
		var u := (mean - COMPLEXITY_AT_REF) / maxf(1.0 - COMPLEXITY_AT_REF, 0.01)
		slope = lerpf(SLOPE_REF, SLOPE_MAX, clampf(u, 0.0, 1.0))
	return clampf(slope, SLOPE_MIN, SLOPE_MAX)


## stroke_index[h] = rank 1..n (1 = hardest). Ties: lower hole number wins hardness.
static func stroke_index_ranks(complexities: Array) -> PackedInt32Array:
	var n := complexities.size()
	var out := PackedInt32Array()
	out.resize(n)
	if n <= 0:
		return out
	var order: Array[int] = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ca := float(complexities[a])
		var cb := float(complexities[b])
		if absf(ca - cb) > 1e-9:
			return ca > cb  # harder first
		return a < b  # lower hole number harder on tie
	)
	for rank in n:
		out[order[rank]] = rank + 1
	return out


static func score_differential(score_to_par: int, course_slope: float) -> float:
	var slope := clampf(course_slope, SLOPE_MIN, SLOPE_MAX)
	return float(score_to_par) * (SLOPE_REF / slope)


## Best-k average of last differentials; null if fewer than min_rounds.
static func handicap_index(differentials: Array, min_rounds: int = 3) -> Variant:
	var n := differentials.size()
	if n < min_rounds:
		return null
	var vals: Array[float] = []
	for d in differentials:
		vals.append(float(d))
	vals.sort()  # best (lowest) first
	var k := mini(8, n)
	var sum := 0.0
	for i in k:
		sum += vals[i]
	return sum / float(k)


static func course_handicap(handicap_index: float, course_slope: float) -> int:
	var slope := clampf(course_slope, SLOPE_MIN, SLOPE_MAX)
	var ch := int(round(handicap_index * slope / SLOPE_REF))
	return clampi(ch, 0, 18)
