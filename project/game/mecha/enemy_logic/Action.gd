extends Node

class_name Action

#If this action should be considered at all
func is_valid(_agent) -> bool:
	return true

#Optional, in case action is valid, how much it "costs"
func get_cost(_blackboard) -> int:
	return 0

#Dict of blackboard states preconditions that this action needs to be used
func get_preconditions() -> Dictionary:
	return {}

#What conditions/states this action satisfies
func get_effects() -> Dictionary:
	return {}

#Action implementation, Returns true when the task is complete
func perform(_actor, _delta) -> bool:
	return false
