extends Mecha

signal update_reload_mode
signal update_lock_mode
signal reloading
signal finished_reloading
signal lost_health

const ROTATION_DEADZONE = 20
const MOVE_CAMERA_SCREEN_MARGIN = 260
const MOVE_CAMERA_MAX_SPEED = 800
const SPRINTING_TIMEOUT = .2 #How much the player needs to hold the button to enter sprint mode

onready var Cam = $Camera2D

var sprinting_timer = 0
var invert_controls = {
	"x": false,
	"y": false,
}

func _ready():
	if Debug.get_setting("player_loadout"):
		set_core("MSV-L3J")
		set_generator("type_1")
		set_chipset("type_1")
		set_thruster("test1")
		set_head("head_test")
		set_chassis("legs_test")
		set_arm_weapon("testlaser", SIDE.LEFT)
		set_arm_weapon("Type2Sh-Gattling", SIDE.RIGHT)
		set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
		set_shoulder_weapon(false, SIDE.LEFT)
		set_shoulders("shoulder_test")
	if Debug.get_setting("player_zoom"):
		Cam.zoom = Debug.get_setting("player_zoom")


func _physics_process(delta):
	if paused or is_stunned():
		return

	check_input()
	
	apply_movement(delta, get_input())
	
	#Update sprinting timer
	if sprinting_timer > 0.0:
		sprinting_timer = max(sprinting_timer - delta, 0.0)
		if sprinting_timer <= 0.0:
			is_sprinting = true
	
	if not get_locked_to():
		var target_pos = get_global_mouse_position()
		if target_pos.distance_to(global_position) > ROTATION_DEADZONE:
			apply_rotation_by_point(delta, target_pos, \
						   movement_type == "tank" or Input.is_action_pressed("strafe"))
	
	update_camera_offset(delta)


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
	elif event.is_action_pressed("lock_mode") and chipset.can_lock:
		cur_mode = MODES.ACTIVATING_LOCK
		emit_signal("update_lock_mode", true)
	elif event.is_action_released("lock_mode") and chipset.can_lock:
		locking_to = false
		cur_mode = MODES.NEUTRAL
		emit_signal("update_lock_mode", false)
	elif event.is_action_pressed("thruster_dash"):
		sprinting_timer = SPRINTING_TIMEOUT
	elif event.is_action_released("thruster_dash"):
		if sprinting_timer > 0.0:
			dash(get_input().normalized())
		stop_sprinting()
		sprinting_timer = 0.0
	elif event.is_action_pressed("debug_1"):
		die(self, "Myself")
	
func get_camera():
	return Cam


func update_camera_offset(dt):
	if head and head.visual_range > 0:
		var mp = get_viewport().get_mouse_position()
		var sx = get_viewport_rect().size.x
		var sy = get_viewport_rect().size.y
		var abs_dir = Vector2()
		var strength = Vector2()
		if mp.x <= MOVE_CAMERA_SCREEN_MARGIN:
			abs_dir.x += 1
			strength.x = -1.0 + (mp.x/float(MOVE_CAMERA_SCREEN_MARGIN))
		elif mp.x >= sx - MOVE_CAMERA_SCREEN_MARGIN:
			abs_dir.x += 1
			strength.x = ((mp.x - sx + MOVE_CAMERA_SCREEN_MARGIN)/float(MOVE_CAMERA_SCREEN_MARGIN))
		if mp.y <= MOVE_CAMERA_SCREEN_MARGIN:
			abs_dir.y += 1
			strength.y = -1.0 + (mp.y/float(MOVE_CAMERA_SCREEN_MARGIN))
		elif mp.y >= sy - MOVE_CAMERA_SCREEN_MARGIN:
			abs_dir.y += 1
			strength.y = ((mp.y - sy + MOVE_CAMERA_SCREEN_MARGIN)/float(MOVE_CAMERA_SCREEN_MARGIN))
		
		abs_dir = abs_dir.normalized()
		strength *= strength*strength #Make it cubically strong on edges
		Cam.offset += abs_dir*strength*MOVE_CAMERA_MAX_SPEED*dt
		Cam.offset = Cam.offset.limit_length(head.visual_range)

func take_damage(amount, shield_mult, health_mult, heat_damage, source_info, weapon_name := "Test", calibre := CALIBRE_TYPES.SMALL):
	var prev_hp = hp
	.take_damage(amount, shield_mult, health_mult, heat_damage, source_info, weapon_name, calibre)
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


func setup(arena_ref):
	arena = arena_ref
	mecha_name = "Player"
	if PlayerStatManager.NumberofExtracts != 0:
		hp = PlayerStatManager.PlayerHP
		emit_signal("lost_health")
	if not Debug.get_setting("player_loadout"):
		set_core("MSV-L3J")
		set_generator("type_1")
		set_chipset("type_1")
		set_thruster("test1")
		set_head("head_test2")
		#Use to test free mode
		set_chassis("legs_test")
		#Use to test tank mode
		#set_chassis("T-01-TR", SIDE.SINGLE)
		set_arm_weapon("TT1-Flamethrower", SIDE.LEFT)
		set_arm_weapon("Type1-Massive", SIDE.RIGHT)
		set_shoulder_weapon("CL1-Shoot", SIDE.RIGHT)
		set_shoulder_weapon(false, SIDE.LEFT)
		set_shoulders("shoulder_test")


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
	
	if movement_type == "relative":
		if mov_vec.x == 0:
			invert_controls.x = false
		if mov_vec.y == 0:
			invert_controls.y = false
		# warning-ignore:narrowing_conversion
		var angle = posmod(rotation_degrees, 360)
		if angle > 180 - Profile.get_option("invert_deadzone_angle")/2 and\
		   angle < 180 + Profile.get_option("invert_deadzone_angle")/2:
			if not moving_axis.x:
				invert_controls.x = mov_vec.x != 0
			if not moving_axis.y:
				invert_controls.y = mov_vec.y != 0
	
	if Profile.get_option("invert_x") and invert_controls.x:
		mov_vec.x *= -1
	if Profile.get_option("invert_y") and invert_controls.y:
		mov_vec.y *= -1
	
	return mov_vec


func get_cam():
	return Cam


func _on_finished_reloading():
	emit_signal("finished_reloading")


func _on_reloading(reload_time, side):
	emit_signal("reloading", reload_time, side)

func player_extracting():
	print(str("Player is Extracting"))
	
