extends Control

@onready var Quantity = $QuantityLabel

var current_part

func setup(part_id, type, is_shopping, quantity): 
	var part = PartManager.get_part(type, part_id)
	
	current_part = part_id
	
	if not part.part_name.is_empty():
		$PartLabel.text = part.part_name
	else:
		$PartLabel.text = "???"
	
	if not part.manufacturer_name.is_empty():
		$ManufacturerLabel.text = part.manufacturer_name_short
	else:
		$ManufacturerLabel.text = "???"
	
	if is_shopping:
		$PriceLabel.text = str(part.price) + "ct"
	else:
		$PriceLabel.text = part.tagline
	
	if part.image:
		$PartPreview.texture = part.image
	else:
		$PartPreview.texture = null
	
	if typeof(quantity) == TYPE_INT or typeof(quantity) == TYPE_FLOAT:
		Quantity.visible = true
		Quantity.text = str(int(quantity))
	else:
		Quantity.visible = false


func get_button():
	return $Button


func update_quantity(value):
	Quantity.text = str(int(value))


func clear():
	current_part = false
	$PartPreview.texture = null
	$ManufacturerLabel.text = "???"
	$PartLabel.text = "???"
	$PriceLabel.text = "-"
