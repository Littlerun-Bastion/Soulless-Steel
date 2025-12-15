extends Button
class_name PartSlot

enum SIDE {LEFT, RIGHT, SINGLE}


@onready var PartName = $MarginContainer/VBoxContainer/PartName
@onready var PartCategory = $MarginContainer/VBoxContainer/PartCategory

@export var part_type: String = "head"
@export var display_name: String = "HEAD"
@export var part_side: int = SIDE.SINGLE

var current_part_id: String = "" 
var current_item: item_data = null
var player_mecha: Mecha = null

func _ready() -> void:
	PartCategory.text = display_name

func setup():
	pass

func set_current_part(part):
	PartCategory.text = display_name
	if part:
		PartName.text = part.part_name

func set_equipped_part(part_id: String, item: item_data) -> void:
	current_part_id = part_id
	current_item = item
	if current_item.part_scene:
		PartName.text = current_item.part_scene.part_name
	else:
		PartName.text = "Error: no part scene. Tell the devs." 

func clear_equipped_part() -> void:
	current_part_id = ""
	current_item = null
	PartName.text = "Empty"
	# icon = null
