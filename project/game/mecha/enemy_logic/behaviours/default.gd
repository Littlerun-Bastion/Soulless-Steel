extends Node


var nodes = ["roaming", "targeting"]
var initial_state = "roaming"

func get_nodes():
	return nodes

## CONNECTION METHODS ##

func roaming_to_targeting(args):
	return false
	if args.valid_target:
		args.going_to_position = false
	return args.valid_target


func targeting_to_roaming(args):
	if not args.valid_target:
		args.going_to_position = false
	return not args.valid_target


## STATE METHODS ##


func do_roaming(dt, enemy):
	if not enemy.going_to_position:
		enemy.going_to_position = true
		enemy.NavAgent.set_target_location(enemy.arena.get_random_position())
	enemy.navigate_to_target(dt)
	
	
	enemy.check_for_targets()


func do_targeting(dt, enemy):
	enemy.check_for_targets()
	if not enemy.valid_target:
		return
	
	if not enemy.going_to_position:
		enemy.going_to_position = true
		enemy.NavAgent.set_target_location(enemy.random_targeting_pos())
	
	enemy.navigate_to_target(dt)
	
	enemy.shoot_weapons()
