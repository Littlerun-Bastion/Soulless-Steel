extends Mecha


onready var p = "res://game/mecha/Player.gd"

const LOGIC = preload("res://game/mecha/EnemyLogic.gd")

var health = 100
var state = "idle"
var speed = 100
var mov_vec = Vector2()
var moving = false
var final_pos = false
var REACH_RANGE = 10
var logic

func _ready():
	logic = LOGIC.new()
	final_pos = random_pos() 
	
	
func _update():
	pass
	
	
func _process(delta):
	if has_method("do_"+state):	
		call("do_"+state, delta)

	logic.updateFiniteLogic()

func idle_to_roaming(args):
	return true
	
	
func idle_to_targeting(args):
	return false
	
	
func roaming_to_idle(args):
	return false


func roaming_to_targeting(args):
	return false
	
	
func targeting_to_idle(args):
	return false
	
	
func targeting_to_roaming(args):
	return false
	
	
func random_pos():
	return Vector2(rand_range(100, get_viewport_rect().size.x-100), \
				   rand_range(100, get_viewport_rect().size.y-100))

	


func do_roaming(delta):
	
	if not final_pos:
		final_pos = random_pos()

	apply_movement(delta, Vector2(final_pos.x-position.x,\
					   final_pos.y-position.y))
	
	if position.distance_to(final_pos) < REACH_RANGE:
		final_pos = false
	





 
