extends Node2D

signal animation_ending


func _input(event):
	if event.is_action_pressed("skip"):
		if $AnimationPlayer.is_playing():
			stop_animation()


func play(anim_name):
	$EntranceSound.volume_db = 0
	$AnimationPlayer.play(anim_name)


func stop_animation():
	var dur = 1.0
	$AnimationPlayer.stop(true)
	var tween = get_tree().create_tween()
	tween.set_parallel()
	tween.tween_property($BG, "modulate", Color(1,1,1,0), dur)
	tween.tween_property($CommandLine, "visible_ratio", 0, dur)
	tween.tween_property($ScreenText, "visible_ratio", 0, dur)
	tween.tween_property($EntranceSound, "volume_db", -60, dur)
	$VCREffect.hide()
	$VCREffect2.hide()
	entrance_animation_ending()


func entrance_animation_ending():
	emit_signal("animation_ending")
