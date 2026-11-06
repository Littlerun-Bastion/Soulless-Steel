extends Mecha

signal update_reload_mode
signal update_lock_mode
signal update_building_status
signal reloading
signal finished_reloading
signal lost_health
# A sweep went out (result from Mecha.sweep), or couldn't ("cooldown").
signal sweep_done(result: Dictionary)
signal sweep_refused(reason: String)

const INSIDE_BUILDING_ZOOM_MUL = 1.4
const DEFAULT_CAM_ZOOM = Vector2(.5,.5)
const ZOOM_SPEED = 2

const ROTATION_DEADZONE = 20
## The edge pan (pan_velocity): how near a screen edge (px) the cursor pans
## the camera, and how long (s) the pan takes to cross the sight circle's
## radius with the cursor right at the edge. Placeholders.
const MOVE_CAMERA_SCREEN_MARGIN = 260
const MOVE_CAMERA_PAN_TIME = 1.0
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
## The player's view: how often (s) each mecha and Entity is checked, and how
## fast one fades out when hidden or back in when seen (alpha per s).
const VIEW_CHECK_TIME = 0.1
const VIEW_FADE_SPEED = 5.0
## The distance (px) all round within which things nobody's light falls on are
## seen anyway (20 m).
const VIEW_PERIPHERAL = 400.0
## Sounds of the illuminator key switching it on and off. Placeholders.
const ILLUMINATOR_ON_SFX = "select"
const ILLUMINATOR_OFF_SFX = "back"
## The illuminator key (see press_illuminator_key): two presses this close
## (real seconds: it times the player's fingers, not the game) latch the
## light on. Placeholder.
const ILLUMINATOR_DOUBLE_TAP = 0.25
## The vision source whose mechas are outlined rather than shown.
const OUTLINE_SOURCE = "seeker"
## How long (s) a body the player saw stays a live sight contact after the
## last view check that saw it.
const SIGHT_CONTACT_TTL = 0.3
## The head's IR tracks (see THE PLAYER'S VIEW): their contact source and
## kind (IRSensing), and how long one stays live after the last view check
## that sensed it.
const IR_SOURCE = IRSensing.SOURCE
const IR_KIND = IRSensing.KIND
const IR_TTL = 0.3
## The sweep cone's width at the start, and how much one mouse wheel notch
## changes it (degrees). Placeholders.
const SWEEP_START_WIDTH = 90.0
const SWEEP_WIDTH_STEP = 10.0

@onready var Cam = $Camera2D
@onready var Light = $MechaLight
@onready var Darkness: PointLight2D = $MechaShadowGen

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
# those hidden from the player, and of those the ones the Seeker outlines
# (body -> true).
var _view_bodies: Array = []
var _view_hidden := {}
var _view_outlined := {}
var _view_timer := 0.0
# The sweep cone (see SENSOR SWEEP): aimed while the sweep key is held; the
# width is kept between sweeps.
var sweep_width := SWEEP_START_WIDTH
var _sweep_aiming := false
# The internal key (see INTERNAL BAY): seconds it has been held, or -1.
var _internal_held := -1.0
# The illuminator key (see press_illuminator_key): whether the light is on
# only while the key is down, and when (real s) the last press that could
# start a double tap came.
var _illuminator_held := false
var _illuminator_tap_at := -INF

func _ready():
	super()
	Illumination.ensure_key_action()
	ensure_flag_key_action()
	ensure_squad_key_actions()
	var layer := CanvasLayer.new()
	layer.layer = DESIGNATOR_LAYER
	layer.follow_viewport_enabled = true
	add_child(layer)
	designator = DESIGNATOR_SCRIPT.new()
	layer.add_child(designator)
	# Its lock turns only its head (aim_at), not the whole mecha.
	faces_lock = false
	# Sound is heard at the mecha, not at the panned camera's centre.
	$AudioListener.make_current()
	# The darkness is placed on the camera's view each frame (_process), not
	# carried by the mecha.
	Darkness.top_level = true

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

	var profile_start := FrameProfiler.start()
	if controls_locked:
		apply_movement(dt, scripted_move)
	else:
		check_input()
		apply_movement(dt, get_input())
	_update_designators(dt)
	_update_view(dt)
	FrameProfiler.add("player", profile_start)

	#Update sprinting timer
	if sprinting_timer > 0.0:
		sprinting_timer = max(sprinting_timer - dt, 0.0)
		if sprinting_timer <= 0.0:
			is_sprinting = true

	aim_at(dt, scripted_aim if controls_locked else get_global_mouse_position())
		
	update_camera_zoom(dt)
	update_camera_offset(dt)


## Turns the mecha to `target_pos` (the cursor, or a cutscene's aim; null for
## none): the body, shoulders and arms, and the head too unless a lock holds
## it. POINTER (Alt) locks the body; head, shoulders and arms keep tracking
## within their rotation ranges. While the player holds a lock, with Lock Head
## Tracking on, the head turns to the locked target instead, within its
## rotation_range at its rotation_acc (stopping at its limit, never turning
## the body), and the light with it.
func aim_at(dt: float, target_pos) -> void:
	var head_target = _lock_head_target()
	if target_pos != null and target_pos.distance_to(global_position) > ROTATION_DEADZONE:
		var lock_body: bool = not controls_locked and\
		(Input.is_action_pressed("strafe") or not MouseManager.is_aiming())
		apply_rotation_by_point(dt, target_pos, lock_body, head_target)
	elif head_target != null:
		_turn_part_to(Head, build.head.rotation_acc, build.head.rotation_range, head_target, dt)
		_aim_light()


# Where the head looks while a lock holds it (see aim_at), or null.
func _lock_head_target():
	if controls_locked or not build.head or is_part_lost("head"):
		return null
	if not Profile.get_option("lock_head_tracking"):
		return null
	var locked = get_locked_to()
	return locked.global_position if locked else null


# The darkness (MechaShadowGen) sits on the centre of the current camera's
# view, so it follows the pan, and a cutscene's camera too.
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	var centre: Vector2 = cam.get_screen_center_position() if cam != null else global_position
	if Darkness.global_position != centre:
		Darkness.global_position = centre


func _input(event):
	# A shoulder release is never missed: while paused or stunned it drops
	# the salvo instead of firing it.
	for slot in SHOULDER_SLOTS:
		if event.is_action_released(slot + "_shoot") and _designating.has(slot):
			if paused or is_stunned() or controls_locked:
				_designating.erase(slot)
			else:
				release_designating(slot)
	if event.is_action_released("sweep") and _sweep_aiming:
		if paused or is_stunned() or controls_locked:
			cancel_sweep()
		else:
			release_sweep()
	if event.is_action_released("use_internal") and _internal_held >= 0.0:
		if paused or is_stunned() or controls_locked:
			cancel_internal()
		else:
			release_internal()
	# A held light goes out when the key comes up, whatever else is going on.
	if event.is_action_released(Illumination.KEY_ACTION):
		release_illuminator_key()
	if paused or is_stunned() or controls_locked:
		return
	if _sweep_aiming and _sweep_aim_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("sweep"):
		begin_sweep()
		get_viewport().set_input_as_handled()
		return
	if _internal_held >= 0.0 and event.is_action_pressed("reload_mode"):
		cancel_internal()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("use_internal"):
		begin_internal()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(Illumination.KEY_ACTION):
		press_illuminator_key()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(FLAG_ACTION):
		toggle_flag()
		get_viewport().set_input_as_handled()
		return
	# A buddy-up offer's answer (CombatScene.offer_buddy).
	if event.is_action_pressed(ACCEPT_ACTION) and arena is Node and arena.has_method("accept_offer"):
		arena.accept_offer()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(DECLINE_ACTION) and arena is Node and arena.has_method("decline_offer"):
		arena.decline_offer()
		get_viewport().set_input_as_handled()
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
					# A wreck's shed parts, crossed out under its loot.
					if container_win.has_method("show_unsalvageable"):
						container_win.show_unsalvageable(thing)
					container_win.position = Vector2(screen_size.x - container_win.size.x - 80, (screen_size.y - container_win.size.y) * 0.5)
				# A wreck's kill record goes beside its loot (KillRecord).
				if thing is Wreck and not thing.kill_record.is_empty():
					MechOS.open_kill_record(thing.kill_record, container_win)
				
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


# The cursor near a screen edge pans the camera that way (Camera.pan_offset,
# pan_velocity), out to the sight circle (Mecha.sight_radius) and no further.
# With no head the camera doesn't pan.
func update_camera_offset(dt):
	var limit := sight_radius() if build.head and not is_part_lost("head") else 0.0
	if limit <= 0.0:
		Cam.pan_offset = Vector2.ZERO
		return
	var velocity := pan_velocity(get_viewport().get_mouse_position(), get_viewport().get_visible_rect().size, limit)
	Cam.pan_offset = (Cam.pan_offset + velocity * dt).limit_length(limit)


## How fast (px/s) the camera pans with the cursor at `mouse` on a `screen`
## px screen, panning out to `limit` px. Inside MOVE_CAMERA_SCREEN_MARGIN of
## an edge it pans that way, at limit / MOVE_CAMERA_PAN_TIME right at the
## edge, slowing with the square of how far in from the edge the cursor is to
## nothing at the margin's inner side. In a corner both ways at once, the
## pair scaled down by sqrt(2).
static func pan_velocity(mouse: Vector2, screen: Vector2, limit: float) -> Vector2:
	var margin := float(MOVE_CAMERA_SCREEN_MARGIN)
	var push := Vector2.ZERO
	var axes := 0
	for axis in 2:
		var into := 0.0
		if mouse[axis] <= margin:
			into = -(1.0 - mouse[axis] / margin)
		elif mouse[axis] >= screen[axis] - margin:
			into = 1.0 - (screen[axis] - mouse[axis]) / margin
		else:
			continue
		into = clampf(into, -1.0, 1.0)
		push[axis] = into * absf(into)
		axes += 1
	if axes == 2:
		push /= sqrt(2.0)
	return push * limit / MOVE_CAMERA_PAN_TIME


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
	# Set in the Hangar: the callsign in the LOC app, Anonymous in DEP.
	callsign = PlayerProgress.get_callsign()
	is_anonymous = PlayerProgress.deploy_anonymous
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
		if not _designating.is_empty() or not _pending_fire.is_empty() or _sweep_aiming or _internal_held >= 0.0:
			cancel_sweep()
			cancel_internal()
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
	if _sweep_aiming:
		marks.append(_sweep_mark())
	if _internal_held >= 0.0:
		_internal_held += dt
		if _internal_held >= TAP_TIME:
			marks.append(_internal_mark())
	if designator:
		designator.set_marks(marks)


# INTERNAL BAY (see Mecha.use_internal)
#
# The internal key: a passive part (ECM, Seeker, Biosensor) switches on or
# off when pressed. A device part: a tap (shorter than TAP_TIME) puts it out
# at the mecha (a ward or decoy at its feet, a drone straight ahead, a flare
# straight ahead as far as it goes); held, the designator shows where it
# would go (a ward's or decoy's landing circle within its throw range, a
# flare's lit circle, a drone's line toward the cursor) and releasing puts it
# there; the reload key cancels. With no charges left, or a Seeker shot down,
# it clicks like an empty gun.

func begin_internal() -> void:
	if not MouseManager.is_aiming() or build.internal == null:
		return
	if build.internal.is_passive():
		_use_internal_feedback(use_internal())
		return
	_internal_held = 0.0


func release_internal() -> void:
	if _internal_held < 0.0:
		return
	var held := _internal_held
	_internal_held = -1.0
	_use_internal_feedback(use_internal(null if held < TAP_TIME else get_global_mouse_position()))


func cancel_internal() -> void:
	_internal_held = -1.0


func is_internal_held() -> bool:
	return _internal_held >= 0.0


# THE ILLUMINATOR KEY
#
# Press and hold: the light is on while the key is down, and goes out when it
# comes up. Two presses within ILLUMINATOR_DOUBLE_TAP latch it on: it stays on
# once the key comes up. Any press while it is on and latched puts it out
# and unlatches it, so going dark is always one press; that press can't start
# a double tap. A light switched on any other way (it starts on, or
# toggle_illuminator) counts as latched. Each switch plays its sound, and the
# light still costs and gives the mecha away as Mecha.set_illuminator says.

## `now` (real s) is for tests; the game uses the clock.
func press_illuminator_key(now := -1.0) -> void:
	if now < 0.0:
		now = Time.get_ticks_msec() / 1000.0
	if is_illuminator_latched():
		_illuminator_tap_at = -INF
		_switch_illuminator(false)
		return
	if now - _illuminator_tap_at <= ILLUMINATOR_DOUBLE_TAP:
		_illuminator_tap_at = -INF
		_illuminator_held = false
		_switch_illuminator(true)
		return
	_illuminator_tap_at = now
	_illuminator_held = true
	_switch_illuminator(true)


func release_illuminator_key() -> void:
	if not _illuminator_held:
		return
	_illuminator_held = false
	_switch_illuminator(false)


## The light is on and stays on when the key comes up.
func is_illuminator_latched() -> bool:
	return illuminator_on and not _illuminator_held


## The light is on only while the key is down.
func is_illuminator_held() -> bool:
	return illuminator_on and _illuminator_held


## Switches the light on or off outright, as latched.
func toggle_illuminator() -> void:
	_illuminator_held = false
	_switch_illuminator(not illuminator_on)


func _switch_illuminator(on: bool) -> void:
	if on == illuminator_on:
		return
	set_illuminator(on)
	AudioManager.play_sfx(ILLUMINATOR_ON_SFX if on else ILLUMINATOR_OFF_SFX)


# ROUNDS AND SOUNDS (see Mecha): a round from someone else that comes within
# SHOT_WEDGE_RADIUS, or a loud sound from something the player can't see,
# puts a wedge in its contacts, which the radar shows (PlayerRadar). The car
# alarm is already an alarm contact (CombatScene).

func _on_nearby_projectile_area_entered(area) -> void:
	var info = area.get("original_mecha_info")
	if not (info is Dictionary) or not is_instance_valid(info.get("body")) or info.body == self:
		return
	var heading = area.get("dir")
	if not (heading is Vector2):
		heading = area.get("velocity") if area.get("velocity") is Vector2 else Vector2.ZERO
	if round_comes_close(area.global_position, heading):
		note_round_from(info.body, info.get("from", info.body.global_position))


func heard_sound(sound_data) -> void:
	if sound_data.get("type") == "car_alarm" or sound_data.get("volume_type") != "loud":
		return
	if sound_data.get("source") == self:
		return
	note_sound_from(sound_data.get("source"), sound_data.position)


## The Flag key (raise_flag): raises the Flag at once, or starts lowering it
## (Mecha.lower_flag's wind-up). While the capsule is exposed, raising it
## again is the emergency Flag, not a choice.
const FLAG_ACTION := "raise_flag"
const FLAG_DEFAULT_KEY := KEY_X


func toggle_flag() -> void:
	if is_flagged() and not is_lowering_flag():
		lower_flag()
	else:
		raise_flag(not is_exposed)


## Adds the Flag key action, bound to FLAG_DEFAULT_KEY, if the project's
## Input Map lacks it. One set in Project Settings is left as it is.
static func ensure_flag_key_action() -> void:
	_ensure_key_action(FLAG_ACTION, FLAG_DEFAULT_KEY)


## The companion keys (Phase 5): the squad orders menu (HudSquadOrders),
## and the answer to a buddy-up offer (CombatScene.offer_buddy).
const ORDERS_ACTION := "squad_orders"
const ORDERS_DEFAULT_KEY := KEY_Z
const ACCEPT_ACTION := "accept_offer"
const ACCEPT_DEFAULT_KEY := KEY_Y
const DECLINE_ACTION := "decline_offer"
const DECLINE_DEFAULT_KEY := KEY_N
## How far (px) from the reticle a mecha may be to count as the player's
## target for an attack order, when nothing is locked. Placeholder.
const TARGET_PICK_RADIUS := 600.0


static func ensure_squad_key_actions() -> void:
	_ensure_key_action(ORDERS_ACTION, ORDERS_DEFAULT_KEY)
	_ensure_key_action(ACCEPT_ACTION, ACCEPT_DEFAULT_KEY)
	_ensure_key_action(DECLINE_ACTION, DECLINE_DEFAULT_KEY)


static func _ensure_key_action(action: String, default_key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var key := InputEventKey.new()
	key.physical_keycode = default_key
	InputMap.action_add_event(action, key)


## What the player means by "my target": the mecha it is locked on to, else
## the living mecha or creature nearest the reticle within
## TARGET_PICK_RADIUS, never a companion. Null for none.
func pointed_target():
	var locked = get_locked_to()
	if locked and is_instance_valid(locked) and not locked.is_dead:
		return locked
	if not (arena is Node) or not arena.has_method("get_mechas"):
		return null
	var cursor := get_global_mouse_position()
	var squad = arena.player_squad(false) if arena.has_method("player_squad") else null
	var best = null
	var best_dist := TARGET_PICK_RADIUS
	var bodies: Array = arena.get_mechas()
	if arena.has_method("get_entities"):
		bodies = bodies + arena.get_entities()
	for body in bodies:
		if body == self or not is_instance_valid(body) or body.is_dead:
			continue
		if squad != null and squad.is_in(body):
			continue
		var d: float = cursor.distance_to(body.global_position)
		if d < best_dist:
			best = body
			best_dist = d
	return best


## The orders menu's pick (HudSquadOrders): the scene passes it on.
func give_order(kind: String) -> bool:
	if arena is Node and arena.has_method("give_order"):
		return arena.give_order(kind)
	return false


func _use_internal_feedback(reason: String) -> void:
	if reason == "no_charges" or reason == "lost":
		AudioManager.play_sfx("no_ammo", global_position)


func _internal_mark() -> Dictionary:
	var part = build.internal
	var cursor := get_global_mouse_position()
	var drone: bool = part != null and part.function == "drone"
	var flare: bool = part != null and part.function == "flare"
	var point := cursor if drone else internal_throw_point(cursor)
	return {
		"shape": "line" if drone else "circle",
		"centre": global_position,
		"origin": global_position,
		"point": point,
		"end": point,
		"radius": float(part.sensor_range) if flare else Device.RING_RADIUS,
		"width": 0.0,
		"facing": get_facing(),
		"gimbal": 180.0,
		"min_range": 0.0,
		"max_range": 0.0 if drone else float(part.throw_range),
		"look_limits": false,
		"direct": true,
		"dashed": can_use_internal() != "",
	}


# SENSOR SWEEP (see Mecha.sweep)
#
# Holding the sweep key shows the cone from the mecha toward the cursor; the
# mouse wheel changes its width (SWEEP_WIDTH_STEP a notch, between
# SWEEP_MIN_WIDTH and 360, and not the throttle while aiming); releasing
# sweeps; the reload key cancels. Pressed while the sweep is cooling down,
# it doesn't aim and reports why (sweep_refused). The result goes to the HUD
# (sweep_done) and the log.

func begin_sweep() -> void:
	if not MouseManager.is_aiming():
		return
	var reason := can_sweep()
	if reason != "":
		sweep_refused.emit(reason)
		return
	_sweep_aiming = true


func release_sweep() -> void:
	if not _sweep_aiming:
		return
	_sweep_aiming = false
	var result := sweep(get_global_mouse_position() - global_position, sweep_width)
	if not result.ok:
		sweep_refused.emit(result.reason)
		return
	MechLog.write("SNS", "Sweep %d°: %s" % [roundi(result.width), describe_sweep(result.counts).to_lower()], MechLog.Kind.COMBAT)
	sweep_done.emit(result)


func cancel_sweep() -> void:
	_sweep_aiming = false


func is_sweep_aiming() -> bool:
	return _sweep_aiming


# The wheel and the reload key while aiming a sweep; true if it used `event`.
func _sweep_aim_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			sweep_width = minf(sweep_width + SWEEP_WIDTH_STEP, SWEEP_MAX_WIDTH)
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			sweep_width = maxf(sweep_width - SWEEP_WIDTH_STEP, SWEEP_MIN_WIDTH)
			return true
	if event.is_action_pressed("reload_mode"):
		cancel_sweep()
		return true
	return false


func _sweep_mark() -> Dictionary:
	var to_cursor := get_global_mouse_position() - global_position
	return {
		"shape": "cone",
		"centre": global_position,
		"facing": to_cursor.normalized() if to_cursor != Vector2.ZERO else Vector2.UP.rotated(global_rotation),
		"width": sweep_width,
		"radius": SWEEP_RANGE,
		"dashed": false,
	}


# THE PLAYER'S VIEW
#
# Nothing past the sight circle (Mecha.sight_radius) is seen: the screen is
# black past it (HeatmapEffects' sight mask), and a body out there is hidden
# before any other check.
#
# Inside the circle, the world is dark round the player except in the light
# cones, drawn by 2D lights (see MapSenses). What the player can see matches
# it. A body any illuminator lights (its own, another mecha's cone on it, or
# the player's own cone: half the head's illuminator_angle either side of
# where the head points, out to its reach, see Illumination) is shown
# wherever it is in the circle, walls between or not, unless it is in a
# different building or in or behind smoke (Illumination.seen_lit). A body
# nobody lights is shown only within VIEW_PERIPHERAL all round, and not
# behind a building wall, in a different building from the player
# (generated or hand-made), or in or behind smoke: with its own light off,
# the player sees nothing else. Two in the same building see each other.
# The rest are faded out (their modulate alpha). Each is checked every
# VIEW_CHECK_TIME s (one wall ray, building and smoke lookups) and fades at
# VIEW_FADE_SPEED. Nothing is hidden while controls are locked (cutscenes),
# and dead ones are left alone (Entities fade their own corpses).
#
# A body under a live vision contact from a flare or the Biosensor
# (ContactStore.has_live_vision) is shown whatever the checks say, and isn't
# checked at all (no ray). A body the checks show becomes a sight contact.
# A mecha or device the checks hide but the Seeker (OUTLINE_SOURCE) covers
# stays hidden and is outlined instead: the HUD draws the edges of its
# sprites (HudVisionOutlines, get_outlined_bodies). A creature the Seeker
# covers has no sprites to outline and is shown in full. Other mechas'
# devices (Device) are checked the same way, without contacts; the player's
# own are always shown.

#
# The head's IR sensor (IRSensing) works within the sight circle too. A body at
# least as hot as its IR identification is shown as a lit one is: walls
# between or not, unless in another building or in or behind smoke. One at
# least as hot as its IR sensitivity that the player can't see otherwise is
# an UNKNOWN contact (IR_SOURCE, a ping): reported at every view check, so
# its HUD marker follows the body live (HudContacts), and once it's seen, or
# cools, or is lost, the marker stays where it was last and fades as a ghost.
# A body that comes into view has its track dropped, so no marker trails it.
#
# A Fisher whose harpoon is in the player is always shown (Fisher.
# is_tethered_to): the player can follow the tether to it. Past the sight
# circle the mask still covers it.

func can_see_body(body: Node2D) -> bool:
	if controls_locked or is_dead:
		return true
	# A Fisher's harpoon in the player: it's on the end of the tether.
	if body.has_method("is_tethered_to") and body.is_tethered_to(self):
		return true
	var to := body.global_position
	var dist := global_position.distance_to(to)
	if dist > sight_radius():
		return false
	if Illumination.seen_lit(self, body) or IRSensing.identifies(self, body):
		return true
	if dist > VIEW_PERIPHERAL:
		return false
	if MapSenses.building_key_of(self) != MapSenses.building_key_of(body):
		return false
	return not MapSenses.sight_blocked(get_world_2d(), global_position, to)


# Whether `point` is inside the light cone (angle and reach only, no walls).
# Never while the illuminator is off. What the player sees there is decided
# by what the cone lights (Illumination.is_lit), walls and all.
func in_view_cone(point: Vector2) -> bool:
	return illuminator_on and Illumination.in_cone(Light, point)


func get_view_reach() -> float:
	return Illumination.reach(Light)


## The vision cone's angle (degrees, edge to edge), from the head.
func get_view_angle() -> float:
	return Illumination.cone_angle(Light)


func is_hidden_from_view(body) -> bool:
	return _view_hidden.has(body)


## The mechas and devices hidden from view that the Seeker outlines.
func get_outlined_bodies() -> Array:
	return _view_outlined.keys().filter(func(b): return is_instance_valid(b) and b.get("is_dead") != true)


func _update_view(dt: float) -> void:
	_view_timer -= dt
	if _view_timer <= 0.0:
		_view_timer = VIEW_CHECK_TIME
		_view_bodies.clear()
		_view_hidden.clear()
		_view_outlined.clear()
		for group in ["mecha", "entity"]:
			for body in get_tree().get_nodes_in_group(group):
				if body == self or not (body is Node2D) or body.get("is_dead") == true:
					continue
				_view_bodies.append(body)
				if contacts.has_live_vision(body, OUTLINE_SOURCE):
					continue
				if can_see_body(body):
					_report_sight(body)
					contacts.drop(body, IR_SOURCE)
				elif not contacts.has_live_vision(body):
					_view_hidden[body] = true
					_track_by_heat(body)
				elif group == "mecha":
					_view_hidden[body] = true
					_view_outlined[body] = true
		# Others' devices (wards, drones, decoys) are seen like mechas, or
		# shown or outlined by a vision contact (a decoy a flare or the
		# Seeker covers); the player always knows where its own are, and a
		# burning flare is seen from anywhere. They make no sight contacts.
		for device in get_tree().get_nodes_in_group("device"):
			if device.get("owner_mecha") == self or not (device is Node2D) or device.get("reveal_everyone") == true:
				continue
			_view_bodies.append(device)
			if contacts.has_live_vision(device, OUTLINE_SOURCE):
				continue
			if not can_see_body(device):
				_view_hidden[device] = true
				if contacts.has_live_vision(device):
					_view_outlined[device] = true
	for body in _view_bodies:
		if is_instance_valid(body) and body.get("is_dead") != true:
			var target := 0.0 if _view_hidden.has(body) else 1.0
			# Only a body still fading is written: a modulate set marks the
			# item for redraw, and most bodies sit at their target.
			if body.modulate.a != target:
				body.modulate.a = move_toward(body.modulate.a, target, VIEW_FADE_SPEED * dt)


# A body the player can't see, picked up by its heat within the sight circle:
# an UNKNOWN track, live until the next view check or two (IR_TTL).
func _track_by_heat(body: Node2D) -> void:
	if global_position.distance_to(body.global_position) > sight_radius() or not IRSensing.senses(self, body):
		return
	contacts.report(body, IR_KIND, body.global_position, IR_SOURCE, IR_TTL)


# A body the view shows is a sight contact, unless it is past the sight
# circle (a tethered Fisher, shown for its tether) or the view is a
# cutscene's (controls locked: everything is shown).
func _report_sight(body: Node2D) -> void:
	if controls_locked or is_dead:
		return
	if global_position.distance_to(body.global_position) > sight_radius():
		return
	contacts.report(body, ContactStore.kind_of(body), body.global_position, "sight", SIGHT_CONTACT_TTL)


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
		cancel_sweep()
		cancel_internal()
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
