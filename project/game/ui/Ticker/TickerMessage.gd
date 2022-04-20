extends RichTextLabel


func start_death_timer(dur):
	var temp_timer = Timer.new()
	add_child(temp_timer)
	temp_timer.start(dur); yield(temp_timer, "timeout")
	queue_free()
