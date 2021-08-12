extends TextureRect

const IMAGES = {
	"bullet_hole": preload("res://assets/images/decals/bullet_hole.png"),
}


func _ready():
	pass
	

func setup(type, size):
	assert(IMAGES.has(type), "Not a valid type of decal: " + str(type))
	
	texture = IMAGES[type]
	rect_size = size


