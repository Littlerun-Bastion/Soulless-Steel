extends Node

enum TYPE {INSTANT, REGULAR}

const REGULAR = preload("res://game/weapons/RegularProjectile.tscn")

func create(mecha, args):
	var projectile_data = args.weapon_data.instance()
	var data = {
		"create_node": false,
		"node": null,
	}
	
	if projectile_data.type == TYPE.INSTANT:
		pass
	
	elif projectile_data.type == TYPE.REGULAR:
		var projectile = REGULAR.instance()
		projectile.setup(mecha, args)
		data.create_node = true
		data.node = projectile
	
	return data

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
		p11 = trans1.xform(poly1[i])
		p12 = trans1.xform(poly1[i + 1]) if i + 1 < poly1.size() else trans1.xform(poly1[0])
		for j in range(0, poly2.size()):
			p21 = trans2.xform(poly2[j])
			p22 = trans2.xform(poly2[j + 1]) if j + 1 < poly2.size() else trans2.xform(poly2[0])
			# use Geometry function to evaluate intersections
			var intersect = Geometry.segment_intersects_segment_2d(p11, p12, p21, p22)
			if intersect != null:
				result.append(intersect)
	return result
