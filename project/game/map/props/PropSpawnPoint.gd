@tool
class_name PropSpawnPoint
extends Marker2D

# One hand-placed prop spawn. Put it under a PropSpawner. The node's position
# and rotation are used; `chance` is rolled once per map seed, so a point can
# be there in some raids and not others.
#
# `kind` is any prop kind's name. The inspector suggests the kinds the
# parent PropSpawner's generated set has and those with a default size
# (PropSpawner.DEFAULT_SIZE), so kinds the generator adds show up there.

@export var kind := "vehicle":
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


func _validate_property(property: Dictionary) -> void:
	if property.name == "kind":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(known_kinds())


# The kind names to suggest (see above), sorted.
func known_kinds() -> PackedStringArray:
	var names := PackedStringArray(PropSpawner.DEFAULT_SIZE.keys())
	var spawner := get_parent() as PropSpawner
	if spawner != null and spawner.spawn_set != null:
		for k in spawner.spawn_set.kinds:
			if not names.has(k):
				names.append(k)
	names.sort()
	return names
