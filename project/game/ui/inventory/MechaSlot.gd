extends Button
@export var type : String
@export var subtype : String
@onready var Tagline = $Tagline


signal mecha_slot_pressed
signal mecha_slot_mouse_entered
signal mecha_slot_mouse_exited

var part_data
# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func change_part(part):
	if part:
		var _type = type
		if type.contains("arm_weapon"):
			_type = "arm_weapon"
		if type.contains("shoulder_weapon"):
			_type = "shoulder_weapon"
		part_data = PartManager.get_part(_type, part)
		if part_data:
			var _icon = part_data.image
			if type.contains("weapon"):
				var img = _icon.get_image()
				img.rotate_90(CLOCKWISE)
				_icon = ImageTexture.create_from_image(img)
				self.set("theme_override_constants/icon_max_width", 250)
			else:
				self.set("theme_override_constants/icon_max_width", 100)
			self.icon = _icon
			Tagline.text = part_data.tagline
		else:
			self.icon = null
			Tagline.text = ""
			part_data = null
	else:
		self.icon = null
		Tagline.text = ""
		part_data = null

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass



func _on_pressed():
	emit_signal("mecha_slot_pressed", self)
	pass # Replace with function body.


func _on_mouse_entered():
	emit_signal("mecha_slot_mouse_entered", self)
	pass # Replace with function body.


func _on_mouse_exited():
	emit_signal("mecha_slot_mouse_exited", self)
	pass # Replace with function body.
