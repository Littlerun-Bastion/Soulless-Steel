extends CanvasLayer

signal finished

@onready var BlockScreen = $BlockScreen
@onready var CommandLine = $CommandLine
@onready var BlurScreen = $BlurScreen
@onready var VCREffect = $VCREffect
@onready var VCREffect2 = $VCREffect2

var sound_repeat_time = 0.1
var sound_tick = 0.0

var active = false
var play_sound = false

func _ready():
	BlockScreen.hide()
	BlurScreen.hide()
	VCREffect.hide()
	VCREffect2.hide()
	
func _process(dt):
	if play_sound:
		if sound_tick >= sound_repeat_time:
			AudioManager.play_sfx("rapid_beep")
			sound_tick = 0.0
		else:
			sound_tick += dt

func transition_to(scene_path: String, command_line_text: String):
	if active:
		#push_warning("Already has an active transition, aborting " + str(scene_path))
		return
	active = true
	
	BlockScreen.show()
	BlockScreen.color = Color.BLACK
	BlockScreen.color.a = 0.0
	var tween = create_tween()
	tween.tween_property(BlockScreen, "color:a", 1.0, .1)
	
	await tween.finished
	play_sound = true
	VCREffect2.show()
	CommandLine.display(command_line_text)
	
	await CommandLine.finished
	
	# warning-ignore:return_value_discarded
	get_tree().change_scene_to_file(scene_path)
	AudioManager.play_sfx("low_tone")
	
	await get_tree().process_frame
	
	play_sound = false
	VCREffect2.hide()
	BlockScreen.color = Color.WHITE
	BlurScreen.show()
	VCREffect.show()
	tween = create_tween()
	tween.tween_property(BlockScreen, "color:a", 0.0, .8)
	tween.parallel().tween_method(set_blur_value, 5.0, 0.0, .8)
	set_noise_value(10)
	tween.parallel().tween_method(set_noise_value, 10.0, 2000.0, .8).set_delay(.2)
	
	await tween.finished
	
	BlockScreen.hide()
	BlurScreen.hide()
	VCREffect.hide()
	
	emit_signal("finished")
	active = false


func set_blur_value(value: float):
	BlurScreen.material.set_shader_parameter("lod", value)


func set_noise_value(value: float):
	VCREffect.material.set_shader_parameter("noiseQuality", value);
