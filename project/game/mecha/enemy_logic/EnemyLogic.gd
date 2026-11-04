extends RefCounted

# The AI engine of one NPC: it holds the behaviour (BaseBehaviour or a
# variant) and decides which of its intents runs. The whole chain
# (EnemyLogic → Graphs → Node → behaviour) is RefCounted and never in the
# scene tree, so it is freed with the Enemy that holds it.
#
# Two kinds of behaviour run here:
#   - Intent behaviours (BaseBehaviour and its variants) give every intent a
#     score_<intent>(enemy) -> float. On each evaluation every intent is
#     scored, the current one gets COMMIT_BONUS, and the highest wins. A
#     switch is refused for MIN_INTENT_TIME s after the last one unless the
#     winner beats the current intent by OVERRIDE_MARGIN, so the NPC doesn't
#     flip-flop between two intents that score alike. exit_<intent> and
#     enter_<intent> hooks run once on a switch, before the new intent's
#     do_<intent> runs.
#   - Transition behaviours (idle, test_dummy, anything older) keep the
#     pairwise <a>_to_<b>(enemy) -> priority methods, evaluated through the
#     graph as before.
# Both evaluate every TRANSITION_INTERVAL_MS of real time (not every physics
# frame), staggered per NPC so a whole population doesn't evaluate on the same
# frame. do_<intent> runs on every thinking frame, so movement and aim stay
# smooth. Score functions must stay pure and cheap: they read the NPC's
# knowledge and never cast rays or scan the scene tree.

const GRAPH = preload("res://game/mecha/enemy_logic/Graphs.gd")
const BEHAVIOUR_PATH = "res://game/mecha/enemy_logic/behaviours/"

const TRANSITION_INTERVAL_MS := 100
## Added to the current intent's score so a rival must beat it clearly.
## Placeholder.
const COMMIT_BONUS := 0.1
## Seconds (game time) an intent is held after a switch unless a rival beats
## it by OVERRIDE_MARGIN. Placeholders.
const MIN_INTENT_TIME := 1.0
const OVERRIDE_MARGIN := 0.15
## How many of the top scores are kept for the debug overlay.
const TOP_SCORES := 3

var g = GRAPH.new()
var behaviour
var _next_eval_ms := 0
## The behaviour's intents that have a score_ method (empty for a
## transition behaviour).
var intents: Array = []
## Intent -> its score at the last evaluation, without the commitment bonus.
var scores := {}
## The TOP_SCORES best [intent, score] pairs of the last evaluation.
var last_scores: Array = []
## Seconds (game time) spent in the current intent.
var intent_time := 0.0


func setup(behaviour_name):
	var path = BEHAVIOUR_PATH + str(behaviour_name) + ".gd"
	assert(FileAccess.file_exists(path),"Not a valid enemy behaviour: " + str(behaviour_name))

	_next_eval_ms = Time.get_ticks_msec() + randi() % TRANSITION_INTERVAL_MS
	behaviour = load(path).new()
	g = GRAPH.new()
	intents.clear()
	scores.clear()
	last_scores.clear()
	intent_time = 0.0

	for node in behaviour.get_nodes():
		g.add_a_node(node)
		if behaviour.has_method("score_" + str(node)):
			intents.append(node)

	g.set_state(behaviour.initial_state)

	for node_i in behaviour.get_nodes():
		for node_j in behaviour.get_nodes():
			var func_name = node_i+"_to_"+node_j
			if behaviour.has_method(func_name):
				g.add_connection(node_i, node_j, [behaviour, func_name])


func get_current_state():
	return g.get_current_state()


## Whether this behaviour decides by intent scores.
func uses_intents() -> bool:
	return not intents.is_empty()


func update(enemy):
	var now = Time.get_ticks_msec()
	if now < _next_eval_ms:
		return
	_next_eval_ms = now + TRANSITION_INTERVAL_MS
	if uses_intents():
		_evaluate_intents(enemy)
	else:
		_evaluate_transitions(enemy)


func run(enemy, dt):
	intent_time += dt
	var state = get_current_state()
	if behaviour.has_method("do_"+state):
		behaviour.call("do_"+state, dt, enemy)


## Switches to `intent` now, running the exit and enter hooks (tests and
## scripted set-ups).
func force_intent(enemy, intent: String) -> void:
	_switch(enemy, intent)


## Scores every intent now, whatever the clock says (tests).
func evaluate_now(enemy) -> void:
	_next_eval_ms = 0
	update(enemy)


func _evaluate_intents(enemy) -> void:
	var current: String = str(g.current_state)
	var best := current
	var best_score := -INF
	var current_score := -INF
	for intent in intents:
		var s: float = float(behaviour.call("score_" + intent, enemy))
		scores[intent] = s
		if intent == current:
			# A tie keeps the current intent. An intent that scores nothing
			# gets no commitment: it is done.
			current_score = s + (COMMIT_BONUS if s > 0.0 else 0.0)
			if current_score >= best_score:
				best_score = current_score
				best = intent
		elif s > best_score:
			best_score = s
			best = intent
	_keep_top_scores()
	if best == current:
		return
	if intent_time < MIN_INTENT_TIME and best_score < current_score + OVERRIDE_MARGIN:
		return
	_switch(enemy, best)


func _switch(enemy, intent: String) -> void:
	var previous: String = str(g.current_state)
	if behaviour.has_method("exit_" + previous):
		behaviour.call("exit_" + previous, enemy)
	AICombatLog.record_intent_change(enemy, previous, intent, intent_time)
	g.set_state(intent)
	intent_time = 0.0
	# Entry hook: scores are evaluated every time for ranking and must stay
	# pure. On-enter mutations (picking targets, claiming loot...) belong in
	# enter_<intent>(enemy), called exactly once per switch, before this
	# frame's do_<intent> runs.
	if behaviour.has_method("enter_" + intent):
		behaviour.call("enter_" + intent, enemy)


func _keep_top_scores() -> void:
	var pairs: Array = []
	for intent in scores:
		pairs.append([intent, scores[intent]])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	last_scores = pairs.slice(0, TOP_SCORES)


func _evaluate_transitions(enemy) -> void:
	var a_node = g.get_a_node(g.current_state)
	var valid_connection = a_node.get_best_connection(enemy)
	if valid_connection and valid_connection.id != g.current_state:
		_switch(enemy, valid_connection.id)
