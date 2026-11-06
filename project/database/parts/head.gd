extends Node2D

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
# Recycling and the Fabricator: the tech tier and what one of these breaks
# down into (or takes to build), material id (see Materials) -> amount.
@export var tech_tier: item_data.TechTier = item_data.TechTier.LOW
@export var composition: Dictionary[String, int] = {}
## False keeps the part out of the store and out of the Compare window's
## STORE list, for secret parts.
@export var store_listed := true
@export var description : String
@export var image : Texture2D
@export var heatmap : Resource
@export var rotation_acc := 8
@export var rotation_range := 45.0
@export var accuracy_modifier := -1.0
## The sight circle's radius and the camera's pan limit, in metres
## (MapSenses.PX_PER_METRE px each): a mecha sees nothing past it
## (Mecha.sight_radius). Its IR illuminator reaches as far
## (Illumination.reach_of).
@export var visual_range := 150
## The IR sensor (IRSensing), in °C. A body at least ir_sensitivity hot is
## picked up as an UNKNOWN track that follows it live; at least
## ir_identification hot, it is seen as if lit. Placeholders: a working
## mecha's hull is about 60 °C, and it starts to burn above 190 °C
## (Mecha.OVERHEAT_DAMAGE_TEMP over ambient).
@export var ir_sensitivity := 60.0
@export var ir_identification := 200.0
## How wide (degrees) its IR illuminator's cone is, edge to edge
## (Illumination.shape_light). What the cone falls on is lit, and the mecha
## sees it out to its sight circle, the player and an NPC alike. Placeholder.
@export_range(2.0, 360.0, 0.5) var illuminator_angle := 30.0
@export var health := 1500
@export var weight := 1.0
## How big it looks to radar for its size (RadarCrossSection): 0.2 a
## stealth part, 1.0 an ordinary one, 3.0 flat, bulky armour. Its shape and
## material as one number. Every head has the same outline (Mecha.tscn's
## HeadCollision), so only this tells heads apart. Placeholder.
@export var rcs_factor := 1.0
@export var tags :Array[String] = ["head"]
@export var item_size := [3,3]
@export var front_armor := 1
@export var side_armor := 1
@export var rear_armor := 1
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

var part_id

func get_image():
	return $Main.texture


func get_sub():
	return $Sub.texture


func get_glow():
	return $Glow.texture
