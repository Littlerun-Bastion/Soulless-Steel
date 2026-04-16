extends Node2D
class_name LootContainer

signal player_entered_range(container)
signal player_exited_range(container)
signal opened(container)
signal closed(container)

@export var grid_width: int = 4
@export var grid_height: int = 4
@export var persistent: bool = true
@export var container_id: String = ""  # for save/load later
@export var default_contents: Array[Dictionary] = []

var inventory: Inventory = null
var is_open: bool = false

@onready var interact_area: Area2D = $InteractArea


func _ready() -> void:
	_init_inventory()
	add_to_group("interactable")
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)


func _init_inventory() -> void:
	inventory = Inventory.new()
	inventory.initialize_grid(grid_width, grid_height)

	for entry in default_contents:
		if entry.has("item") and entry["item"] != null:
			var qty: int = int(entry.get("quantity", 1))
			inventory.add_item(entry["item"], qty)


# Called by the player when they press the interact key
func interact(player: Node) -> void:
	if is_open:
		return
	is_open = true
	emit_signal("opened", self)


func close() -> void:
	if not is_open:
		return
	is_open = false
	emit_signal("closed", self)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("mecha") and body.is_player():
		emit_signal("player_entered_range", self)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("mecha") and body.is_player():
		emit_signal("player_exited_range", self)
