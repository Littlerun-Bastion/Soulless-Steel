extends Mecha

const ROTATION_DEADZONE = 20

onready var Cam = $Camera2D


func _ready():
	setup()


func _physics_process(delta):
	check_input()
	
	apply_movement(delta, get_input())
	
	var target_pos = get_global_mouse_position()
	if target_pos.distance_to(global_position) > ROTATION_DEADZONE:
		apply_rotation(delta, target_pos, Input.is_action_pressed("strafe"))

func _input(event):
	if event.is_action_pressed("honk"):
		AudioManager.play_sfx("test", global_position)
	elif event.is_action_pressed("left_arm_weapon_shoot") and arm_weapon_left:
		shoot("left_arm_weapon")
	elif event.is_action_pressed("right_arm_weapon_shoot") and arm_weapon_right:
		shoot("right_arm_weapon")
	elif event.is_action_pressed("left_shoulder_weapon_shoot") and shoulder_weapon_left:
		shoot("left_shoulder_weapon")
	elif event.is_action_pressed("right_shoulder_weapon_shoot") and shoulder_weapon_right:
		shoot("right_shoulder_weapon")
	elif event.is_action_pressed("debug_1"):
		die()


func knockback(pos, strength):
	.knockback(pos, strength)
	var dur = sqrt(strength)/10
	var freq = pow(strength, .3)*5
	var amp = pow(strength, .3)*5
	Cam.shake(dur, freq, amp, strength)


func apply_recoil(type, recoil):
	.apply_recoil(type, recoil)
	var dur = sqrt(recoil)/10
	var freq = pow(recoil, .3)*5
	var amp = pow(recoil, .3)*5
	Cam.shake(dur, freq, amp, recoil)


func check_input():
	check_weapon_input("left_arm_weapon", arm_weapon_left)
	check_weapon_input("right_arm_weapon", arm_weapon_right)
	check_weapon_input("left_shoulder_weapon", shoulder_weapon_left)
	check_weapon_input("right_shoulder_weapon", shoulder_weapon_right)


func check_weapon_input(name, weapon_ref):
	if weapon_ref and weapon_ref.auto_fire and Input.is_action_pressed(name+"_shoot"):
		shoot(name)


func setup():
	set_max_life(100)
	set_arm_weapon("test_weapon1", SIDE.LEFT)
	set_arm_weapon("test_weapon2", SIDE.RIGHT)
	set_shoulder_weapon("test_weapon1", SIDE.RIGHT)
	set_shoulder_weapon(false, SIDE.LEFT)
	set_head("head_test")
	set_core("core_test")
	set_shoulder("shoulder_test_left", SIDE.LEFT)
	set_shoulder("shoulder_test_right", SIDE.RIGHT)


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
