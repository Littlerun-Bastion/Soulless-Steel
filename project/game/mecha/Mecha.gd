extends CharacterBody2D
class_name Mecha

# hi this edit comes from my tablet!

enum MODES {NEUTRAL, RELOAD, ACTIVATING_LOCK, LOCK}
enum SIDE {LEFT, RIGHT, SINGLE}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

const DECAL = preload("res://game/mecha/Decal.tscn")
const HITBOX = preload("res://game/mecha/Hitbox.tscn")
const PART_DESTRUCTION_EXPLOSION = preload("res://game/weapons/PartDestructionExplosion.tscn")
const ARM_WEAPON_INITIAL_ROT =  9
const SPEED_MOD_CORRECTION = 8
const WEAPON_RECOIL_MOD = .9
const CHASSIS_SPEED = 20
const SPRINTING_COOLDOWN_SPEED = 2
const SPRINTING_ACC_MOD = 0.2
const ENTERING_BUILDING_SPEED_MOD = .96
const FREEZING_SPEED_MOD = .95
const OVERWEIGHT_SPEED_MOD = 4
const LOCKON_RETICLE_SIZE = 15
const DASH_DECAY = 4
const FIRE_DAMAGE = 10.0 #TODO convert to kJ in new heat system
const HITSTOP_TIMESCALE = 0.1
const HITSTOP_DURATION = 0.25
const AI_TURN_DEADZONE = 5
const EXPOSED_INVULN_WINDOW = 1
const SHIELD_PARTICLE_AMOUNT = 5
const SHIELD_PARRY_TIME = 0.15
const SPOOLING_DISTANCE_ATT = .6 #How much to reduce max distance sfx of base weapon
const PASSIVE_SOUNDS_INTERVAL = .8 #How frequently to generate passive sounds
const THROTTLE_STEP = 0.1
const WHEELS_SPEED_FACTOR = 0.6 #Made to balance wheels with legs since they aren't equal speed due to the animation
const AMBIENT_TEMP := -10.0 
const HEAT_TRANSFER := 0.3
const OVERHEAT_DAMAGE_TEMP := 200.0  # °C above ambient on external layer
const OVERHEAT_DAMAGE_INTERVAL := 3.0 

signal create_projectile
signal create_casing
signal shoot_signal
signal took_damage
signal died
signal exposed
signal mecha_extracted
signal shield_ready
signal parried
signal made_sound
signal component_damaged(part_name: String, component_name: String, hp: int, max_hp: int)
signal component_destroyed_alert(part_name: String, component_name: String)
signal cockpit_exposed(hp: int)
signal core_shell_destroyed()
signal system_degraded(system_name: String, severity: float)  # For mobility, sensors, etc.
signal flagged()


@export var speed_modifier = 1.0
@export var display_mode = false

@onready var NavAgent = $NavigationAgent2D

@onready var CoreDecals = $CoreDecals
@onready var LeftShoulderDecals = $LeftShoulder/Decals
@onready var RightShoulderDecals = $RightShoulder/Decals
@onready var MovementAnimation = $MovementAnimation
@onready var LockCollision = $LockCollision

#Main Parts
@onready var Core = $Core
@onready var CoreSub = $Core/Sub
@onready var CoreGlow = $Core/Glow
@onready var Head = $Head
@onready var HeadSub = $Head/Sub
@onready var HeadGlow = $Head/Glow
@onready var HeadPort = $HeadPort
@onready var LeftShoulder = $LeftShoulder
@onready var RightShoulder = $RightShoulder
#Weapons
@onready var LeftArmWeapon = $ArmWeaponLeft
@onready var LeftArmWeaponMain = $ArmWeaponLeft/Main
@onready var LeftArmWeaponSub = $ArmWeaponLeft/Sub
@onready var LeftArmWeaponGlow = $ArmWeaponLeft/Glow
@onready var LeftArmWeaponHitboxes = $ArmWeaponLeft/MeleeHitboxes
@onready var RightArmWeapon = $ArmWeaponRight
@onready var RightArmWeaponMain = $ArmWeaponRight/Main
@onready var RightArmWeaponSub = $ArmWeaponRight/Sub
@onready var RightArmWeaponGlow = $ArmWeaponRight/Glow
@onready var RightArmWeaponHitboxes = $ArmWeaponRight/MeleeHitboxes
@onready var LeftShoulderWeapon = $ShoulderWeaponLeft
@onready var LeftShoulderWeaponMain = $ShoulderWeaponLeft/Main
@onready var LeftShoulderWeaponSub = $ShoulderWeaponLeft/Sub
@onready var LeftShoulderWeaponGlow = $ShoulderWeaponLeft/Glow
@onready var RightShoulderWeapon = $ShoulderWeaponRight
@onready var RightShoulderWeaponMain = $ShoulderWeaponRight/Main
@onready var RightShoulderWeaponSub = $ShoulderWeaponRight/Sub
@onready var RightShoulderWeaponGlow = $ShoulderWeaponRight/Glow
#Chassis
@onready var SingleChassisRoot = $Chassis/Single
@onready var SingleChassis = $Chassis/Single/Main
@onready var SingleChassisSub = $Chassis/Single/Sub
@onready var SingleChassisGlow = $Chassis/Single/Glow
@onready var LeftChassisRoot = $Chassis/Left
@onready var LeftChassis = $Chassis/Left/Main
@onready var LeftChassisSub = $Chassis/Left/Sub
@onready var LeftChassisGlow = $Chassis/Left/Glow
@onready var RightChassisRoot = $Chassis/Right
@onready var RightChassis = $Chassis/Right/Main
@onready var RightChassisSub = $Chassis/Right/Sub
@onready var RightChassisGlow = $Chassis/Right/Glow
@onready var ChassisSprintGlow = $Chassis/SprintGlow

@onready var mech_inventory: Inventory
var target_inventory: Inventory = null
#Particles
@onready var Particle = {
	"blood": [$ParticlesLayer1/Blood1, $ParticlesLayer1/Blood2, $ParticlesLayer1/Blood3],
	"fire": [$ParticlesLayer3/Fire1, $ParticlesLayer3/Fire2],
	"corrosion": [$ParticlesLayer1/Corrosion1, $ParticlesLayer3/Corrosion2],
	"electrified": [$ParticlesLayer3/Electrified],
	"freezing": [$ParticlesLayer3/Freezing1, $ParticlesLayer3/Freezing2],
	"overheating": [$ParticlesLayer3/Overheating1, $ParticlesLayer3/Overheating2,\
					$ParticlesLayer3/Overheating3, $ParticlesLayer3/Overheating4,\
					$ParticlesLayer3/Overheating5, $ParticlesLayer3/OverheatingSparks],
	"grind": [$ParticlesLayer1/Grind1, $ParticlesLayer1/Grind2],
	"dash": {
		"fwd": {
			"cooldown": $ParticlesLayer2/DashCooldownFwd,
			"ready": $ParticlesLayer2/DashReadyFwd,
		},
		"rwd": {
			"cooldown": $ParticlesLayer2/DashCooldownRwd,
			"ready": $ParticlesLayer2/DashReadyRwd,
		},
		"left": {
			"cooldown": $ParticlesLayer2/DashCooldownLeft,
			"ready": $ParticlesLayer2/DashReadyLeft,
		},
		"right": {
			"cooldown": $ParticlesLayer2/DashCooldownRight,
			"ready": $ParticlesLayer2/DashReadyRight,
		},
	},
	"chassis_dash": [$Chassis/DashThrust1, $Chassis/DashThrust2, $Chassis/DashThrust3],
	"chassis_hover": [$Chassis/HoverParticles1, $Chassis/HoverParticles2],
	"chassis_sprint": [$Chassis/SprintThrust1, $Chassis/SprintThrust2],
}
#SFXs
@onready var ChassisAmbientSFX = $SFXs/ChassisAmbient
@onready var GeneratorAmbientSFX = $SFXs/GeneratorAmbient
@onready var WeaponSFXs = {
	"arm_weapon_left": {
		"shoot_loop": $SFXs/LeftArmWeapon/ShootLoop,
		"spool_up": $SFXs/LeftArmWeapon/SpoolUp,
		"spool_down": $SFXs/LeftArmWeapon/SpoolDown,
	},
	"arm_weapon_right": {
		"shoot_loop": $SFXs/RightArmWeapon/ShootLoop,
		"spool_up": $SFXs/RightArmWeapon/SpoolUp,
		"spool_down": $SFXs/RightArmWeapon/SpoolDown,
	},

	"shoulder_weapon_left": {
		"shoot_loop": $SFXs/LeftShoulderWeapon/ShootLoop,
		"spool_up": $SFXs/LeftShoulderWeapon/SpoolUp,
		"spool_down": $SFXs/LeftShoulderWeapon/SpoolDown,
	},
	"shoulder_weapon_right": {
		"shoot_loop": $SFXs/RightShoulderWeapon/ShootLoop,
		"spool_up": $SFXs/RightShoulderWeapon/SpoolUp,
		"spool_down": $SFXs/RightShoulderWeapon/SpoolDown,
	},
}
#Misc
@onready var VisibilityNode = $VisibleOnScreenNotifier2D

var mecha_name = "Mecha Name"
var paused = false
var controls_locked = false
var is_dead = false
var cur_mode = MODES.NEUTRAL
var arena = false
var is_inside_building = false
var is_entering_building = false
var is_exposed = false
var passive_sounds_timer = 0.0
var throttle :float = 1.0

var max_hp = 10
var hp = 10
var max_shield = 10
var shield = 10
var shield_regen_cooldown = 5
var shield_project_cooldown = 0.5
var shield_project_heat
var max_energy = 100
var energy = 100
var total_kills = 0
var shader_heat_value = 0
var battery = 0.0
var battery_capacity = 0.0
var battery_recharge_rate = 0.0
var ecm = 0.0
var ecm_frequency = 0.0
var lock_strength = 1.0
var weight = 0.0
var exposed_hits = 3.0
var exposed_invuln_timer = 0.0
var spooling = {
	"arm_weapon_left": false,
	"arm_weapon_right": false,
	"shoulder_weapon_left": false,
	"shoulder_weapon_right": false,
}

var weight_capacity = 100.0

var movement_type = "free"
var tank_move_target = Vector2(1,0)
var tank_lookat_target = Vector2()
var is_sprinting = false
var sprinting_ending_correction = Vector2()
var dash_velocity = Vector2()
var impact_velocity = Vector2()
var impact_rotation_velocity = 0.0
var dash_strength = 2000
var moving = false
var moving_axis = {
	"x": false,
	"y": false,
}
var max_speed = 500
var friction = 0.01
var move_acc = 50
var rotation_acc = 5
var arm_accuracy_mod := 0.0
var stability := 1.0
var cur_rotation_speed = 0

var last_damage_source
var last_damage_weapon
var processed_hitboxes = []
var lingering_hitboxes = []


var right_arm_bloom_time := 0.0
var right_arm_bloom_count = 0
var left_arm_bloom_time := 0.0
var left_arm_bloom_count = 0
var right_shoulder_bloom_time := 0.0
var right_shoulder_bloom_count = 0
var left_shoulder_bloom_time := 0.0
var left_shoulder_bloom_count = 0

var locking_targets = []
var locking_to = false
var locked_to = false
var lock_on_duration = 0.0
var lock_timer = 0.0

var is_shielding = false
var is_parrying = false
var shield_project_cooldown_timer = 0.0
var shield_parry_timer = 0.0

var internal_temp := 0.0        # °C above ambient (so 0.0 = at ambient)
var external_temp := 0.0        # °C above ambient
var internal_capacity := 40.0   # kJ/°C, derived from core coolant in set_core()
var overheat_temp := 100.0      # °C above ambient, from CoolantType
var external_capacity := 50.0   # kJ/°C, from generator
var pending_heat_kj := 0.0     	# kJ waiting to enter the thermal system
var overheat_damage_timer := 0.0

var build = {
	"arm_weapon_left": null,
	"arm_weapon_right": null,
	"shoulder_weapon_left": null,
	"shoulder_weapon_right": null,
	"shoulders": null,
	"head": null,
	"core": null,
	"generator": null,
	"chipset": null,
	"thruster": null,
	"chassis": null,
}

var projectiles = []

var status_time = {
	"fire": 0.0,
	"electrified": 0.0,
	"freezing": 0.0,
	"corrosion": 0.0,
	"overheating": 0.0,
}
var dash_cooldown = {
	"fwd": 0.0,
	"rwd": 0.0,
	"left": 0.0,
	"right": 0.0,
}

var armor = {
	"core": {
		"front": {"level": 3, "pips": 3},
		"side": {"level": 2, "pips": 3},
		"rear": {"level": 1, "pips": 3}
	},
	"head": {
		"front": {"level": 2, "pips": 3},
		"side": {"level": 1, "pips": 3},
		"rear": {"level": 1, "pips": 3}
	},
	"chassis": {
		"front": {"level": 2, "pips": 3},
		"side": {"level": 2, "pips": 3},
		"rear": {"level": 1, "pips": 3}
	},
	"left_shoulder": {
		"front": {"level": 2, "pips": 3},
		"side": {"level": 1, "pips": 3},
		"rear": {"level": 1, "pips": 3}
	},
	"right_shoulder": {
		"front": {"level": 2, "pips": 3},
		"side": {"level": 1, "pips": 3},
		"rear": {"level": 1, "pips": 3}
	},
}

var components = {
	"core": {},
	"head": {},
	"chassis": {},
	"left_shoulder": {},
	"right_shoulder": {},
}

# Track which systems are affected by destroyed components
var disabled_systems = {
	"left_arm_weapon": false,
	"right_arm_weapon": false,
	"left_shoulder_weapon": false,
	"right_shoulder_weapon": false,
	"mobility": 1.0,  # Multiplier, 1.0 = full, 0.0 = immobile
	"sensors": 1.0,   # Affects lock-on and radar
	"heat_dispersion": 1.0,  # Multiplier for generator heat dispersion
	"shield_regen": 1.0,
}

var thruster_cooldown = 0.0

var ecm_attempt_cooldown = 0.0
var ecm_strength_difference = 0.0

var bleed_timer = 0.0

func _ready():
	for node in [Core, Head, HeadPort,\
				LeftShoulder, RightShoulder,\
				LeftArmWeaponMain, RightArmWeaponMain,\
				LeftShoulderWeaponMain, RightShoulderWeaponMain,\
				SingleChassis, LeftChassis, RightChassis]:
		node.material = Core.material.duplicate(true)
	for node in [CoreSub, HeadSub,\
				LeftArmWeaponSub, RightArmWeaponSub,\
				LeftShoulderWeaponSub, RightShoulderWeaponSub,\
				SingleChassisSub, LeftChassisSub, RightChassisSub]:
		node.material = CoreSub.material.duplicate(true)
	for node in [CoreGlow, HeadGlow,\
				LeftArmWeaponGlow, RightArmWeaponGlow,\
				LeftShoulderWeaponGlow, RightShoulderWeaponGlow,\
				SingleChassisGlow, LeftChassisGlow, RightChassisGlow]:
		node.material = CoreGlow.material.duplicate(true)
	global_rotation_degrees = randf_range(0, 360)
	
	if mech_inventory == null:
		mech_inventory = Inventory.new()

func _physics_process(dt):
	if paused:
		return
	
	generate_passive_sounds(dt)
	
	if is_stunned():
		return
	
	tank_lookat_target = global_position + tank_move_target
	if movement_type == "tank":
		$Chassis.look_at(tank_lookat_target)

	if impact_velocity.length() > 0:
		move(impact_velocity)
		if impact_velocity.x > 0:
			impact_velocity.x = max(impact_velocity.x * (1 - DASH_DECAY*dt), 0)
		else:
			impact_velocity.x = min(impact_velocity.x * (1 - DASH_DECAY*dt), 0)

		if impact_velocity.y > 0:
			impact_velocity.y = max(impact_velocity.y * (1 - DASH_DECAY*dt), 0)
		else:
			impact_velocity.y = min(impact_velocity.y * (1 - DASH_DECAY*dt), 0)
			if impact_velocity.length() < 1:
				impact_velocity = Vector2()

	if abs(impact_rotation_velocity) > 0:
		global_rotation += impact_rotation_velocity * dt
		impact_rotation_velocity *= min(0.95, 3*dt)
		if abs(impact_rotation_velocity) < 0.001:
			impact_rotation_velocity = 0

	if is_dead:
		return

	#Blood
	if hp/float(max_hp) < 0.66:
		bleed_timer = max(bleed_timer - dt, 0.0)
		if bleed_timer <= 0.0:
			bleed_timer = randf_range(1, 1.1*max_hp/hp)
			Particle.blood[0].emitting = !Particle.blood[0].emitting
			if hp/float(max_hp) < 0.33:
				Particle.blood[1].emitting = !Particle.blood[1].emitting
			else:
				Particle.blood[1].emitting = false
	
	if is_exposed:
		exposed_invuln_timer = min(exposed_invuln_timer + dt, EXPOSED_INVULN_WINDOW)

	#ECM
	ecm_attempt_cooldown = max(ecm_attempt_cooldown - dt, 0.0)
	
	#SHIELDS
	if shield_project_cooldown_timer <= 0.0:
		emit_signal("shield_ready")
	else:
		shield_project_cooldown_timer = max(shield_project_cooldown_timer - dt, 0.0)
	
	if shield_parry_timer <= 0.0:
		is_parrying = false
	else:
		shield_parry_timer = max(shield_parry_timer - dt, 0.0)
	
	if is_shielding:
		increase_heat(shield_project_heat*dt)
		if shield <= 0.0:
			shield_down()

	#Bloom
	for part in ["right_arm", "left_arm", "right_shoulder", "left_shoulder"]:
		if get(part+"_bloom_time") > 0:
			set(part+"_bloom_time", max(get(part+"_bloom_time") - dt, 0))
		else:
			set(part+"_bloom_count", 0)

	#Handle shield
	if build.generator and shield < max_shield:
		if not is_shielding:
			shield_regen_cooldown = max(shield_regen_cooldown - dt, 0.0)
		else:
			shield_regen_cooldown = build.generator.shield_regen_delay
		if shield_regen_cooldown <= 0 and not has_status("electrified"):
			shield = min(shield + build.generator.shield_regen_speed*dt, max_shield)
			shield = round(shield)
			emit_signal("took_damage", self, true)
	$ParticlesLayer3/ShieldRing.amount = max(1, int(ceil(SHIELD_PARTICLE_AMOUNT * (shield/max_shield))))
	$ParticlesLayer3/ShieldStartup.amount = max(1, int(ceil(SHIELD_PARTICLE_AMOUNT * (shield/max_shield))))

	#Handle sprinting momentum
	sprinting_ending_correction *= 1.0 - min(SPRINTING_COOLDOWN_SPEED*dt, 1.0)

	#Handle collisions with other mechas and movement
	if not is_stunned() and not is_movement_locked():
		var all_collisions = []
		for i in get_slide_collision_count():
			all_collisions.append(get_slide_collision(i))

		for collision in all_collisions:
			if collision and collision.get_collider().is_in_group("mecha"):
				lock_movement(0.1)
				break
	else:
		if sprinting_ending_correction.length():
			move(sprinting_ending_correction)
		else:
			apply_movement(dt, Vector2())

	#Update shoulder weapons rotation
	for data in [[build.shoulder_weapon_left, LeftShoulderWeapon], [build.shoulder_weapon_right, RightShoulderWeapon]]:
		if data[0]:
			data[1].rotation_degrees += get_best_rotation_diff(data[1].rotation_degrees, 0)*data[0].rotation_acc*dt

	#Handle dash movement
	if not is_stunned() and dash_velocity.length() > 0:
		speed_modifier = 1.0
		move(dash_velocity)
		if dash_velocity.x > 0:
			dash_velocity.x = max(dash_velocity.x * (1 - DASH_DECAY*dt), 0)
		else:
			dash_velocity.x = min(dash_velocity.x * (1 - DASH_DECAY*dt), 0)

		if dash_velocity.y > 0:
			dash_velocity.y = max(dash_velocity.y * (1 - DASH_DECAY*dt), 0)
		else:
			dash_velocity.y = min(dash_velocity.y * (1 - DASH_DECAY*dt), 0)
		if dash_velocity.length() < 1:
			dash_velocity = Vector2()

	#Walking animation
	if build.chassis and build.chassis.is_legs:
		if moving and not MovementAnimation.is_playing() and\
		not is_sprinting and dash_velocity.length() <= 0.0:
			MovementAnimation.play("Walking")
		elif (not moving and velocity.length() <= 2.0) or\
		(is_sprinting or dash_velocity.length() > 0):
			MovementAnimation.stop()
		if not MovementAnimation.is_playing():
			speed_modifier = min(speed_modifier + SPEED_MOD_CORRECTION*dt, 1.0)
			
	# --- Movement Heat ---
	if build.thruster and moving and not is_dead:
		if is_sprinting and not has_status("freezing"):
			increase_heat(build.thruster.sprinting_heat * dt)

	#Locking mechanic
	if is_player():
		update_locking(dt)
	if get_locked_to():
		var target_pos = locked_to.global_position
		apply_rotation_by_point(dt, target_pos, false)

	#Status Effects
	update_heat(dt)
	if battery < battery_capacity and not has_status("electrified"):
		battery = min(battery + battery_recharge_rate*dt, battery_capacity)
	for status in status_time.keys():
		if status == "overheating":
			continue  # Managed by thermal system, not timer
		decrease_status(status, dt)
	for status in ["fire", "electrified", "freezing", "corrosion", "overheating"]:
		for node in Particle[status]:
			node.emitting =  has_status(status)
	if has_status("fire"):
		$FireGlow.energy = min($FireGlow.energy + dt*2, 3)
	else:
		$FireGlow.energy = max($FireGlow.energy - dt*2, 0)


	#Thrusters cooldowns
	for dir in ["fwd", "rwd", "left", "right"]:
		var is_ready = dash_cooldown[dir] <= 0
		dash_cooldown[dir] = max(dash_cooldown[dir] - dt, 0.0)
		Particle.dash[dir].cooldown.emitting = dash_cooldown[dir] > 0
		if dash_cooldown[dir] <= 0 and not is_ready:
			Particle.dash[dir].ready.emitting = true
	update_dash_cooldown_visuals()

	take_status_damage(dt)
	
	process_hitboxes(dt)
	
	if build.chassis and build.chassis.hover_particles and not display_mode:
		Particle.chassis_hover[0].speed_scale = max(0.2,velocity.length()/100)
		Particle.chassis_hover[0].modulate = Color(1.0, 1.0, 1.0,max(0.05,velocity.length()/1000))
	
	#Lock-on Updating
	if get_locked_to():
		if lock_timer >= lock_on_duration:
			locked_to = false
			lock_timer = 0.0
		else:
			lock_timer += dt


func is_player():
	return mecha_name == "Player"


func set_pause(value):
	paused = value


func get_design_data():
	var data = {}
	for part_type in build.keys():
		var part = build[part_type]
		data[part_type] = part.part_id if part else false
	return data


func set_parts_from_design(data):
	for part_name in ["head", "core", "shoulders", "generator", "chipset", "chassis",\
					"thruster", "arm_weapon_left", "arm_weapon_right", "shoulders", \
					"shoulder_weapon_left", "shoulder_weapon_right",]:
		var type = part_name.replace("_left", "").replace("_right", "")
		var side = false
		if part_name.find("left") != -1:
			side = SIDE.LEFT
		elif part_name.find("right") != -1:
			side = SIDE.RIGHT

		if typeof(side) == TYPE_INT:
			callv("set_" + type, [data[part_name], side])
		else:
			callv("set_" + type, [data[part_name]])
	
	refresh_dynamic_components()
	debug_print_components()

func generate_passive_sounds(dt):
	passive_sounds_timer = max(passive_sounds_timer - dt, 0.0)
	if passive_sounds_timer <= 0.0:
		passive_sounds_timer = PASSIVE_SOUNDS_INTERVAL
		if build.chassis:
			create_sound("quiet", "chassis", build.chassis.ambient_sfx_max_distance)
		for weapon_type in WeaponSFXs.keys():
			var sfx_node = WeaponSFXs[weapon_type]
			if sfx_node.shoot_loop.is_playing():
				create_sound("loud", "shooting", sfx_node.shoot_loop.max_distance)
			


func update_speed(_max_speed, _move_acc, _friction, _rotation_acc):
	max_speed = _max_speed
	friction = _friction
	rotation_acc = _rotation_acc
	move_acc = _move_acc
	MovementAnimation.speed_scale = move_acc
	if build.chassis and build.chassis.is_legs:
		move_acc *= 50
	var animation = MovementAnimation.get_animation("Walking")
	var track = 0 #animation.find_track("Mecha:speed_modifier")
	animation.track_set_key_value(track, 2, move_acc/100.0)
	animation.track_set_key_value(track, 5, move_acc/100.0)


func update_max_life_from_parts():
	var value = 0
	if build.core:
		value += build.core.health
	if build.head:
		value += build.head.health
	if build.chassis:
		value += build.chassis.health
	set_max_life(value)


func update_max_shield_from_parts():
	var value = 0
	if build.core:
		value += build.core.shield
	if build.generator:
		value += build.generator.shield
	#Check shoulders
	if build.shoulders:
		value += build.shoulders.shield

	set_max_shield(value)


func is_overweight():
	weight_capacity = get_stat("weight_capacity")
	weight = get_total_weight()
	return weight > weight_capacity


func set_max_life(value):
	max_hp = value
	hp = max_hp


func set_max_shield(value):
	max_shield = value
	shield = max_shield


func set_max_energy(value):
	max_energy = value
	energy = max_energy


func take_damage(amount, shield_mult, health_mult, heat_damage, status_amount, status_type, hitstop, source_info, weapon_name := "Test"):
	if is_dead:
		return

	if hitstop:
		if source_info.name == "Player" or self.name == "Player":
			do_hitstop()
	
	if is_parrying:
		emit_signal("parried")
		do_hitstop()
		return

	if is_shielding:
		var temp_shield = shield
		shield = round(max(shield - (shield_mult * amount), 0))
		amount = max(amount - temp_shield, 0)
		hp = round(max(hp - (health_mult * amount), 0))
	else:
		hp = round(max(hp - (health_mult * amount), 0))
		increase_heat(heat_damage)
		if status_type and status_amount > 0.0:
			set_status(status_type, status_amount)
		if amount > max_hp/0.25:
			Particle.blood[2].emitting = true

	emit_signal("took_damage", self, false)

	last_damage_source = source_info
	last_damage_weapon = weapon_name

	if hp <= 0 and not is_exposed:
		is_exposed = true
		emit_signal("exposed",self)
	elif hp <= 0 and is_exposed:
		if exposed_invuln_timer == EXPOSED_INVULN_WINDOW:
			exposed_hits -= 1
			exposed_invuln_timer = 0.0
			if exposed_hits <= 0:
				AudioManager.play_sfx("final_explosion", global_position, null, null, 1.25, 10000)
				create_sound("loud", "explosion", 10000)
				die(source_info, weapon_name)


func do_hitstop():
	if VisibilityNode.is_on_screen():
		Engine.time_scale = HITSTOP_TIMESCALE
		await get_tree().create_timer(HITSTOP_DURATION * HITSTOP_TIMESCALE).timeout
		Engine.time_scale = 1.0


func has_status(status_name):
	assert(status_time.has(status_name),"Not a valid status name: " + str(status_name))
	return status_time[status_name] > 0.0


func has_any_status():
	for status in status_time.values():
		if status > 0.0:
			return true
	return false


func set_status(status_name, amount):
	assert(status_time.has(status_name),"Not a valid status name: " + str(status_name))
	status_time[status_name] = amount


func decrease_status(status_name, amount):
	assert(status_time.has(status_name),"Not a valid status name: " + str(status_name))
	status_time[status_name] = max(status_time[status_name] - amount, 0.0)


func take_status_damage(dt):
	if is_dead:
		return

	if has_status("overheating"):
		overheat_damage_timer -= dt
		if overheat_damage_timer <= 0.0:
			overheat_damage_timer = OVERHEAT_DAMAGE_INTERVAL
			overheat_damage_tick()
			var heat_severity = clamp((external_temp - OVERHEAT_DAMAGE_TEMP) / 100.0, 0.0, 1.0)
			overheat_damage_timer = lerp(OVERHEAT_DAMAGE_INTERVAL, 1.0, heat_severity)
	else:
		overheat_damage_timer = 0.0

	if has_status("fire"):
		increase_heat(FIRE_DAMAGE*dt)

	if has_status("electrified"):
		shield = round(max(shield - (dt * 100), 0))
		emit_signal("took_damage", self, true)
		if build.generator:
			shield_regen_cooldown = build.generator.shield_regen_delay

	if has_status("corrosion"):
		if hp <= 0:
			is_exposed = true
		else:
			hp = round(max(hp - (dt * (hp/100)), 1))
		emit_signal("took_damage", self, true)

func overheat_damage_tick():
	# Gather all living components across all parts
	var candidates = []
	for part_name in components.keys():
		for comp_name in components[part_name]:
			var comp = components[part_name][comp_name]
			if not comp.disabled and comp.hp > 0:
				if comp_name == "cockpit" and disabled_systems.heat_dispersion >= 1.0:
					comp_name = "radiator" #Targets the radiator instead of the cockpit while we still have heat dispersion up
				candidates.append({
					"part": part_name,
					"comp": comp_name,
					"weight": comp.weight
				})
	
	if candidates.is_empty():
		return
	
	# Weighted random selection across the entire mech
	var total_weight = 0.0
	for c in candidates:
		total_weight += c.weight
	
	var roll = randf() * total_weight
	var running = 0.0
	for c in candidates:
		running += c.weight
		if roll <= running:
			damage_component(c.part, c.comp, 1)
			print("OVERHEAT damaged: ", c.comp, " on ", c.part)
			return

func apply_movement_modifiers(speed):
	if is_overweight():
		var total_weight = get_total_weight()
		if weight_capacity > 0.0:
			speed /= (total_weight / weight_capacity) * OVERWEIGHT_SPEED_MOD
	if has_status("freezing"):
		speed *= FREEZING_SPEED_MOD
	if is_entering_building:
		speed *= ENTERING_BUILDING_SPEED_MOD
	return speed

func die(_source_info, _weapon_name):
	if is_dead:
		return
	is_dead = true
	
	#Update sfxs
	if ChassisAmbientSFX.stream:
		ChassisAmbientSFX.stop()
	if GeneratorAmbientSFX.stream:
		GeneratorAmbientSFX.stop()
	
	await get_tree().create_timer(3.0).timeout
	#TickerManager.new_message({
	#	"type": "mecha_died",
	#	"source": source_info.name,
	#	"self": self.mecha_name,
	#	"weapon_name": weapon_name,
	#	})
	emit_signal("died", self)


#Return all parts that should be generated when mecha dies
func get_scrapable_parts():
	var scraps = []
	for node in [LeftShoulder, RightShoulder, Core, LeftChassis, RightChassis]:
		if node.texture:
			scraps.append(node)
	return scraps


func is_shape_id_chassis(id):
	return shape_owner_get_owner(shape_find_owner(id)) == $ChassisSingleCollision or\
		shape_owner_get_owner(shape_find_owner(id)) == $ChassisLeftCollision or\
		shape_owner_get_owner(shape_find_owner(id)) == $ChassisRightCollision


func get_shape_from_id(id):
	return shape_owner_get_owner(shape_find_owner(id))


func add_decal(id, decal_position, type, size):
	var shape = get_shape_from_id(id)
	var decals_node
	if shape == $CoreCollision:
		decals_node = CoreDecals
	elif shape == $LeftShoulderCollision:
		decals_node = LeftShoulderDecals
	elif shape == $RightShoulderCollision:
		decals_node = RightShoulderDecals
	else:
		push_error("Not a valid shape id: " + str(id))
		return
	if not is_instance_valid(decals_node):
		return
	var decal = DECAL.instantiate()

	#Transform3D global position into local position
	var final_pos = decal_position-decals_node.global_position
	var trans = decals_node.global_transform
	final_pos = final_pos.rotated(-trans.get_rotation())
	final_pos /= trans.get_scale()
	final_pos *= randf_range(.6,.9) #Random depth for decal on mecha
	decals_node.add_child(decal)
	decal.setup(type, size, final_pos)


func increase_heat(amount_kj: float):
	pending_heat_kj += amount_kj

func update_heat(dt):
	if display_mode:
		internal_temp = 0.0
		external_temp = 0.0
		pending_heat_kj = 0.0
		shader_heat_value = 0
		return
	
	# --- Drain pending heat into thermal system ---
	if pending_heat_kj > 0.0:
		# Exponential drain: transfer a fraction per tick
		var transfer_kj = pending_heat_kj * min(dt / HEAT_TRANSFER, 1.0)
		pending_heat_kj -= transfer_kj
		
		# Route through ventilation split (same logic as old increase_heat)
		if build.generator:
			var vent_ratio = build.generator.ventilation_ratio
			var internal_kj = transfer_kj * vent_ratio
			var external_kj = transfer_kj * (1.0 - vent_ratio)
			
			internal_temp += internal_kj / internal_capacity
			
			# Overflow check
			if internal_temp > overheat_temp:
				var overflow_degrees = internal_temp - overheat_temp
				var overflow_kj = overflow_degrees * internal_capacity
				internal_temp = overheat_temp
				external_kj += overflow_kj
			
			external_temp += external_kj / external_capacity
		else:
			external_temp += transfer_kj / external_capacity
	
	# --- Internal Cooling ---
	# Fire status blocks all cooling (same as before)
	if build.generator and not has_status("fire"):
		var cooling_coeff = build.generator.cooling_power * disabled_systems.heat_dispersion
		if has_status("freezing"):
			cooling_coeff *= 2.0
		
		# Newton's law: cooling proportional to temp above ambient
		# internal_temp is already "degrees above ambient", so just multiply
		var internal_cooling_kw = cooling_coeff * internal_temp
		var internal_cooling_kj = internal_cooling_kw * dt
		internal_temp = max(internal_temp - internal_cooling_kj / internal_capacity, 0.0)
	
	# --- Internal Overflow Check ---
	# If cooling couldn't keep up (or fire blocked it), overflow to external
	if internal_temp > overheat_temp:
		var overflow_degrees = internal_temp - overheat_temp
		var overflow_kj = overflow_degrees * internal_capacity
		internal_temp = overheat_temp
		external_temp += overflow_kj / external_capacity
	
	# --- External Shedding ---
	# Always sheds (even during fire — external surface still radiates)
	if build.generator:
		var conductivity = build.generator.thermal_conductivity
		if has_status("freezing"):
			conductivity *= 2.0
		
		var external_shedding_kw = conductivity * external_temp
		var external_shedding_kj = external_shedding_kw * dt
		external_temp = max(external_temp - external_shedding_kj / external_capacity, 0.0)
	
# --- OVverheat Damage Trigger --- 	
	if external_temp >= OVERHEAT_DAMAGE_TEMP:
		if not has_status("overheating"):
			set_status("overheating", 1.0)  # Activate with any positive value
	else:
		if has_status("overheating") and not has_status("fire"):
			# Clear overheating once external cools below threshold
			# (fire status can independently cause overheating, so don't clear if on fire)
			set_status("overheating", 0.0)
	
	# --- Weapon Heat ---
	# Pass external_temp as the visual glow reference for now
	for weapon in [LeftArmWeapon, RightArmWeapon, LeftShoulderWeapon, RightShoulderWeapon]:
		weapon.update_heat(get_effective_cooling(), external_temp, dt)
	
	# --- Shader Visuals ---
	# Bridge to old shader system: map external_temp to the range shaders expect
	# Old system used 0-300 range. Scale external_temp so ambient=0, hot combat~150-200
	var target_visible = external_temp * 2.0  # Tuning scalar — adjust to taste
	if has_status("overheating"):
		target_visible = 300
	
	# Smooth transition (keeps the old visual feel)
	if target_visible > shader_heat_value:
		shader_heat_value = min(shader_heat_value + 200 * dt, target_visible)
	else:
		shader_heat_value = max(shader_heat_value - 100 * dt, target_visible)
	for weapon in [LeftArmWeapon, RightArmWeapon, LeftShoulderWeapon, RightShoulderWeapon]:
		weapon.update_heat(get_effective_cooling(), shader_heat_value, dt)
	for node in [Core, CoreSub, CoreGlow, Head, HeadSub, HeadGlow, HeadPort, LeftShoulder, RightShoulder,\
				SingleChassis, SingleChassisSub, SingleChassisGlow, LeftChassis, LeftChassisSub, LeftChassisGlow,\
				RightChassis, RightChassisSub, RightChassisGlow]:
		node.material.set_shader_parameter("heat", shader_heat_value)

# Returns a 0-1 normalized thermal signature for detection systems
# 0.0 = at ambient (invisible), 1.0 = extremely hot
func get_thermal_signature() -> float:
	# Normalize against a reference "very hot" value
	# 150°C above ambient is considered max detection signature
	return clamp(external_temp / 150.0, 0.0, 1.0)

# Returns absolute external temperature in °C (for display / fuse checks)
func get_external_temp_absolute() -> float:
	return AMBIENT_TEMP + external_temp

func get_effective_cooling() -> float:
	if not build.generator:
		return 0.0
	return build.generator.cooling_power * disabled_systems.heat_dispersion
	


func create_sound(volume_type, type, max_distance):
	emit_signal("made_sound", {
		"volume_type": volume_type,
		"type": type,
		"position": global_position,
		"max_distance": max_distance,
		"source": self
	})


#PARTS SETTERS

func set_arm_weapon(part_name, side):
	if part_name and not build.core:
		push_error("Mecha doesn't have a core to assign arm weapon")
		return

	var node; var sfx_node
	if side == SIDE.LEFT:
		node = $ArmWeaponLeft
		sfx_node = WeaponSFXs["arm_weapon_left"]
	elif side == SIDE.RIGHT:
		node = $ArmWeaponRight
		sfx_node = WeaponSFXs["arm_weapon_right"]
	else:
		push_error("Not a valid side: " + str(side))

	if typeof(part_name) != TYPE_STRING or part_name == null:
		if side == SIDE.LEFT:
			build.arm_weapon_left = null
		else:
			build.arm_weapon_right = null
		node.set_images(null, null, null)
		return

	var part_data = PartManager.get_part("arm_weapon", part_name)
	if side == SIDE.LEFT:
		print("Equipping left arm weapon")
		build.arm_weapon_left = part_data
		node.rotation_degrees = -ARM_WEAPON_INITIAL_ROT if not part_data.is_melee else 0
	else:
		print("Equipping right arm weapon")
		build.arm_weapon_right = part_data
		node.rotation_degrees = ARM_WEAPON_INITIAL_ROT if not part_data.is_melee else 0

	node.setup(self, part_data, build.core, side)
	set_weapon_sfx_nodes(sfx_node, part_data)


func set_shoulder_weapon(part_name, side):
	if part_name and not build.core:
		push_error("Mecha doesn't have a core to assign shoulder weapon")
		return

	var node; var sfx_node
	if side == SIDE.LEFT:
		node = $ShoulderWeaponLeft
		sfx_node = WeaponSFXs["shoulder_weapon_left"]
	elif side == SIDE.RIGHT:
		node = $ShoulderWeaponRight
		sfx_node = WeaponSFXs["shoulder_weapon_right"]
	else:
		push_error("Not a valid side: " + str(side))

	if typeof(part_name) != TYPE_STRING:
		if side == SIDE.LEFT:
			build.shoulder_weapon_left = null
		elif side == SIDE.RIGHT:
			build.shoulder_weapon_right = null
		node.set_images(null, null, null)
		return

	var part_data = PartManager.get_part("shoulder_weapon", part_name)
	if side == SIDE.LEFT:
		build.shoulder_weapon_left = part_data
	else:
		build.shoulder_weapon_right = part_data

	node.setup(self, part_data, build.core, side)
	set_weapon_sfx_nodes(sfx_node, part_data)

func set_weapon_sfx_nodes(sfx_node, part_data):
	sfx_node.shoot_loop.stream = part_data.shoot_loop_sfx
	sfx_node.shoot_loop.max_distance = part_data.sound_max_range
	sfx_node.spool_up.stream = part_data.spool_up_sfx
	sfx_node.spool_up.max_distance = part_data.sound_max_range*SPOOLING_DISTANCE_ATT
	sfx_node.spool_down.stream = part_data.spool_down_sfx
	sfx_node.spool_down.max_distance = part_data.sound_max_range*SPOOLING_DISTANCE_ATT


func set_core(part_name):
	# CHANGED: handle null/false instead of falling back to "Null"
	if not part_name:
		build.core = null
		Core.texture = null
		CoreSub.texture = null 
		CoreGlow.texture = null  
		#do NOT touch mech_inventory here
		return
	var part_data = PartManager.get_part("core", part_name)
	Core.texture = part_data.get_image()
	$CoreCollision.polygon = part_data.get_collision()
	build.core = part_data
	if build.core.get_head_port() != null:
		$HeadPort.texture = build.core.get_head_port()
		$HeadPort.position = build.core.get_head_offset()
	else:
		$HeadPort.texture = null
	var index = 1
	for node in Particle.overheating:
		#Ignores "OverheatingSparks"
		if node.name.find("Sparks") == -1:
			var offset = build.core.get_overheat_offset(index)
			if offset:
				node.position = offset
			else:
				node.visible = false
			index += 1
	if not build.core.has_left_shoulder:
		set_shoulder_weapon(null, SIDE.LEFT)
	if not build.core.has_right_shoulder:
		set_shoulder_weapon(null, SIDE.RIGHT)
	CoreSub.texture = build.core.get_sub()
	CoreGlow.texture = build.core.get_glow()
	update_max_life_from_parts()
	update_max_shield_from_parts()
	stability = get_stat("stability")
	reset_offsets()
	
	# Initialize armor# In set_core(), replace the armor initialization:
	armor.core = {
		"front": {"level": part_data.front_armor if "front_armor" in part_data else 3, "pips": 3},
		"side": {"level": part_data.side_armor if "side_armor" in part_data else 2, "pips": 3},
		"rear": {"level": part_data.rear_armor if "rear_armor" in part_data else 1, "pips": 3}
		}
	
	# Initialize components from defaults + part data
	components.core = initialize_components("core", part_data)
	
	# Add wetware components (generator, chipset, thruster) if equipped
	if build.generator:
		components.core["generator"] = {
			"hp": 3, "max_hp": 3,
			"tags": ["internal"],
			"weight": 1.0,
			"disabled": false
		}
	if build.chipset:
		components.core["chipset"] = {
			"hp": 2, "max_hp": 2,
			"tags": ["internal"],
			"weight": 1.0,
			"disabled": false
		}
	if build.thruster:
		components.core["thruster"] = {
			"hp": 3, "max_hp": 3,
			"tags": ["internal"],
			"weight": 1.0,
			"disabled": false
		}
	
	# CHANGED: replaced initialize_grid with resize_and_migrate to preserve items
	if mech_inventory == null:
		mech_inventory = Inventory.new()
		var cargo = build.core.cargo_space  # MOVED: cargo declaration inside if block
		mech_inventory.initialize_grid(cargo[0], cargo[1])
	else:
		var cargo = build.core.cargo_space  
		mech_inventory.resize_and_migrate(cargo[0], cargo[1])  
		
	# Derive internal thermal capacity from coolant
	if build.core.coolant_type:
		var ct: CoolantType = build.core.coolant_type
		var mass_kg = build.core.coolant_volume * ct.density
		internal_capacity = mass_kg * ct.specific_heat  # kJ/°C
		overheat_temp = ct.overheat_temp - AMBIENT_TEMP  # Convert to delta above ambient
	else:
		# Fallback if no coolant assigned (shouldn't happen in production)
		print("!!!!!!! MECH USING FALLBACK THERMALS !!!!!!!")
		internal_capacity = 40.0
		overheat_temp = 110.0

func set_generator(part_name):
	if part_name:
		var part_data = PartManager.get_part("generator", part_name)
		build.generator = part_data
		
		#Read thermal management stats
		external_capacity = build.generator.external_thermal_capacity
		
		# Battery / shield (unchanged)
		battery_capacity = build.generator.battery_capacity
		battery = build.generator.battery_capacity
		battery_recharge_rate = build.generator.battery_recharge_rate
		shield_project_cooldown = build.generator.shield_project_cooldown
		shield_project_heat = build.generator.shield_project_heat
		
		if is_player():
			GeneratorAmbientSFX.stream = build.generator.ambient_sfx
			if GeneratorAmbientSFX.stream:
				GeneratorAmbientSFX.play()
	else:
		build.generator = null
	update_max_shield_from_parts()


func set_chipset(part_name):
	if part_name:
		var part_data = PartManager.get_part("chipset", part_name)
		build.chipset = part_data
		#TODO remove this variables
		ecm = build.chipset.ECM
		ecm_frequency = build.chipset.ECM_frequency
		lock_strength = build.chipset.lock_on_strength
		lock_on_duration = build.chipset.lock_on_duration
	else:
		build.chipset = null


func set_thruster(part_name):
	if part_name:
		var part_data = PartManager.get_part("thruster", part_name)
		build.thruster = part_data
	else:
		build.thruster = null


func set_chassis(part_name):
	if part_name == null or not (part_name is String or part_name is StringName):
		remove_chassis("single")
		remove_chassis("pair")
		movement_type = "free"
		build.chassis = null
		armor.chassis = {
			"front": {"level": 0, "pips": 0},
			"side": {"level": 0, "pips": 0},
			"rear": {"level": 0, "pips": 0}
		}	
		return
	var part_data = PartManager.get_part("chassis", part_name)
	build.chassis = part_data
	weight_capacity = build.chassis.weight_capacity
	ChassisAmbientSFX.stream = build.chassis.ambient_sfx
	ChassisAmbientSFX.max_distance = build.chassis.ambient_sfx_max_distance
	if ChassisAmbientSFX.stream:
		ChassisAmbientSFX.play()
		
	# Initialize armor
	armor.chassis = {
		"front": {"level": part_data.front_armor if "front_armor" in part_data else 3, "pips": 3},
		"side": {"level": part_data.side_armor if "side_armor" in part_data else 2, "pips": 3},
		"rear": {"level": part_data.rear_armor if "rear_armor" in part_data else 2, "pips": 3}
	}
	
	# Initialize components
	components.chassis = initialize_components("chassis", part_data)
	
	# Add movement-type specific components
	match part_data.movement_type:
		"legs":
			components.chassis["left_leg_actuator"] = {
				"hp": 2, "max_hp": 2,
				"tags": ["internal", "mobility"],
				"weight": 1.5,
				"disabled": false
			}
			components.chassis["right_leg_actuator"] = {
				"hp": 2, "max_hp": 2,
				"tags": ["internal", "mobility"],
				"weight": 1.5,
				"disabled": false
			}
		"wheels", "tank":
			components.chassis["tracks"] = {
				"hp": 3, "max_hp": 3,
				"tags": ["external", "mobility"],
				"weight": 2.0,
				"disabled": false
			}
	
	set_chassis_parts()


func set_chassis_parts():
	if build.chassis.is_legs:
			remove_chassis("single")
			set_chassis_nodes(RightChassis, RightChassisSub, RightChassisGlow, $ChassisRightCollision, SIDE.RIGHT)
			set_chassis_nodes(LeftChassis, LeftChassisSub, LeftChassisGlow, $ChassisLeftCollision, SIDE.LEFT)
	else:
		remove_chassis("pair")
		set_chassis_nodes(SingleChassis, SingleChassisSub, SingleChassisGlow, $ChassisSingleCollision, false)
	stability = get_stat("stability")
	Particle.chassis_hover[0].emitting = (build.chassis.hover_particles and not display_mode)
	Particle.chassis_hover[1].emitting = (build.chassis.hover_particles and not display_mode)


func set_chassis_nodes(main,sub,glow,collision,side = false):
	var chassis = build.chassis
	if build.core and chassis.is_legs:
		var pos = build.core.get_chassis_offset(side)
		main.position = pos
		sub.position = pos
		glow.position = pos
		collision.position = pos
	main.texture = chassis.get_image(side)
	sub.texture = chassis.get_sub(side)
	glow.texture = chassis.get_glow(side)
	collision.polygon = chassis.get_collision(side)
	movement_type = chassis.movement_type
	update_speed(chassis.max_speed, chassis.move_acc, chassis.friction, chassis.rotation_acc)
	update_max_life_from_parts()


func remove_chassis(type):
	if type == "single":
		SingleChassis.texture = null
		SingleChassisGlow.texture = null
		SingleChassisSub.texture = null
		$ChassisSingleCollision.polygon = []
	elif type == "pair":
		LeftChassis.texture = null
		LeftChassisGlow.texture = null
		LeftChassisSub.texture = null
		$ChassisLeftCollision.polygon = []
		RightChassis.texture = null
		RightChassisGlow.texture = null
		RightChassisSub.texture = null
		$ChassisRightCollision.polygon = []


func set_head(part_name):
	if part_name:
		var part_data = PartManager.get_part("head", part_name)
		Head.texture = part_data.get_image()
		HeadSub.texture = part_data.get_sub()
		HeadGlow.texture = part_data.get_glow()
		build.head = part_data
		if build.core:
			Head.position = build.core.get_head_offset()
		armor.head = {
			"front": {"level": part_data.front_armor, "pips": 3},
			"side": {"level": part_data.side_armor, "pips": 3},
			"rear": {"level": part_data.rear_armor, "pips": 3}
		}
		# Initialize components
		components.head = initialize_components("head", part_data)
	else:
		Head.texture = null
		HeadSub.texture = null
		HeadGlow.texture = null
		build.head = null
		armor.head = {
			"front": {"level": 0, "pips": 0},
			"side": {"level": 0, "pips": 0},
			"rear": {"level": 0, "pips": 0}
		}
	update_max_life_from_parts()


func set_shoulders(part_name):
	if part_name:
		var part_data = PartManager.get_part("shoulders", part_name)
		build.shoulders = part_data
		
		# Initialize armor for both shoulders
		armor.left_shoulder = {
			"front": {"level": part_data.front_armor if "front_armor" in part_data else 2, "pips": 3},
			"side": {"level": part_data.side_armor if "side_armor" in part_data else 1, "pips": 3},
			"rear": {"level": part_data.rear_armor if "rear_armor" in part_data else 1, "pips": 3}
		}
		armor.right_shoulder = {
			"front": {"level": part_data.front_armor if "front_armor" in part_data else 2, "pips": 3},
			"side": {"level": part_data.side_armor if "side_armor" in part_data else 1, "pips": 3},
			"rear": {"level": part_data.rear_armor if "rear_armor" in part_data else 1, "pips": 3}
		}
		
		# Initialize components for both shoulders
		components.left_shoulder = initialize_components("shoulders", part_data)
		components.right_shoulder = initialize_components("shoulders", part_data)
		

		if build.core:
			$LeftShoulder.position = build.core.get_shoulder_offset(SIDE.LEFT)
			$LeftShoulderCollision.position = build.core.get_shoulder_offset(SIDE.LEFT)
			$RightShoulder.position = build.core.get_shoulder_offset(SIDE.RIGHT)
			$RightShoulderCollision.position = build.core.get_shoulder_offset(SIDE.RIGHT)
		else:
			push_error("No core for putting on shoulders.")
		$LeftShoulder.texture = part_data.get_image(SIDE.LEFT)
		$RightShoulder.texture = part_data.get_image(SIDE.RIGHT)
		$LeftShoulderCollision.polygon = part_data.get_collision(SIDE.LEFT)
		$RightShoulderCollision.polygon = part_data.get_collision(SIDE.RIGHT)
	else:
		build.shoulders = null
		$LeftShoulder.texture = null
		$RightShoulder.texture = null
		armor.left_shoulder = {
			"front": {"level": 0, "pips": 0},
			"side": {"level": 0, "pips": 0},
			"rear": {"level": 0, "pips": 0}
		}
		armor.right_shoulder = {
			"front": {"level": 0, "pips": 0},
			"side": {"level": 0, "pips": 0},
			"rear": {"level": 0, "pips": 0}
		}
	update_max_shield_from_parts()
	arm_accuracy_mod = get_stat("arms_accuracy_modifier")
	stability = get_stat("stability")


func reset_offsets():
	var core = build.core
	if core:
		$Head.position = core.get_head_offset()
		$HeadPort.position = core.get_headport_offset()
		$LeftShoulder.position = core.get_shoulder_offset(SIDE.LEFT)
		$LeftShoulderCollision.position = core.get_shoulder_offset(SIDE.LEFT)
		$RightShoulder.position = core.get_shoulder_offset(SIDE.RIGHT)
		$RightShoulderCollision.position = core.get_shoulder_offset(SIDE.RIGHT)
		$ArmWeaponLeft.position = core.get_arm_weapon_offset(SIDE.LEFT)
		$ArmWeaponRight.position = core.get_arm_weapon_offset(SIDE.RIGHT)
		$ShoulderWeaponLeft.position = core.get_shoulder_weapon_offset(SIDE.LEFT)
		$ShoulderWeaponRight.position = core.get_shoulder_weapon_offset(SIDE.RIGHT)
		if build.chassis:
			set_chassis_parts()

#ATTRIBUTE METHODS

func get_max_hp():
	return max_hp

func get_cargo_space():
	var total_cargo_space = [0,0]
	for part in build.values():
		if part and part.get("cargo_space"):
			var _cg = part.get("cargo_space")
			total_cargo_space[0] += _cg[0]
			total_cargo_space[1] += _cg[1]
	return total_cargo_space

func get_stat(stat_name):
	var total_stat = 0.0
	for part in build.values():
		if part and part.get(stat_name):
			total_stat += part[stat_name]

	if stat_name.contains("max_speed") and is_overweight():
		var total_weight = get_total_weight()
		if weight_capacity > 0.0:
			total_stat /= (total_weight / weight_capacity) * OVERWEIGHT_SPEED_MOD
			total_stat = round(total_stat)
		
	if stat_name == "thrust_max_speed":
		total_stat += get_stat("max_speed")
	return float(total_stat)

func get_inventory_weight() -> float:
	if mech_inventory:
		return mech_inventory.get_current_weight()
	return 0.0


func get_total_weight() -> float:
	# Parts weight (from build) + cargo weight (inventory)
	var parts_weight = get_stat("weight")
	return parts_weight + get_inventory_weight()



func get_weapon_part(part_name):
	if part_name == "arm_weapon_left":
		if build.arm_weapon_left:
			return $ArmWeaponLeft
	elif part_name == "arm_weapon_right":
		if build.arm_weapon_right:
			return $ArmWeaponRight
	elif part_name == "shoulder_weapon_left":
		if build.shoulder_weapon_left:
			return $ShoulderWeaponLeft
	elif part_name == "shoulder_weapon_right":
		if build.shoulder_weapon_right:
			return $ShoulderWeaponRight
	else:
		push_error("Not a valid weapon part name: " + str(part_name))

	return false


func get_clip_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		if part.data.uses_battery:
			return battery
		else:
			return part.clip_ammo
	return false


func get_battery_drain(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.data.battery_drain
	return false


func get_clip_size(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.data.clip_size
	return false


func get_total_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		if part.data.uses_battery:
			return battery
		else:
			return part.total_ammo - (get_clip_size(part_name) - get_clip_ammo(part_name))
	return false


func get_max_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.data.max_ammo
	return false


func get_ammo_cost(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.data.ammo_cost
	return false


func set_ammo(part_name, target_val):
	var part = get_weapon_part(part_name)
	if typeof(target_val) == TYPE_INT:
		part.data.total_ammo = target_val

#MOVEMENT METHODS

func get_direction_from_vector(dir_vec, eight_directions = false):
	var margin = PI/8
	var angle = dir_vec.angle()
	if angle < 0:
		angle += 2*PI
	if not eight_directions:
		if angle > PI/4 - margin and angle <= 3*PI/4 + margin:
			return "down"
		if angle > 3*PI/4 - margin and angle <= 5*PI/4 + margin:
			return "left"
		if angle > 5*PI/4 - margin and angle <= 7*PI/4 + margin:
			return "up"
		if angle > 7*PI/4 - margin or angle <= PI/4 + margin:
			return "right"
	else:
		if angle > PI/2 - margin and angle <= PI/2 + margin:
			return "down"
		if angle >  PI/2 + PI/4 - margin and angle <= PI/2 + PI/4 + margin:
			return "downleft"
		if angle > PI - margin and angle <= PI + margin:
			return "left"
		if angle >  PI + PI/4 - margin and angle <= PI + PI/4 + margin:
			return "upleft"
		if angle > 3*PI/2 - margin and angle <= 3*PI/2 + margin:
			return "up"
		if angle > 3*PI/2 + PI/4 - margin and angle <= 3*PI/2 + PI/4 + margin:
			return "upright"
		if angle > 3*PI/2 + PI/4 + margin or angle <= margin:
			return "right"
		if angle > PI/4 - margin or angle <= PI/4 + margin:
			return "downright"


func move(vec):
	NavAgent.set_velocity(vec)
	set_velocity(vec)
	move_and_slide()


func get_dir_name(dir):
	if dir == Vector2(0,-1):
		return "fwd"
	elif dir == Vector2(0,1):
		return "rwd"
	elif dir == Vector2(1,0):
		return "right"
	elif dir == Vector2(-1,0):
		return "left"
	else:
		return false


func dash(dash_dir):
	if dash_dir == Vector2():
		return
	var dir = get_dir_name(dash_dir.normalized())
	if typeof(dir) != TYPE_STRING:
		#Not a valid direction, should be a diagonal
		return

	if dash_cooldown[dir] <= 0.0 and not has_status("freezing"):
		increase_heat(build.thruster.dash_heat)
		dash_velocity = dash_dir.normalized()*dash_strength
		for node in Particle.chassis_dash:
			node.rotation_degrees = rad_to_deg(dash_dir.angle()) + 90
			node.restart()
			node.emitting = true
		Particle.grind[0].restart()
		Particle.grind[0].emitting = true
		if movement_type == "relative":
			dash_velocity = dash_velocity.rotated(deg_to_rad(rotation_degrees))
		dash_cooldown[dir] = build.thruster.dash_cooldown
		Particle.dash[dir].cooldown.emitting = true


func update_dash_cooldown_visuals():
	if is_dead or not build.thruster:
		return
	for dir in ["fwd", "rwd", "left", "right"]:
		Particle.dash[dir].cooldown.modulate = Color(1, 1, 1, 0.33*(dash_cooldown[dir] / build.thruster.dash_cooldown))


func apply_movement(dt, direction):
	if is_sprinting:
		#increase_throttle(1.0, THROTTLE_STEP)
		#Disable horizontal and backwards movement when sprinting
		if is_player():
			if movement_type != "tank":
				direction.x = 0
		#if is_player():
			direction.y = min(direction.y, 0.0)
	var target_move_acc = clamp(move_acc*dt, 0, 1)
	var target_speed = direction.normalized() * (max_speed * throttle)
	var mult = 1.0
	if build.thruster:
		var _thrust_max_speed = get_stat("thrust_max_speed")
		if is_sprinting and not has_status("freezing") and direction != Vector2(0,0):
			mult = apply_movement_modifiers(build.thruster.thrust_speed_multiplier)
			increase_heat(build.thruster.sprinting_heat*dt)
			for node in Particle.chassis_sprint:
				node.emitting = true
			ChassisSprintGlow.visible = true
			Particle.grind[1].emitting = true
			if movement_type != "tank":
				target_speed.y = min(target_speed.y * mult, target_speed.y + _thrust_max_speed)
				target_move_acc *= clamp(target_move_acc*SPRINTING_ACC_MOD, 0, 1)
		elif direction == Vector2(0,0):
			for node in Particle.chassis_sprint:
				node.emitting = false
			ChassisSprintGlow.visible = false
			Particle.grind[1].emitting = false
	if movement_type == "free":
		if direction.length() > 0:
			moving = true
			velocity = lerp(velocity, target_speed, target_move_acc)
			increase_heat(build.chassis.move_heat * throttle * dt)
		else:
			moving = false
			velocity *= 1 - build.chassis.friction
		var mod = 1.0 if is_sprinting else speed_modifier
		velocity = apply_movement_modifiers(velocity*mod)
		move(velocity)
	elif movement_type == "relative":
		if direction.length() > 0:
			moving = true
			moving_axis.x = direction.x != 0
			moving_axis.y = direction.y != 0
			target_speed = target_speed.rotated(deg_to_rad(rotation_degrees))
			velocity = lerp(velocity, target_speed, target_move_acc)
			increase_heat(build.chassis.move_heat * throttle * dt)
		else:
			moving = false
			moving_axis.x = false
			moving_axis.y = false
			velocity *= 1 - build.chassis.friction
		var mod = 1.0 if is_sprinting else speed_modifier
		velocity = apply_movement_modifiers(velocity*mod)
		move(velocity)
	elif movement_type == "tank" and not is_player():
		if direction.length() > 0:
			moving = true
			var target_rotation_acc = apply_movement_modifiers(build.chassis.rotation_acc * 50)
			var rotated_tank_move_target = tank_move_target.rotated(deg_to_rad(270))
			#Compare direction we want to go to the way the Chassis is facing.
			var turn_angle = rad_to_deg(rotated_tank_move_target.angle_to(direction))
			#Turn chassis to face the direction
			if turn_angle > AI_TURN_DEADZONE:
				#Right
				tank_move_target = tank_move_target.rotated(deg_to_rad(target_rotation_acc*dt))
				global_rotation_degrees += target_rotation_acc*dt
			elif turn_angle < -AI_TURN_DEADZONE:
				#Left
				tank_move_target = tank_move_target.rotated(deg_to_rad(-target_rotation_acc*dt))
				global_rotation_degrees -= target_rotation_acc*dt
			target_speed = rotated_tank_move_target * min(max_speed, (max_speed * mult/1.5 * pow(rotated_tank_move_target.dot(direction),3.0)))
			target_speed *= WHEELS_SPEED_FACTOR
			velocity = lerp(velocity, target_speed, target_move_acc)
			increase_heat(build.chassis.move_heat * throttle * dt)
			move(apply_movement_modifiers(velocity))
			velocity = apply_movement_modifiers(velocity)
			move(velocity)
			#Move forward or backward depending on how closely the chassis is facing the angle
	elif movement_type == "tank":
		if direction.length() > 0:
			moving = false
			if direction.y > 0:
				moving = true
				target_speed = tank_move_target.rotated(deg_to_rad(90)) * max_speed * mult/1.5 * WHEELS_SPEED_FACTOR
			if direction.y < 0:
				moving = true
				target_speed = tank_move_target.rotated(deg_to_rad(270)) * max_speed * mult/1.5 * WHEELS_SPEED_FACTOR
			if build.thruster:
				var _thrust_max_speed = get_stat("thrust_max_speed")
				if target_speed.length() > (target_speed.normalized() * _thrust_max_speed).length():
					target_speed = target_speed.normalized() * _thrust_max_speed * WHEELS_SPEED_FACTOR
			var target_rotation_acc = apply_movement_modifiers(build.chassis.rotation_acc * 50)
			if direction.y == 0:
				target_rotation_acc *= 2
			if direction.x > 0:
				tank_move_target = tank_move_target.rotated(deg_to_rad(target_rotation_acc*dt))
				global_rotation_degrees += target_rotation_acc*dt
			elif direction.x < 0:
				tank_move_target = tank_move_target.rotated(deg_to_rad(-target_rotation_acc*dt))
				global_rotation_degrees -= target_rotation_acc*dt
			if not moving:
				velocity *= 1 - build.chassis.friction
			else:
				velocity = lerp(velocity, target_speed, target_move_acc)
			increase_heat(build.chassis.move_heat * throttle * dt)
		else:
			if build.chassis:
				velocity *= 1 - build.chassis.friction/2
		move(apply_movement_modifiers(velocity))
	else:
		push_error("Not a valid movement type: " + str(movement_type))
	update_chassis_visuals(dt)

#Rotates solely the body given a direction ('clock' or 'counter'clock wise)
func apply_rotation_by_direction(dt, direction):
	var rot_acc = rotation_acc
	if is_sprinting == true:
		rot_acc = 0
	if direction == "clock":
		rotation_degrees += 90*rot_acc*dt
	elif direction == "counter":
		rotation_degrees -= 90*rot_acc*dt
	else:
		push_error("Not a valid direction: " + str(direction))


func apply_rotation_by_point(dt, target_pos, stand_still):
	#Rotate Body
	var rot_acc = rotation_acc
	if movement_type == "tank" and build.chassis:
		rot_acc = build.chassis.trim_acc
	if is_sprinting == true and movement_type != "tank":
		rot_acc = rotation_acc/2
	if not stand_still:
		rotation_degrees += get_rotation_diff_by_point(dt, global_position, target_pos, rotation_degrees, rot_acc)

	
	#Rotate Head and Shoulders
	for data in [[$Head, build.head], [$LeftShoulder, build.shoulders], [$RightShoulder, build.shoulders]]:
		var node_ref = data[1]
		if node_ref:
			var node = data[0]
			var actual_rot = node.rotation_degrees + rotation_degrees
			node.rotation_degrees += get_rotation_diff_by_point(dt, node.global_position, target_pos, actual_rot, node_ref.rotation_acc)
			node.rotation_degrees = clamp(node.rotation_degrees, -node_ref.rotation_range, node_ref.rotation_range)

	#Rotate Non-Melee Arm Weapons
	for data in [[$ArmWeaponLeft, build.arm_weapon_left], [$ArmWeaponRight, build.arm_weapon_right]]:
		var node_ref = data[1]
		if node_ref and not node_ref.is_melee:
			var node = data[0]
			var actual_rot = node.rotation_degrees + rotation_degrees
			node.rotation_degrees += get_rotation_diff_by_point(dt, node.global_position, target_pos, actual_rot, node_ref.rotation_acc)
			if node == $ArmWeaponLeft:
				node.rotation_degrees += node_ref.parallax_offset
			else:
				node.rotation_degrees -= node_ref.parallax_offset
			node.rotation_degrees = clamp(node.rotation_degrees, -build.core.rotation_range, build.core.rotation_range)

	for data in	[[$Chassis/Left, build.chassis], [$Chassis/Right, build.chassis]]:
		var node_ref = data[1]
		if node_ref:
			var node = data[0]
			var actual_rot = node.rotation_degrees + rotation_degrees
			node.rotation_degrees += get_rotation_diff_by_point(dt, node.global_position, target_pos, actual_rot, node_ref.trim_acc)
			node.rotation_degrees = clamp(node.rotation_degrees, -node_ref.rotation_range, node_ref.rotation_range)

#Return the proper direction diff to rotate given a current and target rotation
func get_best_rotation_diff(cur_rot, target_rot):
	var diff = target_rot - cur_rot
	if diff > 180:
		diff -= 360
	elif diff < -180:
		diff += 360
	return diff


func get_rotation_diff_by_point(dt, origin, target_pos, cur_rot, acc):
	var target_rot = rad_to_deg(origin.angle_to_point(target_pos)) + 90
	return get_best_rotation_diff(cur_rot, target_rot)*acc*dt


func knockback(_strength, _knockback_dir, _should_rotate = true):
	return
	#impact_velocity += (knockback_dir.normalized() * (strength * get_stability()))
	#if should_rotate:
	#	if impact_rotation_velocity > 0:
	#		impact_rotation_velocity += strength / (get_stat("stability")*10)
	#	elif impact_rotation_velocity < 0:
	#		impact_rotation_velocity -= strength / (get_stat("stability")*10)
	#	else:
	#		if randi()%2 == 1:
	#			impact_rotation_velocity += strength / (get_stat("stability")*10)
	#		else:
	#			impact_rotation_velocity -= strength / (get_stat("stability")*10)


func update_chassis_visuals(dt):
	var angulation = 25
	if build.chassis and build.chassis.is_legs:
		var rot_vec = Vector2(1, 0).rotated(deg_to_rad(rotation_degrees))
		var vel_vec = velocity
		var left_target_angle
		var right_target_angle
		if velocity.length() > 5:
			var angle = vel_vec.angle_to(rot_vec)
			var dot = vel_vec.dot(rot_vec)
			if angle >= PI/2 - PI/4 and angle <= PI/2 + PI/4: #Forward
				left_target_angle = angulation
				right_target_angle = -angulation
			elif angle <= -PI/2 + PI/4 and angle >= -PI/2 - PI/4: #Backward
				left_target_angle = -angulation
				right_target_angle = angulation
			elif dot > 0: #Right
				left_target_angle = angulation
				right_target_angle = angulation
			else: #Left
				left_target_angle = -angulation
				right_target_angle = -angulation
		else: #Neutral
			left_target_angle = 0
			right_target_angle = 0

		for child in LeftChassisRoot.get_children():
			child.rotation_degrees = lerp(float(child.rotation), float(left_target_angle),\
										dt*CHASSIS_SPEED)
		for child in RightChassisRoot.get_children():
			child.rotation_degrees = lerp(float(child.rotation), float(right_target_angle),\
										dt*CHASSIS_SPEED)

func stop_sprinting(sprint_dir):
	if is_sprinting and sprint_dir != Vector2(0,0):
		sprinting_ending_correction = Vector2(velocity.x, velocity.y)
		lock_movement(0.5 * get_stability())
		Particle.grind[0].restart()
		Particle.grind[0].emitting = true
		for node in [Particle.chassis_dash[0], Particle.chassis_dash[2]]:
			node.rotation_degrees = rad_to_deg(Vector2(0,-1).angle()) + 90
			node.restart()
			node.emitting = true
		increase_heat(build.thruster.dash_heat/2.0)
	is_sprinting = false
	for node in Particle.chassis_sprint:
		node.emitting = false
	ChassisSprintGlow.visible = false
	Particle.grind[1].emitting = false

func increase_throttle(set_value, step):
	if set_value:
		throttle = set_value
	else:
		throttle = min(throttle + step, 1.0)

func decrease_throttle(set_value, step):
	if set_value:
		throttle = set_value
	else:
		throttle = max(throttle - step, 0.0)

#COMBAT METHODS

func shoot(type, is_auto_fire = false):
	if is_dead:
		return
	if is_shielding:
		return
	if disabled_systems.has(type) and disabled_systems[type] == true:
		if is_player():
			print("Weapon offline!")
		return
	
	#Check for spool up
	var sfx_node = WeaponSFXs[type]
	if build[type].spool_up_sfx:
		if not spooling[type]:
			spooling[type] = true
			sfx_node.spool_up.play()
			create_sound("loud", "spooling", sfx_node.spool_up.max_distance*SPOOLING_DISTANCE_ATT)
			return
		elif sfx_node.spool_up.is_playing():
			return
	
	var weapon_ref = build[type]
	var node = get_weapon_part(type)
	var bloom; var eject_angle
	if type == "arm_weapon_left":
		left_arm_bloom_time = weapon_ref.bloom_reset_time * get_stability()
		bloom = left_arm_bloom_count * weapon_ref.accuracy_bloom
		eject_angle = 180.0
	elif type ==  "arm_weapon_right":
		right_arm_bloom_time = weapon_ref.bloom_reset_time * get_stability()
		bloom = right_arm_bloom_count * weapon_ref.accuracy_bloom
		eject_angle = 0.0
	elif type == "shoulder_weapon_left":
		left_shoulder_bloom_time = weapon_ref.bloom_reset_time * get_stability()
		bloom = left_shoulder_bloom_count * weapon_ref.accuracy_bloom
		eject_angle = 180.0
	elif type ==  "shoulder_weapon_right":
		right_shoulder_bloom_time = weapon_ref.bloom_reset_time * get_stability()
		bloom = right_shoulder_bloom_count * weapon_ref.accuracy_bloom
		eject_angle = 0.0
	else:
		push_error("Not a valid type of weapon to shoot: " + str(type))
		return
	
	if weapon_ref.is_melee:
		node.light_attack()
		increase_heat(weapon_ref.muzzle_heat)
		emit_signal("shoot_signal")
		return
	
	if weapon_ref.shoot_loop_sfx and not sfx_node.shoot_loop.is_playing():
		sfx_node.shoot_loop.play()
		
	while node.burst_count < weapon_ref.burst_size:
		var amount
		if weapon_ref.uses_battery:
			amount = weapon_ref.number_projectiles
			if not node.can_shoot_battery(weapon_ref.battery_drain, battery) or has_status("electrified"):
				if is_player() and weapon_ref.battery_drain > battery and not is_auto_fire:
					AudioManager.play_sfx("no_ammo", global_position)
					create_sound("quiet", "no_ammo", 600)
				return
			node.shoot_battery()
			battery = max(battery - weapon_ref.battery_drain, 0)
		else:
			amount = min(weapon_ref.burst_ammo_cost, get_clip_ammo(type))
			amount = max(amount, 1) #Tries to shoot at least 1 projectile
			if not node.can_shoot(amount):
				if is_player() and node.clip_ammo <= 0 and not is_auto_fire:
					AudioManager.play_sfx("no_ammo", global_position)
					create_sound("quiet", "no_ammo", 600)
					
				return
			node.shoot(amount)

		#Create projectile
		if not weapon_ref.is_melee:
			##check if we can get accuracy modifier, if not set to 0.1, mecha works without head
			var head_accuracy = build.head.accuracy_modifier if build.head else 0.1
			var chipset_accuracy = build.chipset.accuracy_modifier if build.chipset else 0.1
			
			var max_angle = weapon_ref.max_bloom_angle/head_accuracy
			if type == "arm_weapon_left" or type == "arm_weapon_right":
				var arm_acc = arm_accuracy_mod if arm_accuracy_mod > 0.0 else 1.0
				max_angle = max_angle/arm_accuracy_mod
				bloom /= arm_accuracy_mod
			if locked_to:
				max_angle = max_angle/chipset_accuracy
			var total_accuracy = min(weapon_ref.base_accuracy + bloom, max_angle)/head_accuracy
			var current_accuracy = randf_range(-total_accuracy, total_accuracy)
			for _i in range(weapon_ref.number_projectiles):
				var fire_dir = node.get_direction(weapon_ref.bullet_spread, current_accuracy)
				emit_signal("create_projectile", self,
							{
								"projectile": weapon_ref.projectile,
								"pos": node.get_shoot_position().global_position,
								"pos_reference": node.get_shoot_position(),
								"dir": fire_dir,
								"align_dir": fire_dir,
								"seeker_target": locked_to,
								"node_reference": node,
								"inherited_velocity": velocity,
								"bullet_spread_delay": weapon_ref.bullet_spread_delay,
								"muzzle_flash":{
									"flash_effect": weapon_ref.muzzle_flash,
									"flash_speed": weapon_ref.muzzle_flash_speed,
									"flash_size": weapon_ref.muzzle_flash_size,
								},
							}, weapon_ref.part_id)
			apply_recoil(type, node, weapon_ref.recoil_force)
		if weapon_ref.eject_casings:
			emit_signal("create_casing",
							{
								"casing_ejector_pos": node.global_position,
								"casing_eject_angle": eject_angle + self.global_rotation_degrees,
								"casing_size": weapon_ref.casing_size,
							})
		increase_heat(weapon_ref.muzzle_heat)
		if type == "arm_weapon_left":
			left_arm_bloom_count += 1
		elif type ==  "arm_weapon_right":
			right_arm_bloom_count += 1
		elif type == "shoulder_weapon_left":
			left_shoulder_bloom_count += 1
		elif type ==  "shoulder_weapon_right":
			right_shoulder_bloom_count += 1
		emit_signal("shoot_signal")
	node.burst_cooldown()


func stop_shooting(weapon_type):
	var sfx_node = WeaponSFXs[weapon_type]
	if spooling[weapon_type]:
		sfx_node.spool_up.stop()
		sfx_node.spool_down.play()
		create_sound("loud", "spooling", sfx_node.spool_down.max_distance*SPOOLING_DISTANCE_ATT)
	if sfx_node.shoot_loop.is_playing():
		sfx_node.shoot_loop.stop()
	spooling[weapon_type] = false


func apply_recoil(type, node, recoil):
	var total_weight = max(get_total_weight(), 1.0)
	var target_rotation = recoil * 300 / total_weight
	if "left" in type:
		target_rotation *= -1
	rotation_degrees += target_rotation
	node.rotation_degrees += rotation*WEAPON_RECOIL_MOD


func shield_up():
	await shield_ready
	if shield > 0.0:
		$ParticlesLayer3/ShieldStartup.emitting = true
		$ShieldCollision.disabled = false
		is_shielding = true
		$ParticlesLayer3/ShieldRing.emitting = true
	
func shield_down():
	shield_parry()
	$ShieldCollision.disabled = true
	is_shielding = false
	$ParticlesLayer3/ShieldRing.emitting = false
	shield_project_cooldown_timer = shield_project_cooldown

func shield_parry():
	if shield > 0.0 and shield_project_cooldown_timer == 0.0:
		is_parrying = true
		shield_parry_timer = SHIELD_PARRY_TIME
		$ParticlesLayer3/ShieldParry.emitting = true

func get_stability():
	var sum = get_stat("stability")/1000
	if has_status("freezing"):
		sum *= 0.5
	return max((1.5 - sum), 0)

func is_stunned():
	return not $StunTimer.is_stopped()


func is_movement_locked():
	return not $LockMovementTimer.is_stopped()


func stun(time):
	$StunTimer.wait_time += time * get_stability()
	$StunTimer.start()


func lock_movement(time):
	$LockMovementTimer.wait_time = time
	$LockMovementTimer.start()


#LOCK ON METHODS

func get_lock_area():
	return LockCollision

func update_enemy_locking(dt, target):
	if target:
		if not locking_to:
			locking_to = {
				"progress": 0,
				"mecha": target,
			}
		if locking_to.mecha == target and is_instance_valid(locking_to.mecha):
			if locking_to.mecha.ecm > lock_strength:
				if ecm_attempt_cooldown <= 0.0:
					ecm_strength_difference = (locking_to.mecha.ecm - lock_strength) * 0.05
					var percent = randf()
					if (percent < ecm_strength_difference):
						locking_to.progress = 0
					ecm_attempt_cooldown = 1 / locking_to.mecha.ecm_frequency
			var thermal_lock_mult = get_target_thermal_lock_mult(locking_to.mecha)
			if has_status("electrified"):
				locking_to.progress = min(locking_to.progress + (dt*build.chipset.lock_on_speed * 0.5), 1.0)
			else:
				locking_to.progress = min(locking_to.progress + dt*build.chipset.lock_on_speed, 1.0)
			if locking_to.progress >= 1.0:
				locked_to = locking_to.mecha
		else:
			locking_to = {
				"progress": 0,
				"mecha": target,
			}
	
# How much faster/slower lock-on is based on target's thermal signature
# Cold target (sig ~0): lock takes 2x as long
# Neutral target (sig ~0.3): normal speed
# Hot target (sig ~1.0): lock is ~1.5x faster
func get_target_thermal_lock_mult(target: Node) -> float:
	if not target.has_method("get_thermal_signature"):
		return 1.0
	var sig = target.get_thermal_signature()
	# Lerp from 0.5 (cold) to 1.5 (hot), with 1.0 at sig=0.33
	return lerp(0.5, 1.5, sig)

func update_locking(dt):
	if cur_mode == MODES.LOCK:
		#Update locking targets
		#For now, check only using mouse, assuming its only the player that locks
		var could_lock = []
		var mouse_pos = get_global_mouse_position()
		for area in arena.get_lock_areas():
			var mecha = area.get_parent()
			var a_radius = area.get_node("CollisionShape2D").shape.radius
			if  mecha != self and\
			mouse_pos.distance_to(area.global_position) <= build.chipset.lock_on_reticle_size + a_radius:
				could_lock.append(area.get_parent())

		for target in locking_targets:
			if not could_lock.has(target.mecha):
				locking_targets.erase(target)
			else:
				#Erase from list so we don't duplicate later
				could_lock.erase(target.mecha)
		#What remains are new locks
		for mecha in could_lock:
			locking_targets.append({
				"progress": 0,
				"mecha": mecha,
			})

		locking_to = false
		var min_dist = INF
		for target in locking_targets:
			if not locking_to:
				locking_to = target
				min_dist = global_position.distance_to(target.mecha.global_position)
			else:
				var dist = global_position.distance_to(target.mecha.global_position)
				if dist < min_dist:
					locking_to = target
					min_dist = dist
		if locking_to:
			if locking_to.mecha.ecm > lock_strength:
				if ecm_attempt_cooldown <= 0.0:
					ecm_strength_difference = (locking_to.mecha.ecm - lock_strength) * 0.05
					var percent = randf()
					if (percent < ecm_strength_difference):
						locking_to.progress = 0
					ecm_attempt_cooldown = 1 / locking_to.mecha.ecm_frequency
			if has_status("electrified"):
				locking_to.progress = min(locking_to.progress + (dt*build.chipset.lock_on_speed * 0.5), 1.0)
			else:
				locking_to.progress = min(locking_to.progress + dt*build.chipset.lock_on_speed, 1.0)
			if locking_to.progress >= 1.0:
				locked_to = locking_to.mecha


func get_locking_to():
	#Check if mecha has died
	if locking_to and not weakref(locking_to.mecha).get_ref():
		locking_to = false

	return locking_to


func get_locked_to():
	#Check if mecha has died
	if locked_to and not weakref(locked_to).get_ref():
		locked_to = false
	return locked_to


func _on_enter_lock_mode():
	locking_targets = []
	locked_to = false
	cur_mode = MODES.LOCK


# MELEE METHODS

#Check if hitbox is valid, and if so, erases all other lower priorities hitboxes
func check_valid_hitbox_and_update(hitbox_data):
	#Check if mecha was already affected by this hitbox lately
	for data in processed_hitboxes:
		if data[0] == hitbox_data.id:
			return false
	
	var to_erase = []
	for data in lingering_hitboxes:
		if data.id == hitbox_data.id:
			if data.priority >= hitbox_data.priority:
				assert(to_erase.is_empty(),"This shouldn't happen, problem with lingering hitboxes usage")
				return false
			else:
				to_erase.append(data)
	#Since it's valid, erase any other same-id hitbox
	for data in to_erase:
		lingering_hitboxes.erase(data)
	return true

#Assumes it is a valid hitbox
func add_lingering_hitbox(data):
	lingering_hitboxes.append(data)


func process_hitboxes(dt):
	#Process lingering hitboxes
	for data in lingering_hitboxes:
		add_decal(data.body_shape_id, data.collision_point, data.decal_type, data.decal_size)
		
		var weapon_ref = data.data
		take_damage(weapon_ref.damage*data.damage_mul, weapon_ref.shield_mult,\
					weapon_ref.health_mult, weapon_ref.heat_damage, weapon_ref.status_damage,\
					weapon_ref.status_type, weapon_ref.hitstop, data.origin)
		if weapon_ref.melee_knockback > 0.0 and data.knockback_mul > 0.0:
			knockback(weapon_ref.melee_knockback*data.knockback_mul, data.collision_point - data.hitbox_position, true)
		processed_hitboxes.append([data.id, data.dur])
	lingering_hitboxes.clear()
	
	#Process hitboxes that happened to free them up again
	var to_erase = []
	for data in processed_hitboxes:
		data[1] -= dt
		if data[1] <= 0:
			to_erase.append(data)
	for data in to_erase:
		processed_hitboxes.erase(data)


# BUILDING METHODS

func entered_building():
	is_inside_building = true


func exited_building():
	is_inside_building = false


func entering_building(value):
	is_entering_building = value

# MISC METHODS

func cancel_extract():
	$ExtractTimer.stop()
	$ExtractTimer.wait_time = 5


func play_step_sound(is_left := true):
	if mecha_name != "Player" or not moving:
		return
	var pitch
	if is_left:
		pitch = randf_range(.7, .72)
	else:
		pitch = randf_range(.95, .97)

	var volume = min(pow(velocity.length(), 1.3)/300.0 - 9.0, -5.0)
	AudioManager.play_sfx("robot_step", global_position, pitch, volume, 1.0, build.chassis.step_sound_max_distance)
	create_sound("quiet", "step", build.chassis.step_sound_max_distance)


func extracting():
	$ExtractTimer.start()

# CALLBACKS

func _on_ExtractTimer_timeout():
	if self.name == "Player":
		emit_signal("mecha_extracted", self)
	else:
		emit_signal("died", self)


func _on_MeleeHitboxes_create_hitbox(data, side):
	var hitbox = HITBOX.instantiate()
	var node
	if side == "left":
		node = LeftArmWeaponHitboxes
	elif side == "right":
		node = RightArmWeaponHitboxes
	else:
		push_error("Not a valid side for creating hitboxes:" + str(side))

	data.owner = self
	hitbox.setup(data)
	node.add_child(hitbox)
	
func update_inventory_space():
	var space = get_cargo_space()
	var w = space[0]
	var h = space[1]

	if mech_inventory == null:
		mech_inventory = Inventory.new()
		mech_inventory.initialize_grid(w, h)
	else:
		mech_inventory.resize_and_migrate(w, h)
		
func pickup(item: item_data):
	mech_inventory.add_item(item, 1)

func open_container(container):
	target_inventory = container.inventory

# Helper to map shape index to part name
func get_part_name_from_shape(shape_index: int) -> String:
	# shape_find_owner gives you the owner_id
	var owner_id = shape_find_owner(shape_index)
	if owner_id == -1:
		return "core"  # Default fallback
	
	# shape_owner_get_owner gives you the actual node
	var collision_node = shape_owner_get_owner(owner_id)
	
	# Map collision nodes to part names using if-elif
	if collision_node == $CoreCollision:
		return "core"
	elif collision_node == $HeadCollision:
		return "head"
	elif collision_node == $LeftShoulderCollision:
		return "left_shoulder"
	elif collision_node == $RightShoulderCollision:
		return "right_shoulder"
	elif collision_node == $ChassisSingleCollision:
		return "chassis"
	elif collision_node == $ChassisLeftCollision:
		return "chassis"
	elif collision_node == $ChassisRightCollision:
		return "chassis"
	elif collision_node == $ShieldCollision:
		return "shield"
	else:
		push_error("Unknown collision node: " + str(collision_node))
		return "core"  # Fallback

func armor_check(hit_part_name: String, impact_position: Vector2, projectile_dir: Vector2, pen_level: int, damage_pips: int) -> Dictionary:
	# Returns: {penetrated: bool, part_name: String, component_name: String, facing: String}
	
	# 1. Get global facing (front/side/rear of mech)
	var facing = get_global_facing_from_angle(impact_position)
	
	# 2. Get armor for this part and facing
	if not armor.has(hit_part_name):
		push_error("Unknown part for armor: " + hit_part_name)
		return {"penetrated": false, "part_name": "", "component_name": "", "facing": ""}
	
	var part_armor = armor[hit_part_name][facing]
	var armor_level = part_armor.level
	var armor_pips = part_armor.pips
	
	# 3. Get impact angle modifier
	var collision_shape = get_collision_shape_for_part(hit_part_name)
	var impact_angle = get_impact_angle(projectile_dir, impact_position, collision_shape)
	
	# 4. Calculate effective armor based on angle
	var effective_armor = armor_level
	if impact_angle > 60:
		effective_armor += 1  # Glancing hit, harder to penetrate
	elif impact_angle > 30:
		# Angled hit, slight penalty
		effective_armor += 0  # No change for medium angles
	# else: perpendicular hit (<30°), use base armor
	
	# 5. Calculate penetration delta
	var delta = pen_level - effective_armor
	
	# 6. Resolve armor vs penetration
	var penetrated = false
	var armor_pip_damage = 0
	var deflection_type = "" 
	
	if delta <= -2:
		# Heavily overmatched - bounce
		penetrated = false
		armor_pip_damage = 0
		if randf() < 0.66:
			deflection_type = "bounce"
		#print("BOUNCE! Pen:", pen_level, " vs Armor:", effective_armor, " (angle:", impact_angle, "°)")
	elif delta >= -1 and delta <= 0:
		# Marginal/glancing
		penetrated = false
		if randf() < 0.33:
			deflection_type = "glancing"
		if randf() < (damage_pips / 3.0):
			armor_pip_damage = 1
		#print("GLANCING! Pen:", pen_level, " vs Armor:", effective_armor, " (angle:", impact_angle, "°)")
	else:  # delta >= 1
		# Penetration!
		penetrated = true
		armor_pip_damage = damage_pips
		deflection_type = "" #No deflection on penetration, left empty
		#print("PENETRATED! Pen:", pen_level, " vs Armor:", effective_armor, " | Removed ", armor_pip_damage, " pips", " (angle:", impact_angle, "°)")
	
	# 7. Apply armor damage
	armor[hit_part_name][facing].pips = max(armor_pips - armor_pip_damage, 0)
	var facing_exposed = armor[hit_part_name][facing].pips == 0
	
	#if facing_exposed:
	#	print("ARMOR STRIPPED! ", hit_part_name, " ", facing, " facing exposed!")
	
	# 8. Select component to damage (if penetrated or exposed)
	var selected_component = ""
	if penetrated or facing_exposed:
		var eligible = get_eligible_components(hit_part_name, facing, penetrated, false)
		if eligible.size() > 0:
			selected_component = select_component_by_weight(hit_part_name, eligible)
			print("Component hit: ", selected_component)
	
	return {
		"penetrated": penetrated or facing_exposed,
		"part_name": hit_part_name,
		"component_name": selected_component,
		"facing": facing,
		"deflection_type": deflection_type,
	}
	
func get_global_facing_from_angle(impact_position: Vector2) -> String:
	var to_impact = (impact_position - global_position).normalized()
	var forward = Vector2(0, -1).rotated(global_rotation)
	var angle = forward.angle_to(to_impact)
	var deg = rad_to_deg(angle)
	
	if abs(deg) <= 45:
		return "front"
	elif abs(deg) >= 135:
		return "rear"
	else:
		return "side"	
	
func get_collision_shape_for_part(part_name: String) -> CollisionPolygon2D:
	match part_name:
		"core":
			return $CoreCollision
		"head":
			return $HeadCollision
		"left_shoulder":
			return $LeftShoulderCollision
		"right_shoulder":
			return $RightShoulderCollision
		"chassis":
			if $ChassisSingleCollision.polygon.size() > 0:
				return $ChassisSingleCollision
			else:
				return $ChassisLeftCollision
		_:
			return $CoreCollision
			
func get_impact_angle(projectile_dir: Vector2, impact_position: Vector2, collision_shape: CollisionPolygon2D) -> float:
	var surface_normal = get_surface_normal_at_point(impact_position, collision_shape)
	var impact_angle = abs(rad_to_deg(projectile_dir.angle_to(surface_normal)))
	return impact_angle
	
func get_surface_normal_at_point(point: Vector2, collision_polygon: CollisionPolygon2D) -> Vector2:
	var polygon = collision_polygon.polygon
	var transform = collision_polygon.global_transform
	
	# Find closest edge
	var closest_edge_idx = -1
	var closest_dist = INF
	
	for i in range(polygon.size()):
		var p1 = transform * polygon[i]
		var p2 = transform * polygon[(i + 1) % polygon.size()]
		var dist = Geometry2D.get_closest_point_to_segment(point, p1, p2).distance_to(point)
		
		if dist < closest_dist:
			closest_dist = dist
			closest_edge_idx = i
	
	# Get edge normal
	var p1 = transform * polygon[closest_edge_idx]
	var p2 = transform * polygon[(closest_edge_idx + 1) % polygon.size()]
	var edge = (p2 - p1).normalized()
	var normal = Vector2(-edge.y, edge.x)
	
	return normal
	
	
func get_eligible_components(part_name: String, facing: String, penetrated: bool, is_aoe: bool = false) -> Array:
	var eligible = []
	
	if not components.has(part_name):
		return eligible
	
	for comp_name in components[part_name]:
		var comp = components[part_name][comp_name]
		
		# Skip if already destroyed
		if comp.disabled:
			continue
		
		# Determine eligibility based on penetration and tags
		if penetrated:
			# Full penetration - can hit both internal and external
			eligible.append(comp_name)
		else:
			# Armor stripped but not penetrated - only external components exposed
			if "external" in comp.tags:
				eligible.append(comp_name)
	
	return eligible

func select_component_by_weight(part_name: String, eligible_components: Array) -> String:
	if eligible_components.size() == 0:
		return ""
	
	# Calculate total weight
	var total_weight = 0.0
	for comp_name in eligible_components:
		total_weight += components[part_name][comp_name].weight
	
	
	print("  ELIGIBLE COMPONENTS:")
	for comp_name in eligible_components:
		var comp = components[part_name][comp_name]
		var chance = (comp.weight / total_weight) * 100.0
		print("    ", comp_name, ": ", "%.1f" % chance, "% (", comp.tags, ")")
	
	# Weighted random selection
	var roll = randf() * total_weight
	var accumulated = 0.0
	
	for comp_name in eligible_components:
		var comp = components[part_name][comp_name]
		accumulated += comp.weight
		if roll <= accumulated:
			return comp_name
	
	# Fallback (shouldn't reach here)
	return eligible_components[0]

# Returns default components for a given part type
func get_default_components(part_type: String) -> Dictionary:
	match part_type:
		"core":
			return {
				"core_shell": {
					"hp": 3, "max_hp": 3,
					"tags": ["internal"],
					"weight": 2.0,
					"disabled": false
				},
				"radiator": {
					"hp": 2, "max_hp": 2,
					"tags": ["external"],
					"weight": 1.5,
					"disabled": false
				},
				"cockpit": {
					"hp": 1, "max_hp": 1,
					"tags": ["internal"],
					"weight": 0.5,
					"disabled": false
				},
			}
		
		"head":
			return {
				"head_shell": {
					"hp": 2, "max_hp": 2,
					"tags": ["internal"],
					"weight": 1.5,
					"disabled": false
				},
				"optics": {
					"hp": 1, "max_hp": 1,
					"tags": ["external"],
					"weight": 2.0,
					"disabled": false
				},
				"backup_optics": {
					"hp": 1, "max_hp": 1,
					"tags": ["external"],
					"weight": 1.0,
					"disabled": false
				},
				"comms_antenna": {
					"hp": 1, "max_hp": 1,
					"tags": ["external"],
					"weight": 1.5,
					"disabled": false
				},
			}
		
		"chassis":
			return {
				"chassis_shell": {
					"hp": 3, "max_hp": 3,
					"tags": ["internal"],
					"weight": 2.0,
					"disabled": false
				},
				"suspension": {
					"hp": 2, "max_hp": 2,
					"tags": ["internal"],
					"weight": 1.5,
					"disabled": false
				},
				"thruster_nozzles": {
					"hp": 1, "max_hp": 1,
					"tags": ["external"],
					"weight": 1.5,
					"disabled": false
				},
			}
		
		"shoulders":
			return {
				"shoulder_shell": {
					"hp": 2, "max_hp": 2,
					"tags": ["internal"],
					"weight": 1.5,
					"disabled": false
				},
				"arm_actuator": {
					"hp": 2, "max_hp": 2,
					"tags": ["internal"],
					"weight": 1.5,
					"disabled": false
				},
			}
		
		_:
			return {}

func initialize_components(part_type: String, part_data) -> Dictionary:
	# Start with defaults
	var result = get_default_components(part_type)
	
	if "additional_components" in part_data:
		var additional = part_data.additional_components
		if additional != null and additional is Array:
			for comp_data in additional:
				result[comp_data.name] = {
					"hp": comp_data.hp,
					"max_hp": comp_data.max_hp,
					"tags": comp_data.tags.duplicate(),
					"weight": comp_data.weight,
					"disabled": false
				}
	
	return result

func damage_component(part_name: String, component_name: String, damage_pips: int):
	if not components.has(part_name) or not components[part_name].has(component_name):
		push_error("Invalid component: " + part_name + "." + component_name)
		return
	
	var comp = components[part_name][component_name]
	
	# Apply damage
	comp.hp = max(comp.hp - damage_pips, 0)
	spawn_component_damage_explosion(part_name, comp.hp <= 0)
	# Emit damage signal for UI updates
	emit_signal("component_damaged", part_name, component_name, comp.hp, comp.max_hp)
	
	#Special warning if cockpit is damaged
	if component_name == "cockpit" and comp.hp > 0:
		emit_signal("cockpit_exposed", comp.hp)
	
	# Check if destroyed
	if comp.hp <= 0 and not comp.disabled:
		comp.disabled = true
		component_destroyed(part_name, component_name)

func component_destroyed(part_name: String, comp_name: String):
	var comp = components[part_name][comp_name]
	
	
	# Emit destruction signal
	emit_signal("component_destroyed_alert", part_name, comp_name)
	
	# CRITICAL COMPONENTS - Instant effects
	if comp_name == "cockpit":
		die(last_damage_source, last_damage_weapon)
		return
	
	if comp_name == "core_shell":
		emit_signal("core_shell_destroyed")
		enter_flagged_state()  # Use the new function
		return
	
	# MOBILITY COMPONENTS
	if "mobility" in comp.tags:
		# Count destroyed mobility components
		var mobility_loss = 0.0
		if comp_name == "left_leg_actuator" or comp_name == "right_leg_actuator":
			mobility_loss = 0.25  # Lose 25% mobility per leg
		elif comp_name == "tracks":
			mobility_loss = 0.5  # Lose 50% mobility if tracks destroyed
		elif comp_name == "suspension":
			mobility_loss = 0.15  # Lose 15% mobility
		
		disabled_systems.mobility = max(disabled_systems.mobility - mobility_loss, 0.0)
		emit_signal("system_degraded", "mobility", disabled_systems.mobility)
		
		# Update actual movement speed
		if build.chassis:
			var reduced_speed = build.chassis.max_speed * disabled_systems.mobility
			update_speed(reduced_speed, build.chassis.move_acc, build.chassis.friction, build.chassis.rotation_acc)
	
	# WEAPON COMPONENTS
	if "weapon" in comp.tags:
		# Weapon feed destroyed = weapon offline
		if comp_name == "weapon_feed":
			if part_name == "left_shoulder":
				disabled_systems.left_arm_weapon = true
				emit_signal("system_degraded", "left_arm_weapon", 0.0)
				print("    -> Left arm weapon OFFLINE")
			elif part_name == "right_shoulder":
				disabled_systems.right_arm_weapon = true
				emit_signal("system_degraded", "right_arm_weapon", 0.0)
				print("    -> Right arm weapon OFFLINE")
	
	# HEAT MANAGEMENT
	if comp_name == "radiator":
		disabled_systems.heat_dispersion = 0.5  # Lose 50% heat dispersion
		emit_signal("system_degraded", "heat_dispersion", disabled_systems.heat_dispersion)
	
	# SENSORS
	if comp_name == "optics":
		disabled_systems.sensors = 0.5  # Reduced to backup optics
		emit_signal("system_degraded", "sensors", disabled_systems.sensors)
	elif comp_name == "backup_optics":
		if components.head["optics"].disabled:
			disabled_systems.sensors = 0.1  # Nearly blind
			emit_signal("system_degraded", "sensors", disabled_systems.sensors)
	
	# GENERATOR
	if comp_name == "generator":
		disabled_systems.shield_regen = 0.0
		emit_signal("system_degraded", "shield_regen", 0.0)
	
	# THRUSTER
	if comp_name == "thruster":
		pass
		# Thruster already checked in dash() function via build.thruster
		
func refresh_dynamic_components():
	# Refresh wetware components in core
	if build.core:
		# Remove old wetware if present
		if components.core.has("generator"):
			components.core.erase("generator")
		if components.core.has("chipset"):
			components.core.erase("chipset")
		if components.core.has("thruster"):
			components.core.erase("thruster")
		
		# Add current wetware
		if build.generator:
			components.core["generator"] = {
				"hp": 3, "max_hp": 3,
				"tags": ["internal"],
				"weight": 1.0,
				"disabled": false
			}
		if build.chipset:
			components.core["chipset"] = {
				"hp": 2, "max_hp": 2,
				"tags": ["internal"],
				"weight": 1.0,
				"disabled": false
			}
		if build.thruster:
			components.core["thruster"] = {
				"hp": 3, "max_hp": 3,
				"tags": ["internal"],
				"weight": 1.0,
				"disabled": false
			}
		
		#Add shoulder weapon components to core
		for weapon in [build.shoulder_weapon_left, build.shoulder_weapon_right]:
			if weapon and "additional_components" in weapon:
				for comp_data in weapon.additional_components:
					components.core[comp_data.name] = {
						"hp": comp_data.hp,
						"max_hp": comp_data.max_hp,
						"tags": comp_data.tags.duplicate(),
						"weight": comp_data.weight,
						"disabled": false
					}
	
	# Refresh weapon feeds and arm weapon components in shoulders
	if build.shoulders:
		# Left shoulder
		# First, remove all weapon-related components
		var left_to_remove = []
		for comp_name in components.left_shoulder:
			var comp = components.left_shoulder[comp_name]
			if "weapon" in comp.tags:
				left_to_remove.append(comp_name)
		for comp_name in left_to_remove:
			components.left_shoulder.erase(comp_name)
		
		# Add weapon feed if arm weapon equipped
		if build.arm_weapon_left:
			components.left_shoulder["weapon_feed"] = {
				"hp": 1, "max_hp": 1,
				"tags": ["external", "weapon"],
				"weight": 1.0,
				"disabled": false
			}
			#Add arm weapon's additional components
			if "additional_components" in build.arm_weapon_left:
				for comp_data in build.arm_weapon_left.additional_components:
					components.left_shoulder[comp_data.name] = {
						"hp": comp_data.hp,
						"max_hp": comp_data.max_hp,
						"tags": comp_data.tags.duplicate(),
						"weight": comp_data.weight,
						"disabled": false
					}
		
		# Right shoulder
		var right_to_remove = []
		for comp_name in components.right_shoulder:
			var comp = components.right_shoulder[comp_name]
			if "weapon" in comp.tags:
				right_to_remove.append(comp_name)
		for comp_name in right_to_remove:
			components.right_shoulder.erase(comp_name)
		
		# Add weapon feed if arm weapon equipped
		if build.arm_weapon_right:
			components.right_shoulder["weapon_feed"] = {
				"hp": 1, "max_hp": 1,
				"tags": ["external", "weapon"],
				"weight": 1.0,
				"disabled": false
			}
			#Add arm weapon's additional components
			if "additional_components" in build.arm_weapon_right:
				for comp_data in build.arm_weapon_right.additional_components:
					components.right_shoulder[comp_data.name] = {
						"hp": comp_data.hp,
						"max_hp": comp_data.max_hp,
						"tags": comp_data.tags.duplicate(),
						"weight": comp_data.weight,
						"disabled": false
					}

func debug_print_components():
	print("\n=== MECHA COMPONENT DEBUG ===")
	print("Mecha: ", mecha_name)
	print("\n--- ARMOR VALUES ---")
	for part_name in armor.keys():
		if armor[part_name].has("front"):  # Check if this part has armor
			print(part_name.to_upper(), ":")
			for facing in ["front", "side", "rear"]:
				var armor_data = armor[part_name][facing]
				print("  ", facing, ": Level ", armor_data.level, " | Pips ", armor_data.pips)
	
	print("\n--- COMPONENTS ---")
	for part_name in components.keys():
		if components[part_name].size() > 0:
			print(part_name.to_upper(), ":")
			var total_weight = 0.0
			for comp_name in components[part_name]:
				var comp = components[part_name][comp_name]
				total_weight += comp.weight
				var tags_str = ", ".join(comp.tags)
				print("  ", comp_name, ": HP ", comp.hp, "/", comp.max_hp, 
					  " | Weight ", comp.weight, " | Tags [", tags_str, "]", 
					  " | Disabled: ", comp.disabled)
			print("  TOTAL WEIGHT: ", total_weight)
			
			# Show probability percentages
			print("  HIT CHANCES:")
			for comp_name in components[part_name]:
				var comp = components[part_name][comp_name]
				var chance = (comp.weight / total_weight) * 100.0
				print("    ", comp_name, ": ", "%.1f" % chance, "%")
	
	print("\n--- DISABLED SYSTEMS ---")
	for system_name in disabled_systems.keys():
		var value = disabled_systems[system_name]
		if typeof(value) == TYPE_BOOL:
			print(system_name, ": ", "OFFLINE" if value else "ONLINE")
		else:  # Float multiplier
			print(system_name, ": ", "%.1f" % (value * 100.0), "%")
	
	print("=============================\n")

func enter_flagged_state():
	if is_exposed:
		return  # Already flagged
	
	is_exposed = true
	emit_signal("flagged")
	emit_signal("exposed", self)  # Keep old signal for compatibility
	print("!!! MECH FLAGGED !!!")

func spawn_component_damage_explosion(part_name: String, is_destroyed: bool):
	var explosion = PART_DESTRUCTION_EXPLOSION.instantiate()
	get_parent().add_child(explosion)
	
	explosion.global_position = get_part_global_position(part_name)
	
	# Scale based on part size and damage severity
	var base_scale = 1.0
	match part_name:
		"core":
			base_scale = 0.5
		"chassis":
			base_scale = 0.7
		"head":
			base_scale = 0.4
		"left_shoulder", "right_shoulder":
			base_scale = 0.5
	
	if is_destroyed:
		base_scale *= 1.5
	
	explosion.scale = Vector2(base_scale, base_scale)
	
	# Random offset
	var offset = Vector2(randf_range(-10, 10), randf_range(-10, 10))
	explosion.global_position += offset
	
func get_part_global_position(part_name: String) -> Vector2:
	match part_name:
		"core":
			return Core.global_position
		"head":
			return Head.global_position
		"left_shoulder":
			return LeftShoulder.global_position
		"right_shoulder":
			return RightShoulder.global_position
		"chassis":
			# Use the active chassis node
			if SingleChassis.texture:
				return SingleChassis.global_position
			elif LeftChassis.texture:
				# Return center between legs
				return (LeftChassis.global_position + RightChassis.global_position) / 2.0
			else:
				return global_position
		_:
			return global_position  # Fallback to mech center


func estimate_threat_level() -> float:
	# Returns 0.0 (helpless) to 1.0 (full strength)
	var threat := 0.0

	# Armor integrity (30%) — remaining pips across all parts/facings
	var total_pips := 0
	var max_pips := 0
	for part_name in armor:
		for facing in armor[part_name]:
			var face = armor[part_name][facing]
			if face.level > 0:  # only count equipped facings
				total_pips += face.pips
				max_pips += 3  # all facings start with 3 pips
	if max_pips > 0:
		threat += (float(total_pips) / float(max_pips)) * 0.3
	else:
		threat += 0.3

	# Component health (25%) — average hp/max_hp across all components
	var comp_total := 0.0
	var comp_count := 0
	for part_name in components:
		for comp_name in components[part_name]:
			var comp = components[part_name][comp_name]
			if comp.max_hp > 0:
				comp_total += float(comp.hp) / float(comp.max_hp)
			comp_count += 1
	if comp_count > 0:
		threat += (comp_total / float(comp_count)) * 0.25
	else:
		threat += 0.25

	# Systems functional (15%) — working weapons + system multipliers
	var working_weapons := 0.0
	var weapon_slots := ["left_arm_weapon", "right_arm_weapon", "left_shoulder_weapon", "right_shoulder_weapon"]
	for slot in weapon_slots:
		if not disabled_systems[slot]:
			working_weapons += 0.25
	var sys_avg := (disabled_systems.mobility + disabled_systems.sensors + disabled_systems.heat_dispersion) / 3.0
	threat += (working_weapons * 0.5 + sys_avg * 0.5) * 0.15

	# Heat state (15%) — worse of internal vs external temp
	if overheat_temp > 0:
		var heat_ratio = maxf(internal_temp, external_temp) / overheat_temp
		threat += (1.0 - clampf(heat_ratio, 0.0, 1.0)) * 0.15
	else:
		threat += 0.15

	# Flagged/status (15%)
	if is_exposed:
		pass  # 0.0 contribution
	elif has_any_status():
		threat += 0.075  # halved
	else:
		threat += 0.15

	return clampf(threat, 0.0, 1.0)
