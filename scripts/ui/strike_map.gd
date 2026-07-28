class_name StrikeMap
extends Control

## Post-shot strike map — one dot on a clubface (wood / iron / putter family art).
## Vertical = signed contact error (thin/long = top, pure = center, fat/short = bottom),
## horizontal = path_error (hook/left … slice/right). Balance is not a third axis:
## it sets the dot's precision — ghost-dot cloud radius scales with (1 − stance),
## the spread you'd expect repeating this balance, not alternate outcomes.
## Inspired by launch-monitor strike maps, not a literal one — the game tracks
## tempo + path, not true toe/heel impact, so no axis labels claim otherwise.

const GHOST_COUNT := 6
const DOT_R := 12.0
const GHOST_R := 8.0
## Ghost scatter radius at stance 0, as a fraction of the face half-height.
const MAX_SCATTER_FRAC := 0.55
## Dot range as a fraction of face half-size, so extremes stay on the face.
const FACE_USE := 0.78

const PURE_COLOR := Color(1.0, 0.92, 0.35)
const DOT_COLOR := Color(0.95, 0.97, 0.95)

## Three face families — real face-shape difference collapses to these buckets.
const FACE_WOOD := preload("res://assets/ui/strike_face_wood.png")
const FACE_IRON := preload("res://assets/ui/strike_face_iron.png")
const FACE_PUTTER := preload("res://assets/ui/strike_face_putter.png")

var _has_shot := false
var _dot := Vector2.ZERO  ## normalized: x −1..1 left→right, y −1..1 bottom→top
var _ghosts: PackedVector2Array = PackedVector2Array()  ## unit-disc offsets
var _scatter := 0.0  ## (1 − stance)
var _pure := false
var _tex: Texture2D = FACE_IRON
var _last_report: ShotReport = null
var _t := 1.0  ## animate-in progress: dot travels center → result
var _pulse := 0.0  ## pure-halo pulse, decays after the dot lands
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func face_for(club_name: String, lie: String) -> Texture2D:
	if lie == "Green" or club_name == "Putter":
		return FACE_PUTTER
	if club_name.contains("Iron") or club_name.contains("Wedge"):
		return FACE_IRON
	return FACE_WOOD  # Driver / 3-Wood / Hybrid


func show_strike(report: ShotReport) -> void:
	if _has_shot and report == _last_report:
		return  # panel re-shows the same report on final — don't replay
	_last_report = report
	_has_shot = true
	_tex = face_for(report.club_name, report.lie)
	_pure = report.contact == "perfect" and report.stance >= TempoGrade.PURE_BALANCE
	_dot = Vector2(clampf(report.path_error, -1.0, 1.0), _vertical_frac(report.contact))
	_scatter = 1.0 - clampf(report.stance, 0.0, 1.0)
	# Repeatability cloud — fresh random spread from stance alone, never stored.
	_ghosts.clear()
	for i in GHOST_COUNT:
		_ghosts.append(Vector2.from_angle(randf() * TAU) * sqrt(randf()))
	# Thwack-in: dot flies center → result; pure adds a halo pulse on landing.
	if _tween:
		_tween.kill()
	_t = 0.0
	_pulse = 0.0
	_tween = create_tween()
	_tween.tween_method(_set_t, 0.0, 1.0, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _pure:
		_tween.tween_method(_set_pulse, 1.0, 0.0, 0.3)
	queue_redraw()


func _set_t(v: float) -> void:
	_t = v
	queue_redraw()


func _set_pulse(v: float) -> void:
	_pulse = v
	queue_redraw()


func _vertical_frac(contact: String) -> float:
	## Signed error from the measurement contact quality derives from:
	## full/pitch (ratio − target)/tol, putt (actual − target frac)/tol.
	## Both models grade |err|/tol against the same bands, so /BAND_THIN_FAT
	## puts THIN at the top edge, FAT at the bottom, PERFECT at center.
	var m: Dictionary = GameState.last_tempo_metrics
	if not m.is_empty() and m.has("tolerance"):
		var tol := maxf(float(m.get("tolerance", 0.0)), 0.001)
		var err: float
		if m.has("actual_frac"):
			err = float(m["actual_frac"]) - float(m["target_frac"])
		else:
			err = float(m.get("ratio", 0.0)) - float(m.get("target", 0.0))
		return clampf(err / tol / TempoGrade.BAND_THIN_FAT, -1.0, 1.0)
	# No metrics (shouldn't happen mid-run) — categorical fallback.
	if contact == "thin":
		return 0.6
	if contact == "fat":
		return -0.6
	if contact == "miss":
		return 1.0
	return 0.0


func _draw() -> void:
	if not _has_shot:
		return
	# Fit the face texture to the control, preserving aspect; all geometry
	# hangs off the face rect so the dot stays on the blade (putter is wide+short).
	var ts := _tex.get_size()
	var s := minf(size.x / ts.x, size.y / ts.y)
	var face := Rect2((size - ts * s) * 0.5, ts * s)
	draw_texture_rect(_tex, face, false)
	var c := face.get_center()
	var half := face.size * 0.5 * FACE_USE
	# Sweet-spot anchor: center = pure. Cross only, no axis labels.
	var cross := Color(0.9, 0.95, 0.9, 0.28)
	var arm := minf(14.0, half.y * 0.5)
	draw_line(c - Vector2(arm, 0.0), c + Vector2(arm, 0.0), cross, 2.0)
	draw_line(c - Vector2(0.0, arm), c + Vector2(0.0, arm), cross, 2.0)
	var dot_px := c.lerp(c + Vector2(_dot.x * half.x, -_dot.y * half.y), _t)
	var scatter_px := _scatter * MAX_SCATTER_FRAC * half.y
	var ghost_a := 0.18 * clampf((_t - 0.75) / 0.25, 0.0, 1.0)  # cloud only once landed
	if scatter_px > DOT_R * 0.6 and ghost_a > 0.0:  # good balance collapses the cloud
		var ghost_col := Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, ghost_a)
		var inset := Vector2(GHOST_R, GHOST_R)
		for g in _ghosts:
			var p := (dot_px + g * scatter_px).clamp(face.position + inset, face.end - inset)
			draw_circle(p, GHOST_R, ghost_col)
	if _pure:
		var halo_r := DOT_R * 1.9 * (1.0 + 0.8 * _pulse)
		draw_circle(dot_px, halo_r, Color(PURE_COLOR.r, PURE_COLOR.g, PURE_COLOR.b, 0.25 + 0.3 * _pulse))
	draw_circle(dot_px, DOT_R, PURE_COLOR if _pure else DOT_COLOR)
