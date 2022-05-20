extends Control

enum SIDE {LEFT, RIGHT}

onready var LeftWeapon = $LeftWeapon
onready var LeftReload = $LeftReloadProgress
onready var RightWeapon = $RightWeapon
onready var RightReload = $RightReloadProgress
onready var Crosshair = $Crosshair
onready var ReloadLabel = $ReloadLabel


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	Crosshair.show()
	ReloadLabel.hide()
	LeftReload.hide()
	RightReload.hide()


func _process(_delta):
	rect_position = lerp(rect_position, get_global_mouse_position(), .80)


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
	
	if node.visible:
		node.get_node("CurAmmo").text = "%02d" % ammo


func set_reload_mode(active):
	if active:
		Crosshair.hide()
		ReloadLabel.show()
	else:
		Crosshair.show()
		ReloadLabel.hide()


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
	
