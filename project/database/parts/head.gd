extends Node2D

export var part_name : String
export var manufacturer_name : String
export var tagline : String
export var description : String
export var image : Texture
export var rotation_acc := 8
export var rotation_range := 45.0
export var health := 5


func get_image():
	return $Main.texture


func get_sub():
	return $Sub.texture


func get_glow():
	return $Glow.texture
