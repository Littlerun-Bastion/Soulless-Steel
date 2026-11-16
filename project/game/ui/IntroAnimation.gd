extends Node2D

signal animation_ending


func _input(event):
	if event.is_action_pressed("skip"):
		if $AnimationPlayer.is_playing():
			stop_animation()


func play(anim_name):
	$EntranceSound.volume_db = 0
	$AnimationPlayer.play(anim_name)


const RETOLD := "retold"
const SCREEN_TEXT := NodePath("IntroAnimation/ScreenText:text")
const COMMAND_TEXT := NodePath("IntroAnimation/CommandLine:text")
const HEAVY_VCR := NodePath("IntroAnimation/VCREffect:visible")
const LIGHT_VCR := NodePath("IntroAnimation/VCREffect2:visible")
const STATIC_BURST := NodePath("IntroAnimation/Ent_misc4:playing")
const ENDING := &"entrance_animation_ending"
const LINES_DONE_BEFORE_CARD := 1.0
const CARD_READ_TIME := 3.0
const TYPING_SPEED := 50.0


## Plays anim_name with other words: its screen text typed out at a steady
## pace, then card, up long enough to read before the intro ends; its commands
## in order, on the same timing. The screen stays readable throughout: the
## light VCR effect only, so no smeared start and no static burst clearing it.
func play_retold(anim_name: String, text: String, card: String, commands: Array) -> void:
	var animation: Animation = $AnimationPlayer.get_animation(anim_name).duplicate(true)
	_retell_screen(animation, text.split("\n"), card)
	_retell_commands(animation, commands)
	_keep_readable(animation)
	var library: AnimationLibrary = $AnimationPlayer.get_animation_library("")
	if library.has_animation(RETOLD):
		library.remove_animation(RETOLD)
	library.add_animation(RETOLD, animation)
	play(RETOLD)


## Moves the boot's text in from the screen's bottom-left corner.
func inset_text(by: Vector2) -> void:
	for label in [$ScreenText, $CommandLine]:
		label.position += Vector2(by.x, -by.y)


func _retell_screen(animation: Animation, lines: PackedStringArray, card: String) -> void:
	var track := animation.find_track(SCREEN_TEXT, Animation.TYPE_VALUE)
	var shown := []
	for i in animation.track_get_key_count(track):
		if animation.track_get_key_value(track, i) != "":
			shown.append(animation.track_get_key_time(track, i))
	var start: float = shown.front()
	for i in range(animation.track_get_key_count(track) - 1, -1, -1):
		var time := animation.track_get_key_time(track, i)
		if time >= start and time <= shown.back():
			animation.track_remove_key(track, i)
	var card_time := _ending_time(animation) - CARD_READ_TIME
	var typing := "".join(lines).length() / TYPING_SPEED
	var pause := maxf(card_time - LINES_DONE_BEFORE_CARD - start - typing, 0.0) / maxf(lines.size() - 1, 1)
	var time := start
	for i in lines.size():
		var above := "".join(Array(lines.slice(0, i)).map(func(line): return line + "\n"))
		for typed in range(1, lines[i].length() + 1):
			animation.track_insert_key(track, time + typed / TYPING_SPEED, above + lines[i].left(typed))
		time += lines[i].length() / TYPING_SPEED + pause
	animation.track_insert_key(track, card_time, card)


func _ending_time(animation: Animation) -> float:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_METHOD:
			continue
		for i in animation.track_get_key_count(track):
			if animation.method_track_get_name(track, i) == ENDING:
				return animation.track_get_key_time(track, i)
	return animation.length


func _keep_readable(animation: Animation) -> void:
	var heavy := animation.find_track(HEAVY_VCR, Animation.TYPE_VALUE)
	for i in animation.track_get_key_count(heavy):
		animation.track_set_key_value(heavy, i, false)
	var light := animation.find_track(LIGHT_VCR, Animation.TYPE_VALUE)
	for i in animation.track_get_key_count(light):
		animation.track_set_key_value(light, i, animation.track_get_key_time(light, i) < animation.length)
	animation.track_set_enabled(animation.find_track(STATIC_BURST, Animation.TYPE_VALUE), false)


func _retell_commands(animation: Animation, commands: Array) -> void:
	var track := animation.find_track(COMMAND_TEXT, Animation.TYPE_VALUE)
	var next := 0
	for i in animation.track_get_key_count(track):
		if animation.track_get_key_value(track, i) != "" and next < commands.size():
			animation.track_set_key_value(track, i, commands[next])
			next += 1


func stop_animation():
	var dur = 1.0
	$AnimationPlayer.stop(true)
	var tween = create_tween()
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
