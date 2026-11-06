extends Node


enum SIDE {LEFT, RIGHT, SINGLE}

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
## The shoulders' share of the shield's strength, counted once for both
## (Mecha.update_shield_strength averages it with the core's and the
## generator's).
@export var shield_strength := 2.0
@export var stability := 1.0
@export var arms_accuracy_modifier := 1.0
@export var melee_modifier := 0.8
@export var weight := 20.0
## How big it looks to radar for its size (RadarCrossSection): 0.2 a
## stealth part, 1.0 an ordinary one, 3.0 flat, bulky armour. Its shape and
## material as one number. Placeholder.
@export var rcs_factor := 1.0
@export var rotation_acc := 5
@export var rotation_range := 10.0
@export var tags :Array[String] = ["shoulder"]
@export var item_size := [4,4]
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
	# Each shoulder's shield_projector is one of its default components
	# (Mecha.get_default_components); an entry named shield_projector here
	# replaces it.
]

var part_id

func get_image(side):
	if side == SIDE.LEFT:
		return $ShoulderLeft.texture
	elif side == SIDE.RIGHT:
		return $ShoulderRight.texture
	else:
		push_error("Not a valid side:" + str(side))

func get_collision(side):
	if side == SIDE.LEFT:
		return $ShoulderLeft/Collision.polygon
	elif side == SIDE.RIGHT:
		return $ShoulderRight/Collision.polygon
	else: 
		push_error("Not a valid side:" + str(side))
