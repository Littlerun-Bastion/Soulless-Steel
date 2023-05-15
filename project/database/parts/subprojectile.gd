extends Node

@export var projectile : Resource
@export var damage := 10.0
@export var shield_mult := 1.0
@export var health_mult := 1.0
@export var heat_damage := 10.0
@export var status_damage := 0.0
@export var status_type : String
@export var bullet_spread := PI/4 #Relevant for multi-shot
@export var bullet_spread_delay := 0.0 #Relevant for multi-shot
@export var sound_effect := "test"
@export var sound_max_range := 2000
@export var sound_att := 1.00
@export var bullet_velocity := 2000
@export var bullet_drag := 1.0
@export var bullet_drag_var := 0.0
@export var projectile_size := 1.0
@export var projectile_size_scaling := 0.0
@export var projectile_size_scaling_var := 0.0
@export var lifetime := 2.0
@export var impact_force := 0.0
@export var eject_casings := false
@export var casing_size := 1.0


#---BEAM BEHAVIOUR---#
@export var beam_range := 0.0
@export var constant_beam := false
@export var beam_effect : Resource

#---TRAILS AND IMPACTS---
@export var has_trail : PackedScene
@export var trail_lifetime := 1.0
@export var trail_lifetime_range := 0.25
@export var trail_eccentricity := 5.0
@export var trail_min_spawn_distance := 20.0
@export var trail_width := 20

@export var has_smoke : PackedScene
@export var smoke_density := 400
@export var smoke_lifetime := 5.0

@export var impact_effect : PackedScene
@export var impact_size := 1.0
@export var hitstop := false
#---MISSILE/ROCKET BEHAVIOURS---
@export var has_wiggle := false
@export var is_seeker := false
@export var seeker_agility := 0.01
@export var seek_time := 1.0
@export var seeker_angle := 90

#---MELEE BEHAVIOURS---
@export var is_melee := false
@export var melee_knockback := 20

#----COMPLEX PROJECTILE BEHAVIOURS----#

#---PROPULSION---#
@export var stages := 1
@export var stage_max_speed :Array[int] = [4000]
@export var stage_acceleration :Array[float] = [10.0]
@export var stage_thrust_delay :Array[float] = [0.0]
@export var stage_turn_rate :Array[float] = [0.0]
@export var stage_wiggle_amount :Array[float] = [0.0]
@export var stage_wiggle_freq :Array[float] = [0.0]
@export var stage_seeker_type :Array[String] = ["IR"]
@export var stage_seeker_delay :Array[float] = [0.0]
@export var stage_seeker_angle :Array[float] = [0.0]

#---FUSE---#
@export var fuse_arm_time := 0.0
@export var fuse_timer := 3.0
@export var fuse_proximity_distance := 0
@export var fuse_detection_type : String
@export var fuse_angle := 360.0
@export var fuse_is_contact_enabled := true

#---PAYLOAD---#
@export var payload_explosion : Resource
@export var payload_explosion_damage := 0.0
@export var payload_explosion_force := 0.0
@export var payload_explosion_radius := 0.0
@export var payload_subprojectile : Resource


var firing_timer = 0.0
var part_id

func get_stat(stat_name):
	var stat
	if stat_name == "armor_damage":
		stat = 100 * damage * health_mult
	elif stat_name == "shield_damage":
		stat = 100 * damage * shield_mult
	else:
		stat = get(stat_name)
	return stat

	


