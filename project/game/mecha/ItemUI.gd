extends Panel
class_name ItemUI

var stack: item_stack
var cell_size: int = 48

@onready var icon: TextureRect = $Icon
@onready var quantity_label: Label = $Quantity

func _ready():
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_setup_quantity_label_layout()
	
func set_stack(s: item_stack) -> void:
	stack = s
	_update_icon_layout()
	_update_visuals()
	
func _setup_quantity_label_layout() -> void:
	if quantity_label == null:
		return

	quantity_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, false)
	quantity_label.rotation_degrees = 0.0
	quantity_label.offset_left = 2
	quantity_label.offset_bottom = -2
	quantity_label.offset_top = 0
	quantity_label.offset_right = 0


		
func _update_icon_layout() -> void:
	if icon == null or stack == null:
		return

	var panel_size: Vector2 = size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return

	# Get the texture from item_data
	var tex: Texture2D = null
	if stack.item and stack.item.has_method("get"):
		tex = stack.item.get("icon")
	if tex == null:
		icon.texture = null
		return

	icon.texture = tex

	var tex_size: Vector2 = tex.get_size()   # e.g. (60, 150)
	var padding: float = 4.0

	# We want the *visual* footprint to respect rotation:
	# - If not rotated: logical_w = tex.w, logical_h = tex.h
	# - If rotated:     logical_w = tex.h, logical_h = tex.w
	var logical_w := tex_size.x
	var logical_h := tex_size.y
	if stack.rotated:
		var tmp = logical_w
		logical_w = logical_h
		logical_h = tmp

	# Fit the logical size inside the panel with padding
	var max_w = panel_size.x - padding * 2.0
	var max_h = panel_size.y - padding * 2.0

	if max_w <= 0.0 or max_h <= 0.0:
		return

	var scale = min(max_w / logical_w, max_h / logical_h)
	# Optional: avoid upscaling above 1.0 if you want
	# scale = min(scale, 1.0)

	var final_w = logical_w * scale
	var final_h = logical_h * scale

	# Now convert back to TextureRect's rect:
	# If rotated, the rect is "flipped" relative to logical w/h.
	var rect_w = final_w
	var rect_h = final_h
	if stack.rotated:
		rect_w = final_h
		rect_h = final_w

	icon.custom_minimum_size = Vector2(rect_w, rect_h)
	icon.size = Vector2(rect_w, rect_h)

	# Center inside the panel
	icon.position = (panel_size - icon.size) * 0.5

	# Rotate around the icon's own center
	icon.pivot_offset = icon.size * 0.5

	
func _update_visuals() -> void:
	if not is_inside_tree() or stack == null:
		return

	# Rotation only (texture already set in _update_icon_layout)
	if icon:
		icon.rotation_degrees = 90.0 if stack.rotated else 0.0

	# Quantity label: always bottom-left, upright
	if quantity_label:
		if stack.quantity > 1:
			quantity_label.text = str(stack.quantity)
			quantity_label.visible = true
		else:
			quantity_label.visible = false
