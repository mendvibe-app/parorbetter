class_name UiScale
extends Object

## Player-facing type + touch floor for the 1080×1920 canvas.
## .tscn files use matching literals; code paths reference these consts.

const CAPTION := 32
const BODY := 40
const TITLE := 48
const TOUCH_MIN := 120

## Near-white secondary text (hints/adapt) — avoids muted green-on-green.
const TEXT_SECONDARY := Color(0.92, 0.95, 0.88, 1.0)

## Base layout before safe-area insets (viewport px).
const HUD_HEIGHT := 200.0
const CONTROLS_PAD_BOTTOM := 16.0
const CONTROLS_HEIGHT := 194.0
const CONFIRM_AIM_TOP := -296.0
const CONFIRM_AIM_BOTTOM := -160.0
const FEEDBACK_TOP := 220.0
const WIND_TOP := 290.0
const SHOT_RESULT_TOP := 220.0


## Map screen safe rect → viewport L/T/R/B via stretch inverse. Pure for self-check.
static func screen_insets_to_viewport(win: Vector2, safe: Rect2, stretch: Transform2D, vp_size: Vector2) -> Vector4:
	if win.x < 1.0 or win.y < 1.0 or vp_size.x < 1.0 or vp_size.y < 1.0:
		return Vector4.ZERO
	var inv := stretch.affine_inverse()
	var tl: Vector2 = inv * safe.position
	var br: Vector2 = inv * safe.end
	return Vector4(
		maxf(tl.x, 0.0),
		maxf(tl.y, 0.0),
		maxf(vp_size.x - br.x, 0.0),
		maxf(vp_size.y - br.y, 0.0),
	)


static func viewport_safe_margins(vp: Viewport) -> Vector4:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0:
		return Vector4.ZERO
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var stretch := Transform2D.IDENTITY
	var root := vp.get_tree().root if vp.get_tree() else null
	if root:
		stretch = root.get_stretch_transform()
	var vis := vp.get_visible_rect().size
	return screen_insets_to_viewport(win, safe, stretch, vis)


## Apply top/bottom safe insets to hole UI chrome.
static func apply_hole_safe_area(
	hud: Control,
	feedback: Control,
	wind_banner: Control,
	shot_panel: Control,
	confirm_aim: Control,
	shot_result: Control = null,
) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	var m := viewport_safe_margins(hud.get_viewport())
	var top := m.y
	var bottom := m.w

	hud.offset_top = top
	hud.offset_bottom = HUD_HEIGHT + top

	if feedback:
		feedback.offset_top = FEEDBACK_TOP + top
		feedback.offset_bottom = feedback.offset_top + 60.0
	if wind_banner:
		wind_banner.offset_top = WIND_TOP + top
		wind_banner.offset_bottom = wind_banner.offset_top + 90.0

	if shot_result:
		shot_result.offset_top = SHOT_RESULT_TOP + top

	if shot_panel:
		var controls := shot_panel.get_node_or_null("Controls") as Control
		if controls:
			controls.offset_bottom = -(CONTROLS_PAD_BOTTOM + bottom)
			controls.offset_top = -(CONTROLS_PAD_BOTTOM + CONTROLS_HEIGHT + bottom)

	if confirm_aim:
		confirm_aim.offset_top = CONFIRM_AIM_TOP - bottom
		confirm_aim.offset_bottom = CONFIRM_AIM_BOTTOM - bottom
