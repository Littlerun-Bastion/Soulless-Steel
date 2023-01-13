extends Control

onready var DesignContainer = $PanelContainer2/ScrollContainer/DesignContainer

const DESIGN_BUTTON = preload("res://game/ui/customizer/DesignButton.tscn")

var designs = []
var current_design

# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	reload_designs()

func reload_designs():
	designs = FileManager.get_all_mecha_design_names()
	current_design = self.get_parent().DisplayMecha
	for x in DesignContainer.get_children():
		x.queue_free()
	for design in designs:
		var new_panel = DESIGN_BUTTON.instance()
		var design_data = FileManager.load_mecha_design(design)
		if design_data:
			new_panel.connect("design_pressed", self, "_on_design_pressed")
			new_panel.setup(design, design_data)
			DesignContainer.add_child(new_panel)
		else:
			print("No design data to load.")

func save_design():
	var design_name = $DesignNameEntry.text
	var mecha = self.get_parent().DisplayMecha
	if design_name and mecha:
		FileManager.save_mecha_design(mecha, design_name)
	if FileManager.load_mecha_design(design_name):
		$SaveSuccessful.visible = true
		reload_designs()
		yield(get_tree().create_timer(3), "timeout")
		$SaveSuccessful.visible = false
	
func _on_design_pressed():
	pass

func _on_exit_pressed():
	self.visible = false
	pass # Replace with function body.


func _on_RefreshButton_pressed():
	reload_designs()


func _on_SaveButton_pressed():
	save_design()
