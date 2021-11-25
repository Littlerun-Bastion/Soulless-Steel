extends Mecha

signal update_reload_mode
signal reloading
signal finished_reloading

const ROTATION_DEADZONE = 20

onready var Cam = $Camera2D

var reload_mode := false

func _ready():
	setup()


func _physics_process(delta):
	if is_stunned():
		return
	
	check_input()
	
	apply_movement(delta, get_input())
	
	var target_pos = get_global_mouse_position()
	if target_pos.distance_to(global_position) > ROTATION_DEADZONE:
		apply_rotation(delta, target_pos, \
					   movement_type == "tank" or Input.is_action_pressed("strafe"))

func _input(event):
	if event.is_action_pressed("honk"):
		AudioManager.play_sfx("test", global_position)
	elif event.is_action_pressed("left_arm_weapon_shoot") and arm_weapon_left:
		if reload_mode:
			$ArmWeaponLeft.reload()
		elif not $ArmWeaponLeft.reloading:
			shoot("left_arm_weapon")
	elif event.is_action_pressed("right_arm_weapon_shoot") and arm_weapon_right:
		if reload_mode:
			$ArmWeaponRight.reload()
		elif not $ArmWeaponRight.reloading:
			shoot("right_arm_weapon")
	elif event.is_action_pressed("left_shoulder_weapon_shoot") and shoulder_weapon_left:
		shoot("left_shoulder_weapon")
	elif event.is_action_pressed("right_shoulder_weapon_shoot") and shoulder_weapon_right:
		shoot("right_shoulder_weapon")
	elif event.is_action_pressed("reload_mode") and not reload_mode:
		reload_mode = true
		emit_signal("update_reload_mode", reload_mode)
	elif event.is_action_released("reload_mode") and reload_mode:
		reload_mode = false
		emit_signal("update_reload_mode", reload_mode)
	elif event.is_action_pressed("debug_1"):
		die()


func knockback(pos, strength, should_rotate = true):
	.knockback(pos, strength, should_rotate)
	if strength > 0:
		var dur = sqrt(strength)/10
		var freq = pow(strength, .3)*5
		var amp = pow(strength, .3)*5
		Cam.shake(dur, freq, amp, strength)


func apply_recoil(type, recoil):
	.apply_recoil(type, recoil)
	if recoil > 0:
		var dur = sqrt(recoil)/10
		var freq = pow(recoil, .3)*5
		var amp = pow(recoil, .3)*5
		Cam.shake(dur, freq, amp, recoil)


func check_input():
	check_weapon_input("left_arm_weapon", $ArmWeaponLeft, arm_weapon_left)
	check_weapon_input("right_arm_weapon", $ArmWeaponRight, arm_weapon_right)
	check_weapon_input("left_shoulder_weapon", $ShoulderWeaponLeft, shoulder_weapon_left)
	check_weapon_input("right_shoulder_weapon", $ShoulderWeaponRight, shoulder_weapon_right)


func check_weapon_input(name, node, weapon_ref):
	if weapon_ref and weapon_ref.auto_fire and not reload_mode and\
	   not node.reloading and Input.is_action_pressed(name+"_shoot"):
		shoot(name)


func setup():
	movement_type = "tank"
	rotation_acc = 2.0
	friction = 0.3
	set_max_life(100)
	set_core("core_test2")
	set_head("head_test2")
	set_legs("legs_test")
	set_arm_weapon("test_weapon1", SIDE.LEFT)
	set_arm_weapon("test_weapon2", SIDE.RIGHT)
	set_shoulder_weapon("test_weapon1", SIDE.RIGHT)
	set_shoulder_weapon(false, SIDE.LEFT)
	set_shoulder("shoulder_test2_left", SIDE.LEFT)
	set_shoulder("shoulder_test2_right", SIDE.RIGHT)


func set_arm_weapon(part_name, side):
	.set_arm_weapon(part_name, side)
	var node
	if side == SIDE.LEFT:
		node = $ArmWeaponLeft
	elif side == SIDE.RIGHT:
		node = $ArmWeaponRight
	node.connect("finished_reloading", self, "_on_finished_reloading")
	node.connect("reloading", self, "_on_reloading", [side])


func get_input():
	var mov_vec = Vector2()
	if Input.is_action_pressed('right'):
		mov_vec.x += 1
	if Input.is_action_pressed('left'):
		mov_vec.x -= 1
	if Input.is_action_pressed('down'):
		mov_vec.y += 1
	if Input.is_action_pressed('up'):
		mov_vec.y -= 1
	
	return mov_vec


func get_cam():
	return Cam


func _on_finished_reloading():
	emit_signal("finished_reloading")


func _on_reloading(reload_time, side):
	emit_signal("reloading", reload_time, side)
