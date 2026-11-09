extends Node

@export_category("Main Attributes")
@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var tags :Array[String] = ["arm_weapon"]
@export var price := 0.0
@export var weight := 1.0
@export var description : String
@export var image : Texture2D
@export var item_size := [3,2]
# Recycling in the Hangar, like salvage (item_data.composition): what one of
# these breaks down into, material id (see Materials) -> amount.
@export var tech_tier: item_data.TechTier = item_data.TechTier.LOW
@export var composition: Dictionary[String, int] = {}
## False keeps the part out of the store and out of the Compare window's
## STORE list, for secret parts.
@export var store_listed := true
@export var ai_engage_range := 2000
@export var is_indirect_fire := false
@export var additional_components: Array[Dictionary] = [
	#{ EXAMPLE OF ADDITIONAL COMPONENTS (do not delete)
	#	"name": "core_shell",   OVERRIDE default
	#	"hp": 3,               Heavier armor than default (3)
	#	"max_hp": 3,
	#	"tags": ["internal"],
	#	"weight": 3.0          Bigger, easier to hit
	#},
	#{
	#	"name": "shield_emitter",   NEW component
	#	"hp": 2,
	#	"max_hp": 2,
	#	"tags": ["internal", "shield"],
	#	"weight": 1.0
	#}
]

@export_category("Muzzle Flash")
@export var muzzle_flash : PackedScene
@export var muzzle_flash_size := 1.0
@export var muzzle_flash_speed := 1.0

@export_category("Rotation Parameters")
@export var rotation_acc := 5
@export var rotation_range := 10.0

@export_category("Projectile Parameters")
@export var projectile : PackedScene
@export var parallax_offset := 0.0
@export var number_projectiles := 1
@export var burst_ammo_cost := 1
@export var requires_lock := false
@export var uses_battery := false
@export var recoil_force := 0.0
@export var bloom_reset_time := 1.0
@export var fire_rate := .3
@export var burst_size := 1
@export var burst_fire_rate := 0.0
@export var auto_fire := true
@export var base_accuracy := 0.0
@export var accuracy_bloom := 0.0
@export var max_bloom_angle := 2.5
@export var bullet_spread := PI/4 #Relevant for multi-shot
@export var bullet_spread_delay := 0.0 #Relevant for multi-shot
@export var total_ammo := 270
@export var max_ammo := 270
@export var clip_size := 30
@export var reload_speed := 3.0
@export var muzzle_heat := 3.8
@export var ammo_cost := 10 #the monetary cost of the ammunition, not the ammo used when firing.
@export var eject_casings := false
@export var casing_size := 1.0
@export var show_idle_projectile := false
## Energy weapons (uses_battery): the battery's kWh a reload takes for each
## shot it puts in the clip, and the lowest generator WPOR it fires and
## reloads with (WeaponNode.is_underpowered).
@export var battery_drain := 1.00
@export var min_power_rating := 0.0
@export var impact_force := 0.0

@export_category("Sound Attributes")
@export var shoot_single_sfx := "test"
@export var shoot_loop_sfx := AudioStream
@export var spool_up_sfx := AudioStream
@export var spool_down_sfx := AudioStream
@export var sound_max_range := 20000
@export var sound_att := 1.00


@export_category("Beam Behaviours")
@export var beam_range := 0.0
@export var constant_beam := false
@export var beam_effect : Resource

@export_category("Melee Behaviours")
@export var is_melee := false
## A melee hit's damage pips and armour pen (Mecha.process_hitboxes).
## Placeholders.
@export var melee_damage := 1
@export var melee_pen := 1
@export var melee_knockback := 20

# Shoulder weapons with a designator work like skills: holding the fire button
# shows the designator, releasing fires a salvo at it (Mecha.fire_at_point).
# "none" keeps the plain firing path (Mecha.shoot). Fire type is
# is_indirect_fire: indirect rounds fly over walls and vehicles and land on
# the point. Ranges are measured from the mecha's centre, in px (20 px = 1 m).
# A "line" or "rect" designator is a skillshot that always reaches
# max_range: only its direction follows the aim. A "line_box" lands its rounds in a square of
# half-side scatter_radius at the end of its line.
@export_category("Designator")
@export_enum("none", "circle", "line", "line_box", "rect", "point") var designator: String = "none"
@export var min_range := 0.0
@export var max_range := 2000.0
## Radius (px) of the circle each round of a salvo lands in.
@export var scatter_radius := 0.0
## Rounds per salvo, and seconds between them.
@export var barrage_count := 1
@export var barrage_interval := 0.0
## Degrees either side of the mecha's facing the weapon can aim.
@export var gimbal := 5.0
## Width (px) of a "rect" designator: the laser beam's width.
@export var designator_width := 0.0
## Tapping the fire button (shorter than Player.TAP_TIME) fires the salvo at
## the mecha itself instead of the designator: the smoke launcher's screen.
@export var tap_self := false

var cur_stage = 0
var firing_timer = 0.0
var part_id
# Projectile values read once (_read_projectile) for get_aoe_info() and
# get_projectile_stat().
var _projectile_info := {}


func get_sub():
	return $Sub.texture


func get_image():
	return $Main.texture


func get_glow():
	return $Glow.texture


func get_num_shooting_pos():
	return $ShootingPosArray.get_children().size()


func get_shooting_pos(idx):
	assert($ShootingPosArray.get_child_count() >= idx + 1,"Not a valid shooting pos index: " + str(idx))
	return $ShootingPosArray.get_child(idx)


func get_attach_pos():
	return $AttachPos.position


func get_attack_animation():
	return $AttackAnimation.duplicate()


func get_stat(stat_name):
	var stat
	stat = get(stat_name)
	return stat


func has_designator() -> bool:
	return designator != "none"


# What NPC code needs to use this weapon (see AoE weapons.md, "For NPC code").
# The blast radius comes from the projectile scene (_read_projectile).
func get_aoe_info() -> Dictionary:
	_read_projectile()
	return {
		"fire_type": "indirect" if is_indirect_fire else "direct",
		"designator": designator,
		"min_range": min_range,
		"max_range": max_range,
		"scatter_radius": scatter_radius,
		"barrage_count": barrage_count,
		"barrage_interval": barrage_interval,
		"gimbal": gimbal,
		"width": designator_width,
		"blast_radius": _projectile_info.blast_radius,
		"projectile_speed": _projectile_info.muzzle_speed,
		"submunitions": _projectile_info.submunitions,
		"requires_lock": requires_lock,
	}


## A number off the projectile's root ("base_damage", "armor_pen"), or null
## when the weapon has no projectile or its projectile has no such field.
func get_projectile_stat(stat_name: String):
	_read_projectile()
	return _projectile_info.stats.get(stat_name)


# Reads the projectile scene's root once and caches what it needs:
# instantiate() never adds it to the tree and doesn't run _ready, so it has no
# side effects.
func _read_projectile() -> void:
	if not _projectile_info.is_empty():
		return
	_projectile_info = {"blast_radius": 0.0, "muzzle_speed": 0.0, "submunitions": 0, "stats": {}}
	if not projectile is PackedScene:
		return
	var inst: Node = projectile.instantiate()
	var radius = inst.get("payload_explosion_radius")
	var speed = inst.get("muzzle_speed")
	var subs = inst.get("payload_subprojectile_count")
	var has_subs: bool = inst.get("payload_subprojectile") != null
	for stat_name in ["base_damage", "armor_pen"]:
		var value = inst.get(stat_name)
		if value is int or value is float:
			_projectile_info.stats[stat_name] = value
	inst.free()
	if radius != null:
		_projectile_info.blast_radius = float(radius)
	if speed != null:
		_projectile_info.muzzle_speed = float(speed)
	if subs != null and has_subs:
		_projectile_info.submunitions = int(subs)

	
