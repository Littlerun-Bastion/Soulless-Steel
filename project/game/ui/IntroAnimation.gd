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
const COMMAND_SHOWN := NodePath("IntroAnimation/CommandLine:visible_ratio")
const HEAVY_VCR := NodePath("IntroAnimation/VCREffect:visible")
const LIGHT_VCR := NodePath("IntroAnimation/VCREffect2:visible")
const STATIC_BURST := NodePath("IntroAnimation/Ent_misc4:playing")
const ENDING := &"entrance_animation_ending"
const LINES_DONE_BEFORE_CARD := 1.0
const CARD_READ_TIME := 3.0
const TYPING_SPEED := 50.0
const COMMAND_MARK := "> "
const COMMAND_TYPING_TIME := 1.0
const COMMAND_HOLD := 0.4


## Plays anim_name with other words: text, a line a row, typed out at a steady
## pace from when the usual boot starts typing. A row starting with
## COMMAND_MARK is a command, typed at the bottom before the rows it brings up.
## Then card, up long enough to read before the intro ends. The screen stays
## readable throughout: the light VCR effect only, so no smeared start and no
## static burst clearing it.
func play_retold(anim_name: String, text: String, card: String) -> void:
	var animation: Animation = $AnimationPlayer.get_animation(anim_name).duplicate(true)
	_retell(animation, text.split("\n"), card)
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


func _retell(animation: Animation, rows: PackedStringArray, card: String) -> void:
	var screen := animation.find_track(SCREEN_TEXT, Animation.TYPE_VALUE)
	var command := animation.find_track(COMMAND_TEXT, Animation.TYPE_VALUE)
	var command_shown := animation.find_track(COMMAND_SHOWN, Animation.TYPE_VALUE)
	var start := _first_rise(animation, command_shown)
	_clear_text(animation, screen)
	for track in [command, command_shown]:
		while animation.track_get_key_count(track) > 0:
			animation.track_remove_key(track, 0)
	animation.track_insert_key(command, 0.0, "")
	animation.track_insert_key(command_shown, 0.0, 0.0)
	var card_time := _ending_time(animation) - CARD_READ_TIME
	var busy := 0.0
	for row in rows:
		busy += _row_time(row)
	var pause := maxf(card_time - LINES_DONE_BEFORE_CARD - start - busy, 0.0) / maxf(rows.size() - 1, 1)
	var time := start
	var above := ""
	for row in rows:
		if row.begins_with(COMMAND_MARK):
			animation.track_insert_key(command, time, row.trim_prefix(COMMAND_MARK))
			animation.track_insert_key(command_shown, time, 0.0)
			animation.track_insert_key(command_shown, time + COMMAND_TYPING_TIME, 1.0)
			animation.track_insert_key(command, time + COMMAND_TYPING_TIME + COMMAND_HOLD, "")
		else:
			for typed in range(1, row.length() + 1):
				animation.track_insert_key(screen, time + typed / TYPING_SPEED, above + row.left(typed))
			above += row + "\n"
		time += _row_time(row) + pause
	animation.track_insert_key(screen, card_time, card)


func _row_time(row: String) -> float:
	if row.begins_with(COMMAND_MARK):
		return COMMAND_TYPING_TIME + COMMAND_HOLD
	return row.length() / TYPING_SPEED


func _clear_text(animation: Animation, track: int) -> void:
	var shown := []
	for i in animation.track_get_key_count(track):
		if animation.track_get_key_value(track, i) != "":
			shown.append(animation.track_get_key_time(track, i))
	for i in range(animation.track_get_key_count(track) - 1, -1, -1):
		var time := animation.track_get_key_time(track, i)
		if time >= shown.front() and time <= shown.back():
			animation.track_remove_key(track, i)


func _first_rise(animation: Animation, track: int) -> float:
	for i in animation.track_get_key_count(track) - 1:
		if animation.track_get_key_value(track, i + 1) > animation.track_get_key_value(track, i):
			return animation.track_get_key_time(track, i)
	return 0.0


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
