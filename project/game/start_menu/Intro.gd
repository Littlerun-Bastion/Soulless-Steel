extends Control

@onready var Logo = $Logo

func _ready():
	FileManager.load_game()
	
	AudioManager.play_sfx("startup")
	Logo.modulate.a = 0.0
	
	await get_tree().create_timer(.5).timeout
	
	var tween = create_tween()
	tween.tween_property(Logo, "modulate:a", 1.0, .3)
	
	await tween.finished
	await get_tree().create_timer(2.0).timeout
	
	TransitionManager.transition_to("res://game/start_menu/StartMenu.tscn", "Booting System.........")
