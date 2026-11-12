extends Control

@onready var Logo = $Logo

func _ready():
	FileManager.load_game()
	if FileManager.profile_created:
		StoryDirector.set_flag(Onboarding.DONE_FLAG, false)
	
	AudioManager.play_sfx("startup")
	Logo.modulate.a = 0.0
	
	await get_tree().create_timer(.5).timeout
	
	var tween = create_tween()
	tween.tween_property(Logo, "modulate:a", 1.0, .3)
	
	await tween.finished
	await get_tree().create_timer(2.0).timeout
	
	var next := Onboarding.SCENE_PATH if Onboarding.is_due() else Onboarding.MENU_PATH
	TransitionManager.transition_to(next, "Booting System.........")
