extends Node

const POSITIONAL_ACCURACY = 400.0
const THROTTLE_CHANGE_TIME = 1.0

#Essential variables
var nodes = ["roaming", "ambushing", "targeting"]
var initial_state = "roaming"

#Custom variables
var engage_distance = 2000
var max_shooting_distance = 3500
var point_of_interest

func get_nodes():
	return nodes

## CONNECTION METHODS ##

func roaming_to_targeting(enemy):
	var priority = 0
	if enemy.valid_target:
		enemy.going_to_position = false
		priority = 10
	return priority

func roaming_to_ambushing(enemy):
	var priority = 0
	if enemy.get_most_recent_quiet_noise():
		priority = 2
		print("Ambushing")
	return priority
	
func ambushing_to_roaming(enemy):
	var priority = 0
	if enemy.get_most_recent_quiet_noise():
		pass
	else:
		priority = 2
		print("Roaming")
	return priority

func targeting_to_roaming(enemy):
	var priority = 0
	if not enemy.valid_target:
		enemy.going_to_position = false
		priority = 1
	return priority

## STATE METHODS ##

func do_roaming(dt, enemy):
	if enemy.throttle < 1.0:
		enemy.increase_throttle(false, dt/THROTTLE_CHANGE_TIME)
	else:
		enemy.decrease_throttle(1.0, 1.0)
	if not enemy.going_to_position: #Wander around if we are in the state and have no points of interest.
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
	
	enemy.navigate_to_target(dt)
	
	if enemy.NavAgent.is_navigation_finished():
		enemy.going_to_position = false
		point_of_interest = false
	
	
	#enemy.check_for_targets(engage_distance, max_shooting_distance)

func do_ambushing(dt, enemy):
	if enemy.throttle > 0.5:
		enemy.decrease_throttle(false, dt/THROTTLE_CHANGE_TIME)
	else:
		enemy.increase_throttle(0.5, 0.5)
	if not enemy.going_to_position: #Wander around if we are in the state and have no points of interest.
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
			
	if enemy.get_most_recent_quiet_noise():
		if enemy.global_position.distance_to(enemy.get_most_recent_quiet_noise().position) > POSITIONAL_ACCURACY:
			point_of_interest = enemy.get_most_recent_quiet_noise().position
			enemy.going_to_position = true
		else:
			for sound in enemy.senses.sounds:
				if sound.source == enemy.get_most_recent_quiet_noise().source and sound.volume_type == "quiet":
					enemy.senses.sounds.erase(sound)
			enemy.senses.sounds.erase(enemy.get_most_recent_quiet_noise())
			enemy.going_to_position = false
			point_of_interest = false
		
	if point_of_interest:		
		if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
			enemy.NavAgent.target_position = point_of_interest
	
	enemy.navigate_to_target(dt)
	
	if enemy.NavAgent.is_navigation_finished():
		enemy.going_to_position = false
		point_of_interest = false
	

func do_targeting(dt, enemy):
	enemy.check_for_targets(engage_distance, max_shooting_distance)
	if not enemy.valid_target:
		return
	
	if not enemy.going_to_position:
		enemy.going_to_position = true
		enemy.NavAgent.target_position = enemy.random_targeting_pos(400,800)
	
	enemy.navigate_to_target(dt)
	
	enemy.shoot_weapons()
