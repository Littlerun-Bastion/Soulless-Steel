extends "res://game/expedition/Expedition.gd"

# ObserverArena: a small map (database/maps/observer_arena.tscn) for watching
# NPCs and controlling what they meet, opened from the main menu's OBSERVE
# button. It runs on Expedition's systems (route grid, vehicle field, NPC
# behaviour) with no player: no stakes, no director, no mission and no intro;
# the NPCs start at once and run at full rate (Enemy.lod_tier is 0 with no
# player).
#
# The control panel (ObserverPanel) spawns NPCs, squads and dummies at the
# cursor, sets off events there, changes the game speed and switches the
# overlays (ObserverOverlay). Each takes effect through the calls below, which
# the tests call too.
#
# A dummy is a scripted Enemy (no senses, no thinking) whose ObserverDummy
# child drives what it does. A round or a sweep "from the cursor" comes from
# the phantom: a scripted mecha with no sprites and no collision, in no group
# and no list anything looks in for mechas, moved to the cursor to fire. NPCs
# read only where its round came from; nobody can see, lock or target it.
#
# The camera is the scene's ArenaCamera, moved by WASD or the arrow keys, by
# the cursor at a screen edge (not over the panel), faster with Shift held,
# zoomed by the wheel, and following the selected mecha (F). The panel and
# the camera keep running while the game is paused.
#
# Every pilot is in earshot here (hears_every_bark): the NPCs bark as they
# would beside the player, and what they say shows over them.
#
# There is no darkness light without a player (MechaShadowGen is the
# player's), so the arena has its own: one subtracting light over the whole
# view at the same energy (Darkness).

const OBSERVER_PANEL := preload("res://game/arena/observer/ObserverPanel.gd")
const OBSERVER_OVERLAY := preload("res://game/arena/observer/ObserverOverlay.gd")
const OBSERVER_DUMMY := preload("res://game/arena/observer/ObserverDummy.gd")

## The camera: its speed (screen px per second, so the same at any zoom) and
## how much faster it goes with Shift held, how near a screen edge (px) the
## cursor pans it, the zoom it starts at, its limits and how much one wheel
## notch changes it.
const CAMERA_SPEED := 1800.0
const CAMERA_FAST := 2.5
const EDGE_PAN_MARGIN := 24.0
const START_ZOOM := 0.2
const ZOOM_MIN := 0.05
const ZOOM_MAX := 1.0
const ZOOM_STEP := 1.15
## A click picks the mecha nearest it within this many screen px, or
## PICK_MIN_RADIUS world px if that is more.
const PICK_RADIUS := 40.0
const PICK_MIN_RADIUS := 250.0
## Game speeds the panel offers.
const SPEEDS := [0.25, 0.5, 1.0, 2.0]
## The loud noise event: how far it is heard (px) and its sound. Placeholders.
const NOISE_RANGE := 5000.0
const NOISE_SFX := "medium_shotA"
## A car alarm event sets off the nearest car that still can, within this
## distance (px).
const ALARM_PICK_RANGE := 3000.0
## The phantom aims this long (s) before it fires, so its gun points at the
## target. A gun spools up on the first shoot() after it stopped, so the
## phantom keeps pulling the trigger for up to ROUND_TRIGGER_FRAMES physics
## frames until the round is out.
const ROUND_AIM_TIME := 0.4
const ROUND_TRIGGER_FRAMES := 20
const ROUND_SLOT := "arm_weapon_right"
## The phantom's sweep width (degrees). Placeholder.
const EVENT_SWEEP_WIDTH := 90.0
## The internal parts the ward and drone events put out, as the dummy's.
const WARD_PART := "WD-2"
const DRONE_PART := "DR-4"

signal selection_changed

## The last mecha clicked, the last NPC clicked (what a dummy fires at and
## events aim at) and the last dummy clicked (what the dummy controls change).
var selected = null
var selected_npc = null
var selected_dummy = null
var following := false
## Whether the cursor at a screen edge pans the camera.
var edge_pan := true
## Dummy -> its ObserverDummy.
var dummies := {}
var speed := 1.0
var game_paused := false
## The panel's click mode: "" (select), "npc", "dummy", "patrol",
## "fire_point", or "event:<name>" (see trigger_event).
var place_mode := ""

var panel = null
var overlay = null
var _phantom: Mecha = null
var _phantom_shot := {}
var _base_time_scale := 1.0
var _saved_debug := {}
var _next_name := 0


func _ready() -> void:
	FrameSpikeDetector.mark("scene_load:ObserverArena")
	randomize()
	_base_time_scale = Engine.time_scale
	for key in ["enemy_state", "ai_overlay"]:
		_saved_debug[key] = Debug.debug_settings[key]
	ShaderEffects.reset_shader_effect("arena")
	ShaderEffects.play_transition(0.0, 5000.0, 1.0)
	_setup_sight_lighting()
	_setup_wrecks()
	_setup_entities()
	_setup_heatmap()
	_setup_darkness()
	_setup_camera()
	_make_phantom()
	if has_node("Intro"):
		$Intro.queue_free()
	local_pilots.go_live()
	overlay = OBSERVER_OVERLAY.new()
	overlay.arena = self
	add_child(overlay)
	panel = OBSERVER_PANEL.new()
	panel.arena = self
	add_child(panel)
	Debug.debug_settings["enemy_state"] = false
	set_ai_lines(false)


func _exit_tree() -> void:
	Engine.time_scale = _base_time_scale
	if is_inside_tree():
		get_tree().paused = false
	for key in _saved_debug:
		Debug.debug_settings[key] = _saved_debug[key]
	super._exit_tree()


# Only the fullscreen key: the debug keys CombatScene answers need a player.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		Global.toggle_fullscreen()


# The arena's own camera is always on; the debug free cam isn't used.
func activate_debug_cam() -> void:
	pass


func _physics_process(dt: float) -> void:
	_tick_phantom(dt)


# ---- Setup ----

func _setup_darkness() -> void:
	var dark := DirectionalLight2D.new()
	dark.name = "Darkness"
	dark.blend_mode = Light2D.BLEND_MODE_SUB
	dark.color = Color.WHITE
	dark.energy = Illumination.DARKNESS_ENERGY
	dark.range_layer_max = 2
	dark.range_item_cull_mask = MapSenses.SIGHT_LIGHT_MASK
	add_child(dark)


func _setup_camera() -> void:
	ArenaCam.enabled = true
	ArenaCam.zoom = Vector2(START_ZOOM, START_ZOOM)
	ArenaCam.position = Vector2.ZERO
	ArenaCam.make_current()
	ArenaCam.reset_smoothing()


func _make_phantom() -> void:
	_phantom = ENEMY.instantiate()
	_phantom.name = "Phantom"
	_phantom.visible = false
	add_child(_phantom)
	_phantom.remove_from_group("mecha")
	_phantom.collision_layer = 0
	_phantom.collision_mask = 0
	_phantom.setup(self, PlayerProgress.DEFAULT_MECHA.duplicate(), "Phantom")
	_phantom.set_scripted(true)
	_phantom.set_illuminator(false)
	_phantom.paused = true
	_connect_mecha_signals(_phantom)


## The phantom (see the top), for tests.
func get_phantom() -> Mecha:
	return _phantom


# Every mecha here, the phantom too, also has its sweeps drawn.
func _connect_mecha_signals(mecha) -> void:
	super._connect_mecha_signals(mecha)
	mecha.sweep_made.connect(_on_mecha_sweep)


func _on_mecha_sweep(mecha, direction: Vector2, width: float, counts: Dictionary, found: Array) -> void:
	if overlay != null:
		overlay.add_sweep(mecha, direction, width, counts, found)


# ---- Spawning ----

## Spawns `size` NPCs (1 to 3) of the generic design `design_index`
## (NPCManager.NPCS) and personality `type_name` ("hunter"...) at `at`. Two
## or more are a tagged squad. Each gets `skill` (0..1), or a skill drawn for
## its type when `skill` is negative (the panel's AUTO). Returns them.
func spawn_npc(type_name: String, design_index: int, size: int, at: Vector2, skill := -1.0) -> Array:
	var npcs := []
	var count := clampi(size, 1, 3)
	var squad: Squad = null
	if count > 1:
		squad = Squad.new()
		squad.setup(_free_squad_tag(), false)
	for i in count:
		var design: Dictionary = NPCManager.get_design_data(NPCManager.NPCS[posmod(design_index, NPCManager.NPCS.size())], type_name)
		if squad != null:
			design["squad_tag"] = squad.tag
		var offset := Vector2.from_angle(TAU * i / count) * (SQUAD_SPAWN_SPACING if i > 0 else 0.0)
		var enemy := add_enemy(design, "%s_%d" % [type_name.capitalize(), _next_name], at + offset)
		_next_name += 1
		if skill >= 0.0 and enemy.personality != null:
			enemy.personality.skill = clampf(skill, 0.0, 1.0)
		if squad != null:
			squad.add(enemy)
		npcs.append(enemy)
	if squad != null:
		squads.append(squad)
	return npcs


## A dummy at `at`: a scripted Enemy in the default build, its light off,
## driven by an ObserverDummy. Returns it.
func spawn_dummy(at: Vector2) -> Mecha:
	var dummy := add_enemy(PlayerProgress.DEFAULT_MECHA.duplicate(), "Dummy_%d" % _next_name, at)
	_next_name += 1
	dummy.set_scripted(true)
	dummy.set_illuminator(false)
	var control = OBSERVER_DUMMY.new()
	control.name = "ObserverDummy"
	dummy.add_child(control)
	control.setup(self, dummy)
	dummies[dummy] = control
	select(dummy)
	return dummy


func dummy_control(dummy):
	return dummies.get(dummy)


func is_dummy(mecha) -> bool:
	return dummies.has(mecha)


## The living mechas on the map that the panel works on (NPCs and dummies).
func observed_mechas() -> Array:
	return all_mechas.filter(func(m): return is_instance_valid(m) and not m.is_dead)


## The NPCs (not dummies) on the map.
func observed_npcs() -> Array:
	return observed_mechas().filter(func(m): return not is_dummy(m))


# ---- Selection ----

func select(mecha) -> void:
	if mecha != null and not is_instance_valid(mecha):
		mecha = null
	selected = mecha
	if mecha != null:
		if is_dummy(mecha):
			selected_dummy = mecha
		else:
			selected_npc = mecha
	else:
		following = false
	selection_changed.emit()


## The mecha nearest `world` within the pick radius, or null.
func pick(world: Vector2):
	var radius := maxf(PICK_RADIUS / ArenaCam.zoom.x, PICK_MIN_RADIUS)
	var best = null
	var best_d := radius
	for m in observed_mechas():
		var d: float = m.global_position.distance_to(world)
		if d <= best_d:
			best = m
			best_d = d
	return best


func toggle_follow() -> void:
	following = not following and is_instance_valid(selected)
	selection_changed.emit()


# ---- Removing ----

## Takes `mecha` off the map, with no wreck: it leaves Local and its squad.
func remove_mecha(mecha) -> void:
	if not is_instance_valid(mecha):
		return
	local_pilots.leave(mecha)
	for squad in squads.duplicate():
		if squad.is_in(mecha):
			squad.remove(mecha)
			if squad.members.is_empty():
				squads.erase(squad)
	all_mechas.erase(mecha)
	dummies.erase(mecha)
	for key in ["selected", "selected_npc", "selected_dummy"]:
		if is_same(get(key), mecha):
			set(key, null)
	if is_same(selected, null):
		following = false
	mecha.queue_free()
	selection_changed.emit()


## Every NPC and dummy off the map, and the wrecks and bodies they left.
func clear_all() -> void:
	for mecha in all_mechas.duplicate():
		remove_mecha(mecha)
	for holder in [Wrecks, Bodies]:
		if holder != null:
			for child in holder.get_children():
				child.queue_free()


# ---- Time ----

func set_paused(value: bool) -> void:
	game_paused = value
	get_tree().paused = value
	selection_changed.emit()


func set_speed(value: float) -> void:
	speed = value
	Engine.time_scale = _base_time_scale * value
	selection_changed.emit()


# ---- Overlays ----

## Each NPC's ai_overlay lines (Enemy._draw_ai_overlay): to its target, to
## where it last had it, and to where it is heading. Its think tag is the
## overlay's (ObserverOverlay.show_tags), so the NPC's own state label stays
## off here.
func set_ai_lines(on: bool) -> void:
	Debug.debug_settings["ai_overlay"] = on
	for m in observed_mechas():
		m.queue_redraw()


func ai_lines_on() -> bool:
	return Debug.debug_settings["ai_overlay"] == true


# ---- Speech ----

## Every pilot is heard here (Enemy.bark): there is no player to be in
## earshot of. Off with the overlay's barks.
func hears_every_bark() -> bool:
	return overlay != null and overlay.show_barks


# Speech shows in a box over the speaker (ObserverOverlay.show_speech) and
# goes to Local as a bark line.
func _on_mecha_spoke(mecha, text: String, seconds: float, _always_heard: bool) -> void:
	if not is_instance_valid(mecha) or overlay == null:
		return
	if overlay.show_barks:
		overlay.show_speech(mecha, text, seconds)
	local_pilots.post_bark(mecha, text)


# ---- Events ----

## Sets off `event_name` at `at`. Returns whether it happened.
##   car_alarm  the nearest car that can still sound its alarm
##   noise      a loud gunshot sound with no round
##   round      the phantom fires one round at the selected NPC
##   sweep      the phantom sweeps toward the selected NPC
##   ward       a ward put down here, the selected dummy's
##   drone      a drone put out here, heading away from the selected dummy
func trigger_event(event_name: String, at: Vector2) -> bool:
	match event_name:
		"car_alarm":
			return _car_alarm(at)
		"noise":
			_on_mecha_made_sound({"volume_type": "loud", "type": "shooting", "position": at,
					"max_distance": NOISE_RANGE, "source": null, "entities_only": false})
			AudioManager.play_sfx(NOISE_SFX, at)
			return true
		"round":
			return fire_round(at, selected_npc)
		"sweep":
			return sweep_from(at, selected_npc)
		"ward":
			return _put_dummy_device(WARD_PART, at)
		"drone":
			return _put_dummy_device(DRONE_PART, at)
	return false


func _car_alarm(at: Vector2) -> bool:
	var field := VehicleField.find(self)
	if field == null:
		return false
	var best := -1
	var best_d := ALARM_PICK_RANGE
	for i in field.vehicle_count():
		if not field.can_alarm(i):
			continue
		var d := field.vehicle_transform(i).origin.distance_to(at)
		if d < best_d:
			best = i
			best_d = d
	if best < 0:
		return false
	field.start_alarm(best)
	return true


## The phantom fires one round from `from` at `target` (after ROUND_AIM_TIME
## of aiming). Returns whether it will.
func fire_round(from: Vector2, target) -> bool:
	if not is_instance_valid(target) or not is_instance_valid(_phantom) or not _phantom_shot.is_empty():
		return false
	_phantom.global_position = from
	_phantom.global_rotation = Vector2.UP.angle_to(target.global_position - from)
	_phantom.scripted_aim = target.global_position
	_phantom.paused = false
	var node = _phantom.get_weapon_part(ROUND_SLOT)
	if node:
		node.reloading = false
		node.clip_ammo = node.data.clip_size if node.data else 1
	_phantom_shot = {"target": target, "time": ROUND_AIM_TIME, "frames": ROUND_TRIGGER_FRAMES}
	return true


func _tick_phantom(dt: float) -> void:
	if _phantom_shot.is_empty() or not is_instance_valid(_phantom):
		return
	var target = _phantom_shot.target
	if is_instance_valid(target):
		_phantom.scripted_aim = target.global_position
	_phantom_shot.time -= dt
	if _phantom_shot.time > 0.0:
		return
	var node = _phantom.get_weapon_part(ROUND_SLOT)
	var before = node.clip_ammo if node else 0
	if node:
		_phantom.shoot(ROUND_SLOT)
	_phantom_shot.frames -= 1
	if node == null or node.clip_ammo != before or _phantom_shot.frames <= 0:
		_phantom.stop_shooting(ROUND_SLOT)
		_phantom.scripted_aim = null
		_phantom.paused = true
		_phantom_shot = {}


## The phantom sweeps from `from` toward `target` (EVENT_SWEEP_WIDTH wide).
func sweep_from(from: Vector2, target) -> bool:
	if not is_instance_valid(target) or not is_instance_valid(_phantom):
		return false
	_phantom.global_position = from
	_phantom.sweep_cooldown = 0.0
	return bool(_phantom.sweep(target.global_position - from, EVENT_SWEEP_WIDTH).get("ok", false))


func _put_dummy_device(part_name: String, at: Vector2) -> bool:
	if not is_instance_valid(selected_dummy):
		return false
	var part = PartManager.get_part("internal", part_name)
	if part == null:
		return false
	var heading: Vector2 = selected_dummy.global_position.direction_to(at)
	if heading == Vector2.ZERO:
		heading = Vector2.UP
	selected_dummy._put_device(part, at, heading)
	return true


# ---- Input (forwarded by the panel, which runs while paused) ----

## A click on the map (one the panel didn't take): picks a mecha, or places
## what the panel's click mode says. A right click ends a click mode.
func handle_world_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(ZOOM_STEP)
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / ZOOM_STEP)
			return true
		if button.button_index == MOUSE_BUTTON_RIGHT:
			if place_mode != "":
				set_place_mode("")
				return true
			return false
		if button.button_index == MOUSE_BUTTON_LEFT:
			click_world(screen_to_world(button.position))
			return true
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.physical_keycode == KEY_F:
			toggle_follow()
			return true
		if key.physical_keycode == KEY_ESCAPE and place_mode != "":
			set_place_mode("")
			return true
	return false


func set_place_mode(mode: String) -> void:
	place_mode = mode
	selection_changed.emit()


## What a left click at `world` does, by the click mode.
func click_world(world: Vector2) -> void:
	match place_mode:
		"":
			select(pick(world))
		"npc":
			if panel != null:
				spawn_npc(panel.npc_type(), panel.npc_design, panel.squad_size, world, panel.spawn_skill)
		"dummy":
			spawn_dummy(world)
			set_place_mode("")
		"patrol":
			var control = dummy_control(selected_dummy)
			if control != null:
				control.add_patrol_point(world)
		"fire_point":
			var control = dummy_control(selected_dummy)
			if control != null:
				control.fire_point = world
			set_place_mode("")
		_:
			if place_mode.begins_with("event:"):
				trigger_event(place_mode.trim_prefix("event:"), world)


func screen_to_world(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


# ---- Camera (run by the panel every frame, paused or not) ----

func zoom_by(factor: float) -> void:
	var z := clampf(ArenaCam.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	ArenaCam.zoom = Vector2(z, z)


## `real_dt`: real seconds since the last frame, whatever the game speed.
func update_camera(real_dt: float, mouse_over_panel: bool) -> void:
	if following and is_instance_valid(selected):
		ArenaCam.position = selected.global_position
		return
	following = false
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	if edge_pan and not mouse_over_panel and DisplayServer.window_is_focused():
		var mouse := get_viewport().get_mouse_position()
		var size := get_viewport().get_visible_rect().size
		if mouse.x <= EDGE_PAN_MARGIN:
			move.x -= 1.0
		elif mouse.x >= size.x - EDGE_PAN_MARGIN:
			move.x += 1.0
		if mouse.y <= EDGE_PAN_MARGIN:
			move.y -= 1.0
		elif mouse.y >= size.y - EDGE_PAN_MARGIN:
			move.y += 1.0
	if move != Vector2.ZERO:
		var speed := CAMERA_SPEED * (CAMERA_FAST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		ArenaCam.position += move.normalized() * speed / ArenaCam.zoom.x * real_dt
