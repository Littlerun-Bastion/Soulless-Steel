extends Goal

# This is not a valid goal when hunger is less than 50.
func is_valid(_agent) -> bool:
	return WorldState.get_state("hunger", 0)  > 50 and WorldState.get_elements("food").size() > 0


func priority(_agent) -> int:
	return 1 if WorldState.get_state("health", 0) < 75 else 2


func get_desired_state(_agent) -> Dictionary:
	return {
		"enemy_nearby": false
	}
