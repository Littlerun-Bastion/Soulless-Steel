extends Control

var is_disabled = false

func setup(part, is_shopping): 
	if part.part_name.is_empty() == false:
		$PartLabel.text = part.part_name
	else:
		$PartLabel.text = "???"
	if part.manufacturer_name.is_empty() == false:
		$ManufacturerLabel.text = part.manufacturer_name
	else:
		$ManufacturerLabel.text = "???"
	if is_shopping:
		$PriceLabel.text = str(part.price) + "ct"
	else:
		$PriceLabel.text = part.tagline
	if part.image:
		$PartPreview.texture = part.image

func get_button():
	return $Button
	
