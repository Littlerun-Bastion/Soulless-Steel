extends Entity
class_name Brute

# Brute: rare, huge and armoured (most guns do half damage). It's
# territorial: it roams near home, only investigates noise inside its
# territory, and walks back home when its prey gets away. Hunting, it plods
# after its prey (slower than a mecha) and, from mid range, charges: a
# visible wind-up (it shudders and crouches), then a straight rush that rams
# the first mecha in its way. Charging into a wall stuns it for a moment.
# Up close it stomps, hitting every mecha around it. Hurting it enrages it
# (faster, shorter wind-up and cooldown); it never flees.

enum State { WANDER, INVESTIGATE, HUNT, WINDUP, CHARGE, RECOVER, STOMP, STUNNED }

const RAGE_EYE_COLOR := Color(1.0, 0.25, 0.15)
const RECOVER_TIME := 0.8

@export_group("Charge")
## Charges at prey this far away (min, max).
@export var charge_range := Vector2(350.0, 1100.0)
@export var charge_speed := 900.0
@export var charge_windup := 0.8
@export var charge_time := 1.4
@export var charge_cooldown := 4.0
@export var ram_damage := 2
@export var ram_pen := 3
@export var ram_knockback := 40.0
@export var stun_time := 1.5
@export_group("Stomp")
## Stomps when prey is within radius + this (and hits that far plus a hull).
@export var stomp_range := 180.0
@export var stomp_windup := 0.35
@export var stomp_cooldown := 1.6
@export var stomp_damage := 1
@export var stomp_pen := 3
@export var stomp_knockback := 15.0
@export_group("Rage")
@export var rage_time := 8.0
@export var rage_speed_mult := 1.25
@export_group("Territory")
## Ignores noises further than this from home, and gives up a chase that
## drags it 1.5x this far away.
@export var territory_radius := 2500.0
@export var wander_radius := 900.0

var state: State = State.WANDER
var rams := 0    # (tests, tuning)
var stomps := 0
var stuns := 0

var _state_time := 0.0
var _charge_cooldown := 0.0
var _stomp_cooldown := 0.0
var _rage := 0.0
var _charge_dir := Vector2.ZERO
var _wander_point = null
var _wander_wait := 0.0
var _investigate_point := Vector2.ZERO
var _calm_eye_color := Color.WHITE


func _ready() -> void:
	super._ready()
	_calm_eye_color = body_visual.eye_color
	_charge_cooldown = randf_range(1.0, 2.0)


func is_enraged() -> bool:
	return _rage > 0.0


func behave(dt: float) -> void:
	_state_time += dt
	_charge_cooldown = maxf(_charge_cooldown - dt, 0.0)
	_stomp_cooldown = maxf(_stomp_cooldown - dt, 0.0)
	_rage = maxf(_rage - dt, 0.0)
	body_visual.eye_color = RAGE_EYE_COLOR if is_enraged() else _calm_eye_color
	var crouching := state == State.WINDUP or state == State.STOMP
	body_visual.crouch = move_toward(body_visual.crouch, 1.0 if crouching else 0.0, dt * 4.0)
	# Shudders while winding up a charge: the tell.
	body_visual.position = Vector2(randf_range(-5, 5), randf_range(-5, 5)) if state == State.WINDUP else Vector2.ZERO
	match state:
		State.WANDER: _wander(dt)
		State.INVESTIGATE: _investigate()
		State.HUNT: _hunt()
		State.WINDUP: _windup()
		State.CHARGE: _charge()
		State.RECOVER: _recover()
		State.STOMP: _stomp()
		State.STUNNED: _stunned()


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


func _speed(base: float) -> float:
	return base * (rage_speed_mult if is_enraged() else 1.0)


# ---- Hooks ----

# It opens a fight with a charge, not by plodding into stomping range.
const OPENING_CHARGE_DELAY := 0.4

func on_target_acquired(_prey: Node2D) -> void:
	if state == State.WANDER or state == State.INVESTIGATE:
		_charge_cooldown = minf(_charge_cooldown, OPENING_CHARGE_DELAY)
		_set_state(State.HUNT)


func on_target_lost() -> void:
	if state != State.CHARGE and state != State.STUNNED:
		_wander_point = null
		_set_state(State.WANDER)  # home stays where it is: it walks back


func on_heard(point: Vector2) -> void:
	if point.distance_to(home) > territory_radius:
		return
	if state == State.WANDER or state == State.INVESTIGATE:
		_investigate_point = point
		_set_state(State.INVESTIGATE)


func on_hurt(amount: float) -> void:
	_rage = rage_time
	super.on_hurt(amount)


# ---- States ----

func _wander(dt: float) -> void:
	face_point = null
	heal(regen_rate * dt)
	if _wander_wait > 0.0:
		_wander_wait -= dt
		stop()
		return
	if _wander_point == null or _state_time > 12.0:
		_wander_point = random_point_near(home, wander_radius)
		_state_time = 0.0
	if global_position.distance_to(_wander_point) < 100.0:
		_wander_point = null
		_wander_wait = randf_range(2.0, 5.0)
		stop()
		return
	move_to(_wander_point, walk_speed * 0.5)


func _investigate() -> void:
	face_point = null
	move_to(_investigate_point, walk_speed, 150.0)
	if global_position.distance_to(_investigate_point) < 200.0 or _state_time > 12.0:
		_wander_point = null
		_set_state(State.WANDER)


func _hunt() -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	if global_position.distance_to(home) > territory_radius * 1.5:
		lose_target()
		return
	face_point = target.global_position
	var d := distance_to(target)
	if d <= radius + stomp_range and _stomp_cooldown <= 0.0:
		_set_state(State.STOMP)
	elif d >= charge_range.x and d <= charge_range.y and _charge_cooldown <= 0.0 and can_see(target):
		_set_state(State.WINDUP)
		AudioManager.play_sfx("low_tone", global_position)
	else:
		move_to(target.global_position, _speed(walk_speed), radius + 60.0)


func _windup() -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	stop()
	face_point = target.global_position
	if _state_time >= charge_windup * (0.6 if is_enraged() else 1.0):
		var predicted: Vector2 = target.global_position + target.velocity * 0.3
		start_charge((predicted - global_position).normalized())


# A straight rush; rams the first mecha it meets, stunned by a wall.
func start_charge(dir: Vector2) -> void:
	_charge_dir = dir.normalized()
	face_point = null
	velocity = _charge_dir * _speed(charge_speed)
	_set_state(State.CHARGE)


func _charge() -> void:
	desired_velocity = _charge_dir * _speed(charge_speed)
	# What it ran into last physics step.
	for i in get_slide_collision_count():
		var collider = get_slide_collision(i).get_collider()
		if is_valid_prey(collider):
			_ram(collider)
			return
		if collider != null and not (collider is Entity) and not collider.is_in_group("mecha"):
			_stun()
			return
	if is_valid_prey(target) and distance_to(target) <= radius + EntityAttack.HULL_REACH + 20.0:
		_ram(target)
		return
	if _state_time >= charge_time:
		_end_charge()


func _ram(mecha: Node2D) -> void:
	rams += 1
	EntityAttack.hit_mecha(self, mecha, ram_damage, ram_pen, ram_knockback)
	AudioManager.play_sfx("large_impact%d" % randi_range(1, 2), global_position)
	_end_charge()


func _stun() -> void:
	stuns += 1
	AudioManager.play_sfx("medium_impact2", global_position)
	velocity = -_charge_dir * 150.0
	stop()
	_charge_cooldown = charge_cooldown
	_set_state(State.STUNNED)


func _end_charge() -> void:
	stop()
	_charge_cooldown = charge_cooldown * (0.6 if is_enraged() else 1.0)
	_set_state(State.RECOVER)


func _recover() -> void:
	stop()
	if _state_time >= RECOVER_TIME:
		_set_state(State.HUNT if is_valid_prey(target) else State.WANDER)


func _stomp() -> void:
	stop()
	if _state_time >= stomp_windup:
		stomps += 1
		var mechas: Array = arena.get_mechas() if arena != null else []
		EntityAttack.hit_mechas_near(self, mechas, global_position, radius + stomp_range, stomp_damage, stomp_pen, stomp_knockback)
		AudioManager.play_sfx("large_impact2", global_position)
		_stomp_cooldown = stomp_cooldown
		_set_state(State.HUNT)


func _stunned() -> void:
	stop()
	if _state_time >= stun_time:
		_set_state(State.HUNT if is_valid_prey(target) else State.WANDER)
