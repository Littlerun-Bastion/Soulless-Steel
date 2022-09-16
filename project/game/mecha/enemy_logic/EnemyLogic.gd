extends Node

const GRAPH = preload("res://game/mecha/enemy_logic/Graphs.gd")
const BEHAVIOUR_PATH = "res://game/mecha/enemy_logic/behaviours/"

var g = GRAPH.new()
var current_state
var behaviour

func setup(behaviour_name):
	var dir = Directory.new()
	var path = BEHAVIOUR_PATH + str(behaviour_name) + ".gd"
	assert(dir.file_exists(path), "Not a valid enemy behaviour: " + str(behaviour_name))
	
	behaviour = load(path).new()
	
	for node in behaviour.get_nodes():
		g.add_a_node(node)
	
	g.set_state(behaviour.initial_state)
	
	for node_i in behaviour.get_nodes():
		for node_j in behaviour.get_nodes():
			var func_name = node_i+"_to_"+node_j
			if behaviour.has_method(func_name):
				g.add_connection(node_i, node_j, funcref(behaviour, func_name))


func get_current_state():
	current_state = g.get_current_state()
	return g.get_current_state()
	
	
func update(enemy):
	var a_node = g.get_a_node(g.current_state)
	var valid_connections = a_node.get_valid_connections(enemy)
	for connection in valid_connections:
		g.set_state(connection.id)
		break


func run(enemy, dt):
	var state = get_current_state()
	if behaviour.has_method("do_"+state):
		behaviour.call("do_"+state, dt, enemy)
