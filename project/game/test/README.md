# Automated tests

Every suite in `suites/` checks one part of the game. Run them often: a failing
test means something that used to work doesn't any more.

## Running

| How | What runs |
|---|---|
| Double-click `run_tests.bat` in the repo root | every suite |
| `run_tests.bat --fast` | every suite except slow ones (whole-game simulations) |
| `run_tests.bat --suite=Hangar,Wreck` | suites whose name contains one of these |
| Editor: open `game/test/RunAllTests.tscn`, press F6 | every suite, results in Output |
| Editor: open one suite's scene, press F6 | just that suite |
| Committing (GitHub Desktop or git) | the fast suites, via the pre-commit hook |

The report ends with `RESULT: PASSED` or `RESULT: FAILED` and a list of what
failed. From the command line the exit code is 0 or 1.

**Pre-commit hook:** once per clone, run
`git config core.hooksPath tools/git-hooks`. Then every commit that touches
`project/` runs the fast suites first and is blocked if one fails (full log in
`test-results.log`). It needs the Godot console exe next to the repo
(`Godot_v*_win64_console.exe`) or a `GODOT` environment variable; without one
it skips with a message.

## What a test run guarantees

- **Your real save is never touched.** Each suite snapshots progress, story
  and the current mission, turns autosave off, makes FileManager refuse to
  save, and restores everything afterwards.
- **Errors fail tests.** Any script error, `push_error` or engine error while
  a case runs fails that case, even if all its checks passed. Known harmless
  engine noise is listed in `framework/TestErrorWatch.gd` (`ALLOWED`).
- **Game time runs 4x faster** so timers don't slow the run (a suite can set
  `time_scale` lower).
- **Scenes never change under the runner.** While tests run,
  `TransitionManager.transition_to` only records the target in
  `TransitionManager.captured` (so a test can check "Continue goes to the main
  menu"). A suite opens the next screen itself.
- **Nothing hangs.** A case that doesn't finish within 60 seconds (a script
  error stopped it, or it's stuck waiting) fails; a whole run over 10 minutes
  is stopped and fails.

## Writing a suite

Add `suites/MyThingTest.gd` and a scene `suites/MyThingTest.tscn` (a single
Node with the script). The runner finds it automatically.

```gdscript
extends TestSuite

# MyThingTest: what this suite covers, in a sentence or two.


func run_tests() -> void:
	await case("does the thing", _test_thing)


func before_each() -> void:   # optional: reset state before every case
	PlayerProgress.reset()


func _test_thing() -> void:
	check(1 + 1 == 2, "maths works")
	check_eq(PlayerProgress.get_money(), 0.0, "starts broke")
	expect_error("planned")          # the next error containing "planned" is OK
	await wait_until(func(): return some_condition(), 5.0)
```

Mark a whole-game simulation `slow = true` (in `_init`) so the pre-commit hook
skips it.

## Known issues

A problem that's been reported but not fixed yet (often in someone else's
code) can be listed in the suite's `known_issues` (set in `_init`): any failure
whose text contains a key shows under "Known issues" in the report instead of
failing the run. When one stops happening, the report says so; remove the
entry then. Use this for flagged problems only, never to hide a new failure.

```gdscript
func _init() -> void:
	known_issues = {
		"res://game/some/Scene.tscn": "what is wrong; who flagged it and when",
	}
```

## What's covered

| Suite | Covers |
|---|---|
| BootAndMenusTest | Intro loads the profile, main-menu buttons, incomplete-mecha guard, loss notice |
| ContentScenesTest | every script compiles, every scene loads |
| ExpeditionHudTest | mission tracker, load readout, extraction summary |
| ExpeditionRunTest *(slow)* | a real Expedition: spawn, shooting, wrecks and loot, extraction, death, pause, quitting |
| GameLoopTest *(slow)* | Hangar -> Expedition -> Hangar with the player's gear and loot |
| HangarTest | Hangar windows, recycling, Materials window, leave guard, swapping parts |
| LootTableTest | loot tables, tiers, containers |
| NpcDesignsTest | every enemy design is valid and builds |
| OtherModesTest *(slow)* | Store, Ladder, Arena fights start and run |
| PartsTest | every part's data, equipping, every weapon fires |
| PlayerProgressTest | money, stash, stakes, materials, recycling, required parts |
| SaveFileTest | saving/loading on disk, backup recovery, abandoned runs on boot |
| StoryDirectorTest | story beats, flags, triggers, missions |
| WreckTest | wreck loot, weapon drops, Take / Take all |

Not covered: real mouse input (drag-and-drop is tested through the same code
a drop calls, not the mouse tracking), audio, and how things look.

Test saves go to `user://test/` (deleted after each suite); FileManager is
pointed there for every suite, so the real `user://profile.save` can't be
read or written by a test.

## Files

- `framework/TestSuite.gd`: base class (checks, cases, waiting, state safety)
- `framework/TestSession.gd`: runs suites, prints the report, options
- `framework/TestErrorWatch.gd`: turns Godot errors into failures
- `framework/TestRunner.gd` + `RunAllTests.tscn`: run everything
- `tools/git-hooks/pre-commit` and `run_tests.bat` (repo root)
