extends Control

@onready var contact_list: VBoxContainer = $Sidebar/SidebarLayout/ContactScroll/ContactList
@onready var contact_name: Label = $ConversationPanel/ConversationLayout/ContactHeader/ContactName
@onready var message_container: VBoxContainer = $ConversationPanel/ConversationLayout/MessageScroll/MessageContainer
@onready var reply_options: VBoxContainer = $ConversationPanel/ConversationLayout/ReplyPanel/ReplyOptions

var current_contact = null
var contacts = []

func _ready() -> void:
	hide()

func toggle() -> void:
	visible = not visible

func add_contact(contact_data) -> void:
	contacts.append(contact_data)
	_build_contact_list()

func _build_contact_list() -> void:
	for child in contact_list.get_children():
		child.queue_free()
	for contact in contacts:
		var btn = Button.new()
		btn.text = contact.name
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
