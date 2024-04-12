extends Node

const DATA_PATH = "res://database/items/"

@onready var ITEMS = {}
@onready var item_base = preload("res://game/ui/inventory/ItemBase.tscn")
@onready var inventory_slot = preload("res://game/ui/inventory/InventorySlot.tscn")

var player_inventory = {} #DEPRECIATE THIS ASAP YOU STUPID FUCK
var player_cargo = {}
var player_warehouse = {}
var item_held = null
var hovered_slot = null
var original_slot = null
var can_place := false
var warehouse_size = [6,10]

# Called when the node enters the scene tree for the first time.
func _ready():
	load_items()

func load_items():
	var path = DATA_PATH + "/"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				var key = file_name.replace(".tres", "").replace(".tscn", "").replace(".remap", "")
				ITEMS[key] = load(path + file_name.replace(".remap", ""))
				if ITEMS[key] is PackedScene:
					ITEMS[key] = ITEMS[key].instantiate()
				ITEMS[key].item_id = key
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access part path: " + str(DirAccess.get_open_error()))

func get_item(item_name):
	assert(ITEMS.has(item_name),"Not a existent item: " + str(item_name))
	return ITEMS[item_name]

			
func player_inventory_add_item(item_name, slot_id, quantity, part_type):
	player_inventory[slot_id] = {
		"item_name": item_name,
		"quantity": quantity,
		"part_type": part_type}
	debug_player_inventory_check()

func player_inventory_remove_item(slot_id):
	if player_inventory[slot_id]:
		print(str(slot_id) + " Removed: " + str(player_inventory[slot_id].item_name) + ", Quantity: " + str(player_inventory[slot_id].quantity))
		player_inventory.erase(slot_id)
		debug_player_inventory_check()

func debug_player_inventory_check():
	for child in player_inventory:
		print(str(child) + ": " + str(player_inventory[child].item_name) + ", Quantity: " + str(player_inventory[child].quantity) + " Part Type: " + str(player_inventory[child].part_type))

func destroy_item():
	var destroying_item = item_held
	item_held = null
	destroying_item.get_parent().remove_child(destroying_item)
	destroying_item.queue_free()

func switch_item(_item):
	var destroying_item = item_held
	item_held = _item
	destroying_item.get_parent().remove_child(destroying_item)
	destroying_item.queue_free()
