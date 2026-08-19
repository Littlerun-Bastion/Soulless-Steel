extends RefCounted

# One node in the AI state-machine graph. Stores outgoing transitions and
# their condition callables. Held by Graphs (also RefCounted), never in
# the scene tree.

var connections = {}
var id


func add_connection(final, condition):
	connections[final] = condition


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
