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
		var data = connections[connection]
		var behaviour = data[0]
		var func_name = data[1]
		if behaviour.callv(func_name, arguments):
			valid_connections[connection] = true
	return valid_connections


