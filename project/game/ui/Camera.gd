extends Camera2D

# The offset is the sum of two parts: pan_offset, which the player's camera
# pan writes (Player.update_camera_offset), and shake_offset, which the shake
# tweens. A shake never moves the pan: it tweens shake_offset round zero and
# back, and the offset follows both every frame.
#
# On a map with a MapBounds, the camera never shows past the map's edge: each
# frame, after the pan, the shake and the zoom, the offset is clamped so the
# whole view rectangle stays inside MapBounds.map_rect. A view wider (or
# taller) than the map is centred on it on that axis. Camera2D's own limits
# can't do this: they don't apply to the offset.

## Frames between look-ups of the map's MapBounds while there is none.
const BOUNDS_LOOKUP_FRAMES := 30

var amp = 0
var priority = 0
var tweens = []
var pan_offset := Vector2.ZERO
var shake_offset := Vector2.ZERO

var _bounds: MapBounds = null
var _bounds_lookup := 0


func _process(_delta: float) -> void:
	var total := clamp_to_map(pan_offset + shake_offset)
	if offset != total:
		offset = total


## `wanted` (an offset) moved so the view stays inside the map's bounds;
## unchanged on a map with no MapBounds.
func clamp_to_map(wanted: Vector2) -> Vector2:
	var bounds := _map_bounds()
	if bounds == null:
		return wanted
	var view := get_viewport_rect().size / zoom
	var centre := view_centre_in(bounds.global_map_rect(), global_position + wanted, view)
	return centre - global_position


## Where a view of `view` px centred on `centre` must be centred to stay
## inside `map`: clamped on each axis, or the map's centre on an axis where
## the view is the larger.
static func view_centre_in(map: Rect2, centre: Vector2, view: Vector2) -> Vector2:
	var out := centre
	var half := view * 0.5
	for axis in 2:
		if view[axis] >= map.size[axis]:
			out[axis] = map.get_center()[axis]
		else:
			out[axis] = clampf(centre[axis], map.position[axis] + half[axis], map.end[axis] - half[axis])
	return out


func _map_bounds() -> MapBounds:
	if is_instance_valid(_bounds) and _bounds.is_inside_tree():
		return _bounds
	_bounds = null
	_bounds_lookup -= 1
	if _bounds_lookup > 0:
		return null
	_bounds_lookup = BOUNDS_LOOKUP_FRAMES
	_bounds = MapBounds.find(self)
	return _bounds


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
