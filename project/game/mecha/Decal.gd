extends TextureRect

const MATERIAL = preload("res://game/mecha/DecalMaterial.tres")
const IMAGES = {
	"bullet_hole_large": preload("res://assets/images/decals/bullet_hole_large.png"),
	"bullet_hole_small": preload("res://assets/images/decals/bullet_hole_large.png"),
}
const USE_DECAL = false

var fade_out_timer = 2.0


func _ready():
	start_fade_out()
	

func setup(type, size, pos, mask_texture, mask_scale):
	assert(IMAGES.has(type), "Not a valid type of decal: " + str(type))
	
	texture = IMAGES[type]
	rect_size = size
	rect_position = pos - size/2
	
	if not USE_DECAL:
		material = null
	else:
		material = MATERIAL.duplicate()
		material.set_shader_param("mask", mask_texture)
		material.set_shader_param("offset", rect_position)
		material.set_shader_param("size", size*get_global_transform().get_scale())
		material.set_shader_param("mask_size", mask_texture.get_size()*mask_scale)

func start_fade_out():
	$Tween.interpolate_property(self, "modulate:a", 1, 0, 1, Tween.TRANS_LINEAR, Tween.EASE_IN, fade_out_timer)
	$Tween.start()
	yield($Tween, "tween_completed")
	queue_free()
