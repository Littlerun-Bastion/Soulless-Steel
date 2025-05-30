extends Node

const POSITIONAL_ACCURACY = 400.0
const THROTTLE_CHANGE_TIME = 1.0

#Essential variables
var nodes = ["roam", "seek", "alert", "alert_roam", "ambush", "ambush_lock", "in_combat", "attack", "defend"]
var initial_state = "roam"

#Custom variables
var engage_distance = 1800
var min_kite_distance = 1500
var max_kite_distance = 1700
var cqb_distance = 1200
var max_shooting_distance = 2000
var weapon_heat_threshold = 0.75
var general_heat_threshold = 0.9
var cooldown_time = 6.0
var barrage_min_time = 2.0
var reaction_speed = 2


var point_of_interest
var cooldown_timer = 0.0
var barrage_timer = 0.0
var lock_timer = 0.0
var aggression = 0
var aiming_at_enemy = false
var reaction_timer = 0.0

func get_nodes():
	return nodes

## CONNECTION METHODS ##


func roam_to_seek(enemy):
	var priority = 0
	if enemy.get_most_recent_loud_noise() or enemy.get_most_recent_quiet_noise():
		priority = 1
	return priority

func seek_to_roam(enemy):
	var priority = 0
	if not enemy.get_most_recent_loud_noise():
		priority = 1
	return priority

func seek_to_alert(enemy):
	var priority = 0
	if enemy.under_fire_timer:
		priority = 3
	return priority

func seek_to_ambush(enemy):
	var priority = 0
	if enemy.get_most_recent_quiet_noise() and enemy.under_fire_timer <= 0:
		priority = 3
	return priority

func roam_to_alert(enemy):
	var priority = 0
	if enemy.under_fire_timer:
		priority = 3
	return priority

func alert_to_alert_roam(_enemy):
	var priority = 0
	if point_of_interest:
		pass
	else:
		priority = 4
	return priority
	
func alert_roam_to_alert(enemy):
	var priority = 0
	if enemy.under_fire_timer:
		priority = 3
	return priority

func ambush_to_ambush_lock(enemy):
	var priority = 0
	if enemy.valid_target and enemy.under_fire_timer <= 0:
		priority = 5
	return priority

func ambush_lock_to_defending_lock(enemy):
	var priority = 0
	if enemy.valid_target and enemy.under_fire_timer > 0:
		priority = 5
	return priority

func alert_to_defending_lock(enemy):
	var priority = 0
	if enemy.valid_target and enemy.under_fire_timer > 0:
		priority = 5
	return priority

func alert_roam_to_defending_lock(enemy):
	var priority = 0
	if enemy.valid_target and enemy.under_fire_timer > 0:
		priority = 5
	return priority

func ambush_lock_to_in_combat(enemy):
	var priority = 0 
	if enemy.valid_target:
		if enemy.get_locked_to() or enemy.global_position.distance_to(enemy.valid_target.global_position) < cqb_distance:
			if enemy.get_locked_to():
				enemy.current_target = enemy.get_locked_to()
			else:
				enemy.current_target = enemy.valid_target
			priority = 6
	return priority

func defending_lock_to_in_combat(enemy):
	var priority = 0 
	if enemy.valid_target:
		if enemy.get_locked_to() or enemy.global_position.distance_to(enemy.valid_target.global_position) < cqb_distance:
			if enemy.get_locked_to():
				enemy.current_target = enemy.get_locked_to()
			else:
				enemy.current_target = enemy.valid_target
			priority = 6
	return priority
	
func alert_to_in_combat(enemy):
	var priority = 0 
	if enemy.valid_target:
		if enemy.get_locked_to() or enemy.global_position.distance_to(enemy.valid_target.global_position) < cqb_distance:
			if enemy.get_locked_to():
				enemy.current_target = enemy.get_locked_to()
			else:
				enemy.current_target = enemy.valid_target
			priority = 6
	return priority

func in_combat_to_attack(enemy):
	var priority = 0
	if enemy.valid_target and enemy.current_target and aggression > 0:
		priority = 7
	return priority

func in_combat_to_defend(enemy):
	var priority = 0
	if enemy.valid_target and enemy.current_target and aggression == 0:
		priority = 7
	return priority
	
func attack_to_defend(enemy):
	var priority = 0
	if enemy.valid_target and enemy.current_target and aggression == 0:
		priority = 7
	return priority
	
func defend_to_attack(enemy):
	var priority = 0
	if enemy.valid_target and enemy.current_target and aggression > 0:
		priority = 7
	return priority

func attack_to_roam(enemy):
	var priority = 0
	if not enemy.valid_target:
		priority = 8
	return priority

func defend_to_roam(enemy):
	var priority = 0
	if not enemy.valid_target:
		priority = 8
	return priority
## STATE METHODS ##

func do_roam(dt, enemy):
	if is_instance_valid(enemy):
		aiming_at_enemy = false
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
		aiming_at_enemy = false
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
		aiming_at_enemy = false
		if enemy.throttle < 1.0:
			enemy.increase_throttle(false, dt/THROTTLE_CHANGE_TIME)
		else:
			enemy.decrease_throttle(1.0, 1.0)
		
		shield_check(enemy)
		
		enemy.check_for_targets(engage_distance, max_shooting_distance)
		if enemy.last_attack_position:
			point_of_interest = enemy.last_attack_position
			enemy.going_to_position = true
			
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
			
		if enemy.NavAgent.is_navigation_finished():
			enemy.going_to_position = false
			point_of_interest = false
	
		enemy.navigate_to_target(dt, 0, 0, false)
	

func do_alert_roam(dt, enemy):
	if is_instance_valid(enemy):
		aiming_at_enemy = false
		if enemy.throttle < 1.0:
			enemy.increase_throttle(false, dt/THROTTLE_CHANGE_TIME)
		else:
			enemy.decrease_throttle(1.0, 1.0)
		if not enemy.going_to_position: #Wander around if we are in the state and have no points of interest.
			point_of_interest = enemy.arena.get_random_position()
			enemy.going_to_position = true
			
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
		
		if enemy.is_shielding:
			enemy.shield_down()
		
		if point_of_interest:
			if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
				enemy.NavAgent.target_position = point_of_interest
		
		enemy.navigate_to_target(dt, 0, 0, false)
		
		if enemy.NavAgent.is_navigation_finished(): 
			enemy.going_to_position = false
			point_of_interest = false
			
func do_ambush(dt, enemy):
	if is_instance_valid(enemy):
		aiming_at_enemy = false
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
		shield_check(enemy)

func do_ambush_lock(dt, enemy):
	if is_instance_valid(enemy):
		aiming_at_enemy = false
		enemy.check_for_targets(engage_distance, max_shooting_distance)
		if not enemy.valid_target:
			enemy.is_locking = false
			return
		
		else:
			enemy.going_to_position = true
			point_of_interest = enemy.valid_target.global_position
			if enemy.global_position.distance_to(enemy.valid_target.global_position) < min_kite_distance:
				enemy.decrease_throttle(0.25, 0.01)
				enemy.navigate_to_target(dt, 1.0, 0.65)
			elif enemy.global_position.distance_to(enemy.valid_target.global_position) > max_kite_distance:
				enemy.decrease_throttle(0.75, 0.01)
				enemy.navigate_to_target(dt, 0.0, 0.65)
			else:
				enemy.decrease_throttle(0, 0.05)
				enemy.navigate_to_target(dt, 1.0, 0.8)
			enemy.is_locking = true	
			shield_check(enemy)

func do_defending_lock(dt, enemy):
	if is_instance_valid(enemy):
		aiming_at_enemy = false
		enemy.check_for_targets(engage_distance, max_shooting_distance)
		if not enemy.valid_target:
			enemy.is_locking = false
			return
		
		else:
			enemy.going_to_position = true
			point_of_interest = enemy.valid_target.global_position
			if enemy.global_position.distance_to(enemy.valid_target.global_position) < min_kite_distance:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 1.0, 0.65)
			elif enemy.global_position.distance_to(enemy.valid_target.global_position) > max_kite_distance:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 0.0, 0.65)
			else:
				enemy.decrease_throttle(0, 0.05)
				enemy.navigate_to_target(dt, 1.0, 0.8)
			enemy.is_locking = true	
			shield_check(enemy)

func do_in_combat(_dt, enemy):
	if is_instance_valid(enemy):
		shield_check(enemy)
		if not enemy.current_target:
			enemy.valid_target = enemy.current_target
		aggression = health_diff(enemy) + heat_diff(enemy) + status_diff(enemy)

func do_attack(dt, enemy):
	if is_instance_valid(enemy):
		if enemy.is_shielding:
			enemy.shield_down()
		if reaction_timer >= reaction_speed and enemy.global_position.distance_to(enemy.current_target.global_position) < max_shooting_distance and enemy.mecha_heat/enemy.max_heat < weapon_heat_threshold:
			enemy.shoot_weapons(enemy.current_target)
		else:
			reaction_timer += dt
		aggression = health_diff(enemy) + heat_diff(enemy) + status_diff(enemy)
		enemy.going_to_position = true
		
		if enemy.can_see_target(enemy.current_target):
			if is_instance_valid(enemy.current_target): point_of_interest = enemy.current_target.global_position
			aiming_at_enemy = true
		else:
			if aiming_at_enemy or not point_of_interest:
				point_of_interest = enemy.get_random_point_on_radius(enemy.current_target.global_position, cqb_distance)
				aiming_at_enemy = false
				reaction_timer = 0.0
		if enemy.get_locked_to() and aiming_at_enemy and reaction_timer >= reaction_speed:
			if enemy.global_position.distance_to(enemy.current_target.global_position) < min_kite_distance:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 1.0, 0.65)
			elif enemy.global_position.distance_to(enemy.current_target.global_position) > max_kite_distance:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 0.0, 0.65)
			else:
				enemy.decrease_throttle(0, 0.05)
				enemy.navigate_to_target(dt, 1.0, 0.8)
		elif aiming_at_enemy and reaction_timer >= reaction_speed:
			if enemy.global_position.distance_to(enemy.current_target.global_position) > cqb_distance:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 0.0, 0.65)
			else:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 1.0, 0.65)
		else:
			enemy.increase_throttle(1, 0.01)
			enemy.navigate_to_target(dt, 0.0, 0.65)
			
		if point_of_interest:
			if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
				enemy.NavAgent.target_position = point_of_interest
			
		if enemy.NavAgent.is_navigation_finished():
			enemy.going_to_position = false
			point_of_interest = false

func do_defend(dt, enemy):
	if is_instance_valid(enemy):
		shield_check(enemy)
		enemy.going_to_position = true
		aggression = health_diff(enemy) + heat_diff(enemy) + status_diff(enemy)
		if is_instance_valid(enemy.current_target): point_of_interest = enemy.current_target.global_position
		if enemy.global_position.distance_to(point_of_interest) < max_kite_distance:
			enemy.increase_throttle(1, 0.01)
			enemy.navigate_to_target(dt, 0.0, 0.65)
		else:
			enemy.decrease_throttle(0, 0.05)
			enemy.navigate_to_target(dt, 1.0, 0.8)
			
		
		if enemy.can_see_target(enemy.current_target):
			if is_instance_valid(enemy.current_target): point_of_interest = enemy.current_target.global_position
			aiming_at_enemy = true
		else:
			if aiming_at_enemy or not point_of_interest:
				aiming_at_enemy = false
				reaction_timer = 0.0
				
		if enemy.global_position.distance_to(point_of_interest) < max_kite_distance and enemy.mecha_heat/enemy.max_heat < weapon_heat_threshold:
			if reaction_timer >= reaction_speed:
				enemy.shoot_weapons(enemy.current_target)
			else:
				reaction_timer += dt

func health_diff(enemy):
	if is_instance_valid(enemy) and enemy.current_target:
		if is_instance_valid(enemy.current_target):
			var health_pc = enemy.hp/enemy.max_hp
			var health_target_pc = enemy.current_target.hp/enemy.current_target.max_hp
			if health_target_pc <= 0.33:
				return 2
			if health_pc >= health_target_pc:	
				if health_pc - 0.33 >= health_target_pc:
					return 2
				else:
					return 1
			else:
				if health_target_pc - 0.33 >= health_pc:
					return -1
				else:
					return 0
		else:
			return 0
	else:
		return 0

func heat_diff(enemy):
	if is_instance_valid(enemy) and enemy.current_target:
		if is_instance_valid(enemy.current_target):
			var heat_pc = enemy.mecha_heat/enemy.max_heat
			var heat_target_pc = enemy.current_target.mecha_heat/enemy.current_target.max_heat
			if heat_pc > weapon_heat_threshold:
				if heat_pc > general_heat_threshold:
					if health_diff(enemy) == 2:
						return 1
					else:
						return -2
				else:
					return -1
			if heat_pc >= heat_target_pc:
				if heat_pc - 0.33 >= heat_target_pc:
					return 1
				else:
					return 0
			else:
				return 0
		else:
			return 0
	else:
		return 0

func status_diff(enemy):
	if is_instance_valid(enemy) and enemy.current_target:
		if is_instance_valid(enemy.current_target):
			if enemy.has_any_status():
				if enemy.current_target.has_any_status():
					return 0
				else:
					return -1
			else:
				if enemy.current_target.has_any_status():
					if heat_diff(enemy) >= 0:
						return 1
					else:
						return 0
				else:
					return 0
		else:
			return 0	
	else:
		return 0

func shield_check(enemy):
	if is_instance_valid(enemy):
		if enemy.under_fire_timer > 0.0:
			if not enemy.is_shielding and enemy.mecha_heat < enemy.max_heat*general_heat_threshold:
				enemy.shield_up()
		else:
			if enemy.is_shielding:
				enemy.shield_down()
