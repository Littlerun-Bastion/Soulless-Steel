extends Resource
class_name MissionData

var mission_name: String = ""
var mission_description: String = ""
var objectives: Array = []   # array of ObjectiveData
var story_effects: Dictionary = {}  # applied by StoryDirector on completion
var completed: bool = false
# Contracts are accepted outside a match (e.g. in the messenger) and stay
# active across sorties until completed; scene default missions don't replace
# them. Set by MissionManager.accept_contract.
var is_contract: bool = false

func add_objective(type: String, description: String, target: int = 1) -> ObjectiveData:
	var obj = ObjectiveData.new()
	obj.type = type
	obj.description = description
	obj.target_amount = target
	objectives.append(obj)
	return obj
