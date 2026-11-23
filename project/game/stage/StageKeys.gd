class_name StageKeys

const ACTION_TOKEN := r"\{(\w+)\}"


static func expand(text: String) -> String:
	var result := text
	for found: RegExMatch in RegEx.create_from_string(ACTION_TOKEN).search_all(text):
		var action: String = found.get_string(1)
		if InputMap.has_action(action):
			result = result.replace(found.get_string(0), "[%s]" % MechUI.key_name(action))
	return result
