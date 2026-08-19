extends RefCounted

# Minimal debug behaviour: the mech holds position, kept thermally visible so
# it's easy to spot and target. Not assigned to any NPC by default — reachable
# via the Debug "ai_behaviour" override for testing.

var nodes = ["idle"]
var initial_state = "idle"

func get_nodes():
	return nodes

## CONNECTION METHODS ##


## STATE METHODS ##


func do_idle(_dt, enemy):
	#Make the mecha visible
	enemy.internal_temp = 100
