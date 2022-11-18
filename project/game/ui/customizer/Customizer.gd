extends Control

const ITEMFRAME = preload("res://game/ui/customizer/ItemFrame.tscn")
onready var PartList = $PartListContainer/VBoxContainer

func _on_Category_pressed(type):
	var parts = PartManager.get_parts(type)
	for child in PartList.get_children(): #Clear PartList
		PartList.remove_child(child)
	for part in parts.values(): #Parsing through a dictionary using .values()
		var item = ITEMFRAME.instance()
		item.setup(part)
		PartList.add_child(item)
