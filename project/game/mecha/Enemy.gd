extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")

var health = 100
var speed = 100
var mov_vec = Vector2()
var moving = false
var final_pos = false
var REACH_RANGE = 10
var logic
var all_enemies
var valid_target = false
var engage_distance = 500
var shooting_distance = 50
var current_state
var move_d_rand = 100


func _ready():
	logic = LOGIC.new()
	logic.setup()


func _process(delta):
	var state = logic.get_current_state()
	
	check_for_targets()
	
	if has_method("do_"+state):
		call("do_"+state, delta)
		
	logic.updateFiniteLogic(self)
	

func random_pos():
	randomize()
	return Vector2(rand_range(move_d_rand, get_viewport_rect().size.x-move_d_rand),\
				   rand_range(move_d_rand, get_viewport_rect().size.y-move_d_rand))


func random_pos_targeting():
	randomize()
	var v_closeness = Vector2()
	
	if position.x - valid_target.position.x < 0:
		v_closeness.x = -100
	else:
		v_closeness.x = 100
	
	if position.x - valid_target.position.y < 0:
		v_closeness.y = -100
	else:
		v_closeness.y = 100
	
	return Vector2(rand_range(max(move_d_rand, valid_target.position.x-move_d_rand+v_closeness.x),\
				   min(get_viewport_rect().size.x-move_d_rand, valid_target.position.x+move_d_rand+v_closeness.x)),\
				   
				   rand_range(max(move_d_rand, valid_target.position.y-move_d_rand+v_closeness.y),\
				   min(get_viewport_rect().size.y-move_d_rand, valid_target.position.y+move_d_rand+v_closeness.y)))


func do_roaming(delta):
	if not final_pos:
		final_pos = random_pos()

	apply_movement(delta, Vector2(final_pos.x-position.x,\
					   final_pos.y-position.y))
	
	if position.distance_to(final_pos) < REACH_RANGE:
		final_pos = false
		
	if not valid_target:
		check_for_targets()
	
	
func do_targeting(delta):
	var enemy_area =  random_pos_targeting()
	
	self.apply_rotation(delta, valid_target.position, false)
	
	apply_movement(delta, Vector2(enemy_area.x-self.position.x,\
								  enemy_area.y-self.position.y))


func do_idle(delta):
	pass


func set_id_and_enemies(_all_enemies, _id):
	id = _id
	all_enemies = _all_enemies


func check_for_targets():
	var shortest_distance = 10000
	var target_to_return
	
	for target in all_enemies:
		if target.id != self.id:
			shortest_distance = min(target.position.distance_to(self.position), shortest_distance)
			if target.position.distance_to(self.position) == shortest_distance:
				target_to_return = target
		
	if abs(shortest_distance) < engage_distance:
		valid_target = target_to_return
	else:
		valid_target = false


 
