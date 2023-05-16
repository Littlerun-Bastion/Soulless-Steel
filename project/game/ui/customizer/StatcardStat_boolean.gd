extends Control

@export var stat_title = ""
@export var stat_name = ""

func _ready():
	$Title.text = stat_title

func update_stat(current_part, new_part):
	var current_stat = current_part.get(stat_name)
	var new_stat = new_part.get(stat_name)
	if new_stat:
		if not current_stat:
			$Values/Increments.text = "[+]"
		else:
			$Values/Increments.text = ""
		$Values/Value.text = "Yes"
	else:
		if current_stat:
			$Values/Increments.text = "[-]"
		else:
			$Values/Increments.text = ""
		$Values/Value.text = "No"
		
