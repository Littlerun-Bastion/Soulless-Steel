extends Control

@export var stat_title = ""
@export var stat_name = ""

func _ready():
	$Title.text = stat_title

func update_stat(current_part, new_part):
	var current_stat
	var new_stat = new_part.get(stat_name)
	var stat_diff
	if current_part:
		current_stat = current_part.get(stat_name)
	if not current_stat:
		$Values/Increments.visible = false
	if current_stat and new_stat > current_stat:
		$Values/Increments.visible = true
		stat_diff = new_stat - current_stat
		$Values/Value.text = str(new_stat)
		if stat_diff > current_stat * 0.25:
			$Values/Increments.text = "[+++]"
		elif stat_diff > current_stat * 0.1:
			$Values/Increments.text = "[++]"
		else:
			$Values/Increments.text = "[+]"
	elif current_stat and new_stat < current_stat:
		$Values/Increments.visible = true
		$Values/Value.text = str(new_stat)
		stat_diff = current_stat - new_stat
		if stat_diff > current_stat * 0.25:
			$Values/Increments.text = "[---]"
		elif stat_diff > current_stat * 0.1:
			$Values/Increments.text = "[--]"
		else:
			$Values/Increments.text = "[-]"
	else:
		$Values/Increments.visible = false
		$Values/Value.text = str(new_stat)
		stat_diff = 0
