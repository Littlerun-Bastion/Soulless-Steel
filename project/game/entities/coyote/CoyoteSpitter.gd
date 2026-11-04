extends Coyote
class_name CoyoteSpitter

# Coyote Spitter: the pack's gun. It runs with the Coyotes (wandering,
# investigating, fleeing and scattering as they do) but never lunges.
# Hunting, it circles the prey at range, working round to its side, and
# fires from off angles, where the armour is thinner: its two tails curl
# forward and the body pulses as it charges (CoyoteSpitterBody), then it
# spits a glob of sand (an AcidGlob) at where the prey is heading. The shot
# is medium AP (glob_pen 3): it gets through side and rear armour but only
# glances off a mecha's front.

const GLOB_SCRIPT := preload("res://game/entities/AcidGlob.gd")

@export_group("Spitting")
## The distance it fires from (min, max); it circles at orbit_radius.
@export var fire_range := Vector2(350.0, 1000.0)
## Seconds between shots (random in this range).
@export var fire_cooldown := Vector2(2.0, 3.0)
@export var glob_damage := 1
@export var glob_pen := 3
@export var glob_splash := 60.0
@export var glob_speed := 1100.0
@export var glob_color := Color(0.12, 0.12, 0.12)
@export var glob_arc := 40.0
## How long it waits for an off angle before it fires from anywhere.
@export var flank_patience := 5.0

var shots := 0  # globs fired (tests, tuning)

var _side := 1.0  # which side of the prey it works round to

@onready var spitter_body: CoyoteSpitterBody = $Body as CoyoteSpitterBody


func _ready() -> void:
	super._ready()
	spitter_body.fired.connect(_on_fired)


func on_target_acquired(prey: Node2D) -> void:
	# Work round to whichever side of the prey it's on already.
	var right := Vector2(1, 0).rotated(prey.global_rotation)
	_side = 1.0 if (global_position - prey.global_position).dot(right) >= 0.0 else -1.0
	super.on_target_acquired(prey)


# Its spot on the ring is off the prey's side, a little behind.
func _ring_angle() -> float:
	return Vector2(_side, 0).rotated(target.global_rotation).angle() + _side * 0.35 + _orbit_offset * 0.3


func _stalk() -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	face_point = target.global_position
	_circle(_ring_angle(), orbit_radius)
	var d := distance_to(target)
	var off_angle := EntityAttack.facing_toward(target, global_position) != "front"
	if _lunge_cooldown <= 0.0 and d >= fire_range.x and d <= fire_range.y \
			and (off_angle or _state_time > flank_patience) and can_see(target):
		spitter_body.charge(_aim_point())
		_set_state(State.WINDUP)


# Charging: it keeps circling, slowly, its tails tracking the prey. The
# body fires when the charge is done.
func _windup() -> void:
	if not is_valid_prey(target):
		lose_target()
		return
	face_point = target.global_position
	_circle(_ring_angle(), orbit_radius, 0.35)
	spitter_body.aim_point = _aim_point()
	if not spitter_body.is_attacking():
		_lunge_cooldown = randf_range(fire_cooldown.x, fire_cooldown.y) * attack_gap_mult()
		_set_state(State.STALK)


# Where the prey will be when a glob from here reaches it.
func _aim_point() -> Vector2:
	var flight := clampf(distance_to(target) / glob_speed, 0.2, 1.2)
	return target.global_position + target.velocity * flight * 0.8


func _on_fired(muzzle: Vector2, _direction: Vector2) -> void:
	if not is_valid_prey(target) or is_dead:
		return
	shots += 1
	var aim := _aim_point()
	var glob: AcidGlob = GLOB_SCRIPT.new()
	glob.damage = glob_damage
	glob.pen = glob_pen
	glob.splash_radius = glob_splash
	glob.color = glob_color
	glob.arc_height = glob_arc
	_projectile_parent().add_child(glob)
	glob.launch(self, arena, muzzle, aim, clampf(muzzle.distance_to(aim) / glob_speed, 0.2, 1.2))
	AudioManager.play_sfx("pressure_gun_light", global_position)
