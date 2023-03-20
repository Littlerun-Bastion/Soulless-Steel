extends Node2D

@onready var collision = $StaticBody2D/CollisionPolygon2D


func get_collision_transform():
	return collision.get_global_transform()


func get_collision():
	return collision.get_polygon()


func create_collision_polygon(distance):
	var pool_vector = PackedVector2Array()
	var prop_transform = get_collision_transform()
	var pool = Geometry2D.offset_polygon(get_collision(), distance, Geometry2D.PolyJoinType.JOIN_MITER)
	for vertex in pool[0]:
		pool_vector.append(prop_transform * vertex)
	return pool_vector
