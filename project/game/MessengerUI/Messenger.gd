extends Node

## Messenger: the contacts and conversations (autoload "Messenger").
## Holds the data only. The window is MechOS's MSG app
## (game/ui/mech_os/windows/MessengerWindow), which reads from here and
## follows the signals below, so the conversations survive the window
## closing and scene changes.
##
## Other systems talk to it with:
##   add_contact(contact)              a new ContactData (ignored if the name exists)
##   post_message(name, text)          a new line from that contact (counts as unread)
##   get_contact(name) / has_contact(name)
## The window calls choose_reply() and mark_read().
##
## Replies: picking one adds it as the player's line, replaces the pending
## replies with its "next_replies", accepts its "mission" as a contract and
## applies its "story_effects". Replies with "requires" stay hidden until
## StoryDirector.meets() them.

signal contacts_changed               # a contact was added
signal contact_updated(contact)       # messages, replies or unread changed
signal unread_changed(total: int)

var contacts: Array = []  # of ContactData, in the order added


func _ready() -> void:
	# A frame first, so the other autoloads (StoryDirector, MechOS) exist
	# whatever order project.godot lists them in.
	await get_tree().process_frame
	# Replies can be gated on story state.
	StoryDirector.state_changed.connect(_on_story_changed)
	_update_badge()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_messenger"):
		MechOS.toggle_app("messenger")
		get_viewport().set_input_as_handled()


# ---- contacts -----------------------------------------------------------

func add_contact(contact: ContactData) -> void:
	if has_contact(contact.name):
		push_warning("Messenger already has a contact named '%s', ignoring duplicate" % contact.name)
		return
	contacts.append(contact)
	if contact.unread > 0:
		MechLog.write("MSG", "New message from %s" % contact.name)
	contacts_changed.emit()
	_update_badge()


func has_contact(name_to_find: String) -> bool:
	return get_contact(name_to_find) != null


func get_contact(name_to_find: String) -> ContactData:
	for contact in contacts:
		if contact.name == name_to_find:
			return contact
	return null


func post_message(contact_name: String, text: String) -> void:
	var contact := get_contact(contact_name)
	if contact == null:
		push_warning("Messenger: no contact named '%s' for: %s" % [contact_name, text])
		return
	contact.add_message(text)
	MechLog.write("MSG", "New message from %s" % contact.name)
	_changed(contact)


# ---- replies ------------------------------------------------------------

## The pending replies the story allows right now.
func get_available_replies(contact: ContactData) -> Array:
	var result := []
	for reply in contact.pending_replies:
		if StoryDirector.meets(reply.get("requires", {})):
			result.append(reply)
	return result


func choose_reply(contact: ContactData, reply: Dictionary) -> void:
	contact.add_message(reply.text, true)
	contact.pending_replies = reply.get("next_replies", [])
	if reply.has("mission"):
		MissionManager.accept_contract(reply.mission)
		MechLog.write("MSG", "Contract accepted: %s" % reply.mission.mission_name)
	if reply.has("story_effects"):
		StoryDirector.apply_effects(reply.story_effects)  # may emit contact_updated again
	_changed(contact)


# ---- unread -------------------------------------------------------------

func mark_read(contact: ContactData) -> void:
	if contact.unread == 0:
		return
	contact.unread = 0
	_changed(contact)


func get_unread_total() -> int:
	var total := 0
	for contact in contacts:
		total += contact.unread
	return total


# ---- internal -----------------------------------------------------------

func _changed(contact: ContactData) -> void:
	contact_updated.emit(contact)
	_update_badge()


func _update_badge() -> void:
	var total := get_unread_total()
	unread_changed.emit(total)
	MechOS.taskbar.set_badge("messenger", total)


func _on_story_changed() -> void:
	for contact in contacts:
		contact_updated.emit(contact)
