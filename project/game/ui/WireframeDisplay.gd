extends Node2D
class_name WireframeDisplay

# Assign in Inspector. Part arrays indexed [0=dead, 1=critical, 2=okay, 3=full]
# Right shoulder and right chassis leg reuse left-side arrays with flip_h
@export var core_sprites: Array[Texture2D]
@export var head_sprites: Array[Texture2D]
@export var left_shoulder_sprites: Array[Texture2D]
@export var chassis_left_sprites: Array[Texture2D]
@export var chassis_single_sprites: Array[Texture2D]
@export var weapon_sprites: Array[Texture2D]  # [ok, damaged, heavily damaged]


# Static parts — no independent rotation, sit directly on display root
@onready var sprite_core: Sprite2D = $WFCore
@onready var node_head: Node2D = $WFNodeHead
@onready var sprite_head: Sprite2D = $WFNodeHead/WFHead
@onready var node_chassis_single: Node2D = $WFNodeChassisSingle
@onready var sprite_chassis_single: Sprite2D = $WFNodeChassisSingle/WFChassisSingle

# Chassis legs — wrapper Node2D positioned at hip anchor, sprite offset inside
@onready var node_chassis_left: Node2D = $WFNodeChassisLeft
@onready var sprite_chassis_left: Sprite2D = $WFNodeChassisLeft/WFChassisLeft
@onready var node_chassis_right: Node2D = $WFNodeChassisRight
@onready var sprite_chassis_right: Sprite2D = $WFNodeChassisRight/WFChassisRight

# Shoulders — rotate independently (cursor-driven, small limit)
@onready var node_left_shoulder: Node2D = $WFNodeLeftShoulder
@onready var sprite_left_shoulder: Sprite2D = $WFNodeLeftShoulder/WFLeftShoulder
@onready var node_right_shoulder: Node2D = $WFNodeRightShoulder
@onready var sprite_right_shoulder: Sprite2D = $WFNodeRightShoulder/WFRightShoulder

# Arm weapons — rotate independently from shoulders
@onready var node_left_arm: Node2D = $WFNodeLeftArm
@onready var sprite_left_arm_weapon: Sprite2D = $WFNodeLeftArm/WFLeftArmWeapon
@onready var node_right_arm: Node2D = $WFNodeRightArm
@onready var sprite_right_arm_weapon: Sprite2D = $WFNodeRightArm/WFRightArmWeapon

# Shoulder weapons — rotate independently, not related to shoulder nodes
@onready var node_left_shoulder_weapon: Node2D = $WFNodeLeftShoulderWeapon
@onready var sprite_left_shoulder_weapon: Sprite2D = $WFNodeLeftShoulderWeapon/WFLeftShoulderWeapon
@onready var node_right_shoulder_weapon: Node2D = $WFNodeRightShoulderWeapon
@onready var sprite_right_shoulder_weapon: Sprite2D = $WFNodeRightShoulderWeapon/WFRightShoulderWeapon

var player: Node
var _is_legs: bool = false


func _ready() -> void:
	# Right-side sprites mirror left-side assets
	sprite_right_shoulder.flip_h = true
	sprite_chassis_right.flip_h = true

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
	
	print(player.get_node("LeftShoulder").global_rotation, " vs mech: ", player.rotation)
	
func _connect_signals() -> void:
	player.component_damaged.connect(_on_component_damaged)
	player.component_destroyed_alert.connect(_on_component_destroyed)

func _on_component_damaged(part_name: String, _component_name: String, _hp: int, _max_hp: int) -> void:
	_refresh_part(part_name)

func _on_component_destroyed(part_name: String, _component_name: String) -> void:
	_refresh_part(part_name)


# Returns display state for a part's structural sprite:
# -1 = invisible (all components destroyed), 0-3 = sprite index
func _get_part_state(part_name: String) -> int:
	if not player.components.has(part_name):
		return 3

	var part_comps: Dictionary = player.components[part_name]
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

	if destroyed > total / 2:
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

func _apply_part_state(sprite: Sprite2D, textures: Array, state: int) -> void:
	if state == -1:
		sprite.visible = false
		return
	sprite.visible = true
	if textures.size() >= 4:
		sprite.texture = textures[clamp(state, 0, 3)]

func _apply_weapon_state(sprite: Sprite2D, state: int) -> void:
	if state == -1:
		sprite.visible = false
		return
	sprite.visible = true
	if weapon_sprites.size() >= 3:
		sprite.texture = weapon_sprites[clamp(state, 0, 2)]
		
func _update_chassis_visibility() -> void:
	node_chassis_left.visible = _is_legs
	node_chassis_right.visible = _is_legs
	node_chassis_single.visible = not _is_legs

func _refresh_part(part_name: String) -> void:
	match part_name:
		"core":
			_apply_part_state(sprite_core, core_sprites, _get_part_state("core"))
			_apply_weapon_state(sprite_left_shoulder_weapon,
				_get_weapon_state("core", "left_shoulder_weapon_feed"))
			_apply_weapon_state(sprite_right_shoulder_weapon,
				_get_weapon_state("core", "right_shoulder_weapon_feed"))
		"head":
			_apply_part_state(sprite_head, head_sprites, _get_part_state("head"))
		"left_shoulder":
			_apply_part_state(sprite_left_shoulder, left_shoulder_sprites,
				_get_part_state("left_shoulder"))
			_apply_weapon_state(sprite_left_arm_weapon,
				_get_weapon_state("left_shoulder", "weapon_feed"))
		"right_shoulder":
			_apply_part_state(sprite_right_shoulder, left_shoulder_sprites,
				_get_part_state("right_shoulder"))
			_apply_weapon_state(sprite_right_arm_weapon,
				_get_weapon_state("right_shoulder", "weapon_feed"))
		"chassis":
			if _is_legs:
				var state := _get_part_state("chassis")
				_apply_part_state(sprite_chassis_left, chassis_left_sprites, state)
				_apply_part_state(sprite_chassis_right, chassis_left_sprites, state)
			else:
				_apply_part_state(sprite_chassis_single, chassis_single_sprites,
					_get_part_state("chassis"))

func _refresh_all() -> void:
	_refresh_part("core")
	_refresh_part("head")
	_refresh_part("left_shoulder")
	_refresh_part("right_shoulder")
	_refresh_part("chassis")
