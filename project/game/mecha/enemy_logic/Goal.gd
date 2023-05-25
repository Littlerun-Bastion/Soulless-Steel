extends Node

class_name Goal

# Checks if the goal should be considered in the planner or not
func is_valid(_agent) -> bool:
	return true

# Current goal priority, can be dynamic
func get_priority(_agent) -> int:
	return 1

# Goal's desired agent's blackboard state
func get_desired_state(_agent) -> Dictionary:
	return {}
