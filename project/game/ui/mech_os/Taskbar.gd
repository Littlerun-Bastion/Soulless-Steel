extends Panel

var buttons: Dictionary = {}  # app_id -> Button

@onready var button_list: VBoxContainer = $ButtonList


func add_app_button(app_id: String, label: String) -> void:
	if buttons.has(app_id):
		return
	
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(40, 40)
	btn.tooltip_text = label
	btn.pressed.connect(_on_app_button_pressed.bind(app_id))
	
	button_list.add_child(btn)
	buttons[app_id] = btn


func remove_app_button(app_id: String) -> void:
	if not buttons.has(app_id):
		return
	buttons[app_id].queue_free()
	buttons.erase(app_id)


func _on_app_button_pressed(app_id: String) -> void:
	MechOS.toggle_app(app_id)
