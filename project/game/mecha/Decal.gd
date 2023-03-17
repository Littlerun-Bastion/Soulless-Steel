extends Sprite2D

const MATERIAL = preload("res://game/mecha/DecalMaterial.tres")
const IMAGES = {
	"bullet_hole_large": preload("res://assets/images/decals/bullet_hole_large.png"),
	"bullet_hole_small": preload("res://assets/images/decals/bullet_hole_small.png"),
}
const USE_DECAL = false

var fade_out_timer = 2.0


func _ready():
	start_fade_out()
	

func setup(type, size, pos):
	assert(IMAGES.has(type),"Not a valid type of decal: " + str(type))
	
	texture = IMAGES[type]
	scale = Vector2(size.x/texture.get_width(), size.y/texture.get_height())
	position = pos


func start_fade_out():
	$Tween.interpolate_property(self, "modulate:a", 1, 0, 1, Tween.TRANS_LINEAR, Tween.EASE_IN, fade_out_timer)
	$Tween.start()
	await $Tween.finished
	queue_free()
