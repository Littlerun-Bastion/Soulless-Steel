extends Control


func setup():
	clear_pointers()


func clear_pointers():
	for pointer in $Pointers.get_children():
		pointer.queue_free()


func add_pointer():
	pass
