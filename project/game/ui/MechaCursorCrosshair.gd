extends Control

signal enter_lock_mode

enum SIDE {LEFT, RIGHT}
enum MODES {NEUTRAL, RELOAD, ACTIVATING_LOCK, LOCK}

const ALPHA_SPEED = 8
const LOCKING_TIME_COOLDOWN = 1.0
const CROSSHAIRS = {
	"regular": preload("res://assets/images/ui/player_ui/cursor_crosshair.png"),
	"lock": preload("res://assets/images/ui/player_ui/lockon_crosshair.png"),
}

onready var LeftWeapon = $LeftWeapon
onready var LeftReload = $LeftReloadProgress
onready var RightWeapon = $RightWeapon
onready var RightReload = $RightReloadProgress
onready var Crosshair = $Crosshair
onready var ReloadLabel = $ReloadLabel
onready var ChangeModeProgress = $ChangeModeProgress

var cur_mode = MODES.NEUTRAL
var change_mode_timer := 0.0
var lock_reticle_size := 5


func _ready():
	MouseManager.hide_cursor()
	for node in [Crosshair, LeftWeapon, RightWeapon, LeftReload, RightReload]:
		set_alpha(node, 1.0)
	for node in [ReloadLabel, ChangeModeProgress]:
		set_alpha(node, 0.0)
	LeftReload.hide()
	RightReload.hide()

func _process(dt):
	var screen_scale = get_viewport_rect().size/OS.window_size
	var target_pos = get_global_mouse_position() * screen_scale
	rect_position = lerp(rect_position, target_pos, .80)
	
	match cur_mode:
		MODES.NEUTRAL:
			show_specific_nodes(dt, [Crosshair, LeftWeapon, RightWeapon, LeftReload, RightReload])
		MODES.RELOAD:
			show_specific_nodes(dt, [ReloadLabel, LeftWeapon, RightWeapon, LeftReload, RightReload])
		MODES.ACTIVATING_LOCK:
			show_specific_nodes(dt, [ChangeModeProgress])
		MODES.LOCK:
			show_specific_nodes(dt, [Crosshair])
	
	#Update changing-to-lock-mode progress
	if cur_mode == MODES.ACTIVATING_LOCK:
		change_mode_timer = min(change_mode_timer + dt, LOCKING_TIME_COOLDOWN)
		if change_mode_timer >= LOCKING_TIME_COOLDOWN:
			cur_mode = MODES.LOCK
			emit_signal("enter_lock_mode")
	else:
		change_mode_timer = max(change_mode_timer - 10*dt, 0.0)
	ChangeModeProgress.value = 100*change_mode_timer/float(LOCKING_TIME_COOLDOWN)
	
	if cur_mode == MODES.LOCK:
		Crosshair.texture = CROSSHAIRS.lock
		var sc = (2*lock_reticle_size)/float(Crosshair.texture.get_width())
		Crosshair.scale = Vector2(sc, sc)
	else:
		Crosshair.texture = CROSSHAIRS.regular
		Crosshair.scale = Vector2(1.0, 1.0)

func show_specific_nodes(dt, show_nodes):
	for node in [Crosshair, LeftWeapon, RightWeapon, LeftReload, RightReload,\
				 ReloadLabel, ChangeModeProgress]:
		if show_nodes.has(node):
			change_alpha(dt, node, 1.0)
		else:
			change_alpha(dt, node, 0.0)


func set_alpha(node, target_value):
	node.modulate.a = target_value


func change_alpha(dt, node, target_value):
	if node.modulate.a > target_value:
		node.modulate.a = max(node.modulate.a - dt*ALPHA_SPEED, target_value)
	else:
		node.modulate.a = min(node.modulate.a + dt*ALPHA_SPEED, target_value)


func get_side_node(side):
	if side == "left":
		return LeftWeapon
	elif side == "right":
		return RightWeapon
	else:
		push_error("Not a valid side: " + str(side))
		return null


func set_max_ammo(side, max_ammo):
	var node = get_side_node(side)
	if max_ammo is bool and not max_ammo:
		node.visible = false
	elif max_ammo is int:
		node.visible = true
		node.get_node("CurAmmo").text = "%02d" % max_ammo
		node.get_node("MaxAmmo").text = "%02d" % max_ammo
	else:
		push_error("Not a valid max_ammo value: " + str(max_ammo))


func set_ammo(side, ammo):
	var node = get_side_node(side)
	node.get_node("CurAmmo").text = "%02d" % ammo


func set_lock_on_reticle_size(value):
	lock_reticle_size = value


func set_lock_mode(active):
	cur_mode = MODES.ACTIVATING_LOCK if active else MODES.NEUTRAL
	

func set_reload_mode(active):
	cur_mode = MODES.RELOAD if active else MODES.NEUTRAL


func reloading(reload_time, side):
	var weapon_node
	var reload_node
	if side == SIDE.LEFT:
		weapon_node = LeftWeapon
		reload_node = LeftReload
	elif side == SIDE.RIGHT:
		weapon_node = RightWeapon
		reload_node = RightReload
	else:
		push_error("Not a valid side: " + str(side))
	weapon_node.hide()
	reload_node.show()
	var tween = reload_node.get_node("Tween") as Tween
	tween.stop_all()
	tween.interpolate_property(reload_node, "value", 0, 100, reload_time, Tween.TRANS_LINEAR)
	tween.start()
	
	yield(tween, "tween_completed")
	weapon_node.show()
	reload_node.hide()
