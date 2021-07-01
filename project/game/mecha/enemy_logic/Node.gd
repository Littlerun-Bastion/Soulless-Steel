extends Node

var connections = {}
var id

func _ready():
	pass


func add_connection(final, condition):
	connections[final] = condition
	

func get_connections():
	return connections

	
func get_valid_connections(arguments):
	var valid_connections = {}
	for connection in connections:
		if connections[connection].call_func(arguments):
			valid_connections[connection] = true
	return valid_connections


