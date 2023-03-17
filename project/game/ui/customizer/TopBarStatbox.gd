extends Control

@export var stat_name = ""
@export var stat_label = ""

var compared_part = false

func _ready():
	$TitleLabel.text = stat_label

func reset_comparison(mecha):
	$TitleLabel.text = stat_label
	compared_part = false
	$IncreaseIndicator.visible = false
	if stat_name:
		var stat_value = mecha.get_stat(stat_name)
		$StatLabelMain.text = str(stat_value)
		

func set_comparing_part(mecha, diff_mecha):
	$TitleLabel.text = stat_label
	compared_part = true
	if stat_name:
		var diff_stat_value = diff_mecha.get_stat(stat_name)
		var stat_value = mecha.get_stat(stat_name)
		var stat_difference
		if mecha.get_stat(stat_name) and mecha.get_stat(stat_name) != diff_stat_value:
			$IncreaseIndicator.visible = true
			if diff_stat_value > stat_value:
				stat_difference = diff_stat_value - stat_value
				brackets(stat_value, stat_difference, true)
				$StatLabelMain.text = str(str(diff_stat_value) + "*")
			else:
				stat_difference = stat_value - diff_stat_value
				brackets(stat_value, stat_difference, false)
				$StatLabelMain.text = str(str(diff_stat_value) + "*")
			if stat_name == "max_speed":
				if diff_mecha.is_overweight:
					$StatLabelMain.text = $StatLabelMain.text + "!"
		else:
			$IncreaseIndicator.visible = false
		
func brackets(stat, stat_difference, is_positive):
	if stat_difference > stat * 0.25:
		if is_positive:
			$IncreaseIndicator.text = "[+++]"
		else:
			$IncreaseIndicator.text = "[---]"
	elif stat_difference > stat * 0.1:
		if is_positive:
			$IncreaseIndicator.text = "[++]"
		else:
			$IncreaseIndicator.text = "[--]"
	else:
		if is_positive:
			$IncreaseIndicator.text = "[+]"
		else:
			$IncreaseIndicator.text = "[-]"
