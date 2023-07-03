extends Label

signal finished

@export var lifespan := 1.0

var lifetime = 0.0
var is_active = false

func _process(dt):
	if is_active:
		lifetime += dt
		self.visible_ratio = min(self.visible_ratio + dt * (1.0/lifespan*1.5), 1.0)
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
	
