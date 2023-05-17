extends Node

@export var part_name : String
@export var manufacturer_name : String
@export var tagline : String
@export var price := 0.0
@export var description : String
@export var type: String
@export var image : Texture2D
@export var muzzle_flash : PackedScene
@export var muzzle_flash_size := 1.0
@export var muzzle_flash_speed := 1.0
@export var rotation_acc := 5
@export var rotation_range := 10.0
@export var projectile : Resource
@export var projectile_type : String
@export var parallax_offset := 0.0
@export var number_projectiles := 1
@export var burst_ammo_cost := 1
@export var damage := 10.0
@export var requires_lock := false
@export var uses_battery := false
@export var shield_mult := 1.0
@export var health_mult := 1.0
@export var heat_damage := 10.0
@export var status_damage := 0.0
@export var status_type : String
@export var recoil_force := 0.0
@export var bloom_reset_time := 1.0
@export var fire_rate := .3
@export var burst_size := 1
@export var burst_fire_rate := 0.0
@export var auto_fire := true
@export var base_accuracy := 0.0
@export var accuracy_bloom := 0.0
@export var max_bloom_angle := 2.5
@export var bullet_spread := PI/4 #Relevant for multi-shot
@export var bullet_spread_delay := 0.0 #Relevant for multi-shot
@export var total_ammo := 270
@export var max_ammo := 270
@export var clip_size := 30
@export var reload_speed := 3.0
@export var muzzle_heat := 3.8
@export var ammo_cost := 10 #the monetary cost of the ammunition, not the ammo used when firing.
@export var sound_effect := "test"
@export var sound_max_range := 2000
@export var sound_att := 1.00
@export var battery_drain := 1.00
@export var weight := 1.0
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
@export var stage_max_speed :Array[int] = [4000] ##Max Speed: Maximum possible speed the projectile can accelerate to.
@export var stage_acceleration :Array[float] = [10.0] ##Acceleration: Amount speed is increased by per second.
@export var stage_thrust_delay :Array[float] = [0.0] ##Thrust Delay: Number of seconds before Acceleration is applied.
@export var stage_turn_rate :Array[float] = [0.0] ##Turn Rate: Number of degrees per second a projectile can turn by if it is tracking a target.
@export var stage_wiggle_amount :Array[float] = [0.0] ##Wiggle Amount: Maximum number of degrees a projectile can turn off its course.
@export var stage_wiggle_freq :Array[float] = [0.0] ##Wiggle Freq: Number of wiggles per second (based on cosine).
@export var stage_seeker_type :Array[String] = ["IR"] ##Seeker Type: Detection method the projectile will use to see if it is allowed to track a target./
	## (IR: based on mecha_heat, RCS: based on mecha rcs (not implemented), Laser: based on the endpoint of a raycast from player's mech to the direction of the target (not implemented))
@export var stage_seeker_delay :Array[float] = [0.0] ##Seeker Delay: Time in seconds before the stage of that seeker kicks in.
@export var stage_seeker_angle :Array[float] = [0.0] ##Seeker Angle: Angle beyond which the seeker will not chase the target.

#---FUSE---#
@export var fuse_arm_time := 0.0 ##Time in seconds before the projectile can impact an object or deploy its 'payload'
@export var fuse_timer := 3.0 ##Time in seconds (after fuse arm time) until the projectile deploys its 'payload'
@export var fuse_proximity_distance := 0 ##Distance at which the projectile detects an enemy.
@export var fuse_detection_type : String ##Detection method the projectile uses to see if it is allowed to deploy its 'payload'.
@export var fuse_angle := 360.0 ##Angle beyond which the projectile no longer detects enemies to trigger the fuse.
@export var fuse_is_contact_enabled := true ##Whether or not the projectile can directly hit a mecha. If false, projectile will fly past a mecha.

#---PAYLOAD---#
@export var payload_explosion : Resource ##Visual effect for the explosion.
@export var payload_explosion_damage := 0.0 ##Total damage of the explosion.
@export var payload_explosion_shield_mult := 1.0 ##Shield damage multiplier of explosion.
@export var payload_explosion_health_mult := 1.0 ##Health damage multiplier of explosion.
@export var payload_explosion_heat_damage := 0.0 ##Heat damage of explosion.
@export var payload_explosion_status_damage := 0.0 ##Amount of status explosion inflicts.
@export var payload_explosion_status_type : String ##Explosion status type.
@export var payload_explosion_force := 0.0 ##Amount of knockback explosion performs against a target.
@export var payload_explosion_radius := 0.0 ##Distance from impact center an explosion hits a target.
@export var payload_explosion_angle := 360.0 ##Angle from center an explosion hits.
@export var payload_explosion_hitstop := false ##Hitstop of explosion in seconds.
@export var payload_subprojectile : PackedScene ##What subprojectile the payload spawns.
@export var payload_subprojectile_count := 0.0 ##How many subprojectiles the payload spawns.
@export var payload_subprojectile_spread := 0.0 #In degrees

var cur_stage = 0
var firing_timer = 0.0
var part_id


func get_sub():
	return $Sub.texture


func get_image():
	return $Main.texture


func get_glow():
	return $Glow.texture


func get_num_shooting_pos():
	return $ShootingPosArray.get_children().size()


func get_shooting_pos(idx):
	assert($ShootingPosArray.get_child_count() >= idx + 1,"Not a valid shooting pos index: " + str(idx))
	return $ShootingPosArray.get_child(idx)


func get_attach_pos():
	return $AttachPos.position


func get_attack_animation():
	return $AttackAnimation.duplicate()


func get_stat(stat_name):
	var stat
	if stat_name == "armor_damage":
		stat = 100 * damage * health_mult
	elif stat_name == "shield_damage":
		stat = 100 * damage * shield_mult
	else:
		stat = get(stat_name)
	return stat

	


