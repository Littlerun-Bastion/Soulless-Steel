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

@onready var LadderButtons = $ScrollContainer/LadderButtons
@onready var LeaderboardName = $LeaderboardsName
@onready var LeaderboardTier = $LeaderboardsName/Tier
@onready var OpponentsLabel = $ColorRect/VBoxContainer/Opponents/Label2

@onready var PayoutScreen = $PayoutScreen
@onready var BasePayout = $PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer/Label2
@onready var WinPayout = $PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer2/Label2
@onready var ConductPayout = $PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer3/Label2
@onready var ConductKills = $PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer4/Label2
@onready var ConductPerformance = $PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer5/Label2
@onready var PayoutTotal = $PayoutScreen/VBoxContainer2/HBoxContainer/Label3
@onready var Balance = $PayoutScreen/VBoxContainer2/HBoxContainer2/Label3

@onready var RepairsCost = $PayoutScreen/VBoxContainer/VBoxContainer/HBoxContainer/Label2
@onready var AmmoCost = $PayoutScreen/VBoxContainer/VBoxContainer/HBoxContainer2/Label2

var selected_challenger

func _ready():
	setup_leaderboards(1)
	if ArenaManager.last_match_unread:
		if ArenaManager.last_match:
			BasePayout.text = str(ArenaManager.last_match.payout)
			if ArenaManager.last_match.win:
				WinPayout.text = str(ArenaManager.last_match.payout)
			ConductPayout.text = str(ArenaManager.last_match.conduct)
			if ArenaManager.last_match.conduct_kill_deduction > 0:
				$PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer4.visible = true
				ConductKills.text = str("-" + str(ArenaManager.last_match.conduct_kill_deduction))
				$PayoutScreen/VBoxContainer/VBoxContainer2/KillWarning.visible = true
			else:
				$PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer4.visible = false
				$PayoutScreen/VBoxContainer/VBoxContainer2/KillWarning.visible = false
			
			if ArenaManager.last_match.conduct_downs_reward > 0:
				$PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer5.visible = true
				ConductPerformance.text = str(ArenaManager.last_match.conduct_downs_reward)
			else:
				$PayoutScreen/VBoxContainer/VBoxContainer2/HBoxContainer5.visible = false
			var balance = Profile.get_stat("money") + ArenaManager.last_match.total_payout
			Profile.set_stat("money", balance)
			Balance.text = Profile.get_stat("money")
			AmmoCost.text = str(ArenaManager.last_match.total_ammo_cost)
			PayoutTotal.text = str(ArenaManager.last_match.total_payout)
		ArenaManager.last_match_unread = false
		PayoutScreen.visible = true
		$StartMatch.disabled = true


func setup_leaderboards(lb_idx):
	var lb_data = LEADERBOARDS[lb_idx]
	var lb = Profile.get_leaderboard(lb_data.id)
	#Setup ladder buttons
	var idx = 0
	for child in LadderButtons.get_children():
		child.set_mecha_name(lb[idx])
		idx += 1
		child.set_ranking(idx)
		child.connect("ladderlabel_pressed", Callable(self,"on_ladderlabel_pressed"))
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
	TransitionManager.transition_to("res://game/arena/Arena.tscn", "Initializing Combat Simulation...")


func start_match():
	start_game("main")


func on_ladderlabel_pressed(selected_mecha):
	selected_challenger = selected_mecha
	#$VBoxContainer2/Button.disabled = false
	for child in LadderButtons.get_children():
		if child.Name.text == selected_mecha:
			child.press()
		else:
			child.unpress()


func set_challenge_mode():
	ArenaManager.mode = "Challenge"
	ArenaManager.current_challengers = [selected_challenger]
	OpponentsLabel.text = str("'" + selected_challenger + "'")
	for child in LadderButtons.get_children():
		if child.Name.text == selected_challenger:
			child.press()
		else:
			child.unpress()
	$VBoxContainer2/Button.disabled = true


func set_exhibition_mode():
	ArenaManager.mode = "Exhibition"
	OpponentsLabel.text = str("'" + str(ArenaManager.exhibitioner_count) + " PARTICIPANTS'")
	$StartMatch.visible 


func _on_Dismiss_pressed():
	PayoutScreen.visible = false
