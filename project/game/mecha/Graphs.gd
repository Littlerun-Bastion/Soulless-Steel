extends Node

onready var n = "res://game/mecha/Node.gd"

var graph = []

func _ready():
	pass

	
func add_a_node(id):
	var a_node = n.new(id)
	a_node.id = id
	graph.insert()
	
func get_a_node(id):
	for a_node in graph:
		if a_node.id == id:
			return a_node
	
func add_connection(origin, final, condition):
	var origin_node = get_a_node(origin)
	var final_node = get_a_node(final)
	origin_node.add_connection(origin_node, final_node, condition)
	

