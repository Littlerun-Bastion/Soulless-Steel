extends RefCounted

# Inert training-dummy AI. A single "roam" state with no transitions, so it
# never leaves it; do_roam is a deliberate no-op — the mech just stands there.
# Used by the "Test Dummy" NPC (database/npcs/special_npcs/Test Dummy.tres) as
# a passive target for testing weapons and damage.

var nodes = ["roam"]
var initial_state = "roam"

func get_nodes():
	return nodes

## STATE METHODS ##

func do_roam(_dt, _enemy):
	pass
