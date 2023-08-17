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
			if player.dash_cooldown[dir] > 0.0:
				Directions[dir].visible = true
			else:
				if Directions[dir].visible:
					Directions[dir].visible = false
				else:
					pass


func setup(player_ref):
	player = player_ref


func player_died():
	player = false
	hide()

