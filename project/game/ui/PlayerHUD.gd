extends CanvasLayer

onready var LifeBar = $LifeBar
onready var ShieldBar = $ShieldBar
onready var EnergyBar = $EnergyBar

var player


func setup(player_ref):
	player = player_ref
	player.connect("took_damage", self, "_on_player_took_damage")
	setup_lifebar()
	setup_shieldbar()
	setup_energybar()


func setup_lifebar():
	LifeBar.max_value = player.max_hp
	LifeBar.value = player.hp


func setup_shieldbar():
	ShieldBar.max_value = player.max_shield
	ShieldBar.value = player.shield


func setup_energybar():
	EnergyBar.max_value = player.max_energy
	EnergyBar.value = player.energy


func update_lifebar(value):
	LifeBar.value = value


func update_shieldbar(value):
	ShieldBar.value = value


func update_energybar(value):
	EnergyBar.value = value


func _on_player_took_damage(_p):
	update_lifebar(player.hp)
	update_shieldbar(player.shield)


func _on_LifeBar_value_changed(value):
	LifeBar.get_node("Label").text = str(value)


func _on_ShieldBar_value_changed(value):
	ShieldBar.get_node("Label").text = str(value)
