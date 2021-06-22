extends Node

const NODE = preload("res://game/mecha/enemy_logic/Node.gd")

var graph = []
var current_state = "idle"

func _ready():
	pass


func add_a_node(id):
	var node = NODE.new()
	node.id = id
	graph.append(node)


func get_a_node(id):
	for a_node in graph:
		if a_node.id == id:
			return a_node


func add_connection(origin, final, condition):
	var origin_node = get_a_node(origin)
	var final_node = get_a_node(final)
	origin_node.add_connection(origin_node, final_node, condition)


func set_state(state):
	current_state = state
