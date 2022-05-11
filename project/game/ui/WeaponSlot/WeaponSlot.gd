extends Control

const WEAPON_NAME_MAP = {
	"arm_weapon_left": "LARM - ",
	"arm_weapon_right": "RARM - ",
	"shoulder_weapon_left": "LBCK - ",
	"shoulder_weapon_right": "RBCK - ",
}

var type : String

func setup(arm_data, position):
	assert(WEAPON_NAME_MAP.has(position), "Not a valid position for weapon slot: " + str(position))
	$WeaponLabel.text = WEAPON_NAME_MAP[position]
	type = position
	set_ammo(arm_data.total_ammo)


func set_ammo(value):
	$AmmoCountLabel.text = "%02d" % value
