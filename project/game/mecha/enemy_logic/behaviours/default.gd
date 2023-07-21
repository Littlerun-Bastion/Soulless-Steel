extends Node

const POSITIONAL_ACCURACY = 400.0
const THROTTLE_CHANGE_TIME = 1.0

#Essential variables
var nodes = ["roam", "seek", "alert"]
var initial_state = "roam"

#Custom variables
var engage_distance = 2000
var min_kite_distance = 1500
var max_kite_distance = 1700
var max_shooting_distance = 3500
var weapon_heat_threshold = 0.75
var general_heat_threshold = 0.9
var cooldown_time = 6.0
var barrage_min_time = 2.0


var point_of_interest
var cooldown_timer = 0.0
var barrage_timer = 0.0

func get_nodes():
	return nodes

## CONNECTION METHODS ##


func roam_to_seek(enemy):
	var priority = 0
	if enemy.get_most_recent_loud_noise():
		priority = 1
		print("Seeking")
	return priority

func seek_to_roam(enemy):
	var priority = 0
	if not enemy.get_most_recent_loud_noise():
		priority = 1
		print("Roaming")
	return priority

func seek_to_alert(enemy):
	var priority = 0
	if enemy.under_fire_timer:
		priority = 3
		print("Alert")
	return priority

func roam_to_alert(enemy):
	var priority = 0
	if enemy.under_fire_timer:
		priority = 3
		print("Alert")
	return priority

## STATE METHODS ##

func do_roam(dt, enemy):
	if is_instance_valid(enemy):
		if enemy.throttle < 1.0:
			enemy.increase_throttle(false, dt/THROTTLE_CHANGE_TIME)
		else:
			enemy.decrease_throttle(1.0, 1.0)
		if not enemy.going_to_position: #Wander around if we are in the state and have no points of interest.
			point_of_interest = enemy.arena.get_random_position()
			enemy.going_to_position = true
		
		if point_of_interest:
			if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
				enemy.NavAgent.target_position = point_of_interest
		
		enemy.navigate_to_target(dt, 0, 0.65, false)
		
		if enemy.NavAgent.is_navigation_finished(): 
			enemy.going_to_position = false
			point_of_interest = false

func do_seek(dt, enemy):
	if is_instance_valid(enemy):
		if enemy.throttle < 1.0:
			enemy.increase_throttle(false, dt/THROTTLE_CHANGE_TIME)
		else:
			enemy.decrease_throttle(1.0, 1.0)
		
		if enemy.get_most_recent_loud_noise():
			if enemy.global_position.distance_to(enemy.get_most_recent_loud_noise().position) > POSITIONAL_ACCURACY:
				point_of_interest = enemy.get_most_recent_loud_noise().position
				enemy.going_to_position = true
			else:
				enemy.senses.sounds.erase(enemy.get_most_recent_loud_noise())
				enemy.going_to_position = false
				point_of_interest = false
				
		if point_of_interest:
			if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
				enemy.NavAgent.target_position = point_of_interest
		
		enemy.navigate_to_target(dt, 0, 0, false)
		
		if enemy.NavAgent.is_navigation_finished():
			enemy.going_to_position = false
			point_of_interest = false

func do_alert(dt, enemy):
	if is_instance_valid(enemy):
		if enemy.throttle < 1.0:
			enemy.increase_throttle(false, dt/THROTTLE_CHANGE_TIME)
		else:
			enemy.decrease_throttle(1.0, 1.0)
		
		#enemy.check_for_targets(engage_distance, max_shooting_distance)
		if enemy.last_attack_position:
			point_of_interest = enemy.last_attack_position
			enemy.going_to_position = true
			
	if point_of_interest:
		if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
			enemy.NavAgent.target_position = point_of_interest
	
	enemy.navigate_to_target(dt, 0, 0, true)
	
