extends Area2D

var damage_mul

func setup(pos : Vector2, radius : float, dmg_mul : float, dur : float):
	position = pos
	self.damage_mul = dmg_mul
	$Timer.wait_time = dur
	$CollisionShape2D.shape.radius = radius


func _on_Timer_timeout():
	queue_free()
