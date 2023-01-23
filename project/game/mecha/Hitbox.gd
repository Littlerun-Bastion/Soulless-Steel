extends Area2D

onready var Collision = $CollisionShape2D

var damage
var decal_type = "bullet_hole"

func setup(pos : Vector2, radius : float, dmg : float, dur : float):
	position = pos
	damage = dmg
	$Timer.wait_time = dur
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate()
	$CollisionShape2D.shape.radius = radius


func _on_Timer_timeout():
	queue_free()


func _on_Hitbox_body_shape_entered(_body_rid, body, body_shape_id, _local_shape_index):
	if body.is_in_group("mecha"):
		if body.is_shape_id_chassis(body_shape_id):
			return
		
#		if original_mecha_info and original_mecha_info.has("body") and body != original_mecha_info.body:
		var shape = body.get_shape_from_id(body_shape_id)
		var points = []#ProjectileManager.get_intersection_points(Collision.shape, Collision.global_transform,\
												  #shape.polygon, shape.global_transform)
		
		var collision_point
		if points.size() > 0:
			collision_point = points[0]
		else:
			collision_point = global_position
		
		var size = Vector2(40,40)
		body.add_decal(body_shape_id, collision_point, decal_type, size)
		
		body.take_damage(damage, 1.0, 1.0, 10, 0, false, false, false)
		if true:#impact_force > 0.0:
			body.knockback(20, collision_point - global_position, true)


