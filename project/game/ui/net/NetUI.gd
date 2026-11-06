class_name NetUI
extends RefCounted

## Builders for NET page parts, like MechUI for MechOS windows. Every node
## gets its look from a Net… type variation in MechTheme, never from
## per-node overrides. Panels pass the mouse on, so the page area's scroll
## wheel works anywhere on a page.

const COUNTER_DIGITS := 6


static func text(value: String, variation: StringName = &"NetBody", wrapped := false) -> Label:
	var node := MechUI.label(variation, value, wrapped)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func heading(value: String) -> Label:
	return text(value, &"NetHeading")


## A PanelContainer in a Net variation, holding child.
static func panel(variation: StringName, child: Control = null) -> PanelContainer:
	var node := MechUI.pane(variation, child)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	return node


static func vbox(variation: StringName = &"NetStack") -> VBoxContainer:
	var node := MechUI.vbox(variation)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	return node


static func hbox(variation: StringName = &"NetToolbar") -> HBoxContainer:
	var node := MechUI.hbox(variation)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	return node


## An underlined link to url (an address, see NetSites) on page. Clicking it
## runs `before` (if given), then follows the link; hovering shows the
## address in the window's status bar.
static func link(page: NetPage, label: String, url: String, dim := false, before := Callable()) -> LinkButton:
	var node := LinkButton.new()
	node.theme_type_variation = &"NetLinkDim" if dim else &"NetLink"
	node.text = label
	node.focus_mode = Control.FOCUS_NONE
	node.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.set_meta("url", url)
	if before.is_valid():
		node.pressed.connect(before)
	node.pressed.connect(page.follow.bind(url))
	node.mouse_entered.connect(page.hover.bind(url))
	node.mouse_exited.connect(page.hover.bind(""))
	return node


## A raised 1999 button; it sinks while pressed.
static func button(label: String) -> Button:
	var node := MechUI.button(label, &"NetButton")
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return node


## A sunken text field. Escape leaves it rather than reaching the screen.
static func input(placeholder := "", width := 0) -> LineEdit:
	var node := LineEdit.new()
	node.theme_type_variation = &"NetInput"
	node.placeholder_text = placeholder
	node.custom_minimum_size.x = width
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.gui_input.connect(func(event: InputEvent):
		if event.is_action_pressed("escape"):
			node.release_focus()
			node.accept_event())
	return node


## The site banner over a dithered ground: the logo and a line under it on
## the left, `right` (a search box, say) on the right.
static func banner(logo: String, tagline: String, right: Control = null) -> PanelContainer:
	var row := hbox(&"NetColumns")
	var left := vbox(&"NetZeroStack")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(text(logo, &"NetLogo"))
	left.add_child(text(tagline, &"NetMeta"))
	row.add_child(left)
	if right != null:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(right)
	var node := panel(&"NetBanner", row)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return node


## A grey tab strip: tabs on the left, right_tabs pushed to the right. Each
## tab is [label, url]; the one at `active` (an index into tabs, then
## right_tabs) shows as the open page's. Returns the strip; each tab Button
## has the meta "url".
static func tab_strip(page: NetPage, tabs: Array, right_tabs: Array = [], active := -1) -> PanelContainer:
	var row := hbox(&"NetZeroRow")
	var all_tabs := tabs + right_tabs
	for index in all_tabs.size():
		if index == tabs.size():
			row.add_child(MechUI.spacer())
		var tab: Array = all_tabs[index]
		var node := MechUI.button(str(tab[0]), &"NetTabActive" if index == active else &"NetTab")
		node.set_meta("url", tab[1])
		node.pressed.connect(page.follow.bind(tab[1]))
		node.mouse_entered.connect(page.hover.bind(tab[1]))
		node.mouse_exited.connect(page.hover.bind(""))
		row.add_child(node)
	return panel(&"NetTabBar", row)


## A framed box with a grey header bar over body.
static func box(title: String, body: Control) -> PanelContainer:
	var column := vbox(&"NetZeroStack")
	column.add_child(panel(&"NetBoxHeader", text(title, &"NetBarText")))
	column.add_child(body)
	return panel(&"NetBox", column)


## A table in a 1 px frame: a grey header row, then striped rows. columns:
## [{"title", "width" (px, 0 = takes the room left), "align" ("right")}].
## rows: an Array of Arrays of cells (a String or a Control each).
## table_rows() gives the row panels, header first.
static func table(columns: Array, rows: Array) -> PanelContainer:
	var node := vbox(&"NetZeroStack")
	var head := hbox(&"NetZeroRow")
	for column in columns:
		head.add_child(_cell(column, text(str(column.get("title", "")).to_upper(), &"NetBarText")))
	node.add_child(panel(&"NetTableHeader", head))
	for i in rows.size():
		node.add_child(table_row(columns, rows[i], i % 2 == 1))
	var frame := panel(&"NetBox", node)
	frame.set_meta("rows", node)
	return frame


## One striped row of a table (see table).
static func table_row(columns: Array, cells: Array, alt: bool) -> PanelContainer:
	var line := hbox(&"NetZeroRow")
	for i in columns.size():
		var cell = cells[i] if i < cells.size() else ""
		var content: Control = cell if cell is Control else text(str(cell))
		line.add_child(_cell(columns[i], content))
	return panel(&"NetRowAlt" if alt else &"NetRow", line)


static func _cell(column: Dictionary, content: Control) -> Control:
	var holder := hbox(&"NetZeroRow")
	var width := int(column.get("width", 0))
	if width > 0:
		holder.custom_minimum_size.x = width
	else:
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.alignment = BoxContainer.ALIGNMENT_END if column.get("align") == "right" else BoxContainer.ALIGNMENT_BEGIN
	if content is Label:
		content.clip_text = true
		content.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if column.get("align") == "right":
			content.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(content)
	return holder


## The row panels of a table from table(), header first.
static func table_rows(table_node: Control) -> Array:
	var rows: Node = table_node.get_meta("rows") if table_node.has_meta("rows") else table_node
	return rows.get_children()


## The dashed "under construction" box: its lines centred, the first bright.
static func construction(lines: Array) -> PanelContainer:
	var column := vbox(&"NetTightStack")
	for i in lines.size():
		var line := text(str(lines[i]), &"NetBodyBright" if i == 0 else &"NetMeta", true)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(line)
	return panel(&"NetNotice", column)


## "You are visitor no. 004217": count in digit cells.
static func hit_counter(count: int, digits := COUNTER_DIGITS) -> PanelContainer:
	var row := hbox(&"NetCounterRow")
	var shown := str(count).pad_zeros(digits)
	for ch in shown:
		row.add_child(panel(&"NetCounterDigit", text(ch, &"NetBodyBright")))
	var node := panel(&"NetCounter", row)
	node.set_meta("digits", shown)
	return node


## A part's sprite at 1:1 in a framed box of box_size; when there's no
## sprite or it doesn't fit, the part's name instead (as ItemUI does).
static func sprite(texture: Texture2D, box_size: Vector2, fallback: String) -> PanelContainer:
	var frame := panel(&"NetSpriteBox")
	frame.custom_minimum_size = box_size
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var inner := box_size - Vector2(2, 2)
	if texture != null and texture.get_width() <= inner.x and texture.get_height() <= inner.y:
		var image := TextureRect.new()
		image.texture = texture
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.set_meta("sprite", true)
		frame.add_child(image)
	else:
		var label := text(fallback.to_upper(), &"ItemName", true)
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		label.set_meta("fallback", true)
		frame.add_child(panel(&"NetBoxBody", label))
	return frame


## A thin S1 rule between parts of a page.
static func rule() -> HSeparator:
	var node := HSeparator.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
