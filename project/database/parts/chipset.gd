extends Resource

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
# Recycling and the Fabricator: the tech tier and what one of these breaks
# down into (or takes to build), material id (see Materials) -> amount.
@export var tech_tier: item_data.TechTier = item_data.TechTier.LOW
@export var composition: Dictionary[String, int] = {}
@export var description : String
@export var image : Texture2D
@export var can_lock := false
@export var accuracy_modifier := 1.0
@export var lock_on_speed := .2
## How long (s) a made lock lasts (Mecha's lock rules).
@export var lock_on_duration := 5
@export var lock_on_reticle_size := 15 #Radius of the reticle
@export var lock_on_strength := 5
## Whether the player's radar ring shows (PlayerRadar: tracks only).
@export var has_radar := true
@export var loot_search_time := 1.0
@export var weight := 1.0
@export var tags :Array[String] = ["chipset"]
@export var item_size := [2,2]
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
	return image
