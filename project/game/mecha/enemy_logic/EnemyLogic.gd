extends RefCounted

# This whole AI logic chain (EnemyLogic → Graphs → Node → behaviour) used to
# extend Node but never gets added to the scene tree, so on NPC death the
# sub-objects orphaned (~16 nodes per NPC accumulated forever).
# RefCounted auto-frees when the holder (Enemy.gd) drops its reference.

const GRAPH = preload("res://game/mecha/enemy_logic/Graphs.gd")
const BEHAVIOUR_PATH = "res://game/mecha/enemy_logic/behaviours/"

# Transition evaluation runs at ~10Hz instead of every physics frame.
# do_<state> still runs every frame (movement/aim stay smooth) — only the
# decision to CHANGE state is throttled. No condition reads single-frame
# state (under_fire lasts 0.5s, sounds have lifetimes, targets persist),
# so <=100ms decision latency is imperceptible and far under the existing
# 2s reaction_speed. Stagger is randomized per NPC so a full population
# doesn't evaluate on the same frame.
const TRANSITION_INTERVAL_MS := 100

var g = GRAPH.new()
var current_state
var behaviour
var _next_eval_ms := 0

func setup(behaviour_name):
	var path = BEHAVIOUR_PATH + str(behaviour_name) + ".gd"
	assert(FileAccess.file_exists(path),"Not a valid enemy behaviour: " + str(behaviour_name))

	_next_eval_ms = Time.get_ticks_msec() + randi() % TRANSITION_INTERVAL_MS
	behaviour = load(path).new()
	
	for node in behaviour.get_nodes():
		g.add_a_node(node)
	
	g.set_state(behaviour.initial_state)
	
	for node_i in behaviour.get_nodes():
		for node_j in behaviour.get_nodes():
			var func_name = node_i+"_to_"+node_j
			if behaviour.has_method(func_name):
				g.add_connection(node_i, node_j, [behaviour, func_name])


func get_current_state():
	current_state = g.get_current_state()
	return g.get_current_state()
	
	
func update(enemy):
	var now = Time.get_ticks_msec()
	if now < _next_eval_ms:
		return
	_next_eval_ms = now + TRANSITION_INTERVAL_MS

	var a_node = g.get_a_node(g.current_state)
	var valid_connection = a_node.get_best_connection(enemy)
	if valid_connection and valid_connection.id != g.current_state:
		g.set_state(valid_connection.id)
		# Entry hook: transition conditions are evaluated every frame for
		# scoring and must stay pure. On-enter mutations (picking targets,
		# claiming loot, etc.) belong in optional enter_<state>(enemy)
		# methods, called exactly once per state change — before this
		# frame's do_<state> runs.
		var hook = "enter_" + str(valid_connection.id)
		if behaviour.has_method(hook):
			behaviour.call(hook, enemy)


func run(enemy, dt):
	var state = get_current_state()
	if behaviour.has_method("do_"+state):
		behaviour.call("do_"+state, dt, enemy)
