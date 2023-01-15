extends Node2D

export (PackedScene) var casing
export var casings_count := 100

var index = 0

func _ready():
	for x in range(casings_count):
		add_child(casing.instance())
	
func get_next_particle():
	return get_child(index)

func trigger():
	get_next_particle().restart()
	index = (index + 1) % casings_count 
