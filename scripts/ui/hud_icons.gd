class_name HudIcons
extends Object

## Silhouette textures for glance HUD (lie under ball, club in hand).

const LIE := {
	"Tee": preload("res://assets/ui/lie_tee.png"),
	"Fairway": preload("res://assets/ui/lie_fairway.png"),
	"Rough": preload("res://assets/ui/lie_rough.png"),
	"Sand": preload("res://assets/ui/lie_sand.png"),
	"Green": preload("res://assets/ui/lie_green.png"),
}

const CLUB_DRIVER := preload("res://assets/ui/club_driver.png")
const CLUB_WOOD := preload("res://assets/ui/club_wood.png")
const CLUB_HYBRID := preload("res://assets/ui/club_hybrid.png")
const CLUB_IRON := preload("res://assets/ui/club_iron.png")
const CLUB_WEDGE := preload("res://assets/ui/club_wedge.png")
const CLUB_PUTTER := preload("res://assets/ui/club_putter.png")

const TENDENCY := {
	"rushed_transition": preload("res://assets/ui/tendency_rushed.png"),
	"lingering_top": preload("res://assets/ui/tendency_lingering.png"),
	"slice_tendency": preload("res://assets/ui/tendency_slice.png"),
	"hook_tendency": preload("res://assets/ui/tendency_hook.png"),
	"contact_issue": preload("res://assets/ui/tendency_contact.png"),
	"on_track": preload("res://assets/ui/tendency_on_track.png"),
	"insufficient_data": preload("res://assets/ui/tendency_unknown.png"),
}


static func lie_texture(lie: String) -> Texture2D:
	if lie == "Trees":
		return LIE["Rough"]  # ponytail: tree-specific icon later
	return LIE.get(lie, LIE["Fairway"])


static func club_texture(club_name: String) -> Texture2D:
	if club_name == "Putter":
		return CLUB_PUTTER
	if club_name == "Driver":
		return CLUB_DRIVER
	if club_name.contains("Wood"):
		return CLUB_WOOD
	if club_name.contains("Hybrid"):
		return CLUB_HYBRID
	if BallPhysics.is_wedge_family(club_name):
		return CLUB_WEDGE
	return CLUB_IRON


static func tendency_texture(tag: String) -> Texture2D:
	return TENDENCY.get(tag, null)
