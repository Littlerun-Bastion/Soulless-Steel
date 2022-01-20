extends Node

export var image: Resource
export var collision: PoolVector2Array
export var weight:= 300
export var head_offset := Vector2(0, 0)
export var left_shoulder_offset := Vector2(-10, 10)
export var right_shoulder_offset := Vector2(10, 10)
export var head_port : Resource
export var head_port_offset := Vector2()


func get_image():
	return $Core.texture


func get_collision():
	return $Collision.polygon


func get_head_port():
	return $HeadPort.texture


func get_head_port_offset():
	return $HeadOffset.position


func get_shoulder_offset(side):
	if side == "left":
		return $LeftShoulderOffset.position
	elif side == "right":
		return $RightShoulderOffset.position
	else:
		push_error("Not a valid side: " + str(side))
