extends Control

@export var stat_title = "Heatmap"
var stat_name = "heatmap"

func _ready():
	$TextureRect/Title.text = stat_title

func update_stat(_current_part, new_part):
	$TextureRect.texture = new_part.get(stat_name)
