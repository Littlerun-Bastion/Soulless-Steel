extends Button

signal design_pressed

var stored_design

func setup(design_name, design):
	self.text = str(design_name + ".design")
	stored_design = design


func _on_Button_pressed():
	emit_signal("design_pressed", stored_design)
