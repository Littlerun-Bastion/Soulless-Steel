extends Button

enum SIDE {LEFT, RIGHT, SINGLE}

@export var type : String
@export var subtype : String
@export var slot_type = "mecha_slot"
@export var side: SIDE
@onready var Tagline = $Tagline



signal reset_comparison
signal equip_part
signal mecha_slot_mouse_entered
signal mecha_slot_mouse_exited

var part_data
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func change_part(part):
	if part:
		var _type = type
		if type.contains("arm_weapon"):
			_type = "arm_weapon"
		if type.contains("shoulder_weapon"):
			_type = "shoulder_weapon"
		part_data = PartManager.get_part(_type, part)
		if part_data:
			var _icon = part_data.image
			if type.contains("weapon"):
				var img = _icon.get_image()
				img.rotate_90(CLOCKWISE)
				_icon = ImageTexture.create_from_image(img)
				self.set("theme_override_constants/icon_max_width", 250)
			else:
				self.set("theme_override_constants/icon_max_width", 100)
			self.icon = _icon
			Tagline.text = part_data.tagline
		else:
			self.icon = null
			Tagline.text = ""
			part_data = null
	else:
		self.icon = null
		Tagline.text = ""
		part_data = null

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if not Input.is_action_pressed("left_click") and get_global_rect().has_point(get_global_mouse_position()) and visible and ItemManager.item_held:
		equip_item(true)

func _input(event):
	if Input.is_action_just_pressed("left_click") and get_global_rect().has_point(get_global_mouse_position()) and part_data and part_data.part_id != "Null" and visible:
		equip_item(false)
	if Input.is_action_just_released("left_click") and get_global_rect().has_point(get_global_mouse_position()) and visible:
		equip_item(true)

func _on_mouse_entered():
	ItemManager.hovered_slot = self
	if ItemManager.item_held and ItemManager.item_held.part_type == type:
		ItemManager.can_place = true


func _on_mouse_exited():
	ItemManager.hovered_slot = null
	ItemManager.can_place = false

func equip_item(equipping):
	var _item
	var _type = type
	if equipping and ItemManager.item_held:	
		_item = ItemManager.item_held.item_id
	elif not equipping:
		unequip_item(_type)
		return
	if _type.contains("right"):
		if "arm_weapon" in _type:
			_type = "arm_weapon"
		elif "shoulder_weapon" in _type:
			_type = "shoulder_weapon"
		emit_signal("equip_part", _type, [_item,1])
	elif _type.contains("left"):
		if "arm_weapon" in _type:
			_type = "arm_weapon"
		elif "shoulder_weapon" in _type:
			_type = "shoulder_weapon"
		emit_signal("equip_part", _type, [_item,0])
	else:
		emit_signal("equip_part", _type, [_item,2])
	change_part(_item)
	emit_signal("reset_comparison")

func unequip_item(_type):
	if _type.contains("right"):
		if "arm_weapon" in _type:
			_type = "arm_weapon"
		elif "shoulder_weapon" in _type:
			_type = "shoulder_weapon"
		emit_signal("equip_part", _type, [null,1])
	elif _type.contains("left"):
		if "arm_weapon" in _type:
			_type = "arm_weapon"
		elif "shoulder_weapon" in _type:
			_type = "shoulder_weapon"
		emit_signal("equip_part", _type, [null,0])
	else:
		emit_signal("equip_part", _type, [null,2])
	change_part(null)
	emit_signal("reset_comparison")
	
