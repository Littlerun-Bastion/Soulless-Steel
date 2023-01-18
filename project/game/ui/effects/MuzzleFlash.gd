extends Particles2D

export var is_local := true
var attach_reference
var node_reference

func _physics_process(_dt):
	if attach_reference and node_reference and is_local:
		global_position = attach_reference.global_position
		global_rotation = node_reference.get_direction(0, 0).angle() + (PI/2)
	if not $Linger.is_emitting(): #Linger must always be the longest lasting particle effect
		queue_free()
		

func setup(weapon, size, speed, pos):
	if pos:
		attach_reference = pos
		global_position = attach_reference.global_position
	if weapon:
		node_reference = weapon
		global_rotation = node_reference.get_direction(0, 0).angle() + (PI/2)
	scale.x = size
	scale.y = size
	self.emitting = true
	for child in get_children():
		child.speed_scale *= speed
		child.emitting = true
