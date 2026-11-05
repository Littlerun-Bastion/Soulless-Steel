class_name IRSensing
extends RefCounted

## A head's IR sensor (head.ir_sensitivity and head.ir_identification, both
## in °C): what an observer picks up by heat alone.
##   sensitivity     a body at least this hot is sensed: a live track on it
##                   that follows it, though it isn't seen. The player gets
##                   an UNKNOWN contact (Player's view, HudContacts); an NPC
##                   knows where it is, as if it heard it, but exactly and
##                   live (Enemy._look_at, NPCKnowledge.sensed_heat)
##   identification  a body at least this hot is seen, as if an illuminator
##                   lit it (Illumination.seen_lit)
## The player senses within its view's range, an NPC within its sight range.
## Heat reaches the sensor as light does: from anywhere, walls between or
## not, but not from inside another building (roofs hide the inside of a
## building) or through thick smoke. Range is the observer's to check.
##
## A body's temperature (temperature_of) is absolute, in °C: a mecha's hull
## (Mecha.get_external_temp_absolute), an Entity's body_temp, anything else
## from its heat signature (0 at ambient, 1 at SIGNATURE_SPAN above it, as
## Mecha.get_thermal_signature counts it). A mecha with no head, or whose
## head came off, senses nothing.

const SIGNATURE_SPAN := 150.0
## An IR track's contact source (ContactStore), and the kind it's labelled:
## what can't be made out.
const SOURCE := "ir"
const KIND := "unknown"
## What the sensor makes of a body (level).
const NONE := 0
const SENSED := 1
const IDENTIFIED := 2


static func temperature_of(body: Object) -> float:
	if body == null or not is_instance_valid(body):
		return Mecha.AMBIENT_TEMP
	if body.has_method("get_external_temp_absolute"):
		return body.get_external_temp_absolute()
	if body.has_method("get_body_temp"):
		return body.get_body_temp()
	if body.has_method("get_thermal_signature"):
		return Mecha.AMBIENT_TEMP + float(body.get_thermal_signature()) * SIGNATURE_SPAN
	return Mecha.AMBIENT_TEMP


## The head an observer senses with; null for none (or one that came off).
static func head_of(observer: Object):
	if observer == null or not is_instance_valid(observer):
		return null
	if observer.has_method("is_part_lost") and observer.is_part_lost("head"):
		return null
	var build = observer.get("build")
	if not build is Dictionary:
		return null
	return build.get("head") if build.get("head") else null


## The observer's IR sensitivity (°C), or INF with no head.
static func sensitivity_of(observer: Object) -> float:
	var head = head_of(observer)
	return float(head.ir_sensitivity) if head != null and "ir_sensitivity" in head else INF


## The observer's IR identification (°C), or INF with no head.
static func identification_of(observer: Object) -> float:
	var head = head_of(observer)
	return float(head.ir_identification) if head != null and "ir_identification" in head else INF


## Whether heat from `body` gets to `observer`: the same building (or both
## outside), and no thick smoke on it or between.
static func reaches(observer: Node2D, body: Node2D) -> bool:
	if MapSenses.building_key_of(observer) != MapSenses.building_key_of(body):
		return false
	return not (MapSenses.in_smoke(body.global_position) or MapSenses.smoke_between(observer.global_position, body.global_position))


## Whether `observer` senses `body` by its heat (a track; see above).
static func senses(observer: Node2D, body: Node2D) -> bool:
	return level(observer, body) >= SENSED


## Whether `observer` makes `body` out by its heat (seen; see above).
static func identifies(observer: Node2D, body: Node2D) -> bool:
	return level(observer, body) == IDENTIFIED


## What `observer`'s IR sensor makes of `body`: NONE, SENSED or IDENTIFIED.
## The temperature first; the building and smoke checks only for a body hot
## enough to matter.
static func level(observer: Node2D, body: Node2D) -> int:
	var heat := temperature_of(body)
	var head = head_of(observer)
	if head == null or not "ir_sensitivity" in head or heat < float(head.ir_sensitivity):
		return NONE
	if not reaches(observer, body):
		return NONE
	return IDENTIFIED if heat >= float(head.ir_identification) else SENSED
