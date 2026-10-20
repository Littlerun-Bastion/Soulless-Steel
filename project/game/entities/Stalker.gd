extends Entity
class_name Stalker

# Stalker: a lean pack hunter about the size of a car. Packs of 3-5 wander
# around a home area. When one spots a mecha, is shot, or hears gunfire, the
# whole pack responds. Hunting, they circle out of reach and drift round
# behind the prey, where its armour is thinnest; one at a time a Stalker
# crouches, lunges, bites and backs off again (EntityPack's attack token).
# A badly hurt Stalker runs off to lick its wounds, and a pack that loses
# half its members scatters.

enum State { WANDER, INVESTIGATE, STALK, WINDUP, LUNGE, RECOVER, FLEE }

@export_group("Hunting")
@export var orbit_radius := 520.0
@export var lunge_speed := 1150.0
@export var windup_time := 0.3
@export var lunge_time := 0.55
@export var recover_time := 0.7
@export var bite_damage := 1
@export var bite_pen := 2
@export var bite_knockback := 6.0
## Seconds between one Stalker's lunges (random in this range).
@export var lunge_cooldown := Vector2(2.0, 3.5)
## Seconds the pack waits after a lunge before the next member may go.
@export var pack_lunge_gap := 0.6
## How far a mecha's hull reaches from its centre (bite range = radius + this).
@export var prey_reach := 95.0
## A Stalker waiting this long for a shot at the prey's back takes any opening.
@export var patience := 4.0
@export_group("Fear")
## Flees below this fraction of its hp, and won't hunt again until healed past it.
@export var flee_below := 0.35
@export var flee_time := 5.0
@export_group("Wandering")
@export var wander_radius := 1500.0

var state: State = State.WANDER
var bites := 0  # lunges that reached the prey (tests, tuning)

var _state_time := 0.0
var _lunge_cooldown := 0.0
var _lunge_dir := Vector2.ZERO
var _wander_point = null
var _wander_wait := 0.0
var _investigate_point := Vector2.ZERO
var _formation_offset := Vector2.ZERO
var _orbit_offset := 0.0   # its own spot in the ring behind the prey
var _flee_from := Vector2.ZERO


func _ready() -> void:
	super._ready()
	_formation_offset = Vector2.from_angle(randf() * TAU) * randf_range(140.0, 280.0)
	_orbit_offset = randf_range(-0.8, 0.8)
	_lunge_cooldown = randf_range(0.5, 1.5)


func behave(dt: float) -> void:
	_state_time += dt
	_lunge_cooldown = maxf(_lunge_cooldown - dt, 0.0)
	body_visual.crouch = move_toward(body_visual.crouch, 1.0 if state == State.WINDUP else 0.0, dt * 6.0)
	if pack != null and pack.broken and state != State.FLEE:
		_start_flee()
	match state:
		State.WANDER: _wander(dt)
		State.INVESTIGATE: _investigate()
		State.STALK: _stalk()
		State.WINDUP: _windup()
		State.LUNGE: _lunge()
		State.RECOVER: _recover()
		State.FLEE: _flee()


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


# ---- Hooks ----

func wants_prey() -> bool:
	return state != State.FLEE and get_hp_fraction() > flee_below


func on_target_acquired(prey: Node2D) -> void:
	_set_state(State.STALK)
	if pack != null:
		pack.alert(prey, self)


func on_target_lost() -> void:
	_give_back_token()
	if state != State.FLEE:
		settle_home()
		_wander_point = null
		_set_state(State.WANDER)


func on_heard(point: Vector2) -> void:
	if state == State.WANDER or state == State.INVESTIGATE:
		_go_investigate(point)
		if pack != null:
			pack.investigate(point, self)


func join_investigation(point: Vector2) -> void:
	if state == State.WANDER or state == State.INVESTIGATE:
		_go_investigate(point + _formation_offset)


func on_hurt(amount: float) -> void:
	if state == State.FLEE:
		if is_valid_prey(last_attacker):
			_flee_from = last_attacker.global_position
		return
	if get_hp_fraction() < flee_below:
		_start_flee()
		return
	super.on_hurt(amount)


# ---- States ----

func _wander(dt: float) -> void:
	face_point = null
	heal(regen_rate * dt)
	# Followers keep loosely to the leader.
	var leader: Node2D = pack.leader() if pack != null else null
	if leader != null and leader != self and distance_to(leader) < 3000.0:
		var slot := leader.global_position + _formation_offset
		var far := global_position.distance_to(slot) > 400.0
		move_to(slot, walk_speed if far else walk_speed * 0.5, 60.0)
		return
	if _wander_wait > 0.0:
		_wander_wait -= dt
		stop()
		return
	if _wander_point == null or _state_time > 10.0:
		_wander_point = random_point_near(home, wander_reach(wander_radius))
		_state_time = 0.0
	if global_position.distance_to(_wander_point) < 80.0:
		_wander_point = null
		_wander_wait = randf_range(1.0, 3.0)
		stop()
		return
	move_to(_wander_point, walk_speed * 0.6)


func _go_investigate(point: Vector2) -> void:
	_investigate_point = point
	_set_state(State.INVESTIGATE)


func _investigate() -> void:
	face_point = null
	move_to(_investigate_point, run_speed * 0.7, 120.0)
	if global_position.distance_to(_investigate_point) < 150.0 or _state_time > 12.0:
		# Nothing here: settle down nearby.
		settle_home()
		_wander_point = null
		_set_state(State.WANDER)


# Circle the prey on a ring, working round towards its back.
func _stalk() -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	face_point = target.global_position
	var to_me := global_position - target.global_position
	var d := to_me.length()
	var prey_back := Vector2(0, 1).rotated(target.global_rotation)  # mechas face -Y
	var wanted_angle := prey_back.angle() + _orbit_offset
	var step := clampf(angle_difference(to_me.angle(), wanted_angle), -0.6, 0.6)
	var ring_point := target.global_position + Vector2.from_angle(to_me.angle() + step) * orbit_radius
	move_to(ring_point, run_speed if d > orbit_radius * 1.5 else run_speed * 0.75, 20.0)

	var good_angle := EntityAttack.facing_toward(target, global_position) != "front"
	if _lunge_cooldown <= 0.0 and d < orbit_radius * 1.3 \
			and (good_angle or _state_time > patience) and _take_token():
		_set_state(State.WINDUP)


func _windup() -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	stop()
	face_point = target.global_position
	if _state_time >= windup_time:
		var predicted: Vector2 = target.global_position + target.velocity * 0.25
		_lunge_dir = (predicted - global_position).normalized()
		velocity = _lunge_dir * lunge_speed
		face_point = null
		_set_state(State.LUNGE)


func _lunge() -> void:
	desired_velocity = _lunge_dir * lunge_speed
	if is_valid_prey(target) and distance_to(target) <= radius + prey_reach:
		_bite()
		_end_lunge()
	elif _state_time >= lunge_time:
		_end_lunge()


func _bite() -> void:
	bites += 1
	EntityAttack.hit_mecha(self, target, bite_damage, bite_pen, bite_knockback)
	AudioManager.play_sfx("mech_impact_light%d" % randi_range(1, 5), global_position)


func _end_lunge() -> void:
	_lunge_cooldown = randf_range(lunge_cooldown.x, lunge_cooldown.y)
	_give_back_token()
	_set_state(State.RECOVER)


# Back off out of reach before circling again.
func _recover() -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	face_point = null
	var away := (global_position - target.global_position).normalized().rotated(_orbit_offset)
	move_in(away, run_speed)
	if _state_time >= recover_time:
		_set_state(State.STALK)


func _start_flee() -> void:
	_give_back_token()
	if is_valid_prey(target):
		_flee_from = target.global_position
	elif is_valid_prey(last_attacker):
		_flee_from = last_attacker.global_position
	else:
		_flee_from = global_position - forward() * 100.0
	target = null
	face_point = null
	_set_state(State.FLEE)


func _flee() -> void:
	var away := global_position - _flee_from
	if away.length() < 1.0:
		away = -forward()
	move_in(away, run_speed)
	if _state_time >= flee_time:
		settle_home()
		_wander_point = null
		last_attacker = null
		if pack != null and pack.broken:
			pack.regroup()
		_set_state(State.WANDER)


func _take_token() -> bool:
	return pack == null or pack.try_take_token(self)


func _give_back_token() -> void:
	if pack != null:
		pack.release_token(self, pack_lunge_gap)
