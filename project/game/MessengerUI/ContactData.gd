extends Resource
class_name ContactData

## One person in the Messenger. Build it, then hand it to Messenger.add_contact.
## After that, post new lines with Messenger.post_message so the window and
## the MSG badge update.

var name: String = ""
## One line under the name in the conversation header, e.g. "FIXER · HELWAN CONTRACTS".
var role: String = ""
## Not drawn yet: the contact tile shows initials. Kept for later.
var avatar: Texture2D = null
var messages: Array = []         # {"text": String, "is_player": bool}
var pending_replies: Array = []  # see add_reply_option
## Their messages the player hasn't seen. Showing the conversation clears it.
var unread: int = 0


func add_message(text: String, is_player: bool = false) -> void:
	messages.append({
		"text": text,
		"is_player": is_player
	})
	if not is_player:
		unread += 1


# story_effects / requires use the StoryDirector dictionary shapes.
func add_reply_option(text: String, next_replies: Array = [], mission = null,
		story_effects: Dictionary = {}, requires: Dictionary = {}) -> Dictionary:
	var reply = {
		"text": text,
		"next_replies": next_replies,
	}
	if mission:
		reply["mission"] = mission
	if not story_effects.is_empty():
		reply["story_effects"] = story_effects
	if not requires.is_empty():
		reply["requires"] = requires
	pending_replies.append(reply)
	return reply


## "Lady Volk" -> "LV", "Quartermaster" -> "QU".
func get_initials() -> String:
	var words := name.strip_edges().split(" ", false)
	if words.is_empty():
		return "?"
	if words.size() == 1:
		return words[0].left(2).to_upper()
	return (words[0].left(1) + words[words.size() - 1].left(1)).to_upper()


## The last line in the conversation, for the contact list.
func get_last_text() -> String:
	return "" if messages.is_empty() else str(messages[messages.size() - 1].text)
