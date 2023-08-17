extends Control

@onready var Directions = {
	"fwd": $Fwd, "rwd": $Rwd,
	"left": $Left, "right": $Right,
}

var player
var dir_end_animation = {
	"fwd": false, "rwd": false,
	"left": false, "right": false
}

func _ready():
	for dir in Directions.values():
		dir.visible = false


func _process(_dt):
	if player and visible:
		position = player.get_global_transform_with_canvas().origin
		rotation = player.get_global_transform_with_canvas().get_rotation()
		for dir in Directions.keys():
			var node = Directions[dir]
			if player.dash_cooldown[dir] > 0.0 and not dir_end_animation[dir]:
				if not node.visible:
					node.visible = true
					start_dir_animation(dir)
				else:
					set_dir_values(dir)
			else:
				if node.visible and not dir_end_animation[dir]:
					end_dir_animation(dir)


func setup(player_ref):
	player = player_ref


func player_died():
	player = false
	hide()


func start_dir_animation(dir):
	var node = Directions[dir]
	var border = node.get_node("Border")
	node.material.set_shader_parameter("show_percent", 0.0)
	border.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(border, "modulate:a", 1.0, .2)


func end_dir_animation(dir):
	dir_end_animation[dir] = true
	var node = Directions[dir]
	var border = node.get_node("Border")
	
	await get_tree().create_timer(.2).timeout
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(border, "modulate:a", 0.0, .35)
	tween.tween_property(node, "modulate:a", 0.0, .35)
	
	await tween.finished
	
	node.visible = false
	node.modulate.a = 1.0
	dir_end_animation[dir] = false


func set_dir_values(dir):
	var value = 1.0 - player.dash_cooldown[dir]/player.build.thruster.dash_cooldown
	Directions[dir].material.set_shader_parameter("show_percent", value)
