extends Node

const GRAPH = preload("res://game/mecha/enemy_logic/Graphs.gd")

var g = GRAPH.new()
var current_state

func _ready():
	pass


func setup():
	g.add_a_node("idle")
	g.add_a_node("roaming")
	g.add_a_node("targeting")

	g.add_connection("idle", "roaming", funcref(self, "idle_to_roaming"))
	g.add_connection("idle", "targeting", funcref(self, "idle_to_targeting"))
	g.add_connection("roaming", "idle", funcref(self, "roaming_to_idle"))
	g.add_connection("roaming", "targeting", funcref(self, "roaming_to_targeting"))
	g.add_connection("targeting", "idle", funcref(self, "targeting_to_idle"))
	g.add_connection("targeting", "roaming", funcref(self, "targeting_to_roaming"))


func get_current_state():
	current_state = g.get_current_state()
	return g.get_current_state()
	
	
func updateFiniteLogic(enemy):
	var a_node = g.get_a_node(g.current_state)
	var valid_connections = a_node.get_valid_connections(enemy)
	for connection in valid_connections:
		g.set_state(connection.id)
		break


## STATE METHODS ##

func idle_to_roaming(_args):
	if not _args.valid_target and g.get_current_state()=="idle":
		return true
	else:
		return false
	

func idle_to_targeting(_args):
	if _args.valid_target:
		return true
	else:
		return false


func roaming_to_idle(_args):
	return false


func roaming_to_targeting(_args):
	if _args.valid_target and g.get_current_state() != "idle":
		return true
	else:
		return false


func targeting_to_idle(_args):
	return false


func targeting_to_roaming(_args):
	return false



