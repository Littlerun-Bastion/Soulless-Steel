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
