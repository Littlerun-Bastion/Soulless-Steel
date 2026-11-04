extends CanvasLayer

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

@onready var Cursor = $SubViewportContainer/SubViewport/MechaCursorCrosshair
@onready var PlayerRadar = $SubViewportContainer/SubViewport/PlayerRadar
@onready var DashCooldown = $SubViewportContainer/SubViewport/DashCooldown
@onready var Bulletholes = $SubViewportContainer/SubViewport/Bulletholes
@onready var LockingSprite = $SubViewportContainer/SubViewport/LockingSprite
@onready var LockingAnim = $SubViewportContainer/SubViewport/LockingSprite/AnimationPlayer
@onready var ConstantBlinkingSFX = $SubViewportContainer/SubViewport/ConstantBlinkingSFX
@onready var StatusChirpSFX = $SubViewportContainer/SubViewport/StatusChirpSFX
# Bottom left: frame readout + gauges (armour, shield, heat, battery, dash,
# load). Bottom right: weapon list. Both are built in code (game/ui/hud/).
@onready var hud_status: HudStatus = $SubViewportContainer/SubViewport/HudStatus
@onready var hud_weapons: HudWeapons = $SubViewportContainer/SubViewport/HudWeapons
# Top: the strip text (site, grid square, clock), one alert at a time in the
# middle, and the [E] prompt over the nearest container (all game/ui/hud/).
@onready var top_strip: HudTopStrip = $TopStrip
@onready var hud_alerts: HudAlerts = $SubViewportContainer/SubViewport/HudAlerts
@onready var interact_prompt: InteractPrompt = $SubViewportContainer/SubViewport/InteractPrompt
@onready var exit_marker: ExitMarker = $SubViewportContainer/SubViewport/ExitMarker
# Ping contacts (wards, drones) as markers through walls (game/ui/hud/).
@onready var hud_contacts: HudContacts = $SubViewportContainer/SubViewport/HudContacts
# Mechas the Seeker covers, outlined (game/ui/hud/).
@onready var hud_vision_outlines: HudVisionOutlines = $SubViewportContainer/SubViewport/HudVisionOutlines
# Local: name tags and speech boxes over mechas, the feed (top left) and the
# quick chat menu under it (game/ui/hud/).
@onready var hud_world_labels: HudWorldLabels = $SubViewportContainer/SubViewport/HudWorldLabels
@onready var hud_local_feed: HudLocalFeed = $SubViewportContainer/SubViewport/HudLocalFeed
@onready var hud_quick_chat: HudQuickChat = $SubViewportContainer/SubViewport/HudQuickChat
# The sensor sweep's aim and readout, under the alerts (game/ui/hud/).
@onready var hud_sweep: HudSweep = $SubViewportContainer/SubViewport/HudSweep


var player = false
var mechas

var cockpit_warning_active = false
var cockpit_warning_timer = 0.0
var flagged_warning_active = false


func toggle_inventory():
	pass




# The squad orders menu (made in setup, beside the quick chat menu).
var hud_squad_orders: HudSquadOrders = null


# The quick chat and squad orders menus take their keys before the game and
# the pause menu do.
func _input(event: InputEvent) -> void:
	if player and (hud_quick_chat.handle_input(event) or (hud_squad_orders != null and hud_squad_orders.handle_input(event))):
		get_viewport().set_input_as_handled()


func _process(dt):
	var profile_start := FrameProfiler.start()
	_process_step(dt)
	FrameProfiler.add("hud", profile_start)


func _process_step(dt):
	if player:
		update_cursor()
		
		# The status names show as an alert (HudAlerts); the chirp stays here.
		if player.has_any_status():
			if not StatusChirpSFX.playing:
				StatusChirpSFX.play()
		else:
			StatusChirpSFX.playing = false
		
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
			LockingSprite.scale = Vector2(sc, sc)
			LockingSprite.global_position = v_trans * pos
			LockingAnim.play("blinking")
			LockingAnim.speed_scale = blink_speed
		else:
			ConstantBlinkingSFX.stop()
			LockingAnim.stop()
			LockingSprite.hide()

func setup(player_ref, mechas_ref):
	player = player_ref
	mechas = mechas_ref
	player.connect("took_damage",Callable(self,"_on_player_took_damage"))
	player.connect("shoot_signal",Callable(self,"_on_player_shoot"))
	player.connect("update_reload_mode",Callable(self,"_on_reload_mode_update"))
	player.connect("update_lock_mode",Callable(self,"_on_lock_mode_update"))
	player.connect("reloading",Callable(self,"_on_reloading"))
	player.connect("finished_reloading",Callable(self,"update_cursor"))
	player.connect("component_damaged",Callable(self,"_on_component_damaged"))
	player.connect("component_destroyed_alert",Callable(self,"_on_component_destroyed"))
	player.connect("cockpit_exposed",Callable(self,"_on_cockpit_exposed"))
	player.connect("core_shell_destroyed",Callable(self,"_on_core_shell_destroyed"))
	player.connect("flagged",Callable(self,"_on_flagged"))
	player.connect("system_degraded",Callable(self,"_on_system_degraded"))
	Cursor.connect("enter_lock_mode",Callable(player,"_on_enter_lock_mode"))
	setup_cursor()
	hud_status.setup(player)
	hud_weapons.is_lost = hud_status.wireframe.is_weapon_lost
	hud_weapons.setup(player)
	hud_alerts.setup(player)
	interact_prompt.setup(player)
	hud_contacts.setup(player, mechas)
	hud_vision_outlines.setup(player)
	hud_world_labels.setup(player, mechas)
	hud_quick_chat.setup(player)
	if hud_squad_orders == null:
		hud_squad_orders = HudSquadOrders.new()
		hud_squad_orders.theme = hud_quick_chat.theme
		hud_quick_chat.get_parent().add_child(hud_squad_orders)
		hud_squad_orders.position = hud_quick_chat.position
	hud_squad_orders.setup(player)
	hud_sweep.setup(player)
	player.swept.connect(_on_player_swept)
	player.device_destroyed.connect(_on_player_device_destroyed)
	top_strip.setup(player)
	if player.build.chipset.has_radar:
		PlayerRadar.setup(mechas, player, player.build.chipset.radar_range, player.build.chipset.radar_refresh_rate)
		PlayerRadar.show()
	else:
		PlayerRadar.hide()
	DashCooldown.setup(player)
	hud_alerts.extracting = false
	for bullethole in Bulletholes.get_children():
		bullethole.modulate.a = 0

# This match's Local channel: the feed and quick chat (CombatScene).
func setup_local(local: LocalPilots) -> void:
	hud_local_feed.setup(local)
	hud_quick_chat.local = local


# Mecha.say, once CombatScene has found the player hears it.
func show_speech(mecha, text: String, seconds: float) -> void:
	hud_world_labels.show_speech(mecha, text, seconds)


# A buddy-up offer from `name` (CombatScene.offer_buddy): the prompt with its
# keys (Player.ACCEPT_ACTION, DECLINE_ACTION), up for `seconds`, as long as
# the offer stands.
func show_offer(name: String, seconds: float) -> void:
	hud_alerts.show_notice("%s OFFERS TO BUDDY UP · [%s] ACCEPT · [%s] DECLINE" % [name.to_upper(),
			MechUI.key_name("accept_offer"), MechUI.key_name("decline_offer")], seconds)


# A passing line about the player's squad ("ORDER: HOLD HERE", "<NAME> JOINED
# YOUR SQUAD"); "" clears the notice on show.
func show_squad_notice(text: String) -> void:
	hud_alerts.show_notice(text, HudAlerts.NOTICE_TIME if text != "" else 0.0)


# Someone's sweep found the player: an alert and a log line, no bearing.
func _on_player_swept() -> void:
	hud_alerts.show_swept()
	MechLog.write("SNS", "You were swept", MechLog.Kind.COMBAT)


# One of the player's devices was shot: only a mecha can do that, so someone
# is there.
func _on_player_device_destroyed(device) -> void:
	var kind := str(device.kind)
	hud_alerts.show_notice("%s DESTROYED" % kind.to_upper())
	MechLog.write("SNS", "%s destroyed" % kind.capitalize(), MechLog.Kind.COMBAT)


# Off unless a mode asks for it (Expedition, whose exits are far out).
func setup_exit_marker(exits: Array) -> void:
	exit_marker.setup(player, exits)


func set_extracting(value: bool) -> void:
	hud_alerts.extracting = value


# The site name and the map area for the grid square in the top strip
# (Expedition calls it; Arena shows no site).
func set_site(site_name: String, bounds: Rect2) -> void:
	top_strip.set_site(site_name, bounds)


func set_pause(_value):
	#Cursor.visible = not value
	pass


func setup_cursor():
	Cursor.set_max_ammo("left", player.get_clip_ammo("arm_weapon_left"))
	Cursor.set_max_ammo("right", player.get_clip_ammo("arm_weapon_right"))
	Cursor.set_lock_on_reticle_size(player.build.chipset.lock_on_reticle_size)


func update_cursor():
	Cursor.set_ammo("left", player.get_clip_ammo("arm_weapon_left"))
	Cursor.set_ammo("right", player.get_clip_ammo("arm_weapon_right"))


func player_died():
	player = false
	hud_status.player_died()
	hud_weapons.player_died()
	hud_alerts.player_died()
	interact_prompt.player_died()
	hud_contacts.player_died()
	hud_vision_outlines.player_died()
	hud_world_labels.player_died()
	hud_local_feed.player_died()
	hud_quick_chat.player_died()
	if hud_squad_orders != null:
		hud_squad_orders.player_died()
	hud_sweep.player_died()
	top_strip.player_died()
	top_strip.visible = false
	PlayerRadar.player_died()
	DashCooldown.player_died()
	Cursor.hide()


func play_blink_sound():
	var prog = LockingAnim.speed_scale/float(LOCKING_FINAL_BLINK - LOCKING_INIT_BLINK)
	var pitch = 1.0 + BLINK_PITCH_TARGET_MOD*prog
	AudioManager.play_sfx("blinking", false, pitch)


func _on_player_took_damage(_p, is_status):
	#Bullet holes logic
	if player.shield <= 0 and player.hp < player.max_hp*BULLET_THRESHOLD and\
	randf() <= BULLET_CHANCE and not is_status:
		var visible_holes = []
		for hole in Bulletholes.get_children():
			if hole.modulate.a == 0.0:
				visible_holes.append(hole)
		if not visible_holes.is_empty():
			var hole = visible_holes[randi() % visible_holes.size()]
			var tween = create_tween()
			hole.modulate.a = 0.0
			tween.tween_property(hole, "modulate:a", 1.0, HOLE_FADE_DUR)


func _on_player_shoot():
	update_cursor()


func _on_reload_mode_update(active):
	Cursor.set_reload_mode(active)


func _on_lock_mode_update(active):
	Cursor.set_lock_mode(active)


func _on_reloading(reload_time, side):
	Cursor.reloading(reload_time, side)


func _on_component_damaged(_part_name: String, _component_name: String, _hp: int, _max_hp: int):
	# TODO: Update component HP bars in UI
	pass

func _on_component_destroyed(_part_name: String, _component_name: String):
	# TODO: Show warning light/icon for destroyed component
	pass


func _on_cockpit_exposed(_hp: int):
	# TODO: Activate red warning flash for cockpit critical
	pass

func _on_core_shell_destroyed():
	# TODO: Deactivate cockpit warning, wait for flagged signal
	pass

func _on_flagged():
	# TODO: Show critical "mech flagged" UI
	pass

func _on_system_degraded(_system_name: String, _severity: float):
	# TODO: Update system status indicators
	# - Mobility bar showing % remaining
	# - Weapon offline icons
	# - Heat dispersion warning
	pass
