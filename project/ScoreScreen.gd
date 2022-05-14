extends Control

onready var VCRTween = $ShaderEffects/Tween
onready var VCREffect = $ShaderEffects/VCREffect
var RArmTotal = 0
var LArmTotal = 0
var RShdTotal = 0
var LShdTotal = 0
# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	$PlayerKills.text = "Player Kills: " + str(PlayerStatManager.PlayerKills)
	if VCRTween.is_active():
		return
	VCRTween.interpolate_property(VCREffect.material, "shader_param/noiseIntensity", null, 0.02, .1)
	VCRTween.interpolate_property(VCREffect.material, "shader_param/colorOffsetIntensity", null, 1.2, .1)
	VCRTween.start()
	
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
		PlayerStatManager.RepairCost = 150000*((PlayerStatManager.PlayerMaxHP - PlayerStatManager.PlayerHP)/PlayerStatManager.PlayerMaxHP)
	$HBoxContainer/VBoxContainer/ReloadButton2/ReloadCost.text = str(PlayerStatManager.ReloadCost)+"C"
	$HBoxContainer/VBoxContainer/RepairButton/RepairCost.text = str(PlayerStatManager.RepairCost)+"C"

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
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
func not_enough_credits():
	$EarnedCredits.text = "Insufficient Credits."
	yield(get_tree().create_timer(2.0), "timeout")
	$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"

func _on_ReloadButton2_pressed():
	if PlayerStatManager.ReloadCost <= PlayerStatManager.Credits:
		PlayerStatManager.Credits -= PlayerStatManager.ReloadCost
		$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
		PlayerStatManager.RArmAmmo = PlayerStatManager.RArmAmmoMax
		PlayerStatManager.LArmAmmo = PlayerStatManager.LArmAmmoMax
		PlayerStatManager.RShoulderAmmo = PlayerStatManager.RShoulderAmmoMax
		PlayerStatManager.LShoulderAmmo = PlayerStatManager.LShoulderAmmoMax

func _on_RepairButton_pressed():
	if PlayerStatManager.RepairCost <= PlayerStatManager.Credits:
		PlayerStatManager.Credits -= PlayerStatManager.RepairCost
		$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
		PlayerStatManager.PlayerHP = PlayerStatManager.PlayerMaxHP
	else:
		not_enough_credits()


func _on_ContinueButton_pressed():
	get_tree().change_scene("res://game/arena/Arena.tscn")
	pass # Replace with function body.


func _on_ExitButton_pressed():
	get_tree().change_scene("res://Start Menu.tscn")
	pass # Replace with function body.


func _on_RABuy_pressed():
	if RArmTotal <= PlayerStatManager.Credits:
		PlayerStatManager.Credits -= RArmTotal
		$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
		PlayerStatManager.RArmAmmo = PlayerStatManager.RArmAmmoMax
		update_prices()
		


func _on_LABuy_pressed():
	if LArmTotal <= PlayerStatManager.Credits:
		PlayerStatManager.Credits -= LArmTotal
		$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
		PlayerStatManager.LArmAmmo = PlayerStatManager.LArmAmmoMax
		update_prices()


func _on_RSBuy_pressed():
	if RShdTotal <= PlayerStatManager.Credits:
		PlayerStatManager.Credits -= RShdTotal
		$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
		PlayerStatManager.RShdAmmo = PlayerStatManager.RShdAmmoMax
		update_prices()


func _on_LSBuy_pressed():
	if LShdTotal <= PlayerStatManager.Credits:
		PlayerStatManager.Credits -= LShdTotal
		$EarnedCredits.text = "Earned Credits: " + str(PlayerStatManager.Credits) + "C"
		PlayerStatManager.LShdAmmo = PlayerStatManager.LShdAmmoMax
		update_prices()
