extends Node2D

onready var collision = $StaticBody2D/CollisionPolygon2D


func get_collision_transform():
	return collision.get_global_transform()


func get_collision():
	return collision.get_polygon()


func add_collision_to_navigation(arena_poly, scaling):
	var pool_vector = PoolVector2Array()
	var prop_transform = get_collision_transform()
	for vertex in get_collision():
		vertex += collision.position
		vertex *= scaling
		vertex -= collision.position
		pool_vector.append(prop_transform.xform(vertex))
	arena_poly.add_outline(pool_vector)
