extends Control

@onready var DesignContainer = $PanelContainer2/ScrollContainer/DesignContainer
@onready var HeadName = $PanelContainer3/ScrollContainer/VBoxContainer/HeadName
@onready var CoreName = $PanelContainer3/ScrollContainer/VBoxContainer/CoreName
@onready var ShouldersName = $PanelContainer3/ScrollContainer/VBoxContainer/ShouldersName
@onready var ChassisName = $PanelContainer3/ScrollContainer/VBoxContainer/ChassisName
@onready var GeneratorName = $PanelContainer3/ScrollContainer/VBoxContainer/GeneratorName
@onready var ChipsetName = $PanelContainer3/ScrollContainer/VBoxContainer/ChipsetName
@onready var ThrusterName = $PanelContainer3/ScrollContainer/VBoxContainer/ThrusterName
@onready var RightArmName = $PanelContainer3/ScrollContainer/VBoxContainer/RightArmName
@onready var LeftArmName = $PanelContainer3/ScrollContainer/VBoxContainer/RightArmName
@onready var RightShoulderName = $PanelContainer3/ScrollContainer/VBoxContainer/RightShoulderName
@onready var LeftShoulderName = $PanelContainer3/ScrollContainer/VBoxContainer/LeftShoulderName

const DESIGN_BUTTON = preload("res://game/ui/customizer/DesignButton.tscn")

var designs = []
var current_design
var pressed_design
var shopping_mode = true

signal load_pressed

# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	reload_designs()
	if shopping_mode:
		$LoadButton.visible = false
	else:
		$LoadButton.visible = true

func check_pressed_design():
	if pressed_design == null:
		$LoadButton.disabled = true
	else:
		$LoadButton.disabled = false

func reload_designs():
	designs = FileManager.get_all_mecha_design_names()
	current_design = self.get_parent().DisplayMecha
	for x in DesignContainer.get_children():
		x.queue_free()
	for design in designs:
		var new_panel = DESIGN_BUTTON.instantiate()
		var design_data = FileManager.load_mecha_design(design)
		if design_data:
			new_panel.connect("design_pressed",Callable(self,"_on_design_pressed"))
			new_panel.setup(design, design_data)
			DesignContainer.add_child(new_panel)
		else:
			print("No design data to load.")
	
	check_pressed_design()
			

func save_design():
	var design_name = $DesignNameEntry.text
	var mecha = self.get_parent().DisplayMecha
	if design_name and mecha:
		FileManager.save_mecha_design(mecha, design_name)
	if FileManager.load_mecha_design(design_name):
		$SaveSuccessful.visible = true
		reload_designs()
		await get_tree().create_timer(3).timeout
		$SaveSuccessful.visible = false
	check_pressed_design()

func _on_design_pressed(design):
	pressed_design = design
	check_pressed_design()
	if design.head:
		HeadName.text = "- " + design.head
	else:
		HeadName.text = ""
	if design.core:
		CoreName.text = "- " + design.core
	else:
		CoreName.text = ""
	if design.shoulders:
		ShouldersName.text = "- " + design.shoulders
	else:
		ShouldersName.text = ""
	if design.chassis:
		ChassisName.text = "- " + design.chassis
	else:
		ChassisName.text = ""
	if design.generator:
		GeneratorName.text = "- " + design.generator
	else:
		GeneratorName.text = ""
	if design.chipset:
		ChipsetName.text = "- " + design.chipset
	else:
		ChipsetName.text = ""
	if design.thruster:
		ThrusterName.text = "- " + design.thruster
	else:
		ThrusterName.text = ""
	if design.arm_weapon_right:
		RightArmName.text = "- " + design.arm_weapon_right
	else:
		RightArmName.text = ""
	if design.arm_weapon_left:
		LeftArmName.text = "- " + design.arm_weapon_left
	else:
		LeftArmName.text = ""
	if design.shoulder_weapon_right:
		RightShoulderName.text = "- " + design.shoulder_weapon_right
	else:
		RightShoulderName.text = ""
	if design.shoulder_weapon_left:
		LeftShoulderName.text = "- " + design.shoulder_weapon_left
	else:
		LeftShoulderName.text = ""

func _on_exit_pressed():
	check_pressed_design()
	self.visible = false


func _on_RefreshButton_pressed():
	reload_designs()


func _on_SaveButton_pressed():
	save_design()


func _on_LoadButton_pressed():
	self.visible = false
	emit_signal("load_pressed", pressed_design)
