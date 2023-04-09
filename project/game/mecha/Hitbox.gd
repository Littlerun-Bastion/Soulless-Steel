extends Area2D

@onready var Collision = $CollisionShape2D

var data

func setup(hit_data):
	data = hit_data.duplicate(true)
	position = data.pos
	$Timer.wait_time = data.dur
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate()
	$CollisionShape2D.shape.radius = data.radius


func _on_Timer_timeout():
	queue_free()


func _on_Hitbox_body_shape_entered(_body_rid, body, body_shape_id, _local_shape_index):
	if body.is_in_group("mecha"):
		if body.is_shape_id_chassis(body_shape_id):
			return
		
		if body != data.owner and body.check_valid_hitbox_and_update(data):
			var shape = body.get_shape_from_id(body_shape_id)
			var points = ProjectileManager.get_intersection_circle_polygon(Collision.position, Collision.shape.radius, Collision.global_transform,\
																			shape.polygon, shape.global_transform)
			
			var collision_point
			if points.size() > 0:
				collision_point = points[0]
			else:
				collision_point = global_position
			
			data.decal_size = Vector2(40,40)
			data.decal_type = "bullet_hole"
			data.body_shape_id= body_shape_id
			data.collision_point = collision_point
			data.hitbox_position = global_position
			body.add_lingering_hitbox(data)


