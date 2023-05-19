extends Control

var is_disabled = false
var current_part

func setup(part, is_shopping, quantity): 
	current_part = part
	if part.part_name.is_empty() == false:
		$PartLabel.text = part.part_name
	else:
		$PartLabel.text = "???"
	if part.manufacturer_name.is_empty() == false:
		$ManufacturerLabel.text = part.manufacturer_name_short
	else:
		$ManufacturerLabel.text = "???"
	if is_shopping:
		$PriceLabel.text = str(part.price) + "ct"
	else:
		$PriceLabel.text = part.tagline
	if part.image:
		$PartPreview.texture = part.image
	if quantity:
		$QuantityLabel.visible = true
		$QuantityLabel.text = str(quantity)
	else:
		$QuantityLabel.visible = false

func get_button():
	return $Button
	
