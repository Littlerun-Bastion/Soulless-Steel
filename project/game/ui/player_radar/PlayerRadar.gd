extends Control

## The radar round the player's mecha: a ring RadarRing.RADIUS px round it on
## screen, and on the ring the player's tracks (its ContactStore), never a
## mech it has no track on. Drawn at 1:1 in MechOS greys and strokes:
##   live track   a mark on the ring at its bearing (its shape tells the kind:
##                MARK_SHAPES), with 1 to 3 chevrons outside it for far, mid
##                or near inside the sight circle (its thirds); past the
##                circle, the mark alone
##   ghost        the same mark, hollow, fading over its ghost time
##   alarm        a round mark
##   wedge        an arc on the ring as wide as the wedge: shot and sound
##                arcs thin, fading as they age; a lock arc bright, pulsing
##                with the warning's beep and narrowing with the lock (a tick
##                once it is a line)
##   own lock     a bracket round the locked target's mark
## One mark per body: its best contact (ContactStore.best_for). Marks that
## would overlap on the ring stack outward from it, STACK_STEP px a level.
## Everything is worked out each frame (marks, arcs) and drawn in _draw.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const RING := preload("res://game/ui/player_radar/RadarRing.gd")
const MARKS := preload("res://game/ui/player_radar/RadarPointer.gd")
## The warning's beep spacing (PlayerHUD.lock_beep_interval): the lock arc
## pulses in time with it.
const HUD := preload("res://game/ui/PlayerHUD.gd")
## A contact's kind -> its mark's shape; any other kind (an Entity's
## species) is "diamond".
const MARK_SHAPES := {"mech": "triangle", IRSensing.KIND: "square"}
## Placeholders (px).
const MARK_GAP := 16.0
const STACK_STEP := 14.0
const MARK_OUT := 10.0
const ARC_OUT := 4.0
const THIN_ARC := 2.0
const LOCK_ARC := 3.0

var player = null
## This frame's marks: {shape, bearing (radians), level (0 on the ring),
## hollow, fade (0..1), chevrons (0..3), locked}.
var marks: Array[Dictionary] = []
## This frame's arcs: {source, bearing, width (degrees), fade, pulse}.
var arcs: Array[Dictionary] = []
var _pulse_time := 0.0


func setup(player_ref) -> void:
	player = player_ref
	marks.clear()
	arcs.clear()


func player_died() -> void:
	player = null
	hide()


func _process(dt: float) -> void:
	if not is_instance_valid(player) or not visible:
		return
	position = player.get_global_transform_with_canvas().origin
	_pulse_time += dt
	refresh()
	queue_redraw()


## Works out this frame's marks and arcs from the player's contacts.
func refresh() -> void:
	marks.clear()
	arcs.clear()
	if not is_instance_valid(player):
		return
	var store: ContactStore = player.contacts
	var origin: Vector2 = player.global_position
	var sight: float = player.sight_radius() if player.has_method("sight_radius") else INF
	var locked = player.get_locked_to() if player.has_method("get_locked_to") else null
	var seen := {}
	var found: Array[Dictionary] = []
	for contact in store.get_all():
		var body = contact.body
		var key = body.get_instance_id() if body != null else contact
		if seen.has(key):
			continue
		var best: Dictionary = store.best_for(body) if body != null else contact
		seen[key] = true
		var offset: Vector2 = Vector2(best.position) - origin
		var distance := offset.length()
		var shape: String = "round" if best.source == "alarm" else str(MARK_SHAPES.get(best.kind, "diamond"))
		found.append({"shape": shape, "bearing": offset.angle(), "distance": distance, "level": 0,
				"hollow": not best.live, "fade": store.ghost_fade(best), "chevrons": chevrons_for(distance, sight),
				"locked": locked != null and is_same(body, locked), "source": best.source})
	found.sort_custom(func(a, b): return a.distance < b.distance)
	for mark in found:
		mark.level = _free_level(mark.bearing)
		marks.append(mark)
	var warning: Dictionary = player.lock_warning() if player.has_method("lock_warning") else {}
	for wedge in store.wedges():
		var fade := store.ghost_fade(wedge)
		if wedge.source == "lock":
			var live: bool = not warning.is_empty() and is_same(warning.wedge, wedge)
			arcs.append({"source": "lock", "bearing": wedge.bearing, "width": wedge.width, "fade": fade if not live else 0.0,
					"pulse": live})
		else:
			arcs.append({"source": wedge.source, "bearing": wedge.bearing, "width": wedge.width,
					"fade": maxf(fade, store.age(wedge) / float(ContactStore.WEDGES[wedge.source].ttl) * 0.5), "pulse": false})


## How many chevrons a track `distance` px away gets in a `sight` px circle:
## 3 near, 2 mid, 1 far (thirds of the circle), 0 past it.
static func chevrons_for(distance: float, sight: float) -> int:
	if distance > sight:
		return 0
	if distance > sight * 2.0 / 3.0:
		return 1
	if distance > sight / 3.0:
		return 2
	return 3


# The lowest stack level where a mark at `bearing` clears the marks already
# placed (MARK_GAP px apart along the ring at that level).
func _free_level(bearing: float) -> int:
	var level := 0
	while true:
		var radius := RING.RADIUS + MARK_OUT + level * STACK_STEP
		var clash := false
		for mark in marks:
			if mark.level != level:
				continue
			if absf(angle_difference(mark.bearing, bearing)) * radius < MARK_GAP:
				clash = true
				break
		if not clash:
			return level
		level += 1
	return level


func _draw() -> void:
	var dim := THEME.get_color(&"g4", &"MechTokens")
	var mid := THEME.get_color(&"g5", &"MechTokens")
	var bright := THEME.get_color(&"g6", &"MechTokens")
	for arc in arcs:
		var color: Color = bright if arc.source == "lock" else mid
		color.a *= 1.0 - float(arc.fade)
		if arc.pulse:
			var warning: Dictionary = player.lock_warning()
			var rate := 1.0 / maxf(HUD.lock_beep_interval(float(warning.get("progress", 0.0))), 0.05)
			color.a *= 0.55 + 0.45 * cos(_pulse_time * TAU * rate)
		var radius := RING.RADIUS + ARC_OUT
		var half := deg_to_rad(float(arc.width)) * 0.5
		if half <= 0.001:
			var dir := Vector2.from_angle(arc.bearing)
			draw_line(dir * (radius - 6.0), dir * (radius + 10.0), color, LOCK_ARC, true)
		else:
			draw_arc(Vector2.ZERO, radius, arc.bearing - half, arc.bearing + half, maxi(4, int(half * 24.0)), color,
					LOCK_ARC if arc.source == "lock" else THIN_ARC, true)
	for mark in marks:
		var color: Color = mid if not mark.hollow else dim
		color.a *= 1.0 - float(mark.fade)
		var at: Vector2 = Vector2.from_angle(mark.bearing) * (RING.RADIUS + MARK_OUT + mark.level * STACK_STEP)
		MARKS.draw_mark(self, at, mark.bearing, mark.shape, color, mark.hollow)
		MARKS.draw_chevrons(self, at, mark.bearing, mark.chevrons, color)
		if mark.locked:
			MARKS.draw_bracket(self, at, bright)
