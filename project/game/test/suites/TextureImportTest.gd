extends TestSuite

# TextureImportTest: the large pictures the game loads are VRAM compressed
# (BC7: compress/mode 2, high quality), a quarter of the video memory of
# lossless with no visible difference (worst channel error a few levels in
# 255). Masks and other data textures, and art nothing loads, are left as
# they are.

const COMPRESSED := [
	"res://assets/images/ui/menu/grid.png",
	"res://assets/images/props/exit point.png",
	"res://database/maps/arena_oldgate2.png",
	"res://assets/images/map/floor/tutorial_room.png",
	"res://assets/images/map/floor/TestArenaBox.png",
	"res://assets/images/ui/player_ui/ui_vignette.png",
]


func run_tests() -> void:
	await case("the large pictures are imported VRAM compressed", _test_compressed)


func _test_compressed() -> void:
	for path in COMPRESSED:
		var cfg := ConfigFile.new()
		if not check(cfg.load(path + ".import") == OK, "%s: has import settings" % path.get_file()):
			continue
		check_eq(int(cfg.get_value("params", "compress/mode", -1)), 2, "%s: VRAM compressed" % path.get_file())
		check(bool(cfg.get_value("params", "compress/high_quality", false)), "%s: high quality (BC7)" % path.get_file())
		var texture := load(path) as Texture2D
		check(texture != null and texture.get_width() > 0, "%s: loads" % path.get_file())
