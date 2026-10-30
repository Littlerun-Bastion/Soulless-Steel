extends Wreck
class_name Carcass

# What's left of a dead Entity in Expedition. It works like a Wreck (a loot
# container: glowing marker until searched, Take / Take all, darker once
# empty, NPCs may come and look), but it holds bio salvage rolled from the
# Entity's loot table and is drawn as the Entity's own corpse.
#
# Use: instantiate, setup_from(entity) while the Entity is still valid, then
# add to the tree at the Entity's position.

const CORPSE_TINT := Color(1, 1, 1)
const CORPSE_EMPTY_TINT := Color(0.5, 0.5, 0.5)


func setup_from(entity: Entity, rng: RandomNumberGenerator = null) -> void:
	setup(entity.mecha_name, entity.roll_loot(rng))
	display_name = "CARCASS - " + entity.mecha_name.to_upper()
	grid_width = entity.carcass_grid.x
	grid_height = entity.carcass_grid.y
	hull_tint = CORPSE_TINT
	empty_tint = CORPSE_EMPTY_TINT
	var hull: Node2D = $Hull
	hull.rotation = entity.global_rotation
	var corpse: Node2D = entity.body_visual.duplicate()
	hull.add_child(corpse)
	corpse.die()


func get_corpse() -> Node2D:
	return $Hull.get_child(0) if $Hull.get_child_count() > 0 else null
