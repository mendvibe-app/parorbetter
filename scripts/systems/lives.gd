class_name LivesSystem
extends RefCounted


## Apply life change for a finished hole. Returns the delta applied.
static func apply_hole_result(result: Scoring.Result) -> int:
	var delta := 0
	match result:
		Scoring.Result.ALBATROSS, Scoring.Result.EAGLE, Scoring.Result.BIRDIE:
			delta = 1
		Scoring.Result.PAR:
			delta = 0
		Scoring.Result.BOGEY:
			delta = -1
		Scoring.Result.DOUBLE_PLUS:
			delta = -2
	GameState.add_lives(delta)
	return delta
