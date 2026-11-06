extends MechWindow
class_name CompareWindow

## COMPARE: one part (the subject) against another of the same type. Opened
## by "Compare to..." on a part's right-click menu (MechOS.open_compare): a
## part in an inventory grid, a filled slot in EQP, or a part on amazing.com.
## Opening it again with a new subject replaces the subject.
##
## Left, the candidates, in two tabs:
##   OWNED  the parts fitted on the mecha, in the stash and in the cargo, one
##          row per part, grade and place ("FITTED · L ARM", "STASH ×2",
##          "CARGO"), leaving out the subject itself. A secret part
##          (store_listed off) the player owns shows here.
##   STORE  Store.catalogue with prices, so never an unlisted part; while NET
##          is available each row links to its amazing.com page.
## Weapons list by type (arm or shoulder), not side; fitted ones show theirs.
## Right, PartCompare: the subject against the picked candidate.
##
## A part here is {"part_type", "part_id", "grade", "place"}; place is
## "stash", "cargo", "slot:<build key>", "store" or "loot".

const TITLE_PREFIX := "COMPARE"
const OWNED := "owned"
const STORE := "store"
const SLOT_NAMES := {
	"head": "HEAD", "core": "CORE", "shoulders": "SHOULDERS", "chassis": "CHASSIS",
	"generator": "GENERATOR", "chipset": "CHIPSET", "thruster": "THRUSTER", "internal": "INTERNAL",
	"arm_weapon_left": "L ARM", "arm_weapon_right": "R ARM",
	"shoulder_weapon_left": "L SHOULDER", "shoulder_weapon_right": "R SHOULDER",
}
const EMPTY_OWNED := "You own no other parts of this type."
const EMPTY_STORE := "amazing.com sells none of these."

var subject: Dictionary = {}
var candidate: Dictionary = {}
var compare: PartCompare

var _tab := OWNED
var _tab_group := ButtonGroup.new()
var _row_group := ButtonGroup.new()
var _tabs: Dictionary = {}  # tab -> Button
var _list: VBoxContainer
var _empty: Label
var _entries: Array = []    # the candidates listed, in row order


func _ready() -> void:
	super()
	_build()
	_refresh_list()


## Starts over with a new subject: the title, both lists and no candidate.
func set_subject(new_subject: Dictionary) -> void:
	subject = new_subject.duplicate()
	candidate = {}
	window_title = "%s // %s" % [TITLE_PREFIX, PartCompare.display_name(subject).to_upper()]
	if title_label != null:
		title_label.text = window_title
	_refresh_list()
	compare.show_compare(subject, {})


func set_tab(tab: String) -> void:
	_tab = tab
	for key in _tabs:
		_tabs[key].set_pressed_no_signal(key == tab)
	_refresh_list()


## The candidates in the open tab, as listed.
func get_entries() -> Array:
	return _entries.duplicate()


## Each row's text, "NAME | META" (tests).
func get_rows() -> Array:
	var rows := []
	for row in _list.get_children():
		if row.is_queued_for_deletion():
			continue
		var labels: Array = row.find_children("*", "Label", true, false)
		rows.append(" | ".join(labels.map(func(l): return l.text)))
	return rows


func select_candidate(entry: Dictionary) -> void:
	candidate = entry.duplicate()
	compare.show_compare(subject, candidate)
	for i in _entries.size():
		var row: Button = _list.get_child(i)
		row.set_pressed_no_signal(_same(_entries[i], candidate))


func select_row(index: int) -> void:
	if index >= 0 and index < _entries.size():
		select_candidate(_entries[index])


# ---- the part in a menu's context -----------------------------------------

## The part a right-click menu was opened on, for both context shapes: an
## inventory item ({"stack", "inventory"}) or a part
## ({"part_type", "part_id", "grade", "slot" or "from_store"}). {} when the
## context isn't a part.
static func subject_from_context(ctx: Dictionary) -> Dictionary:
	var stack = ctx.get("stack")
	if stack is item_stack:
		if not stack.is_part():
			return {}
		return {"part_type": stack.item_type, "part_id": stack.item_id, "grade": Grades.of(stack.grade),
				"place": _place_of(ctx.get("inventory"))}
	var part_id := str(ctx.get("part_id", ""))
	var part_type := str(ctx.get("part_type", ""))
	if part_id == "" or not part_type in PlayerProgress.PART_TYPES:
		return {}
	var place := "store" if ctx.get("from_store", false) else ""
	if str(ctx.get("slot", "")) != "":
		place = "slot:" + str(ctx.slot)
	return {"part_type": part_type, "part_id": part_id, "grade": Grades.of(ctx.get("grade")), "place": place}


static func _place_of(inv) -> String:
	if inv == null:
		return "loot"
	if inv == PlayerProgress.get_stash_inventory():
		return "stash"
	if inv == player_cargo():
		return "cargo"
	return "loot"


# ---- what the player owns -------------------------------------------------

static func player_cargo() -> Inventory:
	var player = MechOS.player_ref
	if is_instance_valid(player) and player.get("mech_inventory") is Inventory:
		return player.mech_inventory
	return PlayerProgress.get_mech_inventory()


## The build keys a part type fits.
static func slots_of(part_type: String) -> Array:
	if part_type == "arm_weapon" or part_type == "shoulder_weapon":
		return [part_type + "_left", part_type + "_right"]
	return [part_type]


## The parts of this type fitted on the mecha: {"part_id", "grade", "slot"}
## each. The live mecha when MechOS has one (Hangar, field), else the saved
## design.
static func fitted_parts(part_type: String) -> Array:
	var result := []
	var player = MechOS.player_ref
	var live: bool = is_instance_valid(player) and player.get("build") is Dictionary
	var build: Dictionary = player.build if live else PlayerProgress.get_current_mecha()
	var grades: Dictionary = player.part_grades if live and player.get("part_grades") is Dictionary \
			else PlayerProgress.get_current_grades()
	for slot in slots_of(part_type):
		var value = build.get(slot)
		var part_id := ""
		if value is Object and is_instance_valid(value) and value.get("part_id") != null:
			part_id = str(value.part_id)
		elif value is String:
			part_id = value
		if part_id == "" or not PartManager.is_valid_part(part_type, part_id):
			continue
		result.append({"part_id": part_id, "grade": Grades.of(grades.get(slot)), "slot": slot})
	return result


## Every part of this type the player has: fitted, then the stash, then the
## cargo, one entry per part, grade and place, with "count" and "where".
static func owned_candidates(part_type: String) -> Array:
	var result := []
	for fitted in fitted_parts(part_type):
		result.append({"part_type": part_type, "part_id": fitted.part_id, "grade": fitted.grade,
				"place": "slot:" + fitted.slot, "count": 1, "where": "FITTED · " + SLOT_NAMES.get(fitted.slot, fitted.slot)})
	result.append_array(_grouped(part_type, PlayerProgress.get_stash_inventory(), "stash", "STASH"))
	var cargo := player_cargo()
	if cargo != PlayerProgress.get_stash_inventory():
		result.append_array(_grouped(part_type, cargo, "cargo", "CARGO"))
	return result


static func _grouped(part_type: String, inv: Inventory, place: String, label: String) -> Array:
	var groups := {}
	var order := []
	if inv == null or inv.grid.is_empty():
		return []
	for stack in inv.get_stacks():
		if not stack.is_part() or stack.item_type != part_type:
			continue
		var key := "%s|%s" % [stack.item_id, Grades.of(stack.grade)]
		if not groups.has(key):
			groups[key] = {"part_type": part_type, "part_id": stack.item_id, "grade": Grades.of(stack.grade),
					"place": place, "count": 0}
			order.append(key)
		groups[key].count += stack.quantity
	var result := []
	for key in order:
		var entry: Dictionary = groups[key]
		entry["where"] = label if entry.count <= 1 else "%s ×%d" % [label, entry.count]
		result.append(entry)
	return result


## The store's parts of this type: Standard, with "price".
static func store_candidates(part_type: String) -> Array:
	var result := []
	for part_id in Store.catalogue(part_type):
		result.append({"part_type": part_type, "part_id": part_id, "grade": Grades.STANDARD, "place": STORE,
				"price": Store.price(part_type, part_id)})
	return result


# ---- building -------------------------------------------------------------

func _build() -> void:
	content.theme_type_variation = &"WindowContentFlush"
	var columns := MechUI.hbox(&"PaneRow")
	content.add_child(columns)

	var left_pane := MechUI.pane(&"PaneDivider")
	left_pane.custom_minimum_size.x = 400
	columns.add_child(left_pane)
	var left := MechUI.vbox(&"PaneStack")
	left_pane.add_child(left)
	var tab_row := MechUI.hbox(&"TabRow")
	for tab in [OWNED, STORE]:
		var button := MechUI.button(tab.to_upper(), &"Tab")
		button.toggle_mode = true
		button.button_group = _tab_group
		button.button_pressed = tab == _tab
		button.pressed.connect(set_tab.bind(tab))
		tab_row.add_child(button)
		_tabs[tab] = button
	left.add_child(MechUI.pane(&"PaneHeader", tab_row))
	var area := MechUI.scroll_box(&"TightStack")
	left.add_child(area[0])
	var back := MechUI.pane(&"ListBack")
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_list = MechUI.vbox(&"ListRows")
	back.add_child(_list)
	area[1].add_child(back)
	_empty = MechUI.label(&"LabelMeta", "", true)
	area[1].add_child(_empty)

	var right := MechUI.scroll_box(&"StatsColumn")
	right[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right[0])
	compare = PartCompare.new()
	right[1].add_child(compare)


func _refresh_list() -> void:
	if _list == null:
		return
	MechUI.clear(_list)
	var part_type := str(subject.get("part_type", ""))
	_entries = []
	if part_type != "":
		if _tab == OWNED:
			_entries = owned_candidates(part_type).filter(func(e): return not _is_subject(e))
		else:
			_entries = store_candidates(part_type)
	for entry in _entries:
		_list.add_child(_make_row(entry))
	_empty.visible = _entries.is_empty()
	_empty.text = EMPTY_OWNED if _tab == OWNED else EMPTY_STORE


# The subject itself: the same part and grade in the same place.
func _is_subject(entry: Dictionary) -> bool:
	return entry.part_id == subject.get("part_id") and entry.grade == Grades.of(subject.get("grade")) \
			and entry.place == subject.get("place")


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("part_id") == b.get("part_id") and a.get("grade") == b.get("grade") and a.get("place") == b.get("place")


func _make_row(entry: Dictionary) -> Button:
	var row := Button.new()
	row.theme_type_variation = &"ContactRow"
	row.toggle_mode = true
	row.button_group = _row_group
	row.button_pressed = _same(entry, candidate)
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = 56
	row.pressed.connect(select_candidate.bind(entry))
	var line := MechUI.hbox(&"BarRow")
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 12
	line.offset_right = -12
	var text := MechUI.vbox()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(MechUI.label(&"LabelBodyBright", PartCompare.display_name(entry)))
	var maker := Manufacturers.short_name(Manufacturers.of_part(PartCompare.part_of(entry)))
	var meta: String = entry.get("where", "") if entry.place != STORE else "%d CT" % int(entry.get("price", 0))
	text.add_child(MechUI.label(&"LabelMeta", "%s · %s" % [maker, meta] if maker != "" else meta))
	line.add_child(text)
	MechUI.ignore_mouse(line)
	if entry.place == STORE and MechOS.is_app_available("net"):
		var link := LinkButton.new()
		link.theme_type_variation = &"NetFavorite"
		link.text = "View on amazing.com"
		link.focus_mode = Control.FOCUS_NONE
		link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		link.pressed.connect(func(): MechOS.open_net(NetSites.product_url(entry.part_type, entry.part_id)))
		line.add_child(link)
	row.add_child(line)
	return row
