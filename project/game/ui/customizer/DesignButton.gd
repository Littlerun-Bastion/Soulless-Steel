extends Button

signal design_pressed

# Declare member variables here. Examples:
# var a = 2
# var b = "text"
var stored_design

func setup(name, design):
	self.text = str(name + ".bp")
	stored_design = design


func _on_Button_pressed():
	emit_signal("design_pressed", stored_design)
