extends CanvasLayer

signal finished

@onready var BlockScreen = $BlockScreen
@onready var CommandLine = $CommandLine
@onready var BlurScreen = $BlurScreen
@onready var VCREffect = $VCREffect
@onready var VCREffect2 = $VCREffect2

var active = false

func _ready():
	BlockScreen.hide()
	BlurScreen.hide()
	VCREffect.hide()
	VCREffect2.hide()


func transition_to(scene_path: String, command_line_text: String):
	if active:
		push_warning("Already has an active transition")
		return
	active = true
	
	BlockScreen.show()
	BlockScreen.color = Color.BLACK
	BlockScreen.color.a = 0.0
	var tween = get_tree().create_tween()
	tween.tween_property(BlockScreen, "color:a", 1.0, .1)
	
	await tween.finished
	
	VCREffect2.show()
	CommandLine.display(command_line_text)
	
	await CommandLine.finished
	
	# warning-ignore:return_value_discarded
	get_tree().change_scene_to_file(scene_path)
	
	await get_tree().process_frame
	
	VCREffect2.hide()
	BlockScreen.color = Color.WHITE
	BlurScreen.show()
	VCREffect.show()
	tween = get_tree().create_tween()
	tween.tween_property(BlockScreen, "color:a", 0.0, .8)
	tween.parallel().tween_method(set_blur_value, 5.0, 0.0, .8)
	set_noise_value(10)
	tween.parallel().tween_method(set_noise_value, 10.0, 2000.0, .8).set_delay(.2)
	
	await tween.finished
	
	BlockScreen.hide()
	BlurScreen.hide()
	VCREffect.hide()
	
	active = false
	emit_signal("finished")


func set_blur_value(value: float):
	BlurScreen.material.set_shader_parameter("lod", value)


func set_noise_value(value: float):
	VCREffect.material.set_shader_parameter("noiseQuality", value);

