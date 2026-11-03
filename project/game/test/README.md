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

The report ends with `RESULT: PASSED` or `RESULT: FAILED` and a list of what
failed. From the command line the exit code is 0 or 1.

Tests only run when you start them; committing doesn't run them.
`run_tests.bat` needs the Godot console exe next to the repo
(`Godot_v*_win64_console.exe`) or a `GODOT` environment variable.

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

Mark a whole-game simulation `slow = true` (in `_init`) so `--fast` skips it.

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
| AoEDesignatorTest | shoulder weapons with a designator: the MA-GL44's data, the designator clamped to range and look angle, every reason a slot can't fire at a point, a salvo's rounds, ammo, heat, cooldown and reload, NPCs' plain shoot() going through the same rules, a direct-fire designator stopping at a wall, hold / release / reload-to-cancel, INDOORS on the HUD |
| ArtilleryTest | the mortar, MLRS and rocket launcher: their data and salvo heat, minimum and maximum range (also for NPCs' shoot()), a barrage spread over time, barrels and the circle, mortar shells over a building onto their points, flat rockets stopping at a wall or a mecha in the way or going off on their points |
| BarksTest | NPC barks: the line file, named lines before the type's and generic ones, only in the player's earshot, per-NPC and shared cooldowns, events with no chance, each event's trigger, loot shouts and help calls going to Local, StageActorSay making an actor speak |
| BootAndMenusTest | Intro loads the profile, main-menu buttons, incomplete-mecha guard, loss notice |
| CannonTest | the shoulder cannon and howitzer: their data and shot heat, the cannon's line always reaching full range in the aimed direction (also for NPCs), its shell flying along the line into a mecha, howitzer rounds landing in a square box lined up with the line, a howitzer shell over a building into its box |
| ContactsTest | contacts (ContactStore): finding reports by kind, source, liveness and distance, one per body and source, unreported contacts turning into ghosts and going, freed bodies, paused mechas' contacts not ageing, the player's and NPCs' sight writing contacts, vision through walls, ping markers and edge arrows on the HUD, the all_contacts debug view |
| ContentScenesTest | every script compiles, every scene loads |
| EconomyTest | credits: selling at half value (stacks, parts, weapons), never mid-run, nothing for worthless things, Sell all salvage leaving parts, what the cargo would sell for, the Sell menu actions; the repair bill on a real mecha (nothing undamaged, a quarter of what each damaged section is worth), debt from repairs and paying it off |
| EntityTest | Entities (creatures): bullets, blasts and armour; bites by facing; Stalker pack hunting, fleeing, scattering, hearing gunfire; Spitter range and acid; Brute charge, ram, stomp, stun, rage; Cysts waking, hatching leashed guards, brood limit; death; bio loot and carcasses |
| ExpeditionHudTest | mission tracker, weight readout, exit marker, extraction debrief with its sale value, repair bill, credits and debt note |
| ExpeditionRunTest *(slow)* | a real Expedition: spawn, the map's site name, shooting, wrecks and loot, extraction (with the repair bill charged), death and the written-off debrief, pause, quitting; Entities and Cysts placed, NPCs fighting them, carcasses |
| FabricatorTest | blueprints and the Fabricator: recycling copies of a part teaches its blueprint (one Refined copy is enough, salvage teaches nothing), build costs, what stops a build (no Fabricator, no blueprint, high tech below Mk II, materials, credits, stash room), building into the stash, blueprints saving, the FAB window |
| FacilitiesTest | Hangar facilities: where they start, upgrade costs and refusals (credits, materials, top level, debt), the Recycler raising yields, the Workshop cutting a real mecha's repair bill, the Stash growing with items left in place (and on load), the Fabricator's grade odds, levels saving, the FAC window |
| GameLoopTest *(slow)* | Hangar -> Expedition -> Hangar with the player's gear and loot |
| GradesTest | part grades: the grade table, wreck weapon drops rolling grades at their odds, grade scaling value, recycling and repairs, grades scaling a real mecha's summed stats and walk speed (and the stats panel the same), saving and loading grades, old saves as Standard, names showing the grade, a lost run resetting them |
| HangarTest | Hangar windows, recycling, Materials window, selling and the credits readout (debt shown inverted), leave guard, swapping parts, a part keeping its grade on and off the mecha, closing the game mid-refit |
| InternalBayTest | the internal bay: the slot in designs, saves, the stash, the Equipment window and stats, ECM coming from the ECM module, wards (placed or thrown, charges, cooldown, pings), drones flying and self-destructing, devices destroyed by shots and blasts, NPCs using the same call, the player's tap / hold / aim / cancel / toggle, the HUD row and alert, who sees which devices |
| IndirectFireTest | indirect rounds flying over a building and a truck onto their point, roof bursts hurting no one, open-ground bursts, a shell landing right on a mecha hurting it, direct rounds going off at their landing point, building walls (generated and hand-made) blocking blasts both ways, a blast hurting its firer |
| LaserTest | the sweep laser: its data, the rectangle always reaching full range, the beam hitting every mecha in it once for a fixed amount (and nothing beside or behind it, nor the firer), the front sweeping near to far, the beam stopping at a wall |
| LocalPilotsTest | Local: join, death and extraction lines, Anonymous pilots, unique callsigns, broadcasts, the player's callsign and Anonymous setting saving, reputation for unprovoked kills, the HUD feed, quick chat, the LOC app, the LOG app's LOCAL tab, a real match |
| LootTableTest | loot tables, tiers, containers, bio salvage and Entity tables |
| MineTest | mine layers and mines: their data, a contact mine going off only when driven over, a burst of sensor mines landing in the circle and going off when a mecha comes near, a magnetic mine crawling to a mecha, a direct-fire mine bouncing off a wall, mines lasting with no limit on their number, mines_near() for NPC code, a settled mine running no process or physics, mines bursting on a roof |
| MissileTest | the cluster missile and VLS launchers: their data, firing at a locked target whatever the designator, gimbal or minimum range (up to max range), unlocked cluster submunitions dropping onto points in the circle (also when a wall stops the missile), locked VLS missiles over a building onto a target that moved, unlocked VLS missiles landing in the circle |
| MapStreamingTest | map chunks hidden away from the camera, streamed scenes loading near a mecha and freed when it leaves, their loot crates keeping their contents across reloads (no refilling), far NPCs thinking less often |
| MapVehiclesTest | map vehicles: mechas shoving cars, fire engines holding them back, cars shunting each other and stopping at walls, vehicles blocking shots by chance, not blocking sight, collision only near mechas |
| MapWallsTest | building walls and foliage: walls block sight between outside and inside, each wall costs a shot 1 AP, grenades go off at walls, Entities can't see through walls, trees hide mechas, merged walls still count |
| NPCPerceptionTest | what NPCs know: targets only in sight, working from a last-known position and forgetting it, being shot giving the shooter away, roaming NPCs engaging what they spot, blind fire only through walls the round can pass, entering combat at the build's range (from its direct-fire weapons) |
| NPCSteeringTest | how NPCs move round vehicles and buildings: steering, pushing through or round cars, unsticking, routing through gaps, tanks trampling cars, circling in a fight, sprinting and dashing, cars destroyed by shots, blasts and dashes, spawns clear of vehicles |
| NpcDesignsTest | every enemy design is valid and builds |
| OtherModesTest *(slow)* | Store, Ladder, Arena fights start and run |
| PartsTest | every part's data (name, image, weight, size, price, tech tier and composition), equipping, every weapon fires |
| PlayerViewTest | what the player sees: mechas behind a building wall faded out, in-building and out-of-building sight (generated and hand-made buildings), Entities hidden too, nothing hidden while controls are locked |
| PlayerProgressTest | money, stash, stakes, materials, recycling, required parts |
| SandBodyTest | the sand creature looks (Coyote, Coyote Spitter, Fisher): building, walking, their attack moves, bursting into grains on death, the art bench |
| SaveFileTest | saving/loading on disk, a new profile's starting credits, backup recovery, abandoned runs on boot |
| SmokeTest | smoke clouds and the smoke launcher: a cloud thickening, blocking sight into, out of and through it and clearing, the player's view hiding mechas in and behind smoke, NPCs and Entities not seeing through it, tap screening the mecha itself and hold sending canisters to the designator, canisters leaving clouds |
| StageDemoTest *(slow)* | the demo cutscene in a real Expedition: beats in order, the stage camera, frozen bystanders, the spawned NPC and obstacle, handing control and actors back, skipping, F4 and map triggers, ending on the player's death |
| StageDirectorTest | cutscene building blocks: steps in order, waits, skipping, pausing, aborting, cinema bars, taking control, camera look-at/follow/hand-back, dialogue lines, actors walking and shooting |
| StoryDirectorTest | story beats, flags, triggers, missions |
| SweepTest | the sensor sweep: cone and range, walls not blocking it, kinds and counts only, ECM shortening it, heat and cooldown, the swept being told, creatures hearing it, the player aiming, widening, sweeping and cancelling, the HUD |
| TestArenaTest *(slow)* | the test arena that Arena Mode opens: its NPCs, buildings and vehicles, nothing at stake, dead NPCs replaced |
| VisionDevicesTest | the Seeker (following in a match only, showing what is near, humming, toggling, lost when shot down until refitted), flares, the Biosensor showing creatures only, decoys passing for a mecha to sweeps, wards and NPCs, the INT row |
| WorldInfoTest | heat trails (marks by chassis, warmth and cooling, the pool and NPC query), car alarms (set off once by a push, blinking, heard as a sound and an ALARM ping), kill records (built on death, shown beside the wreck's loot and closed with it) |
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
- `run_tests.bat` (repo root)
