extends Mecha

onready var Cam = $Camera2D

func _ready():
	setup()

func _physics_process(delta):
	apply_movement(delta)
	apply_rotation(delta)


func _input(event):
	if event.is_action_pressed("honk"):
		AudioManager.play_sfx("test", global_position)


func apply_movement(dt):
	var direction = get_input()
	if direction.length() > 0:
		velocity = lerp(velocity, direction.normalized() * max_speed, move_acc*dt)
	else:
		velocity = lerp(velocity, Vector2.ZERO, friction)
	
	velocity = move_and_slide(velocity)


func apply_rotation(dt):
	var rot_eps = 5
	var mouse_pos = get_global_mouse_position()
	var target_rot = fmod(rad2deg(global_position.angle_to_point(mouse_pos)) + 270, 360)
	var diff = target_rot - rotation_degrees
	if diff > 180:
		diff -= 360
	elif diff < -180:
		diff += 360
	
	#Rotate properly clock or counter-clockwise fastest to target rotation
	if abs(diff) <= rot_eps:
		rotation_degrees = target_rot
	elif diff > 0:
		rotation_degrees += rotation_acc*dt
	else:
		rotation_degrees -= rotation_acc*dt


func setup():
	pass


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

