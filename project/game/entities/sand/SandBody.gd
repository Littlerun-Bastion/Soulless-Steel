extends Node2D
class_name SandBody

enum BodyShape { WEDGE, NARROW, ROUND, NONE }

#There probably is a better way of doing this but idk lmao.
const LIMB_SHADER := preload("res://game/entities/sand/sand_limb.gdshader")
const GRAIN_SHADER := preload("res://game/entities/sand/sand_grains.gdshader")
## Must match MAX_POINTS in sand_grains.gdshader.
const MAX_POINTS := 64
## Seconds for the body to dissolve into the death burst.
const BODY_BREAK_TIME := 0.12
## Shadow offset per pixel of height.
const SHADOW_PER_HEIGHT := 0.6
const ROPE_POINTS := 12
const TAIL_POINTS := 24
## Length of limb, in px, for one full turn of a braid strand.
const STRAND_TURN_PX := 70.0
const HEAD_FLASH_SHADER := """
shader_type canvas_item;
uniform float flash = 0.0;
void fragment() {
	vec4 c = COLOR;  // already the texture times modulate
	COLOR = vec4(mix(c.rgb, vec3(1.0), flash), c.a);
}
"""

@export_group("Body")
@export var body_shape := BodyShape.WEDGE
@export var body_length := 130.0
@export var body_width := 100.0
## The dark core showing between the body ropes.
@export var body_color := Color(0.07, 0.07, 0.07)
## Highlight on the rounded tops of ropes and braid strands.
@export var ridge_color := Color(0.30, 0.30, 0.30)
## Number of tentacles wound together to form the body.
@export var body_strands := 14
## How far body ropes reach back past the body (1 = to its back edge).
@export var rope_trail := 1.1
## NONE body only: radius of the knot of coiled ropes behind the head
## that limbs and tails grow out of (0 = no knot), and its centre, as a
## fraction of body_length forward of the origin.
@export var knot_radius := 0.0
@export var knot_x := 0.0
## How much the body stretches and gathers with each stride when running
## (a galloping spine). 0 = rigid.
@export var spine_flex := 0.0

@export_group("Head")
## The head sprite, drawn facing right (+X). The middle of its left edge is
## the neck. Leave empty to use a generated placeholder.
@export var head_texture: Texture2D
## false = no head (the species draws its own top, like a shell).
@export var has_head := true
@export var head_scale := 1.0
## Where the neck attaches, as a fraction of body_length forward of centre.
@export var neck_position := 0.24
## Size of the generated placeholder head, in px.
@export var placeholder_head_size := Vector2(34.0, 22.0)
@export var eye_color := Color(0.92, 0.92, 0.92)

@export_group("Legs")
@export var limb_length := 150.0
## Points per limb chain. (Legs + tails) x this must stay within MAX_POINTS.
@export var limb_points := 8
@export var limb_width := 18.0
@export var grain_color := Color(0.05, 0.05, 0.05)
## Thigh, shin and ankle-bone length as fractions of limb_length. With
## ankle_leg > 0 the leg has three segments, like a cheetah's: the ankle
## bone rises from the foot at ankle_angle, so the bend is spread over two
## joints instead of one.
@export var upper_leg := 0.5
@export var lower_leg := 0.62
@export var ankle_leg := 0.0
@export var ankle_angle := 60.0
## How far out from the centre line the hips sit, as a fraction of the
## body's half width there. Low values tuck the legs under the body.
@export var hip_inset := 0.35
## Rest distance from hip to foot, as a fraction of limb_length.
@export var rest_reach := 0.79

@export_group("Gait")
## Step length, as a fraction of limb_length, walking and running (0 =
## the same as walking). A longer stride also means a slower cycle, and a
## planted foot that sweeps further back under the body.
@export var stride := 0.65
@export var run_stride := 0.0
## Speeds (px/s) between which the gait blends from its walk to its run.
## Unset (0), it blends with intensity (idle to hunting) instead.
@export var gallop_from := 0.0
@export var gallop_at := 0.0
## Fraction of each cycle a foot stays planted, walking and running.
@export var duty_walk := 0.7
@export var duty_run := 0.55
## Most legs that may be off the ground at once. 3 keeps an insect tripod
## planted; a galloper can have every leg up.
@export var max_airborne := 3
## How far a swinging foot reaches forward past its landing spot mid-step,
## as a fraction of limb_length. A galloper's legs stretch out in flight.
@export var swing_reach := 0.0
## How far each landing spot can wander from the rest pose, in degrees.
@export var foot_scatter := 5.0
## When standing, a foot further than this from its rest pose (as a fraction
## of limb_length) steps back in.
@export var settle_distance := 0.3
## Body yaw rocking in time with the gait, in degrees.
@export var waddle := 2.5
## Fold the legs up under the body after standing still for retract_delay.
@export var retract_when_still := false
@export var retract_delay := 0.4
## Folded foot distance from the hip, as a fraction of limb_length.
@export var retract_reach := 0.3

## Claws on each foot (0 = none) and their length in px. They splay open
## as the foot swings and close as it plants.
@export var claw_count := 0
@export var claw_length := 16.0
## A solid foot at the end of each leg: thick toes (one per claw), sized as
## a fraction of the leg's width (0 = the leg tapers to a point). Legs
## with paws stay thick to the end.
@export var paw_size := 0.0

@export_group("Depth")
## Hip height above the ground, as a fraction of limb_length.
@export var hip_height := 0.3
## How high a foot lifts mid-step, as a fraction of limb_length.
@export var step_height := 0.22
## How far the knees lean out from straight up, in degrees.
@export var knee_tilt := 40.0
## Ground shadow opacity (0 = off) and the direction the light comes from.
@export var shadow_strength := 0.13
@export var light_angle := 55.0

@export_group("Flow")
## Grain flow speed along the limbs, idle and hunting.
@export var idle_flow := 0.6
@export var hunt_flow := 3.0

@export_group("Death")
@export var death_grains := 1600
@export var burst_speed := 1100.0
## Seconds until the last grain has faded out.
@export var scatter_time := 1.4

# Set by the Entity:
var velocity := Vector2.ZERO   # from update_motion()
var alarm := false    # true while it hunts
var flash := 0.0      # 0..1, white when hit
var crouch := 0.0     # 0..1, sinks the body on its legs
var dead := false
var intensity := 0.2  # 0 = calm, 1 = hunting; eases towards alarm
var flow_phase := 0.0 # accumulated, so flow speed can change without jumps
var gait_phase := 0.0 # cycles walked; a leg's timing is this plus its phase
var gait_blend := 0.0 # 0 = walking gait, 1 = running gait
var thrash := 0.0     # 0..1, set by a species while attacking: tendrils thrash
var body_lift := 1.0  # 0..1, set by a species: 0 = body resting on the ground
# Set by a species for leaps:
var air_height := 0.0      # px the whole Entity is lifted off the ground
var airborne := false      # true = the feet hold a pose instead of stepping
var leg_tuck := 0.0        # 0..1, draws the feet in under the body
var foot_lead := Vector2.ZERO  # world offset the feet reach towards while airborne
var kick := 0.0            # 0..1, a burst of shed grains (take-off, landing)
# Species effects, applied by the base every frame:
var head_lunge := 0.0     # 0..1, snaps the head forward (a bite)
var body_swell := 0.0     # extra body scale, for pulsing
var pulse_pos := 0.0      # 0..1 along every rope, where a bright band sits
var pulse_strength := 0.0 # brightness of that band

var _limbs: Array[Limb] = []
var _tails: Array[Tail] = []
var _ropes: Array[Rope] = []
var _limb_layer: Node2D
var _tail_layer: Node2D
var _shadow_layer: Node2D
var _body_layer: Node2D
var _head: Sprite2D
var _grains: GPUParticles2D
var _death: GPUParticles2D
var _death_time := 0.0
var _time := 0.0
var _white_tex: ImageTexture
var _taper: Curve
var _rope_taper: Curve
var _tail_taper: Curve
var _last_rotation := 0.0
var _waddle := 0.0
var _flex := 1.0          # current spine stretch along the body
var _still_time := 0.0
var _retract := 0.0       # 0..1, how far the legs are folded
var _tail_specs: Array = []
var _knee_index := 1      # chain point that sits on the knee
var _ankle_index := 1     # ... and on the ankle (the foot, for a two-bone leg)
var _paw_taper: Curve
var _claw_layer: Node2D


class Limb:
	var anchor := Vector2.ZERO   # hip, body space
	var rest_angle := 0.0        # body-space direction the leg reaches in
	var side := 1.0
	var walk_phase := 0.0        # its timing in the gait cycle when walking
	var run_phase := 0.0         # ... and when running
	var cycle := 0               # last gait cycle this leg stepped in
	var seed := 0.0
	var points := PackedVector2Array()  # world space, hip first
	var prev := PackedVector2Array()
	var heights := PackedFloat32Array() # height of each point above the ground
	var foot := Vector2.ZERO     # world space
	var swing_from := Vector2.ZERO
	var swing_t := -1.0          # 0..1 through a step; < 0 means planted
	var swing_time := 0.15       # seconds this step takes
	var angle_jitter := 0.0      # radians off the rest pose, rolled per step
	var reach_jitter := 1.0      # multiplier on reach, rolled per step
	var lift := 0.0              # 0..1, how far the foot is raised
	var lean := 1.0              # which side of the leg the knee leans to
	var width := 18.0
	var claw_angle := 0.0        # world direction its toes point, eased
	var has_root := false        # grows out from root (body space) to its hip
	var root := Vector2.ZERO
	var extend := 1.0            # 0..1, set by a species: 0 = hidden at its root
	var line: Line2D             # flowing sand core
	var strands: Array[Line2D] = []  # rope strands braided round the core


class Tail:
	var root := Vector2.ZERO     # body space
	var length := 180.0
	var width := 14.0
	var rest_angle := PI         # body-space direction it trails in at rest
	var sway := 0.35             # how far it sways at rest, radians
	var sway_speed := 1.6
	var run_sway := 0.35         # ... and at a run (blends with gait_blend)
	var run_speed := 1.6
	var run_stiffness := 0.12
	var thrashes := false        # joins in when the species thrashes
	var phase := 0.0             # accumulated wave phase, so speed changes don't jump
	var waves := 0.6             # wavelengths of undulation along its length
	var floaty := 0.0            # 0..1, how much its heading drifts
	var stiffness := 0.12        # how hard each joint eases back to its angle, per frame
	var damping := 0.94          # momentum each joint keeps, per frame
	var pose_falloff := 0.0      # 0 = a pose pulls the whole tail; 1 = mostly the root
	var shed := true             # sheds grains (tendrils don't, to save points)
	var seed := 0.0
	var points := PackedVector2Array()  # world space, root first
	var prev := PackedVector2Array()
	var heights := PackedFloat32Array()
	# A species pulls the tail towards pose (world space, TAIL_POINTS long)
	# by pose_weight (0..1), and raises it off the ground by raise (0..1).
	# With pose_falloff the pull fades towards the tip, so the root leads
	# and momentum carries the rest, like cracking a whip.
	var pose := PackedVector2Array()
	var pose_weight := 0.0
	var raise := 0.0
	# 0..1, set by a species: the tail's length is length * extend, and at 0
	# it is hidden at its root.
	var extend := 1.0
	# A pulse of its own (pulse_pos < 0 = use the Entity's shared pulse).
	var pulse_pos := -1.0
	var pulse_strength := 0.0
	var line: Line2D
	var strands: Array[Line2D] = []


class Rope:
	var start := Vector2.ZERO    # wedge/narrow: body space, at the back
	var end := Vector2.ZERO      # wedge/narrow: body space, at the neck
	var phase := 0.0
	var twist := 2.0             # times it winds across the bundle
	var amp := 0.5               # how far it winds, as a fraction of the width there
	var a0 := 0.0                # round: start angle
	var span := 2.0              # round: angle it coils through
	var r0 := 0.3                # round: start and end radius, fractions
	var r1 := 0.9
	var line: Line2D


func _leg_layout() -> Array:
	var legs := []
	for i in 3:
		var x := lerpf(-0.3, 0.25, (i + 0.5) / 3.0)
		var angle := lerpf(155.0, 30.0, i / 2.0)
		for side in [-1.0, 1.0]:
			var tripod := 0.5 * ((i + (0 if side < 0.0 else 1)) % 2)
			legs.append({"x": x, "side": side, "angle": angle,
					"walk": tripod + (2 - i) * 0.04, "run": tripod})
	return legs


func _tail_layout() -> Array:
	return []


func _animate(_delta: float) -> void:
	pass


# --- Lifecycle 

func _ready() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white_tex = ImageTexture.create_from_image(img)
	_taper = _curve([Vector2(0.0, 1.0), Vector2(0.25, 0.66), Vector2(0.44, 0.78),
			Vector2(0.62, 0.55), Vector2(1.0, 0.1)])
	# Legs ending in paws stay thick to the foot instead of tapering away.
	_paw_taper = _curve([Vector2(0.0, 1.0), Vector2(0.3, 0.72), Vector2(0.55, 0.62),
			Vector2(0.8, 0.55), Vector2(1.0, 0.6)])
	_rope_taper = _curve([Vector2(0.0, 0.5), Vector2(0.3, 1.0), Vector2(0.75, 0.85), Vector2(1.0, 0.35)])
	_tail_taper = _curve([Vector2(0.0, 1.0), Vector2(0.6, 0.65), Vector2(1.0, 0.05)])
	_last_rotation = global_rotation

	_limb_layer = Node2D.new()
	_limb_layer.top_level = true  # leg points are in world space
	_limb_layer.z_index = -1      # legs under the body
	add_child(_limb_layer)
	_shadow_layer = Node2D.new()  # first child, so drawn under the legs
	_shadow_layer.draw.connect(_draw_shadows)
	_limb_layer.add_child(_shadow_layer)
	_tail_specs = _tail_layout()
	_build_limbs()
	_claw_layer = Node2D.new()  # over the legs
	_claw_layer.draw.connect(_draw_claws)
	_limb_layer.add_child(_claw_layer)
	_build_body()
	_build_head()
	_tail_layer = Node2D.new()
	_tail_layer.top_level = true
	_tail_layer.z_index = -1
	add_child(_tail_layer)
	_build_tails()
	_grains = _make_particles(700, false)
	_death = _make_particles(death_grains, true)


## Every physics frame, from the Entity.
func update_motion(new_velocity: Vector2, _dt: float) -> void:
	velocity = new_velocity


func die() -> void:
	if dead:
		return
	var m: ShaderMaterial = _death.process_material
	_set_point_params(m)
	m.set_shader_parameter("burst_origin", global_position)
	m.set_shader_parameter("body_tip", to_global(Vector2(body_length * 0.5, 0.0)))
	m.set_shader_parameter("body_back_l", to_global(Vector2(-body_length * 0.5, -body_width * 0.5)))
	m.set_shader_parameter("body_back_r", to_global(Vector2(-body_length * 0.5, body_width * 0.5)))
	dead = true
	flash = 0.0
	velocity = Vector2.ZERO
	_grains.emitting = false
	_limb_layer.visible = false
	_tail_layer.visible = false
	_death.restart()
	_death_time = 0.0
	# The burst has to outlive the Entity, which may be freed at once (the
	# Expedition swaps it for a Carcass). Its grains are in world space, so
	# moving it up the tree doesn't move them.
	var world := _world_parent()
	if world != null:
		_death.reparent(world)
		get_tree().create_timer(scatter_time + 0.5).timeout.connect(_death.queue_free)


# The node the Entity lives in (where dead parts are left behind).
func _world_parent() -> Node:
	var entity := get_parent()
	return entity.get_parent() if entity != null and entity.get_parent() != null else entity


func _process(delta: float) -> void:
	# The animation clock slows almost to a stop while the legs are folded,
	# so a resting Entity is still.
	_time += delta * (1.0 - 0.9 * _retract)
	flash = move_toward(flash, 0.0, delta * 4.0)
	if dead:
		# The body breaks up into the burst almost at once. The one-shot
		# particle system ends by itself once the last grain fades.
		_death_time += delta
		if _death_time < BODY_BREAK_TIME + delta:
			_body_layer.modulate.a = maxf(1.0 - _death_time / BODY_BREAK_TIME, 0.0)
			queue_redraw()
		return
	intensity = move_toward(intensity, 1.0 if alarm else 0.2, delta * 2.5)
	flow_phase += delta * lerpf(idle_flow, hunt_flow, intensity) * (1.0 - 0.9 * _retract)
	_update_feet(delta)
	_animate(delta)
	_simulate_limbs()
	_simulate_tails(delta)
	var leg_taper := _paw_taper if paw_size > 0.0 else _taper
	for limb in _limbs:
		# A leg thins as it draws in, and is hidden once fully in.
		var shown := limb.extend > 0.02
		_show_chain(limb.line, limb.strands, shown, limb.width * lerpf(0.35, 1.0, minf(limb.extend * 1.5, 1.0)))
		if not shown:
			continue
		var drawn := _leg_path(limb)
		var offset := drawn.size() - limb.points.size()
		var joints := PackedFloat32Array([_fraction_at(drawn, offset + _knee_index)])
		if _ankle_index < limb.points.size() - 1:
			joints.append(_fraction_at(drawn, offset + _ankle_index))
		_update_braid(drawn, limb.line, limb.strands, limb.line.width, leg_taper, joints, limb.seed)
	for tail in _tails:
		var shown := tail.extend > 0.02
		_show_chain(tail.line, tail.strands, shown, tail.width)
		if shown:
			_update_braid(tail.points, tail.line, tail.strands, tail.width, _tail_taper, PackedFloat32Array(),
					tail.seed, tail.pulse_pos, tail.pulse_strength)
	_update_body()
	_shadow_layer.queue_redraw()
	_claw_layer.queue_redraw()
	var m: ShaderMaterial = _grains.process_material
	_set_point_params(m)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("agitation", maxf(flash, kick))
	_grains.amount_ratio = lerpf(0.35, 1.0, maxf(maxf(intensity, flash), kick)) * (1.0 - 0.85 * _retract)
	queue_redraw()


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	return c


# --- Body 

## Half the body's width at x (body space). The body runs from about
## -body_length / 2 to +body_length / 2.
func _half_width_at(x: float) -> float:
	var half_len := body_length * 0.5
	if body_shape == BodyShape.WEDGE:
		return body_width * 0.5 * clampf((body_length * 0.6 - x) / body_length, 0.0, 1.0)
	if body_shape == BodyShape.NARROW:
		var u := clampf(x / half_len, -1.0, 1.0)
		# An ellipse, a little fuller at the shoulders than the hips.
		return body_width * 0.5 * sqrt(1.0 - u * u) * (1.0 + 0.12 * u)
	if body_shape == BodyShape.NONE:
		return body_width * 0.5
	var r := minf(body_length, body_width) * 0.5
	return sqrt(maxf(r * r - x * x, 0.0))


func _outline() -> PackedVector2Array:
	if body_shape == BodyShape.NONE:
		var out := PackedVector2Array()
		var c := Vector2(body_length * neck_position + placeholder_head_size.x * 0.4, 0.0)
		for k in 12:
			out.append(c + Vector2.from_angle(TAU * k / 12.0) * placeholder_head_size * Vector2(0.6, 0.6))
		return out
	if body_shape == BodyShape.WEDGE:
		return PackedVector2Array([Vector2(body_length * 0.6, 0.0), Vector2(-body_length * 0.4, body_width * 0.5),
				Vector2(-body_length * 0.26, 0.0), Vector2(-body_length * 0.4, -body_width * 0.5)])
	var out := PackedVector2Array()
	for k in 20:
		var x := body_length * 0.5 * cos(TAU * k / 20.0)
		var side := 1.0 if k < 10 else -1.0
		out.append(Vector2(x, side * _half_width_at(x)))
	return out


## Body space to world space, following the waddle and the spine flex.
func _body_to_world(p: Vector2) -> Vector2:
	return to_global((p * Vector2(_flex, 1.0)).rotated(_waddle))


func _draw() -> void:
	var core := body_color.lerp(Color.WHITE, flash * 0.5)
	if dead:
		core.a = 1.0 - _death_time / BODY_BREAK_TIME
		if core.a <= 0.0:
			return
	if body_shape == BodyShape.NONE:
		if knot_radius > 0.0:
			draw_set_transform(Vector2.ZERO, _waddle, Vector2.ONE * (1.0 + body_swell))
			draw_circle(Vector2(body_length * knot_x, 0.0), knot_radius * 0.8, core)
		return
	var s := 1.0 + body_swell
	draw_set_transform(Vector2.ZERO, _waddle, Vector2(0.8 * _flex * s, 0.75 * s))
	draw_colored_polygon(_outline(), core)


func _build_body() -> void:
	_body_layer = Node2D.new()  # body space; drawn over the legs
	add_child(_body_layer)
	var neck := Vector2(body_length * neck_position, 0.0)
	var r := minf(body_length, body_width) * 0.5
	if body_shape == BodyShape.NONE:
		if knot_radius <= 0.0:
			return
		r = knot_radius
	for i in body_strands:
		var rope := Rope.new()
		var f := float(i) / maxf(body_strands - 1, 1.0)
		rope.phase = randf() * TAU
		rope.twist = randf_range(1.0, 2.0)
		rope.amp = randf_range(0.3, 0.6)
		var length := body_length * 0.8
		var width := minf(body_width, body_length) * randf_range(0.09, 0.14)
		if body_shape == BodyShape.NONE:
			width = knot_radius * randf_range(0.4, 0.55)
		if body_shape == BodyShape.ROUND or body_shape == BodyShape.NONE:
			# Ropes coil round the centre, some inner, some outer.
			rope.a0 = randf() * TAU
			rope.span = randf_range(1.6, 3.2) * (1.0 if randf() < 0.5 else -1.0)
			rope.r0 = randf_range(0.1, 0.5)
			rope.r1 = randf_range(0.6, 0.95)
			length = r * absf(rope.span) * 0.7
		else:
			# Ropes start spread across the back, some trailing off it, and
			# gather into the neck under the head.
			rope.start = Vector2(-body_length * 0.5 * randf_range(0.75, rope_trail),
					lerpf(-1.0, 1.0, f) * body_width * 0.42)
			rope.end = neck + Vector2(randf_range(2.0, 10.0), randf_range(-0.04, 0.04) * body_width)
		rope.line = _make_line(rope.phase * 10.0, length, width, _rope_taper, true)
		_ropes.append(rope)
	# Add in random order, so the weave isn't layered side to side.
	var order := _ropes.duplicate()
	order.shuffle()
	for rope in order:
		_body_layer.add_child(rope.line)


func _update_body() -> void:
	_body_layer.rotation = _waddle
	_body_layer.scale = Vector2(_flex, 1.0) * (1.0 + body_swell)
	var wind_speed := lerpf(0.6, 1.6, intensity)
	var r := minf(body_length, body_width) * 0.5
	var centre := Vector2.ZERO
	if body_shape == BodyShape.NONE:
		r = knot_radius
		centre = Vector2(body_length * knot_x, 0.0)
	for rope in _ropes:
		var pts := PackedVector2Array()
		pts.resize(ROPE_POINTS)
		for k in ROPE_POINTS:
			var t := float(k) / (ROPE_POINTS - 1)
			if body_shape == BodyShape.ROUND or body_shape == BodyShape.NONE:
				var a := rope.a0 + rope.span * t + _time * 0.15 * signf(rope.span)
				var rad := lerpf(rope.r0, rope.r1, t) * r
				rad *= 1.0 + 0.06 * sin(t * rope.twist * TAU + rope.phase + _time * wind_speed)
				pts[k] = centre + Vector2.from_angle(a) * rad
			else:
				var x := lerpf(rope.start.x, rope.end.x, t)
				var half := _half_width_at(x) * 0.9
				if x < -body_length * 0.5:
					half = body_width * 0.3  
				var y := lerpf(rope.start.y, rope.end.y, pow(t, 0.8))
				y += sin(t * rope.twist * TAU + rope.phase + _time * wind_speed) * rope.amp * half * cos(t * PI * 0.5)
				pts[k] = Vector2(x, clampf(y, -half, half))
		rope.line.points = pts
		_set_line_params(rope.line)
	var hm: ShaderMaterial = _head.material
	hm.set_shader_parameter("flash", flash)
	_head.position = Vector2(body_length * neck_position + head_lunge * placeholder_head_size.x * 0.5, 0.0)
	_head.rotation = sin(_time * 1.7) * lerpf(0.12, 0.05, intensity) * (1.0 - head_lunge)


func _build_head() -> void:
	_head = Sprite2D.new()
	_head.texture = head_texture if head_texture else _placeholder_head()
	_head.offset = Vector2(_head.texture.get_width() * 0.5, 0.0)  # left-middle is the neck
	_head.position = Vector2(body_length * neck_position, 0.0)
	_head.scale = Vector2.ONE * head_scale
	var shader := Shader.new()
	shader.code = HEAD_FLASH_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_head.material = mat
	_head.visible = has_head
	_body_layer.add_child(_head)  # over the ropes


# Stand-in until there's art: a small beaked head with pale teeth.
func _placeholder_head() -> ImageTexture:
	var w := int(placeholder_head_size.x)
	var h := int(placeholder_head_size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w
			var v := ((y + 0.5) / h - 0.5) * 2.0
			var half := 0.95 * pow(1.0 - u, 0.6)
			if absf(v) > half:
				continue
			var shade := 0.14 + 0.2 * (1.0 - absf(v) / half)
			var c := Color(shade, shade, shade)
			if u > 0.35 and u < 0.9 and absf(v) < 0.14 * (1.0 - u) + 0.05:
				c = Color(0.85, 0.85, 0.85) if x % 3 != 0 else Color(0.03, 0.03, 0.03)
			if Vector2((u - 0.22) * 2.0, absf(v) - 0.45).length() < 0.13:
				c = eye_color
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# --- Legs: layout and gait 

func _build_limbs() -> void:
	var layout := _leg_layout()
	var chains := layout.size()
	for spec in _tail_specs:
		if spec.get("shed", true):
			chains += 1
	limb_points = clampi(limb_points, 3, MAX_POINTS / maxi(chains, 1))
	for spec in layout:
		var limb := Limb.new()
		var side: float = spec["side"]
		var x: float = spec["x"] * body_length
		limb.anchor = Vector2(x, side * _half_width_at(x) * hip_inset)
		if spec.has("y"):
			limb.anchor.y = spec["y"] * body_width
		if spec.has("root"):
			limb.has_root = true
			limb.root = spec["root"] * Vector2(body_length, body_width)
		limb.width = spec.get("width", limb_width)
		limb.rest_angle = side * deg_to_rad(spec["angle"])
		limb.side = side
		limb.walk_phase = spec["walk"]
		limb.run_phase = spec["run"]
		# Knees lean towards whichever side of the leg points further out
		# from the body, fixed per leg so it never flips mid-stride.
		var rest_dir := Vector2.from_angle(limb.rest_angle)
		limb.lean = 1.0 if rest_dir.orthogonal().y * side > 0.0 else -1.0
		limb.seed = randf() * 100.0
		var root := to_global(limb.anchor)
		var dir := Vector2.from_angle(global_rotation + limb.rest_angle)
		for k in limb_points:
			var p := root + dir * limb_length * rest_reach * float(k) / (limb_points - 1)
			limb.points.append(p)
			limb.prev.append(p)
			limb.heights.append(0.0)
		limb.foot = limb.points[limb_points - 1]
		limb.claw_angle = global_rotation
		var leg_taper := _paw_taper if paw_size > 0.0 else _taper
		limb.line = _make_line(limb.seed, limb_length, limb.width, leg_taper, false)
		_limb_layer.add_child(limb.line)
		for j in 2:
			var strand := _make_line(limb.seed + j * 17.0, limb_length, limb.width * 0.42, leg_taper, true)
			_limb_layer.add_child(strand)
			limb.strands.append(strand)
		_limbs.append(limb)


func _hip(limb: Limb) -> Vector2:
	return _body_to_world(limb.anchor)


func _hip_z() -> float:
	# Folded legs let the body settle towards the ground.
	return limb_length * hip_height * (1.0 - 0.5 * _retract) * lerpf(0.08, 1.0, body_lift) \
			* (1.0 - 0.5 * crouch) + air_height


# Where a foot sits at rest, plus an optional lead in world space.
func _rest_foot(limb: Limb, lead: Vector2) -> Vector2:
	var reach := limb_length * lerpf(rest_reach, retract_reach, maxf(_retract, leg_tuck)) * limb.reach_jitter
	var angle := global_rotation + _waddle + limb.rest_angle + limb.angle_jitter * limb.side
	return _hip(limb) + Vector2.from_angle(angle) * reach + lead


func _update_feet(delta: float) -> void:
	var speed := velocity.length()
	var turn := absf(angle_difference(_last_rotation, global_rotation)) / maxf(delta, 0.0001)
	_last_rotation = global_rotation
	var blend_target := intensity
	if gallop_at > 0.0:
		blend_target = smoothstep(gallop_from, gallop_at, speed)
	gait_blend = move_toward(gait_blend, blend_target, delta * 3.0)
	var stride_px := limb_length * lerpf(stride, run_stride if run_stride > 0.0 else stride, gait_blend)
	var duty := lerpf(duty_walk, duty_run, gait_blend)
	# The clock runs on distance: one cycle per stride. Turning on the spot
	# counts too, so it shuffles round rather than pivoting on planted feet.
	var rate := (speed + turn * limb_length * 0.5) / stride_px
	var walking := rate > 0.2
	if walking:
		gait_phase += rate * delta
		_still_time = 0.0
	else:
		_still_time += delta
	var fold := retract_when_still and _still_time > retract_delay
	_retract = move_toward(_retract, 1.0 if fold else 0.0, delta * (2.5 if fold else 6.0))
	var target_waddle := sin(gait_phase * TAU) * deg_to_rad(waddle) if walking else 0.0
	_waddle = lerpf(_waddle, target_waddle, clampf(12.0 * delta, 0.0, 1.0))
	# The spine stretches and gathers once per stride at a run.
	var target_flex := 1.0 + spine_flex * sin(gait_phase * TAU) * gait_blend if walking else 1.0
	_flex = lerpf(_flex, target_flex, clampf(15.0 * delta, 0.0, 1.0))
	# A foot lands ahead of its rest pose by half the ground the body covers
	# while it is planted, so it passes under the rest pose mid-stance.
	var move_dir := velocity / speed if speed > 1.0 else Vector2.ZERO
	var lead := move_dir * stride_px * duty * 0.5
	var feet_up := 0  # legs currently stepping
	for limb in _limbs:
		if limb.swing_t >= 0.0:
			feet_up += 1
	for limb in _limbs:
		if limb.extend < 0.999:
			# Growing out (or drawing in): the foot travels from the leg's root
			# to its rest spot, raised in the middle, and takes no steps.
			var start := _body_to_world(limb.root) if limb.has_root else _hip(limb)
			var e := smoothstep(0.0, 1.0, limb.extend)
			limb.foot = start.lerp(_rest_foot(limb, Vector2.ZERO), e)
			limb.lift = sin(limb.extend * PI) * 0.9
			limb.swing_t = -1.0
			# Not yet stepped this cycle: once walking, it takes this cycle's
			# step on time instead of waiting a whole cycle and dragging.
			limb.cycle = floori(gait_phase + lerpf(limb.walk_phase, limb.run_phase, gait_blend)) - 1
			continue
		if airborne:
			# In the air: no steps; each foot holds its pose near the body.
			limb.foot = limb.foot.lerp(_rest_foot(limb, foot_lead), clampf(25.0 * delta, 0.0, 1.0))
			limb.lift = 0.5
			limb.swing_t = -1.0
			# Not yet stepped this cycle: once walking, it takes this cycle's
			# step on time instead of waiting a whole cycle and dragging.
			limb.cycle = floori(gait_phase + lerpf(limb.walk_phase, limb.run_phase, gait_blend)) - 1
			continue
		if limb.swing_t >= 0.0:
			_advance_swing(limb, delta, lead)
			continue
		limb.lift = _retract * 0.7
		var p := gait_phase + lerpf(limb.walk_phase, limb.run_phase, gait_blend)
		var cycle := floori(p)
		if walking:
			# Each leg steps once per cycle, in the last (1 - duty) of it, and
			# lands a little early. It waits if too many legs are already up;
			# a leg that waited past its window steps as soon as it can,
			# rather than skipping a step.
			var due := cycle != limb.cycle and (p - cycle >= duty or cycle - limb.cycle >= 2)
			if due and feet_up < max_airborne:
				limb.cycle = cycle
				_start_swing(limb, 0.85 * (1.0 - duty) / rate)
				feet_up += 1
		elif _retract > 0.01:
			# Folding: feet draw in under the body and lift off the ground.
			limb.foot = limb.foot.lerp(_rest_foot(limb, Vector2.ZERO), 1.0 - exp(-8.0 * delta))
			limb.cycle = cycle
		elif limb.foot.distance_to(_rest_foot(limb, Vector2.ZERO)) > limb_length * settle_distance \
				and feet_up < maxi(_limbs.size() / 2, 1):
			# Standing: tidy a stray foot, half the legs at a time.
			limb.cycle = cycle
			_start_swing(limb, 0.16)
			feet_up += 1
	# Toes point the way the body faces, splayed a little outwards, and
	# turn smoothly with it rather than following the jittery leg end.
	for limb in _limbs:
		var toe_target := global_rotation + _waddle + limb.side * deg_to_rad(12.0)
		limb.claw_angle = lerp_angle(limb.claw_angle, toe_target, clampf(10.0 * delta, 0.0, 1.0))


func _start_swing(limb: Limb, duration: float) -> void:
	var scatter := deg_to_rad(foot_scatter)
	limb.angle_jitter = randf_range(-scatter, scatter)
	limb.reach_jitter = randf_range(0.95, 1.04)
	limb.swing_time = clampf(duration, 0.05, 0.35)
	limb.swing_from = limb.foot
	limb.swing_t = 0.0


func _advance_swing(limb: Limb, delta: float, lead: Vector2) -> void:
	limb.swing_t = minf(limb.swing_t + delta / limb.swing_time, 1.0)
	var s := limb.swing_t
	# Fast out, soft landing. The target tracks the body, so the foot lands
	# where the body now is.
	var e := 1.0 - pow(1.0 - s, 2.2)
	limb.foot = limb.swing_from.lerp(_rest_foot(limb, lead), e)
	if swing_reach > 0.0 and velocity.length() > 1.0:
		limb.foot += velocity.normalized() * swing_reach * limb_length * sin(s * PI) * gait_blend
	limb.lift = maxf(sin(s * PI), _retract * 0.7)
	if s >= 1.0:
		limb.swing_t = -1.0
		limb.lift = _retract * 0.7


# --- Legs: shape --------------------------------------------------------

func _simulate_limbs() -> void:
	var n := limb_points
	var upper := limb_length * upper_leg
	var lower := limb_length * lower_leg
	var ankle_len := limb_length * ankle_leg
	var total := upper + lower + ankle_len
	# The chain points that sit on the knee and the ankle.
	var k1 := clampi(roundi((n - 1) * upper / total), 1, n - 2)
	var k2 := n - 1
	if ankle_len > 0.0:
		k2 = clampi(roundi((n - 1) * (upper + lower) / total), k1 + 1, n - 2)
	_knee_index = k1
	_ankle_index = k2
	var shimmer := lerpf(1.0, 2.5, intensity)
	var shimmer_speed := lerpf(4.0, 10.0, intensity)
	var hip_z := _hip_z()
	var tilt := deg_to_rad(knee_tilt)
	var ankle_up := deg_to_rad(ankle_angle)
	for limb in _limbs:
		var hip := _hip(limb)
		var foot := limb.foot
		var foot_z := limb_length * step_height * limb.lift + air_height
		var hip3 := Vector3(hip.x, hip.y, hip_z)
		var foot3 := Vector3(foot.x, foot.y, foot_z)
		# The ankle bone rises from the foot back towards the hip, then the
		# thigh and shin reach it by two-bone IK.
		var ankle3 := foot3
		if ankle_len > 0.0:
			var back := hip - foot
			back = back.normalized() if back.length() > 0.01 else Vector2.from_angle(global_rotation + PI)
			ankle3 = foot3 + Vector3(back.x * cos(ankle_up), back.y * cos(ankle_up), sin(ankle_up)) * ankle_len
		var knee3 := _solve_knee_3d(hip3, ankle3, upper, lower, limb.lean, tilt)
		var knee := Vector2(knee3.x, knee3.y)
		var ankle := Vector2(ankle3.x, ankle3.y)
		var pts := limb.points
		var prev := limb.prev
		var heights := limb.heights
		heights[0] = hip_z
		for i in range(1, n):
			var target: Vector2
			var along: float  # 0..1 within this bone
			var bone_dir: Vector2
			if i <= k1:
				along = float(i) / k1
				target = hip.lerp(knee, along)
				bone_dir = (knee - hip).normalized()
				heights[i] = lerpf(hip_z, knee3.z, along)
			elif i <= k2:
				along = float(i - k1) / (k2 - k1)
				target = knee.lerp(ankle, along)
				bone_dir = (ankle - knee).normalized()
				heights[i] = lerpf(knee3.z, ankle3.z, along)
			else:
				along = float(i - k2) / (n - 1 - k2)
				target = ankle.lerp(foot, along)
				bone_dir = (foot - ankle).normalized()
				heights[i] = lerpf(ankle3.z, foot_z, along)
			# The sand shivers between the joints but not at them.
			var t := float(i) / (n - 1)
			var wave := sin(_time * shimmer_speed - t * 6.0 + limb.seed) * shimmer * sin(along * PI)
			target += bone_dir.orthogonal() * wave
			# Spring towards the jointed pose, keeping a little lag and whip.
			var p := pts[i]
			var v := (p - prev[i]) * 0.4
			prev[i] = p
			pts[i] = p + v + (target - p) * 0.85
		pts[0] = hip
		pts[k1] = pts[k1].lerp(knee, 0.8)  # keep the joints crisp
		pts[k2] = pts[k2].lerp(ankle, 0.8)
		pts[n - 1] = foot
		limb.points = pts
		limb.prev = prev
		limb.heights = heights


# Two-bone IK in 3D, where z is height above the ground. 
func _solve_knee_3d(hip: Vector3, foot: Vector3, upper: float, lower: float, lean: float, tilt: float) -> Vector3:
	var to_foot := foot - hip
	var dist := to_foot.length()
	var u := to_foot / dist if dist > 0.01 else Vector3.RIGHT
	var d := clampf(dist, absf(upper - lower) + 0.01, upper + lower - 0.01)
	var along := (upper * upper - lower * lower + d * d) / (2.0 * d)
	var rise := sqrt(maxf(upper * upper - along * along, 0.0))
	var up := Vector3(0.0, 0.0, 1.0)
	var up_perp := (up - u * up.dot(u)).normalized()
	var level := Vector2(u.x, u.y)
	if level.length() < 0.001:
		level = Vector2.RIGHT
	var side_2d := level.normalized().orthogonal() * lean
	var out := Vector3(side_2d.x, side_2d.y, 0.0)
	var bend := (up_perp * cos(tilt) + out * sin(tilt)).normalized()
	return hip + u * along + bend * rise


# --- Tails 

func _build_tails() -> void:
	for spec in _tail_specs:
		var tail := Tail.new()
		tail.root = Vector2(spec["x"] * body_length, spec["y"] * body_width)
		tail.length = spec["length"]
		tail.width = spec["width"]
		tail.rest_angle = deg_to_rad(spec.get("angle", 180.0))
		tail.sway = spec.get("sway", 0.35)
		tail.sway_speed = spec.get("speed", 1.6)
		tail.waves = spec.get("waves", 0.6)
		tail.floaty = spec.get("floaty", 0.0)
		tail.stiffness = spec.get("stiffness", 0.12)
		tail.damping = spec.get("damping", 0.94)
		tail.run_sway = spec.get("run_sway", tail.sway)
		tail.run_speed = spec.get("run_speed", tail.sway_speed)
		tail.run_stiffness = spec.get("run_stiffness", tail.stiffness)
		tail.thrashes = spec.get("thrash", false)
		tail.phase = randf() * TAU
		tail.shed = spec.get("shed", true)
		tail.seed = randf() * 100.0
		var root := to_global(tail.root)
		var back := Vector2.from_angle(global_rotation + tail.rest_angle)
		for k in TAIL_POINTS:
			var p := root + back * tail.length * float(k) / (TAIL_POINTS - 1)
			tail.points.append(p)
			tail.prev.append(p)
			tail.heights.append(0.0)
			tail.pose.append(p)
		tail.line = _make_line(tail.seed, tail.length, tail.width, _tail_taper, false)
		_tail_layer.add_child(tail.line)
		for j in 2:
			var strand := _make_line(tail.seed + j * 17.0, tail.length, tail.width * 0.42, _tail_taper, true)
			_tail_layer.add_child(strand)
			tail.strands.append(strand)
		_tails.append(tail)


func _simulate_tails(delta: float) -> void:
	var hip_z := _hip_z()
	var raised := false
	for tail in _tails:
		var n := TAIL_POINTS
		var seg := tail.length * maxf(tail.extend, 0.001) / (n - 1)
		var root := _body_to_world(tail.root)
		var base_angle := global_rotation + _waddle + tail.rest_angle
		var pts := tail.points
		var prev := tail.prev
		var heights := tail.heights
		var drift := sin(_time * 0.5 + tail.seed * 1.7) * 0.4 * tail.floaty
		# The wave grows and quickens towards a run, and much more again when
		# thrashing.
		var th := thrash if tail.thrashes else 0.0
		var amp := lerpf(tail.sway, tail.run_sway, gait_blend) * (1.0 + 0.6 * th)
		var stiffness := lerpf(tail.stiffness, tail.run_stiffness, gait_blend) * (1.0 + 1.5 * th)
		tail.phase += delta * lerpf(tail.sway_speed, tail.run_speed, gait_blend) * (1.0 + 2.5 * th)
		# 1. Momentum: every joint carries on the way it was moving in the
		# world, losing a little each frame.
		for i in range(1, n):
			var t := float(i) / (n - 1)
			var w := tail.pose_weight * lerpf(1.0, pow(1.0 - t, 2.0), tail.pose_falloff)
			var v := (pts[i] - prev[i]) * lerpf(tail.damping, 0.5, w)
			prev[i] = pts[i]
			pts[i] += v
		pts[0] = root
		# 2. Shape: the first segment eases towards the body's rest direction;
		# every later joint eases towards an angle relative to the segment
		# before it.
		var heading_prev := 0.0
		for i in range(1, n):
			var t := float(i) / (n - 1)
			var heading := drift + sin(tail.phase - t * tail.waves * TAU + tail.seed) \
					* amp * (0.35 + 0.65 * t)
			if th > 0.0:
				# Thrashing: fast, uneven lashing on top of the wave.
				heading += (sin(_time * 11.0 + tail.seed * 3.0 - t * 5.0) * 0.6
						+ sin(_time * 17.3 + tail.seed - t * 8.0) * 0.4) * 0.9 * th * t
			var dir: Vector2
			var stiff: float
			if i == 1:
				dir = Vector2.from_angle(base_angle + heading)
				stiff = minf(stiffness * 3.0, 0.9)
			else:
				var before := pts[i - 1] - pts[i - 2]
				dir = before.normalized().rotated(heading - heading_prev) if before.length() > 0.01 \
						else Vector2.from_angle(base_angle)
				stiff = stiffness * lerpf(1.0, 0.35, t)  # floppier towards the tip
			heading_prev = heading
			pts[i] = pts[i].lerp(pts[i - 1] + dir * seg, stiff)
		# 3. A species pose pulls on top (with falloff, mostly at the root).
		if tail.pose_weight > 0.0:
			for i in range(1, n):
				var t := float(i) / (n - 1)
				var w := tail.pose_weight * lerpf(1.0, pow(1.0 - t, 2.0), tail.pose_falloff)
				pts[i] = pts[i].lerp(tail.pose[i], w * 0.8)
		for i in range(1, n):
			var t := float(i) / (n - 1)
			heights[i] = hip_z * (1.0 - 0.6 * t) + tail.raise * tail.length * 0.45 * sin(t * PI)
		heights[0] = hip_z
		# 4. Keep every segment its length.
		for _iter in 6:
			pts[0] = root
			for i in range(n - 1):
				var d := pts[i + 1] - pts[i]
				var dist := d.length()
				if dist < 0.001:
					continue
				var corr := d * ((dist - seg) / dist)
				if i == 0:
					pts[i + 1] -= corr
				else:
					pts[i] += corr * 0.5
					pts[i + 1] -= corr * 0.5
		pts[0] = root
		for i in range(1, n):
			var d := pts[i] - pts[i - 1]
			if d.length() > seg * 1.05:
				pts[i] = pts[i - 1] + d.normalized() * seg * 1.05
		tail.points = pts
		tail.prev = prev
		tail.heights = heights
		raised = raised or tail.raise > 0.3
	# A raised tail draws over the body; a trailing one under it.
	_tail_layer.z_index = 1 if raised else -1


# --- Drawing helpers 

# A tapered line with sand_limb.gdshader: flowing grains, or (rope = true)
# a solid rounded rope with spiralling ridges.
func _make_line(seed: float, length_px: float, width: float, taper: Curve, rope: bool) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.width_curve = taper
	line.texture = _white_tex
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH  # UV.x runs root -> tip
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	var mat := ShaderMaterial.new()
	mat.shader = LIMB_SHADER
	mat.set_shader_parameter("seed", seed)
	mat.set_shader_parameter("limb_px", length_px)
	mat.set_shader_parameter("limb_width_px", width)
	mat.set_shader_parameter("rope", rope)
	line.material = mat
	return line


func _show_chain(line: Line2D, strands: Array[Line2D], shown: bool, width: float) -> void:
	line.visible = shown
	line.width = width
	for strand in strands:
		strand.visible = shown
		strand.width = width * 0.42


# own_pulse_pos >= 0 gives this line its own pulse instead of the shared one.
func _set_line_params(line: Line2D, own_pulse_pos := -1.0, own_pulse_strength := 0.0) -> void:
	var m: ShaderMaterial = line.material
	m.set_shader_parameter("flow_phase", flow_phase)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("grain_color", grain_color.lerp(Color.WHITE, flash))
	m.set_shader_parameter("highlight_color", ridge_color.lerp(Color.WHITE, flash))
	var own := own_pulse_pos >= 0.0
	m.set_shader_parameter("pulse_pos", own_pulse_pos if own else pulse_pos)
	m.set_shader_parameter("pulse_strength", own_pulse_strength if own else pulse_strength)

func _update_braid(points: PackedVector2Array, line: Line2D, strands: Array[Line2D], width: float,
		taper: Curve, joints: PackedFloat32Array, seed: float, own_pulse_pos := -1.0,
		own_pulse_strength := 0.0) -> void:
	var core := _smooth(points)
	line.points = core
	_set_line_params(line, own_pulse_pos, own_pulse_strength)
	var count := core.size()
	var along := PackedFloat32Array()
	along.resize(count)
	for i in range(1, count):
		along[i] = along[i - 1] + core[i].distance_to(core[i - 1])
	var total := maxf(along[count - 1], 1.0)
	for j in strands.size():
		var pts := PackedVector2Array()
		pts.resize(count)
		for i in count:
			var s := along[i] / total
			var tangent := (core[mini(i + 1, count - 1)] - core[maxi(i - 1, 0)]).normalized()
			var pinch := 1.0
			for j_at in joints:
				pinch = minf(pinch, lerpf(0.2, 1.0, smoothstep(0.0, 0.12, absf(s - j_at))))
			var amp := width * 0.42 * taper.sample(s) * pinch
			# Opposite strands (j * PI) wind round each other; the phase
			# drifts with the flow, so the braid slowly twists.
			var wind := sin(along[i] / STRAND_TURN_PX * TAU + j * PI + seed - flow_phase * 2.0)
			pts[i] = core[i] + tangent.orthogonal() * wind * amp
		strands[j].points = pts
		_set_line_params(strands[j], own_pulse_pos, own_pulse_strength)


func _leg_path(limb: Limb) -> PackedVector2Array:
	if not limb.has_root:
		return limb.points
	var root := _body_to_world(limb.root)
	var ctrl := _body_to_world(Vector2(limb.root.x, limb.anchor.y))
	var hip := limb.points[0]
	var out := PackedVector2Array()
	for k in 3:
		var t := k / 3.0
		out.append(root.lerp(ctrl, t).lerp(ctrl.lerp(hip, t), t))
	out.append_array(limb.points)
	return out


# How far along a polyline (0..1, by length) its point `index` sits.
func _fraction_at(points: PackedVector2Array, index: int) -> float:
	var total := 0.0
	var upto := 0.0
	for i in range(1, points.size()):
		var d := points[i].distance_to(points[i - 1])
		total += d
		if i <= index:
			upto += d
	return upto / maxf(total, 0.001)


func _draw_claws() -> void:
	if claw_count <= 0 and paw_size <= 0.0:
		return
	var col := grain_color.lerp(Color.WHITE, flash)
	var hi := ridge_color.lerp(Color.WHITE, flash)
	for limb in _limbs:
		if limb.extend < 0.6:
			continue
		var n := limb.points.size()
		var foot := limb.points[n - 1]
		var dir := Vector2.from_angle(limb.claw_angle)
		var perp := dir.orthogonal()
		var spread := lerpf(0.25, 0.5, limb.lift)
		var toe_w := limb.width * paw_size * 0.36
		var toe_len := limb.width * paw_size * 0.55
		for c in claw_count:
			var f := c - (claw_count - 1) * 0.5
			var d := dir.rotated(f * spread)
			# Toes start just inside the leg's end, so they grow out of it.
			var start := foot - dir * toe_len * 0.25 + perp * f * limb.width * paw_size * 0.12
			var tip_base := start
			if paw_size > 0.0:
				# A toe: a thick rounded stub with a highlight along its top.
				tip_base = start + d * toe_len * (1.0 - absf(f) * 0.15)
				_claw_layer.draw_line(start, tip_base, col, toe_w)
				_claw_layer.draw_circle(tip_base, toe_w * 0.5, col)
				_claw_layer.draw_line(start.lerp(tip_base, 0.15) + d.orthogonal() * toe_w * 0.18,
						tip_base + d.orthogonal() * toe_w * 0.18, hi.darkened(0.2), 1.5)
			# The claw hooks back towards the middle of the foot.
			var w := toe_w * 0.45 if paw_size > 0.0 else limb.width * 0.16
			var length := claw_length * (1.0 - absf(f) * 0.15)
			var p_perp := d.orthogonal()
			var mid := tip_base + d * length * 0.55 + p_perp * f * length * 0.12
			var tip := tip_base + d * length + p_perp * -f * length * 0.1
			_claw_layer.draw_colored_polygon(PackedVector2Array([tip_base + p_perp * w, mid + p_perp * w * 0.6,
					tip, mid - p_perp * w * 0.6, tip_base - p_perp * w]), col)
			_claw_layer.draw_line(tip_base, mid, hi, 1.0)


# Two passes of corner cutting: rounds the knee into a curve, keeps both ends.
func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts
	for _pass in 2:
		var next := PackedVector2Array([out[0]])
		for i in out.size() - 1:
			next.append(out[i].lerp(out[i + 1], 0.25))
			next.append(out[i].lerp(out[i + 1], 0.75))
		next.append(out[out.size() - 1])
		out = next
	return out


func _draw_shadows() -> void:
	# Ground shadows, offset away from the light by height. They separate
	# what is raised from what is on the ground, so a lifting foot reads.
	if shadow_strength <= 0.0:
		return
	var off := Vector2.from_angle(deg_to_rad(light_angle)) * SHADOW_PER_HEIGHT
	var col := Color(0.0, 0.0, 0.0, shadow_strength)
	var hip_z := _hip_z()
	var body := PackedVector2Array()
	for v in _outline():
		body.append(_body_to_world(v * 0.85) + off * hip_z)
	_shadow_layer.draw_colored_polygon(body, col)
	for limb in _limbs:
		if limb.extend > 0.02:
			_draw_chain_shadow(limb.points, limb.heights, off, col, limb.width * 0.45 * limb.extend)
	for tail in _tails:
		if tail.extend > 0.02:
			_draw_chain_shadow(tail.points, tail.heights, off, col, tail.width * 0.45)


func _draw_chain_shadow(points: PackedVector2Array, heights: PackedFloat32Array, off: Vector2,
		col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in points.size():
		pts.append(points[i] + off * heights[i])
	_shadow_layer.draw_polyline(pts, col, width)


# --- Grains 

func _make_particles(amount: int, death: bool) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = amount
	p.local_coords = false  # grains stay where they were shed
	p.texture = _white_tex
	p.visibility_rect = Rect2(-3000.0, -3000.0, 6000.0, 6000.0)
	var m := ShaderMaterial.new()
	m.shader = GRAIN_SHADER
	m.set_shader_parameter("death_burst", death)
	m.set_shader_parameter("grain_color", grain_color)
	m.set_shader_parameter("burst_speed", burst_speed)
	m.set_shader_parameter("scatter_time", scatter_time)
	p.process_material = m
	if death:
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = scatter_time + 0.1
		p.emitting = false
		p.z_index = 1
	else:
		p.lifetime = 1.1
		p.z_index = -1
	add_child(p)
	return p


# Every leg and tail chain, each resampled to limb_points, for the grain
# shader to spawn along.
func _set_point_params(m: ShaderMaterial) -> void:
	var arr := PackedVector2Array()
	arr.resize(MAX_POINTS)
	var k := 0
	for limb in _limbs:
		for p in limb.points:
			arr[k] = p
			k += 1
	var chains := _limbs.size()
	for tail in _tails:
		if not tail.shed:
			continue
		chains += 1
		for i in limb_points:
			var f := float(i) / (limb_points - 1) * (TAIL_POINTS - 1)
			var a := floori(f)
			arr[k] = tail.points[a].lerp(tail.points[mini(a + 1, TAIL_POINTS - 1)], f - a)
			k += 1
	m.set_shader_parameter("points", arr)
	m.set_shader_parameter("limb_count", chains)
	m.set_shader_parameter("points_per_limb", limb_points)
