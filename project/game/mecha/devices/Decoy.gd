class_name Decoy
extends Device

## A decoy (internal bay part, function "decoy"): a device that gives off a
## mecha's heat for its lifetime. Sweeps, wards and drones count it as a
## mecha ("mech"); NPC sight sees it as a mecha it can target
## (Enemy.update_senses) and may shoot it, which destroys it like any device.
## Its owner's own sensors leave it out.
##
## To pass for a mecha in NPC code it carries the fields a target is read for
## (the same duck-typed set an Entity has, see Entity.gd, plus the few a
## mecha target adds): is_dead, mecha_name, callsign, is_anonymous, velocity,
## last_damage_source, armor, components, internal_temp, external_temp,
## overheat_temp, ecm, ecm_frequency, sensor_reduction, is_exposed,
## personality, hp, max_hp, has_any_status(), get_thermal_signature(),
## estimate_threat_level(), is_player(). In group "decoy".

var is_dead := false
var mecha_name := "Decoy"
var callsign := ""
var is_anonymous := true
var velocity := Vector2.ZERO
var last_damage_source = null
var armor := {}
var components := {}
var internal_temp := 0.0
var external_temp := 0.0
var overheat_temp := 100.0
var ecm := 0.0
var ecm_frequency := 0.0
var sensor_reduction := 0.0
var is_exposed := false
var flag_up := false
var personality = null


func is_flagged() -> bool:
	return false
var max_hp := 2.0

var _heat := 0.6
var _threat := 0.5


func setup(owner_ref, part, direction := Vector2.ZERO) -> void:
	super(owner_ref, part, direction)
	max_hp = hp
	_heat = part.decoy_heat
	# It passes for its owner's frame: NPCs weigh it as they would the owner,
	# and take it for the owner's kind of pilot (first-sight hostility).
	if is_instance_valid(owner_ref) and owner_ref.has_method("estimate_threat_level"):
		_threat = owner_ref.estimate_threat_level()
	if is_instance_valid(owner_ref) and owner_ref.get("personality") is Personality:
		personality = owner_ref.personality


func _ready() -> void:
	super()
	add_to_group("decoy")


func get_thermal_signature() -> float:
	return _heat


func estimate_threat_level() -> float:
	return _threat


func has_any_status() -> bool:
	return false


func is_player() -> bool:
	return false


func destroy() -> void:
	is_dead = true
	super()


func expire() -> void:
	is_dead = true
	super()
