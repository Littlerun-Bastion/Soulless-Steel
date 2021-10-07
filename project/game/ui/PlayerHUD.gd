extends CanvasLayer

onready var LifeBar = $LifeBar
onready var ShieldBar = $ShieldBar
onready var EnergyBar = $EnergyBar
onready var Cursor = $MechaCursorCrosshair
onready var PlayerRadar = $PlayerRadar

var player
var mechas


func setup(player_ref, mechas_ref):
	player = player_ref
	mechas = mechas_ref
	player.connect("took_damage", self, "_on_player_took_damage")
	player.connect("shoot", self, "_on_player_shoot")
	setup_lifebar()
	setup_shieldbar()
	setup_energybar()
	setup_cursor()
	PlayerRadar.setup(mechas, player, 2300, 2)


func setup_lifebar():
	LifeBar.max_value = player.max_hp
	LifeBar.value = player.hp


func setup_shieldbar():
	ShieldBar.max_value = player.max_shield
	ShieldBar.value = player.shield


func setup_energybar():
	EnergyBar.max_value = player.max_energy
	EnergyBar.value = player.energy


func setup_cursor():
	Cursor.set_max_ammo("left", player.get_ammo("left_arm"))
	Cursor.set_max_ammo("right", player.get_ammo("right_arm"))


func update_lifebar(value):
	LifeBar.value = value


func update_shieldbar(value):
	ShieldBar.value = value


func update_energybar(value):
	EnergyBar.value = value


func update_cursor():
	Cursor.set_ammo("left", player.get_ammo("left_arm"))
	Cursor.set_ammo("right", player.get_ammo("right_arm"))


func _on_player_took_damage(_p):
	update_lifebar(player.hp)
	update_shieldbar(player.shield)


func _on_player_shoot():
	update_cursor()


func _on_LifeBar_value_changed(value):
	LifeBar.get_node("Label").text = str(value)


func _on_ShieldBar_value_changed(value):
	ShieldBar.get_node("Label").text = str(value)
