class_name SteelapediaLogo
extends Control

## Steelapedia's logo: a globe of riveted steel plates with one plate
## missing, lit from the top left, in the theme's greys (MechTokens). The
## picture is made once, pixel by pixel, and drawn at 1:1 in the middle of
## the control.
##
## Each pixel inside the disc is a point on the sphere. Turned by TILT and
## SPIN into the globe's own frame, its latitude and longitude name its plate
## (PLATE radians a side). A pixel whose right or lower neighbour is on
## another plate is a seam, and so is one beside the edge or the missing
## plate; the corners of each plate get rivets. The rest takes a tone from
## its light (the normal against LIGHT, a little lighter or darker on every
## other plate), dithered with a 4x4 Bayer matrix.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const DIAMETER := 104
const TILT := 0.42
const SPIN := 0.35
const PLATE := PI / 6.0
## The missing plate: (latitude band from the south pole, longitude column).
const MISSING := Vector2i(4, 7)
const LIGHT := Vector3(-0.55, 0.65, 0.52)
## Light above which each tone is used, lightest first (MechTokens names).
const TONES := [["g6", 0.55], ["g5", 0.2], ["g4", -0.2], ["g3", -2.0]]
const SEAM := "g3"
const DITHER := 0.18
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const OUTSIDE := -1
const HOLE := -2

static var _texture: ImageTexture = null


func _init() -> void:
	custom_minimum_size = Vector2(DIAMETER + 2, DIAMETER + 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	var shown := picture()
	draw_texture(shown, ((size - Vector2(shown.get_size())) / 2.0).floor())


## The logo's picture (made on first use).
static func picture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_make())
	return _texture


static func _make() -> Image:
	var side := DIAMETER + 2
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var radius := DIAMETER / 2.0
	var centre := Vector2(side, side) / 2.0
	var light := LIGHT.normalized()
	var plates := PackedInt32Array()
	plates.resize(side * side)
	plates.fill(OUTSIDE)
	var shades := PackedFloat32Array()
	shades.resize(side * side)
	var rivets := PackedByteArray()
	rivets.resize(side * side)
	for y in side:
		for x in side:
			var p := (Vector2(x + 0.5, y + 0.5) - centre) / radius
			var d := p.length_squared()
			if d > 1.0:
				continue
			var normal := Vector3(p.x, -p.y, sqrt(1.0 - d))
			var turned := normal.rotated(Vector3.RIGHT, TILT).rotated(Vector3.UP, SPIN)
			var lat := asin(clampf(turned.y, -1.0, 1.0)) + PI / 2.0
			var lon := atan2(turned.x, turned.z) + PI
			var band := int(lat / PLATE)
			var column := int(lon / PLATE)
			var i := y * side + x
			plates[i] = HOLE if Vector2i(band, column) == MISSING else band * 32 + column
			shades[i] = normal.dot(light) + (0.08 if (band + column) % 2 == 0 else -0.04)
			var u := fposmod(lon, PLATE) / PLATE
			var v := fposmod(lat, PLATE) / PLATE
			if (absf(u - 0.18) < 0.05 or absf(u - 0.82) < 0.05) and (absf(v - 0.2) < 0.06 or absf(v - 0.8) < 0.06):
				rivets[i] = 1
	var seam: Color = THEME.get_color(SEAM, "MechTokens")
	var tones := TONES.map(func(t): return [THEME.get_color(t[0], "MechTokens"), float(t[1])])
	for y in side:
		for x in side:
			var i := y * side + x
			var plate := plates[i]
			if plate < 0:
				continue
			if rivets[i] == 1 or _is_seam(plates, side, x, y, plate):
				image.set_pixel(x, y, seam)
				continue
			var shade: float = shades[i] + (BAYER[(y % 4) * 4 + (x % 4)] / 16.0 - 0.5) * DITHER
			for tone in tones:
				if shade > tone[1]:
					image.set_pixel(x, y, tone[0])
					break
	return image


# Whether the pixel at x, y on plate is a seam: its right or lower neighbour
# is on another plate, or any neighbour is outside the globe or in the hole.
static func _is_seam(plates: PackedInt32Array, side: int, x: int, y: int, plate: int) -> bool:
	for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or ny < 0 or nx >= side or ny >= side:
			return true
		var other := plates[ny * side + nx]
		if other < 0:
			return true
		if other != plate and (offset.x > 0 or offset.y > 0):
			return true
	return false
