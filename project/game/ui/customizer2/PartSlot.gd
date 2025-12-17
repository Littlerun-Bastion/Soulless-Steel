extends Button
class_name PartSlot

enum SIDE {LEFT, RIGHT, SINGLE}


@onready var PartName = $MarginContainer/VBoxContainer/PartName
@onready var PartCategory = $MarginContainer/VBoxContainer/PartCategory

@export var part_type: String = "head"
@export var display_name: String = "HEAD"
@export var part_side: int = SIDE.SINGLE

var current_part_id: String = "" 
var player_mecha: Mecha = null
var inventory_ui: InventoryUI = null

func _ready() -> void:
	PartCategory.text = display_name

func setup():
	pass

func set_current_part(part):
	PartCategory.text = display_name
	current_part_id = part.part_id
	if part:
		var part_ref = PartManager.get_part(part_type, current_part_id)
		if part_ref:
			PartName.text = part_ref.part_name
		else:
			PartName.text = "UNKNOWN"
	

func set_equipped_part(part_id: String, item: item_data) -> void:
	print("set_equipped_part")
	current_part_id = part_id

func clear_equipped_part() -> void:
	current_part_id = ""
	PartName.text = "Empty"
	# icon = null

func _on_slot_pressed() -> void:
	if inventory_ui == null:
		return
	inventory_ui.unequip_part(self)
		
