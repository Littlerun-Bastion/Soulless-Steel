extends Particles2D

var home_projectile
var tickdown := 5.0

func setup(projectile, mat, args):
	home_projectile = projectile
	self.process_material = mat
	self.amount = args.smoke_density
	self.lifetime = args.smoke_lifetime
	tickdown = args.smoke_lifetime
	self.process_material = mat
	self.emitting = true
	self.texture = args.smoke_texture

func _process(dt):
	if is_instance_valid(home_projectile):
		self.global_position = home_projectile.global_position
	else:
		self.emitting = false
		if tickdown > 0:
			tickdown -= dt
		else:
			queue_free()
