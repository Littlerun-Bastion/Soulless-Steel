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
const SPRINTING_TIMEOUT = .25 #How much the player needs to hold the button to enter sprint mode
const DESIGNATOR_SCRIPT = preload("res://game/mecha/player/Designator.gd")
## Canvas layer of the designators: above the IR heatmap (layer 2).
const DESIGNATOR_LAYER = 3
## With look limits off, a salvo released outside the look angle waits this
## long (s) for the mecha to face its point, then is dropped.
const PENDING_FIRE_TIME = 1.5
const SHOULDER_SLOTS = ["shoulder_weapon_left", "shoulder_weapon_right"]
## A tap_self weapon released sooner than this (s) fires at the mecha itself.
const TAP_TIME = 0.2
## The player's view: how often (s) each mecha and Entity is checked, how
## fast one fades out when hidden or back in when seen (alpha per s), and the
## distance (px) past which nothing is checked (it is off screen).
const VIEW_CHECK_TIME = 0.1
const VIEW_FADE_SPEED = 5.0
const VIEW_RANGE = 6000.0
## The vision cone, matching the MechaLight (its aimed_glow texture is lit to
## about 15 degrees either side and to 0.44 of its width from the centre),
## and the distance (px) all round within which things are seen anyway
## (20 m).
const VIEW_CONE_HALF_ANGLE = 15.0
const VIEW_CONE_REACH = 0.44
const VIEW_PERIPHERAL = 400.0

@onready var Cam = $Camera2D
@onready var Light = $MechaLight

var sprinting_timer = 0
var invert_controls = {
	"x": false,
	"y": false,
}
var current_open_container: LootContainer = null
var scripted_move := Vector2.ZERO
var scripted_aim = null

var _awaiting_release := {} #For weapons that were firing, shooting is paused when crosshair goes away for pointer. Shooting resumed when crosshair comes back.
# Shoulder weapons work like skills: holding the fire button shows the
# designator, releasing fires, pressing reload while holding cancels.
# Slot -> true while its fire button is held.
var _designating := {}
# Slot -> {"point", "time"}: salvos released outside the look angle (look
# limits off), fired once the mecha faces the point.
var _pending_fire := {}
var designator = null  # Designator.gd
# The player's view (see _update_view): the mechas and Entities checked last,
# and those hidden from the player (body -> true).
var _view_bodies: Array = []
var _view_hidden := {}
var _view_timer := 0.0

func _ready():
	super()
	var layer := CanvasLayer.new()
	layer.layer = DESIGNATOR_LAYER
	layer.follow_viewport_enabled = true
	add_child(layer)
	designator = DESIGNATOR_SCRIPT.new()
	layer.add_child(designator)

	if Debug.get_setting("player_zoom"):
		var zoom = Debug.get_setting("player_zoom")
		Cam.zoom = Vector2(zoom, zoom)
	else:
		Cam.zoom = DEFAULT_CAM_ZOOM 
	MouseManager.cursor_mode_changed.connect(_on_cursor_mode_changed)

func _physics_process(dt):
	if paused:
		return
	
	super(dt)
	
	
	if is_stunned():
		return
	
	if controls_locked:
		apply_movement(dt, scripted_move)
	else:
		check_input()
		apply_movement(dt, get_input())
	_update_designators(dt)
	_update_view(dt)

	#Update sprinting timer
	if sprinting_timer > 0.0:
		sprinting_timer = max(sprinting_timer - dt, 0.0)
		if sprinting_timer <= 0.0:
			is_sprinting = true

	if not get_locked_to():
		var target_pos = scripted_aim if controls_locked else get_global_mouse_position()
		if target_pos != null:
			if target_pos.distance_to(global_position) > ROTATION_DEADZONE:
				# POINTER (Alt) locks the body; head, shoulders and arms keep
				# tracking within their rotation ranges.
				var lock_body: bool = not controls_locked and\
				(Input.is_action_pressed("strafe") or not MouseManager.is_aiming())
				apply_rotation_by_point(dt, target_pos, lock_body)
		
	update_camera_zoom(dt)
	update_camera_offset(dt)


func _input(event):
	# A shoulder release is never missed: while paused or stunned it drops
	# the salvo instead of firing it.
	for slot in SHOULDER_SLOTS:
		if event.is_action_released(slot + "_shoot") and _designating.has(slot):
			if paused or is_stunned() or controls_locked:
				_designating.erase(slot)
			else:
				release_designating(slot)
	if paused or is_stunned() or controls_locked:
		return
	
	# --- Inventory toggle (MechOS) ---
	if event.is_action_pressed("toggle_inventory"):
		if current_open_container != null:
			MechOS.close_app("container")
			MechOS.close_app("mech_cargo")
			current_open_container.close()
			current_open_container = null
		else:
			if MechOS.is_app_open("mech_cargo"):
				MechOS.close_app("mech_cargo")
			else:
				MechOS.open_inventory("mech_cargo", mech_inventory, "MECH CARGO")
		get_viewport().set_input_as_handled()
		return
	
	# --- Close container via interact key ---
	if event.is_action_pressed("interact") and current_open_container != null:
		MechOS.close_app("container")
		MechOS.close_app("mech_cargo")
		current_open_container.close()
		current_open_container = null
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("arm_weapon_left_shoot") and build.arm_weapon_left and MouseManager.is_aiming():
		if cur_mode == MODES.RELOAD:
			$ArmWeaponLeft.reload()
		elif cur_mode == MODES.NEUTRAL and not $ArmWeaponLeft.reloading:
			shoot("arm_weapon_left")
	elif event.is_action_pressed("arm_weapon_right_shoot") and build.arm_weapon_right and MouseManager.is_aiming():
		if cur_mode == MODES.RELOAD:
			$ArmWeaponRight.reload()
		elif cur_mode == MODES.NEUTRAL and not $ArmWeaponRight.reloading:
			shoot("arm_weapon_right")
	elif event.is_action_pressed("shoulder_weapon_left_shoot") and build.shoulder_weapon_left and\
	cur_mode == MODES.NEUTRAL:
		begin_designating("shoulder_weapon_left")
	elif event.is_action_pressed("shoulder_weapon_right_shoot") and build.shoulder_weapon_right and\
	cur_mode == MODES.NEUTRAL:
		begin_designating("shoulder_weapon_right")
	elif event.is_action_pressed("reload_mode") and not _designating.is_empty():
		cancel_designating()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload_mode"):
		# Tap R to toggle reload mode — press once to enter, press again to exit.
		# While in mode, click any arm weapon to reload it. Lock mode also exits
		# reload as a courtesy if the player switches intent.
		if cur_mode == MODES.RELOAD:
			cur_mode = MODES.NEUTRAL
			emit_signal("update_reload_mode", false)
		else:
			cur_mode = MODES.RELOAD
			emit_signal("update_reload_mode", true)
	elif event.is_action_pressed("lock_mode") and build.chipset.can_lock:
		cur_mode = MODES.ACTIVATING_LOCK
		emit_signal("update_lock_mode", true)
		for weapon_type in WeaponSFXs.keys():
			stop_shooting(weapon_type)
	elif event.is_action_released("lock_mode") and build.chipset.can_lock:
		locking_to = false
		cur_mode = MODES.NEUTRAL
		emit_signal("update_lock_mode", false)
	elif event.is_action_pressed("thruster_dash") and not is_stunned() and not is_movement_locked():
		sprinting_timer = SPRINTING_TIMEOUT
	elif event.is_action_released("thruster_dash") and not is_stunned() and not is_movement_locked():
		if sprinting_timer > 0.0 and movement_type != "tank":
			dash(get_input())
		stop_sprinting(get_input().normalized())
		sprinting_timer = 0.0
	elif event.is_action_pressed("debug_3"):
		die(self, "Myself")
	elif event.is_action_pressed("shield"):
		shield_up()
	elif event.is_action_released("shield"):
		shield_down()
	elif event.is_action_pressed("throttle_up"):
		increase_throttle(false, THROTTLE_STEP)
	elif event.is_action_pressed("throttle_down"):
		decrease_throttle(false, THROTTLE_STEP)
	elif event.is_action_pressed("debug_6"):
		MechOS.toggle_app("equipment")


func _unhandled_input(event: InputEvent) -> void:
	if controls_locked:
		return
	if event.is_action_pressed("interact"):
		var thing = get_closest_interactable()
		if thing != null and thing.has_method("interact"):
			thing.interact(self)
			if thing is LootContainer:
				current_open_container = thing
				var screen_size := get_viewport().get_visible_rect().size
				
				if not MechOS.is_app_open("mech_cargo"):
					var mech_win = MechOS.open_inventory("mech_cargo", mech_inventory, "MECH CARGO")
					if mech_win != null:
						mech_win.position = Vector2(80, (screen_size.y - mech_win.size.y) * 0.5)
				
				var container_win = MechOS.open_inventory("container", thing.inventory, thing.display_name)
				if container_win != null:
					container_win.position = Vector2(screen_size.x - container_win.size.x - 80, (screen_size.y - container_win.size.y) * 0.5)
				
			get_viewport().set_input_as_handled()

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
	if build.head and build.head.visual_range > 0:
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
		Cam.offset = Cam.offset.limit_length(build.head.visual_range)


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
	check_weapon_input("arm_weapon_left")
	check_weapon_input("arm_weapon_right")
	check_weapon_input("shoulder_weapon_left")
	check_weapon_input("shoulder_weapon_right")


func check_weapon_input(weapon_name):
	var node = get_weapon_part(weapon_name)
	var weapon_ref = build[weapon_name]
	if not Input.is_action_pressed(weapon_name + "_shoot"):
		_awaiting_release.erase(weapon_name)
		stop_shooting(weapon_name)
		return
	if _awaiting_release.has(weapon_name):
		return
	# Shoulder weapons fire on release (release_designating), never auto.
	if weapon_name in SHOULDER_SLOTS:
		return
	if weapon_ref and weapon_ref.auto_fire and cur_mode == MODES.NEUTRAL and not node.reloading:
		shoot(weapon_name, true)

func setup(arena_ref):
	arena = arena_ref
	mecha_name = "Player"
	$MechaShadowGen.enabled = true

	if Debug.get_setting("debug_loadout"):
		set_debug_loadout()
	elif PlayerProgress.get_current_mecha():
		part_grades = PlayerProgress.get_current_grades().duplicate()
		set_parts_from_design(PlayerProgress.get_current_mecha())
	else:
		push_warning("No design set for player, using the same as the debug loadout")
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

func shoot(type, is_auto_fire = false):
	if not MouseManager.is_aiming():
		return
	super.shoot(type, is_auto_fire)


# SHOULDER WEAPONS (see Mecha.fire_at_point)

func begin_designating(slot: String) -> void:
	_designating[slot] = 0.0
	_pending_fire.erase(slot)


# Fires `slot` at its designator. A weapon without a designator shoots as
# before (at the locked target if there is one). A tap_self weapon (the smoke
# launcher) tapped for less than TAP_TIME fires at the mecha itself. With
# look limits off, a salvo aimed outside the look angle waits
# PENDING_FIRE_TIME s for the mecha to face it.
func release_designating(slot: String) -> void:
	if not _designating.has(slot):
		return
	var held: float = _designating[slot]
	_designating.erase(slot)
	var weapon = build.get(slot)
	if not weapon or is_dead:
		return
	if not weapon.has_designator():
		shoot(slot)
		return
	var point := get_designator_aim(slot)
	if weapon.tap_self and held < TAP_TIME:
		point = global_position
	var reason := fire_at_point(slot, point)
	if reason == "not_facing":
		_pending_fire[slot] = {"point": point, "time": PENDING_FIRE_TIME}
	elif reason == "no_ammo":
		AudioManager.play_sfx("no_ammo", global_position)
		create_sound("quiet", "no_ammo", 600)


# Drops every held designator and waiting salvo; nothing fires.
func cancel_designating() -> void:
	_designating.clear()
	_pending_fire.clear()
	if designator:
		var none: Array[Dictionary] = []
		designator.set_marks(none)


func is_designating(slot: String) -> bool:
	return _designating.has(slot)


# Where `slot`'s salvo goes for the current cursor, by the SYS setting
# "Designator Look Limits"; for a lock-on weapon with a target locked, on
# that target.
func get_designator_aim(slot: String) -> Vector2:
	if fires_at_lock(slot):
		return get_locked_to().global_position
	var cursor: Vector2 = scripted_aim if controls_locked and scripted_aim != null else get_global_mouse_position()
	return designator_point(slot, cursor, Profile.get_option("designator_look_limits"))


# Waiting salvos fire once the mecha faces them; held designators are drawn.
# Only while a fire button is held: one wall ray per direct-fire designator.
func _update_designators(dt: float) -> void:
	if is_dead or controls_locked:
		if not _designating.is_empty() or not _pending_fire.is_empty():
			cancel_designating()
		return
	for slot in _pending_fire.keys():
		var pending: Dictionary = _pending_fire[slot]
		pending.time -= dt
		var reason := fire_at_point(slot, pending.point)
		if reason != "not_facing" or pending.time <= 0.0:
			_pending_fire.erase(slot)
	var marks: Array[Dictionary] = []
	var look_limits: bool = Profile.get_option("designator_look_limits")
	for slot in _designating:
		_designating[slot] += dt
		var weapon = build.get(slot)
		if not weapon or not weapon.has_designator():
			continue
		if weapon.tap_self and _designating[slot] < TAP_TIME:
			continue
		var point := get_designator_aim(slot)
		var node = get_weapon_part(slot)
		var origin: Vector2 = global_position
		if node and node.shooting_pos_array.size() > 0:
			origin = node.shooting_pos_array[node.shooting_pos_idx].global_position
		marks.append({
			"shape": weapon.designator,
			"centre": global_position,
			"origin": origin,
			"point": point,
			"end": point if weapon.is_indirect_fire else designator_clip(slot, point),
			"radius": weapon.scatter_radius,
			"width": weapon.designator_width,
			"facing": get_facing(),
			"gimbal": weapon.gimbal,
			"min_range": weapon.min_range,
			"max_range": weapon.max_range,
			"look_limits": look_limits,
			"direct": not weapon.is_indirect_fire,
			"dashed": can_fire_at_point(slot, point) != "",
		})
	if designator:
		designator.set_marks(marks)


# THE PLAYER'S VIEW
#
# The world is dark round the player except in its light cone, drawn by 2D
# lights (see MapSenses). What the player can see matches it: a mecha or
# Entity is shown only inside the cone (VIEW_CONE_HALF_ANGLE either side of
# the light, out to its reach) or within VIEW_PERIPHERAL all round, and not
# behind a building wall, in a different building from the player (generated
# or hand-made), or in or behind smoke. Two in the same building see each
# other. The rest are faded out (their modulate alpha). Each is checked every
# VIEW_CHECK_TIME s (one wall ray, building and smoke lookups) and fades at
# VIEW_FADE_SPEED. Nothing is hidden while controls are locked (cutscenes),
# and dead ones are left alone (Entities fade their own corpses).

func can_see_body(body: Node2D) -> bool:
	if controls_locked or is_dead:
		return true
	var to := body.global_position
	var dist := global_position.distance_to(to)
	if dist > VIEW_RANGE:
		return true
	if dist > VIEW_PERIPHERAL and not in_view_cone(to):
		return false
	if MapSenses.building_key_at(self, global_position) != MapSenses.building_key_at(self, to):
		return false
	return not MapSenses.sight_blocked(get_world_2d(), global_position, to)


# Whether `point` is inside the light cone (angle and reach only, no walls).
func in_view_cone(point: Vector2) -> bool:
	var offset: Vector2 = point - Light.global_position
	if offset.length() > get_view_reach():
		return false
	var forward := Vector2.UP.rotated(Light.global_rotation)
	return absf(rad_to_deg(forward.angle_to(offset))) <= VIEW_CONE_HALF_ANGLE


func get_view_reach() -> float:
	if Light.texture == null:
		return 0.0
	return Light.texture.get_width() * Light.texture_scale * VIEW_CONE_REACH


func is_hidden_from_view(body) -> bool:
	return _view_hidden.has(body)


func _update_view(dt: float) -> void:
	_view_timer -= dt
	if _view_timer <= 0.0:
		_view_timer = VIEW_CHECK_TIME
		_view_bodies.clear()
		_view_hidden.clear()
		for group in ["mecha", "entity"]:
			for body in get_tree().get_nodes_in_group(group):
				if body == self or not (body is Node2D) or body.get("is_dead") == true:
					continue
				_view_bodies.append(body)
				if not can_see_body(body):
					_view_hidden[body] = true
	for body in _view_bodies:
		if is_instance_valid(body) and body.get("is_dead") != true:
			var target := 0.0 if _view_hidden.has(body) else 1.0
			body.modulate.a = move_toward(body.modulate.a, target, VIEW_FADE_SPEED * dt)


func _exit_tree() -> void:
	for body in _view_bodies:
		if is_instance_valid(body):
			body.modulate.a = 1.0


func lock_controls() -> void:
	if controls_locked:
		return
	controls_locked = true
	scripted_move = Vector2.ZERO
	scripted_aim = null
	cancel_designating()
	for weapon_type in WeaponSFXs.keys():
		stop_shooting(weapon_type)
	if cur_mode == MODES.ACTIVATING_LOCK or cur_mode == MODES.LOCK:
		locking_to = false
		cur_mode = MODES.NEUTRAL
		emit_signal("update_lock_mode", false)


func unlock_controls() -> void:
	controls_locked = false
	scripted_move = Vector2.ZERO
	scripted_aim = null


func _on_cursor_mode_changed(_mode) -> void:
	if MouseManager.is_aiming():
		for weapon_type in WeaponSFXs.keys():
			if Input.is_action_pressed(weapon_type + "_shoot"):
				_awaiting_release[weapon_type] = true
	else:
		cancel_designating()
		for weapon_type in WeaponSFXs.keys():
			stop_shooting(weapon_type)
		if cur_mode == MODES.ACTIVATING_LOCK:
			locking_to = false
			cur_mode = MODES.NEUTRAL
			emit_signal("update_lock_mode", false)

# CALLBACKS


func _on_finished_reloading():
	emit_signal("finished_reloading")


func _on_reloading(reload_time, side):
	emit_signal("reloading", reload_time, side)
