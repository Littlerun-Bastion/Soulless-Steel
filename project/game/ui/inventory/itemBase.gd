extends Node2D

var item_name : String
var item_description : String
var item_tagline : String
var item_size :=[1,1]
var icon : Texture2D

@onready var Icon = $Icon
@onready var Quantity = $Icon/Quantity
@onready var Tagline = $Icon/Tagline

var item_grids := []
var selected = false
var grid_anchor = null
var item_id
var quantity = 1
var part_type
var weapon_side

func _ready():
	Icon.texture = icon
	Icon.custom_minimum_size.x = item_size[0] * 50
	Icon.custom_minimum_size.y = item_size[1] * 50
	Icon.size.x = item_size[0] * 50
	Icon.size.y = item_size[1] * 50
	$Panel.size.x = item_size[0] * 50
	$Panel.size.y = item_size[1] * 50
	Quantity.text = str(quantity)
	Tagline.text = str(item_tagline)
	
	if quantity == 1:
		Quantity.visible = false
	else:
		Quantity.visible = true

func setup_item(_item_name, _part_type):
	if not _item_name or _item_name == "Null":
		return
	var data
	if _part_type:
		
		if "arm_weapon" in _part_type:
			weapon_side = _part_type
			part_type = "arm_weapon"
		elif "shoulder_weapon" in _part_type:
			weapon_side = _part_type
			part_type = "shoulder_weapon"
		else:
			part_type = _part_type
		data = PartManager.get_part(part_type, _item_name)
		if data:
			item_name = data.part_name
			item_description = data.description
			item_tagline = data.tagline
			item_size = data.item_size
			item_id = data.part_id
			if part_type.contains("weapon"):
				var img = data.image.get_image()
				img.rotate_90(CLOCKWISE)
				icon = ImageTexture.create_from_image(img)
			else:
				icon = data.image
	else:	
		data = ItemManager.get_item(_item_name)
		part_type = null
		if data:
			item_name = data.item_name
			item_description = data.item_description
			item_tagline = data.tagline
			item_size = data.item_size
			if data.is_horizontal:
				var img = data.icon.get_image()
				img.rotate_90(CLOCKWISE)
				icon = ImageTexture.create_from_image(img)
			else:
				icon = data.icon
			item_size = data.item_size
			item_id = data.item_id
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if selected:
		global_position = lerp(global_position, get_global_mouse_position(), 25 * delta)

func snap_to(snap_point:Vector2):
	var tween = get_tree().create_tween()
	tween.tween_property(self, "global_position", snap_point, 0.15).set_trans(Tween.TRANS_SINE)
	selected = false
