extends Node2D

onready var collision = $StaticBody2D/CollisionPolygon2D


func get_collision_transform():
	return collision.get_global_transform()


func get_collision():
	return collision.get_polygon()


func add_collision_to_navigation(arena_poly, distance):
	var pool_vector = PoolVector2Array()
	var prop_transform = get_collision_transform()
	var pool = Geometry.offset_polygon_2d(get_collision(), distance, 2)
	for vertex in pool[0]:
		pool_vector.append(prop_transform.xform(vertex))
	arena_poly.add_outline(pool_vector)
