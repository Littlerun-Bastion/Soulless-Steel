extends Control

const WEAPON_NAME_MAP = {
	"arm_weapon_left": "LARM - ",
	"arm_weapon_right": "RARM - ",
	"shoulder_weapon_left": "LBCK - ",
	"shoulder_weapon_right": "RBCK - ",
}

var type : String

func setup(arm_data, pos):
	assert(WEAPON_NAME_MAP.has(pos),"Not a valid position for weapon slot: " + str(pos))
	$WeaponLabel.text = WEAPON_NAME_MAP[pos]
	type = pos
	set_ammo(arm_data.total_ammo)


func set_ammo(value):
	$AmmoCountLabel.text = "%02d" % value
