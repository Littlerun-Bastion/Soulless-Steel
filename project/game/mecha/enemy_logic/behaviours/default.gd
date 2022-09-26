extends Node

#Essential variables
var nodes = ["roaming", "targeting"]
var initial_state = "roaming"

#Custom variables
var engage_distance = 2000
var max_shooting_distance = 3500

func get_nodes():
	return nodes

## CONNECTION METHODS ##

func roaming_to_targeting(args):
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
	
	
	enemy.check_for_targets(engage_distance, max_shooting_distance)


func do_targeting(dt, enemy):
	enemy.check_for_targets(engage_distance, max_shooting_distance)
	if not enemy.valid_target:
		return
	
	if not enemy.going_to_position:
		enemy.going_to_position = true
		enemy.NavAgent.set_target_location(enemy.random_targeting_pos(400,800))
	
	enemy.navigate_to_target(dt)
	
	enemy.shoot_weapons()
