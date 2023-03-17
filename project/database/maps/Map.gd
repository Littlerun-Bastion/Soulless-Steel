extends Node2D

@export var is_tutorial := false


func get_bg():
	return $BG


func get_bushes():
	return $Bushes.get_children()


func get_props():
	return $Props.get_children()


func get_walls():
	return $Walls.get_children()


func get_start_positions():
	return $StartPositions.get_children()


func get_exits():
	return $Exits.get_children()


func get_trees():
	return $Trees.get_children()


func get_buildings():
	return $Buildings.get_children()


func get_texts():
	return $Texts.get_children()


func get_navigation_polygon():
	return $NavigationRegion2D.navpoly
