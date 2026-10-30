extends Panel

## The MechOS sidebar: one 56px icon tile per app, styled by the SidebarTile
## variation in MechTheme. Tile states: idle, hover, open (left bar),
## unread (badge) and disabled (dashed). NET and SYS sit at the bottom.

const TILE_SIZE := Vector2(56, 56)
const CODE_Y := 34  # icon 6–30, code 34–51

var buttons: Dictionary = {}  # app_id -> Button
var badges: Dictionary = {}   # app_id -> Label

@onready var top_list: VBoxContainer = $ButtonList/Top
@onready var bottom_list: VBoxContainer = $ButtonList/Bottom


## code: the 3-letter label under the icon. full_name: the tooltip.
## bottom: pin the tile under the spacer (NET, SYS).
func add_app_button(app_id: String, code: String, icon: Texture2D = null,
		full_name: String = "", bottom: bool = false) -> void:
	if buttons.has(app_id):
		return

	var btn := Button.new()
	btn.theme_type_variation = &"SidebarTile"
	btn.icon = icon
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.custom_minimum_size = TILE_SIZE
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = full_name if full_name != "" else code
	btn.set_meta("full_name", btn.tooltip_text)
	btn.pressed.connect(_on_app_button_pressed.bind(app_id))
	btn.mouse_entered.connect(_refresh_code.bind(app_id), CONNECT_DEFERRED)
	btn.mouse_exited.connect(_refresh_code.bind(app_id), CONNECT_DEFERRED)

	# The code sits in its own Label: Godot's Button counts the text height
	# twice when the icon is above it, which breaks the 56px tile.
	var code_label := Label.new()
	code_label.text = code
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	code_label.position = Vector2(0, CODE_Y)
	code_label.size = Vector2(TILE_SIZE.x, 17)
	btn.add_child(code_label)
	btn.set_meta("code_label", code_label)

	var badge := Label.new()
	badge.theme_type_variation = &"Badge"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	btn.add_child(badge)

	(bottom_list if bottom else top_list).add_child(btn)
	buttons[app_id] = btn
	badges[app_id] = badge
	_refresh_code(app_id)


func remove_app_button(app_id: String) -> void:
	if not buttons.has(app_id):
		return
	buttons[app_id].queue_free()
	buttons.erase(app_id)
	badges.erase(app_id)


func set_app_button_visible(app_id: String, shown: bool) -> void:
	if buttons.has(app_id):
		buttons[app_id].visible = shown


func is_app_button_visible(app_id: String) -> bool:
	return buttons.has(app_id) and buttons[app_id].visible


## Lights the tile's left bar while its window is open. MechOS calls this
## whenever a window opens or closes.
func set_app_open(app_id: String, open: bool) -> void:
	if buttons.has(app_id):
		buttons[app_id].set_pressed_no_signal(open)
		_refresh_code(app_id)


## A disabled tile stays visible with a dashed frame. The reason joins the
## tooltip, e.g. "Browser — Offline".
func set_app_enabled(app_id: String, enabled: bool, reason: String = "") -> void:
	if not buttons.has(app_id):
		return
	var btn: Button = buttons[app_id]
	btn.disabled = not enabled
	var full_name: String = btn.get_meta("full_name")
	btn.tooltip_text = full_name if enabled or reason == "" else "%s — %s" % [full_name, reason]
	_refresh_code(app_id)


## Unread count in an inverted badge, top right. 0 hides it.
func set_badge(app_id: String, count: int) -> void:
	if not badges.has(app_id):
		return
	var badge: Label = badges[app_id]
	badge.visible = count > 0
	badge.text = str(count) if count < 100 else "99"
	badge.reset_size()
	badge.position = Vector2(TILE_SIZE.x - badge.size.x - 2, 2)


# The code label follows the tile: bright when open or hovered, dim otherwise.
func _refresh_code(app_id: String) -> void:
	if not buttons.has(app_id):
		return
	var btn: Button = buttons[app_id]
	var bright := not btn.disabled and (btn.button_pressed or btn.is_hovered())
	var code_label: Label = btn.get_meta("code_label")
	code_label.theme_type_variation = &"LabelMetaBright" if bright else &"LabelMeta"


func _on_app_button_pressed(app_id: String) -> void:
	MechOS.toggle_app(app_id)
	# A toggle button flips itself on click; the real state is whether the
	# window is open (a Hangar window that can't close stays open).
	set_app_open(app_id, MechOS.is_app_open(app_id))
