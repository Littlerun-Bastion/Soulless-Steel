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
# The parts the body shed (MechaBody.shed) are wrecked: they lie beside it
# but can't be salvaged. unsalvageable lists them, and the loot window shows
# them under the loot, crossed out (InventoryWindow.show_unsalvageable). They
# aren't in the inventory: they can't be taken, weigh nothing and don't keep
# the wreck from reading EMPTY. A Coyote can still carry one off
# (MechaBody.take_part); it then leaves the list (unsalvageable_changed).
#
# Use: instantiate, setup(), copy_mecha_visuals(), then add to the tree.

signal unsalvageable_changed

enum State { UNSEARCHED, SEARCHED, EMPTY }

## How each shed part is named in the loot window.
const SLOT_LABELS := {
	"head": "HEAD",
	"left_shoulder": "L SHOULDER",
	"right_shoulder": "R SHOULDER",
	"arm_weapon_left": "L ARM",
	"arm_weapon_right": "R ARM",
	"shoulder_weapon_left": "L SHOULDER WPN",
	"shoulder_weapon_right": "R SHOULDER WPN",
}

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
## The parts shed beside it, in the order they came off, each {"slot",
## "label" (SLOT_LABELS), "part_type", "part_id", "name", "texture"}.
var unsalvageable: Array[Dictionary] = []
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
	body.parts_changed.connect(_list_unsalvageable)
	$Hull.add_child(body)


# The shed parts still lying here: not taken since (MechaBody.taken_slots).
func _list_unsalvageable() -> void:
	unsalvageable.clear()
	for slot in body.shed_slots:
		if slot in body.taken_slots or not body.part_ids.has(slot):
			continue
		var part_type := WreckLoot.part_type_of(slot)
		if slot in ["left_shoulder", "right_shoulder"]:
			part_type = "shoulders"
		var part_id: String = body.part_ids[slot]
		var part = PartManager.get_part(part_type, part_id) if PartManager.is_valid_part(part_type, part_id) else null
		var part_name = part.get("part_name") if part != null else null
		var texture = part.get("image") if part != null else null
		unsalvageable.append({
			"slot": slot,
			"label": SLOT_LABELS.get(slot, slot.to_upper()),
			"part_type": part_type,
			"part_id": part_id,
			"name": str(part_name) if part_name else part_id,
			"texture": texture if texture is Texture2D else null,
		})
	unsalvageable_changed.emit()


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
