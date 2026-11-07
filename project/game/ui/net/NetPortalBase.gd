class_name NetPortalBase
extends NetPage

## Building blocks for a NET page in the light portal look (pilot.net's new
## look, PilotNetPortalPage): text in RichTextLabels with working links, link
## buttons, rules, titles, striped tables and part pictures. Every node gets
## its look from a NetPortal… variation in MechTheme; NetPortalLink and
## NetPortalMeta are based on NetWikiLink and NetWikiMeta, whose colours the
## BBCode links and grey text use.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")

## The page's main column, which the page fills.
var main: VBoxContainer


## Every text on the page (tests).
func get_text() -> String:
	var bits := []
	for node in find_children("*", "", true, false):
		if node is RichTextLabel:
			bits.append(node.get_parsed_text())
		elif node is Label or node is LinkButton or node is Button:
			bits.append(node.text)
	return "\n".join(bits)


## Every address the page's links, tabs and buttons go to (tests).
func get_links() -> Array:
	var found := []
	var regex := RegEx.create_from_string("\\[url=([^\\]]+)\\]")
	for node in find_children("*", "", true, false):
		if node is RichTextLabel:
			for match_data in regex.search_all(node.text):
				found.append(match_data.get_string(1))
		elif node is BaseButton and node.has_meta("url"):
			found.append(str(node.get_meta("url")))
	return found


# BBCode in a RichTextLabel whose [url=<address>] links load (and show their
# address while the mouse is over them).
func _rich(bbcode: String) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.theme_type_variation = &"NetPortalRich"
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.selection_enabled = false
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	node.focus_mode = Control.FOCUS_NONE
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.text = bbcode
	node.meta_clicked.connect(func(meta): follow(str(meta)))
	node.meta_hover_started.connect(func(meta): hover(str(meta)))
	node.meta_hover_ended.connect(func(_meta): hover(""))
	return node


func _link_code(text: String, url: String) -> String:
	return "[url=%s][color=%s]%s[/color][/url]" % [url, link_color(), esc(text)]


func _meta_code(text: String) -> String:
	return "[color=%s]%s[/color]" % [meta_color(), esc(text)]


static func link_color() -> String:
	return "#" + THEME.get_color("font_color", "NetWikiLink").to_html(false)


static func meta_color() -> String:
	return "#" + THEME.get_color("font_color", "NetWikiMeta").to_html(false)


static func esc(text: String) -> String:
	return BbsText.esc(text)


func _link(label: String, url: String) -> LinkButton:
	var node := NetUI.link(self, label, url)
	node.theme_type_variation = &"NetPortalLink"
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return node


# A link that runs action instead of loading an address.
func _action_link(label: String, action: Callable) -> LinkButton:
	var node := LinkButton.new()
	node.theme_type_variation = &"NetPortalLink"
	node.text = label
	node.focus_mode = Control.FOCUS_NONE
	node.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.pressed.connect(action)
	return node


func _rule() -> HSeparator:
	var node := HSeparator.new()
	node.theme_type_variation = &"NetPortalRule"
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _title(text: String) -> Label:
	return NetUI.text(text, &"NetPortalTitle", true)


# A part's picture at 1:1, centred in a box of box_size.
func _picture(texture: Texture2D, box_size: Vector2) -> CenterContainer:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = box_size
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var image := TextureRect.new()
	image.texture = texture
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(image)
	return holder


static func _fits(texture: Texture2D, box: Vector2) -> bool:
	return texture != null and texture.get_width() <= box.x and texture.get_height() <= box.y


# A table: a dark header row, then striped rows. columns: [{"title", "width"
# (px; 0 takes the room left), "align" ("right")}]; rows: Arrays of cells, a
# String or a Control each.
func _table(columns: Array, rows: Array) -> VBoxContainer:
	var table := NetUI.vbox(&"NetZeroStack")
	var head := NetUI.hbox(&"NetPortalToolbar")
	for column in columns:
		head.add_child(_cell(column, NetUI.text(str(column.get("title", "")), &"NetPortalBarText")))
	table.add_child(NetUI.panel(&"NetPortalBar", head))
	for i in rows.size():
		var line := NetUI.hbox(&"NetPortalToolbar")
		var cells: Array = rows[i]
		for c in columns.size():
			var value = cells[c] if c < cells.size() else ""
			var content: Control = value if value is Control else NetUI.text(str(value), &"NetPortalText")
			line.add_child(_cell(columns[c], content))
		table.add_child(NetUI.panel(&"NetPortalRowAlt" if i % 2 == 1 else &"NetPortalRow", line))
	table.set_meta("rows", rows.size())
	return table


func _cell(column: Dictionary, content: Control) -> Control:
	var holder := NetUI.hbox(&"NetZeroRow")
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var width := int(column.get("width", 0))
	var right: bool = column.get("align") == "right"
	if width > 0:
		holder.custom_minimum_size.x = width
	else:
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	if content is Label:
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if width > 0:
			content.clip_text = true
			content.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if right:
			content.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	elif content is RichTextLabel:
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(content)
	return holder
