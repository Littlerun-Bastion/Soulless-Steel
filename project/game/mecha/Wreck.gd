extends LootContainer
class_name Wreck

# What's left of a destroyed mecha in Expedition: a loot container holding the
# salvage WreckLoot rolled for it, drawn as the mecha's own body in its last
# pose (MechaBody, under $Hull). Spawned by Expedition when an NPC dies.
#
# States (shown on the wreck itself):
#   UNSEARCHED  glowing marker, until the player first opens it
#   SEARCHED    opened, still has something in it
#   EMPTY       opened and nothing left: hull goes darker
# The tints only dim the body, so its build stays readable.
#
# The hull is solid like the mecha was (MechaBody.solid): it blocks movement
# and stops shots, so it is cover. The interact range is a comfortable circle
# around the hull.
#
# Opening it also shows the mecha's kill record (kill_record) beside the loot
# (Player, KillRecordWindow).
#
# Use: instantiate, setup(), copy_mecha_visuals(), then add to the tree.

enum State { UNSEARCHED, SEARCHED, EMPTY }

const HULL_TINT := Color(0.85, 0.85, 0.85)
const EMPTY_TINT := Color(0.6, 0.6, 0.6)
const MARKER_ALPHA_MIN := 0.2
const MARKER_ALPHA_MAX := 0.55
const MARKER_PULSE_TIME := 0.9

var state: State = State.UNSEARCHED
## The dead mecha's KillRecord, shown beside the loot when opened; {} for
## none.
var kill_record := {}
# How the hull is tinted (Carcass draws a corpse, not grey metal).
var hull_tint := HULL_TINT
var empty_tint := EMPTY_TINT
## The mecha's body (copy_mecha_visuals); null for a Carcass.
var body: MechaBody = null
var _pending_stacks: Array = []
var _pulse: Tween = null


func setup(mecha_name: String, stacks: Array) -> void:
	display_name = "WRECK - " + mecha_name.to_upper() if mecha_name != "" else "WRECK"
	_pending_stacks = stacks


# Copies the dead mecha's body into the hull (MechaBody.copy_from). Call
# before adding the wreck to the tree, while the mecha is still valid; the
# wreck's own position should be the mecha's. Shed parts once it is in the
# tree (body.shed).
func copy_mecha_visuals(mecha: Node2D) -> void:
	body = MechaBody.new()
	body.copy_from(mecha)
	$Hull.add_child(body)


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
	$Hull.modulate = empty_tint if state == State.EMPTY else hull_tint
	var marker: Sprite2D = $Marker
	marker.visible = state == State.UNSEARCHED
	if marker.visible and _pulse == null:
		_pulse = create_tween().set_loops()
		_pulse.tween_property(marker, "modulate:a", MARKER_ALPHA_MAX, MARKER_PULSE_TIME)
		_pulse.tween_property(marker, "modulate:a", MARKER_ALPHA_MIN, MARKER_PULSE_TIME)
	elif not marker.visible and _pulse != null:
		_pulse.kill()
		_pulse = null
