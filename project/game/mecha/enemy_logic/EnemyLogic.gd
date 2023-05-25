extends Node

const BEHAVIOUR_PATH = "res://game/mecha/enemy_logic/behaviours/"
const GOAL_PATH = "res://game/mecha/enemy_logic/goals/"
const ACTION_PATH = "res://game/mecha/enemy_logic/actions/"

var goals = []
var actions = []
var blackboard = {
	"enemy_nearby": false,
}
var current_goal
var current_plan
var current_plan_step = 0


func setup(behaviour_name):
	var path = BEHAVIOUR_PATH + str(behaviour_name) + ".gd"
	assert(FileAccess.file_exists(path),"Not a valid enemy behaviour: " + str(behaviour_name))
	
	var behaviour = load(path).new()
	
	for goal in behaviour.get_goals():
		goals.append(instance_goal(goal))
	for action in behaviour.get_action():
		actions.append(instance_action(action))


func instance_goal(goal_name):
	var path = GOAL_PATH + str(goal_name) + ".gd"
	assert(FileAccess.file_exists(path),"Not a valid goal: " + str(goal_name))
	return load(path).new()


func instance_action(action_name):
	var path = ACTION_PATH + str(action_name) + ".gd"
	assert(FileAccess.file_exists(path),"Not a valid action: " + str(action_name))
	return load(path).new()


func update(agent, dt):
	var goal = ActionPlanner.get_best_goal(goals)
	if current_goal == null or goal != current_goal:
	# You can set in the blackboard any relevant information you want to use
	# when calculating action costs and status. I'm not sure here is the best
	# place to leave it, but I kept here to keep things simple.
		var blackboard = {
			"position": _actor.position,
			}

		for s in WorldState._state:
			blackboard[s] = WorldState._state[s]

		_current_goal = goal
		_current_plan = Goap.get_action_planner().get_plan(_current_goal, blackboard)
		_current_plan_step = 0
	else:
		run_current_plan(agent, dt)


func run_current_plan(agent, dt):
	if current_plan.size() == 0:
		return

	var is_step_complete = current_plan[current_plan_step].perform(agent, dt)
	if is_step_complete and current_plan_step < current_plan.size() - 1:
		current_plan_step += 1
