extends "res://game/mecha/enemy_logic/BaseBehaviour.gd"

# Cautious variant: keeps its distance, reacts deliberately, and cools/shields
# early. Same state machine as default — only tunables differ. Assign via an
# NPC's combat_behaviour = "cautious".
#
# Note: for sniper/brawler/artillery builds, _get_effective_distances() derives
# ranges from the weapon loadout, so the kite/shoot overrides below mainly bite
# on balanced builds; reaction_speed and the heat thresholds always apply.

func _init():
	min_kite_distance = 1800    # hold a wider band — fight at arm's length
	max_kite_distance = 2100
	max_shooting_distance = 2200
	reaction_speed = 3          # more deliberate aim/fire
	weapon_heat_threshold = 0.6   # stop firing to cool sooner
	general_heat_threshold = 0.8  # shield / back off earlier
