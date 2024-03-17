extends Panel

signal inventory_slot_entered(slot)
signal inventory_slot_exited(slot)

@onready var filter = $SlotFilter

var slot_id
var is_mouse_hovering := false
enum States {DEFAULT, FILLED, EMPTY}
var state = States.DEFAULT
var item_stored = null
var slot_type = "inventory_slot"

func set_color(state = States.DEFAULT):
	match state:
		States.DEFAULT:
			filter.color = Color(Color.WHITE, 0.1)
		States.FILLED:
			filter.color = Color(Color.WHITE, 0.5)
		States.EMPTY:
			filter.color = Color(Color.BLACK, 1.0)

func _process(dt):
	if get_global_rect().has_point(get_global_mouse_position()):
		if not is_mouse_hovering:
			is_mouse_hovering = true
			emit_signal("inventory_slot_entered",self)
	else:
		if is_mouse_hovering:
			is_mouse_hovering = false
			emit_signal("inventory_slot_exited",self)
