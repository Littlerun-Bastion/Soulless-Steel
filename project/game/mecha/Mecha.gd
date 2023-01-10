extends KinematicBody2D
class_name Mecha

enum MODES {NEUTRAL, RELOAD, ACTIVATING_LOCK, LOCK}
enum SIDE {LEFT, RIGHT, SINGLE}
enum CALIBRE_TYPES {SMALL, MEDIUM, LARGE, FIRE}

const DECAL = preload("res://game/mecha/Decal.tscn")
const ARM_WEAPON_INITIAL_ROT = 9
const SPEED_MOD_CORRECTION = 3
const CHASSIS_SPEED = 20
const SPRINTING_COOLDOWN_SPEED = 2
const SPRINTING_ACC_MOD = 1.5
const LOCKON_RETICLE_SIZE = 15
const DASH_DECAY = 25000

signal create_projectile
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
onready var LeftArmWeaponSub = $ArmWeaponLeft/Sub
onready var LeftArmWeaponGlow = $ArmWeaponLeft/Glow
onready var RightArmWeapon = $ArmWeaponRight
onready var RightArmWeaponSub = $ArmWeaponRight/Sub
onready var RightArmWeaponGlow = $ArmWeaponRight/Glow
onready var LeftShoulderWeapon = $ShoulderWeaponLeft
onready var LeftShoulderWeaponSub = $ShoulderWeaponLeft/Sub
onready var LeftShoulderWeaponGlow = $ShoulderWeaponLeft/Glow
onready var RightShoulderWeapon = $ShoulderWeaponRight
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
var move_heat = 70

var movement_type = "free"
var velocity = Vector2()
var is_sprinting = false
var sprinting_ending_correction = Vector2()
var dash_velocity = Vector2()
var dash_strength = 5000
var moving = false
var moving_axis = {
	"x": false,
	"y": false,
}
var max_speed = 500
var friction = 0.1
var move_acc = 50
var rotation_acc = 5
var arm_accuracy_mod := 0.0
var stability := 1.0


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

var total_weight = 0.0
var weight_capacity = 0.0

var fire_status_time = 0.0
var electrified_status_time = 2.0
var freezing_status_time = 0.0
var corrode_status_time = 0.0


func _ready():
	for node in [Core, CoreSub, CoreGlow, Head, HeadSub, HeadGlow, HeadPort,
				 LeftShoulder, RightShoulder,\
				 LeftArmWeapon, LeftArmWeaponSub, LeftArmWeaponGlow,\
				 RightArmWeapon, RightArmWeaponSub, RightArmWeaponGlow,\
				 LeftShoulderWeapon, LeftShoulderWeaponSub, LeftShoulderWeaponGlow,\
				 RightShoulderWeapon, RightShoulderWeaponSub, RightShoulderWeaponGlow,\
				 SingleChassis, SingleChassisSub, SingleChassisGlow, LeftChassis, LeftChassisSub, LeftChassisGlow,\
				 RightChassis, RightChassisSub, RightChassisGlow]:
		node.material = CoreSub.material.duplicate(true)


func _physics_process(dt):
	if paused:
		return

	#Bloom
	if right_arm_bloom_time > 0:
		right_arm_bloom_time -= dt
	else:
		right_arm_bloom_count = 0

	if left_arm_bloom_time > 0:
		left_arm_bloom_time -= dt
	else:
		left_arm_bloom_count = 0

	if right_shoulder_bloom_time > 0:
		right_shoulder_bloom_time -= dt
	else:
		right_shoulder_bloom_count = 0

	if left_shoulder_bloom_time > 0:
		left_shoulder_bloom_time -= dt
	else:
		left_shoulder_bloom_count = 0

	#Handle shield
	if generator and shield < max_shield:
		shield_regen_cooldown = max(shield_regen_cooldown - dt, 0.0)
		if shield_regen_cooldown <= 0 and electrified_status_time <= 0.0:
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
				var dir = (global_position - collision.collider.global_position).rotated(rand)
				apply_movement(mod*dt, dir)
		if collided:
			lock_movement(0.1)
	else:
		if sprinting_ending_correction.length():
			move(sprinting_ending_correction)
		else:
			apply_movement(dt, Vector2())

	#Handle dash movement
	if not is_stunned() and dash_velocity.length() > 0:
		move(dash_velocity)
		if dash_velocity.x > 0:
			dash_velocity.x = max(dash_velocity.x - DASH_DECAY*dt, 0)
		else:
			dash_velocity.x = min(dash_velocity.x + DASH_DECAY*dt, 0)

		if dash_velocity.y > 0:
			dash_velocity.y = max(dash_velocity.y - DASH_DECAY*dt, 0)
		else:
			dash_velocity.y = min(dash_velocity.y + DASH_DECAY*dt, 0)
		if dash_velocity.length() < 1:
			dash_velocity = Vector2()

	if moving and not MovementAnimation.is_playing() and\
	   not is_sprinting and dash_velocity.length() <= 0.0:
		MovementAnimation.play("Walking")
	elif (not moving and velocity.length() <= 2.0) or\
		 (is_sprinting or dash_velocity.length() > 0):
		MovementAnimation.stop()

	if not MovementAnimation.is_playing():
		speed_modifier = min(speed_modifier + SPEED_MOD_CORRECTION*dt, 1.0)

	update_heat(dt)

	update_locking(dt)

	if get_locked_to():
		var target_pos = locked_to.global_position
		apply_rotation_by_point(dt, target_pos, false)

	#Status Effects
	if fire_status_time > 0.0:
		fire_status_time = max(fire_status_time - dt, 0.0)
		$FireParticles2.emitting = true
		$FireParticles.emitting = true
	elif fire_status_time <= 0.0:
		$FireParticles2.emitting = false
		$FireParticles.emitting = false

	if electrified_status_time > 0.0:
		electrified_status_time = max(electrified_status_time - dt, 0.0)
		$ElectricParticles.emitting = true
	elif electrified_status_time <= 0.0:
		$ElectricParticles.emitting = false

	if freezing_status_time > 0.0:
		freezing_status_time = max(freezing_status_time - dt, 0.0)
		$FreezingParticles2.emitting = true
		$FreezingParticles.emitting = true
	elif freezing_status_time <= 0.0:
		$FreezingParticles2.emitting = false
		$FreezingParticles.emitting = false

	if corrode_status_time > 0.0:
		corrode_status_time = max(corrode_status_time - dt, 0.0)
		$CorrosionParticles.emitting = true
		$CorrosionParticles2.emitting = true
	elif corrode_status_time <= 0.0:
		$CorrosionParticles.emitting = false
		$CorrosionParticles2.emitting = false

	take_status_damage(dt)


func is_player():
	return mecha_name == "Player"


func set_pause(value):
	paused = value


func get_design_data():
	var data = {}
	for part_type in ["arm_weapon_left", "arm_weapon_right", "shoulders", \
					  "shoulder_weapon_left", "shoulder_weapon_right", \
					  "head", "core", "generator", "chipset", "thruster", "chassis"]:
		var part = get(part_type)
		data[part_type] = part.part_id if part else false

	return data


func set_parts_from_design(data):
	for part_name in ["arm_weapon_left", "arm_weapon_right", "shoulders", \
					  "shoulder_weapon_left", "shoulder_weapon_right", \
					  "head", "core", "generator", "chipset", "thruster", "chassis"]:
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
	move_acc = min(_move_acc, 100.0)
	MovementAnimation.playback_speed = max_speed/200
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


func take_damage(amount, shield_mult, health_mult, heat_damage, status_amount, status_type, source_info, weapon_name := "Test", calibre := CALIBRE_TYPES.SMALL):
	if is_dead:
		return

	if amount > 0 and generator:
		shield_regen_cooldown = generator.shield_regen_delay
	var temp_shield = shield
	shield = max(shield - (shield_mult * amount), 0)
	amount = max(amount - temp_shield, 0)
	
	if status_type and status_amount > 0.0:
		if status_type == "Fire":
			fire_status_time = status_amount
		elif status_type == "Electrified":
			electrified_status_time = status_amount
		elif status_type == "Corrode":
			corrode_status_time = status_amount
		elif status_type == "Freezing":
			freezing_status_time = status_amount

	hp = max(hp - (health_mult * amount), 0)
	mecha_heat += heat_damage
	if shield <= 0:
		select_impact(calibre, false)
	else:
		select_impact(calibre, true)
	emit_signal("took_damage", self, false)
	if hp <= 0:
		AudioManager.play_sfx("final_explosion", global_position, null, null, 1.25, 10000)
		die(source_info, weapon_name)

func take_status_damage(dt):
	if is_dead:
		return


	if fire_status_time > 0.0:
		mecha_heat += dt * 10

	if electrified_status_time > 0.0:
		shield = round(max(shield - (dt * 100), 0))
		emit_signal("took_damage", self, true)
		if generator:
			shield_regen_cooldown = generator.shield_regen_delay

	if corrode_status_time > 0.0:
		hp = round(max(hp - (dt * 100), 1))
		emit_signal("took_damage", self, true)

func die(source_info, weapon_name):
	is_dead = true
	TickerManager.new_message({
		"type": "mecha_died",
		"source": source_info.name,
		"self": self.mecha_name,
		"weapon_name": weapon_name,
		})
	if source_info.name == "Player":
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
		mecha_heat = 100
		return
	if generator and fire_status_time <= 0.0:
		mecha_heat = max(mecha_heat - generator.heat_dispersion*dt, 0)
		for weapon in [LeftArmWeapon, RightArmWeapon, LeftShoulderWeapon, RightShoulderWeapon]:
			weapon.update_heat(generator.heat_dispersion, dt)
	for node in [Core, CoreSub, CoreGlow, Head, HeadSub, HeadGlow, HeadPort, LeftShoulder, RightShoulder,\
				 SingleChassis, SingleChassisSub, SingleChassisGlow, LeftChassis, LeftChassisSub, LeftChassisGlow,\
				 RightChassis, RightChassisSub, RightChassisGlow]:
		node.material.set_shader_param("heat", mecha_heat)


#PARTS SETTERS

func set_arm_weapon(part_name, side):
	var node
	if side == SIDE.LEFT:
		node = $ArmWeaponLeft
	elif side == SIDE.RIGHT:
		node = $ArmWeaponRight
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
		node.rotation_degrees = -ARM_WEAPON_INITIAL_ROT
	else:
		arm_weapon_right = part_data
		node.rotation_degrees = ARM_WEAPON_INITIAL_ROT
	node.set_images(part_data.get_image(), part_data.get_sub(), part_data.get_glow())
	node.set_offsets(-part_data.get_attach_pos())
	if core:
		node.position = core.get_arm_weapon_offset(side)
	node.set_shooting_pos(part_data.get_shooting_pos())
	node.setup(part_data)
	total_weight = get_stat("weight")


func set_shoulder_weapon(part_name, side):
	var node
	if side == SIDE.LEFT:
		node = $ShoulderWeaponLeft
	elif side == SIDE.RIGHT:
		node = $ShoulderWeaponRight
	else:
		push_error("Not a valid side: " + str(side))


	if not part_name:
		if side == SIDE.LEFT:
			shoulder_weapon_left = null
		else:
			shoulder_weapon_right = null
		node.set_images(null, null, null)
		return

	var part_data = PartManager.get_part("shoulder_weapon", part_name)
	if side == SIDE.LEFT:
		shoulder_weapon_left = part_data
	else:
		shoulder_weapon_right = part_data
	node.set_images(part_data.get_image(), part_data.get_sub(), part_data.get_glow())
	node.set_offsets(-part_data.get_attach_pos())
	if core:
		node.position = core.get_shoulder_weapon_offset(side)
	node.set_shooting_pos(part_data.get_shooting_pos())
	node.setup(part_data)
	total_weight = get_stat("weight")


func set_core(part_name):
	var part_data = PartManager.get_part("core", part_name)
	Core.texture = part_data.get_image()
	$CoreCollision.polygon = part_data.get_collision()
	core = part_data
	if core.get_head_port() != null:
		$HeadPort.texture = core.get_head_port()
		$HeadPort.position = core.get_head_port_offset()
	else:
		$HeadPort.texture = null
	CoreSub.texture = core.get_sub()
	CoreGlow.texture = core.get_glow()
	update_max_life_from_parts()
	update_max_shield_from_parts()
	total_weight = get_stat("weight")
	stability = get_stat("stability")


func set_generator(part_name):
	if part_name:
		var part_data = PartManager.get_part("generator", part_name)
		generator = part_data
	else:
		generator = false
	update_max_shield_from_parts()
	total_weight = get_stat("weight")


func set_chipset(part_name):
	if part_name:
		var part_data = PartManager.get_part("chipset", part_name)
		chipset = part_data
	else:
		chipset = false
	total_weight = get_stat("weight")


func set_thruster(part_name):
	if part_name:
		var part_data = PartManager.get_part("thruster", part_name)
		thruster = part_data
	else:
		thruster = false
	total_weight = get_stat("weight")


func set_chassis(part_name):
	if not part_name:
		remove_chassis("single")
		remove_chassis("pair")
		movement_type = "free"
		return
	chassis = PartManager.get_part("chassis", part_name)
	if chassis.is_legs:
			remove_chassis("single")
			set_chassis_nodes(RightChassis, RightChassisSub, RightChassisGlow, $ChassisRightCollision, SIDE.RIGHT)
			set_chassis_nodes(LeftChassis, LeftChassisSub, LeftChassisGlow, $ChassisLeftCollision, SIDE.LEFT)
	else:
		remove_chassis("pair")
		set_chassis_nodes(SingleChassis, SingleChassisSub, SingleChassisGlow, $ChassisSingleCollision, false)
	weight_capacity = chassis.weight_capacity
	total_weight = get_stat("weight")
	stability = get_stat("stability")


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
	total_weight = get_stat("weight")

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
	var part_data = PartManager.get_part("head", part_name)
	Head.texture = part_data.get_image()
	HeadSub.texture = part_data.get_sub()
	HeadGlow.texture = part_data.get_glow()
	head = part_data
	if core:
		Head.position = core.get_head_port_offset()
	update_max_life_from_parts()
	total_weight = get_stat("weight")


func set_shoulders(part_name):
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
	update_max_shield_from_parts()
	total_weight = get_stat("weight")
	arm_accuracy_mod = get_stat("arms_accuracy_modifier")
	stability = get_stat("stability")

#ATTRIBUTE METHODS

func get_max_hp():
	return max_hp


func get_stat(stat_name):
	var total_stat = 0.0
	var num_parts = 0
	var parts = [arm_weapon_left, arm_weapon_right, shoulders,\
				 shoulder_weapon_left, shoulder_weapon_right,\
				 head, core, generator, chipset, thruster,\
				 chassis]
	for part in parts:
		if part and part.get(stat_name):
			total_stat += part[stat_name]
			num_parts += 1
	if stat_name == "stability":
		total_stat = total_stat/num_parts
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
		return part.clip_ammo
	return false


func get_clip_size(part_name):
	var part = get_weapon_part(part_name)
	if part:
		return part.clip_size
	return false


func get_total_ammo(part_name):
	var part = get_weapon_part(part_name)
	if part:
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


func dash(dir):
	if dash_velocity.length() == 0 and dir.length() > 0:
		dash_velocity = dir.normalized()*dash_strength
		if movement_type == "relative":
			dash_velocity = dash_velocity.rotated(deg2rad(rotation_degrees))


func apply_movement(dt, direction):
	if is_sprinting:
		#Disable horizontal and backwards movement when sprinting
		direction.x = 0
		direction.y = min(direction.y, 0.0)
	var target_move_acc = clamp(move_acc*dt, 0, 1)
	var target_speed = direction.normalized() * max_speed
	if thruster:
		var mult = thruster.thrust_speed_multiplier
		if is_sprinting:
			mecha_heat = min(mecha_heat + thruster.sprinting_heat*dt, 100)
			target_speed.y *= mult
			target_move_acc *= clamp(target_move_acc*SPRINTING_ACC_MOD, 0, 1)
	if movement_type == "free":
		if direction.length() > 0:
			moving = true
			velocity = lerp(velocity, target_speed, target_move_acc)
			mecha_heat = min(mecha_heat + move_heat*dt, 100)
		else:
			moving = false
			velocity = lerp(velocity, Vector2.ZERO, friction)
		move(velocity*speed_modifier)
	elif movement_type == "relative":
		if direction.length() > 0:
			moving = true
			moving_axis.x = direction.x != 0
			moving_axis.y = direction.y != 0
			target_speed = target_speed.rotated(deg2rad(rotation_degrees))
			velocity = lerp(velocity, target_speed, target_move_acc)
			mecha_heat = min(mecha_heat + move_heat*dt, 100)
		else:
			moving = false
			moving_axis.x = false
			moving_axis.y = false
			velocity = lerp(velocity, Vector2.ZERO, friction)
		move(velocity*speed_modifier)
	elif movement_type == "tank":
		if direction.length() > 0:
			moving = false
			match get_direction_from_vector(direction):
				"down":
					direction = Vector2(0,1).rotated(deg2rad(rotation_degrees))
					moving = true
				"left":
					apply_rotation_by_direction(dt, "counter")
				"up":
					direction = -Vector2(0,1).rotated(deg2rad(rotation_degrees))
					moving = true
				"right":
					apply_rotation_by_direction(dt, "clock")

			if not moving:
				velocity = lerp(velocity, Vector2.ZERO, friction)
			else:
				velocity = lerp(velocity, target_speed, target_move_acc)
				mecha_heat = min(mecha_heat + move_heat*dt, 100)
			move(velocity)

		else:
			velocity = lerp(velocity, Vector2.ZERO, friction)
			move(velocity*speed_modifier)
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
	if is_sprinting == true:
		_rotation_acc = rotation_acc/5
	if not stand_still:
		rotation_degrees += get_target_rotation_diff(dt, global_position, target_pos, rotation_degrees, _rotation_acc)


	#Rotate Arm Weapons
	for data in [[$ArmWeaponLeft, arm_weapon_left], [$ArmWeaponRight, arm_weapon_right],\
				 [$Head, head]]:
		var node_ref = data[1]
		if node_ref:
			var node = data[0]
			var actual_rot = node.rotation_degrees + rotation_degrees
			node.rotation_degrees += get_target_rotation_diff(dt, node.global_position, target_pos, actual_rot, node_ref.rotation_acc)
			node.rotation_degrees = clamp(node.rotation_degrees, -node_ref.rotation_range, node_ref.rotation_range)


func get_target_rotation_diff(dt, origin, target_pos, cur_rotation, acc):
	var target_rot = rad2deg(origin.angle_to_point(target_pos)) + 270
	var diff = target_rot - cur_rotation
	if diff > 180:
		diff -= 360
	elif diff < -180:
		diff += 360

	#Rotate properly clock or counter-clockwise fastest to target rotation
	if diff > 0:
		return abs(diff)*acc*dt
	else:
		return -abs(diff)*acc*dt


func knockback(pos, strength, should_rotate = true):
	apply_movement(sqrt(strength)*2/get_stat("weight"), global_position - pos)
	if should_rotate:
		apply_rotation_by_point(sqrt(strength)*2/get_stat("weight"), pos, false)


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

func stop_sprinting():
	if is_sprinting:
		sprinting_ending_correction = Vector2(velocity.x, velocity.y)
		lock_movement(0.5)
	is_sprinting = false

#COMBAT METHODS

func shoot(type, is_auto_fire = false):
	var node
	var weapon_ref
	var bloom
	if type == "arm_weapon_left":
		node = $ArmWeaponLeft
		weapon_ref = arm_weapon_left
		left_arm_bloom_time = weapon_ref.instability
		bloom = left_arm_bloom_count * weapon_ref.accuracy_bloom
		left_arm_bloom_count += 1
	elif type ==  "arm_weapon_right":
		node = $ArmWeaponRight
		weapon_ref = arm_weapon_right
		right_arm_bloom_time = weapon_ref.instability
		bloom = right_arm_bloom_count * weapon_ref.accuracy_bloom
		right_arm_bloom_count += 1
	elif type == "shoulder_weapon_left":
		node = $ShoulderWeaponLeft
		weapon_ref = shoulder_weapon_left
		left_shoulder_bloom_time = weapon_ref.instability
		bloom = left_shoulder_bloom_count * weapon_ref.accuracy_bloom
		left_shoulder_bloom_count += 1
	elif type ==  "shoulder_weapon_right":
		node = $ShoulderWeaponRight
		weapon_ref = shoulder_weapon_right
		right_shoulder_bloom_time = weapon_ref.instability
		bloom = right_shoulder_bloom_count * weapon_ref.accuracy_bloom
		right_shoulder_bloom_count += 1
	else:
		push_error("Not a valid type of weapon to shoot: " + str(type))

	var amount = 1


	if weapon_ref.uses_battery:
		amount = min(weapon_ref.number_projectiles, get_clip_ammo(type))

	else:
		amount = min(weapon_ref.burst_ammo_cost, get_clip_ammo(type))
		amount = max(amount, 1) #Tries to shoot at least 1 projectile


		if not node.can_shoot(amount):
			if is_player() and node.clip_ammo <= 0 and not is_auto_fire:
				AudioManager.play_sfx("no_ammo", global_position)
			return

	node.shoot(amount)

	var variation = weapon_ref.bullet_spread/float(amount + 1)
	var angle_offset = -weapon_ref.bullet_spread /2
	var total_accuracy = weapon_ref.base_accuracy
	total_accuracy += bloom
	if type == "arm_weapon_left" or type == "arm_weapon_right":
		total_accuracy = total_accuracy / arm_accuracy_mod
	if locked_to:
		total_accuracy = total_accuracy/chipset.accuracy_modifier
	if total_accuracy > weapon_ref.base_accuracy * weapon_ref.max_bloom_factor:
		total_accuracy = weapon_ref.base_accuracy * weapon_ref.max_bloom_factor
	for _i in range(weapon_ref.number_projectiles):
		angle_offset += variation
		emit_signal("create_projectile", self,
					{
						"weapon_data": weapon_ref.projectile,
						"weapon_name": weapon_ref.part_name,
						"pos": node.get_shoot_position(),
						"dir": node.get_direction(angle_offset, total_accuracy),
						"damage_mod": weapon_ref.damage_modifier,
						"shield_mult": weapon_ref.shield_mult,
						"health_mult": weapon_ref.health_mult,
						"heat_damage": weapon_ref.heat_damage,
						"status_damage": weapon_ref.status_damage,
						"status_type": weapon_ref.status_type,
						"delay": rand_range(0, weapon_ref.bullet_spread_delay),
						"bullet_velocity": weapon_ref.bullet_velocity,
						"projectile_size": weapon_ref.projectile_size,
						"lifetime": weapon_ref.lifetime,
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
						"smoke_trail_material": weapon_ref.smoke_trail_material,
						"smoke_texture": weapon_ref.smoke_texture,

						"has_wiggle": weapon_ref.has_wiggle,
						"wiggle_amount": weapon_ref.wiggle_amount,
						"is_seeker": weapon_ref.is_seeker,
						"seeker_target": locked_to,
						"seek_time": weapon_ref.seek_time,
						"seek_agility": weapon_ref.seeker_agility,
						"seeker_angle": weapon_ref.seeker_angle,

						"impact_size": weapon_ref.impact_size
					})
	apply_recoil(type, weapon_ref.recoil_force)
	emit_signal("shoot")

func apply_recoil(type, recoil):
	var rotation = recoil*300/get_stat("weight")
	if "left" in type:
		rotation *= -1
	rotation_degrees += rotation


func is_stunned():
	return not $StunTimer.is_stopped()


func is_movement_locked():
	return not $LockMovementTimer.is_stopped()


func stun(time):
	$StunTimer.wait_time = time
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
			if electrified_status_time > 0.0:
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


# MISC METHODS

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


func _on_ExtractTimer_timeout():
	if self.name == "Player":
		emit_signal("mecha_extracted", self)
	else:
		emit_signal("died", self)


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
