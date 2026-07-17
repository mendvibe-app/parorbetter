class_name ShotResult
extends RefCounted

enum ContactQuality { PERFECT, GOOD, THIN, FAT, MISS }

var power: float = 0.5  ## 0–1
var stance_stability: float = 1.0  ## 0–1
var path_error: float = 0.0  ## −1 (hook/left) … +1 (slice/right)
var contact_quality: ContactQuality = ContactQuality.GOOD
var intended_shape: float = 0.0  ## draw negative, fade positive


func contact_label() -> String:
	match contact_quality:
		ContactQuality.PERFECT:
			return "perfect"
		ContactQuality.GOOD:
			return "good"
		ContactQuality.THIN:
			return "thin"
		ContactQuality.FAT:
			return "fat"
		_:
			return "miss"


func is_perfect() -> bool:
	return contact_quality == ContactQuality.PERFECT


static func make(
	p_power: float,
	p_stability: float,
	p_path: float,
	p_contact: ContactQuality,
	p_shape: float = 0.0
) -> ShotResult:
	var r := ShotResult.new()
	r.power = clampf(p_power, 0.0, 1.0)
	r.stance_stability = clampf(p_stability, 0.0, 1.0)
	r.path_error = clampf(p_path, -1.0, 1.0)
	r.contact_quality = p_contact
	r.intended_shape = p_shape
	return r
