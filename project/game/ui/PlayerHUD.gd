extends CanvasLayer

onready var LifeBar = $LifeBar

var player


func setup(player_ref):
	player = player_ref
	player.connect("took_damage", self, "_on_player_took_damage")
	setup_lifebar()


func setup_lifebar():
	LifeBar.max_value = player.max_hp
	LifeBar.value = player.hp


func update_lifebar(value):
	LifeBar.value = value


func _on_player_took_damage(_p):
	update_lifebar(player.hp)


func _on_LifeBar_value_changed(value):
	LifeBar.get_node("Label").text = str(value)
