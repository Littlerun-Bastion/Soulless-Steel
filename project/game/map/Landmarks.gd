@tool
class_name Landmarks
extends Node2D

# The named places of a map (MapLandmarks, written by the generator): the
# Japanese Garden, the Helwan Observatory, the cemeteries ... Players name
# and navigate by them, and quest hints can point at them (describe).
#
# Look-ups (global positions):
#   at(pos)            the landmark whose outline holds pos (a landmark
#                      with no outline: within its radius), the smallest
#                      when several do; -1 for none
#   nearest(pos, max)  the landmark nearest pos (distance to its area, 0
#                      inside), within max px; -1 for none
#   describe(pos)      a phrase for a hint: "near <name>" inside a place or
#                      within NEAR_PX of it, "<n> m <direction> of <name>"
#                      out to max px, "" past that
#
# Entering: every CHECK_INTERVAL s this node finds which place the player is
# in. Entering one emits player_entered (the expedition shows the name on the
# HUD), unless the player has been in it before and left it less than
# reentry_time s ago, so walking along an edge or doubling back shows it
# once. A place the player is in when first found is taken as already
# entered (no notice at the start of a run). place_changed tells every
# change of the current place (-1 when in none). Nothing is saved.
#
# In the editor it draws each place's outline (or circle) and name.

signal player_entered(index: int)
signal place_changed(index: int)

const CHECK_INTERVAL := 0.25
const NEAR_PX := 4000.0
const DESCRIBE_RANGE := 30000.0
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const EDITOR_COLOR := Color(1.0, 0.8, 0.3, 0.8)
const EDITOR_LINE := 40.0
const EDITOR_FONT_SIZE := 320

@export var landmarks: MapLandmarks:
	set(value):
		landmarks = value
		_current = -1
		_prepare()
		queue_redraw()
## A MapLandmarks file loaded on ready when `landmarks` is not set (the
## generated scene's landmarks.res, written by build_meshes.gd). A missing
## file means no landmarks, so the scene loads before that file exists. In
## the editor it is loaded for drawing only, never into `landmarks`, so a
## scene that instances this one (the master scene) saves no copy of it.
@export_file("*.res", "*.tres") var landmarks_path := ""
## Seconds the player must be out of a place before entering it again shows
## its name again.
@export var reentry_time := 60.0

var _current := -1
var _seen_player := false
# Landmark index -> Time (s, game clock) the player last left it.
var _left_at := {}
var _entered := {}
var _clock := 0.0
var _timer := 0.0
var _player: Node2D = null
var _lookup := 0
var _rects: Array[Rect2] = []
var _editor_landmarks: MapLandmarks = null


func _ready() -> void:
	add_to_group("map_landmarks")
	if landmarks == null and landmarks_path != "" and ResourceLoader.exists(landmarks_path):
		var loaded := load(landmarks_path) as MapLandmarks
		if Engine.is_editor_hint():
			_editor_landmarks = loaded
			queue_redraw()
		else:
			landmarks = loaded
	_prepare()
	if Engine.is_editor_hint():
		set_process(false)


static func find(node: Node) -> Landmarks:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group("map_landmarks") as Landmarks


func count() -> int:
	return landmarks.count() if landmarks != null else 0


func name_of(i: int) -> String:
	return landmarks.names[i] if i >= 0 and i < count() else ""


func kind_of(i: int) -> String:
	return landmarks.kinds[i] if i >= 0 and i < count() else ""


func centre_of(i: int) -> Vector2:
	return to_global(landmarks.centres[i]) if i >= 0 and i < count() else Vector2.INF


func radius_of(i: int) -> float:
	return landmarks.radii[i] if i >= 0 and i < count() else 0.0


# The place the player is in now (-1: none, or not found yet).
func current() -> int:
	return _current


func contains(i: int, global_pos: Vector2) -> bool:
	if i < 0 or i >= count():
		return false
	if _rects.size() != count():
		_prepare()
	var p := to_local(global_pos)
	if not _rects[i].has_point(p):
		return false
	var ring := landmarks.outline(i)
	if ring.size() >= 3:
		return Geometry2D.is_point_in_polygon(p, ring)
	return p.distance_to(landmarks.centres[i]) <= landmarks.radii[i]


# Distance (px) from a global position to landmark i's area, 0 inside.
func distance_to(i: int, global_pos: Vector2) -> float:
	if i < 0 or i >= count():
		return INF
	if contains(i, global_pos):
		return 0.0
	var p := to_local(global_pos)
	var ring := landmarks.outline(i)
	if ring.size() < 3:
		return maxf(p.distance_to(landmarks.centres[i]) - landmarks.radii[i], 0.0)
	var best := INF
	for k in ring.size():
		var q := Geometry2D.get_closest_point_to_segment(p, ring[k], ring[(k + 1) % ring.size()])
		best = minf(best, p.distance_to(q))
	return best


func at(global_pos: Vector2) -> int:
	var best := -1
	for i in count():
		if contains(i, global_pos) and (best < 0 or landmarks.radii[i] < landmarks.radii[best]):
			best = i
	return best


func nearest(global_pos: Vector2, max_px := INF) -> int:
	var best := -1
	var best_d := max_px
	for i in count():
		var d := distance_to(i, global_pos)
		if d <= best_d:
			best = i
			best_d = d
	return best


func describe(global_pos: Vector2, max_px := DESCRIBE_RANGE) -> String:
	var i := at(global_pos)
	if i < 0:
		i = nearest(global_pos, max_px)
	if i < 0:
		return ""
	var d := distance_to(i, global_pos)
	if d <= NEAR_PX:
		return "near " + name_of(i)
	var metres := maxi(100, roundi(d / MapSenses.PX_PER_METRE / 100.0) * 100)
	var from_centre := global_pos - centre_of(i)
	var octant := posmod(roundi(from_centre.angle() / (TAU / 8.0)), 8)
	return "%d m %s of %s" % [metres, COMPASS[octant], name_of(i)]


func _process(delta: float) -> void:
	_clock += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	var player := _find_player()
	if player == null or count() == 0:
		return
	update_player(player.global_position)


# Moves the player's current place to the one at `global_pos`, emitting the
# signals (see Entering above). Called every CHECK_INTERVAL s.
func update_player(global_pos: Vector2) -> void:
	var now := at(global_pos)
	if now == _current:
		_seen_player = true
		return
	if _current >= 0:
		_left_at[_current] = _clock
	var first := not _seen_player
	_seen_player = true
	_current = now
	place_changed.emit(now)
	if now < 0:
		return
	var announce := not first and (not _entered.has(now) or _clock - float(_left_at.get(now, -INF)) >= reentry_time)
	_entered[now] = true
	if announce:
		player_entered.emit(now)


func _prepare() -> void:
	_rects.clear()
	if landmarks == null:
		return
	for i in landmarks.count():
		var ring := landmarks.outline(i)
		var r := landmarks.radii[i]
		var rect := Rect2(landmarks.centres[i] - Vector2(r, r), Vector2(r, r) * 2.0)
		if ring.size() >= 3:
			rect = Rect2(ring[0], Vector2.ZERO)
			for p in ring:
				rect = rect.expand(p)
		_rects.append(rect)


func _draw() -> void:
	var data := landmarks if landmarks != null else _editor_landmarks
	if not Engine.is_editor_hint() or data == null:
		return
	var font := ThemeDB.fallback_font
	for i in data.count():
		var ring := data.outline(i)
		if ring.size() >= 3:
			var closed := ring.duplicate()
			closed.append(ring[0])
			draw_polyline(closed, EDITOR_COLOR, EDITOR_LINE)
		else:
			draw_arc(data.centres[i], data.radii[i], 0.0, TAU, 64, EDITOR_COLOR, EDITOR_LINE)
		draw_string(font, data.centres[i], data.names[i], HORIZONTAL_ALIGNMENT_CENTER, -1,
				EDITOR_FONT_SIZE, EDITOR_COLOR)


func _find_player() -> Node2D:
	if is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	_player = null
	_lookup -= 1
	if _lookup > 0:
		return null
	_lookup = 8
	for mech in get_tree().get_nodes_in_group("mecha"):
		if mech is Node2D and mech.has_method("is_player") and mech.is_player():
			_player = mech
			break
	return _player
