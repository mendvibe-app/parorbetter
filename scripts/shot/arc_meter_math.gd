extends Node

## Autoload: ArcMeters — geometry for golf-arc shot meters.
## Swing: t 0..1 = backswing (left) -> impact (bottom) -> follow-through (right).
## Tempo: t 0..1 = low power -> high power along a rising club-path arc.


func swing_angle(t: float) -> float:
	return PI - clampf(t, 0.0, 1.0) * PI


func swing_rect(control_size: Vector2, top_pad: float = 72.0, bottom_pad: float = 28.0) -> Rect2:
	var h: float = maxf(control_size.y - top_pad - bottom_pad, 80.0)
	var w: float = maxf(control_size.x - 24.0, 80.0)
	return Rect2(12.0, top_pad, w, h)


func swing_radius(rect: Rect2) -> float:
	return minf(rect.size.x * 0.46, rect.size.y * 0.78)


func swing_center(rect: Rect2) -> Vector2:
	var r: float = swing_radius(rect)
	return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y - r - 8.0)


func swing_point(rect: Rect2, t: float) -> Vector2:
	var c: Vector2 = swing_center(rect)
	var r: float = swing_radius(rect)
	var a: float = swing_angle(t)
	return c + Vector2(cos(a), sin(a)) * r


func swing_polyline(rect: Rect2, t0: float, t1: float, segments: int = 24) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = maxi(segments, 2)
	for i in n + 1:
		var u: float = float(i) / float(n)
		pts.append(swing_point(rect, lerpf(t0, t1, u)))
	return pts


func tempo_rect(control_size: Vector2, top_pad: float = 110.0, bottom_pad: float = 70.0) -> Rect2:
	var h: float = maxf(control_size.y - top_pad - bottom_pad, 100.0)
	var w: float = maxf(control_size.x - 20.0, 100.0)
	return Rect2(10.0, top_pad, w, h)


func tempo_angle(t: float) -> float:
	return lerpf(PI * 0.92, PI * 0.08, clampf(t, 0.0, 1.0))


func tempo_center(rect: Rect2) -> Vector2:
	return Vector2(rect.position.x + rect.size.x * 0.55, rect.position.y + rect.size.y * 0.55)


func tempo_radius(rect: Rect2) -> float:
	return minf(rect.size.x, rect.size.y) * 0.42


func tempo_point(rect: Rect2, t: float) -> Vector2:
	var c: Vector2 = tempo_center(rect)
	var r: float = tempo_radius(rect)
	var a: float = tempo_angle(t)
	return c + Vector2(cos(a), -sin(a)) * r


func tempo_polyline(rect: Rect2, t0: float, t1: float, segments: int = 28) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = maxi(segments, 2)
	for i in n + 1:
		var u: float = float(i) / float(n)
		pts.append(tempo_point(rect, lerpf(t0, t1, u)))
	return pts


func lean_rect(control_size: Vector2) -> Rect2:
	var y: float = control_size.y - 58.0
	return Rect2(16.0, y - 36.0, maxf(control_size.x - 32.0, 80.0), 48.0)


func lean_point(rect: Rect2, t: float) -> Vector2:
	var tt: float = clampf(t, 0.0, 1.0)
	var c: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.85)
	var r: float = rect.size.x * 0.48
	var a: float = lerpf(PI * 0.85, PI * 0.15, tt)
	return c + Vector2(cos(a), -sin(a) * 0.35) * r


func lean_polyline(rect: Rect2, segments: int = 20) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in segments + 1:
		pts.append(lean_point(rect, float(i) / float(segments)))
	return pts


func draw_thick_polyline(canvas: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	for i in pts.size() - 1:
		canvas.draw_line(pts[i], pts[i + 1], color, width, true)
