extends Resource
class_name ObjectiveData

var type: String = ""        # "kill", "extract", "reach_location"
var description: String = "" # e.g. "Kill 3 enemies"
var target_amount: int = 1   # how many needed to complete
var current_amount: int = 0  # current progress
var completed: bool = false
