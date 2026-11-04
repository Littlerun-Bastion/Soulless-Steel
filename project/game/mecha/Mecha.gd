extends CharacterBody2D
class_name Mecha

# hi this edit comes from my tablet!

# Tracks which core part_names have already triggered the missing-coolant
# warning, so set_core() doesn't spam push_warning every time a mech respawns.
static var _warned_missing_coolant: Dictionary = {}

enum MODES {NEUTRAL, RELOAD, ACTIVATING_LOCK, LOCK}
enum SIDE {LEFT, RIGHT, SINGLE}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

const DECAL = preload("res://game/mecha/Decal.tscn")
const MINE = preload("res://database/parts/mine.gd")
const HITBOX = preload("res://game/mecha/Hitbox.tscn")
const PART_DESTRUCTION_EXPLOSION = preload("res://game/weapons/PartDestructionExplosion.tscn")
const COMPONENT_EXPLOSION_THROTTLE_MS := 100
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
## The emergency Flag (enter_flagged_state): how long (s) the mecha takes no
## damage of any kind after entering it, and how often (s) the wound spurts
## while it stays Flagged. Placeholders.
const FLAG_GRACE_TIME := 4.0
const FLAG_HEARTBEAT_TIME := 1.0
const FLAG_SPURT_AMOUNT := 12
const FLAG_SPURT_LIFETIME := 1.5
const FLAG_SFX := "large_impact1"
## The Flag (raise_flag, lower_flag): lowering it takes this long (s), a
## visible wind-up; raising it is instant. The pilot whose damage pressed the
## mecha into its Flag is the one that did the most in the last
## PRESSURE_WINDOW s. Placeholders.
const FLAG_LOWER_TIME := 1.5
const PRESSURE_WINDOW := 15.0
## What a pip of component damage counts for against hp damage, in pressure.
const PRESSURE_PER_PIP := 5.0
const FLAG_RAISE_SFX := "select"
const FLAG_LOWER_SFX := "back"
## Bleeding from the Hardware parts' internal components (the tag below on
## any component of these parts). The mecha drips (Blood1) once WOUND_BLEED
## of their internal hp is gone, and more (Blood2) past WOUND_HEAVY_BLEED.
## Each hit on one leaks a few drops (WOUND_LEAK of a full spray), and a hit
## that destroys one throws a small splatter. Placeholders.
const WOUND_PARTS := ["chassis", "left_shoulder", "right_shoulder", "core", "head"]
const WOUND_TAG := "internal"
const WOUND_BLEED := 0.1
const WOUND_HEAVY_BLEED := 0.4
const WOUND_LEAK := 0.2
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
const FALLBACK_FRICTION := 0.01
const FALLBACK_MOVE_HEAT := 0.0
const FALLBACK_ROTATION_ACC := 5.0
const FALLBACK_TRIM_ACC := 5.0

signal create_projectile
signal create_casing
signal shoot_signal
signal took_damage
signal died
# Equipping a core with less cargo space pushed these stacks out of the cargo
# (the Hangar moves them to the stash).
signal cargo_overflow(stacks)
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
# The emergency Flag began (enter_flagged_state). attacker is the mecha (or
# Entity) whose damage caused it, from last_damage_source, or null.
signal emergency_flagged(mecha, attacker)
# The Flag went up (raise_flag, or the emergency state): `voluntary` is
# whether the pilot chose it; `pressured_by` the mecha (or Entity) whose
# damage pressed it most in the last PRESSURE_WINDOW s, or null.
signal flag_raised(mecha, voluntary: bool, pressured_by)
# The pilot started lowering its Flag (the wind-up), and the Flag is down.
signal flag_lowering_started(mecha)
signal flag_lowered(mecha)
# say(): CombatScene shows it to the player if they hear it.
signal spoke(mecha, text: String, seconds: float, always_heard: bool)
# Someone's sweep found this mecha (see sweep). Says nothing of who or where.
signal swept
# One of this mecha's devices (a ward, a drone) was destroyed (Device).
signal device_destroyed(device)
# Its IR illuminator went on or off (set_illuminator).
signal illuminator_toggled(on: bool)

## How long (s) a speech box stays up by default. Placeholder.
const SPEECH_TIME := 3.0


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
@onready var FireGlow = $FireGlow

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
## What this mecha knows about where others are (see ContactStore). Its
## clock runs in _physics_process, so it stops while the mecha is paused.
## An NPC advances it itself, with its thinking time (Enemy.update_senses).
var contacts := ContactStore.new()
var contacts_auto_advance := true
## The tag of this mecha's squad, shown before its callsign in Local ("" for
## none, and for an Anonymous squad).
var squad_tag := ""
## The name other pilots see (Local, name tags, speech). mecha_name stays the
## internal name (is_player, kill credit, stage actors). "" until the mecha
## joins Local, which gives an NPC one from the callsign list.
var callsign := ""
## An Anonymous pilot isn't on the Local roster, gets no join or leave
## lines, shows no name tag and is "Unknown" when it speaks. Fixed for the
## match.
var is_anonymous := false
## Active sensors (sweeps; later drones, wards, the Seeker) find this mecha
## only within (1 - sensor_reduction) of their range. Set by an ECM module.
var sensor_reduction := 0.0
## Seconds until this mecha can sweep again.
var sweep_cooldown := 0.0
## The internal bay part's state (see INTERNAL BAY): charges left, seconds
## until it can be used again, and whether a passive part is switched on.
var internal_charges := 0
var internal_cooldown := 0.0
var internal_on := false
## A Seeker that was shot down is gone until the part is fitted again.
var internal_lost := false
var _biosensor_timer := randf()
var paused = false
var controls_locked = false
var is_dead = false
var cur_mode = MODES.NEUTRAL
var arena = false
var is_inside_building = false
var is_entering_building = false
var is_exposed = false
var _last_component_explosion_ms := {}  # part_name -> Time.get_ticks_msec() of last spawn; throttles VFX spam
var _last_shield_particle_amount: int = -1  # Caches the previous shield particle amount so we only reassign on change — writing GPUParticles2D.amount reallocates GPU buffers and causes a micro-stutter.
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
## Seconds left of the emergency Flag's grace window (0 outside it).
var flag_grace := 0.0
## The Flag: up (weapons locked, others expected to hold fire), whether the
## pilot raised it by choice, and the seconds left of the wind-up while it is
## being lowered (0 otherwise). is_exposed is the emergency state (the cockpit
## exposed, exposed_hits counting), which lowering the Flag doesn't end.
var flag_up := false
var flag_voluntary := false
var flag_lowering := 0.0
## Damage taken lately, for pressured_by: [{body, time, amount}].
var _pressure: Array[Dictionary] = []
## Extra aim bloom (degrees) an NPC adds under panic (Enemy).
var extra_bloom := 0.0
var _heartbeat := 0.0
var _flag_marker: FlagMarker = null
var _spurt: GPUParticles2D = null
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
# NPC tanks' own driving velocity, kept apart from dash and knockback moves.
var _tank_drive_velocity := Vector2.ZERO
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
## Built when it dies (KillRecord): who killed it, with what, from where, and
## what it knew. Empty while alive.
var kill_record := {}
## Whether its IR illuminator is on (set_illuminator).
var illuminator_on := true
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
	"internal": null,
}
# Grades of the fitted parts: build slot -> grade (Grades). Missing means
# Standard. Set it before the parts are fitted (set_parts_from_design) so the
# stats they set up include it; get_stat applies it to Grades.GRADED_STATS.
var part_grades := {}

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

# Designator salvos still firing: {"slot", "point", "left" (rounds), "wait" (s
# until the next round)}. See fire_at_point.
var _salvos: Array[Dictionary] = []

var thruster_cooldown = 0.0

var ecm_attempt_cooldown = 0.0
var ecm_strength_difference = 0.0

var bleed_timer = 0.0
## How much of the Hardware parts' internal component hp is gone, 0 to 1
## (get_internal_wound), kept up to date when components change.
var internal_wound := 0.0
var _wound_dirty := true

func _ready():
	# duplicate(false) keeps the underlying Shader resource shared across
	# instances (shaders are stateless — per-instance state lives in
	# shader_parameter values, which duplicate(false) still copies). The
	# previous deep duplicate(true) cloned the Shader 30 times per
	# Mecha._ready (~200ms per spawn), which was the dominant cost of NPC
	# spawning and the cause of the visible hitch on world population +
	# soft-spawns.
	for node in [Core, Head, HeadPort,\
				LeftShoulder, RightShoulder,\
				LeftArmWeaponMain, RightArmWeaponMain,\
				LeftShoulderWeaponMain, RightShoulderWeaponMain,\
				SingleChassis, LeftChassis, RightChassis]:
		node.material = Core.material.duplicate(false)
	for node in [CoreSub, HeadSub,\
				LeftArmWeaponSub, RightArmWeaponSub,\
				LeftShoulderWeaponSub, RightShoulderWeaponSub,\
				SingleChassisSub, LeftChassisSub, RightChassisSub]:
		node.material = CoreSub.material.duplicate(false)
	for node in [CoreGlow, HeadGlow,\
				LeftArmWeaponGlow, RightArmWeaponGlow,\
				LeftShoulderWeaponGlow, RightShoulderWeaponGlow,\
				SingleChassisGlow, LeftChassisGlow, RightChassisGlow]:
		node.material = CoreGlow.material.duplicate(false)
	global_rotation_degrees = randf_range(0, 360)
	Illumination.style_lights(self)
	$FireGlow.energy = 0.0
	$FireGlow.enabled = false

	if mech_inventory == null:
		mech_inventory = Inventory.new()

	# Mechas bump into and push map vehicles (see VehicleField).
	set_collision_mask_value(MapSenses.VEHICLE_LAYER, true)
	set_collision_mask_value(MapSenses.HEAVY_VEHICLE_LAYER, true)
	device_destroyed.connect(_on_own_device_destroyed)


func _physics_process(dt):
	if paused:
		return
	var profile_start := FrameProfiler.start()
	_physics_step(dt)
	FrameProfiler.add("mecha", profile_start)


# The body of _physics_process (one return point for the profiler).
func _physics_step(dt):
	if contacts_auto_advance:
		contacts.advance(dt)
	flag_grace = maxf(flag_grace - dt, 0.0)
	if flag_lowering > 0.0:
		flag_lowering = maxf(flag_lowering - dt, 0.0)
		if _flag_marker:
			_flag_marker.lowering = 1.0 - flag_lowering / FLAG_LOWER_TIME
		if flag_lowering <= 0.0:
			_finish_lowering()
	sweep_cooldown = maxf(sweep_cooldown - dt, 0.0)
	internal_cooldown = maxf(internal_cooldown - dt, 0.0)
	var sounds_start := FrameProfiler.start()
	_update_biosensor(dt)
	generate_passive_sounds(dt)
	FrameProfiler.add("    sounds (in mecha)", sounds_start)

	# Mines round this mecha react to it (mine.gd): a grid lookup, no physics.
	if not is_dead:
		var mines_start := FrameProfiler.start()
		MINE.check_mecha(self)
		FrameProfiler.add("    mines (in mecha)", mines_start)

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

	#Blood: drips from damaged internal components
	if _wound_dirty:
		_wound_dirty = false
		internal_wound = get_internal_wound()
	if internal_wound >= WOUND_BLEED:
		bleed_timer = max(bleed_timer - dt, 0.0)
		if bleed_timer <= 0.0:
			bleed_timer = randf_range(1, 1.1 / internal_wound)
			Particle.blood[0].emitting = !Particle.blood[0].emitting
			if internal_wound >= WOUND_HEAVY_BLEED:
				Particle.blood[1].emitting = !Particle.blood[1].emitting
			else:
				Particle.blood[1].emitting = false
	
	if is_exposed:
		exposed_invuln_timer = min(exposed_invuln_timer + dt, EXPOSED_INVULN_WINDOW)
		# The wound spurts in time with a heartbeat while Flagged.
		_heartbeat -= dt
		if _heartbeat <= 0.0:
			_heartbeat = FLAG_HEARTBEAT_TIME
			if _spurt:
				_spurt.restart()

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

	#Bloom — direct member access (avoids per-frame get()/set() string reflection)
	if right_arm_bloom_time > 0: right_arm_bloom_time = max(right_arm_bloom_time - dt, 0.0)
	else: right_arm_bloom_count = 0
	if left_arm_bloom_time > 0: left_arm_bloom_time = max(left_arm_bloom_time - dt, 0.0)
	else: left_arm_bloom_count = 0
	if right_shoulder_bloom_time > 0: right_shoulder_bloom_time = max(right_shoulder_bloom_time - dt, 0.0)
	else: right_shoulder_bloom_count = 0
	if left_shoulder_bloom_time > 0: left_shoulder_bloom_time = max(left_shoulder_bloom_time - dt, 0.0)
	else: left_shoulder_bloom_count = 0

	if not _salvos.is_empty():
		_process_salvos(dt)

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
	# Only reassign on change — see _last_shield_particle_amount declaration.
	var new_shield_particle_amount: int = max(1, int(ceil(SHIELD_PARTICLE_AMOUNT * (shield / max_shield))))
	if new_shield_particle_amount != _last_shield_particle_amount:
		_last_shield_particle_amount = new_shield_particle_amount
		$ParticlesLayer3/ShieldRing.amount = new_shield_particle_amount
		$ParticlesLayer3/ShieldStartup.amount = new_shield_particle_amount

	#Handle sprinting momentum
	sprinting_ending_correction *= 1.0 - min(SPRINTING_COOLDOWN_SPEED*dt, 1.0)

	#Handle collisions with other mechas and movement
	if not is_stunned() and not is_movement_locked():
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			var other = collision.get_collider() if collision else null
			if other and other.is_in_group("mecha"):
				lock_movement(0.1)
				break
	else:
		if sprinting_ending_correction.length():
			move(sprinting_ending_correction)
		else:
			apply_movement(dt, Vector2())

	#Update shoulder weapons rotation
	if build.shoulder_weapon_left:
		LeftShoulderWeapon.rotation_degrees += get_best_rotation_diff(LeftShoulderWeapon.rotation_degrees, 0) * build.shoulder_weapon_left.rotation_acc * dt
	if build.shoulder_weapon_right:
		RightShoulderWeapon.rotation_degrees += get_best_rotation_diff(RightShoulderWeapon.rotation_degrees, 0) * build.shoulder_weapon_right.rotation_acc * dt

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
	var anim_start := FrameProfiler.start()
	if build.chassis and build.chassis.is_legs:
		if moving and not MovementAnimation.is_playing() and\
		not is_sprinting and dash_velocity.length() <= 0.0:
			MovementAnimation.play("Walking")
		elif (not moving and velocity.length() <= 2.0) or\
		(is_sprinting or dash_velocity.length() > 0):
			MovementAnimation.stop()
		if not MovementAnimation.is_playing():
			speed_modifier = min(speed_modifier + SPEED_MOD_CORRECTION*dt, 1.0)
	FrameProfiler.add("    anim (in mecha)", anim_start)

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
	var heat_start := FrameProfiler.start()
	update_heat(dt)
	FrameProfiler.add("    heat (in mecha)", heat_start)
	if not entity_slow_stacks.is_empty():
		_update_entity_slow(dt)
	if not ticks.is_empty() or not _fading_ticks.is_empty():
		_update_ticks(dt)
	if battery < battery_capacity and not has_status("electrified"):
		battery = min(battery + battery_recharge_rate*dt, battery_capacity)
	for status in status_time:
		if status == "overheating":
			continue  # Managed by thermal system, not timer
		decrease_status(status, dt)
	# The looks of it (particles, glows), skipped on frames a mecha off
	# screen doesn't need them (wants_visuals); the state they show is kept
	# in the fields above, so they catch up when it is next drawn.
	var visuals: bool = wants_visuals()
	if visuals:
		for status in STATUS_PARTICLES:
			var on: bool = has_status(status)
			for node in Particle[status]:
				if node.emitting != on:
					node.emitting = on
	if has_status("fire"):
		FireGlow.energy = min(FireGlow.energy + dt*2, 3)
	elif FireGlow.energy > 0.0:
		FireGlow.energy = max(FireGlow.energy - dt*2, 0)
	# Off while not burning: Godot lights each canvas item with at most 16
	# lights, and a glow at zero energy would still take one.
	var glowing: bool = FireGlow.energy > 0.0
	if FireGlow.enabled != glowing:
		FireGlow.enabled = glowing


	#Thrusters cooldowns
	for dir in DASH_DIRS:
		var is_ready = dash_cooldown[dir] <= 0
		dash_cooldown[dir] = max(dash_cooldown[dir] - dt, 0.0)
		if visuals:
			var cooling: bool = dash_cooldown[dir] > 0
			if Particle.dash[dir].cooldown.emitting != cooling:
				Particle.dash[dir].cooldown.emitting = cooling
		if dash_cooldown[dir] <= 0 and not is_ready:
			Particle.dash[dir].ready.emitting = true
	if visuals:
		update_dash_cooldown_visuals()

	take_status_damage(dt)

	process_hitboxes(dt)

	if visuals and build.chassis and build.chassis.hover_particles and not display_mode:
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


## The statuses with particle effects, and the dash directions, as constants
## so the frame loop allocates no lists.
const STATUS_PARTICLES := ["fire", "electrified", "freezing", "corrosion", "overheating"]
const DASH_DIRS := ["fwd", "rwd", "left", "right"]


## Whether this frame's looks (particles, glows, cooldown visuals) are worth
## updating: always for a mecha that may be on screen. An NPC off screen
## updates them now and then (Enemy.wants_visuals).
func wants_visuals() -> bool:
	return true


func set_pause(value):
	paused = value


func get_design_data():
	var data = {}
	for part_type in build.keys():
		var part = build[part_type]
		data[part_type] = part.part_id if part else false
	return data


func set_parts_from_design(data):
	# A design without an optional slot (older designs and saves have no
	# "internal") leaves it empty.
	for part_name in ["head", "core", "shoulders", "generator", "chipset", "chassis",\
					"thruster", "arm_weapon_left", "arm_weapon_right", "shoulders", \
					"shoulder_weapon_left", "shoulder_weapon_right", "internal"]:
		var type = part_name.replace("_left", "").replace("_right", "")
		var side = false
		if part_name.find("left") != -1:
			side = SIDE.LEFT
		elif part_name.find("right") != -1:
			side = SIDE.RIGHT

		if typeof(side) == TYPE_INT:
			callv("set_" + type, [data.get(part_name, false), side])
		else:
			callv("set_" + type, [data.get(part_name, false)])
	
	refresh_dynamic_components()

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
	if is_dead or is_in_flag_grace():
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
	if amount > 0:
		_shake_ticks(1)

	last_damage_source = source_info
	last_damage_weapon = weapon_name
	_note_attack(source_info)
	_note_pressure(source_info, float(amount) * float(health_mult))

	if hp <= 0 and not is_exposed:
		enter_flagged_state()
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
		# Restore via the timer's signal, not an await on this mecha: if the
		# mecha is freed mid-hitstop (death, scene change), an awaiting
		# coroutine dies with it and the game stays stuck at 10% speed.
		# The lambda captures no instance state, so it survives the free.
		get_tree().create_timer(HITSTOP_DURATION * HITSTOP_TIMESCALE).timeout.connect(
			func(): Engine.time_scale = 1.0
		)


# The status checks run many times a frame per mecha; the assert's message
# is only built once a name is wrong (an assert's arguments are evaluated
# every call in a debug build).
func has_status(status_name):
	if not status_time.has(status_name):
		assert(false, "Not a valid status name: " + str(status_name))
	return status_time[status_name] > 0.0


func has_any_status():
	for status in status_time.values():
		if status > 0.0:
			return true
	return false


func set_status(status_name, amount):
	if not status_time.has(status_name):
		assert(false, "Not a valid status name: " + str(status_name))
	status_time[status_name] = amount


func decrease_status(status_name, amount):
	if not status_time.has(status_name):
		assert(false, "Not a valid status name: " + str(status_name))
	status_time[status_name] = max(status_time[status_name] - amount, 0.0)


func take_status_damage(dt):
	if is_dead or is_in_flag_grace():
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
			enter_flagged_state()
		else:
			hp = round(max(hp - (dt * (hp/100.0)), 1))
		emit_signal("took_damage", self, true)

func overheat_damage_tick():
	# Gather all living components across all parts
	var candidates = []
	for part_name in components.keys():
		for comp_name in components[part_name]:
			var comp = components[part_name][comp_name]
			if not comp.disabled and comp.hp > 0:
				if is_protected(part_name, comp_name):
					continue
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

func die(source_info, weapon_name):
	if is_dead:
		return
	is_dead = true
	kill_record = KillRecord.build(self, source_info, weapon_name)
	_drop_all_ticks()

	# The Flag is over; the blood pools under what will be the wreck.
	if _flag_marker:
		_flag_marker.queue_free()
		_flag_marker = null
	if _spurt:
		_spurt.emitting = false
	var stains := BloodStains.find(self)
	if stains:
		stains.add_pool(global_position)

	#Update sfxs
	if ChassisAmbientSFX.stream:
		ChassisAmbientSFX.stop()
	if GeneratorAmbientSFX.stream:
		GeneratorAmbientSFX.stop()
	
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(self):
		return
	#TickerManager.new_message({
	#	"type": "mecha_died",
	#	"source": source_info.name,
	#	"self": self.mecha_name,
	#	"weapon_name": weapon_name,
	#	})
	emit_signal("died", self)


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
		return  # Head/chassis hits — no decal nodes for these parts
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


## Heat an Entity sucks out of the mecha (a Coyote's bite, a Fisher's drain,
## a tick), in kJ: first the heat still waiting to enter the system, then the
## external layer (its signature), then the coolant. external_only takes it
## from the external layer alone. Never below ambient. Returns the kJ taken.
func drain_heat(amount_kj: float, external_only := false) -> float:
	var left := maxf(amount_kj, 0.0)
	if not external_only:
		var from_pending := minf(pending_heat_kj, left)
		pending_heat_kj -= from_pending
		left -= from_pending
	var from_external := minf(external_temp * external_capacity, left)
	external_temp = maxf(external_temp - from_external / external_capacity, 0.0)
	left -= from_external
	if not external_only:
		var from_internal := minf(internal_temp * internal_capacity, left)
		internal_temp = maxf(internal_temp - from_internal / internal_capacity, 0.0)
		left -= from_internal
	return maxf(amount_kj, 0.0) - left


# ---- Entity slow ----
# A Coyote's bite drags at the mecha: each one adds a stack of slow that wears
# off on its own after its duration. Stacks add up to ENTITY_SLOW_MAX_STACKS;
# past that a new one replaces the one closest to wearing off. Applied once to
# the target speed in apply_movement(), whatever the movement type.

const ENTITY_SLOW_PER_STACK := 0.12
const ENTITY_SLOW_MAX_STACKS := 4

var entity_slow_stacks: Array[float] = []  # seconds left on each stack


func add_entity_slow(duration: float) -> void:
	entity_slow_stacks.append(duration)
	if entity_slow_stacks.size() > ENTITY_SLOW_MAX_STACKS:
		entity_slow_stacks.sort()
		entity_slow_stacks.remove_at(0)


## Speed multiplier from Entity slow: 1.0 with none.
func get_entity_slow() -> float:
	return 1.0 - ENTITY_SLOW_PER_STACK * entity_slow_stacks.size()


func _update_entity_slow(dt: float) -> void:
	for i in range(entity_slow_stacks.size() - 1, -1, -1):
		entity_slow_stacks[i] -= dt
		if entity_slow_stacks[i] <= 0.0:
			entity_slow_stacks.remove_at(i)

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
		
		# Route through ventilation split 
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
	# Pass external_temp as the visual glow reference for now. The weapons'
	# heat tint is only written on frames the mecha is drawn (wants_visuals).
	var visuals: bool = wants_visuals()
	var cooling: float = get_effective_cooling()
	LeftArmWeapon.update_heat(cooling, external_temp, dt, visuals)
	RightArmWeapon.update_heat(cooling, external_temp, dt, visuals)
	LeftShoulderWeapon.update_heat(cooling, external_temp, dt, visuals)
	RightShoulderWeapon.update_heat(cooling, external_temp, dt, visuals)

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
	# The heat tint of the body sprites: 18 shader parameter writes, so only
	# when the value changed, and only on frames the mecha is drawn. A mecha
	# coming back on screen catches up on its first drawn frame.
	if visuals and shader_heat_value != _shader_heat_shown:
		_shader_heat_shown = shader_heat_value
		if _heat_nodes.is_empty():
			_heat_nodes = [Core, CoreSub, CoreGlow, Head, HeadSub, HeadGlow, HeadPort, LeftShoulder, RightShoulder,\
					SingleChassis, SingleChassisSub, SingleChassisGlow, LeftChassis, LeftChassisSub, LeftChassisGlow,\
					RightChassis, RightChassisSub, RightChassisGlow]
		for node in _heat_nodes:
			node.material.set_shader_parameter("heat", shader_heat_value)


# The heat value last written to the body sprites' shaders, and those sprites
# (gathered on first use; see update_heat).
var _shader_heat_shown := -1.0
var _heat_nodes: Array = []

# Returns a 0-1 normalized thermal signature for detection systems
# 0.0 = at ambient (invisible), 1.0 = extremely hot
# Each tick on the mecha glows TICK_GLOW on top of its real heat.
func get_thermal_signature() -> float:
	# Normalize against a reference "very hot" value
	# 150°C above ambient is considered max detection signature
	return clamp(external_temp / 150.0 + TICK_GLOW * ticks.size(), 0.0, 1.0)

# Returns absolute external temperature in °C (for display / fuse checks)
func get_external_temp_absolute() -> float:
	return AMBIENT_TEMP + external_temp

func get_effective_cooling() -> float:
	if not build.generator:
		return 0.0
	return build.generator.cooling_power * disabled_systems.heat_dispersion
	


## entities_only: only creatures hear it (a sweep), not mechas.
func create_sound(volume_type, type, max_distance, entities_only := false):
	emit_signal("made_sound", {
		"volume_type": volume_type,
		"type": type,
		"position": global_position,
		"max_distance": max_distance,
		"source": self,
		"entities_only": entities_only,
	})


# IR ILLUMINATOR
#
# Every mecha's MechaLight is its IR illuminator: a cone of light ahead of it.
# On, the mecha and whatever its cone falls on are lit, and lit bodies are
# seen from anywhere their light shows, walls between or not
# (Illumination). Off, its cone goes dark and the mecha is seen only the
# usual way, but it sees less itself: the player only by peripheral sight and
# other mechas' light, an NPC at a shorter range (Enemy.DARK_SIGHT_MULT). The
# player switches it with the illuminator key; NPC behaviours pick it by state
# (BaseBehaviour.dark_states).

func set_illuminator(on: bool) -> void:
	if on == illuminator_on:
		return
	illuminator_on = on
	var light := Illumination.light_of(self)
	if light:
		light.enabled = on
	illuminator_toggled.emit(on)


# SENSOR SWEEP
#
# Every mecha has a sweep, like a directional scan: a cone from the mecha,
# SWEEP_RANGE long and from SWEEP_MIN_WIDTH to 360 degrees wide. It reports
# what is in the cone by kind ("mech", or an Entity's species) with counts,
# and nothing else: no positions, directions or distances. A narrow cone
# tells more only by what it leaves out. Walls don't block it. A mecha with
# sensor_reduction (ECM) is only found within (1 - sensor_reduction) of the
# range; further out it simply isn't there.
#
# It costs SWEEP_HEAT kJ (about a dash) and SWEEP_COOLDOWN s. Every mecha it
# finds gets the swept signal (the player sees "YOU WERE SWEPT"); creatures
# hear it as a loud sound at the sweeper (Entity.hears_sweeps), mechas don't.
# Sweeps never write contacts. The player aims one with the sweep key
# (Player, "SENSOR SWEEP"); NPC code calls sweep() directly.

## Placeholders.
const SWEEP_RANGE := 10000.0
const SWEEP_MIN_WIDTH := 10.0
const SWEEP_MAX_WIDTH := 360.0
const SWEEP_HEAT := 650.0
const SWEEP_COOLDOWN := 10.0
## How far (px) creatures hear a sweep.
const SWEEP_SOUND_RANGE := 10000.0


## "" if this mecha can sweep now, else why not: "dead", "cooldown".
func can_sweep() -> String:
	if is_dead:
		return "dead"
	if sweep_cooldown > 0.0:
		return "cooldown"
	return ""


## Sweeps a cone `width_deg` wide (clamped to SWEEP_MIN_WIDTH..360) along
## `direction`. Returns {"ok": true, "width": degrees, "counts": {kind:
## count}}, or {"ok": false, "reason": can_sweep()} if it can't sweep now.
func sweep(direction: Vector2, width_deg: float) -> Dictionary:
	var reason := can_sweep()
	if reason != "":
		return {"ok": false, "reason": reason}
	var width := clampf(width_deg, SWEEP_MIN_WIDTH, SWEEP_MAX_WIDTH)
	var counts := {}
	for body in sweep_finds(direction, width):
		var kind := ContactStore.kind_of(body)
		counts[kind] = counts.get(kind, 0) + 1
		if body.has_signal("swept"):
			body.swept.emit()
	increase_heat(SWEEP_HEAT)
	sweep_cooldown = SWEEP_COOLDOWN
	create_sound("loud", "sweep", SWEEP_SOUND_RANGE, true)
	return {"ok": true, "width": width, "counts": counts}


## A sweep's counts as text, mechs first, then species by name:
## "2 MECH · 3 STALKER", or "NO RETURNS".
static func describe_sweep(counts: Dictionary) -> String:
	if counts.is_empty():
		return "NO RETURNS"
	var kinds: Array = counts.keys()
	kinds.sort_custom(func(a, b): return (a == "mech" and b != "mech") or (a != "mech" and b != "mech" and str(a) < str(b)))
	var parts: Array[String] = []
	for kind in kinds:
		parts.append("%d %s" % [counts[kind], str(kind).to_upper()])
	return " · ".join(parts)


## The living mechas, decoys (counted as mechas; not this mecha's own) and
## Entities a sweep along `direction`, `width_deg` wide, would find. No side
## effects.
func sweep_finds(direction: Vector2, width_deg: float) -> Array:
	var found := []
	var half := deg_to_rad(width_deg) * 0.5
	var forward := direction.normalized() if direction != Vector2.ZERO else Vector2.UP.rotated(global_rotation)
	for group in ["mecha", "decoy", "entity"]:
		for body in get_tree().get_nodes_in_group(group):
			if body == self or not (body is Node2D) or body.get("is_dead") == true:
				continue
			if body.get("owner_mecha") == self:
				continue
			var offset: Vector2 = body.global_position - global_position
			var reduction = body.get("sensor_reduction")
			var reach := SWEEP_RANGE * (1.0 - clampf(float(reduction) if reduction != null else 0.0, 0.0, 1.0))
			if offset.length() > reach:
				continue
			if width_deg < SWEEP_MAX_WIDTH and absf(forward.angle_to(offset)) > half:
				continue
			found.append(body)
	return found


# INTERNAL BAY
#
# One optional part (build.internal, database/parts/internal.gd). use_internal
# is the one call for the player (the internal key, Player "INTERNAL BAY")
# and NPC code alike:
#   - a device part spends a charge and puts out its device (Device):
#       ward, decoy  at the mecha on a tap; thrown toward a point, at most
#                    throw_range away
#       drone        straight ahead on a tap; toward a point
#       flare        straight ahead at throw_range on a tap; at a point,
#                    at most throw_range away
#   - a passive part (ECM, Seeker, Biosensor) switches on or off.
# Every use waits the part's use_cooldown. While on:
#   - an ECM module gives the mecha its ECM / ECM_frequency (lock-on
#     breaking, update_locking) and sensor_reduction (active sensors find it
#     at (1 - reduction) of their range)
#   - a Seeker follows the mecha (a Device that follows its owner). Only in a
#     match (the mecha has an arena), so a Hangar display mecha has none.
#     Shot down, it is lost (internal_lost) until the part is fitted again.
#   - a Biosensor gives the mecha vision contacts (source "biosensor") of the
#     Entities within sensor_range, every update_interval s (_update_biosensor)

## "" if the internal part can be used now, else why not: "dead", "no_part",
## "lost" (a Seeker shot down), "cooldown", "no_charges".
func can_use_internal() -> String:
	if is_dead:
		return "dead"
	if build.internal == null:
		return "no_part"
	if internal_lost:
		return "lost"
	if internal_cooldown > 0.0:
		return "cooldown"
	if not build.internal.is_passive() and internal_charges <= 0:
		return "no_charges"
	return ""


## Uses the internal part (see INTERNAL BAY); `point` is where it is aimed,
## or null for a tap. Returns "" if it was used, else can_use_internal's
## reason.
func use_internal(point = null) -> String:
	var reason := can_use_internal()
	if reason != "":
		return reason
	var part = build.internal
	internal_cooldown = part.use_cooldown
	if part.is_passive():
		internal_on = not internal_on
		_apply_internal()
		return ""
	internal_charges -= 1
	if part.function == "drone":
		var heading := get_facing()
		if point is Vector2 and point != global_position:
			heading = global_position.direction_to(point)
		_put_device(part, global_position, heading)
	elif part.function == "flare":
		var aim: Vector2 = point if point is Vector2 else global_position + get_facing() * part.throw_range
		_put_device(part, internal_throw_point(aim), Vector2.ZERO)
	else:
		var at := global_position
		if point is Vector2:
			at = internal_throw_point(point)
		_put_device(part, at, Vector2.ZERO)
	return ""


## Where a held use aimed at `point` would put a ward, decoy or flare (at
## most throw_range away).
func internal_throw_point(point: Vector2) -> Vector2:
	var part = build.internal
	var reach: float = part.throw_range if part != null else 0.0
	return global_position + (point - global_position).limit_length(reach)


## This mecha's devices still out there.
func get_devices() -> Array:
	return Device.owned_by(self)


func _put_device(part, at: Vector2, heading: Vector2) -> void:
	if part.device_scene == null or get_parent() == null:
		return
	var device: Device = part.device_scene.instantiate()
	device.setup(self, part, heading)
	get_parent().add_child(device)
	device.global_position = at


func _apply_internal() -> void:
	var part = build.internal
	var ecm_on: bool = part != null and part.function == "ecm" and internal_on
	ecm = part.ECM if ecm_on else 0.0
	ecm_frequency = part.ECM_frequency if ecm_on else 0.0
	sensor_reduction = part.sensor_reduction if ecm_on else 0.0
	_update_seeker()


# A Seeker part switched on puts its follower out; anything else takes it in.
func _update_seeker() -> void:
	if not is_inside_tree():
		return
	var part = build.internal
	var wanted: bool = part != null and part.function == "seeker" and internal_on \
			and not internal_lost and not is_dead and arena is Node
	var followers := get_devices().filter(func(d): return d.follows_owner)
	if wanted and followers.is_empty():
		_put_device(part, global_position, Vector2.ZERO)
	elif not wanted:
		for follower in followers:
			follower.expire()


func _update_biosensor(dt: float) -> void:
	var part = build.internal
	if part == null or part.function != "biosensor" or not internal_on or is_dead:
		return
	_biosensor_timer -= dt
	if _biosensor_timer > 0.0:
		return
	_biosensor_timer = part.update_interval
	var ttl: float = part.update_interval + Device.PING_SLACK
	for entity in get_tree().get_nodes_in_group("entity"):
		if entity.get("is_dead") == true or not (entity is Node2D):
			continue
		if global_position.distance_to(entity.global_position) <= part.sensor_range:
			contacts.report(entity, ContactStore.kind_of(entity), entity.global_position, "biosensor", ttl)


func _on_own_device_destroyed(device) -> void:
	if device.get("follows_owner") == true:
		internal_lost = true
		internal_on = false


# SPEECH AND LOCAL

## Says `text` out loud: a speech box over this mecha for `seconds`, shown
## to the player if they are within earshot (Barks.EARSHOT), even through
## walls, and added to the Local feed as a bark line. always_heard skips the
## earshot check (cutscenes, StageActorSay).
func say(text: String, seconds := SPEECH_TIME, always_heard := false) -> void:
	if text == "":
		return
	spoke.emit(self, text, seconds, always_heard)


# Tells the match's Local channel who hit whom first (reputation).
func _note_attack(source_info) -> void:
	if typeof(source_info) != TYPE_DICTIONARY or not (arena is Node):
		return
	var local = arena.get("local_pilots")
	if local is LocalPilots:
		local.note_attack(source_info.get("body"), self)


#PARTS SETTERS

func set_arm_weapon(part_name, side):
	_stats_changed()
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
		build.arm_weapon_left = part_data
		node.rotation_degrees = -ARM_WEAPON_INITIAL_ROT if not part_data.is_melee else 0
	else:
		build.arm_weapon_right = part_data
		node.rotation_degrees = ARM_WEAPON_INITIAL_ROT if not part_data.is_melee else 0

	node.setup(self, part_data, build.core, side)
	set_weapon_sfx_nodes(sfx_node, part_data)


func set_shoulder_weapon(part_name, side):
	_stats_changed()
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
	_stats_changed()
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
	$CoreCollision.polygon = collision_shape_of(part_data.get_collision())
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
	
	# Size cargo to the core. Same rules as HangarScreen: a never-sized grid
	# is initialised; an existing one is only repacked when the size actually
	# changes (resize_and_migrate re-places every item, which would shuffle
	# the player's layout and can drop items that only fit their arrangement).
	var cargo = build.core.cargo_space
	if mech_inventory == null:
		mech_inventory = Inventory.new()
	if mech_inventory.grid_width == 0 or mech_inventory.grid_height == 0 or mech_inventory.grid.is_empty():
		mech_inventory.initialize_grid(cargo[0], cargo[1])
	elif mech_inventory.grid_width != cargo[0] or mech_inventory.grid_height != cargo[1]:
		var overflow: Array = mech_inventory.resize_and_migrate(cargo[0], cargo[1])
		if not overflow.is_empty():
			cargo_overflow.emit(overflow)

	# Derive internal thermal capacity from coolant
	if build.core.coolant_type:
		var ct: CoolantType = build.core.coolant_type
		var mass_kg = build.core.coolant_volume * ct.density
		internal_capacity = mass_kg * ct.specific_heat  # kJ/°C
		overheat_temp = ct.overheat_temp - AMBIENT_TEMP  # Convert to delta above ambient
	else:
		# Fallback if no coolant assigned (shouldn't happen in production).
		# Warn once per core part so repeated mech spawns don't spam.
		var core_id: String = str(part_name)
		if not _warned_missing_coolant.has(core_id):
			_warned_missing_coolant[core_id] = true
			push_warning("Mecha core '%s' has no coolant_type — using fallback thermals" % core_id)
		internal_capacity = 40.0
		overheat_temp = 110.0

func set_generator(part_name):
	_stats_changed()
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
	_stats_changed()
	if part_name:
		var part_data = PartManager.get_part("chipset", part_name)
		build.chipset = part_data
		# Flatten chipset stats onto the mecha so the lock-on code can read
		# them as plain properties. Mechs with no chipset keep the safe
		# defaults these vars declare. ECM comes from an internal ECM module
		# (set_internal), not the chipset.
		lock_strength = build.chipset.lock_on_strength
		lock_on_duration = build.chipset.lock_on_duration
	else:
		build.chipset = null


func set_thruster(part_name):
	_stats_changed()
	if part_name:
		var part_data = PartManager.get_part("thruster", part_name)
		build.thruster = part_data
	else:
		build.thruster = null


## The internal bay part (see INTERNAL BAY). Fitting one gives a full load
## of charges; a passive part starts switched on.
func set_internal(part_name):
	_stats_changed()
	if part_name:
		build.internal = PartManager.get_part("internal", part_name)
		internal_charges = build.internal.charges
		internal_on = build.internal.is_passive()
	else:
		build.internal = null
		internal_charges = 0
		internal_on = false
	internal_cooldown = 0.0
	internal_lost = false
	_apply_internal()


func set_chassis(part_name):
	_stats_changed()
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
	collision.polygon = collision_shape_of(chassis.get_collision(side))
	movement_type = chassis.movement_type
	var walk_speed: float = chassis.max_speed * Grades.stat_mult(part_grades.get("chassis"), "max_speed")
	update_speed(walk_speed, chassis.move_acc, chassis.friction, chassis.rotation_acc)
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
	_stats_changed()
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
	_stats_changed()
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
		$LeftShoulderCollision.polygon = collision_shape_of(part_data.get_collision(SIDE.LEFT))
		$RightShoulderCollision.polygon = collision_shape_of(part_data.get_collision(SIDE.RIGHT))
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

# The stat sums, cached for the physics frame: movement reads several of
# them a frame (thrust_max_speed, and the overweight check's weight and
# weight_capacity, which the speed stats read again), each a walk of every
# part. The cache is dropped when a part is fitted (_stats_changed), so a
# read in the same frame as the swap is right. A display mecha (the garage,
# the store) is never cached: its parts and grades change while the UI reads.
var _stat_cache := {}
var _stat_cache_frame := -1


## Called by every part setter: the next get_stat sums afresh.
func _stats_changed() -> void:
	_stat_cache_frame = -1


func get_stat(stat_name):
	if display_mode:
		return _sum_stat(stat_name)
	var frame := Engine.get_physics_frames()
	if frame != _stat_cache_frame:
		_stat_cache_frame = frame
		_stat_cache.clear()
	elif _stat_cache.has(stat_name):
		return _stat_cache[stat_name]
	var total: float = _sum_stat(stat_name)
	_stat_cache[stat_name] = total
	return total


func _sum_stat(stat_name) -> float:
	var total_stat = 0.0
	var weight: bool = stat_name == "weight"
	for slot in build:
		var part = build[slot]
		if part and part.get(stat_name):
			var share := _weight_share(slot) if weight else 1.0
			total_stat += part[stat_name] * Grades.stat_mult(part_grades.get(slot), stat_name) * share

	if stat_name.contains("max_speed") and is_overweight():
		var total_weight = get_total_weight()
		if weight_capacity > 0.0:
			total_stat /= (total_weight / weight_capacity) * OVERWEIGHT_SPEED_MOD
			total_stat = round(total_stat)

	if stat_name == "thrust_max_speed":
		total_stat += get_stat("max_speed")
	return float(total_stat)

# How much of a slot's part is still on the mecha (lose_part): none of a lost
# one, half the shoulders per shoulder lost.
func _weight_share(slot: String) -> float:
	if lost_parts.is_empty():
		return 1.0
	if slot == "shoulders":
		return 1.0 - 0.5 * (int(is_part_lost("left_shoulder")) + int(is_part_lost("right_shoulder")))
	return 0.0 if is_part_lost(slot) else 1.0


func get_inventory_weight() -> float:
	if mech_inventory:
		return mech_inventory.get_current_weight()
	return 0.0


func get_total_weight() -> float:
	# Parts weight (from build) + cargo weight (inventory). The cargo weight
	# is a walk of the whole inventory grid, so it is read once a physics
	# frame (the stat cache; a pick-up shows the next frame).
	var parts_weight = get_stat("weight")
	if display_mode:
		return parts_weight + get_inventory_weight()
	var cargo = _stat_cache.get(CARGO_WEIGHT_KEY)
	if cargo == null:
		cargo = get_inventory_weight()
		_stat_cache[CARGO_WEIGHT_KEY] = cargo
	return parts_weight + cargo


## The stat cache's key for the cargo weight (no part has a stat so named).
const CARGO_WEIGHT_KEY := "__cargo_weight"



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


# Moves by `vec` this frame. The NavigationAgent2D gets no velocity: its
# avoidance is off (NPCs keep apart through their context steering, see
# Enemy._add_mechas), so there is nothing for it to compute.
# Frames of motion one move() covers: 1, or the step interval of an NPC
# running at a lower physics rate (Enemy.step_interval), which moves the
# distance of the frames it skipped. The velocity is scaled for the move and
# restored after, so the speed the next frame starts from is unchanged.
var _step_scale := 1.0


func move(vec):
	_update_car_collision()
	set_velocity(vec * _step_scale)
	move_and_slide()
	if _step_scale != 1.0:
		velocity /= _step_scale
	VehicleField.push_from(self, vec)


# A sprinting mecha passes over cars: it stops colliding with the car layer
# (vans and trucks are on another layer and still stop it). After the sprint
# it collides with cars again only once it is clear of every car, so it never
# ends up inside one.
func _update_car_collision() -> void:
	var colliding := get_collision_mask_value(MapSenses.VEHICLE_LAYER)
	if is_sprinting:
		if colliding:
			set_collision_mask_value(MapSenses.VEHICLE_LAYER, false)
	elif not colliding and not _over_a_car():
		set_collision_mask_value(MapSenses.VEHICLE_LAYER, true)


func _over_a_car() -> bool:
	if not is_inside_tree():
		return false
	var radius := 0.0
	for c in get_children():
		if c is CollisionPolygon2D and not c.disabled:
			for p in c.polygon:
				radius = maxf(radius, (c.position + p * c.scale).length())
	var shape := CircleShape2D.new()
	shape.radius = maxf(radius * 0.85, 60.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = MapSenses.CAR_MASK
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


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
	if not build.thruster:
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
			direction.y = min(direction.y, 0.0)
	var target_move_acc = clamp(move_acc*dt, 0, 1)
	var target_speed = direction.normalized() * (max_speed * throttle) * get_entity_slow()
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
			increase_heat(get_chassis_move_heat() * throttle * dt)
		else:
			moving = false
			velocity *= 1 - get_chassis_friction()
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
			increase_heat(get_chassis_move_heat() * throttle * dt)
		else:
			moving = false
			moving_axis.x = false
			moving_axis.y = false
			velocity *= 1 - get_chassis_friction()
		var mod = 1.0 if is_sprinting else speed_modifier
		velocity = apply_movement_modifiers(velocity*mod)
		move(velocity)
	elif movement_type == "tank" and not is_player():
		# This frame's dash or knockback move overwrote velocity; NPC tanks
		# drive on from their own driving speed, or the dash would be carried
		# into their (double) drive move and fly them several times as far.
		if dash_velocity.length() > 0.0 or impact_velocity.length() > 0.0:
			velocity = _tank_drive_velocity
		if direction.length() > 0:
			moving = true
			var target_rotation_acc = apply_movement_modifiers(get_chassis_rotation_acc() * 50)
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
			target_speed *= WHEELS_SPEED_FACTOR * get_entity_slow()
			velocity = lerp(velocity, target_speed, target_move_acc)
			increase_heat(get_chassis_move_heat() * throttle * dt)
			move(apply_movement_modifiers(velocity))
			velocity = apply_movement_modifiers(velocity)
			move(velocity)
			#Move forward or backward depending on how closely the chassis is facing the angle
		_tank_drive_velocity = velocity
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
			target_speed *= get_entity_slow()
			var target_rotation_acc = apply_movement_modifiers(get_chassis_rotation_acc() * 50)
			if direction.y == 0:
				target_rotation_acc *= 2
			if direction.x > 0:
				tank_move_target = tank_move_target.rotated(deg_to_rad(target_rotation_acc*dt))
				global_rotation_degrees += target_rotation_acc*dt
			elif direction.x < 0:
				tank_move_target = tank_move_target.rotated(deg_to_rad(-target_rotation_acc*dt))
				global_rotation_degrees -= target_rotation_acc*dt
			if not moving:
				velocity *= 1 - get_chassis_friction()
			else:
				velocity = lerp(velocity, target_speed, target_move_acc)
			increase_heat(get_chassis_move_heat() * throttle * dt)
		else:
			if build.chassis:
				velocity *= 1 - get_chassis_friction()/2
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
		rot_acc = get_chassis_trim_acc()
	if is_sprinting == true and movement_type != "tank":
		rot_acc = rotation_acc/2
	if not stand_still:
		rotation_degrees += get_rotation_diff_by_point(dt, global_position, target_pos, rotation_degrees, rot_acc)

	
	# Head, shoulders, arm weapons and chassis halves each turn towards the
	# point at their part's rate, within its range. Each is written once (a
	# node's rotation set is a transform update) and no lists are built: this
	# runs every frame for every mecha with a target.
	if build.head:
		_turn_part_to(Head, build.head.rotation_acc, build.head.rotation_range, target_pos, dt)
	if build.shoulders:
		_turn_part_to(LeftShoulder, build.shoulders.rotation_acc, build.shoulders.rotation_range, target_pos, dt)
		_turn_part_to(RightShoulder, build.shoulders.rotation_acc, build.shoulders.rotation_range, target_pos, dt)

	#Rotate Non-Melee Arm Weapons
	if build.arm_weapon_left and not build.arm_weapon_left.is_melee:
		_turn_weapon_to(LeftArmWeapon, build.arm_weapon_left, 1.0, target_pos, dt)
	if build.arm_weapon_right and not build.arm_weapon_right.is_melee:
		_turn_weapon_to(RightArmWeapon, build.arm_weapon_right, -1.0, target_pos, dt)

	if build.chassis:
		_turn_part_to(LeftChassisRoot, build.chassis.trim_acc, build.chassis.rotation_range, target_pos, dt)
		_turn_part_to(RightChassisRoot, build.chassis.trim_acc, build.chassis.rotation_range, target_pos, dt)


# Turns `node` (a part of this mecha) towards `target_pos` at `acc`, clamped
# to ±`range` degrees from the body.
func _turn_part_to(node: Node2D, acc: float, range_degrees: float, target_pos: Vector2, dt: float) -> void:
	var actual_rot = node.rotation_degrees + rotation_degrees
	node.rotation_degrees = clamp(node.rotation_degrees \
			+ get_rotation_diff_by_point(dt, node.global_position, target_pos, actual_rot, acc), \
			-range_degrees, range_degrees)


# An arm weapon turns like a part, plus its parallax offset (to the left
# for the left arm, `parallax_sign` 1; to the right for the right arm, -1),
# within the core's range.
func _turn_weapon_to(node: Node2D, part, parallax_sign: float, target_pos: Vector2, dt: float) -> void:
	var actual_rot = node.rotation_degrees + rotation_degrees
	node.rotation_degrees = clamp(node.rotation_degrees \
			+ get_rotation_diff_by_point(dt, node.global_position, target_pos, actual_rot, part.rotation_acc) \
			+ part.parallax_offset * parallax_sign, \
			-build.core.rotation_range, build.core.rotation_range)

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
	# No-op on the base mecha; Player overrides this with real knockback.
	return


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

		# Written only when the angle moves: a rotation set is a transform
		# update for the leg and everything under it, and a standing mecha's
		# legs sit at their angle.
		for child in LeftChassisRoot.get_children():
			var angle: float = lerp(float(child.rotation), float(left_target_angle), dt*CHASSIS_SPEED)
			if angle != child.rotation_degrees:
				child.rotation_degrees = angle
		for child in RightChassisRoot.get_children():
			var angle: float = lerp(float(child.rotation), float(right_target_angle), dt*CHASSIS_SPEED)
			if angle != child.rotation_degrees:
				child.rotation_degrees = angle

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
	# The Flag locks the weapons (the smoke launcher excepted).
	if is_shielding or (is_flagged() and not flag_allows(type)):
		return
	# A weapon that came off with its part.
	if is_part_lost(type):
		return
	# Designator weapons fire salvos at a point; callers that only say "shoot"
	# (NPCs, scripted scenes) aim at get_default_aim_point, and don't fire
	# when it is out of the weapon's range.
	if build.get(type) and build[type].has_designator():
		fire_at_point(type, get_default_aim_point(type))
		return
	if disabled_systems.has(type) and disabled_systems[type] == true:
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
				# Guard against divide-by-zero when arm_accuracy_mod is 0
				var arm_acc = arm_accuracy_mod if arm_accuracy_mod > 0.0 else 1.0
				max_angle = max_angle / arm_acc
				bloom /= arm_accuracy_mod
			if locked_to:
				max_angle = max_angle/chipset_accuracy
			var total_accuracy = min(weapon_ref.base_accuracy + bloom, max_angle)/head_accuracy + extra_bloom
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


# DESIGNATOR WEAPONS
#
# A weapon with a designator (weapon.gd) fires salvos at a world point. The
# same rules hold for the player and NPCs: the point must be within the
# weapon's min and max range of the mecha's centre and within `gimbal`
# degrees of its facing; indirect weapons can't fire from inside a building
# (the roof is in the way); and the weapon needs ammo, no cooldown or reload
# running and an internal temperature below the overheat point. A "line"
# (the cannon) or "rect" (the laser) designator is a skillshot: only its
# direction comes from the aim, and it always reaches max_range. A salvo
# costs one clip round and muzzle_heat per round, added at once; the rounds
# go out barrage_interval s apart, each aimed at a random point within
# scatter_radius of the designated point. An empty clip starts the reload,
# which is the weapon's cooldown.

const DISABLED_WEAPON_KEYS := {
	"arm_weapon_left": "left_arm_weapon",
	"arm_weapon_right": "right_arm_weapon",
	"shoulder_weapon_left": "left_shoulder_weapon",
	"shoulder_weapon_right": "right_shoulder_weapon",
}
const DESIGNATOR_RANGE_SLACK := 1.0
const DESIGNATOR_ANGLE_SLACK := 0.5


func get_facing() -> Vector2:
	return Vector2.UP.rotated(global_rotation)


# Where `slot`'s designator goes for an aim at `target`: clamped to the
# weapon's range and, with look_limits, to its gimbal either side of facing.
func designator_point(slot: String, target: Vector2, look_limits := true) -> Vector2:
	var weapon = build.get(slot)
	if not weapon:
		return target
	var offset := target - global_position
	var dist := clampf(offset.length(), weapon.min_range, weapon.max_range)
	if weapon.designator == "line" or weapon.designator == "rect":
		dist = weapon.max_range
	var angle := 0.0
	if offset.length() > 0.001:
		angle = get_facing().angle_to(offset)
	if look_limits:
		var limit := deg_to_rad(weapon.gimbal)
		angle = clampf(angle, -limit, limit)
	return global_position + get_facing().rotated(angle) * dist


# A direct-fire designator stops short of the first wall or solid body on
# the way from the weapon to `point`, where the shot would really hit.
# Vehicles (lower than a shoulder mount), mechas and Entities don't stop it.
func designator_clip(slot: String, point: Vector2) -> Vector2:
	var node = get_weapon_part(slot)
	var from: Vector2 = global_position
	if node and node.shooting_pos_array.size() > 0:
		from = node.shooting_pos_array[node.shooting_pos_idx].global_position
	var exclude: Array[RID] = [get_rid()]
	var hit = MapSenses.solid_hit(get_world_2d(), from, point, exclude)
	if hit == null:
		return point
	return hit - (point - from).normalized() * 4.0


# Why `slot` can't fire at `point` now, or "" if it can. Reasons:
# no_weapon, disabled, busy (dead, shielding or a salvo still going out),
# flagged (the Flag locks the weapons),
# indoors (indirect fire from inside a building), reloading (also the
# cooldown), no_ammo, too_hot, too_close, too_far, not_facing.
func can_fire_at_point(slot: String, point: Vector2) -> String:
	var weapon = build.get(slot)
	var node = get_weapon_part(slot) if weapon else null
	if not weapon or not node:
		return "no_weapon"
	if disabled_systems.get(DISABLED_WEAPON_KEYS.get(slot, ""), false) == true:
		return "disabled"
	if is_dead or is_shielding or is_salvo_firing(slot):
		return "busy"
	if is_flagged() and not flag_allows(slot):
		return "flagged"
	if weapon.is_indirect_fire and is_inside_building:
		return "indoors"
	if node.clip_ammo is not bool and node.clip_ammo <= 0 and node.total_ammo <= 0:
		return "no_ammo"
	if node.is_reloading() or node.timer > 0.0 or (node.clip_ammo is not bool and node.clip_ammo <= 0):
		return "reloading"
	if internal_temp >= overheat_temp:
		return "too_hot"
	if weapon.has_designator() and fires_at_lock(slot):
		if global_position.distance_to(get_locked_to().global_position) > weapon.max_range + DESIGNATOR_RANGE_SLACK:
			return "too_far"
	elif weapon.has_designator():
		var offset := point - global_position
		if offset.length() < weapon.min_range - DESIGNATOR_RANGE_SLACK:
			return "too_close"
		if offset.length() > weapon.max_range + DESIGNATOR_RANGE_SLACK:
			return "too_far"
		if offset.length() > 0.001 and\
		absf(get_facing().angle_to(offset)) > deg_to_rad(weapon.gimbal + DESIGNATOR_ANGLE_SLACK):
			return "not_facing"
	return ""


# Fires `slot` at `point` under the rules above. Returns "" if it fired,
# else the reason it didn't (see can_fire_at_point; also "jammed" when an
# overheated weapon jams). A weapon without a designator just shoots.
func fire_at_point(slot: String, point: Vector2) -> String:
	var reason := can_fire_at_point(slot, point)
	if reason != "":
		return reason
	var weapon = build[slot]
	if not weapon.has_designator():
		shoot(slot)
		return ""
	var node = get_weapon_part(slot)
	if not node.can_shoot(1):
		return "jammed"
	if fires_at_lock(slot):
		point = get_locked_to().global_position
	elif (weapon.designator == "line" or weapon.designator == "rect") and point != global_position:
		point = global_position + global_position.direction_to(point) * weapon.max_range
	node.shoot_salvo(weapon.muzzle_heat * weapon.barrage_count)
	_fire_designator_round(slot, point)
	if weapon.barrage_count > 1:
		_salvos.append({"slot": slot, "point": point, "left": weapon.barrage_count - 1,
				"wait": weapon.barrage_interval})
	elif node.is_clip_empty():
		node.reload()
	emit_signal("shoot_signal")
	return ""


# A lock-on weapon (requires_lock) with a target locked fires at that target
# wherever the designator is: no gimbal or minimum range, only max range.
# Its rounds carry the target as their seeker; an indirect one (VLS) flies
# over everything onto the target, a direct one flies as it always has.
func fires_at_lock(slot: String) -> bool:
	var weapon = build.get(slot)
	return weapon and weapon.requires_lock and get_locked_to()


# The mines within `radius` of `pos` (any owner): one Dictionary each with
# "type" (contact, sensor, magnetic), "owner" (the mecha that laid it, or
# null), "position", "trigger_radius", "attract_radius" (magnetic only),
# "armed" and "node". A grid lookup, cheap enough to call every frame.
func mines_near(pos: Vector2, radius: float) -> Array[Dictionary]:
	return MINE.mines_near(pos, radius)


func is_salvo_firing(slot: String) -> bool:
	for salvo in _salvos:
		if salvo.slot == slot:
			return true
	return false


# Aim point for a designator weapon fired through shoot(), which has no
# point: straight ahead at the weapon's AI engage range. Enemy aims at its
# target instead.
func get_default_aim_point(slot: String) -> Vector2:
	var weapon = build.get(slot)
	var dist: float = weapon.ai_engage_range if weapon else 0.0
	return global_position + get_facing() * dist


func _process_salvos(dt: float) -> void:
	for salvo in _salvos.duplicate():
		if is_dead or not build.get(salvo.slot):
			_salvos.erase(salvo)
			continue
		salvo.wait -= dt
		while salvo.wait <= 0.0 and salvo.left > 0:
			_fire_designator_round(salvo.slot, salvo.point)
			salvo.left -= 1
			salvo.wait += build[salvo.slot].barrage_interval
		if salvo.left <= 0:
			_salvos.erase(salvo)
			var node = get_weapon_part(salvo.slot)
			if node and node.is_clip_empty():
				node.reload()


# One round of a salvo, aimed at a random point within the weapon's scatter
# round `point`: a circle of scatter_radius, or for a line_box designator a
# square of half-side scatter_radius lined up with the line of fire. The
# round carries its landing point: indirect rounds fly to it over
# everything, direct ones go off there unless they hit something first
# (complex_projectile).
func _fire_designator_round(slot: String, point: Vector2) -> void:
	var weapon = build[slot]
	var node = get_weapon_part(slot)
	var locked := fires_at_lock(slot)
	var cluster: bool = weapon.get_aoe_info().submunitions > 0
	var landing := point
	var r: float = weapon.scatter_radius
	if locked:
		landing = get_locked_to().global_position
	elif cluster:
		pass
	elif r > 0.0 and weapon.designator == "line_box":
		var along := global_position.direction_to(point)
		landing += along * randf_range(-r, r) + along.orthogonal() * randf_range(-r, r)
	elif r > 0.0:
		landing += Vector2.RIGHT.rotated(randf() * TAU) * r * sqrt(randf())
	var muzzle = node.get_shoot_position()
	var from: Vector2 = muzzle.global_position
	var dir := from.direction_to(landing)
	if dir == Vector2.ZERO:
		dir = get_facing()
	var args := {
		"projectile": weapon.projectile,
		"pos": from,
		"pos_reference": muzzle,
		"dir": dir,
		"align_dir": dir,
		"seeker_target": get_locked_to() if locked else false,
		"node_reference": node,
		"inherited_velocity": velocity,
		"bullet_spread_delay": 0,
		"muzzle_flash": null if weapon.muzzle_flash == null else {
			"flash_effect": weapon.muzzle_flash,
			"flash_speed": weapon.muzzle_flash_speed,
			"flash_size": weapon.muzzle_flash_size,
		},
		"target_pos": landing,
		"indirect": weapon.is_indirect_fire,
		"beam_width": weapon.designator_width,
	}
	# A locked direct missile has no landing point: it flies at its seeker
	# target as lock-on missiles always have.
	if locked and not weapon.is_indirect_fire:
		args.erase("target_pos")
	if cluster and not locked:
		args["cluster_radius"] = r
	emit_signal("create_projectile", self, args, weapon.part_id)
	node.play_shot_sound(from)
	if weapon.recoil_force > 0.0:
		apply_recoil(slot, node, weapon.recoil_force)
	if weapon.eject_casings:
		emit_signal("create_casing",
						{
							"casing_ejector_pos": node.global_position,
							"casing_eject_angle": (180.0 if "left" in slot else 0.0) + global_rotation_degrees,
							"casing_size": weapon.casing_size,
						})


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

# The two timers, looked up once: these checks run several times a frame
# for every mecha.
@onready var StunTimer: Timer = $StunTimer
@onready var LockMovementTimer: Timer = $LockMovementTimer


func is_stunned():
	return not StunTimer.is_stopped()


func is_movement_locked():
	return not LockMovementTimer.is_stopped()


func stun(time):
	StunTimer.wait_time += time * get_stability()
	StunTimer.start()


func lock_movement(time):
	LockMovementTimer.wait_time = time
	LockMovementTimer.start()


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
			# Cold targets lock slower (0.5×), hot targets faster (1.5×).
			var thermal_lock_mult = get_target_thermal_lock_mult(locking_to.mecha)
			if has_status("electrified"):
				locking_to.progress = min(locking_to.progress + (dt * build.chipset.lock_on_speed * 0.5 * thermal_lock_mult), 1.0)
			else:
				locking_to.progress = min(locking_to.progress + dt * build.chipset.lock_on_speed * thermal_lock_mult, 1.0)
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

func armor_check(hit_part_name: String, impact_position: Vector2, projectile_dir: Vector2, pen_level: int, damage_pips: int, is_aoe := false) -> Dictionary:
	# Returns: {penetrated: bool, part_name: String, component_name: String, facing: String}

	# The shield collision isn't a real armor part — it's a separate
	# damage-absorption layer handled by take_damage. Explosion area queries
	# can pick it up; treat as "not penetrated" instead of erroring.
	if hit_part_name == "shield":
		return {"penetrated": false, "part_name": "", "component_name": "", "facing": ""}

	# In the Flag's grace window a hit lands (the round stops on the hull) but
	# strips no armour and picks no component.
	if is_in_flag_grace():
		return {"penetrated": true, "part_name": hit_part_name, "component_name": "", "facing": "", "deflection_type": ""}

	# A part that came off isn't there to hit.
	if is_part_lost(hit_part_name):
		return {"penetrated": false, "part_name": "", "component_name": "", "facing": ""}

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
	elif delta >= -1 and delta <= 0:
		# Marginal/glancing
		penetrated = false
		if randf() < 0.33:
			deflection_type = "glancing"
		if randf() < (damage_pips / 3.0):
			armor_pip_damage = 1
	else:  # delta >= 1
		# Penetration!
		penetrated = true
		armor_pip_damage = damage_pips
		deflection_type = "" #No deflection on penetration, left empty

	# 7. Apply armor damage
	armor[hit_part_name][facing].pips = max(armor_pips - armor_pip_damage, 0)
	var facing_exposed = armor[hit_part_name][facing].pips == 0
	
	# 8. Select component to damage (if penetrated or exposed)
	var selected_component = ""
	if penetrated or facing_exposed:
		var eligible = get_eligible_components(hit_part_name, facing, penetrated, is_aoe)
		if eligible.size() > 0:
			selected_component = select_component_by_weight(hit_part_name, eligible)

	# The damage_component that follows a hit on a component counts its pips
	# against the ticks; armour stripped without reaching one counts here.
	_hit_facing[hit_part_name] = facing
	_aoe_part = hit_part_name if is_aoe and selected_component != "" else ""
	if selected_component == "":
		_shake_ticks(armor_pip_damage * (TICK_AOE_SHAKE if is_aoe else 1))
	_check_part_loss(hit_part_name, facing)

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
	
## With SIMPLE_COLLISION on, a part collides as the rectangle round its
## outline (one convex shape of four points) instead of the outline itself,
## which the physics engine cuts into several convex pieces. Measured with
## FrameCostProbe's walkers case: half the collision pairs, no change in
## the frame time within the noise, so it is off; the switch stays for a
## map or a count of mechas where it might pay. On, hits still land on the
## right part (each keeps its own shape); a round can land a little outside
## the drawn outline, in the rectangle's corners.
const SIMPLE_COLLISION := false


static func collision_shape_of(outline) -> PackedVector2Array:
	var poly := PackedVector2Array(outline) if outline != null else PackedVector2Array()
	if not SIMPLE_COLLISION or poly.size() < 3:
		return poly
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


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
	var poly_xform = collision_polygon.global_transform

	# Find closest edge
	var closest_edge_idx = -1
	var closest_dist = INF

	for i in range(polygon.size()):
		var pa = poly_xform * polygon[i]
		var pb = poly_xform * polygon[(i + 1) % polygon.size()]
		var dist = Geometry2D.get_closest_point_to_segment(point, pa, pb).distance_to(point)

		if dist < closest_dist:
			closest_dist = dist
			closest_edge_idx = i

	# Get edge normal
	var closest_p1 = poly_xform * polygon[closest_edge_idx]
	var closest_p2 = poly_xform * polygon[(closest_edge_idx + 1) % polygon.size()]
	var edge = (closest_p2 - closest_p1).normalized()
	var normal = Vector2(-edge.y, edge.x)

	return normal
	
	
func get_eligible_components(part_name: String, _facing: String, penetrated: bool, _is_aoe: bool = false) -> Array:
	var eligible = []

	if not components.has(part_name) or is_part_lost(part_name):
		return eligible
	
	for comp_name in components[part_name]:
		var comp = components[part_name][comp_name]
		
		# Skip if already destroyed, or shielded by its part's shell
		if comp.disabled or is_protected(part_name, comp_name):
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

# Whether a component can't be hit yet: a critical one (the cockpit, the only
# lethal component) while its part's core_shell is intact.
func is_protected(part_name: String, comp_name: String) -> bool:
	var comp: Dictionary = components[part_name][comp_name]
	if not "critical" in comp.tags:
		return false
	var shell = components[part_name].get("core_shell")
	return shell != null and not shell.disabled

func select_component_by_weight(part_name: String, eligible_components: Array) -> String:
	if eligible_components.size() == 0:
		return ""
	
	# Calculate total weight
	var total_weight = 0.0
	for comp_name in eligible_components:
		total_weight += components[part_name][comp_name].weight

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
					"tags": ["internal", "critical"],
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
					"weight": 1.0,
					"disabled": false
				},
				"power unit": {
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
	_wound_dirty = true
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

# hit_dir: the way the hit travelled (a shot's direction, a blast's from its
# centre); ZERO for damage with no direction, like overheating.
func damage_component(part_name: String, component_name: String, damage_pips: int, hit_dir := Vector2.ZERO):
	if is_in_flag_grace():
		return
	if not components.has(part_name) or not components[part_name].has(component_name):
		push_error("Invalid component: " + part_name + "." + component_name)
		return
	var aoe := _aoe_part == part_name
	_aoe_part = ""
	if is_part_lost(part_name):
		return

	var comp = components[part_name][component_name]

	# Apply damage
	comp.hp = max(comp.hp - damage_pips, 0)
	_wound_dirty = true
	_shake_ticks(damage_pips * (TICK_AOE_SHAKE if aoe else 1))
	_note_pressure(last_damage_source, float(damage_pips) * PRESSURE_PER_PIP)
	spawn_component_damage_explosion(part_name, comp.hp <= 0)
	if part_name in WOUND_PARTS and WOUND_TAG in comp.tags:
		_show_wound(part_name, comp.hp <= 0 and not comp.disabled, hit_dir)
	# Emit damage signal for UI updates
	emit_signal("component_damaged", part_name, component_name, comp.hp, comp.max_hp)
	
	#Special warning if cockpit is damaged
	if component_name == "cockpit" and comp.hp > 0:
		emit_signal("cockpit_exposed", comp.hp)
	
	# Check if destroyed
	if comp.hp <= 0 and not comp.disabled:
		comp.disabled = true
		component_destroyed(part_name, component_name)

	# The facing the hit came in on (from its direction, else the last armour
	# check on this part) decides whether the part comes off.
	var facing: String = get_global_facing_from_angle(global_position - hit_dir * 100.0) \
			if hit_dir != Vector2.ZERO else str(_hit_facing.get(part_name, ""))
	if facing != "":
		_check_part_loss(part_name, facing)

func component_destroyed(part_name: String, comp_name: String):
	var comp = components[part_name][comp_name]


	# Emit destruction signal
	emit_signal("component_destroyed_alert", part_name, comp_name)
	
	# CRITICAL COMPONENTS - Instant effects
	if "critical" in comp.tags:
		die(last_damage_source, last_damage_weapon)
		return

	if comp_name == "core_shell":
		emit_signal("core_shell_destroyed")
		enter_flagged_state()
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
			update_speed(reduced_speed, build.chassis.move_acc, get_chassis_friction(), get_chassis_rotation_acc())
	
	# WEAPON COMPONENTS
	if "weapon" in comp.tags:
		# Weapon feed destroyed = weapon offline
		if comp_name == "weapon_feed":
			if part_name == "left_shoulder":
				disabled_systems.left_arm_weapon = true
				emit_signal("system_degraded", "left_arm_weapon", 0.0)
			elif part_name == "right_shoulder":
				disabled_systems.right_arm_weapon = true
				emit_signal("system_degraded", "right_arm_weapon", 0.0)
	
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
	_wound_dirty = true
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

# The emergency Flag. Both ways in come here: hp reaching 0 (take_damage) and
# the core shell destroyed (component_destroyed). The grace window starts at
# once, inside the damage that caused it, so the rest of that blast or burst
# does nothing (take_damage, armor_check, damage_component and
# take_status_damage all check it). The weapons lock (shoot,
# can_fire_at_point) and a salvo still going out stops. After the window the
# cockpit can be hit (is_protected) and the exposed_hits rule counts.
func enter_flagged_state():
	if is_exposed or is_dead:
		return
	is_exposed = true
	flag_grace = FLAG_GRACE_TIME
	exposed_invuln_timer = 0.0
	_heartbeat = FLAG_HEARTBEAT_TIME
	var attacker = get_last_attacker()
	_show_flag_entry(attacker)
	_set_flag_up(false)
	emit_signal("flagged")
	emit_signal("exposed", self)
	emergency_flagged.emit(self, attacker)


func is_in_flag_grace() -> bool:
	return flag_grace > 0.0


# ---- The Flag ----

## Whether the Flag is up (voluntary or emergency), the wind-up included.
func is_flagged() -> bool:
	return flag_up


func is_lowering_flag() -> bool:
	return flag_lowering > 0.0


## Raises the Flag at once, by choice unless `voluntary` is false (the
## emergency state raises it itself). A Flag being lowered goes back up.
func raise_flag(voluntary := true) -> void:
	if is_dead:
		return
	if flag_up and flag_lowering <= 0.0:
		return
	var was_lowering := flag_lowering > 0.0
	flag_lowering = 0.0
	if was_lowering:
		if _flag_marker:
			_flag_marker.lowering = 0.0
		return
	if is_inside_tree():
		if _flag_marker == null:
			_flag_marker = FlagMarker.new()
			add_child(_flag_marker)
		AudioManager.play_sfx(FLAG_RAISE_SFX, global_position)
	_set_flag_up(voluntary)
	emit_signal("flagged")


## Starts lowering the Flag: the wind-up (FLAG_LOWER_TIME) is visible on the
## marker, and the Flag is down when it ends (flag_lowered). Lowering the
## emergency Flag doesn't end the emergency state.
func lower_flag() -> void:
	if not flag_up or flag_lowering > 0.0 or is_dead:
		return
	flag_lowering = FLAG_LOWER_TIME
	if _flag_marker:
		_flag_marker.lowering = 0.0
	if is_inside_tree():
		AudioManager.play_sfx(FLAG_LOWER_SFX, global_position)
	flag_lowering_started.emit(self)


## Whether a weapon slot still fires under the Flag: only the smoke launcher
## (a tap_self designator).
func flag_allows(slot: String) -> bool:
	var weapon = build.get(slot)
	return weapon != null and weapon.get("tap_self") == true


## The mecha (or Entity) whose damage pressed this mecha most in the last
## PRESSURE_WINDOW s, or null.
func pressured_by():
	var now := contacts.now
	var totals := {}
	var bodies := {}
	for entry in _pressure:
		if now - float(entry.time) > PRESSURE_WINDOW:
			continue
		var body = entry.body
		if not is_instance_valid(body):
			continue
		var id: int = body.get_instance_id()
		totals[id] = float(totals.get(id, 0.0)) + float(entry.amount)
		bodies[id] = body
	var best = null
	var most := 0.0
	for id in totals:
		if totals[id] > most:
			most = totals[id]
			best = bodies[id]
	return best


func _set_flag_up(voluntary: bool) -> void:
	flag_up = true
	flag_voluntary = voluntary
	flag_lowering = 0.0
	_salvos.clear()
	for slot in WeaponSFXs:
		if not flag_allows(slot):
			stop_shooting(slot)
	if _flag_marker:
		_flag_marker.voluntary = voluntary
		_flag_marker.lowering = 0.0
	flag_raised.emit(self, voluntary, pressured_by())


func _finish_lowering() -> void:
	flag_up = false
	flag_voluntary = false
	if _flag_marker:
		_flag_marker.queue_free()
		_flag_marker = null
	flag_lowered.emit(self)


func _note_pressure(source_info, amount: float) -> void:
	if typeof(source_info) != TYPE_DICTIONARY or amount <= 0.0:
		return
	var body = source_info.get("body")
	if not is_instance_valid(body) or body == self:
		return
	var now := contacts.now
	_pressure.append({"body": body, "time": now, "amount": amount})
	while not _pressure.is_empty() and now - float(_pressure[0].time) > PRESSURE_WINDOW:
		_pressure.pop_front()


# The mecha (or Entity) whose damage hit this one last, or null.
func get_last_attacker():
	if typeof(last_damage_source) == TYPE_DICTIONARY:
		var body = last_damage_source.get("body")
		if is_instance_valid(body):
			return body
	return null


# The moment the Flag starts, made visible: the marker (FlagMarker), a sound,
# a burst of blood from the core and a splatter on the ground thrown away from
# the attacker (BloodStains). The spurt emitter then pulses with the heartbeat.
func _show_flag_entry(attacker) -> void:
	if not is_inside_tree():
		return
	if _flag_marker == null:
		_flag_marker = FlagMarker.new()
		add_child(_flag_marker)
	_flag_marker.restart_entry()
	AudioManager.play_sfx(FLAG_SFX, global_position)
	var burst: GPUParticles2D = Particle.blood[2]
	burst.restart()
	if _spurt == null:
		_spurt = burst.duplicate()
		_spurt.amount = FLAG_SPURT_AMOUNT
		_spurt.lifetime = FLAG_SPURT_LIFETIME
		burst.get_parent().add_child(_spurt)
	var away := Vector2.RIGHT.rotated(randf() * TAU)
	if attacker is Node2D and attacker.global_position != global_position:
		away = (global_position - attacker.global_position).normalized()
	var stains := BloodStains.find(self)
	if stains:
		stains.add_splatter(global_position, away)
		stains.spray(global_position, away)


## How much of the Hardware parts' internal component hp is gone, 0 to 1
## (WOUND_PARTS, WOUND_TAG).
func get_internal_wound() -> float:
	var lost := 0.0
	var total := 0.0
	for part_name in WOUND_PARTS:
		for comp in components.get(part_name, {}).values():
			if WOUND_TAG in comp.tags:
				total += comp.max_hp
				lost += comp.max_hp - comp.hp
	return lost / total if total > 0.0 else 0.0


# A hit on an internal component, made visible at its part: a few drops
# thrown out the way the hit went (any way for one with no direction), or,
# when the hit destroyed it, a full spray and a small splatter on the ground.
# Damage with no direction (overheating) only ever leaks drops.
func _show_wound(part_name: String, destroyed: bool, hit_dir: Vector2) -> void:
	var stains := BloodStains.find(self)
	if stains == null:
		return
	var at := get_part_global_position(part_name)
	if hit_dir == Vector2.ZERO:
		stains.spray(at, Vector2.RIGHT.rotated(randf() * TAU), WOUND_LEAK)
	elif destroyed:
		stains.spray(at, hit_dir)
		stains.add_small_splatter(at, hit_dir)
	else:
		stains.spray(at, hit_dir, WOUND_LEAK)

func spawn_component_damage_explosion(part_name: String, is_destroyed: bool):
	# Throttle rapid same-part hits to avoid spawn storms during cascading damage.
	# Destruction always plays — it's the dramatic final pop.
	if not is_destroyed:
		var now_ms := Time.get_ticks_msec()
		var last_ms: int = _last_component_explosion_ms.get(part_name, -COMPONENT_EXPLOSION_THROTTLE_MS)
		if now_ms - last_ms < COMPONENT_EXPLOSION_THROTTLE_MS:
			return
		_last_component_explosion_ms[part_name] = now_ms

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


# TICKS
#
# A tick swarm's motes jump on a hot mecha (TickSwarm) and become the
# mecha's own: attach_tick() adds one, and the mecha keeps it, whatever
# happens to its swarm. Each tick sits on a part (in that part node's space,
# so it moves with the mecha), stays on its own time, and while on:
#   - drains TICK_DRAIN kJ/s from the external layer (drain_heat)
#   - bleeds at its spot now and then (BloodStains.spray, visual only)
#   - adds TICK_GLOW to the thermal signature (get_thermal_signature)
#   - every TICK_BITE_PERIOD s, a TICK_BITE_CHANCE of one pip: an external
#     component of its part or an armour pip of its facing, even chance
# Damage from anything else shakes them off: one tick per point of damage,
# TICK_AOE_SHAKE per point of a blast's (_shake_ticks). Cooling doesn't.
#
# TICK_SYNC_MIN or more from one swarm on one mecha sync: their timers are
# pulled within TICK_SYNC_SPREAD s of the middle one's. When the middle one
# drops off, a brood forms on the ground here (TickSwarm.spawn_brood) with
# the group's ticks that are done; the rest join it as they drop off. A
# synced tick that is done before the middle one holds on until it goes. A
# group shaken down below TICK_SYNC_MIN unsyncs, and a tick in no group just
# fades when its time ends.
#
# All the ticks on a mecha are drawn by one node over it (_tick_layer), in
# one pass, and only on frames the mecha is drawn (wants_visuals).

## Placeholders.
const TICK_DRAIN := 100.0
const TICK_GLOW := 0.1
const TICK_BITE_PERIOD := 3.0
const TICK_BITE_CHANCE := 0.33
const TICK_AOE_SHAKE := 3
const TICK_SYNC_MIN := 3
const TICK_SYNC_SPREAD := 1.0
const TICK_BLEED_INTERVAL := Vector2(1.2, 2.5)
const TICK_JUMP_TIME := 0.1
const TICK_FADE_TIME := 0.5
const TICK_PULSE_PERIOD := 0.9
const TICK_RADIUS := 4.0
## Where a tick lands on its part: this far (px) out from the part's centre
## towards where it jumped from.
const TICK_SPOT := Vector2(8.0, 26.0)
const TICK_PARTS := ["core", "head", "left_shoulder", "right_shoulder", "chassis"]


class Tick:
	var group := 0              # the swarm it came from (TickSwarm.group_id)
	var arena = null            # where its brood would go
	var part := ""
	var node: Node2D            # the part node it sits on
	var local := Vector2.ZERO   # its spot, in node's space
	var from := Vector2.ZERO    # world point it jumped from
	var jump := 0.0             # 0..1 through the jump
	var time_left := 12.0
	var bite_timer := 3.0
	var bleed_timer := 1.0
	var phase := 0.0
	var synced := false
	var middle := false


var ticks: Array[Tick] = []
# Ticks falling off: [world position, seconds left].
var _fading_ticks: Array = []
var _tick_layer: Node2D = null
# Each synced group's brood once it has formed: group -> TickSwarm.
var _tick_broods := {}
# Damage the ticks do themselves doesn't shake ticks off.
var _tick_damage := false
# A blast's armour check (armor_check, is_aoe) names its part here for the
# damage_component that follows it.
var _aoe_part := ""


func get_tick_count() -> int:
	return ticks.size()


## A tick jumping on from `from` (world): it lands on the part nearest to it
## and stays `duration` s. group: its swarm's TickSwarm.group_id; arena_ref:
## where a brood would form. Returns false if there's nowhere to land.
func attach_tick(group: int, arena_ref, from: Vector2, duration: float) -> bool:
	if is_dead:
		return false
	var part := ""
	var best := INF
	for part_name in TICK_PARTS:
		if is_part_lost(part_name) or not _part_fitted(part_name):
			continue
		var d := get_part_global_position(part_name).distance_squared_to(from)
		if d < best:
			best = d
			part = part_name
	if part == "":
		return false
	var tick := Tick.new()
	tick.group = group
	tick.arena = arena_ref
	tick.part = part
	tick.node = _part_node(part)
	var centre := get_part_global_position(part)
	var out := (from - centre).normalized() if from.distance_to(centre) > 1.0 else Vector2.RIGHT.rotated(randf() * TAU)
	var spot := centre + out.rotated(randf_range(-0.7, 0.7)) * randf_range(TICK_SPOT.x, TICK_SPOT.y)
	tick.local = tick.node.to_local(spot)
	tick.from = from
	tick.time_left = duration
	tick.bite_timer = TICK_BITE_PERIOD * randf_range(0.5, 1.0)
	tick.bleed_timer = randf_range(TICK_BLEED_INTERVAL.x, TICK_BLEED_INTERVAL.y)
	tick.phase = randf()
	ticks.append(tick)
	_sync_ticks(group)
	if _tick_layer == null:
		_tick_layer = Node2D.new()
		_tick_layer.name = "Ticks"
		_tick_layer.z_index = 8
		var unshaded := CanvasItemMaterial.new()
		unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_tick_layer.material = unshaded
		_tick_layer.draw.connect(_draw_ticks)
		add_child(_tick_layer)
	return true


## The world position of a tick on this mecha.
func tick_position(tick: Tick) -> Vector2:
	var spot := tick.node.to_global(tick.local)
	return tick.from.lerp(spot, tick.jump) if tick.jump < 1.0 else spot


func _part_fitted(part_name: String) -> bool:
	match part_name:
		"head": return build.head != null
		"left_shoulder", "right_shoulder": return build.shoulders != null
		"chassis": return build.chassis != null
	return build.core != null


func _part_node(part_name: String) -> Node2D:
	match part_name:
		"head": return Head
		"left_shoulder": return LeftShoulder
		"right_shoulder": return RightShoulder
		"chassis": return $Chassis
	return Core


# A group of TICK_SYNC_MIN or more pulls its timers together round its middle
# tick; a smaller one isn't synced.
func _sync_ticks(group: int) -> void:
	var members: Array[Tick] = []
	for tick in ticks:
		if tick.group == group:
			members.append(tick)
	if members.size() < TICK_SYNC_MIN:
		for tick in members:
			tick.synced = false
			tick.middle = false
		return
	members.sort_custom(func(a, b): return a.time_left < b.time_left)
	var middle: Tick = members[members.size() / 2]
	for tick in members:
		tick.time_left = clampf(tick.time_left, middle.time_left - TICK_SYNC_SPREAD, middle.time_left + TICK_SYNC_SPREAD)
		tick.synced = true
		tick.middle = tick == middle


func _update_ticks(dt: float) -> void:
	var drain := 0.0
	var visuals: bool = wants_visuals()
	var i := ticks.size() - 1
	while i >= 0:
		var tick := ticks[i]
		tick.jump = minf(tick.jump + dt / TICK_JUMP_TIME, 1.0)
		tick.phase += dt / TICK_PULSE_PERIOD
		tick.time_left -= dt
		drain += TICK_DRAIN * dt
		tick.bleed_timer -= dt
		if tick.bleed_timer <= 0.0:
			tick.bleed_timer = randf_range(TICK_BLEED_INTERVAL.x, TICK_BLEED_INTERVAL.y)
			if visuals:
				var stains := BloodStains.find(self)
				if stains:
					var at := tick_position(tick)
					stains.spray(at, at - get_part_global_position(tick.part), WOUND_LEAK)
		tick.bite_timer -= dt
		if tick.bite_timer <= 0.0:
			tick.bite_timer = TICK_BITE_PERIOD
			if randf() < TICK_BITE_CHANCE:
				_tick_bite(tick)
		if tick.time_left <= 0.0:
			_tick_done(tick)
		i = mini(i - 1, ticks.size() - 1)
	if drain > 0.0:
		drain_heat(drain, true)
	for k in range(_fading_ticks.size() - 1, -1, -1):
		_fading_ticks[k][1] -= dt
		if _fading_ticks[k][1] <= 0.0:
			_fading_ticks.remove_at(k)
	if _tick_layer != null and visuals:
		_tick_layer.queue_redraw()


# A tick whose time is up: a lone one fades; a synced one forms its group's
# brood (the middle one), joins it, or holds on until the middle one goes.
func _tick_done(tick: Tick) -> void:
	if not tick.synced:
		_remove_tick(tick)
		return
	var brood = _tick_broods.get(tick.group)
	if is_instance_valid(brood) and not brood.is_dead:
		brood.add_motes([tick_position(tick)])
		_remove_tick(tick, false)
		return
	if not tick.middle:
		tick.time_left = 0.0
		return
	var points := []
	var leaving: Array[Tick] = []
	for other in ticks:
		if other.group == tick.group and other.time_left <= 0.0:
			points.append(tick_position(other))
			leaving.append(other)
	brood = TickSwarm.spawn_brood(tick.arena, global_position, points)
	if brood != null:
		_tick_broods[tick.group] = brood
	for other in leaving:
		_remove_tick(other, brood == null)


func _remove_tick(tick: Tick, fade := true) -> void:
	if fade:
		_fading_ticks.append([tick_position(tick), TICK_FADE_TIME])
	ticks.erase(tick)
	var left_in_group := false
	for other in ticks:
		if other.group == tick.group:
			left_in_group = true
			break
	if not left_in_group:
		_tick_broods.erase(tick.group)


# Damage from anything but the ticks: `points` ticks fall off, at random. A
# group left with fewer than TICK_SYNC_MIN stops being synced (no brood).
func _shake_ticks(points: int) -> void:
	if _tick_damage or points <= 0 or ticks.is_empty():
		return
	var groups := {}
	for k in mini(points, ticks.size()):
		var tick: Tick = ticks.pick_random()
		groups[tick.group] = true
		_remove_tick(tick)
	for group in groups:
		if not _tick_broods.has(group):
			_sync_ticks(group)


# One pip from a tick: an external component of its part, or an armour pip
# of the facing it sits on (even chance, the other if one has nothing left).
func _tick_bite(tick: Tick) -> void:
	if is_in_flag_grace() or is_part_lost(tick.part):
		return
	var at := tick_position(tick)
	var facing := get_global_facing_from_angle(at)
	var externals := get_eligible_components(tick.part, facing, false)
	var plate: Dictionary = armor[tick.part][facing]
	var can_plate: bool = plate.level > 0 and plate.pips > 0
	if externals.is_empty() and not can_plate:
		return
	last_damage_source = {"body": null, "name": "Tick Swarm"}
	last_damage_weapon = "Tick Swarm"
	_tick_damage = true
	if not externals.is_empty() and (not can_plate or randf() < 0.5):
		var dir := (get_part_global_position(tick.part) - at).normalized()
		damage_component(tick.part, select_component_by_weight(tick.part, externals), 1, dir)
	else:
		plate.pips -= 1
		_check_part_loss(tick.part, facing)
	_tick_damage = false


# Everything on the mecha is gone when it dies (its update stops).
func _drop_all_ticks() -> void:
	ticks.clear()
	_fading_ticks.clear()
	_tick_broods.clear()
	if _tick_layer != null:
		_tick_layer.queue_redraw()


func _draw_ticks() -> void:
	for tick in ticks:
		var p := _tick_layer.to_local(tick_position(tick))
		var pulse := 0.5 + 0.5 * sin(tick.phase * TAU)
		_draw_tick(p, 0.55 + 0.45 * pulse)
	for fading in _fading_ticks:
		_draw_tick(_tick_layer.to_local(fading[0]), 0.6 * fading[1] / TICK_FADE_TIME)


func _draw_tick(p: Vector2, bright: float) -> void:
	_tick_layer.draw_circle(p, TICK_RADIUS * 2.6, Color(1.0, 1.0, 1.0, 0.14 * bright))
	_tick_layer.draw_circle(p, TICK_RADIUS, Color(0.88, 0.88, 0.88, bright))
	_tick_layer.draw_circle(p, TICK_RADIUS * 0.45, Color(1.0, 1.0, 1.0, bright))


# PARTS COMING OFF
#
# A shoulder (taking the arm and shoulder weapon on its side with it) or the
# head comes off when the facing that just took a hit is at 0 pips and every
# internal component of the part is destroyed (_check_part_loss). The core
# and chassis never do. A Coyote can tear a shoulder or the head off, or an
# arm weapon on its own (lose_part with torn).
#
# The part is hidden, not freed (much keeps references to its nodes). Its
# collision shapes are off and it is in lost_parts, with the weapon slots
# that went with it, which everything that picks a part to damage skips. Its
# components are destroyed (the head's do what destroying them does). Its
# weapons can't fire (shoot, can_fire_at_point), are offline in
# disabled_systems, show as gone on the HUD (WireframeDisplay) and NPCs stop
# using them (_on_weapons_lost); its weight goes (_sum_stat). A blown-off
# part goes up in a large PartDestructionExplosion, a torn-off one sprays
# blood. A copy of it lands on the ground beside the mecha (MechaBody, like a
# wreck's shed parts) and fades after DEBRIS_TIME s. A wreck copies only what
# is still shown, so it keeps the lost parts missing.

const LOSABLE_PARTS := ["left_shoulder", "right_shoulder", "head"]
## What goes when each part comes off: the part and the build slots on it.
const LOST_WITH := {
	"left_shoulder": ["left_shoulder", "arm_weapon_left", "shoulder_weapon_left"],
	"right_shoulder": ["right_shoulder", "arm_weapon_right", "shoulder_weapon_right"],
	"head": ["head"],
	"arm_weapon_left": ["arm_weapon_left"],
	"arm_weapon_right": ["arm_weapon_right"],
}
## Placeholders.
const PART_LOSS_EXPLOSION_SCALE := 1.6
const DEBRIS_TIME := 90.0
const DEBRIS_FADE_TIME := 3.0

signal part_lost(part_name: String)

## Parts that came off (lose_part), and the weapon slots that went with
## them: name -> true.
var lost_parts := {}
# The facing each part was last armour-checked on (armor_check).
var _hit_facing := {}


func is_part_lost(part_name: String) -> bool:
	return lost_parts.has(part_name)


## The design (get_design_data) less what came off: lost slots are empty.
func get_intact_design_data() -> Dictionary:
	var data: Dictionary = get_design_data()
	for slot in data:
		if is_part_lost(slot):
			data[slot] = false
	return data


func _check_part_loss(part_name: String, facing: String) -> void:
	if is_dead or not part_name in LOSABLE_PARTS or is_part_lost(part_name) or not armor.has(part_name):
		return
	if not armor[part_name].has(facing) or int(armor[part_name][facing].pips) > 0:
		return
	var internals := 0
	for comp in components[part_name].values():
		if WOUND_TAG in comp.tags:
			internals += 1
			if not comp.disabled:
				return
	if internals > 0:
		lose_part(part_name)


## Takes a part off: one of LOSABLE_PARTS, or an arm weapon slot on its own.
## Blown off (an explosion), or torn off (a spray of blood). Returns false if
## it isn't fitted or is already gone.
func lose_part(part_name: String, torn := false) -> bool:
	if is_dead or is_part_lost(part_name) or not LOST_WITH.has(part_name):
		return false
	if part_name.begins_with("arm_weapon"):
		if build.get(part_name) == null:
			return false
	elif not _part_fitted(part_name):
		return false
	var at := _lost_part_position(part_name)
	var slots: Array = LOST_WITH[part_name]
	# What a Coyote tears off it carries away; the rest falls.
	_leave_debris(slots.filter(func(s): return not (torn and s == part_name)))
	for slot in slots:
		lost_parts[slot] = true
	_stats_changed()
	_hide_lost(part_name)
	var weapons := []
	for slot in slots:
		if DISABLED_WEAPON_KEYS.has(slot):
			weapons.append(slot)
			disabled_systems[DISABLED_WEAPON_KEYS[slot]] = true
			stop_shooting(slot)
	if not weapons.is_empty():
		_salvos = _salvos.filter(func(s): return not s.slot in weapons)
		_on_weapons_lost(weapons)
	# Ticks on it go with it.
	for tick in ticks.duplicate():
		if is_part_lost(tick.part):
			_remove_tick(tick)
	if part_name in LOSABLE_PARTS:
		_destroy_components(part_name, func(_comp_name, _comp): return true)
	else:
		var shoulder := "left_shoulder" if part_name == "arm_weapon_left" else "right_shoulder"
		_destroy_components(shoulder, func(_comp_name, comp): return "weapon" in comp.tags)
	_show_part_loss(at, torn)
	part_lost.emit(part_name)
	return true


# Every living component of a part that `which(name, comp)` picks is
# destroyed, with the effects destroying it has.
func _destroy_components(part_name: String, which: Callable) -> void:
	for comp_name in components[part_name].keys():
		var comp: Dictionary = components[part_name][comp_name]
		if comp.disabled or not which.call(comp_name, comp):
			continue
		comp.hp = 0
		comp.disabled = true
		_wound_dirty = true
		component_destroyed(part_name, comp_name)
		if is_dead:
			return


func _lost_part_position(part_name: String) -> Vector2:
	match part_name:
		"arm_weapon_left": return LeftArmWeapon.global_position
		"arm_weapon_right": return RightArmWeapon.global_position
	return get_part_global_position(part_name)


func _hide_lost(part_name: String) -> void:
	match part_name:
		"left_shoulder":
			for node in [LeftShoulder, LeftArmWeapon, LeftShoulderWeapon]:
				node.visible = false
			$LeftShoulderCollision.set_deferred("disabled", true)
		"right_shoulder":
			for node in [RightShoulder, RightArmWeapon, RightShoulderWeapon]:
				node.visible = false
			$RightShoulderCollision.set_deferred("disabled", true)
		"head":
			Head.visible = false
			$HeadCollision.set_deferred("disabled", true)
		"arm_weapon_left":
			LeftArmWeapon.visible = false
		"arm_weapon_right":
			RightArmWeapon.visible = false


func _show_part_loss(at: Vector2, torn: bool) -> void:
	if not is_inside_tree():
		return
	if torn:
		var stains := BloodStains.find(self)
		if stains:
			var away := (at - global_position).normalized()
			stains.spray(at, away)
			stains.add_small_splatter(at, away)
		AudioManager.play_sfx("medium_impact1", at)
		return
	var explosion = PART_DESTRUCTION_EXPLOSION.instantiate()
	get_parent().add_child(explosion)
	explosion.global_position = at
	explosion.scale = Vector2.ONE * PART_LOSS_EXPLOSION_SCALE
	AudioManager.play_sfx(FLAG_SFX, at)


# A copy of the part, thrown down beside the mecha, under the mechas, fading
# after DEBRIS_TIME. Copied while still shown.
func _leave_debris(slots: Array) -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var debris := MechaBody.new()
	debris.name = "PartDebris"
	debris.position = global_position
	debris.copy_parts_from(self, slots)
	if debris.get_part_slots().is_empty():
		debris.free()
		return
	var parent := get_parent()
	parent.add_child.call_deferred(debris)
	parent.move_child.call_deferred(debris, 0)
	debris.ready.connect(func():
		for slot in slots:
			debris.shed(slot)
		var fade := debris.create_tween()
		fade.tween_interval(DEBRIS_TIME)
		fade.tween_property(debris, "modulate:a", 0.0, DEBRIS_FADE_TIME)
		fade.tween_callback(debris.queue_free), CONNECT_ONE_SHOT)


## Weapons that came off (Enemy forgets them).
func _on_weapons_lost(_slots: Array) -> void:
	pass


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
	var sys_avg = (disabled_systems.mobility + disabled_systems.sensors + disabled_systems.heat_dispersion) / 3.0
	threat += (working_weapons * 0.5 + sys_avg * 0.5) * 0.15

	# Heat state (15%) — worse of internal vs external temp
	if overheat_temp > 0:
		var heat_ratio = maxf(internal_temp, external_temp) / overheat_temp
		threat += (1.0 - clampf(heat_ratio, 0.0, 1.0)) * 0.15
	else:
		threat += 0.15

	# Flagged/status (15%)
	if is_exposed or flag_up:
		pass  # 0.0 contribution
	elif has_any_status():
		threat += 0.075  # halved
	else:
		threat += 0.15

	return clampf(threat, 0.0, 1.0)
	

var interactables_in_range: Array = []

func add_interactable(thing) -> void:
	if thing not in interactables_in_range:
		interactables_in_range.append(thing)

func remove_interactable(thing) -> void:
	interactables_in_range.erase(thing)

func get_closest_interactable():
	if interactables_in_range.is_empty():
		return null
	var closest = null
	var closest_dist := INF
	for thing in interactables_in_range:
		if not is_instance_valid(thing):
			continue
		var d := global_position.distance_squared_to(thing.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = thing
	return closest


func get_chassis_friction() -> float:
	if build.chassis:
		return build.chassis.friction
	return FALLBACK_FRICTION

func get_chassis_move_heat() -> float:
	if build.chassis:
		return build.chassis.move_heat
	return FALLBACK_MOVE_HEAT

func get_chassis_rotation_acc() -> float:
	if build.chassis:
		return build.chassis.rotation_acc
	return FALLBACK_ROTATION_ACC

func get_chassis_trim_acc() -> float:
	if build.chassis:
		return build.chassis.trim_acc
	return FALLBACK_TRIM_ACC
