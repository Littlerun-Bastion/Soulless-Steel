extends Resource
class_name ContactData

var name: String = ""
var avatar: Texture2D = null
var messages: Array = []
var pending_replies: Array = []

func add_message(text: String, is_player: bool = false) -> void:
	messages.append({
		"text": text,
		"is_player": is_player
	})

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
