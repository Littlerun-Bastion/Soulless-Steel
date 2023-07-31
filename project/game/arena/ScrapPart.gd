extends RigidBody2D

const LIFETIME_MIN = 5
const LIFETIME_MAX = 5.5
const FADEOUT_MIN = .4
const FADEOUT_MAX = .8


func _ready():
	start_death()


func setup(image):
	$Sprite2D.texture = image
	$Sprite2D.material = $Sprite2D.material.duplicate(true)


func update_scale(value):
	for child in get_children():
		if not child.get("scale") == null:
			child.scale = value


func set_heat_parameters(heat, min_darkness):
	$Sprite2D.material.set_shader_parameter("heat", heat)
	$Sprite2D.material.set_shader_parameter("min_darkness", min_darkness)


func start_death():
	#Wait a while
	var dur = randf_range(LIFETIME_MIN, LIFETIME_MAX)
	var timer = Timer.new()
	timer.wait_time = dur
	add_child(timer)
	timer.start()
	await timer.timeout

	#Start fading out
	dur = randf_range(FADEOUT_MIN, FADEOUT_MAX)
	var tween = create_tween()
	modulate.a = 1.0
	tween.tween_property(self, "modulate:a", 0.0, dur)
	tween.tween_callback(self.queue_free)
