extends Node2D
class_name WireframeDisplay

# The HUD frame readout: the mecha seen from above, one outline per part,
# turning with the mecha. Each part is an OutlinePart that draws its outline
# in the style for its damage state (see OutlinePart). Drawn 1:1: the old
# sprites needed scale 0.33, which thinned their lines; the outlines are
# traced at HUD size instead (WireframeTracer, wireframe_outlines.tres), and
# the part positions in the scene are the sprite ones x WireframeTracer.SCALE.
# The right shoulder and right chassis leg draw the left outlines mirrored.

@export var outlines: WireframeOutlines = preload("res://game/ui/wireframe/wireframe_outlines.tres")
# Rotated 1px lines: smooth (true) or hard pixels (false). Spec open item:
# compare both under the CRT shader.
@export var antialiased := false:
	set(value):
		antialiased = value
		if is_node_ready():
			for part in _all_parts():
				part.antialiased = value

# Static parts — no independent rotation, sit directly on display root
@onready var sprite_core: OutlinePart = $WFCore
@onready var node_head: Node2D = $WFNodeHead
@onready var sprite_head: OutlinePart = $WFNodeHead/WFHead
@onready var node_chassis_single: Node2D = $WFNodeChassisSingle
@onready var sprite_chassis_single: OutlinePart = $WFNodeChassisSingle/WFChassisSingle

# Chassis legs — wrapper Node2D positioned at hip anchor, part offset inside
@onready var node_chassis_left: Node2D = $WFNodeChassisLeft
@onready var sprite_chassis_left: OutlinePart = $WFNodeChassisLeft/WFChassisLeft
@onready var node_chassis_right: Node2D = $WFNodeChassisRight
@onready var sprite_chassis_right: OutlinePart = $WFNodeChassisRight/WFChassisRight

# Shoulders — rotate independently (cursor-driven, small limit)
@onready var node_left_shoulder: Node2D = $WFNodeLeftShoulder
@onready var sprite_left_shoulder: OutlinePart = $WFNodeLeftShoulder/WFLeftShoulder
@onready var node_right_shoulder: Node2D = $WFNodeRightShoulder
@onready var sprite_right_shoulder: OutlinePart = $WFNodeRightShoulder/WFRightShoulder

# Arm weapons — rotate independently from shoulders
@onready var node_left_arm: Node2D = $WFNodeLeftArm
@onready var sprite_left_arm_weapon: OutlinePart = $WFNodeLeftArm/WFLeftArmWeapon
@onready var node_right_arm: Node2D = $WFNodeRightArm
@onready var sprite_right_arm_weapon: OutlinePart = $WFNodeRightArm/WFRightArmWeapon

# Shoulder weapons — rotate independently, not related to shoulder nodes
@onready var node_left_shoulder_weapon: Node2D = $WFNodeLeftShoulderWeapon
@onready var sprite_left_shoulder_weapon: OutlinePart = $WFNodeLeftShoulderWeapon/WFLeftShoulderWeapon
@onready var node_right_shoulder_weapon: Node2D = $WFNodeRightShoulderWeapon
@onready var sprite_right_shoulder_weapon: OutlinePart = $WFNodeRightShoulderWeapon/WFRightShoulderWeapon

var player: Node
var _is_legs: bool = false


func _ready() -> void:
	sprite_core.outline = outlines.get_outline("core")
	sprite_head.outline = outlines.get_outline("head")
	sprite_chassis_single.outline = outlines.get_outline("chassis_single")
	sprite_chassis_left.outline = outlines.get_outline("chassis_leg")
	sprite_chassis_right.outline = outlines.get_outline("chassis_leg")
	sprite_left_shoulder.outline = outlines.get_outline("shoulder")
	sprite_right_shoulder.outline = outlines.get_outline("shoulder")
	for weapon in [sprite_left_arm_weapon, sprite_right_arm_weapon,
			sprite_left_shoulder_weapon, sprite_right_shoulder_weapon]:
		weapon.outline = outlines.get_outline("weapon")
	# Mirror, don't flip: the right side uses the left outlines with x negated.
	sprite_right_shoulder.mirror = true
	sprite_chassis_right.mirror = true
	for part in _all_parts():
		part.antialiased = antialiased


func _all_parts() -> Array:
	return [sprite_core, sprite_head, sprite_chassis_single, sprite_chassis_left,
		sprite_chassis_right, sprite_left_shoulder, sprite_right_shoulder,
		sprite_left_arm_weapon, sprite_right_arm_weapon,
		sprite_left_shoulder_weapon, sprite_right_shoulder_weapon]

func setup(p: Node) -> void:
	player = p
	_is_legs = player.build.chassis.is_legs if player.build.chassis else false
	_update_chassis_visibility()
	_connect_signals()
	_refresh_all()

func _process(_delta: float) -> void:
	if not player:
		return

	# Whole display mirrors mech world rotation
	rotation = player.rotation

	# Shoulders
	node_left_shoulder.rotation = player.get_node("LeftShoulder").rotation
	node_right_shoulder.rotation = player.get_node("RightShoulder").rotation

	# Arm weapons
	node_left_arm.rotation = player.get_node("ArmWeaponLeft").global_rotation - player.rotation
	node_right_arm.rotation = player.get_node("ArmWeaponRight").global_rotation - player.rotation + PI
	
	node_head.rotation = player.get_node("Head").global_rotation - player.rotation

	if player.build.has("left_shoulder_weapon") and player.build.left_shoulder_weapon:
		node_left_shoulder_weapon.rotation = \
			player.get_node("ShoulderWeaponLeft").global_rotation - player.rotation
	if player.build.has("right_shoulder_weapon") and player.build.right_shoulder_weapon:
		node_right_shoulder_weapon.rotation = \
			player.get_node("ShoulderWeaponRight").global_rotation - player.rotation + PI
	if _is_legs:
		node_chassis_left.rotation = player.get_node("Chassis/Left").global_rotation - player.rotation
		node_chassis_right.rotation = player.get_node("Chassis/Right").global_rotation - player.rotation
	else:
		node_chassis_single.rotation = player.get_node("Chassis/Single").global_rotation - player.rotation

	
func _connect_signals() -> void:
	player.component_damaged.connect(_on_component_damaged)
	player.component_destroyed_alert.connect(_on_component_destroyed)

func _on_component_damaged(part_name: String, _component_name: String, _hp: int, _max_hp: int) -> void:
	_refresh_part(part_name)

func _on_component_destroyed(part_name: String, _component_name: String) -> void:
	_refresh_part(part_name)


# Display state for a part: -1 = gone (all components destroyed), 0-3 =
# dead / critical / okay / full. Static so the debrief can read a mecha's
# damage without a display (part_state).
func _get_part_state(part_name: String) -> int:
	return part_state(player.components, part_name)


static func part_state(components: Dictionary, part_name: String) -> int:
	if not components.has(part_name):
		return 3

	var part_comps: Dictionary = components[part_name]
	var total := 0
	var destroyed := 0
	var current_hp := 0
	var max_hp := 0

	for comp in part_comps.values():
		total += 1
		current_hp += comp.hp
		max_hp += comp.max_hp
		if comp.disabled:
			destroyed += 1

	if total > 0 and destroyed == total:
		return -1

	if destroyed * 2 > total:
		return 0

	# HP ratio baseline
	var ratio := float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	var ratio_state: int
	if ratio > 0.75:
		ratio_state = 3
	elif ratio > 0.50:
		ratio_state = 2
	elif ratio > 0.25:
		ratio_state = 1
	else:
		ratio_state = 0

	# At least one destroyed → cap at _1
	if destroyed >= 1:
		return min(ratio_state, 1)

	return ratio_state

# Returns weapon display state: -1 = invisible, 0-2 = sprite index
func _get_weapon_state(_part_name: String, _feed_component: String) -> int:
	# TODO: Weapon component damage not yet implemented.
	# When weapon feeds are added as components, replace this with:
	#   if not player.components.has(part_name): return 0
	#   if not player.components[part_name].has(feed_component): return 0
	#   var comp = player.components[part_name][feed_component]
	#   if comp.disabled: return -1
	#   if comp.hp >= 2: return 0   (ok)
	#   if comp.hp == 1: return 1   (damaged)
	#   return 2                    (heavily damaged / hp 0 shouldn't occur, disabled catches it)
	return 0  

# Part state -1..3 straight onto the outline (-1 hides it).
func _apply_part_state(part: OutlinePart, state: int) -> void:
	part.state = clampi(state, -1, 3)

# Weapon state: -1 gone, 0 ok, 1 damaged, 2 heavily damaged. Weapons use the
# part styles: ok = full, damaged = okay, heavily damaged = critical.
func _apply_weapon_state(part: OutlinePart, state: int) -> void:
	part.state = -1 if state == -1 else [3, 2, 1][clampi(state, 0, 2)]
		
func _update_chassis_visibility() -> void:
	node_chassis_left.visible = _is_legs
	node_chassis_right.visible = _is_legs
	node_chassis_single.visible = not _is_legs

func _refresh_part(part_name: String) -> void:
	match part_name:
		"core":
			_apply_part_state(sprite_core, _get_part_state("core"))
			_apply_weapon_state(sprite_left_shoulder_weapon,
				_get_weapon_state("core", "left_shoulder_weapon_feed"))
			_apply_weapon_state(sprite_right_shoulder_weapon,
				_get_weapon_state("core", "right_shoulder_weapon_feed"))
		"head":
			_apply_part_state(sprite_head, _get_part_state("head"))
		"left_shoulder":
			_apply_part_state(sprite_left_shoulder, _get_part_state("left_shoulder"))
			_apply_weapon_state(sprite_left_arm_weapon,
				_get_weapon_state("left_shoulder", "weapon_feed"))
		"right_shoulder":
			_apply_part_state(sprite_right_shoulder, _get_part_state("right_shoulder"))
			_apply_weapon_state(sprite_right_arm_weapon,
				_get_weapon_state("right_shoulder", "weapon_feed"))
		"chassis":
			if _is_legs:
				var state := _get_part_state("chassis")
				_apply_part_state(sprite_chassis_left, state)
				_apply_part_state(sprite_chassis_right, state)
			else:
				_apply_part_state(sprite_chassis_single, _get_part_state("chassis"))

func _refresh_all() -> void:
	_refresh_part("core")
	_refresh_part("head")
	_refresh_part("left_shoulder")
	_refresh_part("right_shoulder")
	_refresh_part("chassis")


# ---- for the HUD gauges and weapon list ----

const PART_LABELS := {"core": "CORE", "head": "HEAD", "left_shoulder": "L SHD",
	"right_shoulder": "R SHD", "chassis": "LEGS"}
const STATE_WORDS := {1: "CRIT", 0: "DEAD", -1: "LOST"}

## Parts in a bad way, worst first: "L SHD LOST · HEAD CRIT". "" when none.
func get_damage_summary() -> String:
	if not player:
		return ""
	var bad := []
	for part in PART_LABELS:
		var state := _get_part_state(part)
		if state <= 1:
			bad.append([state, "%s %s" % [PART_LABELS[part], STATE_WORDS[state]]])
	bad.sort_custom(func(a, b): return a[0] < b[0])
	return " · ".join(bad.map(func(entry): return entry[1]))


## Whether the weapon in this build slot is shown as gone.
func is_weapon_lost(slot: String) -> bool:
	match slot:
		"arm_weapon_left": return sprite_left_arm_weapon.state == -1
		"arm_weapon_right": return sprite_right_arm_weapon.state == -1
		"shoulder_weapon_left": return sprite_left_shoulder_weapon.state == -1
		"shoulder_weapon_right": return sprite_right_shoulder_weapon.state == -1
	return false
