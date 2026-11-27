class_name PaperPilot
extends RefCounted

# Stands in Local (LocalPilots) for an NPC whose mecha is off the map: a
# dormant roaming camp's pilot, or an encounter's (CampField). It carries
# what Local reads off a pilot (callsign, squad tag, Anonymous) and where
# it is, so the roster lists it as on the map. When its mecha is put on the
# map it hands its place over (LocalPilots.replace), and takes it back when
# the mecha goes off again.

var callsign := ""
var mecha_name := ""
var squad_tag := ""
var is_anonymous := false
var is_dead := false
var global_position := Vector2.ZERO


static func from_design(design: Dictionary, name_: String) -> PaperPilot:
	var pilot := PaperPilot.new()
	pilot.mecha_name = name_
	pilot.squad_tag = str(design.get("squad_tag", ""))
	pilot.is_anonymous = design.get("anonymous", false) == true
	pilot.callsign = str(design.get("callsign", ""))
	return pilot


static func from_mecha(mecha) -> PaperPilot:
	var pilot := PaperPilot.new()
	pilot.callsign = str(mecha.callsign)
	pilot.mecha_name = str(mecha.mecha_name)
	pilot.squad_tag = str(mecha.squad_tag)
	pilot.is_anonymous = mecha.is_anonymous
	pilot.global_position = mecha.global_position
	return pilot
