class_name MapDistricts
extends Resource

# The district of every square of a map, as the generator tagged it (or as a
# DistrictZone painted over it). codes holds one byte per cell, row by row:
# cell (x, y) is codes[y * size.x + x], and covers the square of cell_px
# whose top-left corner is origin + Vector2(x, y) * cell_px, in map px.

enum { RESIDENTIAL, INDUSTRIAL, MARKET, FARMLAND }

const NAMES := ["residential", "industrial", "market", "farmland"]

@export var origin := Vector2.ZERO
@export var cell_px := 500.0
@export var size := Vector2i.ZERO
@export var codes := PackedByteArray()


static func code_of(district_name: String) -> int:
	return maxi(NAMES.find(district_name), 0)


static func name_of(code: int) -> String:
	return NAMES[code] if code >= 0 and code < NAMES.size() else NAMES[RESIDENTIAL]


# The district at a position in map px. Outside the grid: residential.
func at(pos: Vector2) -> int:
	if size.x <= 0 or size.y <= 0:
		return RESIDENTIAL
	var c := Vector2i(((pos - origin) / cell_px).floor())
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return RESIDENTIAL
	return codes[c.y * size.x + c.x]


func name_at(pos: Vector2) -> String:
	return name_of(at(pos))
