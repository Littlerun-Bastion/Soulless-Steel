@tool
class_name PropSpawnPoint
extends Marker2D

# One hand-placed prop spawn. Put it under a PropSpawner. The node's position
# and rotation are used; `chance` is rolled once per map seed, so a point can
# be there in some raids and not others.

@export_enum("vehicle", "truck", "vehicle_wreck", "tree", "bush", "debris") var kind := "vehicle":
	set(value):
		kind = value
		_changed()
@export_range(0.0, 1.0) var chance := 1.0
## Sprite variant (index into the kind's sprite list); -1 picks one by position.
@export var variant := -1:
	set(value):
		variant = value
		_changed()
## Size in px; zero uses the kind's default size.
@export var size := Vector2.ZERO:
	set(value):
		size = value
		_changed()


func _changed() -> void:
	var spawner := get_parent() as PropSpawner
	if spawner:
		spawner.mark_dirty()
