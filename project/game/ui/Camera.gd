extends Camera2D

# The offset is the sum of two parts: pan_offset, which the player's camera
# pan writes (Player.update_camera_offset), and shake_offset, which the shake
# tweens. A shake never moves the pan: it tweens shake_offset round zero and
# back, and the offset follows both every frame.

var amp = 0
var priority = 0
var tweens = []
var pan_offset := Vector2.ZERO
var shake_offset := Vector2.ZERO


func _process(_delta: float) -> void:
	var total := pan_offset + shake_offset
	if offset != total:
		offset = total


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
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "shake_offset", target, $Frequency.wait_time)
	tweens.append(tween)


func stop_shake():
	for tween in tweens:
		tween.kill()
	tweens = []
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "shake_offset", Vector2(), $Frequency.wait_time/2)
	tweens.append(tween)
	priority = 0

func _on_Duration_timeout():
	stop_shake()
	$Frequency.stop()


func _on_Frequency_timeout():
	new_shake()
