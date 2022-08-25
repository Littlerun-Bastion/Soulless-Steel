extends Node

const GRAPH = preload("res://game/mecha/enemy_logic/Graphs.gd")

var g = GRAPH.new()
var current_state


func setup():
	g.add_a_node("idle")
	g.add_a_node("roaming")
	g.add_a_node("targeting")

	add_connection("idle", "roaming")
	#add_connection("idle", "targeting")
	#add_connection("roaming", "idle")
	#add_connection("roaming", "targeting")
	#add_connection("targeting", "idle")
	#add_connection("targeting", "roaming")


func add_connection(from, to):
	g.add_connection(from, to, funcref(self, from+"_to_"+to))


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

func idle_to_roaming(args):
	return not args.valid_target


func idle_to_targeting(args):
	return args.valid_target


func roaming_to_idle(_args):
	return false


func roaming_to_targeting(args):
	if args.valid_target:
		args.going_to_position = false
	return args.valid_target


func targeting_to_idle(_args):
	return false


func targeting_to_roaming(args):
	if not args.valid_target:
		args.going_to_position = false
	return not args.valid_target
