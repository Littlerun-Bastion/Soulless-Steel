extends RigidBody2D

const LIFETIME_MIN = 5
const LIFETIME_MAX = 5.5
const FADEOUT_MIN = .4
const FADEOUT_MAX = .8

func _ready():
	inertia = 1.0 #Need to set some value to allow rotation
	start_death()


func setup(image):
	$Sprite.texture = image


func start_death():
	#Wait a while
	var dur = rand_range(LIFETIME_MIN, LIFETIME_MAX)
	yield(get_tree().create_timer(dur), "timeout")
	
	#Start fading out
	dur = rand_range(FADEOUT_MIN, FADEOUT_MAX)
	$Tween.interpolate_property(self, "modulate:a", 1.0, 0.0, dur)
	$Tween.start()
	yield($Tween, "tween_completed")
	
	queue_free()
