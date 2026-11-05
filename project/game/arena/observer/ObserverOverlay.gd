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
# and the selected dummy's patrol points and fire point. The ai_overlay label
# over each NPC is the NPC's own (ObserverArena.set_labels), kept upright
# here while it shows.
#
# Greys and strokes are MechTheme's tokens (G3 to G6, S1 and S2).

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const LAYER := 4
const CROSS_HALF := 8.0
const SELECT_RADIUS := 26.0
const POINT_HALF := 6.0
const LABEL_SIZE := 16
const ARC_POINTS := 96

var arena = null
var show_sight := true
var show_cone := true
var show_tracks := true
var show_wedges := true
var show_locks := true

var _canvas: Node2D = null
var _font: Font = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Node2D.new()
	_canvas.name = "Canvas"
	add_child(_canvas)
	_canvas.draw.connect(_draw_overlays)
	_font = THEME.get_font(&"font", &"LabelMeta")


func _process(_delta: float) -> void:
	_canvas.queue_redraw()
	if arena != null and is_instance_valid(arena) and arena.labels_on():
		for m in arena.observed_mechas():
			var label_holder := m.get_node_or_null("Debug") as Node2D
			if label_holder != null and label_holder.global_rotation != 0.0:
				label_holder.global_rotation = 0.0


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


func _cross(p: Vector2, color: Color, width: float) -> void:
	var h := CROSS_HALF
	_canvas.draw_line(p + Vector2(-h, -h), p + Vector2(h, h), color, width)
	_canvas.draw_line(p + Vector2(-h, h), p + Vector2(h, -h), color, width)
