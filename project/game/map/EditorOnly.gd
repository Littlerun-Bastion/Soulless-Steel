@tool
extends Node

# Attach to any node that should exist only in the editor, such as reference
# images or guide overlays. The node and its children are removed when the game runs.


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
