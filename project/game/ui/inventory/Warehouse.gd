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
	ShaderEffects.reset_shader_effect("main_menu")
	if Profile.stats.current_mecha:
		DisplayMecha.set_parts_from_design(Profile.stats.current_mecha)
		ComparisonMecha.set_parts_from_design(Profile.stats.current_mecha)
		for slot in MechaSlots.get_children():
			if DisplayMecha.build[slot.type]:
				slot.change_part(DisplayMecha.build[slot.type].part_id)
			else:
				slot.change_part(null)
	else:
		push_error("Couldn't find a current mecha")
	
	for child in MechaSlots.get_children():
		child.reset_comparison.connect(_reset_comparison)
		child.equip_part.connect(equip_part)
	
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

func equip_part(_type,_part):
	var _typecheck = _type
	if _part[1] == 1:
		_typecheck = str(_typecheck + "_right")
	if _part[1] == 0:
		_typecheck = str(_typecheck + "_left")
	if _part[1] == 2:
		_part.remove_at(1)
	print(_typecheck)
	if DisplayMecha.build[_typecheck] and DisplayMecha.build[_typecheck].part_id != "Null":
		var unequipped_item = ItemManager.item_base.instantiate()
		unequipped_item.setup_item(DisplayMecha.build[_typecheck].part_id, _type)
		add_child(unequipped_item)
		unequipped_item.global_position = get_global_mouse_position()
		if ItemManager.item_held:
			ItemManager.switch_item(unequipped_item)
			ItemManager.item_held.selected = true
		else:
			ItemManager.item_held = unequipped_item
			ItemManager.item_held.selected = true
	else:
		if ItemManager.item_held:
			ItemManager.destroy_item() 
	DisplayMecha.callv("set_" + str(_type), _part)
	ComparisonMecha.callv("set_" + str(_type), _part)

func shoulder_weapon_check():
	if not DisplayMecha.build.core:
		pass


func update_weight():
	pass

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
	
func _reset_comparison():
	for child in BasicStats.get_children():
		child.reset_comparison(DisplayMecha)

#func _on_button_pressed():
#	var unequipped_item = ItemManager.item_base.instantiate()
#	unequipped_item.setup_item("TestItem", null)
#	ItemManager.item_held = unequipped_item
#	ItemManager.item_held.selected = true
	#add_child(ItemManager.item_held)
	#ItemManager.item_held.global_position = get_global_mouse_position()
