class_name SalvagePickup
extends Node2D

# The node of one SalvageField source that is picked up, not searched (the
# pieces of a destroyed car): Interact moves everything that fits straight
# into the player's cargo, with no window. What doesn't fit stays. The field
# makes and frees the node and owns its inventory.
#
# Needs a child Area2D named InteractArea (the field adds it): the player
# coming into it can use the pickup (Mecha.add_interactable).

signal picked_up(pickup: SalvagePickup, moved: int)

## The field's index of the source this node stands for.
var source_index := -1
var inventory: Inventory = null
var display_name := ""
var interact_verb := "PICK UP"
## Never open: a pickup has no window (InteractPrompt hides open things).
var is_open := false

var _player: Node = null


func _ready() -> void:
	add_to_group("interactable")
	var area := get_node_or_null("InteractArea") as Area2D
	if area != null:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.remove_interactable(self)
	_player = null


func interact(by: Node) -> void:
	if by == null or not by.has_method("is_player") or not by.is_player():
		return
	var cargo: Inventory = by.get("mech_inventory")
	if cargo == null or inventory == null:
		return
	var moved := inventory.transfer_all_to(cargo)
	picked_up.emit(self, moved)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("mecha") and body.has_method("is_player") and body.is_player():
		body.add_interactable(self)
		_player = body


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("mecha") and body.has_method("is_player") and body.is_player():
		body.remove_interactable(self)
		_player = null
