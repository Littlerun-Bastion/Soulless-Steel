extends Node

const POSITIONAL_ACCURACY = 400.0
const THROTTLE_CHANGE_TIME = 1.0

#Essential variables
var nodes = ["roaming", "ambushing", "locking", "barraging", "cooling"]
var initial_state = "roaming"

#Custom variables
var engage_distance = 2000
var min_kite_distance = 1500
var max_kite_distance = 1700
var max_shooting_distance = 3500
var weapon_heat_threshold = 0.75
var general_heat_threshold = 0.9
var cooldown_time = 6.0


var point_of_interest
var cooldown_timer = 0.0

func get_nodes():
	return nodes

## CONNECTION METHODS ##


func roaming_to_ambushing(enemy):
	var priority = 0
	if enemy.get_most_recent_quiet_noise():
		priority = 2
	return priority
	
func ambushing_to_roaming(enemy):
	var priority = 0
	if enemy.get_most_recent_quiet_noise():
		pass
	else:
		priority = 2
	return priority
	
func locking_to_ambushing(enemy):
	var priority = 0
	if not enemy.valid_target:
		enemy.going_to_position = false
		priority = 1
	return priority
	
func ambushing_to_locking(enemy):
	var priority = 0
	if enemy.valid_target:
		priority = 5
	return priority

func locking_to_barraging(enemy):
	var priority = 0
	if enemy.valid_target and enemy.locked_to:
		priority = 6
	return priority

func locking_to_cooling(enemy):
	var priority = 0
	if enemy.mecha_heat > enemy.max_heat * general_heat_threshold:
		priority = 10
	return priority
	
func barraging_to_cooling(enemy):
	var priority = 0
	if enemy.mecha_heat > enemy.max_heat * weapon_heat_threshold:
		priority = 10
	return priority

func cooling_to_ambushing(enemy):
	var priority = 0
	if enemy.mecha_heat < enemy.max_heat * 0.2 or cooldown_time <= 0.0:
		priority = 2
	return priority
	
func cooling_to_roaming(enemy):
	var priority = 0
	if enemy.mecha_heat < enemy.max_heat * 0.2 or cooldown_time <= 0.0:
		priority = 2
	return priority
	
func cooling_to_locking(enemy):
	var priority = 0
	if enemy.mecha_heat < enemy.max_heat * 0.2 or cooldown_time <= 0.0:
		if enemy.valid_target:
			priority = 3
	return priority


## STATE METHODS ##

func do_roaming(dt, enemy):
	if enemy:
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
		
		if point_of_interest:
			if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
				enemy.NavAgent.target_position = point_of_interest
		
		enemy.navigate_to_target(dt, 0, 0.65)
		
		if enemy.NavAgent.is_navigation_finished():
			enemy.going_to_position = false
			point_of_interest = false
		
		
		enemy.check_for_targets(engage_distance, max_shooting_distance)
		if enemy.is_shielding:
			enemy.shield_down()

func do_ambushing(dt, enemy):
	if enemy:
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
					if sound.source and\
					   sound.volume_type == "quiet" and sound.source == enemy.get_most_recent_quiet_noise().source:
						enemy.senses.sounds.erase(sound)
				enemy.senses.sounds.erase(enemy.get_most_recent_quiet_noise())
				enemy.going_to_position = false
				point_of_interest = false
			
		if point_of_interest:		
			if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
				enemy.NavAgent.target_position = point_of_interest
		
		enemy.navigate_to_target(dt, 0, 0)
		
		if enemy.NavAgent.is_navigation_finished():
			enemy.going_to_position = false
			point_of_interest = false
			
		enemy.check_for_targets(engage_distance, max_shooting_distance)
		if enemy.is_shielding:
			enemy.shield_down()

func do_locking(dt, enemy):
	if enemy:
		enemy.check_for_targets(engage_distance, max_shooting_distance)
		if not enemy.valid_target:
			enemy.is_locking = false
			return
		
		enemy.going_to_position = true
		point_of_interest = enemy.valid_target.global_position
		if enemy.global_position.distance_to(enemy.valid_target.global_position) < min_kite_distance:
			enemy.increase_throttle(1, 1)
			enemy.navigate_to_target(dt, 1.0, 0.65)
		elif enemy.global_position.distance_to(enemy.valid_target.global_position) > max_kite_distance:
			enemy.increase_throttle(1, 1)
			enemy.navigate_to_target(dt, 0.0, 0.65)
		else:
			enemy.decrease_throttle(0.5, 0.5)
			enemy.navigate_to_target(dt, 1.0, 0.8)
		enemy.is_locking = true	
		if not enemy.is_shielding and enemy.mecha_heat < enemy.max_heat*general_heat_threshold:
			enemy.shield_up()

func do_barraging(dt, enemy):
	if enemy:
		if enemy.is_shielding:
			enemy.shield_down()
		if enemy.global_position.distance_to(enemy.valid_target.global_position) < min_kite_distance:
			enemy.increase_throttle(1, 1)
			enemy.navigate_to_target(dt, 1.0, 0.65)
		elif enemy.global_position.distance_to(enemy.valid_target.global_position) > max_kite_distance:
			enemy.increase_throttle(1, 1)
			enemy.navigate_to_target(dt, 0.0, 0.65)
		else:
			enemy.decrease_throttle(0.5, 0.5)
			enemy.navigate_to_target(dt, 1.0, 0.8)
		if enemy.mecha_heat < enemy.max_heat*weapon_heat_threshold:
			enemy.shoot_weapons()

func do_cooling(dt, enemy):
	if enemy:
		if enemy.valid_target:
			enemy.navigate_to_target(dt, 1.0, 0.0)
			enemy.increase_throttle(1.0, 1.0)
			cooldown_timer = cooldown_time
			#if not enemy.is_shielding and enemy.mecha_heat < enemy.max_heat*general_heat_threshold and enemy.can_see_target():
				#enemy.shield_up()
			if enemy.is_shielding:
				enemy.shield_down()
		else:
			enemy.going_to_position = false
			cooldown_time = max(cooldown_time - dt, 0)
		
		

