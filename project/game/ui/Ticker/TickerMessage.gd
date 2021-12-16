extends RichTextLabel


func start_death_timer(dur):
	yield(get_tree().create_timer(dur), "timeout")
	queue_free()
