extends CanvasLayer

@onready var contact_list: VBoxContainer = $Root/Sidebar/SidebarLayout/ContactScroll/ContactList
@onready var contact_name: Label = $Root/ConversationPanel/ConversationLayout/ContactHeader/ContactName
@onready var message_container: VBoxContainer = $Root/ConversationPanel/ConversationLayout/MessageScroll/MessageContainer
@onready var reply_options: VBoxContainer = $Root/ConversationPanel/ConversationLayout/ReplyPanel/ReplyOptions

var current_contact = null
var contacts = []

func _ready() -> void:
	await get_tree().process_frame
	
	var root = $Root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = get_viewport().get_visible_rect().size
	
	var sidebar = $Root/Sidebar
	var conversation = $Root/ConversationPanel
	
	# Sidebar takes left 25% of screen
	sidebar.set_anchors_preset(Control.PRESET_FULL_RECT)
	sidebar.anchor_right = 0.25
	
	# Conversation takes remaining 75%
	conversation.set_anchors_preset(Control.PRESET_FULL_RECT)
	conversation.anchor_left = 0.25
	
	var sidebar_style = StyleBoxFlat.new()
	sidebar_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	sidebar.add_theme_stylebox_override("panel", sidebar_style)
	
	var conversation_style = StyleBoxFlat.new()
	conversation_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	conversation.add_theme_stylebox_override("panel", conversation_style)
	
	hide()
	await get_tree().process_frame

func toggle() -> void:
	visible = not visible

func add_contact(contact) -> void:
	print("add_contact called: ", contact.name)
	contacts.append(contact)
	call_deferred("_build_contact_list")

func _build_contact_list() -> void:
	print("_build_contact_list called | contacts: ", contacts.size())
	for child in contact_list.get_children():
		child.queue_free()
	for contact in contacts:
		print("creating button for: ", contact.name)
		var btn = Button.new()
		btn.text = contact.name
		btn.custom_minimum_size = Vector2(200, 50)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.pressed.connect(_on_contact_pressed.bind(contact))
		contact_list.add_child(btn)

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
