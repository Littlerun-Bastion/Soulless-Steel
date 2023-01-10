extends Particles2D

var home_projectile
var tickdown := 5.0

func _process(dt):
	if is_instance_valid(home_projectile):
		global_position = home_projectile.global_position
	else:
		emitting = false
		tickdown = max(tickdown - dt, 0)
		if tickdown <= 0:
			die()


func setup(projectile, mat, args):
	home_projectile = projectile
	self.process_material = mat
	self.amount = args.smoke_density
	self.lifetime = args.smoke_lifetime
	tickdown = args.smoke_lifetime
	self.process_material = mat
	self.emitting = true
	self.texture = args.smoke_texture


func die():
	queue_free()
