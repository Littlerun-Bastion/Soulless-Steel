extends Node2D

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export var heatmap : Resource
export var rotation_acc := 8
export var rotation_range := 45.0
export var accuracy_modifier := -1.0 
export var visual_range := 450 
export var health := 1500
export var weight := 1.0 

var part_id

func get_image():
	return $Main.texture


func get_sub():
	return $Sub.texture


func get_glow():
	return $Glow.texture
