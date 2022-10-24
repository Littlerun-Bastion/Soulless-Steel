extends CanvasLayer

const WEAPON_SLOT = preload("res://game/ui/weapon_slot/WeaponSlot.tscn")
const LOCKING_SPRITES = {
	"locking": preload("res://assets/images/ui/player_ui/locking_on_highlight.png"),
	"locked": preload("res://assets/images/ui/player_ui/locked_on_highlight.png"),
}
const HOLE_FADE_DUR = .1
const BULLET_THRESHOLD = .75 #On what percent of max helth should player start getting holes
const BULLET_CHANCE = .8 #Chance that a bullet will appear on hud

onready var LifeBar = $LifeBar
onready var ShieldBar = $ShieldBar
onready var EnergyBar = $EnergyBar
onready var WeaponSlots = $WeaponSlots
onready var Cursor = $MechaCursorCrosshair
onready var PlayerRadar = $PlayerRadar
onready var Bulletholes = $Bulletholes
onready var LockingSprite = $LockingSprite


var player = false
var mechas


func _process(_delta):
	if player:
		update_shieldbar(player.shield)
		ShieldBar.get_node("Label").text = str(player.shield)
		
		var v_trans = get_viewport().canvas_transform
		if player.get_locked_to():
			LockingSprite.show()
			LockingSprite.texture = LOCKING_SPRITES.locked
			LockingSprite.global_position = v_trans * player.get_locked_to().global_position
		elif player.get_locking_to():
			LockingSprite.show()
			LockingSprite.texture = LOCKING_SPRITES.locking
			var mecha = player.get_locking_to().mecha
			var dist = mecha.global_position - player.global_position
			var pos = player.global_position + dist*player.get_locking_to().progress
			LockingSprite.global_position = v_trans * pos
		else:
			LockingSprite.hide()

func setup(player_ref, mechas_ref):
	player = player_ref
	mechas = mechas_ref
	player.connect("took_damage", self, "_on_player_took_damage")
	player.connect("shoot", self, "_on_player_shoot")
	player.connect("update_reload_mode", self, "_on_reload_mode_update")
	player.connect("update_lock_mode", self, "_on_lock_mode_update")
	player.connect("reloading", self, "_on_reloading")
	player.connect("finished_reloading", self, "update_cursor")
	Cursor.connect("enter_lock_mode", player, "_on_enter_lock_mode")
	setup_lifebar()
	setup_shieldbar()
	setup_energybar()
	setup_weapon_slots()
	setup_cursor()
	if player.head.has_radar:
		PlayerRadar.setup(mechas, player, 5000, 2)
		PlayerRadar.show()
	else:
		PlayerRadar.hide()
	$ExtractingLabel.visible = false
	update_lifebar(player.hp)
	update_shieldbar(player.shield)
	LifeBar.get_node("Label").text = str(player.hp)
	ShieldBar.get_node("Label").text = str(player.shield)
	for bullethole in Bulletholes.get_children():
		bullethole.modulate.a = 0


func set_pause(value):
	Cursor.visible = not value


func setup_lifebar():
	LifeBar.max_value = player.max_hp
	LifeBar.value = player.hp


func setup_shieldbar():
	ShieldBar.max_value = player.max_shield
	ShieldBar.value = player.shield


func setup_energybar():
	EnergyBar.max_value = player.max_energy
	EnergyBar.value = player.energy


func setup_weapon_slots():
	for slot in WeaponSlots.get_children():
		slot.queue_free()
	for weapon in ["arm_weapon_left", "arm_weapon_right", "shoulder_weapon_left", "shoulder_weapon_right"]:
		if player.get(weapon):
			var slot = WEAPON_SLOT.instance()
			WeaponSlots.add_child(slot)
			slot.setup(player.get(weapon), weapon)


func setup_cursor():
	Cursor.set_max_ammo("left", player.get_clip_ammo("arm_weapon_left"))
	Cursor.set_max_ammo("right", player.get_clip_ammo("arm_weapon_right"))


func update_lifebar(value):
	LifeBar.value = value


func update_shieldbar(value):
	ShieldBar.value = value


func update_energybar(value):
	EnergyBar.value = value


func update_cursor():
	Cursor.set_ammo("left", player.get_clip_ammo("arm_weapon_left"))
	Cursor.set_ammo("right", player.get_clip_ammo("arm_weapon_right"))


func update_arsenal():
	for weapon in $WeaponSlots.get_children():
		var total_ammo = player.get_total_ammo(weapon.type)
		if total_ammo:
			weapon.set_ammo(total_ammo)


func player_died():
	player = false
	PlayerRadar.player_died()
	Cursor.hide()


func _on_player_took_damage(_p):
	update_lifebar(player.hp)
	update_shieldbar(player.shield)
	LifeBar.get_node("Label").text = str(player.hp)
	ShieldBar.get_node("Label").text = str(player.shield)
	#Bullet holes logic
	if player.shield <= 0 and player.hp < player.max_hp*BULLET_THRESHOLD and\
	   randf() <= BULLET_CHANCE:
		var visible_holes = []
		for hole in Bulletholes.get_children():
			if hole.modulate.a == 0.0:
				visible_holes.append(hole)
		if not visible_holes.empty():
			var hole = visible_holes[randi() % visible_holes.size()]
			$Tween.interpolate_property(hole, "modulate:a", 0.0, 1.0, HOLE_FADE_DUR)
			$Tween.start()


func _on_player_shoot():
	update_cursor()
	update_arsenal()


func _on_reload_mode_update(active):
	Cursor.set_reload_mode(active)


func _on_lock_mode_update(active):
	Cursor.set_lock_mode(active)


func _on_reloading(reload_time, side):
	Cursor.reloading(reload_time, side)


func _on_LifeBar_value_changed(value):
	LifeBar.get_node("Label").text = str(value)


func _on_ShieldBar_value_changed(value):
	ShieldBar.get_node("Label").text = str(value)

