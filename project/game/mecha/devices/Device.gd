class_name Device
extends StaticBody2D

## Something a mecha puts out from its internal bay (Mecha.use_internal): a
## ward, drone, Seeker, flare or decoy. A device with a sensor_range pings:
## every update_interval s it reports the living mechas, decoys (as mechas)
## and Entities within range to its owner's contacts (source = its kind;
## ContactStore.REVEALS says whether that is a ping or vision), through walls
## and smoke. A mecha with ECM is found only within (1 - sensor_reduction) of
## the range. Devices never report their owner or their owner's decoys. The
## first ping comes after a random part of the interval, so devices don't all
## ping on the same frame; a ping is one pass over the bodies with a distance
## check, no rays.
##
## What each kind adds, from its scene's settings:
##   drone            moves: speed px/s along `heading`, over buildings, and
##                    self-destructs (expire) once it has flown max_distance
##   follows_owner    hovers round its owner (the Seeker; FOLLOW_ANGLE), and
##                    gives a quiet sound there every sound_interval s that
##                    NPCs within sound_range hear; gone when its owner dies
##   reveal_everyone  reports to every mecha, ignoring ECM (the flare)
##   lifetime         gone after this many seconds (flares, decoys)
##   destructible     mechas' shots, blasts and beams destroy it (take_hit,
##                    from the projectiles; Entities never attack devices);
##                    off for flares, which shots pass through
##
## Destroyed, it tells its owner (Mecha.device_destroyed: "WARD DESTROYED"
## for the player); expiring tells no one. It sits on DEVICE_LAYER, which
## shots hit and mechas don't bump into, and is in the "device" group.
##
## For NPC code: Device.find_near(node, point, radius), owner_mecha, kind,
## destroy().

signal destroyed(device)

const DEVICE_LAYER := 13
## A ping's contacts stay live this long (s) past the next ping, so a body
## still in range never flickers to a ghost.
const PING_SLACK := 0.5
## The ring drawn round a device, in G4. World px.
const RING_RADIUS := 34.0
## Where a follower hovers round its owner, in the owner's frame (turned
## with it; 0 rad is the owner's right, PI/2 behind): it drifts about
## FOLLOW_ANGLE, up to FOLLOW_ANGLE_SWAY either side, at FOLLOW_RADIUS give
## or take FOLLOW_RADIUS_SWAY (world px), and eases toward that point at
## FOLLOW_EASE (1/s), so it lags a little behind its owner's moves. It turns
## toward where it is going. FOLLOW_DRIFT sets how fast it wanders.
const FOLLOW_ANGLE := 2.45
const FOLLOW_ANGLE_SWAY := 1.0
const FOLLOW_RADIUS := 150.0
const FOLLOW_RADIUS_SWAY := 45.0
const FOLLOW_EASE := 3.0
const FOLLOW_DRIFT := 0.5
const THEME := preload("res://game/ui/mech_os/MechTheme.tres")

@export var kind := "ward"
@export var destructible := true
@export var reveal_everyone := false
@export var follows_owner := false

var owner_mecha = null
var sensor_range := 1500.0
var update_interval := 2.0
var hp := 2.0
var speed := 0.0
var max_distance := 0.0
var heading := Vector2.ZERO
var travelled := 0.0
## Seconds left (0 = lasts until destroyed).
var lifetime := 0.0
var sound_interval := 0.0
var sound_range := 0.0

var _ping_timer := 0.0
var _sound_timer := 0.0
var _gone := false
# A follower's own clock and phase, so two Seekers don't wander in step.
var _drift_time := 0.0
var _drift_phase := randf() * TAU


## The devices within `radius` of `point` that are still out there. Each
## has owner_mecha (may be freed) and kind.
static func find_near(node: Node, point: Vector2, radius: float) -> Array:
	var found := []
	for device in node.get_tree().get_nodes_in_group("device"):
		if device is Device and not device.is_gone() and device.global_position.distance_to(point) <= radius:
			found.append(device)
	return found


## Every device `mecha` has out.
static func owned_by(mecha: Node) -> Array:
	var found := []
	for device in mecha.get_tree().get_nodes_in_group("device"):
		if device is Device and not device.is_gone() and device.owner_mecha == mecha:
			found.append(device)
	return found


## Takes its numbers from the internal part that put it out.
func setup(owner_ref, part, direction := Vector2.ZERO) -> void:
	owner_mecha = owner_ref
	sensor_range = part.sensor_range
	update_interval = maxf(part.update_interval, 0.1)
	hp = part.device_hp
	heading = direction.normalized()
	speed = part.device_speed if kind == "drone" else 0.0
	max_distance = part.device_max_distance
	lifetime = part.device_lifetime
	sound_interval = part.sound_interval if follows_owner else 0.0
	sound_range = part.sound_range
	_ping_timer = randf() * update_interval
	_sound_timer = randf() * sound_interval


func _ready() -> void:
	add_to_group("device")
	collision_layer = (1 << (DEVICE_LAYER - 1)) if destructible else 0
	collision_mask = 0
	if heading != Vector2.ZERO:
		rotation = heading.angle() + PI * 0.5


func _physics_process(dt: float) -> void:
	if _gone:
		return
	if follows_owner:
		if not is_instance_valid(owner_mecha) or owner_mecha.get("is_dead") == true:
			expire()
			return
		_follow(dt)
	if speed > 0.0:
		var step := heading * speed * dt
		global_position += step
		travelled += step.length()
		if travelled >= max_distance:
			expire()
			return
	if lifetime > 0.0:
		lifetime -= dt
		if lifetime <= 0.0:
			expire()
			return
	if sensor_range > 0.0:
		_ping_timer -= dt
		if _ping_timer <= 0.0:
			_ping_timer = update_interval
			ping()
	if sound_interval > 0.0:
		_sound_timer -= dt
		if _sound_timer <= 0.0:
			_sound_timer = sound_interval
			make_sound()


## Reports what is in range to its owner's contacts now, or to every
## mecha's (reveal_everyone).
func ping() -> void:
	if _gone:
		return
	var ttl := update_interval + PING_SLACK
	if reveal_everyone:
		for mecha in get_tree().get_nodes_in_group("mecha"):
			if mecha.get("contacts") is ContactStore and mecha.get("is_dead") != true:
				_report_to(mecha, ttl)
	elif is_instance_valid(owner_mecha):
		_report_to(owner_mecha, ttl)


## The living mechas (not `viewer`, the owner by default), decoys (not
## viewer's) and Entities within range now; ECM shortens the range unless
## reveal_everyone.
func in_range(viewer = null) -> Array:
	if viewer == null:
		viewer = owner_mecha
	var found := []
	for group in ["mecha", "decoy", "entity"]:
		for body in get_tree().get_nodes_in_group(group):
			if body == viewer or not (body is Node2D) or body.get("is_dead") == true:
				continue
			if body is Device and (body.owner_mecha == viewer or body.is_gone()):
				continue
			var reach := sensor_range
			if not reveal_everyone:
				var reduction = body.get("sensor_reduction")
				reach *= 1.0 - clampf(float(reduction) if reduction != null else 0.0, 0.0, 1.0)
			if global_position.distance_to(body.global_position) <= reach:
				found.append(body)
	return found


## The Seeker's quiet sound, at the device, as its owner's (NPCs hear it
## through Enemy.heard_sound).
func make_sound() -> void:
	if not is_instance_valid(owner_mecha) or not owner_mecha.has_signal("made_sound"):
		return
	owner_mecha.made_sound.emit({
		"volume_type": "quiet",
		"type": kind,
		"position": global_position,
		"max_distance": sound_range,
		"source": owner_mecha,
		"entities_only": false,
	})


## Shots, blasts and beams (the same call as Entity.take_hit). Only a
## mecha's attack hurts it, and only a destructible device.
func take_hit(damage: float, _pen := 0, _dir := Vector2.ZERO, source_info = null, _knockback := 0.0) -> void:
	if _gone or not destructible or typeof(source_info) != TYPE_DICTIONARY:
		return
	var by = source_info.get("body")
	if not is_instance_valid(by) or not (by is Node) or not (by as Node).is_in_group("mecha"):
		return
	hp -= damage
	if hp <= 0.0:
		destroy()


## Destroyed: the owner is told (Mecha.device_destroyed), then it goes.
func destroy() -> void:
	if _gone:
		return
	_gone = true
	destroyed.emit(self)
	if is_instance_valid(owner_mecha) and owner_mecha.has_signal("device_destroyed"):
		owner_mecha.device_destroyed.emit(self)
	queue_free()


## Ran its course (a drone at the end of its flight, a burnt-out flare, a
## Seeker switched off): gone, nobody told.
func expire() -> void:
	if _gone:
		return
	_gone = true
	queue_free()


func is_gone() -> bool:
	return _gone


## Where a follower is heading now, round its owner (see FOLLOW_ANGLE).
func follow_point() -> Vector2:
	var t := _drift_time * FOLLOW_DRIFT
	var angle := FOLLOW_ANGLE + FOLLOW_ANGLE_SWAY * (0.7 * sin(t + _drift_phase) + 0.3 * sin(t * 2.7 + _drift_phase * 2.0))
	var radius := FOLLOW_RADIUS + FOLLOW_RADIUS_SWAY * sin(t * 1.9 + _drift_phase * 3.0)
	return owner_mecha.global_position + Vector2.from_angle(angle).rotated(owner_mecha.global_rotation) * radius


func _follow(dt: float) -> void:
	_drift_time += dt
	var before := global_position
	global_position = global_position.lerp(follow_point(), 1.0 - exp(-FOLLOW_EASE * dt))
	var moved := global_position - before
	if moved.length() > 0.5:
		rotation = lerp_angle(rotation, moved.angle() + PI * 0.5, 1.0 - exp(-FOLLOW_EASE * 2.0 * dt))


func _report_to(viewer, ttl: float) -> void:
	var store: ContactStore = viewer.contacts
	for body in in_range(viewer):
		store.report(body, ContactStore.kind_of(body), body.global_position, kind, ttl)


func _draw() -> void:
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 32, THEME.get_color(&"g4", &"MechTokens"), 2.0)
