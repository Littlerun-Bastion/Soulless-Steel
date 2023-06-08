extends Resource

@export_category("Main Attributes")
@export var name := "Example"
@export var combat_behaviour := "default"
@export_range(0.0, 10.0, 0.1) var difficulty := 5.0

@export_category("Mecha Build")
@export var head : Array[String] = ["MSV-L3J-H"]
@export var core: Array[String] = ["MSV-L3J-C"]
@export var shoulders : Array[String] = ["MSV-L3J-SG"]
@export var generator : Array[String] = ["type_1"]
@export var chipset : Array[String] = ["type_2"]
@export var chassis : Array[String] = ["MSV-L3J-L"]
@export var thruster : Array[String] = ["test1"]
@export var arm_weapon_left : Array[String] = ["MA-L127"]
@export var arm_weapon_right : Array[String] = ["MA-L127"]
@export var shoulder_weapon_left : Array[String] = ["TORI-ML"]
@export var shoulder_weapon_right : Array[String] = ["TORI-ML"]
