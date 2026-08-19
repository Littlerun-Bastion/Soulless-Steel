extends "res://game/mecha/enemy_logic/BaseBehaviour.gd"

# Aggressive variant: notices targets sooner, fights close, reacts fast, and
# keeps firing when hotter. Same state machine as default — only tunables
# differ. Assign via an NPC's combat_behaviour = "aggressive".
#
# Note: for sniper/brawler/artillery builds, _get_effective_distances() derives
# ranges from the weapon loadout, so the kite/shoot overrides below mainly bite
# on balanced builds; reaction_speed and the heat thresholds always apply.

func _init():
	engage_distance = 2200      # spot and commit from farther out
	min_kite_distance = 1000    # hold a tighter band — press the enemy
	max_kite_distance = 1200
	cqb_distance = 1400
	reaction_speed = 1          # snappier aim/fire
	weapon_heat_threshold = 0.85  # tolerate more heat before ceasing fire
