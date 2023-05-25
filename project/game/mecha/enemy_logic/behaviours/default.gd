extends Node


var valid_goals = [
	"hunt_target",
	"explore"
]

var valid_actions = [
	
]


func get_goals():
	return valid_goals.duplicate()


func get_actions():
	return valid_actions.duplicate()

