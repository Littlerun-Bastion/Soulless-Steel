extends CanvasLayer

const WEAPON_SLOT = preload("res://game/ui/weapon_slot/WeaponSlot.tscn")
const LOCKING_SPRITES = {
	"locking": preload("res://assets/images/ui/player_ui/locking_on_highlight.png"),
	"locked": preload("res://assets/images/ui/player_ui/locked_on_highlight.png"),
	"locking_ecm": preload("res://assets/images/ui/player_ui/locking_on_ecm_highlight.png")
}
const HOLE_FADE_DUR = .1
const BULLET_THRESHOLD = .75 #On what percent of max helth should player start getting holes
const BULLET_CHANCE = .8 #Chance that a bullet will appear on hud
const LOCKING_INIT_SCALE = .15
const LOCKING_FINAL_SCALE = .25
const LOCKING_INIT_BLINK = .7
const LOCKING_FINAL_BLINK = 15.0
const BLINK_PITCH_TARGET_MOD = .40
const STATUS_BLINK_SPEED = 0.66
const BUILDING_SPEED = 1.5

onready var LifeBar = $ViewportContainer/Viewport/LifeBar
onready var ShieldBar = $ViewportContainer/Viewport/ShieldBar
onready var HeatBar = $ViewportContainer/Viewport/HeatBar
onready var WeaponSlots = $ViewportContainer/Viewport/WeaponSlots
onready var Cursor = $ViewportContainer/Viewport/MechaCursorCrosshair
onready var PlayerRadar = $ViewportContainer/Viewport/PlayerRadar
onready var Bulletholes = $ViewportContainer/Viewport/Bulletholes
onready var LockingSprite = $ViewportContainer/Viewport/LockingSprite
onready var LockingAnim = $ViewportContainer/Viewport/LockingSprite/AnimationPlayer
onready var ConstantBlinkingSFX = $ViewportContainer/Viewport/ConstantBlinkingSFX
onready var ExtractingLabel = $ViewportContainer/Viewport/ExtractingLabel
onready var Tw = $ViewportContainer/Viewport/Tween
onready var StatusLabels = {
	"freezing": $ViewportContainer/Viewport/StatusContainer/FreezingLabel,
	"corrosion": $ViewportContainer/Viewport/StatusContainer/CorrosionLabel,
	"electrified": $ViewportContainer/Viewport/StatusContainer/ElectrifiedLabel,
	"fire": $ViewportContainer/Viewport/StatusContainer/FireLabel,
	"overheating":$ViewportContainer/Viewport/StatusContainer/OverheatingLabel,
}
onready var StatusContainer = $ViewportContainer/Viewport/StatusContainer
onready var StatusChirpSFX = $ViewportContainer/Viewport/StatusChirpSFX
onready var TemperatureLabel = $ViewportContainer/Viewport/HeatBar/TemperatureLabel
onready var TemperatureErrorLabel = $ViewportContainer/Viewport/HeatBar/TemperatureErrorLabel
onready var ECMLabel = $ViewportContainer/Viewport/ECMLabel
onready var ECMFreqLabel = $ViewportContainer/Viewport/ECMLabel/ECMFreqLabel
onready var OverweightLabel = $ViewportContainer/Viewport/StatusContainer/OverweightLabel
onready var BuildingEffect = $ViewportContainer/Viewport/BuildingEffect


var player = false
var mechas
var blink_timer = 0.66
var building_effect_active = false


func _ready():
	BuildingEffect.modulate.a = 0


func _process(dt):
	if player:
		update_cursor()
		update_shieldbar(player.shield)
		update_lifebar(player.hp)
		update_heatbar(player.mecha_heat_visible)
		if player.mecha_heat_visible > player.max_heat:
			TemperatureLabel.visible = false
			TemperatureErrorLabel.visible = true
		else:
			TemperatureLabel.text = str(round(player.mecha_heat_visible) * 8)
			TemperatureLabel.visible = true
			TemperatureErrorLabel.visible = false
		ShieldBar.get_node("Label").text = str(player.shield)
		
		for status in player.status_time:
			if StatusLabels.has(status):
				StatusLabels[status].visible = player.has_status(status)

		if player.has_any_status():
			if not StatusChirpSFX.playing:
				StatusChirpSFX.play()
		else:
			StatusChirpSFX.playing = false
		
		if player.is_overweight:
			OverweightLabel.visible = true
		else:
			OverweightLabel.visible = false
		
		if blink_timer <= 0.0:
			if StatusContainer.visible == true:
				StatusContainer.visible = false
			else:
				StatusContainer.visible = true
			blink_timer = STATUS_BLINK_SPEED
		else:
			blink_timer -= dt
		
		var v_trans = get_viewport().canvas_transform
		if player.get_locked_to():
			LockingSprite.texture = LOCKING_SPRITES.locked
			LockingSprite.global_position = v_trans * player.get_locked_to().global_position
			LockingSprite.scale = Vector2(LOCKING_FINAL_SCALE, LOCKING_FINAL_SCALE)
			LockingAnim.play("static")
			if not ConstantBlinkingSFX.playing:
				ConstantBlinkingSFX.play()
		elif player.get_locking_to():
			ConstantBlinkingSFX.stop()
			LockingSprite.texture = LOCKING_SPRITES.locking
			var prog = player.get_locking_to().progress
			var mecha = player.get_locking_to().mecha
			var dist = mecha.global_position - player.global_position
			var pos = player.global_position + dist*prog
			var sc = LOCKING_INIT_SCALE -  LOCKING_INIT_SCALE*prog + LOCKING_FINAL_SCALE*prog
			var blink_speed = LOCKING_INIT_BLINK -  LOCKING_INIT_BLINK*prog + LOCKING_FINAL_BLINK*prog
			if player.ecm_strength_difference > 0.0:
				LockingSprite.texture = LOCKING_SPRITES.locking_ecm
				ECMLabel.visible = true
				ECMLabel.text = str("WRN ECM -" + str(player.ecm_strength_difference * 100) + "%")
				var ecm_progress = (player.ecm_attempt_cooldown / player.locking_to.mecha.ecm_frequency) * 100
				ECMFreqLabel.value = ecm_progress
			else:
				ECMLabel.visible = false
			LockingSprite.scale = Vector2(sc, sc)
			LockingSprite.global_position = v_trans * pos
			LockingAnim.play("blinking")
			LockingAnim.playback_speed = blink_speed
		else:
			ECMLabel.visible = false
			ConstantBlinkingSFX.stop()
			LockingAnim.stop()
			LockingSprite.hide()
		
		if building_effect_active:
			BuildingEffect.modulate.a = min(1.0, BuildingEffect.modulate.a + BUILDING_SPEED*dt)
		else:
			BuildingEffect.modulate.a = max(0.0, BuildingEffect.modulate.a - BUILDING_SPEED*dt)

func setup(player_ref, mechas_ref):
	player = player_ref
	mechas = mechas_ref
	player.connect("took_damage", self, "_on_player_took_damage")
	player.connect("shoot", self, "_on_player_shoot")
	player.connect("update_reload_mode", self, "_on_reload_mode_update")
	player.connect("update_lock_mode", self, "_on_lock_mode_update")
	player.connect("reloading", self, "_on_reloading")
	player.connect("finished_reloading", self, "update_cursor")
	player.connect("update_building_status", self, "_on_player_update_building_status")
	Cursor.connect("enter_lock_mode", player, "_on_enter_lock_mode")
	setup_lifebar()
	setup_shieldbar()
	setup_heatbar()
	setup_weapon_slots()
	setup_cursor()
	if player.chipset.has_radar:
		PlayerRadar.setup(mechas, player, player.chipset.radar_range, player.chipset.radar_refresh_rate)
		PlayerRadar.show()
	else:
		PlayerRadar.hide()
	ExtractingLabel.visible = false
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


func setup_heatbar():
	HeatBar.max_value = player.max_heat
	HeatBar.value = player.mecha_heat_visible


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
	Cursor.set_lock_on_reticle_size(player.chipset.lock_on_reticle_size)


func update_lifebar(value):
	LifeBar.value = value


func update_shieldbar(value):
	ShieldBar.value = value


func update_heatbar(value):
	HeatBar.value = value


func update_cursor():
	Cursor.set_ammo("left", player.get_clip_ammo("arm_weapon_left"))
	Cursor.set_ammo("right", player.get_clip_ammo("arm_weapon_right"))


func update_arsenal():
	for weapon in WeaponSlots.get_children():
		var total_ammo = player.get_total_ammo(weapon.type)
		if total_ammo:
			weapon.set_ammo(total_ammo)


func player_died():
	player = false
	PlayerRadar.player_died()
	Cursor.hide()


func play_blink_sound():
	var prog = LockingAnim.playback_speed/float(LOCKING_FINAL_BLINK - LOCKING_INIT_BLINK)
	var pitch = 1.0 + BLINK_PITCH_TARGET_MOD*prog
	AudioManager.play_sfx("blinking", false, pitch)


func _on_player_took_damage(_p, is_status):
	update_lifebar(player.hp)
	update_shieldbar(player.shield)
	LifeBar.get_node("Label").text = str(player.hp)
	ShieldBar.get_node("Label").text = str(player.shield)
	#Bullet holes logic
	if player.shield <= 0 and player.hp < player.max_hp*BULLET_THRESHOLD and\
	   randf() <= BULLET_CHANCE and not is_status:
		var visible_holes = []
		for hole in Bulletholes.get_children():
			if hole.modulate.a == 0.0:
				visible_holes.append(hole)
		if not visible_holes.empty():
			var hole = visible_holes[randi() % visible_holes.size()]
			Tw.interpolate_property(hole, "modulate:a", 0.0, 1.0, HOLE_FADE_DUR)
			Tw.start()


func _on_player_update_building_status(value):
	building_effect_active = value


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

