extends Control

## The radar round the player's mecha: a ring RadarRing.RADIUS px round it on
## screen, and round the ring the player's tracks (its ContactStore), never a
## mech it has no track on. Each kind of thing has a lane of its own, a
## circle at its own radius, so none sits on another:
##   SOUND_R  inside the ring: sound wedges, a dotted arc as wide as the
##            wedge, fading as it ages
##   SHOT_R   inside the ring, nearer it: shot wedges, a dashed arc
##   RADIUS   the ring
##   MARK_R   outside the ring: one mark per body (its best contact,
##            ContactStore.best_for), its shape telling the kind
##            (MARK_SHAPES), with 1 to 3 chevrons outside it for far, mid or
##            near inside the sight circle (its thirds); past the circle the
##            mark alone. A ghost is the same mark, hollow, fading over its
##            ghost time; an alarm a round mark; the player's own lock a
##            bracket round the target's mark
##   LOCK_R   outermost, clear of the marks and their chevrons: lock wedges, a
##            bright solid band with end caps pointing in and a LOCK label,
##            pulsing with the warning's beep and narrowing with the lock (an
##            arrowhead pointing in once it is a line)
## Marks closer than MARK_GAP px along their lane spread apart along it
## (spread), each moved one with a leader from its true bearing on the ring.
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
const SOUND_R := RING.RADIUS - 16.0
const SHOT_R := RING.RADIUS - 8.0
const MARK_R := RING.RADIUS + 12.0
const LOCK_R := RING.RADIUS + 48.0
const MARK_GAP := 18.0
const LEADER_MIN := 3.0
const THIN_ARC := 2.0
const DASH := 6.0
const DASH_GAP := 4.0
const DOT_STEP := 5.0
const DOT := 1.25
const LOCK_ARC := 4.0
const LOCK_CAP := 7.0
const LOCK_HEAD := 7.0
const LABEL := "LOCK"
const LABEL_SIZE := 16
const LABEL_GAP := 5.0
## Each wedge source's lane and how its arc is drawn.
const LANES := {
	"sound": {"radius": SOUND_R, "style": "dot"},
	"shot": {"radius": SHOT_R, "style": "dash"},
	"lock": {"radius": LOCK_R, "style": "band"},
}

var player = null
## This frame's marks: {shape, bearing (radians, the truth), at (radians,
## where it is drawn on its lane), distance, hollow, fade (0..1), chevrons
## (0..3), locked, source}.
var marks: Array[Dictionary] = []
## This frame's arcs: {source, bearing, width (degrees), radius, style, fade,
## pulse}.
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
	var bearings: Array[float] = []
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
		marks.append({"shape": shape, "bearing": offset.angle(), "at": offset.angle(), "distance": distance,
				"hollow": not best.live, "fade": store.ghost_fade(best), "chevrons": chevrons_for(distance, sight),
				"locked": locked != null and is_same(body, locked), "source": best.source})
		bearings.append(offset.angle())
	var spread_out := spread(bearings, MARK_GAP / MARK_R)
	for i in marks.size():
		marks[i].at = spread_out[i]
	var warning: Dictionary = player.lock_warning() if player.has_method("lock_warning") else {}
	for wedge in store.wedges():
		var fade := store.ghost_fade(wedge)
		var lane: Dictionary = LANES[wedge.source]
		var arc := {"source": wedge.source, "bearing": wedge.bearing, "width": wedge.width, "radius": lane.radius,
				"style": lane.style, "pulse": false}
		if wedge.source == "lock":
			arc.pulse = not warning.is_empty() and is_same(warning.wedge, wedge)
			arc.fade = 0.0 if arc.pulse else fade
		else:
			arc.fade = maxf(fade, store.age(wedge) / float(ContactStore.WEDGES[wedge.source].ttl) * 0.5)
		arcs.append(arc)


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


## Where to draw marks at `bearings` (radians) on a circle so that no two
## are closer than `gap` radians: each run of marks that would be closer
## than that is laid out `gap` apart, in order of bearing, round the run's
## mean bearing, and runs that then come too close join into one. The circle
## is cut at the widest space between bearings, so a run can straddle ±PI.
## Too many marks for the circle share it evenly. Returns the bearings, in
## -PI..PI, in the order given.
static func spread(bearings: Array[float], gap: float) -> Array[float]:
	var n := bearings.size()
	var result: Array[float] = []
	for bearing in bearings:
		result.append(wrapf(bearing, -PI, PI))
	if n < 2:
		return result
	gap = minf(gap, TAU / n)
	var order: Array = range(n)
	order.sort_custom(func(a, b): return result[a] < result[b])
	var cut := 0
	var widest := -1.0
	for k in n:
		var space := wrapf(result[order[k]] - result[order[k - 1]], 0.0, TAU)
		if space > widest:
			widest = space
			cut = k
	var line: Array[float] = []
	var ids: Array[int] = []
	var start: float = result[order[cut]]
	for k in n:
		var id: int = order[(cut + k) % n]
		ids.append(id)
		line.append(start + wrapf(result[id] - start, 0.0, TAU))
	var runs: Array[Dictionary] = []
	for k in n:
		runs.append({"first": k, "count": 1, "sum": line[k]})
		while runs.size() >= 2:
			var a: Dictionary = runs[-2]
			var b: Dictionary = runs[-1]
			var a_end: float = a.sum / a.count + (a.count - 1) * gap * 0.5
			var b_start: float = b.sum / b.count - (b.count - 1) * gap * 0.5
			if b_start - a_end >= gap - 0.000001:
				break
			a.count += b.count
			a.sum += b.sum
			runs.pop_back()
	var first: Dictionary = runs[0]
	var last: Dictionary = runs[-1]
	var low: float = first.sum / first.count - (first.count - 1) * gap * 0.5
	var high: float = last.sum / last.count + (last.count - 1) * gap * 0.5
	if runs.size() > 1 and low + TAU - high < gap - 0.000001:
		var total := 0.0
		for run in runs:
			total += run.sum
		runs.clear()
		runs.append({"first": 0, "count": n, "sum": total})
	for run in runs:
		if run.count == 1:
			continue
		var middle: float = run.sum / run.count
		for j in run.count:
			result[ids[run.first + j]] = wrapf(middle + (j - (run.count - 1) * 0.5) * gap, -PI, PI)
	return result


func _draw() -> void:
	var dim := THEME.get_color(&"g4", &"MechTokens")
	var mid := THEME.get_color(&"g5", &"MechTokens")
	var bright := THEME.get_color(&"g6", &"MechTokens")
	for arc in arcs:
		var color: Color = bright if arc.style == "band" else mid
		color.a *= 1.0 - float(arc.fade)
		if arc.pulse:
			var warning: Dictionary = player.lock_warning()
			var rate := 1.0 / maxf(HUD.lock_beep_interval(float(warning.get("progress", 0.0))), 0.05)
			color.a *= 0.55 + 0.45 * cos(_pulse_time * TAU * rate)
		var half := deg_to_rad(float(arc.width)) * 0.5
		match arc.style:
			"dot":
				_draw_dotted(arc.radius, arc.bearing, half, color)
			"dash":
				_draw_dashed(arc.radius, arc.bearing, half, color)
			_:
				_draw_lock(arc.radius, arc.bearing, half, color)
	for mark in marks:
		var color: Color = mid if not mark.hollow else dim
		color.a *= 1.0 - float(mark.fade)
		var at: Vector2 = Vector2.from_angle(mark.at) * MARK_R
		if absf(angle_difference(mark.bearing, mark.at)) * MARK_R > LEADER_MIN:
			var leader := dim
			leader.a *= 1.0 - float(mark.fade)
			draw_line(Vector2.from_angle(mark.bearing) * RING.RADIUS, Vector2.from_angle(mark.at) * (MARK_R - MARKS.MARK_SIZE),
					leader, 1.0, true)
		MARKS.draw_mark(self, at, mark.at, mark.shape, color, mark.hollow)
		MARKS.draw_chevrons(self, at, mark.at, mark.chevrons, color)
		if mark.locked:
			MARKS.draw_bracket(self, at, mark.at, bright)


# Dots DOT_STEP px apart along the arc, the first and last on its ends.
func _draw_dotted(radius: float, bearing: float, half: float, color: Color) -> void:
	var count := int(radius * half * 2.0 / DOT_STEP) + 1
	for i in count:
		var angle := bearing if count == 1 else bearing - half + half * 2.0 * i / (count - 1)
		draw_circle(Vector2.from_angle(angle) * radius, DOT, color)


# DASH px dashes about DASH_GAP px apart, the first and last on the arc's
# ends; an arc shorter than a dash gets one dash on its middle.
func _draw_dashed(radius: float, bearing: float, half: float, color: Color) -> void:
	var length := radius * half * 2.0
	var count := maxi(1, int((length + DASH_GAP) / (DASH + DASH_GAP)))
	for i in count:
		var from := -DASH * 0.5
		if count > 1:
			from = -length * 0.5 + i * (length - DASH) / (count - 1)
		draw_arc(Vector2.ZERO, radius, bearing + from / radius, bearing + (from + DASH) / radius, 3, color, THIN_ARC, true)


func _draw_lock(radius: float, bearing: float, half: float, color: Color) -> void:
	var dir := Vector2.from_angle(bearing)
	var side := dir.orthogonal()
	if half <= 0.001:
		draw_colored_polygon(PackedVector2Array([dir * (radius - LOCK_HEAD),
				dir * (radius + LOCK_HEAD * 0.6) + side * LOCK_HEAD * 0.7,
				dir * (radius + LOCK_HEAD * 0.6) - side * LOCK_HEAD * 0.7]), color)
	else:
		draw_arc(Vector2.ZERO, radius, bearing - half, bearing + half, maxi(6, int(half * 32.0)), color, LOCK_ARC, true)
		for end in [bearing - half, bearing + half]:
			var edge := Vector2.from_angle(end)
			draw_line(edge * (radius + LOCK_ARC * 0.5), edge * (radius - LOCK_CAP), color, LOCK_ARC * 0.5, true)
	var font: Font = THEME.default_font if THEME.default_font != null else ThemeDB.fallback_font
	var text_size := font.get_string_size(LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	# The label's box sits just outside the band: its centre is as far out
	# as the box reaches back toward the ring along `dir`.
	var reach := absf(dir.x) * text_size.x * 0.5 + absf(dir.y) * text_size.y * 0.5
	var centre := dir * (radius + LOCK_ARC + LABEL_GAP + reach)
	draw_string(font, centre + Vector2(-text_size.x * 0.5, text_size.y * 0.5 - font.get_descent(LABEL_SIZE)), LABEL,
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
