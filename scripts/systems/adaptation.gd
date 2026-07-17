class_name Adaptation
extends RefCounted


## Map rolling miss bias to hazard side for a hole.
## Returns HoleData.HazardBias, possibly overriding the hole default when bias is strong.
static func effective_hazard_bias(hole: HoleData) -> HoleData.HazardBias:
	var bias := GameState.get_adaptation_bias()
	# Strong player tendency overrides / reinforces placement on later holes
	if hole.hole_number >= 4:
		if bias > 0.35:
			return HoleData.HazardBias.RIGHT
		if bias < -0.35:
			return HoleData.HazardBias.LEFT
	return hole.hazard_bias


## Extra wind nudge opposing common miss (push ball toward danger they create).
static func wind_adaptation_nudge() -> Vector2:
	var bias := GameState.get_adaptation_bias()
	# Right misses (slice) → wind from left (positive x pushes right toward right hazards)
	return Vector2(bias * 12.0, 0.0)


static func bias_label() -> String:
	var b := GameState.get_adaptation_bias()
	if b > 0.25:
		return "Slice bias (R)"
	if b < -0.25:
		return "Hook bias (L)"
	return "Neutral"
