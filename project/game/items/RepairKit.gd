class_name RepairKit
extends Node2D

signal used(by)

var display_name := "REPAIR KIT"
var interact_verb := "USE"

@onready var interact_area: Area2D = $InteractArea


func _ready() -> void:
	add_to_group("interactable")
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)


func interact(by: Node) -> void:
	if by == null or not by.has_method("repair_systems"):
		return
	by.repair_systems()
	by.remove_interactable(self)
	by.add_child(RepairBurst.new())
	AudioManager.play_sfx("confirm")
	used.emit(by)
	queue_free()


func _on_body_entered(body: Node) -> void:
	if _is_player(body):
		body.add_interactable(self)


func _on_body_exited(body: Node) -> void:
	if _is_player(body):
		body.remove_interactable(self)


func _is_player(body: Node) -> bool:
	return body.is_in_group("mecha") and body.is_player()
