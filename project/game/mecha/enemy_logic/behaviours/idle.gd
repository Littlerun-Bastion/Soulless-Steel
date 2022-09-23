extends Node


var nodes = ["idle"]
var initial_state = "idle"

func get_nodes():
	return nodes

## CONNECTION METHODS ##


## STATE METHODS ##


func do_idle(_dt, enemy):
	#Make the mecha visible
	enemy.mecha_heat = 100
