class_name Scoring
extends RefCounted

enum Result { ALBATROSS, EAGLE, BIRDIE, PAR, BOGEY, DOUBLE_PLUS }


static func result_from_diff(diff: int) -> Result:
	if diff <= -3:
		return Result.ALBATROSS
	if diff == -2:
		return Result.EAGLE
	if diff == -1:
		return Result.BIRDIE
	if diff == 0:
		return Result.PAR
	if diff == 1:
		return Result.BOGEY
	return Result.DOUBLE_PLUS


static func label(result: Result) -> String:
	match result:
		Result.ALBATROSS:
			return "Albatross"
		Result.EAGLE:
			return "Eagle"
		Result.BIRDIE:
			return "Birdie"
		Result.PAR:
			return "Par"
		Result.BOGEY:
			return "Bogey"
		_:
			return "Double+"


static func is_birdie_or_better(result: Result) -> bool:
	return result == Result.ALBATROSS or result == Result.EAGLE or result == Result.BIRDIE


static func is_ace(strokes: int) -> bool:
	return strokes == 1


static func hole_label(result: Result, strokes: int) -> String:
	if is_ace(strokes):
		return "Hole in One"
	return label(result)
