extends Control

export var stat_title = ""
export var stat_name = ""

func _ready():
	$Title.text = stat_title

func update_stat(_current_part, new_part):
	var new_stat = new_part.get(stat_name)
	if new_stat:
		$Values/Value.text = "Yes"
	else:
		$Values/Value.text = "No"
