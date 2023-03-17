extends Camera2D

var amp = 0
var priority = 0

func shake(duration := 0.2, frequency := 15, amplitude := 16, prio := 0):
	if priority > prio or frequency <= 0:
		return
	priority = prio
	amp = amplitude
	
	$Duration.wait_time = duration
	$Frequency.wait_time = 1/float(frequency)
	new_shake()
	$Duration.start()
	$Frequency.start()

func new_shake():
	var target = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	$Tween.interpolate_property(self, "offset", offset, target, $Frequency.wait_time, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	$Tween.start()


func stop_shake():
	$Tween.stop_all()
	$Tween.interpolate_property(self, "offset", offset, Vector2(), $Frequency.wait_time/2, Tween.TRANS_QUAD, Tween.EASE_OUT)
	$Tween.start()
	priority = 0

func _on_Duration_timeout():
	stop_shake()
	$Frequency.stop()


func _on_Frequency_timeout():
	new_shake()
