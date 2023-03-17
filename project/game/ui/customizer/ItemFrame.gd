extends Control

var is_disabled = false

func setup(part): 
	if part.part_name.is_empty() == false:
		$PartLabel.text = part.part_name
	else:
		$PartLabel.text = "???"
	if part.manufacturer_name.is_empty() == false:
		$ManufacturerLabel.text = part.manufacturer_name
	else:
		$ManufacturerLabel.text = "???"
	if part.tagline.is_empty() == false:
		$TaglineLabel.text = part.tagline
	else:
		$TaglineLabel.text = "???"
	if part.image:
		$PartPreview.texture = part.image

func get_button():
	return $Button
	
