extends Control

const POINTER = preload("res://game/ui/PlayerRadar/Pointer.tscn")
const POINTER_TEXTURES = {
	"far": preload("res://assets/images/ui/player_ui/player_directional_pointer_far.png"),
	"mid": preload("res://assets/images/ui/player_ui/player_directional_pointer_mid.png"),
	"near": preload("res://assets/images/ui/player_ui/player_directional_pointer_near.png"),
}

var player
var range_radius
var pointers

func setup(player_ref, radius):
	clear_pointers()
	player = player_ref
	range_radius = radius
	pointers = []


func update_pointers(mechas):
	#Remove pointers from dead mechas
	var to_delete = []
	for pointer_data in pointers:
		if not mechas.has(pointer_data.mecha):
			pointer_data.pointer.queue_free()
			to_delete.append(pointer_data)
	for pointer in to_delete:
		pointers.erase(pointer)
	
	for mecha in mechas:
		if mecha != player:
			var pos = mecha.get_global_transform_with_canvas().origin
			var pointer = get_mecha_pointer(mecha)
			update_pointer(pointer, pos)


func clear_pointers():
	for pointer in $Pointers.get_children():
		pointer.queue_free()


func get_mecha_pointer(mecha):
	for p in pointers:
		if p.mecha == mecha:
			return p.pointer
	#Doesn't have a pointer
	var p = add_pointer()
	pointers.append({
		"mecha": mecha,
		"pointer": p,
	})
	return p


func add_pointer():
	var pointer = POINTER.instance()
	$Pointers.add_child(pointer)
	
	return pointer


func update_pointer(pointer, target_pos):
	#Rotate
	var angle = rect_position.angle_to_point(target_pos) - PI/2
	pointer.rect_rotation = rad2deg(angle)
	
	var distance = rect_position.distance_to(target_pos)
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
