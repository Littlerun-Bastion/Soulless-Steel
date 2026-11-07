class_name MemorialCandle
extends Control

## A candle for the Memorial Wall, drawn on whole pixels in MechTokens greys:
## a BODY candle in a 1 px OUTLINE with a HIGHLIGHT stripe, a WICK, a FLAME
## and a saucer.
##   big     (the record page) BIG_SIZE; two rings of glow round the flame,
##           GLOW_INNER then GLOW_OUTER, each on every other pixel (dither, no
##           alpha). It flickers: every FLICKER_SECONDS the flame takes a new
##           height (FLAME_HEIGHTS) and lean (FLAME_LEANS, most at the tip).
##           It only runs while it is visible in the tree.
##   small   (record cards) SMALL_SIZE, still, no glow.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const BODY := "g5"
const HIGHLIGHT := "g6"
const OUTLINE := "g4"
const FLAME := "g6"
const CORE := "g5"
const WICK := "g3"
const SAUCER := "g3"
const GLOW_INNER := "g3"
const GLOW_OUTER := "g2"
const BIG_SIZE := Vector2i(72, 88)
const SMALL_SIZE := Vector2i(10, 16)
const FLICKER_SECONDS := [0.12, 0.3]
const FLAME_HEIGHTS := [14, 15, 15, 16]
const FLAME_LEANS := [-1, 0, 0, 1]
const FLAME_WIDTH := 9
const BODY_WIDTH := 21
const BODY_TOP := 36
## The glow's middle, this many rows over the candle's top.
const GLOW_RISE := 10
const GLOW_INNER_RADII := Vector2(11, 16)
const GLOW_OUTER_RADII := Vector2(17, 23)

var big := true
var flame_height := 15
var flame_lean := 0

var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _next := 0.2
var _glow_inner := PackedVector2Array()
var _glow_outer := PackedVector2Array()


func _init(is_big := true) -> void:
	big = is_big
	custom_minimum_size = Vector2(BIG_SIZE if big else SMALL_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rng.randomize()
	set_process(false)
	if big:
		_make_glow()


# Runs the flame only while the candle can be seen. Entering the tree, its
# parents' visibility isn't settled yet, so that check waits a moment.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_running()
	elif what == NOTIFICATION_ENTER_TREE:
		_update_running.call_deferred()


func _update_running() -> void:
	set_process(big and is_inside_tree() and is_visible_in_tree())


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= _next:
		flicker()


## A new flame height and lean, then a redraw.
func flicker() -> void:
	_clock = 0.0
	_next = _rng.randf_range(FLICKER_SECONDS[0], FLICKER_SECONDS[1])
	flame_height = FLAME_HEIGHTS[_rng.randi_range(0, FLAME_HEIGHTS.size() - 1)]
	flame_lean = FLAME_LEANS[_rng.randi_range(0, FLAME_LEANS.size() - 1)]
	queue_redraw()


## Whether the flame is running (it stops while the candle isn't shown).
func is_flickering() -> bool:
	return is_processing()


## The flame's row widths from the tip down, for a height: odd widths
## (centred on one pixel), narrow at the tip, widest low down, round at the
## foot.
static func flame_rows(height: int, width := FLAME_WIDTH) -> Array:
	var rows := []
	for row in height:
		var t := (row + 0.5) / height
		var w := 0.0
		if t < 0.75:
			w = width * pow(t, 0.7)
		else:
			var foot := (t - 0.75) / 0.25
			w = width * sqrt(maxf(1.0 - foot * foot, 0.0))
		rows.append(maxi(1, 2 * roundi((w - 1.0) / 2.0) + 1))
	return rows


func _draw() -> void:
	var box: Vector2i = BIG_SIZE if big else SMALL_SIZE
	var origin := Vector2i(((size - Vector2(box)) / 2.0).floor())
	if big:
		_draw_big(origin)
	else:
		_draw_small(origin)


func _draw_big(origin: Vector2i) -> void:
	var cx := origin.x + BIG_SIZE.x / 2
	var body_top := origin.y + BODY_TOP
	var inner := _grey(GLOW_INNER)
	var outer := _grey(GLOW_OUTER)
	for point in _glow_outer:
		_pixel(origin + Vector2i(point), outer)
	for point in _glow_inner:
		_pixel(origin + Vector2i(point), inner)
	var saucer_y := origin.y + BIG_SIZE.y - 4
	_rect(cx - 14, saucer_y, 29, 1, _grey(OUTLINE))
	_rect(cx - 15, saucer_y + 1, 31, 2, _grey(SAUCER))
	_rect(cx - 13, saucer_y + 3, 27, 1, _grey(SAUCER))
	var left := cx - BODY_WIDTH / 2
	var body_height := saucer_y - body_top
	_rect(left, body_top, BODY_WIDTH, body_height, _grey(OUTLINE))
	_rect(left + 1, body_top + 1, BODY_WIDTH - 2, body_height - 1, _grey(BODY))
	_rect(left + 3, body_top + 3, 2, body_height - 6, _grey(HIGHLIGHT))
	_rect(cx, body_top - 3, 1, 3, _grey(WICK))
	_draw_flame(cx, body_top - 3, flame_height, flame_lean, true)


func _draw_small(origin: Vector2i) -> void:
	var cx := origin.x + SMALL_SIZE.x / 2
	var body_top := origin.y + 8
	_rect(cx - 2, body_top, 5, SMALL_SIZE.y - 8, _grey(OUTLINE))
	_rect(cx - 1, body_top + 1, 3, SMALL_SIZE.y - 9, _grey(BODY))
	_rect(cx, body_top - 1, 1, 1, _grey(WICK))
	_draw_flame(cx, body_top - 2, 5, 0, false)


# The flame with its foot on row `foot`, centred on column cx; lean moves
# the tip up to two pixels.
func _draw_flame(cx: int, foot: int, height: int, lean: int, core: bool) -> void:
	var rows := flame_rows(height, FLAME_WIDTH if big else 3)
	var flame := _grey(FLAME)
	var core_grey := _grey(CORE)
	for row in rows.size():
		var t := (row + 0.5) / rows.size()
		var shift := roundi(lean * 2.0 * pow(1.0 - t, 1.5))
		var w: int = rows[row]
		var y := foot - rows.size() + 1 + row
		_rect(cx - w / 2 + shift, y, w, 1, flame)
		if core and w >= 5 and t > 0.6:
			_rect(cx - (w - 4) / 2 + shift, y, w - 4, 1, core_grey)


func _make_glow() -> void:
	var centre := Vector2(BIG_SIZE.x / 2, BODY_TOP - GLOW_RISE) + Vector2(0.5, 0.5)
	for y in BIG_SIZE.y:
		for x in BIG_SIZE.x:
			if (x + y) % 2 != 0:
				continue
			var offset := Vector2(x, y) + Vector2(0.5, 0.5) - centre
			var inner := pow(offset.x / GLOW_INNER_RADII.x, 2) + pow(offset.y / GLOW_INNER_RADII.y, 2)
			var outer := pow(offset.x / GLOW_OUTER_RADII.x, 2) + pow(offset.y / GLOW_OUTER_RADII.y, 2)
			if inner <= 1.0:
				_glow_inner.append(Vector2(x, y))
			elif outer <= 1.0:
				_glow_outer.append(Vector2(x, y))


func _grey(token: String) -> Color:
	return THEME.get_color(token, "MechTokens")


func _pixel(at: Vector2i, color: Color) -> void:
	draw_rect(Rect2(at, Vector2.ONE), color)


func _rect(x: int, y: int, w: int, h: int, color: Color) -> void:
	if w > 0 and h > 0:
		draw_rect(Rect2(x, y, w, h), color)
