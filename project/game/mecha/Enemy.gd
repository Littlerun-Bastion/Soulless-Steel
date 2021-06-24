extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")

var health = 100
var speed = 100
var mov_vec = Vector2()
var moving = false
var final_pos = false
var REACH_RANGE = 10
var logic


func _ready():
	logic = LOGIC.new()
	logic.setup()


func _process(delta):
	var state = logic.get_current_state()
	if has_method("do_"+state):
		call("do_"+state, delta)
		
	logic.updateFiniteLogic(self)


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
	
	
func do_targeting():
	pass


func do_idle(delta):
	pass









 
