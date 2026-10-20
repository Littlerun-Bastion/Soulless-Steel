extends Entity
class_name Spitter

# Spitter: ranged support, fragile. It wanders alone, and when it finds prey
# it keeps its distance (keep_range), strafing from side to side; every few
# seconds it rears up and lobs a volley of acid globs (AcidGlob) at where the
# prey is heading. If a mecha closes in it backs off fast, and when badly
# hurt it flees.

enum State { WANDER, INVESTIGATE, KEEP_RANGE, SPIT, FLEE }

const GLOB_SCRIPT := preload("res://game/entities/AcidGlob.gd")

@export_group("Spitting")
## The distance it tries to keep from its prey (min, max).
@export var keep_range := Vector2(900.0, 1300.0)
## Closer than this, it backs off at a run.
@export var retreat_range := 650.0
@export var volley_size := 3
@export var spit_cooldown := 2.2
@export var spit_windup := 0.4
@export var glob_flight_time := 0.9
## How far globs land around the aim point.
@export var glob_scatter := 120.0
@export var acid_damage := 1
@export var acid_pen := 2
@export var splash_radius := 110.0
@export_group("Fear")
@export var flee_below := 0.4
@export var flee_time := 4.0
@export_group("Wandering")
@export var wander_radius := 1200.0

var state: State = State.WANDER
var volleys := 0  # volleys spat (tests, tuning)

var _state_time := 0.0
var _spit_cooldown := 0.0
var _strafe_side := 1.0
var _strafe_time := 0.0
var _wander_point = null
var _wander_wait := 0.0
var _investigate_point := Vector2.ZERO
var _flee_from := Vector2.ZERO


func _ready() -> void:
	super._ready()
	_spit_cooldown = randf_range(0.5, 1.5)
	_strafe_side = 1.0 if randf() < 0.5 else -1.0


func behave(dt: float) -> void:
	_state_time += dt
	_spit_cooldown = maxf(_spit_cooldown - dt, 0.0)
	body_visual.crouch = move_toward(body_visual.crouch, 1.0 if state == State.SPIT else 0.0, dt * 5.0)
	match state:
		State.WANDER: _wander(dt)
		State.INVESTIGATE: _investigate()
		State.KEEP_RANGE: _keep_range(dt)
		State.SPIT: _spit()
		State.FLEE: _flee()


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


# ---- Hooks ----

func wants_prey() -> bool:
	return state != State.FLEE and get_hp_fraction() > flee_below


func on_target_acquired(_prey: Node2D) -> void:
	_set_state(State.KEEP_RANGE)


func on_target_lost() -> void:
	if state != State.FLEE:
		settle_home()
		_wander_point = null
		_set_state(State.WANDER)


func on_heard(point: Vector2) -> void:
	if state == State.WANDER or state == State.INVESTIGATE:
		_investigate_point = point
		_set_state(State.INVESTIGATE)


func on_hurt(amount: float) -> void:
	if state == State.FLEE:
		return
	if get_hp_fraction() < flee_below:
		_start_flee()
		return
	super.on_hurt(amount)


# ---- States ----

func _wander(dt: float) -> void:
	face_point = null
	heal(regen_rate * dt)
	if _wander_wait > 0.0:
		_wander_wait -= dt
		stop()
		return
	if _wander_point == null or _state_time > 10.0:
		_wander_point = random_point_near(home, wander_reach(wander_radius))
		_state_time = 0.0
	if global_position.distance_to(_wander_point) < 80.0:
		_wander_point = null
		_wander_wait = randf_range(1.5, 4.0)
		stop()
		return
	move_to(_wander_point, walk_speed * 0.5)


# Edges towards the noise, but only to spitting range of it.
func _investigate() -> void:
	face_point = null
	move_to(_investigate_point, walk_speed, keep_range.x)
	if global_position.distance_to(_investigate_point) <= keep_range.x + 50.0 or _state_time > 12.0:
		settle_home()
		_wander_point = null
		_set_state(State.WANDER)


func _keep_range(dt: float) -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	face_point = target.global_position
	var away := global_position - target.global_position
	var d := away.length()
	_strafe_time -= dt
	if _strafe_time <= 0.0:
		_strafe_time = randf_range(2.0, 4.0)
		_strafe_side = -_strafe_side
	if d < retreat_range:
		move_in(away, run_speed)
	elif d < keep_range.x:
		move_in(away.normalized() + away.orthogonal().normalized() * _strafe_side * 0.5, walk_speed)
	elif d > keep_range.y:
		move_in(-away, walk_speed)
	else:
		move_in(away.orthogonal() * _strafe_side, walk_speed * 0.8)
	if _spit_cooldown <= 0.0 and d >= retreat_range * 0.6 and d <= keep_range.y + 300.0 and can_see(target):
		_set_state(State.SPIT)


# Rears up (crouch), then lobs the volley.
func _spit() -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	stop()
	face_point = target.global_position
	if _state_time >= spit_windup:
		spit_volley(target)
		_spit_cooldown = spit_cooldown
		_set_state(State.KEEP_RANGE)


# Globs land around where the prey will be when they come down.
func spit_volley(prey: Node2D) -> void:
	volleys += 1
	var aim: Vector2 = prey.global_position + prey.velocity * glob_flight_time * 0.8
	var parent: Node = _glob_parent()
	for i in volley_size:
		var glob: AcidGlob = GLOB_SCRIPT.new()
		glob.damage = acid_damage
		glob.pen = acid_pen
		glob.splash_radius = splash_radius
		parent.add_child(glob)
		var scatter := Vector2.ZERO if i == 0 else Vector2.from_angle(randf() * TAU) * glob_scatter * sqrt(randf())
		glob.launch(self, arena, global_position + forward() * radius, aim + scatter, glob_flight_time * randf_range(0.9, 1.1))
	AudioManager.play_sfx("pressure_gun_light", global_position)


# Globs fly above everything: in the scene's projectile layer when it has one.
func _glob_parent() -> Node:
	var projectiles = arena.get("Projectiles") if arena != null else null
	return projectiles if projectiles is Node else get_parent()


func _start_flee() -> void:
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
		_set_state(State.WANDER)
