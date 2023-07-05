extends Node

const POSITIONAL_ACCURACY = 200.0

#Essential variables
var nodes = ["roaming", "targeting"]
var initial_state = "roaming"

#Custom variables
var engage_distance = 2000
var max_shooting_distance = 3500
var point_of_interest

func get_nodes():
	return nodes

## CONNECTION METHODS ##

func roaming_to_targeting(enemy):
	if enemy.valid_target:
		enemy.going_to_position = false
	return enemy.valid_target


func targeting_to_roaming(enemy):
	if not enemy.valid_target:
		enemy.going_to_position = false
	return not enemy.valid_target

## STATE METHODS ##

func do_roaming(dt, enemy):
	if not enemy.going_to_position:
		point_of_interest = enemy.arena.get_random_position()
		enemy.going_to_position = true
		
	if enemy.get_most_recent_loud_noise():
		if enemy.global_position.distance_to(enemy.get_most_recent_loud_noise().position) > POSITIONAL_ACCURACY:
			point_of_interest = enemy.get_most_recent_loud_noise().position
			enemy.going_to_position = true
		else:
			enemy.senses.sounds.erase(enemy.get_most_recent_loud_noise())
			enemy.going_to_position = false
			point_of_interest = false
			#else:
	
	if point_of_interest:		
		if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
			enemy.NavAgent.target_position = point_of_interest
	else:
		print("No POI")
	
	enemy.navigate_to_target(dt)
	
	if enemy.NavAgent.is_navigation_finished():
		enemy.going_to_position = false
		point_of_interest = false
		print("Point reached")
	
	
	#enemy.check_for_targets(engage_distance, max_shooting_distance)


func do_targeting(dt, enemy):
	enemy.check_for_targets(engage_distance, max_shooting_distance)
	if not enemy.valid_target:
		return
	
	if not enemy.going_to_position:
		enemy.going_to_position = true
		enemy.NavAgent.target_position = enemy.random_targeting_pos(400,800)
	
	enemy.navigate_to_target(dt)
	
	enemy.shoot_weapons()
