extends Control

const LEADERBOARDS =[
	{
		"id": "civ-grade",
		"name": "Civ-Grade",
		"tier": "C-Tier",
	},
	{
		"id": "mil-grade",
		"name": "Mil-Grade",
		"tier": "B-Tier",
	},
	{
		"id": "state-of-the-art",
		"name": "State-of-the-Art",
		"tier": "A-Tier",
	}
]

@onready var LadderButtons = $LadderButtons
@onready var LeaderboardName = $LeaderboardsName
@onready var LeaderboardTier = $LeaderboardsName/Tier

func _ready():
	setup_leaderboards(1)


func setup_leaderboards(lb_idx):
	var lb_data = LEADERBOARDS[lb_idx]
	var lb = Profile.get_leaderboard(lb_data.id)
	#Setup ladder buttons
	var idx = 0
	for child in LadderButtons.get_children():
		child.set_mecha_name(lb[idx])
		idx += 1
		child.set_ranking(idx)
	#Setup labels
	LeaderboardName.text = lb_data.name
	LeaderboardTier.text = lb_data.tier

func start_game(mode):
	AudioManager.stop_bgm()
	PlayerStatManager.NumberofExtracts = 0
	PlayerStatManager.Credits = 0
	match mode:
		"main":
			ArenaManager.set_map_to_load("arena_oldgate")
		"tutorial":
			ArenaManager.set_map_to_load("tutorial")
		"test":
			ArenaManager.set_map_to_load("test_buildings")
		_:
			push_error("Not a valid mode: " + str(mode))
	ShaderEffects.play_transition(5000.0, 0, 0.5)
	# warning-ignore:return_value_discarded
	get_tree().change_scene_to_file("res://game/arena/Arena.tscn")

func start_match():
	start_game("main")
	pass # Replace with function body.
