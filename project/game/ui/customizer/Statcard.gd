extends Control

func display_part_stats(current_part, new_part, part_type):
	$Title/Title.text = new_part.part_name
	$Title/Subtitle.text = new_part.tagline
	$description/Manufactuer.text = new_part.manufacturer_name
	$description/HBoxContainer/MSRP.text = str(new_part.price)
	if new_part.description:
		$description/Description.text = new_part.description
	else:
		$description/Description.text = "No info available."
	for child in $parts.get_children():
		child.visible = false
	var category = $parts.get_node_or_null(part_type)
	if category:
		category.visible = true
	else:
		$PanelContainer.visible = false
	var type_section = $parts.get_node_or_null(part_type)
	if type_section:
		$PanelContainer.visible = true
		for child in type_section.get_children():
			child.update_stat(current_part, new_part)


func toggle_description():
	AudioManager.play_sfx("keystrike")
	AudioManager.play_sfx("boop")
	$description.visible = !$description.visible
	$parts.visible = !$parts.visible
	pass # Replace with function body.
