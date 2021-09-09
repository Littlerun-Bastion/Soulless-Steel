extends TextureRect

const IMAGES = {
	"bullet_hole": preload("res://assets/images/decals/bullet_hole.png"),
}

var fade_out_timer = 2.0


func _ready():
	start_fade_out()
	

func setup(type, size, pos, mask_texture):
	assert(IMAGES.has(type), "Not a valid type of decal: " + str(type))
	
	texture = IMAGES[type]
	rect_size = size
	rect_position = pos
	
	material.set_shader_param("mask", mask_texture)
	material.set_shader_param("offset", pos)
	material.set_shader_param("mask_size", size)
	material.set_shader_param("mask_size", mask_texture.get_size())

func start_fade_out():
	$Tween.interpolate_property(self, "modulate:a", 1, 0, 1, Tween.TRANS_LINEAR, Tween.EASE_IN, fade_out_timer)
	$Tween.start()
	yield($Tween, "tween_completed")
	queue_free()
