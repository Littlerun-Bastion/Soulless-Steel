extends Node2D

export (PackedScene) var casing
export var casings_count := 100

var index = 0

func _ready():
	for _x in range(casings_count):
		add_child(casing.instance())
	
func get_next_particle():
	return get_child(index)

func trigger(scale):
	var next_particle = get_next_particle()
	next_particle.scale *= scale
	next_particle.restart()
	index = (index + 1) % casings_count 
