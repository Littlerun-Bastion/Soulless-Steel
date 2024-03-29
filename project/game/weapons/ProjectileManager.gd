extends Node

enum TYPE {INSTANT, REGULAR, COMPLEX}

const REGULAR = preload("res://game/weapons/RegularProjectile.tscn")
const COMPLEX = preload("res://game/weapons/ComplexProjectile.tscn")
const INSTANT = preload("res://game/weapons/InstantProjectile.tscn")
const NUM_SIDES = 30

func create(mecha, args, weapon):
	var wr = weakref(mecha)
	if not wr.get_ref():
		return false
	var data = {
		"create_node": false,
		"node": null,
	}
	var projectile = args.projectile.instantiate()
	projectile.setup(mecha, args, weapon)
	data.create_node = true
	data.node = projectile
	
	return data


func create_muzzle_flash(weapon, data, pos, dir):
	var flash = data.flash_effect.instantiate()
	flash.setup(weapon, data.flash_size, data.flash_speed, pos, dir)
	return flash


func create_trail(projectile, data):
		var trail = data.instantiate()
		trail.setup(projectile)
		return trail


func create_explosion(pos, impact_effect):
	var explosion = impact_effect.instantiate()
	explosion.position = pos.position
	return explosion

#Return all positions where a polygon intersects with a circle
func get_intersection_circle_polygon(circ_center, circ_radius, circ_trans, poly, poly_trans):
	var result = []
	for i in range(0, poly.size()):
		var p1 = poly_trans * poly[i]
		var p2 = poly_trans * poly[i + 1] if i + 1 < poly.size() else poly_trans.xform(poly[0])
		var inter = Geometry2D.segment_intersects_circle(p1, p2, circ_trans * circ_center, circ_radius)
		if inter != -1:
			result.append(p1 + inter*(p2-p1))
	return result

#Given two polygons and their transforms, return an array with all points where they collide
func get_intersection_points(poly1, trans1, poly2, trans2):
	var result = []

	var p11 = Vector2() 
	var p12 = Vector2()
	var p21 = Vector2()
	var p22 = Vector2()

	# nested loops checking intersections 
	# between all segments of both polygons
	for i in range(0, poly1.size()):
		p11 = trans1 * poly1[i]
		p12 = trans1 * poly1[i + 1] if i + 1 < poly1.size() else trans1.basis_xform(poly1[0])
		for j in range(0, poly2.size()):
			p21 = trans2 * poly2[j]
			p22 = trans2 * poly2[j + 1] if j + 1 < poly2.size() else trans2.basis_xform(poly2[0])
			# use Geometry function to evaluate intersections
			var intersect = Geometry2D.segment_intersects_segment(p11, p12, p21, p22)
			if intersect != null:
				result.append(intersect)
	return result


func generate_circle_polygon(radius: float, position: Vector2) -> PackedVector2Array:
	var angle_delta: float = (PI * 2) / NUM_SIDES
	var vector: Vector2 = Vector2(radius, 0)
	var polygon := PackedVector2Array()
	for _i in NUM_SIDES:
		polygon.append(vector + position)
		vector = vector.rotated(angle_delta)

	return polygon
