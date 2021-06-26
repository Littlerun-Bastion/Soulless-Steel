extends Mecha

const LOGIC = preload("res://game/mecha/enemy_logic/EnemyLogic.gd")

var health = 100
var speed = 100
var mov_vec = Vector2()
var moving = false
var final_pos = false
var REACH_RANGE = 10
var logic
var id
var all_enemies
var valid_target = false
var engage_distance = 100
var shooting_distance = 50

func _ready():
	logic = LOGIC.new()
	logic.setup()


func _process(delta):
	var state = logic.get_current_state()
	if has_method("do_"+state):
		call("do_"+state, delta)
		
	logic.updateFiniteLogic(self)
	
	check_for_targets()

func random_pos():
	randomize()
	return Vector2(rand_range(100, get_viewport_rect().size.x-100), \
				   rand_range(100, get_viewport_rect().size.y-100))


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
	apply_movement(delta, Vector2(valid_target.x-position.x,\
					   valid_target.y-position.y))


func do_idle(delta):
	pass


func set_id_and_enemies(_all_enemies, _id):
	id = _id
	all_enemies = _all_enemies


func check_for_targets():
	var closest_target = all_enemies[0]
	var shortest_distance = 1000000
	var target_to_return
	
	for target in all_enemies:
		shortest_distance = min(target.position.distance_to(self.position), shortest_distance)
		if target.position.distance_to(self.position) == shortest_distance:
			target_to_return = target
		
	if shortest_distance < abs(engage_distance):
		valid_target = target_to_return
	else:
		valid_target = false


 
