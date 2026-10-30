class_name InteractPrompt
extends PanelContainer

## The world prompt over the nearest thing the player can use:
## "[E] SEARCH — INDUSTRIAL CRATE", in a framed box above it.
## Hidden while that thing is already open, and when nothing is in range.
## The verb comes from the thing's interact_verb if it has one, else SEARCH
## for containers (wrecks and carcasses included) and USE for the rest.

const OFFSET := Vector2(0, -64)   # above the thing, in screen px
const EDGE := 15

var player = null

var _key: Label
var _text: Label


func _ready() -> void:
	theme_type_variation = &"HudPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := MechUI.hbox(&"TabRow")
	_key = MechUI.label(&"LabelMetaBright")
	_text = MechUI.label(&"LabelBody")
	row.add_child(_key)
	row.add_child(_text)
	add_child(row)
	MechUI.ignore_mouse(self)
	visible = false


func setup(player_ref) -> void:
	player = player_ref


func player_died() -> void:
	player = null
	visible = false


## "[E] SEARCH — CRATE" or "" when hidden.
func get_text() -> String:
	return "%s %s" % [_key.text, _text.text] if visible else ""


func _process(_delta: float) -> void:
	var thing = player.get_closest_interactable() if is_instance_valid(player) else null
	if thing == null or not is_instance_valid(thing) or thing.get("is_open") == true:
		visible = false
		return
	visible = true
	_key.text = "[%s]" % MechUI.key_name("interact") if InputMap.has_action("interact") else "[E]"
	var verb = thing.get("interact_verb")
	if verb == null or str(verb) == "":
		verb = "SEARCH" if thing is LootContainer else "USE"
	var thing_name = thing.get("display_name")
	_text.text = str(verb).to_upper() + (" — " + str(thing_name).to_upper() if thing_name else "")
	reset_size()
	var at: Vector2 = thing.get_global_transform_with_canvas().origin + OFFSET
	var screen := get_parent_area_size()
	position = Vector2(
		clampf(floorf(at.x - size.x * 0.5), EDGE, screen.x - size.x - EDGE),
		clampf(floorf(at.y - size.y), EDGE + 30, screen.y - size.y - EDGE))
