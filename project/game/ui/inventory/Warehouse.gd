extends Control

@onready var item_base = preload("res://game/ui/inventory/ItemBase.tscn")
@onready var inventory_slot = preload("res://game/ui/inventory/InventorySlot.tscn")
@onready var grid_container = $MarginContainer/HBoxContainer/Storage/MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var scroll_container = $MarginContainer/HBoxContainer/Storage/MarginContainer/VBoxContainer/ScrollContainer
@onready var cargo_grid_container = $MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/BasicStats/MarginContainer/VBoxContainer2/MarginContainer2/Cargo/MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var cargo_scroll_container = $MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/BasicStats/MarginContainer/VBoxContainer2/MarginContainer2/Cargo/MarginContainer/VBoxContainer/ScrollContainer
@onready var y_count = grid_container.columns
@onready var DisplayMecha = $Mecha
@onready var ComparisonMecha = $ComparisonMecha
@onready var MechaSlots = $MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer/MechaSlotsContainer
@onready var BasicStats = $MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/BasicStats/MarginContainer/VBoxContainer2/MarginContainer/GridContainer
@onready var Tabs = $MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/HBoxContainer

var num_slots = 480
var grid_array := []
var cargo_grid_array := []
var item_held = null
var hovered_slot = null
var original_slot = null
var can_place := false
var item_anchor : Vector2
var cargo_x = 0
var cargo_y = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	if Profile.stats.current_mecha:
		DisplayMecha.set_parts_from_design(Profile.stats.current_mecha)
		ComparisonMecha.set_parts_from_design(Profile.stats.current_mecha)
		for slot in MechaSlots.get_children():
			#slot.mecha_slot_pressed.connect(_on_mecha_slot_pressed)
			slot.mecha_slot_mouse_entered.connect(_on_mecha_slot_mouse_entered)
			slot.mecha_slot_mouse_exited.connect(_on_mecha_slot_mouse_exited)
			if DisplayMecha.build[slot.type]:
				slot.change_part(DisplayMecha.build[slot.type].part_id)
			else:
				slot.change_part(null)
	else:
		push_error("Couldn't find a current mecha")
	
	#for i in range(num_slots):
	#	create_slot()
	
	grid_container.setup(ItemManager.warehouse_size)
	cargo_grid_container.setup([5,8])
	#setup_cargo()
	
	ComparisonMecha.global_rotation = 0
	for child in BasicStats.get_children():
		child.reset_comparison(DisplayMecha)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
	
func create_cargo_slot():
	var new_slot = inventory_slot.instantiate()
	new_slot.slot_id = cargo_grid_array.size()
	cargo_grid_container.add_child(new_slot)
	cargo_grid_array.append(new_slot)
	new_slot.inventory_slot_entered.connect(_on_slot_mouse_entered)
	new_slot.inventory_slot_exited.connect(_on_slot_mouse_exited)

func setup_cargo():
	if DisplayMecha.build.core:
		var cargo_space_total = DisplayMecha.get_cargo_space()
		cargo_x = cargo_space_total[0]
		cargo_y = cargo_space_total[1]
	for i in range(cargo_x * cargo_y):
		create_cargo_slot()

func _on_slot_mouse_entered(slot):
	item_anchor = Vector2(100,100)
	hovered_slot = slot
	if hovered_slot.item_stored and hovered_slot.item_stored.part_type and not hovered_slot.item_stored.part_type.contains("weapon"):
		ComparisonMecha.callv("set_" + str(hovered_slot.item_stored.part_type), [hovered_slot.item_stored.item_id])
		for child in BasicStats.get_children():
			child.set_comparing_part(DisplayMecha,ComparisonMecha)
	
func _on_slot_mouse_exited(slot):
	if slot.item_stored and slot.item_stored.part_type and not slot.item_stored.part_type.contains("weapon"):
		ComparisonMecha.set_parts_from_design(Profile.stats.current_mecha)
		for child in BasicStats.get_children():
			child.reset_comparison(DisplayMecha)
	if not item_held and not scroll_container.get_global_rect().has_point(get_global_mouse_position()):
		hovered_slot = null

func place_item(_slot):
	var adjusted_position = _slot.global_position
	adjusted_position.x += 25
	adjusted_position.y += 25
	if not _slot:
		bounce_back()
	if _slot.slot_type == "mecha_slot" and item_held.part_type:
		var _type = _slot.type
		if not item_held.part_type in _type:
			bounce_back()
		if PartManager.get_part(_type, item_held.item_id):
			equip_part(_type, item_held.item_id)
		_slot.change_part(DisplayMecha.build[_slot.type].part_id)
		item_held.queue_free()
		original_slot = null
	elif _slot.slot_type == "inventory_slot":
		item_held.snap_to(adjusted_position)
		item_held.get_parent().remove_child(item_held)
		grid_container.add_child(item_held)
		item_held.global_position = get_global_mouse_position()
		item_held.grid_anchor = _slot.slot_id
		for row in item_held.item_size[1]:
			for space in item_held.item_size[0]:
				var slot_id_to_check = _slot.slot_id + space + (row * y_count)
				grid_array[slot_id_to_check].state = grid_array[slot_id_to_check].States.FILLED
				grid_array[slot_id_to_check].item_stored = item_held
		ItemManager.player_inventory_add_item(item_held.item_name, _slot.slot_id, item_held.quantity, item_held.part_type)
		original_slot = null
	item_held = null
	
func pick_up_item():
	if hovered_slot and hovered_slot.slot_type == "inventory_slot" and hovered_slot.item_stored:
		item_held = hovered_slot.item_stored
		item_held.selected = true
		item_held.get_parent().remove_child(item_held)
		add_child(item_held)
		item_held.global_position = get_global_mouse_position()
		ItemManager.player_inventory_remove_item(item_held.grid_anchor)
		for row in item_held.item_size[1]:
			for space in item_held.item_size[0]:
				var slot_id_to_check = item_held.grid_anchor + space + (row * y_count)
				grid_array[slot_id_to_check].state = grid_array[slot_id_to_check].States.EMPTY
				grid_array[slot_id_to_check].item_stored = null
		original_slot = hovered_slot
	elif hovered_slot and hovered_slot.slot_type == "mecha_slot":
		if not DisplayMecha.build[hovered_slot.type] and not item_held:
			return
		if DisplayMecha.build[hovered_slot.type].part_id == "Null" and not item_held:
			return
		var unequipped_item = item_base.instantiate()
		unequipped_item.setup_item(DisplayMecha.build[hovered_slot.type].part_id, hovered_slot.type)
		add_child(unequipped_item)

		if not item_held:
			hovered_slot.change_part(null)
			unequip_part(hovered_slot.type)
		item_held = unequipped_item	
		item_held.selected = true
		item_held.global_position = get_global_mouse_position()
		original_slot = hovered_slot

func unequip_part(_type):
	if _type.contains("right"):
		if "arm_weapon" in _type:
			_type = "arm_weapon"
		elif "shoulder_weapon" in _type:
			_type = "shoulder_weapon"
		DisplayMecha.callv("set_" + str(_type), [null,1])
		ComparisonMecha.callv("set_" + str(_type), [null,1])
	elif _type.contains("left"):
		if "arm_weapon" in _type:
			_type = "arm_weapon"
		elif "shoulder_weapon" in _type:
			_type = "shoulder_weapon"
		DisplayMecha.callv("set_" + str(_type), [null,0])
		ComparisonMecha.callv("set_" + str(_type), [null,0])
	else:
		DisplayMecha.callv("set_" + str(_type), [null])
		ComparisonMecha.callv("set_" + str(_type), [null])
	Profile.set_stat("current_mecha", DisplayMecha.get_design_data())
	for child in BasicStats.get_children():
		child.reset_comparison(DisplayMecha)
	shoulder_weapon_check()
	update_weight()

func equip_part(_type,_part):
	if not item_held:
		return
	if _type.contains("right"):
		if "arm_weapon" in _type:
			_type = "arm_weapon"
		elif "shoulder_weapon" in _type:
			_type = "shoulder_weapon"
		DisplayMecha.callv("set_" + str(_type), [_part,1])
		ComparisonMecha.callv("set_" + str(_type), [_part,1])
	elif _type.contains("left"):
		if "arm_weapon" in _type:
			_type = "arm_weapon"
		elif "shoulder_weapon" in _type:
			_type = "shoulder_weapon"
		DisplayMecha.callv("set_" + str(_type), [_part,0])
		ComparisonMecha.callv("set_" + str(_type), [_part,0])
	else:
		DisplayMecha.callv("set_" + str(_type), [_part])
		ComparisonMecha.callv("set_" + str(_type), [_part])
	for child in BasicStats.get_children():
		child.reset_comparison(DisplayMecha)

func shoulder_weapon_check():
	if not DisplayMecha.build.core:
		pass


func update_weight():
	pass

func _on_mecha_slot_mouse_entered(_slot):
	hovered_slot = _slot
	if item_held and item_held.part_type == hovered_slot.type:
		can_place = true
	
func _on_mecha_slot_mouse_exited(_slot):
	hovered_slot = null
	can_place = false

func bounce_back():
	pass

func _on_tab_pressed(subtype):
	for child in MechaSlots.get_children():
		if child.subtype == subtype:
			child.visible = true
		else:
			child.visible = false
	for child in Tabs.get_children():
		if child.name != subtype:
			child.button_pressed = false
	$MarginContainer/HBoxContainer/Hangar/MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer/TabLabel.text = subtype
	


func _on_button_pressed():
	var unequipped_item = ItemManager.item_base.instantiate()
	unequipped_item.setup_item("TestItem", null)
	ItemManager.item_held = unequipped_item
	ItemManager.item_held.selected = true
	add_child(ItemManager.item_held)
	ItemManager.item_held.global_position = get_global_mouse_position()
