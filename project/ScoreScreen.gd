extends Control

onready var VCRTween = $ShaderEffects/Tween
onready var VCREffect = $ShaderEffects/VCREffect
var RArmTotal = 0
var LArmTotal = 0
var RShdTotal = 0
var LShdTotal = 0


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	$PlayerKills.text = "Player Kills: " + str(PlayerStatManager.PlayerKills)
	PlayerStatManager.Credits = PlayerStatManager.PlayerKills * 25000.0 * (1.0 + (PlayerStatManager.PlayerKills/10.0))
	
	$PlayerKills.text = "Player Kills: " + str(PlayerStatManager.PlayerKills)
	$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
	if typeof(PlayerStatManager.RArmAmmo) == TYPE_INT:
		$VBoxContainer2/RightArmBox/RightArmAmmo.text = str(PlayerStatManager.RArmAmmo) +"/"+ str(PlayerStatManager.RArmAmmoMax)
		RArmTotal = (PlayerStatManager.RArmAmmoMax - PlayerStatManager.RArmAmmo) * PlayerStatManager.RArmCost
		$VBoxContainer2/RACost.text = str(RArmTotal) + "C"
	if typeof(PlayerStatManager.LArmAmmo) == TYPE_INT:
		$VBoxContainer2/LeftArmBox/LeftArmAmmo.text = str(PlayerStatManager.LArmAmmo)+"/"+str(PlayerStatManager.LArmAmmoMax)
		LArmTotal = (PlayerStatManager.LArmAmmoMax - PlayerStatManager.LArmAmmo) * PlayerStatManager.LArmCost
		$VBoxContainer2/LACost.text = str(LArmTotal) + "C"
	if typeof(PlayerStatManager.RShoulderAmmo) == TYPE_INT:
		$VBoxContainer2/RightShoulderBox/RightShoulderAmmo.text = str(PlayerStatManager.RShoulderAmmo)+"/"+str(PlayerStatManager.RShoulderAmmoMax)
		RShdTotal = (PlayerStatManager.RShoulderAmmoMax - PlayerStatManager.RShoulderAmmo) * PlayerStatManager.RShoulderCost
		$VBoxContainer2/RSCost.text = str(RShdTotal) + "C"
	if typeof(PlayerStatManager.LShoulderAmmo) == TYPE_INT:
		$VBoxContainer2/LeftShoulderBox/LeftShoulderAmmo.text = str(PlayerStatManager.LShoulderAmmo)+"/"+str(PlayerStatManager.LShoulderAmmoMax)
		LShdTotal = (PlayerStatManager.LShoulderAmmoMax - PlayerStatManager.LShoulderAmmo) * PlayerStatManager.LShoulderCost
		$VBoxContainer2/LSCost.text = str(LShdTotal) + "C"
	PlayerStatManager.ReloadCost = RArmTotal + LArmTotal + RShdTotal + LShdTotal
	if PlayerStatManager.PlayerMaxHP == PlayerStatManager.PlayerHP:
		PlayerStatManager.RepairCost = 0
	else:
		if PlayerStatManager.PlayerHP >= 90:
			PlayerStatManager.RepairCost = (PlayerStatManager.PlayerMaxHP - PlayerStatManager.PlayerHP)* 500
		else:
			PlayerStatManager.RepairCost = 5000
	$HBoxContainer/VBoxContainer/ReloadButton2/ReloadCost.text = str(PlayerStatManager.ReloadCost)+"C"
	$HBoxContainer/VBoxContainer/RepairButton/RepairCost.text = str(PlayerStatManager.RepairCost)+"C"
	$VBoxContainer2/ArmorBox/RemainingArmor.text = str(PlayerStatManager.PlayerHP)

func update_prices():
	$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
	if typeof(PlayerStatManager.RArmAmmo) == TYPE_INT:
		$VBoxContainer2/RightArmBox/RightArmAmmo.text = str(PlayerStatManager.RArmAmmo) +"/"+ str(PlayerStatManager.RArmAmmoMax)
		$VBoxContainer2/RACost.text = str(RArmTotal) + "C"
	if typeof(PlayerStatManager.LArmAmmo) == TYPE_INT:
		$VBoxContainer2/LeftArmBox/LeftArmAmmo.text = str(PlayerStatManager.LArmAmmo)+"/"+str(PlayerStatManager.LArmAmmoMax)
		$VBoxContainer2/LACost.text = str(LArmTotal) + "C"
	if typeof(PlayerStatManager.RShoulderAmmo) == TYPE_INT:
		$VBoxContainer2/RightShoulderBox/RightShoulderAmmo.text = str(PlayerStatManager.RShoulderAmmo)+"/"+str(PlayerStatManager.RShoulderAmmoMax)
		$VBoxContainer2/RSCost.text = str(RShdTotal) + "C"
	if typeof(PlayerStatManager.LShoulderAmmo) == TYPE_INT:
		$VBoxContainer2/LeftShoulderBox/LeftShoulderAmmo.text = str(PlayerStatManager.LShoulderAmmo)+"/"+str(PlayerStatManager.LShoulderAmmoMax)
		$VBoxContainer2/LSCost.text = str(LShdTotal) + "C"
	if PlayerStatManager.PlayerMaxHP == PlayerStatManager.PlayerHP:
		PlayerStatManager.RepairCost = 0
	else:
		if PlayerStatManager.PlayerHP >= 90:
			PlayerStatManager.RepairCost = (PlayerStatManager.PlayerMaxHP - PlayerStatManager.PlayerHP)* 500
		else:
			PlayerStatManager.RepairCost = 5000
	$HBoxContainer/VBoxContainer/RepairButton/RepairCost.text = str(PlayerStatManager.RepairCost)+"C"
	$HBoxContainer/VBoxContainer/ReloadButton2/ReloadCost.text = str(PlayerStatManager.ReloadCost)+"C"
	$VBoxContainer2/ArmorBox/RemainingArmor.text = str(PlayerStatManager.PlayerHP)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
func not_enough_credits():
	$AnimationPlayer.stop(true)
	$AnimationPlayer.play("noCredits")
	$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"

func _on_ReloadButton2_pressed():
	if PlayerStatManager.ReloadCost <= PlayerStatManager.Credits:
		PlayerStatManager.Credits -= PlayerStatManager.ReloadCost
		$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
		PlayerStatManager.RArmAmmo = PlayerStatManager.RArmAmmoMax
		PlayerStatManager.LArmAmmo = PlayerStatManager.LArmAmmoMax
		PlayerStatManager.RShoulderAmmo = PlayerStatManager.RShoulderAmmoMax
		PlayerStatManager.LShoulderAmmo = PlayerStatManager.LShoulderAmmoMax
		update_prices()
	else:
		not_enough_credits()

func _on_RepairButton_pressed():
	if PlayerStatManager.RepairCost <= PlayerStatManager.Credits:
		PlayerStatManager.Credits -= PlayerStatManager.RepairCost
		$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
		if PlayerStatManager.PlayerHP >= 90:
			PlayerStatManager.PlayerHP = 100
		else:
			PlayerStatManager.PlayerHP += 10
		update_prices()
		PlayerStatManager.RepairedLastRound = true
	else:
		not_enough_credits()


func _on_ContinueButton_pressed():
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://game/arena/Arena.tscn")
	PlayerStatManager.PlayerKills = 0


func _on_ExitButton_pressed():
# warning-ignore:return_value_discarded
	get_tree().change_scene("res://Start Menu.tscn")
	PlayerStatManager.PlayerKills = 0
	PlayerStatManager.NumberofExtracts = 0


func _on_RABuy_pressed():
	if PlayerStatManager.RArmAmmo:
		if RArmTotal <= PlayerStatManager.Credits:
			PlayerStatManager.Credits -= RArmTotal
			$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
			PlayerStatManager.RArmAmmo = PlayerStatManager.RArmAmmoMax
			update_prices()
	else:
		not_enough_credits()	


func _on_LABuy_pressed():
	if PlayerStatManager.LArmAmmo:
		if LArmTotal <= PlayerStatManager.Credits:
			PlayerStatManager.Credits -= LArmTotal
			$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
			PlayerStatManager.LArmAmmo = PlayerStatManager.LArmAmmoMax
			update_prices()
	else:
		not_enough_credits()


func _on_RSBuy_pressed():
	if PlayerStatManager.RShoulderAmmo:
		if RShdTotal <= PlayerStatManager.Credits:
			PlayerStatManager.Credits -= RShdTotal
			$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
			PlayerStatManager.RShoulderAmmo = PlayerStatManager.RShoulderAmmoMax
			update_prices()
	else:
		not_enough_credits()


func _on_LSBuy_pressed():
	if PlayerStatManager.LShoulderAmmo:
		if LShdTotal <= PlayerStatManager.Credits:
			PlayerStatManager.Credits -= LShdTotal
			$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
			PlayerStatManager.LShdAmmo = PlayerStatManager.LShoulderAmmoMax
			update_prices()
	else:
		not_enough_credits()
