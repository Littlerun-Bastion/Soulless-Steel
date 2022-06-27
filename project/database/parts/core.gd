extends Node

export var weight:= 300
export var heat_dispersion = 20 


func get_image():
	return $Core.texture


func get_collision():
	return $Collision.polygon


func get_sub():
	return $CoreSub.texture


func get_glow():
	return $CoreGlow.texture


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


func get_leg_offset(side):
	if side == "left":
		return $LeftLegOffset.position
	elif side == "right":
		return $RightLegOffset.position
	else:
		push_error("Not a valid side: " + str(side))
