extends Button
class_name PartSlot

enum SIDE {LEFT, RIGHT, SINGLE}


@onready var PartName = $MarginContainer/VBoxContainer/PartName
@onready var PartCategory = $MarginContainer/VBoxContainer/PartCategory

@export var part_type: String = "head"
@export var display_name: String = "HEAD"
@export var part_side: int = SIDE.SINGLE

# Pressing a slot is handled by whoever shows it (Mech OS EquipmentWindow
# connects `pressed` itself).
var current_part_id: String = ""
var player_mecha: Mecha = null

func _ready() -> void:
	PartCategory.text = display_name

func setup():
	pass

func set_current_part(part):
	if part:
		PartCategory.text = display_name
		current_part_id = part.part_id
		var part_ref = PartManager.get_part(part_type, current_part_id)
		if part_ref:
			PartName.text = part_ref.part_name
	else:
		current_part_id = ""
		PartName.text = "EMPTY"
	

# Right-click (MechOS context menu) on a filled slot targets its part:
# {"type": "part", "part_type", "part_id", "grade", "slot": <build key>}.
# The Equipment window around it knows the mecha; an empty slot gives nothing.
func get_context_target(_global_pos: Vector2) -> Dictionary:
	var node := get_parent()
	while node != null and not node is EquipmentWindow:
		node = node.get_parent()
	if node == null:
		return {}
	return (node as EquipmentWindow).slot_context(self)


func set_equipped_part(part_id: String, _item: item_data) -> void:
	current_part_id = part_id

func clear_equipped_part() -> void:
	current_part_id = ""
	PartName.text = "Empty"
	# icon = null
		
