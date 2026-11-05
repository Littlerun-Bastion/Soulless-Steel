extends Entity
class_name Fisher

# Fisher: a lone ambush hunter that looks like ground clutter. Dormant, it's
# just a shell on the ground: it senses nothing but noise. A loud noise wakes
# it (ALERT): its antennae come out and it searches for heat. If it finds a
# hot mecha, or is hurt, it stands up and hunts (HUNT) that one mecha.
#
# Hunting, it keeps its distance (keep_range), facing its prey, and fires a
# long harpoon tendril. A harpoon that gets through the armour buries itself
# and latches on for latch_time: the Fisher holds the tether's length as the
# prey moves, and every drain_period the harpoon draws on it, a hit that
# always gets through to a random part (EntityAttack.hit_through) and sucks
# out heat. Every hit that gets through heals it 1 hp. The tether snaps if
# the prey gets tether_break away; before that, the Fisher leaps after it to
# keep it.
#
# It leaps: back and to the side when prey rushes it, round the prey's flank
# when the prey turns its front on it (the side the prey is turned away
# from, so its leaps outrun the prey's turning and it's hard to keep in
# front), and after prey that runs off, to get back into harpoon range. It
# has leap_charges leaps in a row; once they're spent it waits leap_cooldown
# before it leaps again (a spent leap comes back after leap_cooldown without
# leaping, too). So it can be caught out: make it spend its leaps, then rush
# into close range.
#
# It remembers its prey (Entity's Memory: memory_time, close_sense): prey it
# no longer perceives (cooled off, dark, out of sight) it stalks over to
# where it last had it, without harpoon or leaps, until it has it again or
# memory_time runs out. Its harpoon in the prey, it always perceives it.
# A mecha's light within a screen finds it prey while it is awake; with
# nothing to hunt it searches a while, then curls back up where it is.
# Dormant, it senses nothing but noise, light or not; a shot wakes it, and
# it goes for the shooter. The mecha its harpoon is in always sees it
# (is_tethered_to).
#
# Its look is a FisherBody (the Body child). The Fisher moves itself, leaps
# included, through velocity; it hands the body its stage, the harpoon's
# state and tip, the recoil and the leap pose.

enum State { DORMANT, ALERT, HUNT }
enum Harpoon { NONE, FLYING, LATCHED, REELING }

@export_group("Harpoon")
@export var harpoon_range := 650.0
@export var harpoon_speed := 2600.0
@export var reel_speed := 1600.0
## Component damage pips and armour pen of the harpoon's first strike.
@export var harpoon_damage := 1
@export var harpoon_pen := 2
@export var harpoon_cooldown := Vector2(1.5, 2.5)
## Latched: how long the harpoon stays in, how often it draws on the prey,
## and what each draw does.
@export var latch_time := 6.0
@export var drain_period := 2.0
@export var drain_damage := 1
@export var drain_heat := 1500.0
## The tether snaps if the prey gets this far away (half a screen at the
## game's 0.5 camera zoom).
@export var tether_break := 1080.0
@export var tether_speed := 200.0
@export_group("Hunting")
## The distance it keeps from its prey while not latched.
@export var keep_range := 480.0
## Awake with nothing found, it curls back up after this long.
@export var search_time := 6.0
@export_group("Leap")
@export var leap_distance := 450.0
@export var crouch_time := 0.1
@export var air_time := 0.25
@export var land_time := 0.15
## Leaps it can make in a row; spent, it waits leap_cooldown for them back.
@export var leap_charges := 3
@export var leap_cooldown := 2.5
## Prey closing in or pulling away faster than this (px/s) makes it leap.
@export var threat_speed := 260.0
## Rushed inside this distance, it leaps away.
@export var evade_range := 600.0
## Prey running off beyond this distance makes it leap after it.
@export var pursue_range := 460.0
## Rushed, how much of the leap goes away from the prey (the rest round it).
@export_range(0.0, 1.0) var evade_back := 0.55
## The prey's front is on it when the Fisher is within this many degrees of
## where the prey faces; kept there face_react s, it leaps round it.
@export var facing_cone := 25.0
@export var face_react := 0.3
## A leap round the prey turns it at most this far round (radians).
@export var max_flank_turn := 1.3

var state: State = State.DORMANT
var harpoon: Harpoon = Harpoon.NONE
var latches := 0      # harpoons that latched on (tests, tuning)
var drain_hits := 0   # draws on latched prey
var leaps := 0

var _state_time := 0.0
var _harpoon_cool := 0.0
var _h_dir := Vector2.RIGHT
var _h_len := 0.0
var _latched_to: Node2D = null
var _attach := Vector2.ZERO   # latched: the catch point, in the prey's own space
var _tether_len := 0.0
var _latch_t := 0.0
var _leap := FisherBody.LeapPhase.NONE
var _leap_t := 0.0
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _leap_cool := 0.0
var _leaps_left := 3
var _faced_time := 0.0
var _focus_dist := -1.0
var _focus_rate := 0.0

@onready var fisher_body: FisherBody = $Body as FisherBody


func _ready() -> void:
	super._ready()
	_leaps_left = leap_charges


func behave(dt: float) -> void:
	_state_time += dt
	_harpoon_cool = maxf(_harpoon_cool - dt, 0.0)
	if _leap_cool > 0.0:
		_leap_cool = maxf(_leap_cool - dt, 0.0)
		if _leap_cool <= 0.0:
			_leaps_left = leap_charges
	match state:
		State.DORMANT: _dormant(dt)
		State.ALERT: _alert()
		State.HUNT: _hunt(dt)
	_update_harpoon(dt)
	_update_leap(dt)
	fisher_body.alarm = state == State.HUNT
	var has_prey := is_valid_prey(target)
	fisher_body.focus_point = target.global_position if has_prey else global_position
	fisher_body.has_focus = has_prey


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	fisher_body.stage = [FisherBody.Stage.DORMANT, FisherBody.Stage.ALERT, FisherBody.Stage.ACTIVE][new_state]


# ---- Hooks ----

# Dormant, it senses nothing but noise (and being hurt).
func wants_prey() -> bool:
	return state != State.DORMANT


func on_target_acquired(_prey: Node2D) -> void:
	_set_state(State.HUNT)


func on_target_lost() -> void:
	_reel_in()
	_set_state(State.ALERT)


func on_heard(point: Vector2) -> void:
	if state == State.HUNT:
		return
	face_point = point
	_set_state(State.ALERT)


func on_hurt(amount: float) -> void:
	# Even dormant, a shot wakes it, and it goes for the shooter, knowing
	# where it fired from (Entity.on_hurt).
	if target == null and is_valid_prey(last_attacker):
		acquire_target(last_attacker)
	super.on_hurt(amount)


# With its harpoon in its prey, it has it on the end of the tether.
func perceives(mecha: Node2D) -> bool:
	return is_tethered_to(mecha) or super.perceives(mecha)


# ---- States ----

func _dormant(dt: float) -> void:
	stop()
	face_point = null
	heal(regen_rate * dt)


func _alert() -> void:
	stop()
	if _state_time > search_time:
		face_point = null
		_set_state(State.DORMANT)


func _hunt(dt: float) -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	# Prey it has lost (Entity's Memory): it stalks over to where it last had
	# it, no harpoon and no leaps, until it has it again or forgets it.
	if not target_perceived and harpoon != Harpoon.LATCHED:
		if _leap != FisherBody.LeapPhase.NONE:
			return
		face_point = last_known
		if fisher_body.legs_out() < 0.95 or harpoon != Harpoon.NONE:
			stop()
		else:
			move_to(last_known, walk_speed, keep_range * 0.5)
		return
	_watch_prey(dt)
	if _leap != FisherBody.LeapPhase.NONE:
		return
	face_point = target.global_position
	# It can't move until its legs are out, and stands still to fire.
	if fisher_body.legs_out() < 0.95 or harpoon == Harpoon.FLYING or harpoon == Harpoon.REELING:
		stop()
		return
	if harpoon == Harpoon.LATCHED:
		_hold_tether()
		return
	var d := distance_to(target)
	if d > keep_range * 1.2:
		move_to(target.global_position, walk_speed, keep_range)
	elif d < keep_range * 0.8:
		move_in(global_position - target.global_position, run_speed)
	else:
		stop()
	if _harpoon_cool <= 0.0 and d <= harpoon_range and can_see(target):
		_fire()


# ---- Harpoon ----

func _fire() -> void:
	var aim := target.global_position - fisher_body.harpoon_root()
	_h_dir = aim.normalized() if aim.length() > 1.0 else forward()
	_h_len = 0.0
	harpoon = Harpoon.FLYING
	stop()
	velocity = Vector2.ZERO
	fisher_body.recoil(_h_dir)
	AudioManager.play_sfx("pressure_gun_light", global_position)


func _reel_in() -> void:
	if harpoon == Harpoon.FLYING or harpoon == Harpoon.LATCHED:
		harpoon = Harpoon.REELING
	_latched_to = null


func _update_harpoon(dt: float) -> void:
	var root := fisher_body.harpoon_root()
	match harpoon:
		Harpoon.FLYING:
			_fly(root, dt)
		Harpoon.LATCHED:
			_draw_on_prey(root, dt)
		Harpoon.REELING:
			_h_len = maxf(_h_len - reel_speed * dt, 0.0)
			if _h_len <= 0.0:
				harpoon = Harpoon.NONE
				_harpoon_cool = randf_range(harpoon_cooldown.x, harpoon_cooldown.y) * attack_gap_mult()
	fisher_body.harpoon_mode = [FisherBody.HarpoonMode.NONE, FisherBody.HarpoonMode.FLYING,
			FisherBody.HarpoonMode.LATCHED, FisherBody.HarpoonMode.REELING][harpoon]
	fisher_body.harpoon_tip = _tip(root)
	fisher_body.drain_phase = _latch_t / drain_period


func _tip(root: Vector2) -> Vector2:
	if harpoon == Harpoon.LATCHED and is_instance_valid(_latched_to):
		return _latched_to.to_global(_attach)
	return root + _h_dir * _h_len


# Out towards the prey's hull; it strikes when it gets there, and is
# stopped by a wall or by running out of length.
func _fly(root: Vector2, dt: float) -> void:
	if not is_valid_prey(target):
		_reel_in()
		return
	var aim := target.global_position - root
	if aim.length() > 1.0:
		_h_dir = aim.normalized()
	var reach := maxf(aim.length() - EntityAttack.HULL_REACH * 0.6, 0.0)
	_h_len = minf(_h_len + harpoon_speed * dt, minf(reach, harpoon_range))
	if _blocked(root, root + _h_dir * _h_len):
		_reel_in()
	elif _h_len >= reach:
		_strike(root)
	elif _h_len >= harpoon_range:
		_reel_in()  # out of range


func _blocked(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, MapSenses.SIGHT_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider != target and not hit.collider is Entity \
			and not (hit.collider is Node and (hit.collider as Node).is_in_group("mecha"))


# The harpoon reaches its prey: through the armour, it buries itself.
func _strike(root: Vector2) -> void:
	if not EntityAttack.hit_mecha(self, target, harpoon_damage, harpoon_pen):
		_reel_in()
		return
	harpoon = Harpoon.LATCHED
	latches += 1
	_latched_to = target
	var tip := root + _h_dir * _h_len
	_attach = target.to_local(tip)
	_tether_len = global_position.distance_to(tip)
	_latch_t = 0.0
	heal(1.0)


# Latched: every drain_period it draws on the prey. The harpoon comes out
# after latch_time, or when the tether snaps.
func _draw_on_prey(root: Vector2, dt: float) -> void:
	if not is_valid_prey(_latched_to):
		_reel_in()
		return
	var before := _latch_t
	_latch_t += dt
	if floori(_latch_t / drain_period) > floori(before / drain_period):
		drain_hits += 1
		EntityAttack.hit_through(self, _latched_to, drain_damage)
		if _latched_to.has_method("drain_heat"):
			_latched_to.drain_heat(drain_heat)
		heal(1.0)
	var tip := _tip(root)
	_h_len = root.distance_to(tip)
	if _h_len > 1.0:
		_h_dir = (tip - root) / _h_len
	if _latch_t >= latch_time or _h_len > tether_break:
		_reel_in()


# Walk in or back off to hold the tether's length, facing the catch.
func _hold_tether() -> void:
	var tip := _tip(fisher_body.harpoon_root())
	face_point = tip
	var to := tip - global_position
	var err := to.length() - _tether_len
	if absf(err) < 8.0:
		stop()
	else:
		desired_velocity = to.normalized() * clampf(err * 4.0, -tether_speed, tether_speed)


# ---- Leaping ----

# Watches how fast its prey closes in or pulls away, and whether its prey's
# front is on it. Rushed, it springs back and round the prey's flank. Faced,
# it leaps round the prey, the way the prey is turned from it. Run from, it
# lunges after it: back into harpoon range or, latched on, to keep the
# tether from snapping.
func _watch_prey(dt: float) -> void:
	var d := distance_to(target)
	# Its own leaps don't count as the prey moving.
	if _focus_dist >= 0.0 and _leap == FisherBody.LeapPhase.NONE:
		var rate := (_focus_dist - d) / maxf(dt, 0.0001)
		_focus_rate = lerpf(_focus_rate, rate, clampf(8.0 * dt, 0.0, 1.0))
	_focus_dist = d
	_faced_time = _faced_time + dt if _faced() else 0.0
	if _leap != FisherBody.LeapPhase.NONE or _leaps_left <= 0 or fisher_body.legs_out() < 0.95:
		return
	var away := (global_position - target.global_position).normalized()
	if harpoon == Harpoon.LATCHED:
		var stretch := _tip(fisher_body.harpoon_root()).distance_to(global_position)
		if stretch > lerpf(_tether_len, tether_break, 0.5):
			leap(-away, clampf(stretch - _tether_len, 120.0, leap_distance))
	elif harpoon == Harpoon.NONE:
		if _focus_rate > threat_speed and d < evade_range:
			leap_to(flank_point(leap_distance * evade_back))
		elif _focus_rate < -threat_speed and d > pursue_range:
			leap(-away, clampf(d - harpoon_range * 0.7, 120.0, leap_distance))
		elif _faced_time >= face_react:
			_faced_time = 0.0
			leap_to(flank_point(clampf(keep_range - d, -leap_distance * 0.3, leap_distance * 0.5)))


# Whether its prey has its front on it (within facing_cone of where it
# faces). Mechas face -Y.
func _faced() -> bool:
	if not is_valid_prey(target):
		return false
	var facing := Vector2.UP.rotated(target.global_rotation)
	return absf(rad_to_deg(facing.angle_to(global_position - target.global_position))) <= facing_cone


## Where to leap to get round the prey: about leap_distance away, `outward`
## px of it further from the prey (closer for less than 0), the rest round
## it toward the side its front is turned away from, at most max_flank_turn
## round. Straight in front, a side at random.
func flank_point(outward: float) -> Vector2:
	var prey := target.global_position
	var from_prey := global_position - prey
	var r := maxf(from_prey.length(), 1.0)
	var facing := Vector2.UP.rotated(target.global_rotation)
	var off_front := facing.angle_to(from_prey)
	var side := signf(off_front) if absf(off_front) > 0.01 else (1.0 if randf() < 0.5 else -1.0)
	var out := clampf(outward, -leap_distance, leap_distance)
	var new_r := maxf(r + out, radius + 120.0)
	var round_by := sqrt(maxf(leap_distance * leap_distance - out * out, 0.0))
	var turn := minf(round_by / ((r + new_r) * 0.5), max_flank_turn)
	return prey + from_prey.normalized().rotated(side * turn) * new_r


## Leap in a direction (world), the default distance or the one given.
func leap(direction: Vector2, distance := -1.0) -> void:
	if direction.length() < 0.01:
		return
	leap_to(global_position + direction.normalized() * (leap_distance if distance < 0.0 else distance))


## Leap to a point (world), if it has a leap left.
func leap_to(point: Vector2) -> void:
	if state != State.HUNT or _leap != FisherBody.LeapPhase.NONE or _leaps_left <= 0:
		return
	if point.distance_to(global_position) < 1.0:
		return
	_leap = FisherBody.LeapPhase.CROUCH
	_leap_t = 0.0
	_leap_from = global_position
	_leap_to = point
	_leaps_left -= 1
	_leap_cool = leap_cooldown
	leaps += 1


## Whether its harpoon is in `mecha`: that mecha always sees it, wherever it
## is (Player.can_see_body, Enemy._look_at), since it's on the end of the
## tether.
func is_tethered_to(mecha) -> bool:
	return harpoon == Harpoon.LATCHED and is_instance_valid(_latched_to) and is_same(_latched_to, mecha) and not is_dead


## Leaps it has left before it must wait (leap_charges, leap_cooldown).
func leaps_left() -> int:
	return _leaps_left


# Crouch, fly, land. In the air it moves at the leap's speed (walls stop it);
# it keeps facing its prey.
func _update_leap(dt: float) -> void:
	if _leap == FisherBody.LeapPhase.NONE:
		return
	if state != State.HUNT:
		_leap = FisherBody.LeapPhase.NONE
		fisher_body.set_leap(_leap, 0.0, Vector2.ZERO)
		return
	_leap_t += dt
	var dir := (_leap_to - _leap_from).normalized()
	var length: float = {FisherBody.LeapPhase.CROUCH: crouch_time, FisherBody.LeapPhase.AIR: air_time,
			FisherBody.LeapPhase.LAND: land_time}[_leap]
	var u := minf(_leap_t / length, 1.0)
	if _leap == FisherBody.LeapPhase.AIR:
		desired_velocity = (_leap_to - _leap_from) / air_time
		velocity = desired_velocity
	else:
		stop()
		velocity = Vector2.ZERO
	if is_valid_prey(target):
		face_point = target.global_position
	fisher_body.set_leap(_leap, u, dir)
	if u >= 1.0:
		_leap_t = 0.0
		if _leap == FisherBody.LeapPhase.CROUCH:
			_leap = FisherBody.LeapPhase.AIR
		elif _leap == FisherBody.LeapPhase.AIR:
			_leap = FisherBody.LeapPhase.LAND
			stop()
			velocity = Vector2.ZERO
		else:
			_leap = FisherBody.LeapPhase.NONE
		fisher_body.set_leap(_leap, 0.0, dir)


func die() -> void:
	_reel_in()
	harpoon = Harpoon.NONE
	super.die()
