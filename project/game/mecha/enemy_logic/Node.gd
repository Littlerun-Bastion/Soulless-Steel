extends Node

var connections = {}
var id

func _ready():
	pass


func add_connection(final, condition):
	connections[final] = condition
	

func get_connections():
	return connections


#Gets the "highest value" connection, false if there isn't any valid
func get_best_connection(arguments):
	var best_connection = false
	var connection_value = -999
	for connection in connections:
		var data = connections[connection]
		var behaviour = data[0]
		var func_name = data[1]
		var value = behaviour.callv(func_name, [arguments])
		if value and value > connection_value:
			connection_value = value
			best_connection = connection
	return best_connection


func get_valid_connections(arguments):
	var valid_connections = {}
	for connection in connections:
		var data = connections[connection]
		var behaviour = data[0]
		var func_name = data[1]
		if behaviour.callv(func_name, [arguments]):
			valid_connections[connection] = true
	return valid_connections


