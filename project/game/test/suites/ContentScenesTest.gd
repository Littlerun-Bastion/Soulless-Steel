extends TestSuite

# ContentScenesTest: every script in the game compiles, and every scene loads
# and can be instanced. Catches broken references (moved or deleted files,
# renamed nodes in inherited scenes, script parse errors) anywhere in the
# project, including places no other test opens.
#
# Scenes are only instanced, never added to the tree, so nothing runs: no
# expedition starts, no profile loads, no music plays.

const ROOTS := ["res://game/", "res://database/"]


func run_tests() -> void:
	await case("every script compiles", _test_scripts)
	await case("every scene loads and instances", _test_scenes)


func _test_scripts() -> void:
	var scripts := find_files(".gd")
	check(scripts.size() > 50, "found the game's scripts (%d)" % scripts.size())
	for path in scripts:
		var script = load(path)
		check(script is Script, "%s compiles" % path)
		_errors_belong_to(path)


func _test_scenes() -> void:
	var scenes := find_files(".tscn")
	check(scenes.size() > 100, "found the game's scenes (%d)" % scenes.size())
	for path in scenes:
		var packed = load(path)
		if check(packed is PackedScene, "%s loads" % path):
			var instance: Node = packed.instantiate()
			if check(instance != null, "%s instances" % path):
				instance.free()
		_errors_belong_to(path)


# Reports errors logged while handling one file against that file, so the
# report names the broken scene or script.
func _errors_belong_to(path: String) -> void:
	for error in errors.take_errors():
		check(false, "%s: %s" % [path, error])


# Every file with this extension under ROOTS (hidden folders like .godot are
# skipped by DirAccess).
static func find_files(extension: String) -> Array[String]:
	var found: Array[String] = []
	for root in ROOTS:
		_collect(root, extension, found)
	found.sort()
	return found


static func _collect(dir_path: String, extension: String, found: Array[String]) -> void:
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(extension):
			found.append(dir_path + file)
	for sub in DirAccess.get_directories_at(dir_path):
		_collect(dir_path + sub + "/", extension, found)
