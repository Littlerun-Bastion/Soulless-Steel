@tool
class_name PropZone
extends Polygon2D

# A hand-drawn area that changes prop spawning. Put it under a PropSpawner and
# draw its outline with Godot's Polygon2D tools. It shows only in the editor.
#
# CLEAR removes generated spawn points of the listed kinds inside it (all
#   kinds if the list is empty). Use it round hand-built areas.
# SCATTER adds points of the listed kinds inside it, picked at random, at
#   `density` points per 100 m^2 (a 200 x 200 px square), no closer than
#   `min_spacing` px, and not inside buildings.
# Hand-placed PropSpawnPoints are never cleared.

enum Mode { CLEAR, SCATTER }

@export var mode := Mode.CLEAR:
	set(value):
		mode = value
		_changed()
@export var kinds := PackedStringArray():
	set(value):
		kinds = value
		_changed()
@export var density := 1.0:
	set(value):
		density = value
		_changed()
@export var min_spacing := 80.0:
	set(value):
		min_spacing = value
		_changed()
@export var zone_seed := 0:
	set(value):
		zone_seed = value
		_changed()


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
	_changed()


func applies_to(k: String) -> bool:
	return kinds.is_empty() or kinds.has(k)


# The zone's outline in the parent spawner's space.
func outline() -> PackedVector2Array:
	return transform * polygon


func _changed() -> void:
	color = Color(1, 0.3, 0.3, 0.25) if mode == Mode.CLEAR else Color(0.3, 1, 0.4, 0.25)
	var spawner := get_parent() as PropSpawner
	if spawner:
		spawner.mark_dirty()
