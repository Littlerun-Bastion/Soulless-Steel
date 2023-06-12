extends Control

@onready var LadderButtons = $LadderButtons


func _ready():
	setup_leaderboards("mil-grade")


func setup_leaderboards(lb_name):
	var lb = Profile.get_leaderboard(lb_name)
	var idx = 0
	for child in LadderButtons.get_children():
		child.set_mecha_name(lb[idx])
		idx += 1
		child.set_ranking(idx)
