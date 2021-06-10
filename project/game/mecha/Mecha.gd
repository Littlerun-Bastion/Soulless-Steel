extends KinematicBody2D
class_name Mecha

const ARM_WEAPON_INITIAL_ROT = 9

var movement_type = "free"
var velocity = Vector2()
var max_speed = 200
var friction = 0.1
var move_acc = 50
var rotation_acc = 5

var arm_weapon_left = null
var arm_weapon_right = null
var shoulder_weapon_left = null
var shoulder_weapon_right = null
