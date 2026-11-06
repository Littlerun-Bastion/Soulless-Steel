extends CanvasLayer

# The observer arena's overlays, drawn in screen space above the IR colour map
# (HeatmapEffects, layer 2) and under the panel, for every mecha on the map,
# brighter for the selected one:
#   sight    each NPC's sight circle (Mecha.sight_radius, shortened under a
#            tree): it sees nothing past it
#   cone     each mecha's illuminator cone (Illumination: its angle and
#            reach, along the light), faint while the light is off
#   tracks   each NPC's contacts (ContactStore): a cross where the source put
#            the body, live ones solid, ghosts fading over the store's
#            ghost_time; the selected NPC's are labelled "<KIND> · <SOURCE>"
#   wedges   each NPC's wedges (ContactStore.wedges): the sector out to its
#            range band (to its sight circle for an unknown range), and a
#            cross at its estimate point, fading as it ages
#   locks    a line from each locker to what it locks: dashed while locking,
#            solid once locked
#   tags     each NPC's think tag under it (tag_lines): its name and intent,
#            how long it has stood still (from STILL_SHOW s: within
#            STILL_RADIUS px of one spot, game time), and its top intent
#            scores; the selected NPC's has the whole ai_overlay detail
#            (Enemy.overlay_text: every score, its light and panic, what it
#            knows, its target) instead. The same size at any zoom
#   barks    what each mecha says (ObserverArena._on_mecha_spoke), in a box
#            over it for as long as the speech lasts
# and the selected dummy's patrol points and fire point.
#
# Greys and strokes are MechTheme's tokens (G1 to G6, S1 and S2).

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const LAYER := 4
const CROSS_HALF := 8.0
const SELECT_RADIUS := 26.0
const POINT_HALF := 6.0
const LABEL_SIZE := 16
const ARC_POINTS := 96
## Tags and speech boxes (px): text size, line spacing, padding, how far
## from the mecha's centre at least, how wide a speech box gets before it
## wraps, and how many scores a tag lists. Placeholders.
const TAG_SIZE := 14
const TAG_LINE := 16.0
const TAG_PAD := 4.0
const TAG_GAP := 18.0
const SPEECH_WIDTH := 320.0
const TAG_SCORES := 3
## A mecha's body reaches about this far (world px) round its centre.
const BODY_REACH := 125.0
## Standing still: within STILL_RADIUS (world px) of one spot; the tag shows
## it from STILL_SHOW s.
const STILL_RADIUS := 40.0
const STILL_SHOW := 3.0

var arena = null
var show_sight := true
var show_cone := true
var show_tracks := true
var show_wedges := true
var show_locks := true
var show_tags := true
var show_barks := true

var _canvas: Node2D = null
var _font: Font = null
## Mecha -> {"text", "left": game seconds it still shows}.
var _speech := {}
## Mecha -> {"at": the spot it is standing at, "time": game seconds there}.
var _still := {}


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.name = "Canvas"
	add_child(_canvas)
	_canvas.draw.connect(_draw_overlays)
	_font = THEME.get_font(&"font", &"LabelMeta")


func _process(delta: float) -> void:
	_canvas.queue_redraw()
	if arena == null or not is_instance_valid(arena):
		return
	for m in _still.keys():
		if not is_instance_valid(m) or m.is_dead:
			_still.erase(m)
	if arena.game_paused:
		return
	for m in _speech.keys():
		_speech[m].left -= delta
		if not is_instance_valid(m) or _speech[m].left <= 0.0:
			_speech.erase(m)
	for m in arena.observed_npcs():
		var entry: Dictionary = _still.get(m, {})
		if entry.is_empty() or m.global_position.distance_to(entry.at) > STILL_RADIUS:
			_still[m] = {"at": m.global_position, "time": 0.0}
		else:
			entry.time += delta


## Shows `text` in a box over `mecha` for `seconds` of game time.
func show_speech(mecha, text: String, seconds: float) -> void:
	_speech[mecha] = {"text": text, "left": seconds}


## What `mecha` is saying now ("" for nothing).
func speech_of(mecha) -> String:
	return str(_speech[mecha].text) if _speech.has(mecha) else ""


## How long (game s) `npc` has stood within STILL_RADIUS of one spot.
func still_time(npc) -> float:
	return float(_still[npc].time) if _still.has(npc) else 0.0


## The lines of `npc`'s think tag (see above); `detailed` adds the
## ai_overlay detail.
func tag_lines(npc, detailed: bool) -> PackedStringArray:
	var lines := PackedStringArray()
	var state = npc.logic.get_current_state() if npc.logic != null else null
	var head := "%s · %s" % [str(npc.mecha_name).to_upper(), str(state).to_upper() if state else "?"]
	var still := still_time(npc)
	if still >= STILL_SHOW:
		head += " · STILL %dS" % int(still)
	lines.append(head)
	if detailed:
		lines.append_array(npc.overlay_text().split("\n", false))
	elif npc.logic != null and not npc.logic.last_scores.is_empty():
		var parts := PackedStringArray()
		for pair in npc.logic.last_scores.slice(0, TAG_SCORES):
			parts.append("%s %.2f" % [pair[0], pair[1]])
		lines.append(" ".join(parts))
	return lines


## How far (px) an NPC sees at most: its sight circle, as Enemy.update_senses
## takes it.
static func sight_reach(npc) -> float:
	return npc.sight_radius() * MapSenses.sight_mult(npc)


func _draw_overlays() -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var to_screen: Transform2D = arena.get_viewport().get_canvas_transform()
	var zoom: float = to_screen.get_scale().x
	var g3 := THEME.get_color(&"g3", &"MechTokens")
	var g4 := THEME.get_color(&"g4", &"MechTokens")
	var g5 := THEME.get_color(&"g5", &"MechTokens")
	var g6 := THEME.get_color(&"g6", &"MechTokens")
	var s1 := float(THEME.get_constant(&"s1", &"MechTokens"))
	var s2 := float(THEME.get_constant(&"s2", &"MechTokens"))
	for m in arena.observed_mechas():
		var selected: bool = is_same(m, arena.selected)
		var dummy: bool = arena.is_dummy(m)
		var at: Vector2 = to_screen * m.global_position
		var bright := g6 if selected else g4
		var width := s2 if selected else s1
		if selected:
			_canvas.draw_arc(at, SELECT_RADIUS, 0.0, TAU, 32, g6, s2)
		if show_sight and not dummy:
			var faint := bright
			faint.a = 0.6 if selected else 0.35
			_canvas.draw_arc(at, sight_reach(m) * zoom, 0.0, TAU, ARC_POINTS, faint, width)
		if show_cone:
			_draw_cone(m, to_screen, zoom, bright if m.illuminator_on else g3, width)
		if show_tracks and not dummy:
			_draw_tracks(m, to_screen, g5 if selected else g4, width, selected)
		if show_wedges and not dummy:
			_draw_wedges(m, to_screen, zoom, g5 if selected else g4, width)
		if show_locks:
			_draw_lock(m, to_screen, g6 if selected else g5, width)
	var reach := maxf(BODY_REACH * zoom, TAG_GAP)
	if show_tags and _font != null:
		for npc in arena.observed_npcs():
			var selected: bool = is_same(npc, arena.selected)
			_draw_box(to_screen * npc.global_position + Vector2(0.0, reach), tag_lines(npc, selected), -1.0,
					g6 if selected else g5, false)
	if show_barks and _font != null:
		for m in _speech:
			if is_instance_valid(m):
				_draw_box(to_screen * m.global_position - Vector2(0.0, reach), PackedStringArray([speech_of(m)]),
						SPEECH_WIDTH, g6, true)
	var control = arena.dummy_control(arena.selected_dummy)
	if control != null:
		var last := Vector2.INF
		for point in control.patrol_points:
			var p: Vector2 = to_screen * point
			_canvas.draw_rect(Rect2(p - Vector2.ONE * POINT_HALF, Vector2.ONE * POINT_HALF * 2.0), g5, false, s1)
			if last != Vector2.INF:
				_canvas.draw_dashed_line(last, p, g4, s1, 8.0)
			last = p
		if control.fire_point != Vector2.INF:
			_cross(to_screen * control.fire_point, g6, s2)


func _draw_cone(m, to_screen: Transform2D, zoom: float, color: Color, width: float) -> void:
	var light := Illumination.light_of(m)
	if light == null:
		return
	var origin: Vector2 = to_screen * light.global_position
	var reach := Illumination.reach(light) * zoom
	var half := deg_to_rad(Illumination.cone_angle(light) * 0.5)
	var forward := Vector2.UP.rotated(light.global_rotation)
	var start := forward.angle() - half
	var end := forward.angle() + half
	if half * 2.0 < TAU - 0.01:
		_canvas.draw_line(origin, origin + Vector2.from_angle(start) * reach, color, width)
		_canvas.draw_line(origin, origin + Vector2.from_angle(end) * reach, color, width)
	_canvas.draw_arc(origin, reach, start, end, maxi(8, int(ARC_POINTS * half / PI)), color, width)


func _draw_tracks(m, to_screen: Transform2D, color: Color, width: float, labelled: bool) -> void:
	var store: ContactStore = m.contacts
	for contact in store.get_all():
		var c := color
		c.a = 1.0 - store.ghost_fade(contact)
		if not contact.live:
			c.a *= 0.6
		var p: Vector2 = to_screen * contact.position
		_cross(p, c, width)
		if labelled and _font != null:
			var text := "%s · %s" % [str(contact.kind).to_upper(), str(contact.source).to_upper()]
			_canvas.draw_string(_font, p + Vector2(CROSS_HALF + 4.0, LABEL_SIZE * 0.4), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, c)


func _draw_wedges(m, to_screen: Transform2D, zoom: float, color: Color, width: float) -> void:
	var store: ContactStore = m.contacts
	for wedge in store.wedges():
		var c := color
		c.a = (1.0 - store.ghost_fade(wedge)) * (1.0 if wedge.live else 0.6)
		var origin: Vector2 = to_screen * Vector2(wedge.origin)
		var half := deg_to_rad(float(wedge.width)) * 0.5
		var near := float(wedge.min_range) * zoom
		var far := (sight_reach(m) if is_inf(float(wedge.max_range)) else float(wedge.max_range)) * zoom
		var bearing := float(wedge.bearing)
		for edge in [bearing - half, bearing + half]:
			_canvas.draw_line(origin + Vector2.from_angle(edge) * near, origin + Vector2.from_angle(edge) * far, c, width)
		if half > 0.001:
			_canvas.draw_arc(origin, far, bearing - half, bearing + half, maxi(4, int(ARC_POINTS * half / PI)), c, width)
			if near > 0.0:
				_canvas.draw_arc(origin, near, bearing - half, bearing + half, maxi(4, int(ARC_POINTS * half / PI)), c, width)
		_cross(to_screen * ContactStore.estimate_point(wedge), c, width)


func _draw_lock(m, to_screen: Transform2D, color: Color, width: float) -> void:
	var locked = m.get_locked_to()
	var locking = m.get_locking_to()
	var target = locked if locked else (locking.mecha if locking else null)
	if not is_instance_valid(target):
		return
	var from: Vector2 = to_screen * m.global_position
	var to: Vector2 = to_screen * target.global_position
	if locked:
		_canvas.draw_line(from, to, color, width)
	else:
		_canvas.draw_dashed_line(from, to, color, width, 10.0)


# A box of `lines` on a G1 backing, centred on `anchor` across: hanging
# below it, or standing on it when `above`. With `wrap` above 0 the text
# wraps at that width; otherwise the box is as wide as its widest line.
func _draw_box(anchor: Vector2, lines: PackedStringArray, wrap: float, color: Color, above: bool) -> void:
	var text := "\n".join(lines)
	var width := wrap
	if width <= 0.0:
		width = 0.0
		for line in lines:
			width = maxf(width, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x)
	var size := _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, TAG_SIZE)
	if wrap > 0.0:
		width = minf(width, size.x + 1.0)
	var box := Rect2(anchor.x - width * 0.5 - TAG_PAD, anchor.y, width + TAG_PAD * 2.0, size.y + TAG_PAD * 2.0)
	if above:
		box.position.y -= box.size.y
	var back := THEME.get_color(&"g1", &"MechTokens")
	back.a = 0.8
	_canvas.draw_rect(box, back)
	_canvas.draw_rect(box, THEME.get_color(&"g3", &"MechTokens"), false, 1.0)
	_canvas.draw_multiline_string(_font, box.position + Vector2(TAG_PAD, TAG_PAD + _font.get_ascent(TAG_SIZE)), text,
			HORIZONTAL_ALIGNMENT_LEFT, width, TAG_SIZE, -1, color)


func _cross(p: Vector2, color: Color, width: float) -> void:
	var h := CROSS_HALF
	_canvas.draw_line(p + Vector2(-h, -h), p + Vector2(h, h), color, width)
	_canvas.draw_line(p + Vector2(-h, h), p + Vector2(h, -h), color, width)
