extends Resource

@export var part_name: String
@export var manufacturer_name: String
@export var manufacturer_name_short: String
@export var tagline: String
@export var price := 0.0
# Recycling and the Fabricator: the tech tier and what one of these breaks
# down into (or takes to build), material id (see Materials) -> amount.
@export var tech_tier: item_data.TechTier = item_data.TechTier.LOW
@export var composition: Dictionary[String, int] = {}
## False keeps the part out of the store and out of the Compare window's
## STORE list, for secret parts.
@export var store_listed := true
@export var description: String
@export var image: Texture2D
@export var ambient_sfx := preload("res://assets/audio/sfx/generator_ambient/test.mp3")

## The shield (Mecha, SHIELDS): its pool (Shield Capacity, SC), its strength
## (Shield Strength, SS: an armour level, averaged with the core's and the
## shoulders'), the SC it regains a second while down, and how long (s) it
## regains nothing after SC reaches 0. Heat (kJ) a second while it is up.
@export var shield_capacity := 15.0
@export var shield_strength := 2.0
@export var shield_regen_rate := 1.0
@export var shield_break_cooldown := 3.0
@export var shield_project_heat := 165

@export var ventilation_ratio: float = 0.7        # 0-1, fraction kept internal
@export var cooling_power: float = 8.5           # kW/°C — internal cooling coefficient
@export var thermal_conductivity: float = 2.5     # kW/°C — external shedding coefficient
@export var external_thermal_capacity: float = 85.0  # kJ/°C — external layer mass

## The battery (kWh): the one reserve every energy weapon (weapon.uses_battery)
## reloads its clip from. Power output (kW) puts that many kWh a second back
## into it. The weapon power output rating (WPOR, 0 to 1) makes energy weapons
## fire, reload and hold more (Mecha.weapon_power_boost); some need a minimum
## (weapon.min_power_rating).
@export var battery_capacity := 250.0
@export var power_output := 20.0
@export var weapon_power_rating := 0.33

@export var weight := 10.0
@export var tags: Array[String] = ["generator"]
@export var item_size := [3, 3]
@export var additional_components: Array[Dictionary] = []

var part_id

func get_image():
	return image
