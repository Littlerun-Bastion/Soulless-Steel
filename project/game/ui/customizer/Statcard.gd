extends Control

func display_part_stats(current_part, new_part, part_type):
	$Title/Title.text = new_part.part_name
	$Title/Subtitle.text = new_part.tagline
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
