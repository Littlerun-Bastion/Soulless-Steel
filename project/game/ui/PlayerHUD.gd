extends CanvasLayer

onready var LifeBar = $LifeBar
onready var ShieldBar = $ShieldBar

var player


func setup(player_ref):
	player = player_ref
	player.connect("took_damage", self, "_on_player_took_damage")
	setup_lifebar()
	setup_shieldbar()


func setup_lifebar():
	LifeBar.max_value = player.max_hp
	LifeBar.value = player.hp


func setup_shieldbar():
	ShieldBar.max_value = player.max_shield
	ShieldBar.value = player.shield


func update_lifebar(value):
	LifeBar.value = value


func update_shieldbar(value):
	ShieldBar.value = value


func _on_player_took_damage(_p):
	update_lifebar(player.hp)
	update_shieldbar(player.shield)


func _on_LifeBar_value_changed(value):
	LifeBar.get_node("Label").text = str(value)


func _on_ShieldBar_value_changed(value):
	ShieldBar.get_node("Label").text = str(value)
