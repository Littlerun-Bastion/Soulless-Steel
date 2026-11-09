class_name CombatRecorder
extends Node

## The player's side of the combat log: what happens to its mecha, written to
## the LOG app's COMBAT tab (MechLog, source CBT) as it happens, and the last
## MEMORY seconds of it kept for the frame loss report. Expedition attaches one
## to the player (attach); it is freed with the mecha.
##
## Only the moments that teach something get a line:
##   "Hit by Vex (Autocannon) · core"   an attacker's first hit, or its first
##                                      after NEW_ATTACKER_GAP s without one
##   "Core radiator destroyed · heat dispersion halved"
##                                      a component destroyed, with what it
##                                      did ("destroyed by heat" when an
##                                      overheat tick did it)
##   "Cockpit breached"                 the critical component (critical line;
##                                      "by heat" when an overheat tick did it)
##   "Head lost"                        a part came off; its components go
##                                      with it, without lines of their own
##   "Overheating"                      overheating starts, at most once every
##                                      OVERHEAT_GAP s
##   "Core shell broken · emergency Flag raised", "Emergency Flag raised",
##   "Flag raised"                      the Flag going up (critical unless
##                                      raised by choice)
## Other hits, amounts and armour rolls aren't written: the log stays short.
##
## A hit is anything that damages a component (rounds, beams, blasts, bites:
## the attacker is in Mecha.last_damage_source by then) or is reported through
## Mecha.register_hit (took_damage, not a status's). Heat ticks
## (Mecha.damage_cause "heat") aren't hits. Hits from the mecha itself (its
## own blast) aren't written.

const NODE_NAME := "CombatRecorder"
const SOURCE := "CBT"
## Seconds of hits and heat damage kept (hits, heat_damage).
const MEMORY := 60.0
## An attacker's hit gets a line again after this many seconds without one.
const NEW_ATTACKER_GAP := 30.0
## Seconds between "Overheating" lines.
const OVERHEAT_GAP := 20.0
const PART_NAMES := {
	"core": "Core", "head": "Head", "chassis": "Chassis",
	"left_shoulder": "Left shoulder", "right_shoulder": "Right shoulder",
	"arm_weapon_left": "Left arm weapon", "arm_weapon_right": "Right arm weapon",
	"shoulder_weapon_left": "Left shoulder weapon", "shoulder_weapon_right": "Right shoulder weapon",
}

var mecha: Mecha = null
## Seconds of game time since it was attached (paused while the game is).
var now := 0.0
## The hits of the last MEMORY s, oldest first: {"time", "key" (who, for
## telling attackers apart), "name", "weapon" ("" if not a known weapon),
## "part" ("" if not known), "facing" (front / side / rear, or ""), "lit"
## (its illuminator was on), "shielding", "overheating"}.
var hits: Array = []
## When a heat tick damaged a component, in the last MEMORY s.
var heat_damage: Array = []
## How the critical component (the cockpit) went: "hit", "heat", or "" while
## it holds.
var breach := ""

var _last_hit_by := {}  # attacker key -> time of its last hit
var _last_overheat_line := -INF
var _overheating := false
var _shell_broken := false  # the core shell just broke; the Flag line says so


## Attaches a recorder to `target` (the player's mecha) and returns it.
static func attach(target: Mecha) -> CombatRecorder:
	var recorder := CombatRecorder.new()
	recorder.name = NODE_NAME
	recorder.mecha = target
	target.add_child(recorder)
	return recorder


## The recorder on `target`, or null.
static func of(target: Node) -> CombatRecorder:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NODE_NAME) as CombatRecorder


func _ready() -> void:
	mecha.component_damaged.connect(_on_component_damaged)
	mecha.component_destroyed_alert.connect(_on_component_destroyed)
	mecha.took_damage.connect(_on_took_damage)
	mecha.part_lost.connect(_on_part_lost)
	mecha.flag_raised.connect(_on_flag_raised)


func _physics_process(delta: float) -> void:
	now += delta
	var hot: bool = mecha.has_status("overheating")
	if hot and not _overheating and now - _last_overheat_line >= OVERHEAT_GAP:
		_last_overheat_line = now
		_write("Overheating")
	_overheating = hot


## The hits within the last `seconds`, oldest first.
func recent_hits(seconds: float = MEMORY) -> Array:
	return hits.filter(func(hit): return now - hit.time <= seconds)


# ---- Hits ----

func _on_component_damaged(part_name: String, _component: String, _hp: int, _max_hp: int) -> void:
	if mecha.damage_cause == "heat":
		heat_damage.append(now)
		_forget()
		return
	_note_hit(part_name)


func _on_took_damage(_mecha, is_status) -> void:
	if not is_status:
		_note_hit("")


func _note_hit(part_name: String) -> void:
	var source = mecha.last_damage_source
	var body = null
	if source is Dictionary:
		body = source.get("body")
	elif source is Node:
		body = source
	if is_instance_valid(body) and body == mecha:
		return
	var name := attacker_name(source)
	var key: String = str(body.get_instance_id()) if is_instance_valid(body) else "name:" + name
	var hit := {
		"time": now, "key": key, "name": name,
		"weapon": weapon_name(mecha.last_damage_weapon), "part": part_name,
		"facing": _facing(source, body),
		"lit": mecha.illuminator_on == true, "shielding": mecha.is_shielding == true,
		"overheating": mecha.has_status("overheating"),
	}
	hits.append(hit)
	_forget()
	var last: float = _last_hit_by.get(key, -INF)
	_last_hit_by[key] = now
	if now - last < NEW_ATTACKER_GAP:
		return
	var text := "Hit by " + name
	if hit.weapon != "":
		text += " (%s)" % hit.weapon
	if part_name != "":
		text += " · " + PART_NAMES.get(part_name, part_name).to_lower()
	_write(text)


## Who `source` (a Mecha.last_damage_source) is, as the log names them: a
## pilot as others see it (LocalPilots.name_of), a creature by its species, a
## sourceless swarm by the name it gave ("Tick Swarm"), else Unknown.
static func attacker_name(source) -> String:
	var body = null
	if source is Dictionary:
		body = source.get("body")
		# No body at all (not one that is gone): the name is all there is.
		if typeof(body) == TYPE_NIL and str(source.get("name", "")) not in ["", "Player"]:
			return str(source.name)
	elif source is Node:
		body = source
	if is_instance_valid(body):
		return LocalPilots.name_of(body)
	return KillRecord.UNKNOWN


## A weapon's name from its part id, or "" if it isn't a weapon part (a
## creature's attack carries its species instead).
static func weapon_name(id) -> String:
	if id == null or str(id) == "":
		return ""
	for type in KillRecord.WEAPON_TYPES:
		var parts: Dictionary = PartManager.get_parts(type)
		if parts.has(str(id)):
			return KillRecord.weapon_label(id)
	return ""


func _facing(source, body) -> String:
	var from = source.get("from") if source is Dictionary else null
	if not from is Vector2 and is_instance_valid(body) and body is Node2D:
		from = body.global_position
	return mecha.get_global_facing_from_angle(from) if from is Vector2 else ""


# Drops what is older than MEMORY.
func _forget() -> void:
	hits = hits.filter(func(hit): return now - hit.time <= MEMORY)
	heat_damage = heat_damage.filter(func(time): return now - time <= MEMORY)
	for key in _last_hit_by.keys():
		if now - _last_hit_by[key] >= NEW_ATTACKER_GAP:
			_last_hit_by.erase(key)


# ---- What the damage did ----

func _on_component_destroyed(part_name: String, component: String) -> void:
	# A part coming off takes its components with it: one "lost" line.
	if mecha.is_part_lost(part_name):
		return
	var tags: Array = mecha.components[part_name][component].get("tags", [])
	if "weapon" in tags and mecha.is_part_lost(_arm_slot(part_name)):
		return
	if "critical" in tags:
		breach = "heat" if mecha.damage_cause == "heat" else "hit"
		_write("%s breached%s" % [component.replace("_", " ").capitalize(), " by heat" if breach == "heat" else ""], true)
		return
	if component == "core_shell":
		# The emergency Flag follows at once (Mecha.enter_flagged_state) and
		# its line says this too; if the mecha is already exposed, it won't.
		if mecha.is_exposed or mecha.is_dead:
			_write("Core shell broken", true)
		else:
			_shell_broken = true
		return
	var text := component_label(part_name, component) + " destroyed"
	if mecha.damage_cause == "heat":
		text += " by heat"
	var effect := _effect(part_name, component, tags)
	if effect != "":
		text += " · " + effect
	_write(text)


## "Core radiator", "Left shoulder weapon feed", "Head shell".
static func component_label(part_name: String, component: String) -> String:
	var part: String = PART_NAMES.get(part_name, part_name.capitalize())
	if component.ends_with("_shell"):
		return part + " shell"
	return part + " " + component.replace("_", " ")


func _effect(part_name: String, component: String, tags: Array) -> String:
	if "mobility" in tags:
		return "mobility reduced"
	if component == Mecha.SHIELD_PROJECTOR:
		return "shield weakened"
	match component:
		"weapon_feed":
			return "%s arm weapon offline" % ("left" if part_name == "left_shoulder" else "right")
		"radiator":
			return "heat dispersion halved"
		"optics":
			return "sensors reduced"
		"backup_optics":
			var optics = mecha.components.get("head", {}).get("optics")
			return "nearly blind" if optics != null and optics.disabled else ""
		"generator":
			return "shield regeneration offline"
	return ""


func _arm_slot(part_name: String) -> String:
	return "arm_weapon_left" if part_name == "left_shoulder" else "arm_weapon_right"


func _on_part_lost(part_name: String) -> void:
	_write("%s lost" % PART_NAMES.get(part_name, part_name.capitalize()))


func _on_flag_raised(_mecha, voluntary: bool, _pressured_by) -> void:
	if voluntary:
		_write("Flag raised")
		return
	_write("Core shell broken · emergency Flag raised" if _shell_broken else "Emergency Flag raised", true)
	_shell_broken = false


func _write(text: String, critical := false) -> void:
	MechLog.write(SOURCE, text, MechLog.Kind.COMBAT, critical)
