extends Resource
class_name MissionData

var mission_name: String = ""
var mission_description: String = ""
var objectives: Array = []   # array of ObjectiveData

func add_objective(type: String, description: String, target: int = 1) -> ObjectiveData:
	var obj = ObjectiveData.new()
	obj.type = type
	obj.description = description
	obj.target_amount = target
	objectives.append(obj)
	return obj
