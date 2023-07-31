extends Control


func _ready():
	await get_tree().create_timer(.75).timeout
	
	get_tree().quit()
