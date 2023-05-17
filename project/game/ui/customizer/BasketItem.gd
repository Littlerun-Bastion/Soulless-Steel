extends Control

var current_item

func setup(item):
	current_item = item
	$Button/HBoxContainer/Name.text = item.part_name
	$Button/HBoxContainer/Price.text = str(item.price)

func get_price():
	return current_item.price

func get_button():
	return $Button
