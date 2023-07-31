extends Label

signal finished

@export var lifespan := 1.0

var lifetime = 0.0
var is_active = false
var sound_tick_rate = 0.1
var sound_tick = 0.0
var keystrike = false

func _process(dt):
	if is_active:
		lifetime += dt
		self.visible_ratio = min(self.visible_ratio + dt * (1.0/lifespan*1.5), 1.0)
		if sound_tick >= sound_tick_rate and lifetime <= lifespan / 1.5:
			AudioManager.play_sfx("rapid_beep")
			sound_tick = 0.0
			keystrike = false
		elif lifetime > lifespan / 1.5 and keystrike == false:
			AudioManager.play_sfx("keystrike")
			keystrike = true
		else:
			sound_tick += dt
	if lifetime >= lifespan:
		reset()

func reset():
	is_active = false
	lifetime = 0.0
	self.visible = false
	self.visible_ratio = 0.0
	self.text = ""
	emit_signal("finished")

func display(command):
	reset()
	self.visible = true
	self.text = command
	is_active = true
	
