extends Node2D


func _ready():
	var NavInstance = $Navigation2D/NavigationPolygonInstance
	var arena_poly = NavInstance.navpoly
	
	#Add props collision to navigation
	var distance = 100
	var prop_polygons = []
	for prop in $Props.get_children():
		prop_polygons.append(prop.create_collision_polygon(distance))
		
	
	merge_polygons(prop_polygons)

	for polygon in prop_polygons:
		arena_poly.add_outline(polygon)

	arena_poly.make_polygons_from_outlines()
	
	NavInstance.set_navigation_polygon(arena_poly)
	NavInstance.enabled = false
	NavInstance.enabled = true


func merge_polygons(polygons):
	while(true):
		var merged_something = false
		for i in polygons.size():
			var polygon = polygons[i]
			for j in range(i + 1, polygons.size()):
				var other_polygon = polygons[j]
				var merged_polygon = Geometry.merge_polygons_2d(polygon, other_polygon)
				if merged_polygon.size() == 1 or Geometry.is_polygon_clockwise(merged_polygon[1]):
					polygons.append(merged_polygon[0])
					merged_something = [i, j]
					break
			if merged_something:
				break

		if not merged_something:
			break
		else:
			polygons.remove(merged_something[1])
			polygons.remove(merged_something[0])
