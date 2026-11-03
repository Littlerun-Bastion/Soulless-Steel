extends Node2D

# A smoke cloud, left where a smoke canister goes off
# (complex_projectile.payload_spawn). It grows to `radius` over grow_time,
# lasts `lifetime` s in all and thins out over its last fade_time s. While it
# is thick (from half way through its growth to half way through its fade)
# it blocks sight: nothing can see into, out of or through it. The queries
# (point_in_smoke, blocks) are used through MapSenses by the player's view
# (Player), NPC senses (MapSenses.sight_blocked in Enemy.update_senses) and
# Entities (Entity.can_see). It casts no shadow: the light cones pass
# through it, and what it hides is hidden by those queries.
#
# The look is the Particles child (GPUParticles2D, one shot): puffs burst
# out, slow to a stop near the edge over about 1.5 s and fade out together
# over the last 2/15 of their life. Its material is tuned for a cloud of
# PARTICLE_RADIUS that grows over 1.5 s, lasts 15 s and fades over 2 s; _ready
# scales the node to `radius` and sets the puffs' life to `lifetime`. The
# particles are on light layers 1 and 2 like the map, so the darkness, the
# cones and wall shadows all act on them.
#
# Clouds are few and short-lived: the queries check every live cloud in a
# static list with plain maths, no physics.

const PARTICLE_RADIUS := 300.0

@export var radius := 300.0
@export var grow_time := 1.5
@export var lifetime := 15.0
@export var fade_time := 2.0

static var _clouds: Array = []

var _age := 0.0

@onready var Particles: GPUParticles2D = $Particles


func _ready() -> void:
	z_index = 2
	_clouds.append(self)
	Particles.lifetime = lifetime
	Particles.scale = Vector2.ONE * radius / PARTICLE_RADIUS


func _exit_tree() -> void:
	_clouds.erase(self)


func _physics_process(dt: float) -> void:
	_age += dt
	if _age >= lifetime:
		queue_free()


func current_radius() -> float:
	if grow_time <= 0.0:
		return radius
	return radius * clampf(_age / grow_time, 0.0, 1.0)


func is_thick() -> bool:
	return _age >= grow_time * 0.5 and _age <= lifetime - fade_time * 0.5


# Whether `point` is inside thick smoke.
static func point_in_smoke(point: Vector2) -> bool:
	for cloud in _clouds:
		if is_instance_valid(cloud) and cloud.is_thick() \
				and point.distance_to(cloud.global_position) <= cloud.current_radius():
			return true
	return false


# Whether thick smoke lies anywhere on the segment from `a` to `b` (either
# end inside it included).
static func blocks(a: Vector2, b: Vector2) -> bool:
	for cloud in _clouds:
		if not is_instance_valid(cloud) or not cloud.is_thick():
			continue
		var centre: Vector2 = cloud.global_position
		if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre) <= cloud.current_radius():
			return true
	return false


static func count() -> int:
	return _clouds.size()
