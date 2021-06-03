extends Mecha

onready var Cam = $Camera2D

func _ready():
	setup()

func _physics_process(_delta):
	var direction = get_input()
	
	if direction.length() > 0:
		velocity = lerp(velocity, direction.normalized() * max_speed, acceleration)
	else:
		velocity = lerp(velocity, Vector2.ZERO, friction)
	
	velocity = move_and_slide(velocity)


func _input(event):
	if event.is_action_pressed("honk"):
		AudioManager.play_sfx("test", global_position)


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

