extends CanvasLayer

@onready var contact_list: VBoxContainer = $Root/Sidebar/SidebarLayout/ContactScroll/ContactList
@onready var contact_name: Label = $Root/ConversationPanel/ConversationLayout/ContactHeader/ContactName
@onready var message_container: VBoxContainer = $Root/ConversationPanel/ConversationLayout/MessageScroll/MessageContainer
@onready var reply_options: VBoxContainer = $Root/ConversationPanel/ConversationLayout/ReplyPanel/ReplyOptions

var current_contact = null
var contacts = []

func _set_full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0

func _ready() -> void:
	await get_tree().process_frame

	# Root fills viewport
	var root = $Root
	_set_full_rect(root)
	root.size = get_viewport().get_visible_rect().size

	# Sidebar takes left 25%
	var sidebar = $Root/Sidebar
	sidebar.anchor_left = 0.0
	sidebar.anchor_top = 0.0
	sidebar.anchor_right = 0.25
	sidebar.anchor_bottom = 1.0
	sidebar.offset_left = 0
	sidebar.offset_top = 0
	sidebar.offset_right = 0
	sidebar.offset_bottom = 0
	sidebar.mouse_filter = Control.MOUSE_FILTER_PASS

	# SidebarLayout fills sidebar
	var sidebar_layout = $Root/Sidebar/SidebarLayout
	_set_full_rect(sidebar_layout)
	sidebar_layout.mouse_filter = Control.MOUSE_FILTER_PASS

	# ContactScroll expands to fill remaining space in sidebar
	var contact_scroll = $Root/Sidebar/SidebarLayout/ContactScroll
	contact_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contact_scroll.mouse_filter = Control.MOUSE_FILTER_PASS

	# Conversation takes right 75%
	var conversation = $Root/ConversationPanel
	conversation.anchor_left = 0.25
	conversation.anchor_top = 0.0
	conversation.anchor_right = 1.0
	conversation.anchor_bottom = 1.0
	conversation.offset_left = 0
	conversation.offset_top = 0
	conversation.offset_right = 0
	conversation.offset_bottom = 0

	# ConversationLayout fills conversation panel
	var conversation_layout = $Root/ConversationPanel/ConversationLayout
	_set_full_rect(conversation_layout)

	# MessageScroll expands to fill conversation
	var message_scroll = $Root/ConversationPanel/ConversationLayout/MessageScroll
	message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Styles
	var sidebar_style = StyleBoxFlat.new()
	sidebar_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	sidebar.add_theme_stylebox_override("panel", sidebar_style)

	var conversation_style = StyleBoxFlat.new()
	conversation_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	conversation.add_theme_stylebox_override("panel", conversation_style)

	# Root should not block input when hidden
	$Root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Rebuild contact list now that layout is correct
	_build_contact_list()

	hide()

func toggle() -> void:
	visible = not visible
	$Root.mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE

func add_contact(contact) -> void:
	contacts.append(contact)
	call_deferred("_build_contact_list")

func _build_contact_list() -> void:
	for child in contact_list.get_children():
		child.queue_free()
	for contact in contacts:
		var btn = Button.new()
		btn.text = contact.name
		btn.custom_minimum_size = Vector2(200, 50)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", Color.WHITE)
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
		btn.add_theme_stylebox_override("normal", btn_style)
		contact_list.add_child(btn)
		btn.pressed.connect(_on_contact_pressed.bind(contact))

func _on_contact_pressed(contact) -> void:
	current_contact = contact
	contact_name.text = contact.name
	_build_messages()

func _build_messages() -> void:
	for child in message_container.get_children():
		child.queue_free()
	for message in current_contact.messages:
		var label = Label.new()
		label.text = message.text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		if message.is_player:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		message_container.add_child(label)
	_build_reply_options()

func _build_reply_options() -> void:
	for child in reply_options.get_children():
		child.queue_free()
	if current_contact.pending_replies.is_empty():
		return
	for reply in current_contact.pending_replies:
		var btn = Button.new()
		btn.text = reply.text
		btn.pressed.connect(_on_reply_pressed.bind(reply))
		reply_options.add_child(btn)

func _on_reply_pressed(reply) -> void:
	current_contact.messages.append({
		"text": reply.text,
		"is_player": true
	})
	current_contact.pending_replies = reply.next_replies if reply.has("next_replies") else []
	if reply.has("mission"):
		MissionManager.start_mission(reply.mission)
	_build_messages()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_messenger"):
		toggle()
		get_viewport().set_input_as_handled()
