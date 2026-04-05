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

func add_reply_option(text: String, next_replies: Array = [], mission = null) -> Dictionary:
	var reply = {
		"text": text,
		"next_replies": next_replies,
	}
	if mission:
		reply["mission"] = mission
	pending_replies.append(reply)
	return reply
