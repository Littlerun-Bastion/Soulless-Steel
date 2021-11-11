extends Control

const WEAPON_NAME_MAP = {
	"arm_weapon_left": "L-ARM",
	"arm_weapon_right": "R-ARM",
	"shoulder_weapon_left": "L-SHOULDER",
	"shoulder_weapon_right": "R-SHOULDER",
}

var type : String

func setup(arm_data, position):
	assert(WEAPON_NAME_MAP.has(position), "Not a valid position for weapon slot: " + str(position))
	$Position.text = WEAPON_NAME_MAP[position]
	$WeaponImage.texture = arm_data.image
	type = position
	set_ammo(arm_data.total_ammo)


func set_ammo(value):
	$TotalAmmo.text = "%02d" % value
