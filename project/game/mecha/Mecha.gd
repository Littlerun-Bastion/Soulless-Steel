extends KinematicBody2D
class_name Mecha

enum MODES {NEUTRAL, RELOAD, ACTIVATING_LOCK, LOCK}
enum SIDE {LEFT, RIGHT, SINGLE}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

const DECAL = preload("res://game/mecha/Decal.tscn")
const HITBOX = preload("res://game/mecha/Hitbox.tscn")
const ARM_WEAPON_INITIAL_ROT =  9
const SPEED_MOD_CORRECTION = 3
const WEAPON_RECOIL_MOD = .9
const CHASSIS_SPEED = 20
const SPRINTING_COOLDOWN_SPEED = 2
const SPRINTING_ACC_MOD = 0.2
const LOCKON_RETICLE_SIZE = 15
const DASH_DECAY = 4
const OVERHEAT_BUFFER = 1.1
const HITSTOP_TIMESCALE = 0.1
const HITSTOP_DURATION = 0.25

signal create_projectile
signal create_casing
signal shoot
signal took_damage
signal died
signal player_kill
signal mecha_extracted

export var speed_modifier = 1.0
export var display_mode = false

onready var NavAgent = $NavigationAgent2D

onready var CoreDecals = $CoreDecals
onready var LeftShoulderDecals = $LeftShoulder/Decals
onready var RightShoulderDecals = $RightShoulder/Decals
onready var MovementAnimation = $MovementAnimation
onready var LockCollision = $LockCollision

#Main Parts
onready var Core = $Core
onready var CoreSub = $Core/Sub
onready var CoreGlow = $Core/Glow
onready var Head = $Head
onready var HeadSub = $Head/Sub
onready var HeadGlow = $Head/Glow
onready var HeadPort = $HeadPort
onready var LeftShoulder = $LeftShoulder
onready var RightShoulder = $RightShoulder
#Weapons
onready var LeftArmWeapon = $ArmWeaponLeft
onready var LeftArmWeaponMain = $ArmWeaponLeft/Main
onready var LeftArmWeaponSub = $ArmWeaponLeft/Sub
onready var LeftArmWeaponGlow = $ArmWeaponLeft/Glow
onready var LeftArmWeaponHitboxes = $ArmWeaponLeft/MeleeHitboxes
onready var RightArmWeapon = $ArmWeaponRight
onready var RightArmWeaponMain = $ArmWeaponRight/Main
onready var RightArmWeaponSub = $ArmWeaponRight/Sub
onready var RightArmWeaponGlow = $ArmWeaponRight/Glow
onready var RightArmWeaponHitboxes = $ArmWeaponRight/MeleeHitboxes
onready var LeftShoulderWeapon = $ShoulderWeaponLeft
onready var LeftShoulderWeaponMain = $ShoulderWeaponLeft/Main
onready var LeftShoulderWeaponSub = $ShoulderWeaponLeft/Sub
onready var LeftShoulderWeaponGlow = $ShoulderWeaponLeft/Glow
onready var RightShoulderWeapon = $ShoulderWeaponRight
onready var RightShoulderWeaponMain = $ShoulderWeaponRight/Main
onready var RightShoulderWeaponSub = $ShoulderWeaponRight/Sub
onready var RightShoulderWeaponGlow = $ShoulderWeaponRight/Glow
#Chassis
onready var SingleChassisRoot = $Chassis/Single
onready var SingleChassis = $Chassis/Single/Main
onready var SingleChassisSub = $Chassis/Single/Sub
onready var SingleChassisGlow = $Chassis/Single/Glow
onready var LeftChassisRoot = $Chassis/Left
onready var LeftChassis = $Chassis/Left/Main
onready var LeftChassisSub = $Chassis/Left/Sub
onready var LeftChassisGlow = $Chassis/Left/Glow
onready var RightChassisRoot = $Chassis/Right
onready var RightChassis = $Chassis/Right/Main
onready var RightChassisSub = $Chassis/Right/Sub
onready var RightChassisGlow = $Chassis/Right/Glow
#Particles
onready var Particle = {
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
onready var ChassisSprintGlow = $Chassis/SprintGlow

var mecha_name = "Mecha Name"
var paused = false
var is_dead = false
var cur_mode = MODES.NEUTRAL
var arena = false

var max_hp = 10
var hp = 10
var max_shield = 10
var shield = 10
var shield_regen_cooldown = 5
var max_energy = 100
var energy = 100
var total_kills = 0
var mecha_heat = 0
var mecha_heat_visible = 0
var max_heat = 100
var idle_threshold = 0.15
var move_heat = 70
var battery = 0.0
var battery_capacity = 0.0
var battery_recharge_rate = 0.0
var ecm = 0.0
var ecm_frequency = 0.0
var lock_strength = 1.0

var weight_capacity = 100.0
var is_overweight = false

var movement_type = "free"
var velocity = Vector2()
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

var arm_weapon_left = null
var arm_weapon_right = null
var shoulders = null
var shoulder_weapon_left = null
var shoulder_weapon_right = null
var head = null
var core = null
var generator = null
var chipset = null
var thruster = null
var chassis = null

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
	global_rotation_degrees = rand_range(0, 360)


func _physics_process(dt):
	if paused:
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

	if impact_rotation_velocity > 0 or impact_rotation_velocity < 0:
		global_rotation += impact_rotation_velocity * dt
		impact_rotation_velocity *= 0.95
		if abs(impact_rotation_velocity) < 0.001:
			impact_rotation_velocity = 0

	if is_dead:
		return

	#Blood
	if hp / max_hp < 0.8:
		bleed_timer = max(bleed_timer - dt, 0.0)
		if bleed_timer <= 0.0:
			bleed_timer = rand_range(1, 1.1*max_hp/hp)
			Particle.blood[0].emitting = !Particle.blood[0].emitting
			if hp / max_hp < 0.3:
				Particle.blood[1].emitting = !Particle.blood[1].emitting
			else:
				Particle.blood[1].emitting = false

	#ECM
	ecm_attempt_cooldown = max(ecm_attempt_cooldown - dt, 0.0)

	#Bloom
	for part in ["right_arm", "left_arm", "right_shoulder", "left_shoulder"]:
		if get(part+"_bloom_time") > 0:
			set(part+"_bloom_time", max(get(part+"_bloom_time") - dt, 0))
		else:
			set(part+"_bloom_count", 0)

	#Handle shield
	if generator and shield < max_shield:
		shield_regen_cooldown = max(shield_regen_cooldown - dt, 0.0)
		if shield_regen_cooldown <= 0 and has_status("electrified"):
			shield = min(shield + generator.shield_regen_speed*dt, max_shield)
			shield = round(shield)
			emit_signal("took_damage", self, true)

	#Handle sprinting momentum
	sprinting_ending_correction *= 1.0 - min(SPRINTING_COOLDOWN_SPEED*dt, 1.0)

	#Handle collisions with other mechas and movement
	if not is_stunned() and not is_movement_locked():
		var all_collisions = []
		for i in get_slide_count():
			all_collisions.append(get_slide_collision(i))

		var collided = false
		for collision in all_collisions:
			if collision and collision.collider.is_in_group("mecha"):
				collided = true
				var mod = 2.0
				var rand = rand_range(-PI/8, PI/8)
				var collision_dir = (global_position - collision.collider.global_position).rotated(rand)
				apply_movement(mod*dt, collision_dir)
		if collided:
			lock_movement(0.1)
	else:
		if sprinting_ending_correction.length():
			move(sprinting_ending_correction)
		else:
			apply_movement(dt, Vector2())

	#Update shoulder weapons rotation
	for data in [[shoulder_weapon_left, LeftShoulderWeapon], [shoulder_weapon_right, RightShoulderWeapon]]:
		if data[0]:
			data[1].rotation_degrees += get_best_rotation_diff(data[1].rotation_degrees, 0)*data[0].rotation_acc*dt

	#Handle dash movement
	if not is_stunned() and dash_velocity.length() > 0:
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
	if chassis and chassis.is_legs:
		if moving and not MovementAnimation.is_playing() and\
		   not is_sprinting and dash_velocity.length() <= 0.0:
			MovementAnimation.play("Walking")
		elif (not moving and velocity.length() <= 2.0) or\
			 (is_sprinting or dash_velocity.length() > 0):
			MovementAnimation.stop()
		if not MovementAnimation.is_playing():
			speed_modifier = min(speed_modifier + SPEED_MOD_CORRECTION*dt, 1.0)

	#Locking mechanic
	update_locking(dt)
	if get_locked_to():
		var target_pos = locked_to.global_position
		apply_rotation_by_point(dt, target_pos, false)

	#Status Effects
	update_heat(dt)
	if battery < battery_capacity and not has_status("electrified"):
		battery = min(battery + battery_recharge_rate*dt, battery_capacity)
	for status in status_time.keys():
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
		var ready = dash_cooldown[dir] <= 0
		dash_cooldown[dir] = max(dash_cooldown[dir] - dt, 0.0)
		Particle.dash[dir].cooldown.emitting = dash_cooldown[dir] > 0
		if dash_cooldown[dir] <= 0 and not ready:
			Particle.dash[dir].ready.emitting = true
	update_dash_cooldown_visuals()

	take_status_damage(dt)
	
	process_hitboxes(dt)
	
	if chassis and chassis.hover_particles and not display_mode:
		Particle.chassis_hover[0].speed_scale = max(0.2,velocity.length()/100)
		Particle.chassis_hover[0].modulate = Color(1.0, 1.0, 1.0,max(0.05,velocity.length()/1000))


func is_player():
	return mecha_name == "Player"


func set_pause(value):
	paused = value


func get_design_data():
	var data = {}
	for part_type in ["head", "core", "shoulders", "generator", "chipset", "chassis",\
					  "thruster", "arm_weapon_left", "arm_weapon_right", "shoulders", \
					  "shoulder_weapon_left", "shoulder_weapon_right"]:
		var part = get(part_type)
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

	return data


func set_speed(_max_speed, _move_acc, _friction, _rotation_acc):
	max_speed = _max_speed
	friction = _friction
	rotation_acc = _rotation_acc
	move_acc = _move_acc
	MovementAnimation.playback_speed = move_acc
	if chassis and chassis.is_legs:
		move_acc *= 50
	var animation = MovementAnimation.get_animation("Walking")
	var track = 0 #animation.find_track("Mecha:speed_modifier")
	animation.track_set_key_value(track, 2, move_acc/100.0)
	animation.track_set_key_value(track, 5, move_acc/100.0)


func update_max_life_from_parts():
	var value = 0
	if core:
		value += core.health
	if head:
		value += head.health
	if chassis:
		value += chassis.health
	set_max_life(value)


func update_max_shield_from_parts():
	var value = 0
	if core:
		value += core.shield
	if generator:
		value += generator.shield
	#Check shoulders
	if shoulders:
		value += shoulders.shield

	set_max_shield(value)


func set_max_life(value):
	max_hp = value
	hp = max_hp


func set_max_shield(value):
	max_shield = value
	shield = max_shield


func set_max_energy(value):
	max_energy = value
	energy = max_energy


func take_damage(amount, shield_mult, health_mult, heat_damage, status_amount, status_type, hitstop, source_info, weapon_name := "Test", calibre := CALIBRE_TYPES.SMALL):
	if is_dead:
		return

	if hitstop:
		if source_info.name == "Player" or self.name == "Player":
			do_hitstop()

	if amount > 0 and generator:
		shield_regen_cooldown = generator.shield_regen_delay
	var temp_shield = shield
	shield = max(shield - (shield_mult * amount), 0)
	amount = max(amount - temp_shield, 0)

	if status_type and status_amount > 0.0:
		set_status(status_type, status_amount)

	hp = max(hp - (health_mult * amount), 0)
	if amount > max_hp/0.25:
		Particle.blood[2].emitting = true
	mecha_heat = min(mecha_heat + heat_damage, max_heat * OVERHEAT_BUFFER)
	if shield <= 0:
		select_impact(calibre, false)
	else:
		select_impact(calibre, true)
	emit_signal("took_damage", self, false)

	last_damage_source = source_info
	last_damage_weapon = weapon_name

	if hp <= 0:
		AudioManager.play_sfx("final_explosion", global_position, null, null, 1.25, 10000)
		die(source_info, weapon_name)


func do_hitstop():
	Engine.time_scale = HITSTOP_TIMESCALE
	yield(get_tree().create_timer(HITSTOP_DURATION * HITSTOP_TIMESCALE), "timeout")
	Engine.time_scale = 1.0


func has_status(status_name):
	assert(status_time.has(status_name), "Not a valid status name: " + str(status_name))
	return status_time[status_name] > 0.0


func has_any_status():
	for status in status_time.values():
		if status > 0.0:
			return true
	return false


func set_status(status_name, amount):
	assert(status_time.has(status_name), "Not a valid status name: " + str(status_name))
	status_time[status_name] = amount


func decrease_status(status_name, amount):
	assert(status_time.has(status_name), "Not a valid status name: " + str(status_name))
	status_time[status_name] = max(status_time[status_name] - amount, 0.0)


func take_status_damage(dt):
	if is_dead:
		return

	if has_status("overheating"):
		hp -= (max_hp * 0.02 * dt)
		hp = round(hp)
		if hp <= 0:
			AudioManager.play_sfx("final_explosion", global_position, null, null, 1.25, 10000)
			die(last_damage_source, last_damage_weapon)
			die(last_damage_source, last_damage_weapon)

	if has_status("fire"):
		mecha_heat = min(mecha_heat + dt * 10, max_heat * OVERHEAT_BUFFER)

	if has_status("electrified"):
		shield = round(max(shield - (dt * 100), 0))
		emit_signal("took_damage", self, true)
		if generator:
			shield_regen_cooldown = generator.shield_regen_delay

	if has_status("corrosion"):
		hp = round(max(hp - (dt * 100), 1))
		emit_signal("took_damage", self, true)

func freezing_status_slowdown(speed):
	if has_status("freezing"):
		speed *= 0.5
	return speed

func freezing_status_heat(heat_disp):
	if has_status("freezing"):
		heat_disp *= 2
	return heat_disp

func die(source_info, _weapon_name):
	if is_dead:
		return
	is_dead = true
	yield(get_tree().create_timer(3.0), "timeout")
	#TickerManager.new_message({
	#	"type": "mecha_died",
	#	"source": source_info.name,
	#	"self": self.mecha_name,
	#	"weapon_name": weapon_name,
	#	})
	if is_instance_valid(source_info):
		if is_player():
			emit_signal("player_kill")
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
	if is_instance_valid(decals_node):
		if shape == $CoreCollision:
			decals_node = CoreDecals
		elif shape == $LeftShoulderCollision:
			decals_node = LeftShoulderDecals
		elif shape == $RightShoulderCollision:
			decals_node = RightShoulderDecals
		else:
			push_error("Not a valid shape id: " + str(id))
		var decal = DECAL.instance()

		#Transform global position into local position
		var final_pos = decal_position-decals_node.global_position
		var trans = decals_node.global_transform
		final_pos = final_pos.rotated(-trans.get_rotation())
		final_pos /= trans.get_scale()
		final_pos *= rand_range(.6,.9) #Random depth for decal on mecha
		decals_node.add_child(decal)
		decal.setup(type, size, final_pos)


func update_heat(dt):
	#Main Mecha Heat
	if display_mode == true:
		mecha_heat = max_heat - 1
		return
	if generator and not has_status("fire"):
		if mecha_heat > max_heat*idle_threshold:
			mecha_heat = max(mecha_heat - freezing_status_heat(generator.heat_dispersion)*dt, max_heat*idle_threshold)
		else:
			mecha_heat = max(mecha_heat - freezing_status_heat(generator.heat_dispersion * (mecha_heat/max_heat))*dt, 0)
		for weapon in [LeftArmWeapon, RightArmWeapon, LeftShoulderWeapon, RightShoulderWeapon]:
			weapon.update_heat(generator.heat_dispersion, dt)
	if generator:
		if mecha_heat >= max_heat:
			set_status("overheating", 5.0)
	if not has_status("overheating"):
		mecha_heat_visible = max(mecha_heat_visible - freezing_status_heat(generator.heat_dispersion)*dt*4, mecha_heat)
	else:
		mecha_heat_visible = min(mecha_heat_visible + 0.5, 150)
	for node in [Core, CoreSub, CoreGlow, Head, HeadSub, HeadGlow, HeadPort, LeftShoulder, RightShoulder,\
				 SingleChassis, SingleChassisSub, SingleChassisGlow, LeftChassis, LeftChassisSub, LeftChassisGlow,\
				 RightChassis, RightChassisSub, RightChassisGlow]:
		node.material.set_shader_param("heat", mecha_heat_visible)


#PARTS SETTERS

func set_arm_weapon(part_name, side):
	if part_name and not core:
		push_error("Mecha doesn't have a core to assign arm weapon")
		return

	var node
	if side == SIDE.LEFT:
		node = $ArmWeaponLeft
		node.side = SIDE.LEFT
	elif side == SIDE.RIGHT:
		node = $ArmWeaponRight
		node.side = SIDE.RIGHT
	else:
		push_error("Not a valid side: " + str(side))

	if not part_name:
		if side == SIDE.LEFT:
			arm_weapon_left = null
		else:
			arm_weapon_right = null
		node.set_images(null, null, null)
		return

	var part_data = PartManager.get_part("arm_weapon", part_name)
	if side == SIDE.LEFT:
		arm_weapon_left = part_data
		node.rotation_degrees = -ARM_WEAPON_INITIAL_ROT if not part_data.is_melee else 0
	else:
		arm_weapon_right = part_data
		node.rotation_degrees = ARM_WEAPON_INITIAL_ROT if not part_data.is_melee else 0

	if node.has_node("AttackAnimation"):
		node.get_node("AttackAnimation").queue_free()

	node.setup(part_data)
	node.set_images(part_data.get_image(), part_data.get_sub(), part_data.get_glow())
	node.position = core.get_arm_weapon_offset(side)
	node.set_offsets(-part_data.get_attach_pos())
	if not part_data.is_melee:
		node.clear_shooting_pos()
		if part_data.get_num_shooting_pos() > 0:
			for idx in part_data.get_num_shooting_pos():
				var defined_pos = part_data.get_shooting_pos(idx + 1)
				var shooting_position = Position2D.new()
				shooting_position.position = defined_pos.position + node.offset
				node.add_child(shooting_position)
				node.set_shooting_pos(shooting_position)
	else:
		node.add_child(part_data.get_attack_animation().duplicate())


func set_shoulder_weapon(part_name, side):
	if part_name and not core:
		push_error("Mecha doesn't have a core to assign shoulder weapon")
		return

	var node
	if side == SIDE.LEFT:
		node = $ShoulderWeaponLeft
		node.side = SIDE.LEFT
	elif side == SIDE.RIGHT:
		node = $ShoulderWeaponRight
		node.side = SIDE.RIGHT
	else:
		push_error("Not a valid side: " + str(side))

	if not part_name or not core.has_left_shoulder or not core.has_right_shoulder:
		if side == SIDE.LEFT or not core.has_left_shoulder:
			shoulder_weapon_left = null
		elif side == SIDE.RIGHT or not core.has_right_shoulder:
			shoulder_weapon_right = null
		node.set_images(null, null, null)
		return

	var part_data = PartManager.get_part("shoulder_weapon", part_name)
	if side == SIDE.LEFT:
		shoulder_weapon_left = part_data
	else:
		shoulder_weapon_right = part_data
	node.set_images(part_data.get_image(), part_data.get_sub(), part_data.get_glow())
	node.position = core.get_shoulder_weapon_offset(side)
	node.set_offsets(-part_data.get_attach_pos())
	node.clear_shooting_pos()
	if part_data.get_num_shooting_pos() > 0 and not display_mode:
		for idx in part_data.get_num_shooting_pos():
			var defined_pos = part_data.get_shooting_pos(idx)
			var shooting_position = Position2D.new()
			if defined_pos:
				shooting_position.position = defined_pos.position + node.offset
			node.add_child(shooting_position)
			node.set_shooting_pos(shooting_position)
	#node.set_shooting_pos(part_data.get_shooting_pos())
	node.setup(part_data)


func set_core(part_name):
	var part_data = PartManager.get_part("core", part_name)
	Core.texture = part_data.get_image()
	$CoreCollision.polygon = part_data.get_collision()
	core = part_data
	if core.get_head_port() != null:
		$HeadPort.texture = core.get_head_port()
		$HeadPort.position = core.get_head_offset()
	else:
		$HeadPort.texture = null
	var index = 1
	for node in Particle.overheating:
		#Ignores "OverheatingSparks"
		if node.name.find("Sparks") == -1:
			var offset = core.get_overheat_offset(index)
			if offset:
				node.position = offset
			else:
				node.visible = false
			index += 1
	if not core.has_left_shoulder:
		set_shoulder_weapon(null, SIDE.LEFT)
	if not core.has_right_shoulder:
		set_shoulder_weapon(null, SIDE.RIGHT)
	CoreSub.texture = core.get_sub()
	CoreGlow.texture = core.get_glow()
	update_max_life_from_parts()
	update_max_shield_from_parts()
	stability = get_stat("stability")
	reset_offsets()


func set_generator(part_name):
	if part_name:
		var part_data = PartManager.get_part("generator", part_name)
		generator = part_data
		generator.heat_capacity = max_heat
		idle_threshold = generator.idle_threshold / 100
		battery_capacity = generator.battery_capacity
		battery = generator.battery_capacity
		battery_recharge_rate = generator.battery_recharge_rate
	else:
		generator = false
	update_max_shield_from_parts()


func set_chipset(part_name):
	if part_name:
		var part_data = PartManager.get_part("chipset", part_name)
		chipset = part_data
		ecm = chipset.ECM
		ecm_frequency = chipset.ECM_frequency
		lock_strength = chipset.lock_on_strength
	else:
		chipset = false


func set_thruster(part_name):
	if part_name:
		var part_data = PartManager.get_part("thruster", part_name)
		thruster = part_data
	else:
		thruster = false


func set_chassis(part_name):
	if not part_name:
		remove_chassis("single")
		remove_chassis("pair")
		movement_type = "free"
		return
	chassis = PartManager.get_part("chassis", part_name)
	weight_capacity = chassis.weight_capacity
	set_chassis_parts()


func set_chassis_parts():
	if chassis.is_legs:
			remove_chassis("single")
			set_chassis_nodes(RightChassis, RightChassisSub, RightChassisGlow, $ChassisRightCollision, SIDE.RIGHT)
			set_chassis_nodes(LeftChassis, LeftChassisSub, LeftChassisGlow, $ChassisLeftCollision, SIDE.LEFT)
	else:
		remove_chassis("pair")
		set_chassis_nodes(SingleChassis, SingleChassisSub, SingleChassisGlow, $ChassisSingleCollision, false)
	stability = get_stat("stability")
	Particle.chassis_hover[0].emitting = (chassis.hover_particles and not display_mode)
	Particle.chassis_hover[1].emitting = (chassis.hover_particles and not display_mode)


func set_chassis_nodes(main,sub,glow,collision,side = false):
	if core and chassis.is_legs:
		var pos = core.get_chassis_offset(side)
		main.position = pos
		sub.position = pos
		glow.position = pos
		collision.position = pos
	main.texture = chassis.get_image(side)
	sub.texture = chassis.get_sub(side)
	glow.texture = chassis.get_glow(side)
	collision.polygon = chassis.get_collision(side)
	movement_type = chassis.movement_type
	move_heat = chassis.move_heat
	set_speed(chassis.max_speed, chassis.move_acc, chassis.friction, chassis.rotation_acc)
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
		head = part_data
		if core:
			Head.position = core.get_head_offset()
	else:
		Head.texture = null
		HeadSub.texture = null
		HeadGlow.texture = null
		head = null
	update_max_life_from_parts()


func set_shoulders(part_name):
	if part_name:
		var part_data = PartManager.get_part("shoulders", part_name)
		shoulders = part_data
		if core:
			$LeftShoulder.position = core.get_shoulder_offset(SIDE.LEFT)
			$LeftShoulderCollision.position = core.get_shoulder_offset(SIDE.LEFT)
			$RightShoulder.position = core.get_shoulder_offset(SIDE.RIGHT)
			$RightShoulderCollision.position = core.get_shoulder_offset(SIDE.RIGHT)
		else:
			push_error("No core for putting on shoulders.")
		$LeftShoulder.texture = part_data.get_image(SIDE.LEFT)
		$RightShoulder.texture = part_data.get_image(SIDE.RIGHT)
		$LeftShoulderCollision.polygon = part_data.get_collision(SIDE.LEFT)
		$RightShoulderCollision.polygon = part_data.get_collision(SIDE.RIGHT)
	else:
		shoulders = null
		$LeftShoulder.texture = null
		$RightShoulder.texture = null
	update_max_shield_from_parts()
	arm_accuracy_mod = get_stat("arms_accuracy_modifier")
	stability = get_stat("stability")

func reset_offsets():
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
		if chassis:
			set_chassis_parts()

#ATTRIBUTE METHODS

func get_max_hp():
	return max_hp


func get_stat(stat_name):
	var total_stat = 0.0
	var parts = [arm_weapon_left, arm_weapon_right, shoulders,\
				 shoulder_weapon_left, shoulder_weapon_right,\
				 head, core, generator, chipset, thruster,\
				 chassis]
	for part in parts:
		if part and part.get(stat_name):
			total_stat += part[stat_name]
	return float(total_stat)


func get_weapon_part(part_name):
	if part_name == "arm_weapon_left":
		if arm_weapon_left:
			return $ArmWeaponLeft
	elif part_name == "arm_weapon_right":
		if arm_weapon_right:
			return $ArmWeaponRight
	elif part_name == "shoulder_weapon_left":
		if shoulder_weapon_left:
			return $ShoulderWeaponLeft
	elif part_name == "shoulder_weapon_right":
		if shoulder_weapon_right:
			return $ShoulderWeaponRight
	else:
		push_error("Not a valid weapon part name: " + str(part_name))

	return false


func get_clip_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		if part.uses_battery:
			return battery
		else:
			return part.clip_ammo
	return false

func get_battery_drain(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.battery_drain
	return false


func get_clip_size(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.clip_size
	return false


func get_total_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		if part.uses_battery:
			return battery
		else:
			return part.total_ammo - (get_clip_size(part_name) - get_clip_ammo(part_name))
	return false

func get_max_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.max_ammo
	return false

func get_ammo_cost(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.ammo_cost
	return false

func set_ammo(part_name, target_val):
	var part = get_weapon_part(part_name)
	if typeof(target_val) == TYPE_INT:
		part.total_ammo = target_val

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
	if is_player():
		NavAgent.set_velocity(vec)
		velocity = move_and_slide(vec)
	else:
		NavAgent.set_velocity(vec)


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
	var dir = get_dir_name(dash_dir)
	if not dir:
		return #Not a valid dash direction

	if dash_cooldown[dir] <= 0.0 and not has_status("freezing"):
		mecha_heat = min(mecha_heat + thruster.dash_heat, max_heat  * OVERHEAT_BUFFER)
		dash_velocity = dash_dir.normalized()*dash_strength
		for node in Particle.chassis_dash:
			node.rotation_degrees = rad2deg(dash_dir.angle()) + 90
			node.restart()
			node.emitting = true
		Particle.grind[0].restart()
		Particle.grind[0].emitting = true
		if movement_type == "relative":
			dash_velocity = dash_velocity.rotated(deg2rad(rotation_degrees))
		dash_cooldown[dir] = thruster.dash_cooldown
		Particle.dash[dir].cooldown.emitting = true


func update_dash_cooldown_visuals():
	if is_dead or not thruster:
		return
	for dir in ["fwd", "rwd", "left", "right"]:
		Particle.dash[dir].cooldown.modulate = Color(1, 1, 1, 0.33*(dash_cooldown[dir] / thruster.dash_cooldown))


func weight_speed_modifier(speed):
	return speed
	#if get_stat("weight") > weight_capacity * 0.75:
	#	is_overweight = true
	#	if get_stat("weight") > weight_capacity:
	#		speed *= 0.33
	#	else:
	#		speed *= 0.5
	#else:
	#	is_overweight = false
	#return speed

func apply_movement(dt, direction):
	if is_sprinting:
		#Disable horizontal and backwards movement when sprinting
		if movement_type != "tank":
			direction.x = 0
		direction.y = min(direction.y, 0.0)
	var target_move_acc = clamp(move_acc*dt, 0, 1)
	var target_speed = direction.normalized() * max_speed
	var mult = 1.0
	if thruster:
		var thrust_max_speed = weight_speed_modifier(max_speed + thruster.thrust_max_speed)

		if is_sprinting and not has_status("freezing") and direction != Vector2(0,0):
			mult = freezing_status_slowdown(weight_speed_modifier(thruster.thrust_speed_multiplier))
			mecha_heat = min(mecha_heat + thruster.sprinting_heat*dt, max_heat * OVERHEAT_BUFFER)
			for node in Particle.chassis_sprint:
				node.emitting = true
			ChassisSprintGlow.visible = true
			Particle.grind[1].emitting = true
			if movement_type != "tank":
				target_speed.y = min(target_speed.y * mult, target_speed.y + thrust_max_speed)
				target_move_acc *= clamp(target_move_acc*SPRINTING_ACC_MOD, 0, 1)
		elif direction == Vector2(0,0):
			for node in Particle.chassis_sprint:
				node.emitting = false
			ChassisSprintGlow.visible = false
			Particle.grind[1].emitting = false
	if movement_type == "free":
		if direction.length() > 0:
			moving = true
			velocity = lerp(velocity, freezing_status_slowdown(weight_speed_modifier(target_speed)), freezing_status_slowdown(weight_speed_modifier(target_move_acc)))
			mecha_heat = min(mecha_heat +move_heat*dt, max_heat * OVERHEAT_BUFFER)
		else:
			moving = false
			velocity *= 1 - chassis.friction
		var mod = 1.0 if is_sprinting else speed_modifier
		move(velocity*mod)
	elif movement_type == "relative":
		if direction.length() > 0:
			moving = true
			moving_axis.x = direction.x != 0
			moving_axis.y = direction.y != 0
			target_speed = target_speed.rotated(deg2rad(rotation_degrees))
			velocity = lerp(velocity, freezing_status_slowdown(weight_speed_modifier(target_speed)), freezing_status_slowdown(weight_speed_modifier(target_move_acc)))
			mecha_heat += move_heat*dt
		else:
			moving = false
			moving_axis.x = false
			moving_axis.y = false
			velocity *= 1 - chassis.friction
		var mod = 1.0 if is_sprinting else speed_modifier
		move(velocity*mod)
	elif movement_type == "tank":
		if direction.length() > 0:
			moving = false
			if direction.y > 0:
				moving = true
				target_speed = tank_move_target.rotated(deg2rad(90)) * max_speed * mult/1.5
			if direction.y < 0:
				moving = true
				target_speed = tank_move_target.rotated(deg2rad(270)) * max_speed * mult/1.5
			if thruster:
				var thrust_max_speed = max_speed + thruster.thrust_max_speed
				if target_speed.length() > (target_speed.normalized() * thrust_max_speed).length():
					target_speed = target_speed.normalized() * thrust_max_speed
			var _rotation_acc = freezing_status_slowdown(weight_speed_modifier(chassis.rotation_acc * 50))
			if direction.y == 0:
				_rotation_acc *= 2
			if direction.x > 0:
				tank_move_target = tank_move_target.rotated(deg2rad(_rotation_acc*dt))
				global_rotation_degrees += _rotation_acc*dt
			elif direction.x < 0:
				tank_move_target = tank_move_target.rotated(deg2rad(-_rotation_acc*dt))
				global_rotation_degrees -= _rotation_acc*dt
			if not moving:
				velocity *= 1 - chassis.friction
			else:
				velocity = lerp(velocity, freezing_status_slowdown(weight_speed_modifier(target_speed)), freezing_status_slowdown(weight_speed_modifier(target_move_acc)))
				mecha_heat = min(mecha_heat + move_heat*dt, max_heat * OVERHEAT_BUFFER)
		else:
			if chassis:
				velocity *= 1 - chassis.friction/2
		move(velocity)
	else:
		push_error("Not a valid movement type: " + str(movement_type))
	update_chassis_visuals(dt)

#Rotates solely the body given a direction ('clock' or 'counter'clock wise)
func apply_rotation_by_direction(dt, direction):
	var _rotation_acc = rotation_acc
	if is_sprinting == true:
		_rotation_acc = 0
	if direction == "clock":
		rotation_degrees += 90*_rotation_acc*dt
	elif direction == "counter":
		rotation_degrees -= 90*_rotation_acc*dt
	else:
		push_error("Not a valid direction: " + str(direction))


func apply_rotation_by_point(dt, target_pos, stand_still):
	#Rotate Body
	var _rotation_acc = rotation_acc
	if movement_type == "tank" and chassis:
		_rotation_acc = chassis.trim_acc
	if is_sprinting == true and movement_type != "tank":
		_rotation_acc = rotation_acc/2
	if not stand_still:
		rotation_degrees += get_rotation_diff_by_point(dt, global_position, target_pos, rotation_degrees, _rotation_acc)


	#Rotate Head and Shoulders
	for data in [[$Head, head], [$LeftShoulder, shoulders], [$RightShoulder, shoulders]]:
		var node_ref = data[1]
		if node_ref:
			var node = data[0]
			var actual_rot = node.rotation_degrees + rotation_degrees
			node.rotation_degrees += get_rotation_diff_by_point(dt, node.global_position, target_pos, actual_rot, node_ref.rotation_acc)
			node.rotation_degrees = clamp(node.rotation_degrees, -node_ref.rotation_range, node_ref.rotation_range)

	#Rotate Non-Melee Arm Weapons
	for data in [[$ArmWeaponLeft, arm_weapon_left], [$ArmWeaponRight, arm_weapon_right]]:
		var node_ref = data[1]
		if node_ref and not node_ref.is_melee:
			var node = data[0]
			var actual_rot = node.rotation_degrees + rotation_degrees
			node.rotation_degrees += get_rotation_diff_by_point(dt, node.global_position, target_pos, actual_rot, node_ref.rotation_acc)
			if node == $ArmWeaponLeft:
				node.rotation_degrees += node_ref.parallax_offset
			else:
				node.rotation_degrees -= node_ref.parallax_offset
			node.rotation_degrees = clamp(node.rotation_degrees, -core.rotation_range, core.rotation_range)

	for data in	[[$Chassis/Left, chassis], [$Chassis/Right, chassis]]:
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
	var target_rot = rad2deg(origin.angle_to_point(target_pos)) + 270
	return get_best_rotation_diff(cur_rot, target_rot)*acc*dt


func knockback(strength, knockback_dir, should_rotate = true):
	impact_velocity += (knockback_dir.normalized() * (strength * get_stability()))
	if should_rotate:
		if impact_rotation_velocity > 0:
			impact_rotation_velocity += strength / (get_stat("stability")*10)
		elif impact_rotation_velocity < 0:
			impact_rotation_velocity -= strength / (get_stat("stability")*10)
		else:
			if randi()%2 == 1:
				impact_rotation_velocity += strength / (get_stat("stability")*10)
			else:
				impact_rotation_velocity -= strength / (get_stat("stability")*10)


func update_chassis_visuals(dt):
	var angulation = 25
	if chassis and chassis.is_legs:
		var rot_vec = Vector2(1, 0).rotated(deg2rad(rotation_degrees))
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
			child.rotation_degrees = lerp(child.rotation_degrees, left_target_angle,\
										  dt*CHASSIS_SPEED)
		for child in RightChassisRoot.get_children():
			child.rotation_degrees = lerp(child.rotation_degrees, right_target_angle,\
										  dt*CHASSIS_SPEED)

func stop_sprinting(sprint_dir):
	if is_sprinting and sprint_dir != Vector2(0,0):
		sprinting_ending_correction = Vector2(velocity.x, velocity.y)
		lock_movement(0.5 * get_stability())
		Particle.grind[0].restart()
		Particle.grind[0].emitting = true
		for node in [Particle.chassis_dash[0], Particle.chassis_dash[2]]:
			node.rotation_degrees = rad2deg(Vector2(0,-1).angle()) + 90
			node.restart()
			node.emitting = true
		mecha_heat = min(mecha_heat + thruster.dash_heat/2, max_heat  * OVERHEAT_BUFFER)
	is_sprinting = false
	for node in Particle.chassis_sprint:
		node.emitting = false
	ChassisSprintGlow.visible = false
	Particle.grind[1].emitting = false

#COMBAT METHODS

func shoot(type, is_auto_fire = false):
	var node
	var weapon_ref
	var bloom
	var eject_angle = 0.0
	if type == "arm_weapon_left":
		node = $ArmWeaponLeft
		weapon_ref = arm_weapon_left
		left_arm_bloom_time = weapon_ref.bloom_reset_time * get_stability()
		bloom = left_arm_bloom_count * weapon_ref.accuracy_bloom
		eject_angle = 180.0
	elif type ==  "arm_weapon_right":
		node = $ArmWeaponRight
		weapon_ref = arm_weapon_right
		right_arm_bloom_time = weapon_ref.bloom_reset_time * get_stability()
		bloom = right_arm_bloom_count * weapon_ref.accuracy_bloom
	elif type == "shoulder_weapon_left":
		node = $ShoulderWeaponLeft
		weapon_ref = shoulder_weapon_left
		left_shoulder_bloom_time = weapon_ref.bloom_reset_time * get_stability()
		bloom = left_shoulder_bloom_count * weapon_ref.accuracy_bloom
		eject_angle = 180.0
	elif type ==  "shoulder_weapon_right":
		node = $ShoulderWeaponRight
		weapon_ref = shoulder_weapon_right
		right_shoulder_bloom_time = weapon_ref.bloom_reset_time * get_stability()
		bloom = right_shoulder_bloom_count * weapon_ref.accuracy_bloom
	else:
		push_error("Not a valid type of weapon to shoot: " + str(type))

	if weapon_ref.is_melee:
		node.light_attack()
		mecha_heat = min(mecha_heat + weapon_ref.muzzle_heat, max_heat * OVERHEAT_BUFFER)
		emit_signal("shoot")
		return

	while node.burst_count < weapon_ref.burst_size:
		if is_dead:
			return
		var amount
		if weapon_ref.uses_battery:
			amount = weapon_ref.number_projectiles
			if not node.can_shoot_battery(weapon_ref.battery_drain, battery) or has_status("electrified"):
				if is_player() and weapon_ref.battery_drain > battery and not is_auto_fire:
					AudioManager.play_sfx("no_ammo", global_position)
				return
			node.shoot_battery()
			battery = max(battery - weapon_ref.battery_drain, 0)
		else:
			amount = min(weapon_ref.burst_ammo_cost, get_clip_ammo(type))
			amount = max(amount, 1) #Tries to shoot at least 1 projectile
			if not node.can_shoot(amount):
				if is_player() and node.clip_ammo <= 0 and not is_auto_fire:
					AudioManager.play_sfx("no_ammo", global_position)
				return
			node.shoot(amount)

		#Create projectile
		if not weapon_ref.is_melee:
			var max_angle = weapon_ref.max_bloom_angle/head.accuracy_modifier
			if type == "arm_weapon_left" or type == "arm_weapon_right":
				max_angle = max_angle/arm_accuracy_mod
				bloom /= arm_accuracy_mod
			if locked_to:
				max_angle = max_angle/chipset.accuracy_modifier
			var total_accuracy = min(weapon_ref.base_accuracy + bloom, max_angle)/head.accuracy_modifier
			var current_accuracy = rand_range(-total_accuracy, total_accuracy)
			for _i in range(weapon_ref.number_projectiles):
				emit_signal("create_projectile", self,
							{
								"weapon_data": weapon_ref,
								"pos": node.get_shoot_position().global_position,
								"pos_reference": node.get_shoot_position(),
								"dir": node.get_direction(weapon_ref.bullet_spread, current_accuracy),
								"muzzle_flash": weapon_ref.muzzle_flash,
								"muzzle_flash_size": weapon_ref.muzzle_flash_size,
								"muzzle_flash_speed": weapon_ref.muzzle_flash_speed,
								"damage_mod": weapon_ref.damage,
								"shield_mult": weapon_ref.shield_mult,
								"health_mult": weapon_ref.health_mult,
								"heat_damage": weapon_ref.heat_damage,
								"status_damage": weapon_ref.status_damage,
								"status_type": weapon_ref.status_type,
								"delay": rand_range(0, weapon_ref.bullet_spread_delay),
								"bullet_drag": weapon_ref.bullet_drag,
								"bullet_drag_var": weapon_ref.bullet_drag_var,
								"projectile_size": weapon_ref.projectile_size,
								"projectile_size_scaling": weapon_ref.projectile_size_scaling,
								"projectile_size_scaling_var": weapon_ref.projectile_size_scaling_var,
								"lifetime": weapon_ref.lifetime,
								"impact_force": weapon_ref.impact_force,
								"beam_range": weapon_ref.beam_range,
								"has_trail": weapon_ref.has_trail,
								"trail_lifetime": weapon_ref.trail_lifetime,
								"trail_lifetime_range": weapon_ref.trail_lifetime_range,
								"trail_eccentricity": weapon_ref.trail_eccentricity,
								"trail_min_spawn_distance" : weapon_ref.trail_min_spawn_distance,
								"trail_width" : weapon_ref.trail_width,

								"has_smoke": weapon_ref.has_smoke,
								"smoke_density": weapon_ref.smoke_density,
								"smoke_lifetime": weapon_ref.smoke_lifetime,

								"has_wiggle": weapon_ref.has_wiggle,
								"wiggle_amount": weapon_ref.wiggle_amount,
								"is_seeker": weapon_ref.is_seeker,
								"seeker_target": locked_to,
								"seek_time": weapon_ref.seek_time,
								"seek_agility": weapon_ref.seeker_agility,
								"seeker_angle": weapon_ref.seeker_angle,

								"impact_effect": weapon_ref.impact_effect,
								"impact_size": weapon_ref.impact_size,
								"hitstop": weapon_ref.hitstop,
							}, node) #TODO: FIX THIS
			apply_recoil(type, node, weapon_ref.recoil_force)
		if weapon_ref.eject_casings:
			emit_signal("create_casing",
							{
								"casing_ejector_pos": node.global_position,
								"casing_eject_angle": eject_angle + self.global_rotation_degrees,
								"casing_size": weapon_ref.casing_size,
							})
		mecha_heat = min(mecha_heat + weapon_ref.muzzle_heat, max_heat * OVERHEAT_BUFFER)
		if type == "arm_weapon_left":
			left_arm_bloom_count += 1
		elif type ==  "arm_weapon_right":
			right_arm_bloom_count += 1
		elif type == "shoulder_weapon_left":
			left_shoulder_bloom_count += 1
		elif type ==  "shoulder_weapon_right":
			right_shoulder_bloom_count += 1
		emit_signal("shoot")
	node.burst_cooldown()

func apply_recoil(type, node, recoil):
	var rotation = recoil*300/get_stat("weight")
	if "left" in type:
		rotation *= -1
	rotation_degrees += rotation
	node.rotation_degrees += rotation*WEAPON_RECOIL_MOD

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
			   mouse_pos.distance_to(area.global_position) <= chipset.lock_on_reticle_size + a_radius:
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
				locking_to.progress = min(locking_to.progress + (dt*chipset.lock_on_speed * 0.5), 1.0)
			else:
				locking_to.progress = min(locking_to.progress + dt*chipset.lock_on_speed, 1.0)
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
				assert(to_erase.empty(), "This shouldn't happen, problem with lingering hitboxes usage")
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
		
		take_damage(data.damage, 1.0, 1.0, 10, 0, false, false, false)
		if data.knockback > 0.0:
			knockback(data.knockback, data.collision_point - data.hitbox_position, true)
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

# MISC METHODS

func cancel_extract():
	$ExtractTimer.stop()
	$ExtractTimer.wait_time = 5


func select_impact(calibre, is_shield):
	var sfx_idx
	match calibre:
		CALIBRE_TYPES.LARGE:
			if is_shield:
				sfx_idx = "large_shield_impact" + str((randi()%2) + 1)
			else:
				sfx_idx = "large_impact" + str((randi()%2) + 1)
		CALIBRE_TYPES.MEDIUM:
			if is_shield:
				sfx_idx = "small_shield_impact" + str((randi()%3) + 1)
			else:
				sfx_idx = "medium_impact" + str((randi()%2) + 1)
		CALIBRE_TYPES.SMALL:
			if is_shield:
				sfx_idx = "small_shield_impact" + str((randi()%3) + 1)
			else:
				sfx_idx = "small_impact" + str((randi()%2) + 1)
		CALIBRE_TYPES.FIRE:
			sfx_idx = false
		_:
			push_error("Not a valid calibre type:" + str(calibre))

	if sfx_idx:
		AudioManager.play_sfx(sfx_idx, global_position)


func play_step_sound(is_left := true):
	if mecha_name != "Player" or not moving:
		return
	var pitch
	if is_left:
		pitch = rand_range(.7, .72)
	else:
		pitch = rand_range(.95, .97)

	var volume = min(pow(velocity.length(), 1.3)/300.0 - 23.0, -5.0)
	AudioManager.play_sfx("robot_step", global_position, pitch, volume)


func extracting():
	$ExtractTimer.start()

# CALLBACKS

func _on_ExtractTimer_timeout():
	if self.name == "Player":
		emit_signal("mecha_extracted", self)
	else:
		emit_signal("died", self)


func _on_MeleeHitboxes_create_hitbox(data, side):
	var hitbox = HITBOX.instance()
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
