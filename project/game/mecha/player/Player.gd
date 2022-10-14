extends Mecha

signal update_reload_mode
signal update_lock_mode
signal reloading
signal finished_reloading
signal lost_health

const ROTATION_DEADZONE = 20

onready var Cam = $Camera2D


func _ready():
	if Debug.get_setting("player_loadout"):
		set_core("MSV-L3J")
		set_generator("type_1")
		set_head("head_test")
		set_leg("MSV-L3J-L", SIDE.LEFT)
		set_leg("MSV-L3J-R", SIDE.RIGHT)
		set_arm_weapon("TT1-Shotgun", SIDE.LEFT)
		set_arm_weapon("Type2Sh-Gattling", SIDE.RIGHT)
		set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
		set_shoulder_weapon(false, SIDE.LEFT)
		set_shoulder("shoulder_test3_left", SIDE.LEFT)
		set_shoulder("shoulder_test3_right", SIDE.RIGHT)
	if Debug.get_setting("player_zoom"):
		Cam.zoom = Debug.get_setting("player_zoom")


func _physics_process(delta):
	if paused or is_stunned():
		return

	check_input()
	
	apply_movement(delta, get_input())
	
	var target_pos = get_global_mouse_position()
	if target_pos.distance_to(global_position) > ROTATION_DEADZONE:
		apply_rotation_by_point(delta, target_pos, \
					   movement_type == "tank" or Input.is_action_pressed("strafe"))


func _input(event):
	if paused or is_stunned():
		return
	
	if event.is_action_pressed("interact"):
		AudioManager.play_sfx("test", global_position)
	elif event.is_action_pressed("arm_weapon_left_shoot") and arm_weapon_left:
		if cur_mode == MODES.RELOAD:
			$ArmWeaponLeft.reload()
		elif cur_mode == MODES.NEUTRAL and not $ArmWeaponLeft.reloading:
			shoot("arm_weapon_left")
	elif event.is_action_pressed("arm_weapon_right_shoot") and arm_weapon_right:
		if cur_mode == MODES.RELOAD:
			$ArmWeaponRight.reload()
		elif cur_mode == MODES.NEUTRAL and not $ArmWeaponRight.reloading:
			shoot("arm_weapon_right")
	elif event.is_action_pressed("shoulder_weapon_left_shoot") and shoulder_weapon_left and\
		 cur_mode == MODES.NEUTRAL:
		shoot("shoulder_weapon_left")
	elif event.is_action_pressed("shoulder_weapon_right_shoot") and shoulder_weapon_right and\
		 cur_mode == MODES.NEUTRAL:
		shoot("shoulder_weapon_right")
	elif event.is_action_pressed("reload_mode"):
		cur_mode = MODES.RELOAD
		emit_signal("update_reload_mode", true)
	elif event.is_action_released("reload_mode"):
		cur_mode = MODES.NEUTRAL
		emit_signal("update_reload_mode", false)
	elif event.is_action_pressed("lock_mode"):
		cur_mode = MODES.ACTIVATING_LOCK
		emit_signal("update_lock_mode", true)
	elif event.is_action_released("lock_mode"):
		cur_mode = MODES.NEUTRAL
		emit_signal("update_lock_mode", false)
	elif event.is_action_pressed("debug_1"):
		die(self, "Myself")


func get_camera():
	return Cam


func take_damage(amount, source_info, weapon_name := "Test", calibre := CALIBRE_TYPES.SMALL):
	var prev_hp = hp
	.take_damage(amount, source_info, weapon_name, calibre)
	if prev_hp > hp:
		emit_signal("lost_health")


func knockback(pos, strength, should_rotate = true):
	.knockback(pos, strength, should_rotate)
	if strength > 0:
		var dur = sqrt(strength)/10
		var freq = pow(strength, .3)*5
		var amp = pow(strength, .3)*5
		Cam.shake(dur, freq, amp, strength)


func apply_recoil(type, recoil):
	.apply_recoil(type, recoil)
	if recoil > 0:
		var dur = sqrt(recoil)/10
		var freq = pow(recoil, .3)*5
		var amp = pow(recoil, .3)*5
		Cam.shake(dur, freq, amp, recoil)


func check_input():
	check_weapon_input("arm_weapon_left", $ArmWeaponLeft, arm_weapon_left)
	check_weapon_input("arm_weapon_right", $ArmWeaponRight, arm_weapon_right)
	check_weapon_input("shoulder_weapon_left", $ShoulderWeaponLeft, shoulder_weapon_left)
	check_weapon_input("shoulder_weapon_right", $ShoulderWeaponRight, shoulder_weapon_right)


func check_weapon_input(name, node, weapon_ref):
	if weapon_ref and weapon_ref.auto_fire and cur_mode == MODES.NEUTRAL and\
	   not node.reloading and Input.is_action_pressed(name+"_shoot"):
		shoot(name, true)


func setup():
	mecha_name = "Player"
	if PlayerStatManager.NumberofExtracts != 0:
		hp = PlayerStatManager.PlayerHP
		emit_signal("lost_health")
	if not Debug.get_setting("player_loadout"):
		set_core("MSV-L3J")
		set_generator("type_1")
		set_head("head_test2")
		#Use to test free mode
		set_leg("MSV-L3J-L", SIDE.LEFT)
		set_leg("MSV-L3J-R", SIDE.RIGHT)
		#Use to test tank mode
		#set_leg("T-01-TR", SIDE.SINGLE)
		set_arm_weapon("TT1-Flamethrower", SIDE.LEFT)
		set_arm_weapon("Type1-Massive", SIDE.RIGHT)
		set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
		set_shoulder_weapon(false, SIDE.LEFT)
		set_shoulder("shoulder_test3_left", SIDE.LEFT)
		set_shoulder("shoulder_test3_right", SIDE.RIGHT)


func set_arm_weapon(part_name, side):
	.set_arm_weapon(part_name, side)
	var node
	if side == SIDE.LEFT:
		node = $ArmWeaponLeft
	elif side == SIDE.RIGHT:
		node = $ArmWeaponRight
	node.connect("finished_reloading", self, "_on_finished_reloading")
	node.connect("reloading", self, "_on_reloading", [side])


func get_input():
	var mov_vec = Vector2()
	if Input.is_action_pressed('right'):
		mov_vec.x += 1
	if Input.is_action_pressed('left'):
		mov_vec.x -= 1
	if Input.is_action_pressed('down'):
		mov_vec.y += 1
	if Input.is_action_pressed('up'):
		mov_vec.y -= 1
	
	return mov_vec


func get_cam():
	return Cam


func _on_finished_reloading():
	emit_signal("finished_reloading")


func _on_reloading(reload_time, side):
	emit_signal("reloading", reload_time, side)

func player_extracting():
	print(str("Player is Extracting"))
	
