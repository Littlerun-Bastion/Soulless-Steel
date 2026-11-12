class_name StageSpawn
extends StageStep

@export var scene: PackedScene
@export var alias := ""


func _start() -> void:
	if scene != null:
		var thing := scene.instantiate()
		var host := director.get_scene_root()
		if host == null:
			host = director.get_parent()
		host.add_child(thing)
		if thing is Node2D:
			thing.global_position = global_position
		if alias != "":
			director.set_actor(alias, thing)
	_finish()
