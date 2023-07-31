extends GPUParticles2D

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


func setup(projectile):
	home_projectile = projectile
	amount = projectile.smoke_density
	lifetime = projectile.smoke_lifetime
	tickdown = projectile.smoke_lifetime
	emitting = true


func die():
	queue_free()
