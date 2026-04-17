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
@export var default_contents: Array[LootEntry] = []

var inventory: Inventory = null
var is_open: bool = false

@onready var interact_area: Area2D = $InteractArea


func _ready() -> void:
	_init_inventory()
	add_to_group("interactable")
	add_to_group("loot_container")
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)


func _init_inventory() -> void:
	inventory = Inventory.new()
	inventory.initialize_grid(grid_width, grid_height)

	if not default_contents.is_empty():
		populate(default_contents)

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
		body.add_interactable(self)
		emit_signal("player_entered_range", self)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("mecha") and body.is_player():
		body.remove_interactable(self)
		emit_signal("player_exited_range", self)
		if is_open:
			close()
			body.current_open_container = null

func populate(entries: Array) -> void:
	var stacks: Array = []
	for entry in entries:
		if entry is LootEntry and entry.item != null:
			var stack := item_stack.new()
			stack.item = entry.item
			stack.quantity = entry.quantity
			stacks.append(stack)
	var overflow := inventory.add_stacks_bulk(stacks)
	if not overflow.is_empty():
		push_warning("LootContainer '%s': %d items didn't fit." % [container_id, overflow.size()])
		#TODO: spawn as loose items on the ground when full
		_handle_overflow(overflow)

func _handle_overflow(overflow: Array) -> void:
	# TODO: spawn LooseItem nodes at this position. for now, items are lost
	for stack in overflow:
		push_warning("  Discarded: %s x%d" % [str(stack.item), stack.quantity])
