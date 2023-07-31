extends Sprite2D

const MATERIAL = preload("res://game/mecha/DecalMaterial.tres")
const IMAGES = {
	"bullet_hole_large": preload("res://assets/images/decals/bullet_hole_large.png"),
	"bullet_hole_small": preload("res://assets/images/decals/bullet_hole_small.png"),
}
const USE_DECAL = false

var fade_out_timer = 2.0


func _ready():
	await get_tree().create_timer(fade_out_timer).timeout
	start_fade_out()
	

func setup(type, size, pos):
	assert(IMAGES.has(type),"Not a valid type of decal: " + str(type))
	
	texture = IMAGES[type]
	scale = Vector2(size.x/texture.get_width(), size.y/texture.get_height())
	position = pos


func start_fade_out():
	var tween = create_tween()
	modulate.a = 1.0
	tween.tween_property(self, "modulate:a", 0.0, 1)
	tween.tween_callback(self.queue_free)
