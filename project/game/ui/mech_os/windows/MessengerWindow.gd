extends MechWindow
class_name MessengerWindow

## MSG: the Messenger as a MechOS window.
## Contacts on the left, the conversation on the right, replies at the bottom.
## All data lives in the Messenger autoload; this window only draws it and
## sends the player's choices back, so it can close and reopen freely.
## Showing a conversation marks it read.
##
## Layout (built in code, like the stats panel; all spacing is in MechTheme):
##   Columns (PaneRow)
##   ├ Contacts (PaneDivider, 320 wide)
##   │   ├ PaneHeader  "CONTACTS · n"
##   │   ├ Scroll > ListBack > ListRows > ContactRow buttons
##   │   └ PaneFooter  ACTIVE CONTRACT
##   └ Conversation (PaneStack)
##       ├ PaneHeader  name + role
##       ├ Scroll > PaneMargin > MessageList  messages, contract offers
##       └ PaneFooter  REPLY + buttons

const CONTACTS_WIDTH := 320
const ROW_HEIGHT := 64
const ROW_PADDING := 12
const AVATAR_SIZE := 40
const BUBBLE_MAX := 560       # message width before it wraps
const CARD_WIDTH := 460
const CONTRACT_NOTE := "Stays active until done. Progress resets each sortie: meet every objective in one run."

var _current: ContactData = null
var _marking := false
var _row_group := ButtonGroup.new()

var _contacts_title: Label
var _contact_rows: VBoxContainer
var _contract_label: Label
var _name_label: Label
var _role_label: Label
var _message_scroll: ScrollContainer
var _message_list: VBoxContainer
var _reply_footer: PanelContainer
var _reply_flow: HFlowContainer


func _ready() -> void:
	super()
	content.theme_type_variation = &"WindowContentFlush"
	_build_layout()
	Messenger.contacts_changed.connect(_rebuild_contacts)
	Messenger.contact_updated.connect(_on_contact_updated)
	MissionManager.mission_started.connect(_refresh_contract.unbind(1))
	MissionManager.mission_completed.connect(_refresh_contract.unbind(1))
	_refresh_contract()
	_show_contact(_pick_first_contact())


## The contact shown now (null when there are none).
func get_current_contact() -> ContactData:
	return _current


func show_contact(contact: ContactData) -> void:
	_show_contact(contact)


# ---- building -----------------------------------------------------------

func _build_layout() -> void:
	var columns := HBoxContainer.new()
	columns.theme_type_variation = &"PaneRow"
	content.add_child(columns)

	# Contacts column
	var contacts := PanelContainer.new()
	contacts.theme_type_variation = &"PaneDivider"
	contacts.custom_minimum_size.x = CONTACTS_WIDTH
	columns.add_child(contacts)
	var left := MechUI.vbox(&"PaneStack")
	contacts.add_child(left)

	_contacts_title = MechUI.label(&"LabelMeta")
	left.add_child(MechUI.pane(&"PaneHeader", _contacts_title))

	var contact_scroll := MechUI.scroll()
	left.add_child(contact_scroll)
	var back := PanelContainer.new()
	back.theme_type_variation = &"ListBack"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	contact_scroll.add_child(back)
	_contact_rows = VBoxContainer.new()
	_contact_rows.theme_type_variation = &"ListRows"
	back.add_child(_contact_rows)

	var contract_box := VBoxContainer.new()
	contract_box.theme_type_variation = &"TightStack"
	contract_box.add_child(MechUI.label(&"LabelMeta", "ACTIVE CONTRACT"))
	_contract_label = MechUI.label(&"LabelBody")
	_contract_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contract_box.add_child(_contract_label)
	left.add_child(MechUI.pane(&"PaneFooter", contract_box))

	# Conversation column
	var right := MechUI.vbox(&"PaneStack")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	var heading := VBoxContainer.new()
	heading.theme_type_variation = &"TightStack"
	_name_label = MechUI.label(&"LabelTitle")
	_name_label.uppercase = true
	_role_label = MechUI.label(&"LabelMeta")
	_role_label.uppercase = true
	heading.add_child(_name_label)
	heading.add_child(_role_label)
	right.add_child(MechUI.pane(&"PaneHeader", heading))

	_message_scroll = MechUI.scroll()
	right.add_child(_message_scroll)
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"PaneMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_scroll.add_child(margin)
	_message_list = VBoxContainer.new()
	_message_list.theme_type_variation = &"MessageList"
	margin.add_child(_message_list)

	var reply_box := VBoxContainer.new()
	reply_box.theme_type_variation = &"ContractStack"
	reply_box.add_child(MechUI.label(&"LabelMeta", "REPLY"))
	_reply_flow = HFlowContainer.new()
	_reply_flow.theme_type_variation = &"ReplyFlow"
	reply_box.add_child(_reply_flow)
	_reply_footer = MechUI.pane(&"PaneFooter", reply_box)
	right.add_child(_reply_footer)


func _rebuild_contacts() -> void:
	MechUI.clear(_contact_rows)
	_contacts_title.text = "CONTACTS · %d" % Messenger.contacts.size()
	for contact in Messenger.contacts:
		_contact_rows.add_child(_make_row(contact))


func _make_row(contact: ContactData) -> Button:
	var selected := contact == _current
	var row := Button.new()
	row.theme_type_variation = &"ContactRow"
	row.toggle_mode = true
	row.button_group = _row_group
	row.button_pressed = selected
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = ROW_HEIGHT
	row.tooltip_text = contact.name
	# Deferred: showing a contact rebuilds the list, this button included.
	row.pressed.connect(_show_contact.bind(contact), CONNECT_DEFERRED)

	var line := HBoxContainer.new()
	line.theme_type_variation = &"BarRow"
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = ROW_PADDING
	line.offset_top = ROW_PADDING
	line.offset_right = -ROW_PADDING
	line.offset_bottom = -ROW_PADDING
	row.add_child(line)

	var avatar := PanelContainer.new()
	avatar.theme_type_variation = &"AvatarActive" if selected else &"Avatar"
	avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	var initials := MechUI.label(&"LabelMetaBright" if selected else &"LabelMeta", contact.get_initials())
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_child(initials)
	line.add_child(avatar)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := MechUI.label(&"LabelBodyBright" if selected else &"LabelBody", contact.name)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var preview := MechUI.label(&"LabelMeta", _preview_text(contact))
	preview.clip_text = true
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_label)
	text.add_child(preview)
	line.add_child(text)

	if contact.unread > 0:
		var badge := MechUI.label(&"Badge", str(mini(contact.unread, 99)))
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(badge)

	MechUI.ignore_mouse(line)
	return row


func _build_conversation() -> void:
	MechUI.clear(_message_list)
	MechUI.clear(_reply_flow)
	if _current == null:
		_name_label.text = "NO MESSAGES"
		_role_label.visible = false
		_reply_footer.visible = false
		return

	_name_label.text = _current.name
	_role_label.text = _current.role
	_role_label.visible = _current.role != ""

	for message in _current.messages:
		var bubble := _make_bubble(message.text, message.is_player)
		_message_list.add_child(bubble)
		_fit_bubble(bubble.get_child(0))

	var replies := Messenger.get_available_replies(_current)
	for reply in replies:
		if reply.has("mission"):
			_message_list.add_child(_make_contract_card(reply.mission))
	_reply_footer.visible = not replies.is_empty()
	for reply in replies:
		var button := Button.new()
		# Taking a contract is the action that matters: it gets the inverted button.
		button.theme_type_variation = &"ReplyButtonPrimary" if reply.has("mission") else &"ReplyButton"
		button.text = reply.text
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_reply_pressed.bind(_current, reply), CONNECT_DEFERRED)
		_reply_flow.add_child(button)

	MechUI.scroll_to_end(_message_scroll)
	_marking = true
	Messenger.mark_read(_current)
	_marking = false


func _make_bubble(text: String, is_player: bool) -> PanelContainer:
	var bubble := PanelContainer.new()
	bubble.theme_type_variation = &"MessageOut" if is_player else &"MessageIn"
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if is_player else Control.SIZE_SHRINK_BEGIN
	var label := MechUI.label(&"LabelBody", text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(label)
	return bubble


# A wrapping label has no width of its own: give it the text's width, up to
# the cap. Measured in the tree, so the font is the one the label really uses.
func _fit_bubble(label: Label) -> void:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label.custom_minimum_size.x = ceilf(minf(width, BUBBLE_MAX))


func _make_contract_card(mission) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"ContractCard"
	card.custom_minimum_size.x = CARD_WIDTH
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var box := VBoxContainer.new()
	box.theme_type_variation = &"ContractStack"
	card.add_child(box)

	box.add_child(MechUI.label(&"LabelMeta", "CONTRACT OFFER"))
	var title := MechUI.label(&"LabelTitle", mission.mission_name)
	title.uppercase = true
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	if mission.mission_description != "":
		var description := MechUI.label(&"LabelBody", mission.mission_description)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(description)
	var objectives := VBoxContainer.new()
	objectives.theme_type_variation = &"TightStack"
	for obj in mission.objectives:
		var line := MechUI.label(&"LabelBody", "[ ] " + obj.description)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		objectives.add_child(line)
	box.add_child(objectives)
	box.add_child(HSeparator.new())
	var note := MechUI.label(&"LabelMeta", CONTRACT_NOTE)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	return card


# ---- behaviour ----------------------------------------------------------

func _show_contact(contact: ContactData) -> void:
	_current = contact
	_rebuild_contacts()
	_build_conversation()


func _on_contact_updated(contact: ContactData) -> void:
	_rebuild_contacts()
	if contact == _current and not _marking:
		_build_conversation()


func _on_reply_pressed(contact: ContactData, reply: Dictionary) -> void:
	Messenger.choose_reply(contact, reply)


func _refresh_contract() -> void:
	var mission = MissionManager.current_mission
	_contract_label.text = mission.mission_name if MissionManager.has_active_contract() else "None"


# Unread first, so a new message is what the window opens on.
func _pick_first_contact() -> ContactData:
	for contact in Messenger.contacts:
		if contact.unread > 0:
			return contact
	return null if Messenger.contacts.is_empty() else Messenger.contacts[0]


func _preview_text(contact: ContactData) -> String:
	if contact.messages.is_empty():
		return ""
	var last: Dictionary = contact.messages[contact.messages.size() - 1]
	return ("You: " if last.is_player else "") + str(last.text)
