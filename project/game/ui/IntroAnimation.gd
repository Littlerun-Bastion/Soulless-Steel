extends Node2D

signal animation_ending


func _input(event):
	if event.is_action_pressed("skip"):
		if $AnimationPlayer.is_playing():
			stop_animation()


func play(name):
	$EntranceSound.volume_db = 0
	$AnimationPlayer.play(name)


func stop_animation():
	var dur = 1.0
	$AnimationPlayer.stop(true)
	$Tween.interpolate_property($BG, "modulate", null, Color(1,1,1,0), dur)
	$Tween.interpolate_property($CommandLine, "percent_visible", null, 0, dur)
	$Tween.interpolate_property($ScreenText, "percent_visible", null, 0, dur)
	$Tween.interpolate_property($EntranceSound, "volume_db", null, -60, dur)
	$VCREffect.hide()
	$VCREffect2.hide()
	$Tween.start()
	entrance_animation_ending()


func entrance_animation_ending():
	emit_signal("animation_ending")
