extends RigidBody2D

var speed = 0
var dir = Vector2()
var damage = 0
var decal_type = "bullet_hole"
var original_mecha


func setup(mecha, args):
	var data = args.weapon_data
	$Sprite.texture = data.image
	$CollisionShape2D.shape.extents = data.collision_extents
	original_mecha = mecha
	decal_type = data.decal_type
	speed = data.speed
	damage = data.damage * args.damage_mod
	apply_scaling(data.scale)
	dir = args.dir.normalized()
	position = args.pos
	rotation_degrees = rad2deg(dir.angle()) + 90
	apply_impulse(Vector2(), dir*speed)


#Workaround since RigidBody can't have its scale changed
func apply_scaling(sc):
	for child in get_children():
		child.scale = sc


func _on_RegularProjectile_body_shape_entered(_body_id, body, body_shape, _local_shape):
	if body.is_in_group("mecha") and body != original_mecha:
		body.add_decal(body_shape, global_transform, decal_type, $Sprite.scale*$Sprite.texture.get_size())
		body.take_damage(damage)
		body.knockback(global_position, 100*damage/float(body.get_max_hp()))
	
	queue_free()
