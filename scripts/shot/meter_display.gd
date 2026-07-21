class_name MeterDisplay
extends Control

## Display-only strip: power/lean + swing arcs above the thumb touch pads.
## Reads live state from PowerStance / SwingContact; no input handling.

const MARKER_TEX := preload("res://assets/ui/swing_marker.png")

var power_stance: PowerStance
var swing_contact: SwingContact


func bind(ps: PowerStance, sc: SwingContact) -> void:
	if power_stance and power_stance.updated.is_connected(_on_updated):
		power_stance.updated.disconnect(_on_updated)
	if swing_contact and swing_contact.updated.is_connected(_on_updated):
		swing_contact.updated.disconnect(_on_updated)
	power_stance = ps
	swing_contact = sc
	if power_stance:
		power_stance.updated.connect(_on_updated)
	if swing_contact:
		swing_contact.updated.connect(_on_updated)
	queue_redraw()


func _on_updated(_a = null, _b = null) -> void:
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	# Keep sweet-spot pulse alive while swinging even if no new signal this frame.
	if swing_contact and swing_contact.swinging:
		queue_redraw()


func _draw() -> void:
	if power_stance == null or swing_contact == null:
		return
	var half_w := size.x * 0.5
	_draw_power(Rect2(0.0, 0.0, half_w - 8.0, size.y))
	_draw_swing(Rect2(half_w + 8.0, 0.0, half_w - 8.0, size.y))


func _draw_power(area: Rect2) -> void:
	var local_size := area.size
	var t_rect: Rect2 = ArcMeters.tempo_rect(local_size, 28.0, 52.0)
	t_rect.position += area.position
	var l_rect: Rect2 = ArcMeters.lean_rect(local_size)
	l_rect.position += area.position

	var track: PackedVector2Array = ArcMeters.tempo_polyline(t_rect, 0.0, 1.0, 36)
	ArcMeters.draw_thick_polyline(self, track, Color(0.12, 0.18, 0.14, 0.95), 16.0)
	ArcMeters.draw_thick_polyline(self, track, Color(0.22, 0.32, 0.24, 0.9), 10.0)

	var power := power_stance.power
	var fill_c: Color = Color(0.35, 0.85, 0.45).lerp(Color(0.95, 0.85, 0.2), power)
	if power > 0.92:
		fill_c = Color(0.95, 0.4, 0.25)
	var fill: PackedVector2Array = ArcMeters.tempo_polyline(t_rect, 0.0, power, 28)
	ArcMeters.draw_thick_polyline(self, fill, fill_c, 12.0)

	var rec := power_stance.recommend_power
	var rec_p: Vector2 = ArcMeters.tempo_point(t_rect, rec)
	var rec_a: float = ArcMeters.tempo_angle(rec)
	var radial: Vector2 = Vector2(cos(rec_a), -sin(rec_a))
	draw_line(rec_p - radial * 10.0, rec_p + radial * 14.0, Color(1, 1, 1, 0.95), 3.0, true)

	var dwell: float = power_stance._dwell
	var lock_t: float = clampf(dwell / PowerStance.DWELL_REQUIRED, 0.0, 1.0)
	if lock_t > 0.02:
		var lock_pts: PackedVector2Array = ArcMeters.tempo_polyline(t_rect, maxf(power - 0.08, 0.0), power, 10)
		ArcMeters.draw_thick_polyline(self, lock_pts, Color(0.95, 0.9, 0.4, 0.35 + 0.55 * lock_t), 6.0)

	var tip: Vector2 = ArcMeters.tempo_point(t_rect, power)
	draw_circle(tip, 8.0, fill_c)
	draw_arc(tip, 8.0, 0.0, TAU, 20, Color(0.05, 0.08, 0.05, 0.8), 2.0, true)

	var lean: PackedVector2Array = ArcMeters.lean_polyline(l_rect, 24)
	ArcMeters.draw_thick_polyline(self, lean, Color(0.14, 0.2, 0.16, 0.95), 14.0)
	ArcMeters.draw_thick_polyline(self, lean, Color(0.25, 0.35, 0.28, 0.85), 8.0)

	var tgt: Vector2 = ArcMeters.lean_point(l_rect, power_stance._target_x)
	var gold_a: float = 0.45 + 0.45 * lock_t
	draw_circle(tgt, 11.0, Color(1.0, 0.85, 0.2, gold_a))
	draw_arc(tgt, 14.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.35, gold_a), 2.5, true)

	var ply: Vector2 = ArcMeters.lean_point(l_rect, power_stance._player_x)
	var needle_c: Color = Color(0.3, 0.9, 0.5).lerp(Color(0.95, 0.3, 0.25), 1.0 - power_stance.stability)
	draw_circle(ply, 7.0, needle_c)
	draw_line(ply + Vector2(0, -16), ply + Vector2(0, 16), needle_c, 3.0, true)

	# Yardage bit above the pad labels
	var est := BallPhysics.estimate_carry_yards(power, power_stance.club_max_yards, power_stance.lie)
	draw_string(
		ThemeDB.fallback_font,
		area.position + Vector2(12.0, 28.0),
		"%s  %d%% → %d yd" % [power_stance.club_name, int(power * 100.0), int(est)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiScale.BODY,
		Color(0.85, 0.92, 0.8, 0.95),
	)


func _draw_swing(area: Rect2) -> void:
	var local_size := area.size
	var rect: Rect2 = ArcMeters.swing_rect(local_size, 28.0, 20.0)
	rect.position += area.position
	var sweet_h: float = swing_contact.sweet_half()
	var good_h: float = swing_contact.good_half()

	var track: PackedVector2Array = ArcMeters.swing_polyline(rect, 0.0, 1.0, 40)
	ArcMeters.draw_thick_polyline(self, track, Color(0.12, 0.18, 0.16, 0.95), 18.0)
	ArcMeters.draw_thick_polyline(self, track, Color(0.2, 0.28, 0.24, 0.9), 12.0)

	var good: PackedVector2Array = ArcMeters.swing_polyline(rect, 0.5 - good_h, 0.5 + good_h, 18)
	ArcMeters.draw_thick_polyline(self, good, Color(0.35, 0.55, 0.3, 0.85), 14.0)

	var sweet: PackedVector2Array = ArcMeters.swing_polyline(rect, 0.5 - sweet_h, 0.5 + sweet_h, 12)
	ArcMeters.draw_thick_polyline(self, sweet, Color(0.95, 0.85, 0.25, 0.95), 16.0)

	var impact: Vector2 = ArcMeters.swing_point(rect, 0.5)
	draw_line(impact + Vector2(0, -10), impact + Vector2(0, 14), Color(1.0, 0.95, 0.4, 0.9), 3.0, true)

	draw_circle(ArcMeters.swing_point(rect, 0.02), 4.0, Color(0.7, 0.75, 0.7, 0.7))
	draw_circle(ArcMeters.swing_point(rect, 0.98), 4.0, Color(0.7, 0.75, 0.7, 0.7))

	var m: Vector2 = ArcMeters.swing_point(rect, swing_contact.marker_pos)
	var a: float = ArcMeters.swing_angle(swing_contact.marker_pos)
	var mh := 56.0
	var mw := mh * float(MARKER_TEX.get_width()) / float(MARKER_TEX.get_height())
	draw_set_transform(m, a + PI / 2.0, Vector2.ONE)
	draw_texture_rect(MARKER_TEX, Rect2(Vector2(-mw / 2.0, -mh / 2.0), Vector2(mw, mh)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if swing_contact.swinging:
		draw_circle(impact, 5.0 + sin(Time.get_ticks_msec() * 0.02) * 2.0, Color(1.0, 0.9, 0.3, 0.35))
