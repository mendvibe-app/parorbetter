class_name TempoGrade
extends RefCounted

## Pure tempo math — backswing:downswing ratio vs target, balance as window modifier.
## Speed-invariant: only the ratio of the two intervals is graded.

const TARGET_FULL := 3.0
const TARGET_SHORT := 2.0
## Half-width of accept window at full balance (full: 2.5–3.5, short: 1.6–2.4).
const TOL_FULL := 0.5
const TOL_SHORT := 0.4
const PURE_BALANCE := 0.72

## Contact tiers by |ratio − target| / tolerance (after balance × timing scale).
const BAND_PERFECT := 0.35
const BAND_GOOD := 0.75
const BAND_THIN_FAT := 1.25


static func shot_type_for(lie: String, club_name: String, remaining_yd: float) -> String:
	if lie == "Green":
		return "putt"
	if club_name.contains("Wedge") or remaining_yd < 60.0:
		return "chip"
	return "full"


static func target_ratio(shot_type: String) -> float:
	return TARGET_SHORT if shot_type == "putt" or shot_type == "chip" else TARGET_FULL


static func base_tolerance(shot_type: String) -> float:
	return TOL_SHORT if shot_type == "putt" or shot_type == "chip" else TOL_FULL


static func ratio(sample: Dictionary) -> float:
	var bs: float = float(sample.get("t_top", 0.0)) - float(sample.get("t_takeaway", 0.0))
	var ds: float = float(sample.get("t_impact", 0.0)) - float(sample.get("t_top", 0.0))
	if ds <= 0.001:
		return 99.0
	if bs <= 0.0:
		return 0.0
	return bs / ds


static func balance(sample: Dictionary, tighten: float = 1.0) -> float:
	## Gesture qualities → 0..1. tighten scales how harshly spikes hurt (debug knob).
	var t := maxf(tighten, 0.0)
	var accel := float(sample.get("max_accel", 0.0))
	var jerk := float(sample.get("max_jerk", 0.0))
	var bs_len := float(sample.get("backswing_len", 0.0))
	var ft_len := float(sample.get("follow_through_len", 0.0))
	var incomplete: bool = bool(sample.get("incomplete", false))

	# ponytail: accel/jerk thresholds are playtest knobs — calibrate on-device
	var accel_pen := clampf((accel - 8.0) / 24.0, 0.0, 1.0) * t
	var jerk_pen := clampf((jerk - 0.6) / 1.4, 0.0, 1.0) * t
	var short_bs := clampf((0.18 - bs_len) / 0.18, 0.0, 1.0)
	var short_ft := 0.0 if incomplete else clampf((0.08 - ft_len) / 0.08, 0.0, 1.0)
	var incomplete_pen := 0.55 if incomplete else 0.0

	var pen := accel_pen * 0.35 + jerk_pen * 0.30 + short_bs * 0.20 + short_ft * 0.15 + incomplete_pen
	return clampf(1.0 - pen, 0.0, 1.0)


static func tolerance_width(
	shot_type: String,
	bal: float,
	timing_scale: float = 1.0,
	tol_scale: float = 1.0
) -> float:
	## Held base (bal→1) = full window; lurch (bal→0) shrinks toward ~35% width. Never widens past base.
	var base := base_tolerance(shot_type) * maxf(tol_scale, 0.15) * maxf(timing_scale, 0.35)
	var shrink := lerpf(0.35, 1.0, clampf(bal, 0.0, 1.0))
	return base * shrink


static func grade(
	sample: Dictionary,
	shot_type: String,
	timing_scale: float = 1.0,
	tol_scale: float = 1.0,
	balance_tighten: float = 1.0
) -> Dictionary:
	var target := target_ratio(shot_type)
	var bal := balance(sample, balance_tighten)
	var tol := tolerance_width(shot_type, bal, timing_scale, tol_scale)
	var r := ratio(sample)
	var err := r - target
	var abs_n := absf(err) / maxf(tol, 0.01)

	var contact: ShotResult.ContactQuality
	if bool(sample.get("incomplete", false)) and abs_n > BAND_GOOD:
		contact = ShotResult.ContactQuality.MISS
	elif abs_n <= BAND_PERFECT:
		contact = ShotResult.ContactQuality.PERFECT
	elif abs_n <= BAND_GOOD:
		contact = ShotResult.ContactQuality.GOOD
	elif abs_n <= BAND_THIN_FAT:
		# Rushed (ratio low) → fat/early; dragged (ratio high) → thin/late
		contact = ShotResult.ContactQuality.FAT if err < 0.0 else ShotResult.ContactQuality.THIN
	else:
		contact = ShotResult.ContactQuality.MISS

	# Extreme balance loss caps contact — modifier, not a second meter.
	if bal < 0.35 and contact == ShotResult.ContactQuality.PERFECT:
		contact = ShotResult.ContactQuality.GOOD
	if bal < 0.2 and contact == ShotResult.ContactQuality.GOOD:
		contact = ShotResult.ContactQuality.FAT if err < 0.0 else ShotResult.ContactQuality.THIN

	# Power multiplier ≤ 1 — gesture can only subtract from committed carry.
	var power_mul := clampf(1.0 - abs_n * 0.55, 0.35, 1.0)
	if contact == ShotResult.ContactQuality.MISS:
		power_mul = minf(power_mul, 0.45)

	# Path: rushed (err < 0) = pull/left (−); dragged (err > 0) = push/right (+)
	var path := clampf(signf(err if absf(err) > 0.01 else 0.0) * abs_n * 0.55, -1.0, 1.0)
	if bal < 0.4:
		path = clampf(path * (1.0 + (0.4 - bal)), -1.0, 1.0)

	return {
		"ratio": r,
		"target": target,
		"balance": bal,
		"tolerance": tol,
		"contact": contact,
		"power_mul": power_mul,
		"path_error": path,
		"note": tempo_note(r, target, bal),
		"backswing_ms": int((float(sample.get("t_top", 0.0)) - float(sample.get("t_takeaway", 0.0))) * 1000.0),
		"downswing_ms": int((float(sample.get("t_impact", 0.0)) - float(sample.get("t_top", 0.0))) * 1000.0),
	}


static func tempo_note(r: float, target: float, bal: float) -> String:
	var err := r - target
	var bal_word := "steady base" if bal >= PURE_BALANCE else ("shaky base" if bal >= 0.4 else "lurch")
	var tempo_word: String
	if absf(err) <= target * 0.08:
		tempo_word = "on tempo"
	elif err < 0.0:
		tempo_word = "transition rushed"
	else:
		tempo_word = "dragged the downswing"
	return "Tempo %.1f:1 — %s · %s" % [r, tempo_word, bal_word]
