extends Control

const WEAPON_NAME_MAP = {
	"arm_weapon_left": "LEFT ARM",
	"arm_weapon_right": "RIGHT ARM",
	"shoulder_weapon_left": "LEFT SHOULDER",
	"shoulder_weapon_right": "RIGHT SHOULDER",
}

func setup(arm_data, position):
	assert(WEAPON_NAME_MAP.has(position), "Not a valid position for weapon slot: " + str(position))
	$Position.text = WEAPON_NAME_MAP[position]
	$Name.text = (arm_data.name).to_upper()
	$Type.text = (arm_data.type).to_upper()
	$Image.texture = arm_data.image
	$MagazineAmmo.text = "%02d" % arm_data.clip_size
	$SpareAmmo.text = "%02d" % arm_data.total_ammo
