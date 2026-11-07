extends TestSuite

# ArenaMapsTest: ArenaManager keeps every map in database/maps/ by path and
# loads one only when it's asked for (get_map), so maps not being played hold
# no memory (map1 alone draws a 15000 px floor). set_map_to_load starts the
# next map loading in the background; get_current_map returns it. Every map
# still opens.


func _init() -> void:
	case_timeout = 120


func run_tests() -> void:
	await case("maps are known by path, not loaded at boot", _test_paths)
	await case("every map opens", _test_every_map)
	await case("the map set to load next opens from its background load", _test_next_map)


func _test_paths() -> void:
	check(ArenaManager.MAPS.size() > 0, "maps found")
	for map_name in ArenaManager.MAPS:
		var path = ArenaManager.MAPS[map_name]
		check(path is String and ResourceLoader.exists(path), "%s: a path to its scene" % map_name)
	if ArenaManager.MAPS.has("map1"):
		check(not ResourceLoader.has_cached(ArenaManager.MAPS["map1"]), "map1 isn't loaded while nothing uses it")


func _test_every_map() -> void:
	for map_name in ArenaManager.MAPS:
		var map: Node = ArenaManager.get_map(map_name)
		check(map != null, "%s opens" % map_name)
		if map:
			map.free()


func _test_next_map() -> void:
	var saved = ArenaManager.map_to_load
	ArenaManager.set_map_to_load("tutorial")
	var path: String = ArenaManager.MAPS["tutorial"]
	check(ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "it starts loading")
	var map: Node = ArenaManager.get_current_map()
	check(map != null, "and opens")
	check_eq(ArenaManager.map_to_load, false, "nothing is left set to load")
	if map:
		map.free()
	ArenaManager.map_to_load = saved
