extends Control

onready var LeftWeapon = $LeftWeapon
onready var RightWeapon = $RightWeapon


func _ready():
	 Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


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
		node.get_node("CurAmmo").text = str(max_ammo)
		node.get_node("MaxAmmo").text = str(max_ammo)
	else:
		push_error("Not a valid max_ammo value: " + str(max_ammo))


func set_ammo(side, ammo):
	var node = get_side_node(side)
	
	if node.visible:
		node.get_node("CurAmmo").text = str(ammo)
