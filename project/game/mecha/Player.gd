extends Mecha

const ROTATION_DEADZONE = 20

onready var Cam = $Camera2D


func _ready():
	setup()


func _physics_process(delta):
	apply_movement(delta, get_input())
	
	var target_pos = get_global_mouse_position()
	if target_pos.distance_to(global_position) > ROTATION_DEADZONE:
		apply_rotation(delta, target_pos, Input.is_action_pressed("strafe"))


func _input(event):
	if event.is_action_pressed("honk"):
		AudioManager.play_sfx("test", global_position)
	elif event.is_action_pressed("left_arm_weapon_shoot"):
		shoot("left_arm_weapon")
	elif event.is_action_pressed("right_arm_weapon_shoot"):
		shoot("right_arm_weapon")
	elif event.is_action_pressed("left_shoulder_weapon_shoot"):
		shoot("left_shoulder_weapon")
	elif event.is_action_pressed("right_shoulder_weapon_shoot"):
		shoot("right_shoulder_weapon")


func setup():
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
