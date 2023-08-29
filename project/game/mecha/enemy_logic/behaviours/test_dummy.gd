extends Node

const POSITIONAL_ACCURACY = 400.0
const THROTTLE_CHANGE_TIME = 1.0

#Essential variables
var nodes = ["roam", "seek", "alert", "alert_roam", "ambush", "ambush_lock", "in_combat", "attack", "defend"]
var initial_state = "roam"

#Custom variables
var engage_distance = 2000
var min_kite_distance = 1500
var max_kite_distance = 1700
var cqb_distance = 1200
var max_shooting_distance = 3500
var weapon_heat_threshold = 0.75
var general_heat_threshold = 0.9
var cooldown_time = 6.0
var barrage_min_time = 2.0
var reaction_speed = 2


var point_of_interest
var cooldown_timer = 0.0
var barrage_timer = 0.0
var lock_timer = 0.0
var aggression = 0
var aiming_at_enemy = false
var reaction_timer = 0.0

func get_nodes():
	return nodes

## CONNECTION METHODS ##

func do_roam(dt, enemy):
	pass
