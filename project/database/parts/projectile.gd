extends Node2D

enum TYPE {INSTANT, REGULAR, COMPLEX}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

signal bullet_impact

@export var type : TYPE
@export var projectile_size := 1.0
@export var projectile_size_scaling := 0.0
@export var projectile_size_scaling_var := 0.0
@export var bullet_drag := 1.0
@export var bullet_drag_var := 0.0
@export var is_overtime := false
@export var decal_type:= "bullet_hole"
@export var texture_variations = []
@export var calibre := CALIBRE_TYPES.SMALL
@export var light_energy:= 0.5
@export var muzzle_speed:= 400
@export var life_time = -1.0 #-1 means it won't disappear
@export var life_time_var = 0.0 #How much to vary from base life_time
@export var random_rotation := false

#---TRAILS AND IMPACTS---#

#---DAMAGE---#

@export var base_damage := 100
@export var health_mult := 1.0
@export var shield_mult := 1.0
@export var dropoff_modifier := 0.8 
@export var heat_damage := 10.0
@export var status_damage := 0.0
@export var status_type : String

#----COMPLEX PROJECTILE BEHAVIOURS----#

#---PROPULSION---#
@export var stages := 1
@export var stage_max_speed :Array[int] = [4000] ##Max Speed: Maximum possible speed the projectile can accelerate to.
@export var stage_min_speed :Array[int] = [0] ##Max Speed: Maximum possible speed the projectile can accelerate to.
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

var args
#weapon_data - reference to the weapon
#projectile - the projectile packed scene
#pos - global position of the bullet at time of firing
#dir - direction of the weapon's aim point
#seeker_target - locked target
var original_mecha_info
var part_id	
var seeker_target
var dying
var lifetime = 0
var speed = 0.0
var max_speed = 0.0
var min_speed = 0.0
var wiggle_amount = 0.0
var wiggle_freq = 0.0
var dir
var acceleration = 0.0

func _process(dt):
	if dying:
		return
	lifetime += dt
	position += dir*speed*dt
	propulsion(dt)

func setup(_mecha, _args, _weapon):
	if random_rotation:
		$Image.rotation_degrees = randf_range(0,360)
	args = _args
	position = args.pos
	dir = args.dir.normalized()
	rotation_degrees = rad_to_deg(dir.angle()) + 90
	seeker_target = args.seeker_target
	speed = muzzle_speed
	
func get_image():
	if texture_variations.is_empty() or randf() > 1.0/float(texture_variations.size() + 1):
		return $Image.texture
	else:
		texture_variations.shuffle()
		return texture_variations.front()

func get_collision():
	return $CollisionShape3D.polygon


func propulsion(dt):
	var cur_stage = get_propulsion_stage()
	if cur_stage > 0:
		acceleration = get_propulsion_var("acceleration", cur_stage)
		max_speed = get_propulsion_var("max_speed", cur_stage)
		min_speed = get_propulsion_var("max_speed", cur_stage)
		wiggle_amount = get_propulsion_var("wiggle_amount", cur_stage)
		wiggle_freq = get_propulsion_var("wiggle_freq", cur_stage)
	
	if speed < max_speed and acceleration > 0.0:
		speed = min(speed + acceleration*dt, max_speed) 
		
	elif speed > min_speed and acceleration < 0.0:
		speed = max(speed + acceleration*dt, min_speed) 

func get_propulsion_stage():
	var cur_stage = 0
	var total_delay = 0
	for idx in stages:
		total_delay += stage_thrust_delay[cur_stage]
		if lifetime < total_delay:
			break
		cur_stage += 1
	return cur_stage

func get_propulsion_var(var_name, stage):
	var var_data = get("stage_"+var_name)
	if var_data.size() >= stage:
		return var_data[stage - 1]
	#Return last position if cur stage doesn't exist
	return var_data.back()

