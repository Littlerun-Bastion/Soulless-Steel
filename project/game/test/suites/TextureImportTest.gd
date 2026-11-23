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


const WORLD_ART := [
	"res://assets/images/mechas/",
	"res://assets/images/props/",
	"res://assets/images/buildings/",
	"res://assets/images/fx/",
	"res://assets/images/decals/",
	"res://assets/images/anims/",
	"res://assets/images/map/floor/",
	"res://assets/images/map/ground/",
	"res://assets/images/map/props/",
	"res://database/maps/",
	"res://database/buildings/",
]


func run_tests() -> void:
	await case("the large pictures are imported VRAM compressed", _test_compressed)
	await case("the world's art has mipmaps, to stay smooth as the camera pulls back", _test_world_mipmaps)


func _test_compressed() -> void:
	for path in COMPRESSED:
		var cfg := ConfigFile.new()
		if not check(cfg.load(path + ".import") == OK, "%s: has import settings" % path.get_file()):
			continue
		check_eq(int(cfg.get_value("params", "compress/mode", -1)), 2, "%s: VRAM compressed" % path.get_file())
		check(bool(cfg.get_value("params", "compress/high_quality", false)), "%s: high quality (BC7)" % path.get_file())
		var texture := load(path) as Texture2D
		check(texture != null and texture.get_width() > 0, "%s: loads" % path.get_file())


func _test_world_mipmaps() -> void:
	var missing: Array[String] = []
	var textures := []
	for dir in WORLD_ART:
		textures += _texture_imports(dir)
	for path in textures:
		var cfg := ConfigFile.new()
		cfg.load(path + ".import")
		if not bool(cfg.get_value("params", "mipmaps/generate", false)):
			missing.append(path.trim_prefix("res://"))

	check(textures.size() > 400, "the world's art was found (%d pictures)" % textures.size())
	check(missing.is_empty(), "every picture has mipmaps (%d without: %s)" % [missing.size(), missing.slice(0, 5)])
	var mecha := load("res://assets/images/mechas/legs/MSV-L3J/msv-l3j_lleg_main.png") as Texture2D
	check(mecha != null and mecha.get_image().has_mipmaps(), "and the imported pictures carry them")


func _texture_imports(dir: String) -> Array:
	var found := []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".import"):
			var cfg := ConfigFile.new()
			if cfg.load(dir + file) == OK and cfg.get_value("remap", "importer", "") == "texture":
				found.append(dir + file.trim_suffix(".import"))
	for sub in DirAccess.get_directories_at(dir):
		found += _texture_imports(dir + sub + "/")
	return found
