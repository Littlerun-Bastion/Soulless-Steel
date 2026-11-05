class_name HudWeapons
extends PanelContainer

## Bottom-right HUD block: one row per weapon slot.
##   key     the bound input (LMB, RMB, Q...)
##   slot    L ARM, R ARM, L SHD, R SHD (+ " · RELOADING" while reloading)
##   name    the weapon's part name, or EMPTY for an empty slot
##   ammo    rounds in the clip (battery charge for battery weapons), large;
##           the reserve underneath, small. Dim at 0.
## While a weapon reloads its name gives way to a reload bar. A weapon the
## frame readout shows as gone reads LOST (struck through, dashed tag). An
## indirect-fire weapon can't fire from inside a building: its name dims and
## a dashed INDOORS tag shows.
## The last row is the internal bay (INT): a device part's charges left, large
## (dim at 0), "CHARGES" under them; a passive part ON or OFF (dim), or LOST
## for a Seeker shot down, its function under it. While it can't be used yet
## the label reads "INT · 0.6S".
## Under it the IR illuminator: ON, HELD while the key holds it on or LATCHED
## while it stays on by itself (Player.press_illuminator_key), or OFF (dim),
## DARK, while the player runs dark.
## Rows are built once in setup(); values are read each frame.

const SLOTS := [
	{"slot": "arm_weapon_left", "label": "L ARM", "action": "arm_weapon_left_shoot", "node": "ArmWeaponLeft"},
	{"slot": "arm_weapon_right", "label": "R ARM", "action": "arm_weapon_right_shoot", "node": "ArmWeaponRight"},
	{"slot": "shoulder_weapon_left", "label": "L SHD", "action": "shoulder_weapon_left_shoot", "node": "ShoulderWeaponLeft"},
	{"slot": "shoulder_weapon_right", "label": "R SHD", "action": "shoulder_weapon_right_shoot", "node": "ShoulderWeaponRight"},
	{"slot": "internal", "label": "INT", "action": "use_internal", "node": ""},
	{"slot": "illuminator", "label": "IR", "action": "toggle_illuminator", "node": ""},
]
const WIDTH := 380

var player = null
## Asked per slot whether the weapon is gone (WireframeDisplay supplies it).
var is_lost: Callable = func(_slot: String) -> bool: return false

var _rows: Dictionary = {}       # slot -> {...}
var _reload_start: Dictionary = {}  # slot -> msec when its reload began


func _ready() -> void:
	theme_type_variation = &"HudList"
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(player_ref) -> void:
	player = player_ref
	MechUI.clear(self)
	_rows.clear()
	var list := MechUI.vbox(&"ListRows")
	add_child(list)
	for info in SLOTS:
		list.add_child(_make_row(info))
	MechUI.ignore_mouse(self)
	_update()


func player_died() -> void:
	player = null


func _process(_delta: float) -> void:
	if is_instance_valid(player):
		_update()


## The text a row shows, for tests: "RMB R ARM MA-L127 30 / 240".
func get_row_text(slot: String) -> String:
	var row: Dictionary = _rows.get(slot, {})
	if row.is_empty():
		return ""
	var parts := [row.key.text, row.slot.text]
	if row.name.visible:
		parts.append(row.name.text)
	if row.ammo_box.visible:
		parts.append("%s / %s" % [row.ammo.text, row.reserve.text])
	if row.lost.visible:
		parts.append("LOST")
	if row.indoors.visible:
		parts.append("INDOORS")
	return " ".join(parts)


# ---- building -----------------------------------------------------------

func _make_row(info: Dictionary) -> PanelContainer:
	var row := MechUI.pane(&"HudRow")
	var line := MechUI.hbox(&"BarRow")
	row.add_child(line)

	var key := MechUI.label(&"LabelMeta", MechUI.key_name(info.action) if InputMap.has_action(info.action) else "")
	key.custom_minimum_size.x = 44
	line.add_child(key)

	var middle := MechUI.vbox(&"StatRow")
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	var slot_label := MechUI.label(&"LabelMeta", info.label)
	var name_label := MechUI.label(&"LabelBody")
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var reload := StatBar.new()
	reload.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reload.visible = false
	middle.add_child(slot_label)
	middle.add_child(name_label)
	middle.add_child(reload)
	line.add_child(middle)

	var ammo_box := MechUI.vbox()
	ammo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var ammo := MechUI.label(&"LabelDisplay")
	ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var reserve := MechUI.label(&"LabelMeta")
	reserve.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(ammo)
	ammo_box.add_child(reserve)
	line.add_child(ammo_box)

	var lost := MechUI.pane(&"NoticeDashed", MechUI.label(&"LabelMeta", "LOST"))
	lost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lost.visible = false
	line.add_child(lost)

	var indoors := MechUI.pane(&"NoticeDashed", MechUI.label(&"LabelMeta", "INDOORS"))
	indoors.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	indoors.visible = false
	line.add_child(indoors)

	_rows[info.slot] = {"info": info, "key": key, "slot": slot_label, "name": name_label,
			"reload": reload, "ammo": ammo, "reserve": reserve, "ammo_box": ammo_box, "lost": lost,
			"indoors": indoors}
	return row


# ---- updating -----------------------------------------------------------

func _update() -> void:
	for slot in _rows:
		_update_row(_rows[slot])


func _update_row(row: Dictionary) -> void:
	var info: Dictionary = row.info
	if info.slot == "illuminator":
		_update_illuminator_row(row)
		return
	var part = player.build.get(info.slot)
	if not part:
		row.slot.text = info.label
		row.name.text = "EMPTY"
		row.name.theme_type_variation = &"LabelDim"
		row.name.visible = true
		row.reload.visible = false
		row.ammo_box.visible = false
		row.lost.visible = false
		row.indoors.visible = false
		return

	if info.slot == "internal":
		_update_internal_row(row, part)
		return

	var lost: bool = is_lost.call(info.slot)
	row.lost.visible = lost
	var indoors: bool = not lost and part.get("is_indirect_fire") == true and player.is_inside_building
	row.indoors.visible = indoors
	row.ammo_box.visible = not lost
	var weapon_name: String = str(part.get("part_name")) if part.get("part_name") else str(info.slot)
	if lost:
		row.slot.text = info.label
		row.name.text = weapon_name
		row.name.theme_type_variation = &"LabelDim"
		row.name.visible = true
		row.reload.visible = false
		return

	var node = player.get_node_or_null(info.node)
	var reloading: bool = node != null and node.get("reloading") == true
	if reloading:
		if not _reload_start.has(info.slot):
			_reload_start[info.slot] = Time.get_ticks_msec()
		var duration := maxf(float(node.data.reload_speed), 0.01)
		row.reload.ratio = (Time.get_ticks_msec() - _reload_start[info.slot]) / 1000.0 / duration
	else:
		_reload_start.erase(info.slot)
	row.slot.text = info.label + (" · RELOADING" if reloading else "")
	row.name.text = weapon_name
	row.name.theme_type_variation = &"LabelDim" if indoors else &"LabelBody"
	row.name.visible = not reloading
	row.reload.visible = reloading

	var clip = player.get_clip_ammo(info.slot)
	var total = player.get_total_ammo(info.slot)
	var clip_value := roundi(float(clip)) if clip is float or clip is int else 0
	row.ammo.text = str(clip_value)
	row.ammo.theme_type_variation = &"LabelDisplay" if clip_value > 0 else &"LabelDisplayDim"
	var battery: bool = node != null and node.get("data") != null and node.data.uses_battery
	row.reserve.text = "BATTERY" if battery else str(roundi(float(total)) if total is float or total is int else 0)


func _update_internal_row(row: Dictionary, part) -> void:
	var info: Dictionary = row.info
	var cooldown: float = player.internal_cooldown
	row.slot.text = info.label + (" · %sS" % MechUI.fmt(snappedf(cooldown, 0.1)) if cooldown > 0.0 else "")
	row.name.text = str(part.get("part_name"))
	row.name.theme_type_variation = &"LabelBody"
	row.name.visible = true
	row.reload.visible = false
	row.lost.visible = false
	row.indoors.visible = false
	row.ammo_box.visible = true
	if part.is_passive():
		var on: bool = player.internal_on
		row.ammo.text = "LOST" if player.internal_lost else ("ON" if on else "OFF")
		row.ammo.theme_type_variation = &"LabelDisplay" if on else &"LabelDisplayDim"
		row.reserve.text = str(part.function).to_upper()
	else:
		var charges: int = player.internal_charges
		row.ammo.text = str(charges)
		row.ammo.theme_type_variation = &"LabelDisplay" if charges > 0 else &"LabelDisplayDim"
		row.reserve.text = "CHARGES"


func _update_illuminator_row(row: Dictionary) -> void:
	var on: bool = player.illuminator_on
	row.slot.text = row.info.label
	row.name.text = "ILLUMINATOR"
	row.name.theme_type_variation = &"LabelBody"
	row.name.visible = true
	row.reload.visible = false
	row.lost.visible = false
	row.indoors.visible = false
	row.ammo_box.visible = true
	row.ammo.text = "ON" if on else "OFF"
	row.ammo.theme_type_variation = &"LabelDisplay" if on else &"LabelDisplayDim"
	if not on:
		row.reserve.text = "DARK"
	elif player.has_method("is_illuminator_held") and player.is_illuminator_held():
		row.reserve.text = "HELD"
	else:
		row.reserve.text = "LATCHED"
