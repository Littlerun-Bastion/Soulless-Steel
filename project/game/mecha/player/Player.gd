extends Mecha

signal update_reload_mode
signal update_lock_mode
signal update_building_status
signal reloading
signal finished_reloading
signal lost_health

const INSIDE_BUILDING_ZOOM_MUL = 1.4
const DEFAULT_CAM_ZOOM = Vector2(.5,.5)
const ZOOM_SPEED = 2

const ROTATION_DEADZONE = 20
const MOVE_CAMERA_SCREEN_MARGIN = 260
const MOVE_CAMERA_MAX_SPEED = 800
const SPRINTING_TIMEOUT = .13 #How much the player needs to hold the button to enter sprint mode

@onready var Cam = $Camera2D

var sprinting_timer = 0
var invert_controls = {
	"x": false,
	"y": false,
}

func _ready():
	super()
	
	if Debug.get_setting("player_zoom"):
		var zoom = Debug.get_setting("player_zoom")
		Cam.zoom = Vector2(zoom, zoom)
	else:
		Cam.zoom = DEFAULT_CAM_ZOOM 


func _physics_process(delta):
	if paused or is_stunned():
		return
	
	super(delta)
	
	check_input()
	
	apply_movement(delta, get_input())
	
	#Update sprinting timer
	if sprinting_timer > 0.0:
		sprinting_timer = max(sprinting_timer - delta, 0.0)
		if sprinting_timer <= 0.0:
			is_sprinting = true
	
	if not get_locked_to():# and movement_type != "tank":
		var target_pos = get_global_mouse_position()
		if target_pos.distance_to(global_position) > ROTATION_DEADZONE:
			apply_rotation_by_point(delta, target_pos, Input.is_action_pressed("strafe"))
	
	update_camera_zoom(delta)
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
	elif event.is_action_pressed("thruster_dash") and not is_stunned() and not is_movement_locked():
		sprinting_timer = SPRINTING_TIMEOUT
	elif event.is_action_released("thruster_dash") and not is_stunned() and not is_movement_locked():
		if sprinting_timer > 0.0 and movement_type != "tank":
			dash(get_input().normalized())
		stop_sprinting(get_input().normalized())
		sprinting_timer = 0.0
	elif event.is_action_pressed("debug_3"):
		die(self, "Myself")


func get_camera_3d():
	return Cam


func update_camera_zoom(dt):
	var target
	if Debug.get_setting("player_zoom"):
		var zoom = Debug.get_setting("player_zoom")
		target = Vector2(zoom, zoom)
	else:
		target = DEFAULT_CAM_ZOOM 
	if is_inside_building:
		target *= INSIDE_BUILDING_ZOOM_MUL
	
	Cam.zoom = lerp(Cam.zoom, target, clamp(dt*ZOOM_SPEED, 0.0, 1.0))


func update_camera_offset(dt):
	if head and head.visual_range > 0:
		var mp = get_viewport().get_mouse_position()
		var vp_size = get_viewport().get_visible_rect().size
		var margin = MOVE_CAMERA_SCREEN_MARGIN
		var abs_dir = Vector2()
		var strength = Vector2()
		if mp.x <= margin:
			abs_dir.x += 1
			strength.x = -1.0 + (mp.x/float(margin))
		elif mp.x >= vp_size.x - margin:
			abs_dir.x += 1
			strength.x = ((mp.x - vp_size.x + margin)/float(margin))
		if mp.y <= margin:
			abs_dir.y += 1
			strength.y = -1.0 + (mp.y/float(margin))
		elif mp.y >= vp_size.y - margin:
			abs_dir.y += 1
			strength.y = ((mp.y - vp_size.y + margin)/float(margin))
		
		abs_dir = abs_dir.normalized()
		strength *= strength*strength #Make it cubically strong on edges
		Cam.offset += abs_dir*strength*MOVE_CAMERA_MAX_SPEED*dt
		Cam.offset = Cam.offset.limit_length(head.visual_range)


func take_damage(amount, shield_mult, health_mult, heat_damage, status_amount, status_type, hitstop, source_info, weapon_name := "Test"):
	var prev_hp = hp
	super.take_damage(amount, shield_mult, health_mult, heat_damage, status_amount, status_type, hitstop, source_info, weapon_name)
	if prev_hp > hp:
		emit_signal("lost_health")


func do_hitstop():
	Cam.shake((HITSTOP_DURATION + 1) * HITSTOP_TIMESCALE, 15, 50, 10)


func knockback(strength, dir, should_rotate = true):
	super.knockback(strength, dir, should_rotate)
	if strength > 0:
		var dur = min(sqrt(strength)/10, 1.5)
		var freq = pow(strength, .3)*5
		var amp = pow(strength, .3)*5
		Cam.shake(dur, freq, amp, strength)


func apply_recoil(type, node, recoil):
	super.apply_recoil(type, node, recoil)
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
	
	#Safety check for sprinting, since it was bugging sometimes
	if not Input.is_action_pressed("thruster_dash"):
		stop_sprinting(get_input().normalized())
		sprinting_timer = 0.0

func check_weapon_input(weapon_name, node, weapon_ref):
	if weapon_ref and weapon_ref.auto_fire and cur_mode == MODES.NEUTRAL and\
	not node.reloading and Input.is_action_pressed(weapon_name+"_shoot"):
		shoot(weapon_name, true)
	if not Input.is_action_pressed(weapon_name+"_shoot"):
		if spooling[weapon_name]:
			WeaponSFXs[weapon_name].spool_up.stop()
		spooling[weapon_name] = false


func setup(arena_ref):
	arena = arena_ref
	mecha_name = "Player"
	if PlayerStatManager.NumberofExtracts != 0:
		hp = PlayerStatManager.PlayerHP
		emit_signal("lost_health")
	
	if Debug.get_setting("debug_loadout"):
		set_debug_loadout()
	elif Profile.stats.current_mecha:
		set_parts_from_design(Profile.stats.current_mecha)
	else:
		push_warning("No design setted for player, using the same as the debug loadout")
		set_debug_loadout()


func set_debug_loadout():
	set_core("Lancelot-Core")
	set_generator("avg_civ_generator")
	set_chipset("type_1")
	set_thruster("test1")
	set_head("MSV-L3J-H")
	set_chassis("MSV-L3J-L")
	set_arm_weapon("Clarent-01", SIDE.LEFT)
	set_arm_weapon("MA-ASR1", SIDE.RIGHT)
	set_shoulder_weapon("Arend", SIDE.RIGHT)
	set_shoulder_weapon("CL1-Shoot", SIDE.LEFT)
	set_shoulders("Lancelot-Pauldron")


func set_arm_weapon(part_name, side):
	super.set_arm_weapon(part_name, side)
	var node
	if side == SIDE.LEFT:
		node = $ArmWeaponLeft
	elif side == SIDE.RIGHT:
		node = $ArmWeaponRight
	
	if node.is_connected("finished_reloading",Callable(self,"_on_finished_reloading")):
		node.disconnect("finished_reloading",Callable(self,"_on_finished_reloading"))
	if node.is_connected("reloading_signal",Callable(self,"_on_reloading")):
		node.disconnect("reloading_signal",Callable(self,"_on_reloading"))
	node.connect("finished_reloading",Callable(self,"_on_finished_reloading"))
	node.connect("reloading_signal",Callable(self,"_on_reloading").bind(side))


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
		@warning_ignore("narrowing_conversion")
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


# BUILDING METHODS

func entered_building():
	super.entered_building()
	emit_signal("update_building_status", true)


func exited_building():
	super.exited_building()
	emit_signal("update_building_status", false)


# CALLBACKS


func _on_finished_reloading():
	emit_signal("finished_reloading")


func _on_reloading(reload_time, side):
	emit_signal("reloading", reload_time, side)

func player_extracting():
	print(str("Player is Extracting"))
	
