extends Label

const COMMAND_LINE_LIFESPAN = 1
var lifetime = 0.0
var is_active = false

func _process(dt):
	if is_active:
		lifetime += dt
		self.visible_ratio = min(self.visible_ratio + dt * (1/COMMAND_LINE_LIFESPAN*1.5), 1.0)
	if lifetime >= COMMAND_LINE_LIFESPAN:
		reset()

func reset():
	is_active = false
	lifetime = 0.0
	self.visible = false
	self.visible_ratio = 0.0
	self.text = ""

func display(command):
	reset()
	self.visible = true
	self.text = command
	is_active = true
	
