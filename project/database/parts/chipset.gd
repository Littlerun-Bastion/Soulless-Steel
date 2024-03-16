extends Resource

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var price := 0.0
@export var description : String
@export var image : Texture2D
@export var can_lock := false
@export var accuracy_modifier := 1.0
@export var lock_on_speed := .2
@export var lock_on_duration := 5
@export var lock_on_distance := 5000
@export var lock_on_reticle_size := 15 #Radius of the reticle
@export var lock_on_strength := 5
@export var ECM := 10
@export var ECM_frequency := .3
@export var has_radar := true
@export var radar_refresh_rate := 1.0
@export var loot_search_time := 1.0
@export var radar_range := 5000.0
@export var weight := 1.0
@export var tags :Array[String] = ["chipset"]
@export var item_size := [2,2]

var part_id

func get_image():
	return image
