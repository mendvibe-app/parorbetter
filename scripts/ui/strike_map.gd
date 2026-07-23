class_name StrikeMap
extends Control

## Post-shot strike map — one dot on a generic clubface.
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

var _has_shot := false
var _dot := Vector2.ZERO  ## normalized: x −1..1 left→right, y −1..1 bottom→top
var _ghosts: PackedVector2Array = PackedVector2Array()  ## unit-disc offsets
var _scatter := 0.0  ## (1 − stance)
var _pure := false
var _face := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ponytail: generic face placeholder — swap for 3 club-family art once validated
	_face.bg_color = Color(0.32, 0.36, 0.38, 0.9)
	_face.set_corner_radius_all(48)
	_face.border_color = Color(0.75, 0.8, 0.8, 0.7)
	_face.set_border_width_all(3)


func show_strike(report: ShotReport) -> void:
	_has_shot = true
	_pure = report.contact == "perfect" and report.stance >= TempoGrade.PURE_BALANCE
	_dot = Vector2(clampf(report.path_error, -1.0, 1.0), _vertical_frac(report.contact))
	_scatter = 1.0 - clampf(report.stance, 0.0, 1.0)
	# Repeatability cloud — fresh random spread from stance alone, never stored.
	_ghosts.clear()
	for i in GHOST_COUNT:
		_ghosts.append(Vector2.from_angle(randf() * TAU) * sqrt(randf()))
	queue_redraw()


func _vertical_frac(contact: String) -> float:
	## Signed error from the measurement contact quality derives from:
	## full/chip (ratio − target)/tol, putt (actual − target frac)/tol.
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
	draw_style_box(_face, Rect2(Vector2.ZERO, size))
	var c := size * 0.5
	var half := c * FACE_USE
	# Sweet-spot anchor: center = pure. Cross only, no axis labels.
	var cross := Color(0.9, 0.95, 0.9, 0.28)
	draw_line(c - Vector2(14.0, 0.0), c + Vector2(14.0, 0.0), cross, 2.0)
	draw_line(c - Vector2(0.0, 14.0), c + Vector2(0.0, 14.0), cross, 2.0)
	var dot_px := c + Vector2(_dot.x * half.x, -_dot.y * half.y)
	var scatter_px := _scatter * MAX_SCATTER_FRAC * half.y
	if scatter_px > DOT_R * 0.6:  # good balance collapses the cloud to nothing
		var ghost_col := Color(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, 0.18)
		var inset := Vector2(GHOST_R, GHOST_R)
		for g in _ghosts:
			var p := (dot_px + g * scatter_px).clamp(inset, size - inset)
			draw_circle(p, GHOST_R, ghost_col)
	if _pure:
		draw_circle(dot_px, DOT_R * 1.9, Color(PURE_COLOR.r, PURE_COLOR.g, PURE_COLOR.b, 0.25))
	draw_circle(dot_px, DOT_R, PURE_COLOR if _pure else DOT_COLOR)
