extends Control

@onready var Place = $Button/HBoxContainer/Place
@onready var Suffix = $Button/HBoxContainer/VBoxContainer/Suffix
@onready var Name = $Button/Name



func set_mecha_name(mecha_name):
	Name.text = mecha_name


func set_ranking(new_idx):
	Place.text = str(new_idx)
	match new_idx:
		1:
			Suffix.text = "st"
		2:
			Suffix.text = "nd"
		3:
			Suffix.text = "rd"
		_:
			Suffix.text = "th"
