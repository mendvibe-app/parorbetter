extends Node

## Vendored from kyoz/godot-haptics (v1.0.6, Godot 4.x autoload).
## Call init() once at boot. No-ops safely when native plugin is absent (desktop/editor).

signal on_error(error_message)

var haptics = null


func init() -> void:
	if Engine.has_singleton("Haptics"):
		haptics = Engine.get_singleton("Haptics")


func ready() -> bool:
	return haptics != null


func light() -> void:
	if not haptics:
		not_found_plugin()
		return
	haptics.light()


func medium() -> void:
	if not haptics:
		not_found_plugin()
		return
	haptics.medium()


func heavy() -> void:
	if not haptics:
		not_found_plugin()
		return
	haptics.heavy()


func not_found_plugin() -> void:
	# Desktop/editor: expected. Avoid spamming every shot — print once.
	if not has_meta("_warned"):
		set_meta("_warned", true)
		print("[Haptics] Native plugin not found (editor/desktop or export without Haptics enabled).")
