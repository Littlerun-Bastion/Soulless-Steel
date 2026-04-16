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
	if enemy.valid_target and enemy.current_target and aggression <= 0:
		priority = 7
	return priority

func attack_to_defend(enemy):
	var priority = 0
	if enemy.valid_target and enemy.current_target and aggression <= 0:
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
		
		enemy.check_for_targets(_effective_engage_distance(enemy), max_shooting_distance)
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
			
		enemy.check_for_targets(_effective_engage_distance(enemy), max_shooting_distance)
		shield_check(enemy)

func do_ambush_lock(dt, enemy):
	if is_instance_valid(enemy):
		aiming_at_enemy = false
		enemy.check_for_targets(_effective_engage_distance(enemy), max_shooting_distance)
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
		enemy.check_for_targets(_effective_engage_distance(enemy), max_shooting_distance)
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
		var state = _get_self_state(enemy)
		var base_aggression = health_diff(enemy) + heat_diff(enemy) + status_diff(enemy)
		var personality_mod = (enemy.personality.aggression - 0.5) * 2.0
		var state_mod = _self_state_aggression_mod(state)
		aggression = base_aggression + personality_mod + state_mod

func _get_effective_distances(enemy) -> Dictionary:
	var eff = {
		"min_kite": min_kite_distance,
		"max_kite": max_kite_distance,
		"max_shoot": max_shooting_distance,
		"cqb": cqb_distance,
	}
	match enemy.combat_style:
		"sniper":
			eff.max_shoot = enemy.preferred_combat_range
			eff.min_kite = enemy.preferred_combat_range * 0.75
			eff.max_kite = enemy.preferred_combat_range * 0.9
			eff.cqb = enemy.preferred_combat_range * 0.5
		"brawler":
			eff.max_shoot = enemy.preferred_combat_range
			eff.min_kite = 400
			eff.max_kite = 700
			eff.cqb = 500
		"artillery":
			eff.max_shoot = enemy.preferred_combat_range
			eff.min_kite = enemy.preferred_combat_range * 0.8
			eff.max_kite = enemy.preferred_combat_range
			eff.cqb = enemy.preferred_combat_range * 0.6
	return eff


# --- Self-aware mech state helpers ---

func _get_self_state(enemy) -> Dictionary:
	# Returns a snapshot of the AI's own condition for decision-making
	var state = {
		"heat_ratio": 0.0,
		"is_overheating": false,
		"is_hot": false,
		"weapons_working": 0,
		"weapons_total": 0,
		"low_ammo": false,
		"no_ammo": false,
		"mobility_damaged": false,
		"sensors_damaged": false,
	}

	# Heat
	if enemy.overheat_temp > 0:
		var worst_heat = maxf(enemy.internal_temp, enemy.external_temp)
		state.heat_ratio = worst_heat / enemy.overheat_temp
		state.is_overheating = state.heat_ratio >= general_heat_threshold
		state.is_hot = state.heat_ratio >= weapon_heat_threshold

	# Weapons and ammo
	var weapon_slots = ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]
	var disabled_keys = ["left_arm_weapon", "right_arm_weapon", "left_shoulder_weapon", "right_shoulder_weapon"]
	var any_has_ammo = false
	var any_low_ammo = false
	for i in weapon_slots.size():
		var node = enemy.get_weapon_part(weapon_slots[i])
		if node and not enemy.disabled_systems[disabled_keys[i]]:
			state.weapons_total += 1
			state.weapons_working += 1
			var max_ammo = enemy.get_max_ammo(weapon_slots[i])
			var total_ammo = enemy.get_total_ammo(weapon_slots[i])
			if max_ammo and total_ammo != false:
				if total_ammo > 0:
					any_has_ammo = true
				if max_ammo > 0 and float(total_ammo) / float(max_ammo) < 0.25:
					any_low_ammo = true
			else:
				any_has_ammo = true  # battery/melee = unlimited
		elif node:
			state.weapons_total += 1

	state.low_ammo = any_low_ammo
	state.no_ammo = state.weapons_working > 0 and not any_has_ammo

	# Systems
	state.mobility_damaged = enemy.disabled_systems.mobility < 0.8
	state.sensors_damaged = enemy.disabled_systems.sensors < 0.8

	return state


func _self_state_aggression_mod(state: Dictionary) -> float:
	# Returns a modifier based on the mech's own condition
	var mod := 0.0

	if state.is_overheating:
		mod -= 2.0
	elif state.is_hot:
		mod -= 1.0

	if state.no_ammo:
		mod -= 2.0
	elif state.weapons_working == 0:
		mod -= 3.0
	elif state.low_ammo:
		mod -= 0.5

	if state.mobility_damaged:
		mod -= 0.5

	return mod


func _effective_engage_distance(enemy) -> float:
	return engage_distance * enemy.disabled_systems.sensors


func do_attack(dt, enemy):
	if is_instance_valid(enemy):
		var eff = _get_effective_distances(enemy)
		var state = _get_self_state(enemy)
		if enemy.is_shielding:
			enemy.shield_down()

		# Shooting: check heat, ammo, distance, reaction time
		var can_fire = reaction_timer >= reaction_speed \
			and enemy.global_position.distance_to(enemy.current_target.global_position) < eff.max_shoot \
			and not state.is_hot \
			and not state.no_ammo
		# Low ammo: conserve — only fire at close range
		if state.low_ammo and enemy.global_position.distance_to(enemy.current_target.global_position) > eff.cqb:
			can_fire = false
		if can_fire:
			enemy.shoot_weapons(enemy.current_target)
		else:
			reaction_timer += dt

		var base_aggression = health_diff(enemy) + heat_diff(enemy) + status_diff(enemy)
		var personality_mod = (enemy.personality.aggression - 0.5) * 2.0
		var state_mod = _self_state_aggression_mod(state)
		aggression = base_aggression + personality_mod + state_mod
		enemy.going_to_position = true

		if enemy.can_see_target(enemy.current_target):
			if is_instance_valid(enemy.current_target): point_of_interest = enemy.current_target.global_position
			aiming_at_enemy = true
		else:
			if aiming_at_enemy or not point_of_interest:
				point_of_interest = enemy.get_random_point_on_radius(enemy.current_target.global_position, eff.cqb)
				aiming_at_enemy = false
				reaction_timer = 0.0

		# Don't sprint when hot — sprinting generates heat
		var allow_sprint = not state.is_hot

		if enemy.get_locked_to() and aiming_at_enemy and reaction_timer >= reaction_speed:
			if enemy.global_position.distance_to(enemy.current_target.global_position) < eff.min_kite:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 1.0, 0.65, allow_sprint)
			elif enemy.global_position.distance_to(enemy.current_target.global_position) > eff.max_kite:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 0.0, 0.65, allow_sprint)
			else:
				enemy.decrease_throttle(0, 0.05)
				enemy.navigate_to_target(dt, 1.0, 0.8)
		elif aiming_at_enemy and reaction_timer >= reaction_speed:
			if enemy.global_position.distance_to(enemy.current_target.global_position) > eff.cqb:
				enemy.increase_throttle(1, 0.01)
				enemy.navigate_to_target(dt, 0.0, 0.65, allow_sprint)
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
		var eff = _get_effective_distances(enemy)
		var state = _get_self_state(enemy)
		shield_check(enemy)
		enemy.going_to_position = true
		var base_aggression = health_diff(enemy) + heat_diff(enemy) + status_diff(enemy)
		var personality_mod = (enemy.personality.aggression - 0.5) * 2.0
		var state_mod = _self_state_aggression_mod(state)
		aggression = base_aggression + personality_mod + state_mod
		if is_instance_valid(enemy.current_target): point_of_interest = enemy.current_target.global_position

		# Overheating or out of ammo: retreat harder to create distance
		var retreat_mult = 1.0
		if state.is_overheating or state.no_ammo:
			retreat_mult = 1.5

		if enemy.global_position.distance_to(point_of_interest) < eff.max_kite * retreat_mult:
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

		# Only shoot if not overheating and have ammo
		var can_fire = not state.is_hot and not state.no_ammo
		# Low ammo: conserve — only fire at close range
		if state.low_ammo and enemy.global_position.distance_to(point_of_interest) > eff.cqb:
			can_fire = false

		if can_fire and enemy.global_position.distance_to(point_of_interest) < eff.max_kite:
			if reaction_timer >= reaction_speed:
				enemy.shoot_weapons(enemy.current_target)
			else:
				reaction_timer += dt

func health_diff(enemy):
	if is_instance_valid(enemy) and enemy.current_target:
		if is_instance_valid(enemy.current_target):
			var my_threat = enemy.estimate_threat_level()
			var their_threat = enemy.current_target.estimate_threat_level()
			var diff = my_threat - their_threat  # positive = I'm healthier
			if their_threat <= 0.25:
				return 2  # target is crippled, press the attack
			if diff >= 0.2:
				return 2  # significantly healthier
			elif diff >= 0.0:
				return 1  # slightly healthier
			elif diff >= -0.2:
				return 0  # roughly even
			else:
				return -1  # significantly worse off
		else:
			return 0
	else:
		return 0

func heat_diff(enemy):
	if is_instance_valid(enemy) and enemy.current_target:
		if is_instance_valid(enemy.current_target):
			var heat_pc = enemy.internal_temp/enemy.overheat_temp
			var heat_target_pc = enemy.current_target.internal_temp/enemy.current_target.overheat_temp
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
			if not enemy.is_shielding and enemy.internal_temp < enemy.overheat_temp*general_heat_threshold:
				enemy.shield_up()
		else:
			if enemy.is_shielding:
				enemy.shield_down()
