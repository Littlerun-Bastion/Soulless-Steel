extends Control

var current_item
var part_type := ""  # PartManager key, needed to put the part in the stash

func setup(item, type: String):
	current_item = item
	part_type = type
	$Button/HBoxContainer/Name.text = item.part_name
	$Button/HBoxContainer/Price.text = str(item.price)

func get_price():
	return current_item.price

func get_button():
	return $Button
