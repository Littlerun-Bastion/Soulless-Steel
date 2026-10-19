extends TestSuite

# OtherModesTest: the screens and modes outside the Expedition loop still
# start and run for a few seconds without errors: the Store, the Ladder, and
# an Arena fight (Exhibition against a random NPC, Challenge against the
# current challenger). Arena is parked, so this is a smoke test, not a
# playthrough.

const STORE := preload("res://game/ui/customizer/Storepage.tscn")
const LADDER := preload("res://game/ui/ladder/Ladder.tscn")
const ARENA := preload("res://game/arena/Arena.tscn")
const ARENA_MAP := "arena_oldgate"
const RUN_SECONDS := 3.0

var _saved_arena := {}


func _init() -> void:
	slow = true
	known_issues = {
		"given the tags: [\"type_1\"]": "Lady Volk's part ids don't exist (see NpcDesignsTest); flagged 2026-10-19",
		"given the tags: [\"type_2\"]": "Lady Volk's part ids don't exist (see NpcDesignsTest); flagged 2026-10-19",
		"given the tags: [\"test1\"]": "Lady Volk's part ids don't exist (see NpcDesignsTest); flagged 2026-10-19",
	}


func run_tests() -> void:
	_saved_arena = {"mode": ArenaManager.mode, "map": ArenaManager.map_to_load}
	await case("the Store opens and runs", func(): await _run_scene(STORE.instantiate(), "Store"))
	await case("the Ladder opens and runs", func(): await _run_scene(LADDER.instantiate(), "Ladder"))
	await case("an Arena exhibition fight runs", func(): await _run_arena("Exhibition"))
	await case("an Arena challenge fight runs", func(): await _run_arena("Challenge"))
	ArenaManager.mode = _saved_arena["mode"]
	ArenaManager.map_to_load = _saved_arena["map"]


func _run_scene(scene: Node, label: String) -> void:
	add_child(scene)
	await wait_seconds(RUN_SECONDS)
	check(is_instance_valid(scene) and scene.is_inside_tree(), "%s is still running" % label)
	check(TransitionManager.captured.is_empty(), "%s didn't leave on its own" % label)
	scene.queue_free()
	await wait_frames(2)


func _run_arena(mode: String) -> void:
	PlayerProgress.reset()
	ArenaManager.mode = mode
	ArenaManager.set_map_to_load(ARENA_MAP)
	var arena = ARENA.instantiate()
	add_child(arena)
	var started := await wait_until(func(): return arena.player != null and arena.all_mechas.size() > 1, 15.0)
	check(started, "%s: the player and an opponent spawned" % mode)
	await wait_seconds(RUN_SECONDS)
	check(is_instance_valid(arena.player), "%s: the player is still in the fight" % mode)
	arena.queue_free()
	await wait_frames(2)
