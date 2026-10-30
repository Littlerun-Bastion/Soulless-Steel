extends Node2D

# Art bench for the sand Entity bodies (SandBody and the species bodies).
# Not a game test: it has no Entity, no arena and no damage. A plain Node2D
# "puppet" stands in for the Entity, with the body as its Body child, and
# this script plays the Entity's part: it moves the puppet, calls
# update_motion() every frame, and pokes the body's moves (whip, bite,
# charge, stage, harpoon, leap) the way the real Entity will.
#
# The puppet walks to the mouse cursor, or on autopilot a figure-eight. The
# Coyote Spitter circles its prey and the Fisher keeps its distance; on
# autopilot both work round a fixed prey marker.
#
# Keys: 3 Coyote, 4 Coyote Spitter, 5 Fisher
#       1 calm (Fisher: curl up)   2 hunt (Fisher: legs out)
#       N loud noise (Fisher: wake and search)
#       F attack the cursor (or the prey on autopilot)
#       J leap away from the cursor (Fisher)
#       H hit flash   K kill   R respawn   A autopilot on/off
# Without autopilot the cursor is the prey: rush it at a Fisher, or pull it
# away fast, and the Fisher leaps. Latched on, drag it more than
# TETHER_BREAK away and the tether snaps.

const SPECIES := {
	"Coyote": {"body": preload("res://game/entities/coyote/CoyoteBody.gd"),
			"idle_speed": 160.0, "hunt_speed": 650.0, "accel": 2400.0, "turn": 7.0},
	"Coyote Spitter": {"body": preload("res://game/entities/coyote/CoyoteSpitterBody.gd"),
			"idle_speed": 160.0, "hunt_speed": 480.0, "accel": 2000.0, "turn": 6.0, "orbit": 360.0},
	"Fisher": {"body": preload("res://game/entities/fisher/FisherBody.gd"),
			"idle_speed": 90.0, "hunt_speed": 170.0, "accel": 700.0, "turn": 3.5, "kite": 420.0},
}
const KEYS := {KEY_3: "Coyote", KEY_4: "Coyote Spitter", KEY_5: "Fisher"}
const HELP := "3 Coyote  4 Spitter  5 Fisher   1 calm  2 hunt  N noise  F attack  J leap  H hit  K kill  R respawn  A autopilot"
const GROUND := Color(0.36, 0.36, 0.36)
const GRID := Color(0.40, 0.40, 0.40)

# Fisher puppet numbers: the design values the Fisher Entity will use.
const HARPOON_RANGE := 650.0
const HARPOON_SPEED := 2600.0
const REEL_SPEED := 1600.0
const LATCH_TIME := 6.0
const DRAIN_PERIOD := 2.0
## Half a screen at the game's 0.5 camera zoom.
const TETHER_BREAK := 1080.0
const TETHER_SPEED := 170.0
const TETHER_ACCEL := 700.0
const SEARCH_TIME := 6.0
const LEAP_DISTANCE := 320.0
const CROUCH_TIME := 0.16
const AIR_TIME := 0.5
const LAND_TIME := 0.25
const LEAP_COOLDOWN := 2.5
const THREAT_SPEED := 260.0
const EVADE_RANGE := 520.0
const PURSUE_RANGE := 400.0
const GLOB_SPEED := 900.0

@export var species := "Coyote"
@export var autopilot := false

## The stand-in Entity, and its body.
var puppet: Node2D
var body: SandBody
var velocity := Vector2.ZERO
var hunting := false
## On autopilot, the prey a species that works round it is after. A capture
## script can move it (prey_velocity) to rush the puppet or run from it.
var prey := Vector2.ZERO
var prey_velocity := Vector2.ZERO
## Fisher counters, shown on screen.
var drain_ticks := 0
var latches := 0

var _auto_t := 0.0
var _label: Label
# Fisher puppet state
var _search_t := 0.0
var _harpoon_dir := Vector2.RIGHT
var _harpoon_len := 0.0
var _attach := Vector2.ZERO   # latched: the catch point, relative to the prey
var _tether_len := 0.0
var _latch_t := 0.0
var _leap := FisherBody.LeapPhase.NONE
var _leap_t := 0.0
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _leap_cool := 0.0
var _focus_dist := -1.0
var _focus_rate := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(GROUND)
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(24.0, 20.0)
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	layer.add_child(_label)
	add_child(layer)
	spawn()


func _cfg(key: String) -> float:
	return SPECIES[species].get(key, 0.0)


func spawn() -> void:
	if puppet:
		puppet.queue_free()
	puppet = Node2D.new()
	puppet.name = "Puppet"
	body = SPECIES[species]["body"].new()
	body.name = "Body"
	puppet.add_child(body)
	velocity = Vector2.ZERO
	hunting = false
	drain_ticks = 0
	latches = 0
	_leap = FisherBody.LeapPhase.NONE
	_leap_cool = 0.0
	_focus_dist = -1.0
	# On autopilot, a species that works round the prey starts out at a
	# distance from it, facing it, not on top of it.
	if autopilot and _cfg("orbit") > 0.0:
		puppet.position = Vector2(_cfg("orbit"), 0.0)
	elif autopilot and _cfg("kite") > 0.0:
		puppet.position = Vector2(_cfg("kite") + 300.0, 0.0)
		puppet.rotation = PI
	add_child(puppet)
	if body is CoyoteSpitterBody:
		(body as CoyoteSpitterBody).fired.connect(_on_fired)
	elif body is CoyoteBody:
		# The Coyote Entity chains the bite off the whip the same way.
		(body as CoyoteBody).whip_struck.connect((body as CoyoteBody).bite)


## Where the puppet is heading: the cursor, or on autopilot a figure-eight
## (or, for a species that works round its prey, the prey marker).
func target() -> Vector2:
	if not autopilot:
		return get_global_mouse_position()
	if _cfg("orbit") > 0.0 or _cfg("kite") > 0.0:
		return prey
	return Vector2(sin(_auto_t) * 600.0, sin(_auto_t * 2.0) * 280.0)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if KEYS.has(key.keycode):
		species = KEYS[key.keycode]
		spawn()
	elif key.keycode == KEY_1:
		calm()
	elif key.keycode == KEY_2:
		hunt()
	elif key.keycode == KEY_N:
		noise()
	elif key.keycode == KEY_F:
		attack()
	elif key.keycode == KEY_J:
		leap(puppet.global_position - target())
	elif key.keycode == KEY_H:
		hit()
	elif key.keycode == KEY_K:
		kill()
	elif key.keycode == KEY_R:
		spawn()
	elif key.keycode == KEY_A:
		autopilot = not autopilot


# ---- Commands (keys, or a capture script) ----

func calm() -> void:
	if body.dead:
		return
	hunting = false
	if body is FisherBody:
		(body as FisherBody).stage = FisherBody.Stage.DORMANT
		_reel_in()


func hunt() -> void:
	if body.dead:
		return
	hunting = true
	if body is FisherBody:
		(body as FisherBody).stage = FisherBody.Stage.ACTIVE


func noise() -> void:
	if body is FisherBody and not body.dead:
		var fisher := body as FisherBody
		if fisher.stage == FisherBody.Stage.DORMANT:
			fisher.stage = FisherBody.Stage.ALERT
		_search_t = 0.0


func attack() -> void:
	if body.dead:
		return
	if body is CoyoteSpitterBody:
		(body as CoyoteSpitterBody).charge(target())
	elif body is CoyoteBody:
		(body as CoyoteBody).whip()
	elif body is FisherBody:
		_fire_harpoon()


func hit() -> void:
	if not body.dead:
		body.flash = 1.0


func kill() -> void:
	if not body.dead:
		hunting = false
		velocity = Vector2.ZERO
		body.die()


# ---- Every frame ----

func _process(delta: float) -> void:
	queue_redraw()
	prey += prey_velocity * delta
	body.flash = move_toward(body.flash, 0.0, delta * 8.0)
	_update_label()
	if body.dead:
		body.update_motion(Vector2.ZERO, delta)
		return
	body.alarm = hunting
	_auto_t += delta * (0.8 if hunting else 0.35)
	if body is FisherBody:
		_fisher_process(delta)
	if not _moves_itself():
		_steer(delta)
	body.update_motion(velocity, delta)


func _update_label() -> void:
	var text := "%s   |   %s" % [species, HELP]
	if body is FisherBody:
		var fisher := body as FisherBody
		text += "\nstage: %s   harpoon: %s   latches: %d   drain hits: %d" % [
				["dormant", "alert", "active"][fisher.stage],
				["-", "flying", "latched", "reeling"][fisher.harpoon_mode], latches, drain_ticks]
	_label.text = text


# Walk towards the target, circle it, or hold a distance from it.
func _steer(delta: float) -> void:
	var speed := _cfg("hunt_speed") if hunting else _cfg("idle_speed")
	var to_target := target() - puppet.global_position
	var orbit := _cfg("orbit")
	var kite := _cfg("kite")
	var desired := Vector2.ZERO
	if orbit > 0.0 and hunting:
		# Run round the target, steering in or out to hold the radius.
		var radial := to_target.normalized() if to_target.length() > 1.0 else Vector2.RIGHT
		var error := clampf((to_target.length() - orbit) / orbit * 2.0, -1.0, 1.0)
		desired = (radial.orthogonal() + radial * error).normalized() * speed
	elif kite > 0.0 and hunting:
		# Hold its distance: close in if too far, back off if too near.
		var d := to_target.length()
		if d > kite * 1.2:
			desired = to_target.normalized() * speed
		elif d < kite * 0.8:
			desired = -to_target.normalized() * speed
	elif to_target.length() > 80.0:
		desired = to_target.normalized() * speed
	if not _can_walk():
		desired = Vector2.ZERO
	velocity = velocity.move_toward(desired, _cfg("accel") * delta)
	puppet.global_position += velocity * delta
	# A kiter faces its target and walks backwards or sideways as needed.
	var facing := to_target.angle() if kite > 0.0 and hunting else velocity.angle()
	if (kite > 0.0 and hunting and _can_walk()) or velocity.length() > 10.0:
		puppet.rotation = lerp_angle(puppet.rotation, facing, clampf(_cfg("turn") * delta, 0.0, 1.0))


func _can_walk() -> bool:
	if body is FisherBody:
		var fisher := body as FisherBody
		return fisher.stage == FisherBody.Stage.ACTIVE and fisher.legs_out() > 0.95 \
				and fisher.harpoon_mode == FisherBody.HarpoonMode.NONE
	return true


# Leaping, or holding a tether, the Fisher moves itself.
func _moves_itself() -> bool:
	if body is FisherBody:
		return _leap != FisherBody.LeapPhase.NONE \
				or (body as FisherBody).harpoon_mode == FisherBody.HarpoonMode.LATCHED
	return false


# ---- Coyote Spitter: the placeholder glob ----

func _on_fired(muzzle: Vector2, direction: Vector2) -> void:
	var glob := Glob.new()
	glob.velocity = direction * GLOB_SPEED
	glob.color = body.grain_color
	add_child(glob)
	glob.global_position = muzzle


# ---- Fisher puppet ----

func _fisher_process(delta: float) -> void:
	var fisher := body as FisherBody
	if fisher.stage == FisherBody.Stage.ALERT:
		_search_t += delta
		if _search_t > SEARCH_TIME:
			calm()
	fisher.focus_point = target()
	fisher.has_focus = hunting
	_watch_focus(delta)
	_update_leap(delta)
	_update_harpoon(delta)


func _fire_harpoon() -> void:
	var fisher := body as FisherBody
	if fisher.stage != FisherBody.Stage.ACTIVE or fisher.harpoon_mode != FisherBody.HarpoonMode.NONE \
			or fisher.legs_out() < 0.95 or _leap != FisherBody.LeapPhase.NONE:
		return
	var aim := target() - fisher.harpoon_root()
	_harpoon_dir = aim.normalized() if aim.length() > 1.0 else Vector2.from_angle(puppet.global_rotation)
	_harpoon_len = 0.0
	fisher.harpoon_mode = FisherBody.HarpoonMode.FLYING
	fisher.recoil(_harpoon_dir)


func _reel_in() -> void:
	var fisher := body as FisherBody
	if fisher.harpoon_mode != FisherBody.HarpoonMode.NONE:
		fisher.harpoon_mode = FisherBody.HarpoonMode.REELING


# The harpoon flies out; on reaching the prey it latches on (the bench
# treats every hit as penetrating). Latched, the Fisher holds the tether
# length, a drain hit lands every DRAIN_PERIOD, and after LATCH_TIME, or
# if the prey gets TETHER_BREAK away, it lets go and reels in.
func _update_harpoon(delta: float) -> void:
	var fisher := body as FisherBody
	var root := fisher.harpoon_root()
	match fisher.harpoon_mode:
		FisherBody.HarpoonMode.FLYING:
			var aim := target() - root
			var reach := minf(aim.length(), HARPOON_RANGE)
			if aim.length() > 1.0:
				_harpoon_dir = aim.normalized()
			_harpoon_len = minf(_harpoon_len + HARPOON_SPEED * delta, reach)
			if _harpoon_len >= reach - 0.5:
				if aim.length() <= HARPOON_RANGE:
					fisher.harpoon_mode = FisherBody.HarpoonMode.LATCHED
					_attach = root + _harpoon_dir * _harpoon_len - target()
					_tether_len = puppet.global_position.distance_to(target() + _attach)
					_latch_t = 0.0
					fisher.drain_phase = 0.0
					latches += 1
				else:
					_reel_in()
		FisherBody.HarpoonMode.LATCHED:
			_hold_tether(delta)
			root = fisher.harpoon_root()
			var aim := target() + _attach - root
			_harpoon_len = aim.length()
			if _harpoon_len > 1.0:
				_harpoon_dir = aim / _harpoon_len
			_latch_t += delta
			var before := fisher.drain_phase
			fisher.drain_phase += delta / DRAIN_PERIOD
			if floori(fisher.drain_phase) > floori(before):
				drain_ticks += 1
			if _latch_t >= LATCH_TIME or _harpoon_len > TETHER_BREAK:
				_reel_in()
		FisherBody.HarpoonMode.REELING:
			_harpoon_len = maxf(_harpoon_len - REEL_SPEED * delta, 0.0)
			if _harpoon_len <= 0.0:
				fisher.harpoon_mode = FisherBody.HarpoonMode.NONE
	fisher.harpoon_tip = fisher.harpoon_root() + _harpoon_dir * _harpoon_len


# Latched: walk in or back off to hold the tether length, facing the catch.
func _hold_tether(delta: float) -> void:
	if _leap != FisherBody.LeapPhase.NONE:
		return
	var to := target() + _attach - puppet.global_position
	var d := to.length()
	if d < 1.0:
		return
	var err := d - _tether_len
	var want := Vector2.ZERO
	if absf(err) > 8.0:
		want = to / d * clampf(err * 4.0, -TETHER_SPEED, TETHER_SPEED)
	velocity = velocity.move_toward(want, TETHER_ACCEL * delta)
	puppet.global_position += velocity * delta
	puppet.rotation = lerp_angle(puppet.rotation, to.angle(), clampf(4.0 * delta, 0.0, 1.0))


## Leap in a direction (world), the default distance or the one given.
func leap(direction: Vector2, distance := -1.0) -> void:
	if not (body is FisherBody):
		return
	var fisher := body as FisherBody
	if fisher.stage != FisherBody.Stage.ACTIVE or _leap != FisherBody.LeapPhase.NONE \
			or fisher.legs_out() < 0.95 or direction.length() < 0.01:
		return
	_leap = FisherBody.LeapPhase.CROUCH
	_leap_t = 0.0
	_leap_from = puppet.global_position
	_leap_to = puppet.global_position + direction.normalized() * (LEAP_DISTANCE if distance < 0.0 else distance)
	_leap_cool = LEAP_COOLDOWN
	velocity = Vector2.ZERO


# Watches how fast its prey closes in or pulls away. Rushed, it springs
# away. Fled from, it lunges after: to get back into harpoon range, or,
# latched on, to keep the tether from snapping.
func _watch_focus(delta: float) -> void:
	var fisher := body as FisherBody
	_leap_cool = maxf(_leap_cool - delta, 0.0)
	if not hunting or fisher.stage != FisherBody.Stage.ACTIVE:
		_focus_dist = -1.0
		_focus_rate = 0.0
		return
	var d := puppet.global_position.distance_to(target())
	# Its own leaps don't count as the prey moving.
	if _focus_dist >= 0.0 and _leap == FisherBody.LeapPhase.NONE:
		var rate := (_focus_dist - d) / maxf(delta, 0.0001)
		_focus_rate = lerpf(_focus_rate, rate, clampf(8.0 * delta, 0.0, 1.0))
	_focus_dist = d
	if _leap != FisherBody.LeapPhase.NONE or _leap_cool > 0.0 or fisher.legs_out() < 0.95:
		return
	var away := (puppet.global_position - target()).normalized()
	var mode := fisher.harpoon_mode
	if mode == FisherBody.HarpoonMode.LATCHED:
		if d > lerpf(_tether_len, TETHER_BREAK, 0.5):
			leap(-away, clampf(d - _tether_len, 120.0, LEAP_DISTANCE))
	elif _focus_rate > THREAT_SPEED and d < EVADE_RANGE:
		leap(away.rotated(randf_range(-0.4, 0.4)))
	elif _focus_rate < -THREAT_SPEED and d > PURSUE_RANGE and mode == FisherBody.HarpoonMode.NONE:
		leap(-away, clampf(d - HARPOON_RANGE * 0.7, 120.0, LEAP_DISTANCE))


# Moves the puppet along the leap and hands the body its pose.
func _update_leap(delta: float) -> void:
	var fisher := body as FisherBody
	if _leap == FisherBody.LeapPhase.NONE:
		return
	_leap_t += delta
	var dir := (_leap_to - _leap_from).normalized()
	var length: float = {FisherBody.LeapPhase.CROUCH: CROUCH_TIME, FisherBody.LeapPhase.AIR: AIR_TIME,
			FisherBody.LeapPhase.LAND: LAND_TIME}[_leap]
	var u := minf(_leap_t / length, 1.0)
	if _leap == FisherBody.LeapPhase.AIR:
		puppet.global_position = _leap_from.lerp(_leap_to, u)
	fisher.set_leap(_leap, u, dir)
	if u >= 1.0:
		_leap_t = 0.0
		if _leap == FisherBody.LeapPhase.CROUCH:
			_leap = FisherBody.LeapPhase.AIR
		elif _leap == FisherBody.LeapPhase.AIR:
			_leap = FisherBody.LeapPhase.LAND
		else:
			_leap = FisherBody.LeapPhase.NONE
		fisher.set_leap(_leap, 0.0, dir)


func _draw() -> void:
	for i in range(-20, 21):
		draw_line(Vector2(i * 100.0, -2000.0), Vector2(i * 100.0, 2000.0), GRID, 1.0)
		draw_line(Vector2(-2000.0, i * 100.0), Vector2(2000.0, i * 100.0), GRID, 1.0)
	var ring := maxf(_cfg("orbit"), _cfg("kite"))
	if autopilot and ring > 0.0:
		# Prey marker, and the distance the species works at.
		draw_circle(prey, 14.0, Color(0.8, 0.8, 0.8, 0.6))
		draw_arc(prey, ring, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 2.0)


## Placeholder projectile: a tumbling clump of grains with a short trail.
## The Coyote Spitter Entity will fire an AcidGlob instead.
class Glob extends Node2D:
	const LIFETIME := 1.2
	var velocity := Vector2.ZERO
	var color := Color(0.05, 0.05, 0.05)
	var life := 0.0
	var _grains: Array[Vector3] = []  # angle, radius, size

	func _ready() -> void:
		z_index = 1
		for k in 18:
			_grains.append(Vector3(randf() * TAU, randf_range(1.0, 8.0), randf_range(2.0, 4.0)))

	func _process(delta: float) -> void:
		global_position += velocity * delta
		life += delta
		if life >= LIFETIME:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var fade := 1.0 - smoothstep(LIFETIME * 0.7, LIFETIME, life)
		var back := -velocity.normalized()
		for g in _grains:
			var p := Vector2.from_angle(g.x + life * 9.0) * g.y
			draw_rect(Rect2(p - Vector2.ONE * g.z * 0.5, Vector2.ONE * g.z), Color(color, fade))
		for k in 8:
			var p := back * (10.0 + k * 7.0) + Vector2.from_angle(k * 2.3 + life * 5.0) * 3.0
			draw_rect(Rect2(p, Vector2.ONE * 2.0), Color(color, fade * (1.0 - k / 8.0)))
