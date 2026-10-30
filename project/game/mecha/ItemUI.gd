extends Panel
class_name ItemUI

## One item in an inventory grid (and the drag ghost).
## Sprites draw at 1:1: a w × h footprint is (cell + 1) * w - 1 by
## (cell + 1) * h - 1 pixels. Nothing is scaled, so line weights stay true.
## No sprite → the item's name in Meta at the top left.

const MECH_THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const ART_MARGIN := 4  # sprites keep their art this far from each edge

var stack: item_stack
var cell_size: int = 68  # set by InventoryGrid / DragManager; layout uses the panel size

@onready var icon: TextureRect = $Icon
@onready var quantity_label: Label = $Quantity

var _name_label: Label = null
# Warn once per texture about a size that doesn't match its footprint.
static var _warned_textures: Dictionary = {}


func _ready():
	# Set here, not inherited: the drag ghost lives on a layer with no theme.
	theme = MECH_THEME
	theme_type_variation = &"ItemFrame"
	set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	mouse_filter = Control.MOUSE_FILTER_PASS

	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_name_label = Label.new()
	_name_label.theme_type_variation = &"ItemName"
	_name_label.uppercase = true
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.clip_text = true
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.position = Vector2(ART_MARGIN, ART_MARGIN - 2)
	_name_label.visible = false
	add_child(_name_label)

	quantity_label.theme_type_variation = &"LabelMetaBright"
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
	quantity_label.grow_vertical = Control.GROW_DIRECTION_BEGIN  # grow up, stay inside
	quantity_label.offset_left = ART_MARGIN
	quantity_label.offset_bottom = -2
	quantity_label.offset_top = -2
	quantity_label.offset_right = 0


# The item or part resource behind the stack.
func _get_stack_resource() -> Object:
	if stack == null:
		return null
	# 1) Generic loot item: use item_data
	if stack.kind == item_stack.ItemKind.GENERIC and stack.item != null:
		return stack.item
	# 2) Mech part: resolve via PartManager
	if stack.kind == item_stack.ItemKind.PART:
		if stack.item != null:
			return stack.item
		if stack.item_type != "" and stack.item_id != "":
			return PartManager.get_part(stack.item_type, stack.item_id)
	return null


func _get_stack_texture() -> Texture2D:
	var res: Object = _get_stack_resource()
	if res == null:
		return null
	if res is Texture2D:
		return res
	# "icon" first, then "image" (what the parts use)
	var maybe_icon = res.get("icon")
	if maybe_icon is Texture2D:
		return maybe_icon
	var maybe_image = res.get("image")
	if maybe_image is Texture2D:
		return maybe_image
	return null


func _get_stack_name() -> String:
	var res: Object = _get_stack_resource()
	if res == null:
		return "?"
	for key in ["item_name", "part_name", "display_name", "name"]:
		var value = res.get(key)
		if value != null and str(value) != "":
			return str(value)
	return "?"


func _update_icon_layout() -> void:
	if icon == null or stack == null:
		return

	var panel_size: Vector2 = size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return

	var tex: Texture2D = _get_stack_texture()
	icon.texture = tex
	_name_label.visible = tex == null
	if tex == null:
		_name_label.text = _get_stack_name()
		_name_label.size = Vector2(panel_size.x - ART_MARGIN * 2, panel_size.y - ART_MARGIN - 20)
		return

	var tex_size: Vector2 = tex.get_size()
	_check_sprite_size(tex, tex_size, panel_size)

	# 1:1, no scaling. The rect is the texture's own size.
	icon.pivot_offset = Vector2.ZERO
	icon.custom_minimum_size = tex_size
	icon.size = tex_size

	if stack.rotated:
		# Turn 90° about the top-left corner, then shift right by the
		# texture height. Every pixel lands on a whole pixel; turning about
		# the centre would land odd sizes (137 px) on half pixels.
		var turned := Vector2(tex_size.y, tex_size.x)
		var offset := ((panel_size - turned) * 0.5).floor()
		icon.position = offset + Vector2(tex_size.y, 0)
	else:
		icon.position = ((panel_size - tex_size) * 0.5).floor()


# Debug builds only: a sprite drawn at the wrong size gets one warning.
func _check_sprite_size(tex: Texture2D, tex_size: Vector2, panel_size: Vector2) -> void:
	if not OS.is_debug_build():
		return
	var expected := Vector2(panel_size.y, panel_size.x) if stack.rotated else panel_size
	if tex_size == expected:
		return
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _warned_textures.has(key):
		return
	_warned_textures[key] = true
	push_warning("ItemUI: '%s' sprite is %dx%d, footprint wants %dx%d (%s)." % [
		_get_stack_name(), tex_size.x, tex_size.y, expected.x, expected.y, key])


func _update_visuals() -> void:
	if not is_inside_tree() or stack == null:
		return

	# Rotate icon (the layout already accounted for rotated bounds)
	if icon:
		icon.rotation_degrees = 90.0 if stack.rotated else 0.0

	# Quantity label (always bottom-left, upright)
	if quantity_label:
		if stack.quantity > 1:
			quantity_label.text = str(stack.quantity)
			quantity_label.visible = true
		else:
			quantity_label.visible = false
