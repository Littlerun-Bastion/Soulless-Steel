extends Control

@onready var Directions = {
	"fwd": $Fwd,
	"rwd": $Rwd,
	"left": $Left,
	"right": $Right,
}

var player

func _ready():
	for dir in Directions.values():
		dir.visible = false


func _process(_dt):
	if player and visible:
		position = player.get_global_transform_with_canvas().origin
		rotation = player.get_global_transform_with_canvas().get_rotation()
		for dir in Directions.keys():
			var node = Directions[dir]
			if player.dash_cooldown[dir] > 0.0:
				if not node.visible:
					node.visible = true
					start_dir_animation(dir)
				else:
					set_dir_values(dir)
			else:
				if node.visible:
					node.visible = false
				else:
					pass


func setup(player_ref):
	player = player_ref


func player_died():
	player = false
	hide()


func start_dir_animation(dir):
	Directions[dir].material.set_shader_parameter("show_percent", 0.0)


func set_dir_values(dir):
	var value = 1.0 - player.dash_cooldown[dir]/player.build.thruster.dash_cooldown
	Directions[dir].material.set_shader_parameter("show_percent", value)
