extends LootContainer
class_name Wreck

# What's left of a destroyed mecha in Expedition: a loot container holding the
# salvage WreckLoot rolled for it, drawn as a darkened copy of the mecha's
# hull. Spawned by Expedition when an NPC dies.
#
# States (shown on the wreck itself):
#   UNSEARCHED  glowing marker, until the player first opens it
#   SEARCHED    opened, still has something in it
#   EMPTY       opened and nothing left: hull goes darker
#
# Unlike the test container it doesn't block movement, and its interact
# range is a comfortable circle around the hull.
#
# Use: instantiate, setup(), copy_mecha_visuals(), then add to the tree.

enum State { UNSEARCHED, SEARCHED, EMPTY }

const HULL_TINT := Color(0.38, 0.36, 0.34)
const EMPTY_TINT := Color(0.18, 0.18, 0.18)
const MARKER_ALPHA_MIN := 0.2
const MARKER_ALPHA_MAX := 0.55
const MARKER_PULSE_TIME := 0.9

var state: State = State.UNSEARCHED
var _pending_stacks: Array = []
var _pulse: Tween = null


func setup(mecha_name: String, stacks: Array) -> void:
	display_name = "WRECK - " + mecha_name.to_upper() if mecha_name != "" else "WRECK"
	_pending_stacks = stacks


# Copies the hull sprites (shoulders, core, chassis) where they were on the
# dead mecha. Call before adding the wreck to the tree, while the mecha is
# still valid; the wreck's own position should be the mecha's.
func copy_mecha_visuals(mecha: Node2D) -> void:
	var hull: Node2D = $Hull
	hull.rotation = mecha.global_rotation
	hull.scale = mecha.global_scale
	var to_mecha := mecha.global_transform.affine_inverse()
	for part in mecha.get_scrapable_parts():
		var sprite := Sprite2D.new()
		sprite.texture = part.texture
		sprite.centered = part.centered
		sprite.offset = part.offset
		sprite.flip_h = part.flip_h
		sprite.flip_v = part.flip_v
		sprite.transform = to_mecha * part.global_transform
		hull.add_child(sprite)


func _ready() -> void:
	super._ready()
	add_to_group("wreck")
	populate_stacks(_pending_stacks)
	_pending_stacks = []
	opened.connect(_on_opened)
	closed.connect(_on_closed)
	_update_visuals()


func _on_opened(_container) -> void:
	if state == State.UNSEARCHED:
		state = State.SEARCHED
	_update_visuals()


func _on_closed(_container) -> void:
	if state != State.UNSEARCHED and inventory.is_empty():
		state = State.EMPTY
	_update_visuals()


func _update_visuals() -> void:
	$Hull.modulate = EMPTY_TINT if state == State.EMPTY else HULL_TINT
	var marker: Sprite2D = $Marker
	marker.visible = state == State.UNSEARCHED
	if marker.visible and _pulse == null:
		_pulse = create_tween().set_loops()
		_pulse.tween_property(marker, "modulate:a", MARKER_ALPHA_MAX, MARKER_PULSE_TIME)
		_pulse.tween_property(marker, "modulate:a", MARKER_ALPHA_MIN, MARKER_PULSE_TIME)
	elif not marker.visible and _pulse != null:
		_pulse.kill()
		_pulse = null
