extends Control

const POINTER = preload("res://game/ui/PlayerRadar/Pointer.tscn")
const POINTER_TEXTURES = {
	"far": preload("res://assets/images/ui/player_ui/player_directional_pointer_far.png"),
	"mid": preload("res://assets/images/ui/player_ui/player_directional_pointer_mid.png"),
	"near": preload("res://assets/images/ui/player_ui/player_directional_pointer_near.png"),
}

var player
var mechas
var range_radius
var pointers
var update_cooldown


func _process(_dt):
	if player and visible:
		rect_position = player.get_global_transform_with_canvas().origin
		clear_dead_mechas()
		if not update_cooldown:
			update_mecha_position()	
		update_pointers()


func setup(mechas_ref, player_ref, radius, update_timer):
	clear_pointers()
	mechas = mechas_ref
	player = player_ref
	range_radius = radius
	if update_timer:
		update_cooldown = true
		$UpdateTimer.wait_time = update_timer
		$UpdateTimer.start()
	pointers = []


func update_mecha_position():
	for p in pointers:
		p.target_position = p.mecha.global_position


func clear_dead_mechas():
	var to_delete = []
	for pointer_data in pointers:
		if not mechas.has(pointer_data.mecha):
			pointer_data.pointer.queue_free()
			to_delete.append(pointer_data)
	for pointer in to_delete:
		pointers.erase(pointer)


func update_pointers():	
	for mecha in mechas:
		if mecha != player:
			update_pointer(get_mecha_pointer(mecha))


func clear_pointers():
	for pointer in $Pointers.get_children():
		pointer.queue_free()


func get_mecha_pointer(mecha):
	for p in pointers:
		if p.mecha == mecha:
			return p
	#Doesn't have a pointer
	var p = add_pointer()
	var pointer_data = {
		"mecha": mecha,
		"pointer": p,
		"target_position": mecha.global_position,
	}
	pointers.append(pointer_data)
	return pointer_data


func add_pointer():
	var pointer = POINTER.instance()
	$Pointers.add_child(pointer)
	
	return pointer


func update_pointer(pointer_data):
	var target_pos = pointer_data.target_position
	var pointer = pointer_data.pointer
	
	#Rotate
	var angle = player.global_position.angle_to_point(target_pos) - PI/2
	pointer.rect_rotation = rad2deg(angle)
	
	var distance = player.global_position.distance_to(target_pos)
	if distance > range_radius:
		pointer.modulate.a = 0.0
	else:
		pointer.modulate.a = 1.0
		if distance > .6*range_radius:
			pointer.texture = POINTER_TEXTURES.far
		elif distance > .3*range_radius:
			pointer.texture = POINTER_TEXTURES.mid
		else:
			pointer.texture = POINTER_TEXTURES.near


func _on_UpdateTimer_timeout():
	var t_scale = Vector2(.6,.6)
	$Tween.interpolate_property($Circle, "rect_scale", Vector2(1,1), t_scale, .1, Tween.TRANS_CUBIC, Tween.EASE_IN)
	$Tween.start()
	yield($Tween, "tween_completed")
	update_mecha_position()
	$Tween.interpolate_property($Circle, "rect_scale", t_scale, Vector2(1,1), .5, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	$Tween.start()
	
	
