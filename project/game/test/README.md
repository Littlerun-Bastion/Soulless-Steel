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
| BootAndMenusTest | Intro loads the profile, main-menu buttons, incomplete-mecha guard, loss notice |
| CannonTest | the shoulder cannon and howitzer: their data and shot heat, the cannon's line always reaching full range in the aimed direction (also for NPCs), its shell flying along the line into a mecha, howitzer rounds landing in a square box lined up with the line, a howitzer shell over a building into its box |
| CompanionTest *(slow)* | the player's companions: a companion following the player into its slot and fighting what it sees, follow and hold orders keeping it out of a fight while it fires on the move, an attack order giving it the player's target once the callout lands and ending with the target, regroup ending on arrival, its callouts pinging the player's contact store; standing (hostility, reputation, being spared), the offer as a bark, a Local line and the scene's prompt, once, the help-call chances by personality; the orders menu's key and numbers; a companion shot by the player leaving, one left far behind leaving in time, a Rat turning on a weak and lonely player, a Guardian joining a pilot it sees attacked; a real Test Arena with the starting companion, an offer taken and one declined on the keys, a hold order acknowledged |
| ContentScenesTest | every script compiles, every scene loads |
| EconomyTest | credits: selling at half value (stacks, parts, weapons), never mid-run, nothing for worthless things, Sell all salvage leaving parts, what the cargo would sell for, the Sell menu actions; the repair bill on a real mecha (nothing undamaged, a quarter of what each damaged section is worth), debt from repairs and paying it off |
| EntityTest | Entities (creatures): bullets, blasts and armour; bites by facing; Stalker pack hunting, fleeing, scattering, hearing gunfire; Spitter range and acid; Brute charge, ram, stomp, stun, rage; Cysts waking, hatching leashed guards, brood limit; death; bio loot and carcasses |
| ExpeditionHudTest | mission tracker, weight readout, exit marker, extraction debrief with its sale value, repair bill, credits and debt note |
| ExpeditionRunTest *(slow)* | a real Expedition: spawn, the map's site name, shooting, wrecks and loot, extraction (with the repair bill charged), death and the written-off debrief, pause, quitting; Entities and Cysts placed, NPCs fighting them, carcasses |
| FabricatorTest | blueprints and the Fabricator: recycling copies of a part teaches its blueprint (one Refined copy is enough, salvage teaches nothing), build costs, what stops a build (no Fabricator, no blueprint, high tech below Mk II, materials, credits, stash room), building into the stash, blueprints saving, the FAB window |
| FacilitiesTest | Hangar facilities: where they start, upgrade costs and refusals (credits, materials, top level, debt), the Recycler raising yields, the Workshop cutting a real mecha's repair bill, the Stash growing with items left in place (and on load), the Fabricator's grade odds, levels saving, the FAC window |
| FlagTest | the Flag, panic and mines: a Flag raised at once and lowered with a wind-up, locking the weapons but not smoke or the bay, the emergency Flag and the HUD, the key, who pressed a mecha into its Flag; NPCs respecting a Flag by personality and the reputation roll; treachery (lowering a Flag raised by choice and attacking) and its cost, witnesses, the cost of killing a Flagged pilot and the reward for sparing one; surrender and a Rat's fake; a Rat's execution and stalk, a Guardian's protection; panic's rises, falls and effect on aim; mines seen or missed by panic; the stage step |
| FlagFixTest | the emergency Flag: the core shell keeping the cockpit from hits, blasts and overheat, both ways in (core shell, hp at 0) starting one grace window of three to five seconds in which nothing hurts the mecha, killing it after the window, the weapons locked, the emergency_flagged signal; the splatter thrown away from the attacker, the death pool and the stain cap; hits on internal components leaking drops, a destroying hit throwing a small splatter and a full droplet jet along it, bleeding from internal damage rather than low hp; a dead mecha's body showing every fitted part (single chassis too) but the one or two that came off, never the core, chassis or a weapon in the loot, being solid (blocking movement, shots and sight lines, but not where a part came off, also when left inside a physics callback) and being in the tree before the mecha is freed; NPCs dropping a Flagged target, a Rat holding fire through the grace window |
| GameLoopTest *(slow)* | Hangar -> Expedition -> Hangar with the player's gear and loot |
| GradesTest | part grades: the grade table, wreck weapon drops rolling grades at their odds, grade scaling value, recycling and repairs, grades scaling a real mecha's summed stats and walk speed (and the stats panel the same), saving and loading grades, old saves as Standard, names showing the grade, a lost run resetting them |
| HangarTest | Hangar windows, recycling, Materials window, selling and the credits readout (debt shown inverted), leave guard, swapping parts, a part keeping its grade on and off the mecha, closing the game mid-refit |
| InfoSystemsTest | NPCs using the information systems: a Local help call or loot shout as a lead at a spot blurred once within 150 m, kept a minute, acted on instead of the true position; help by personality (a Guardian's roll, a Hunter never), a hated caller unanswered, a squadmate under fire and hurt helped at once where it is, a helper turning on whoever hits the caller; a Hunter vulturing a fight heard, dark, and preying on the survivor once it is quiet, not when running hot, a Scavenger never; a Professional scouting with a sweep before a long trip or one into ground it took fire on, once in a while; a Rat's fake loot shout from an ambush and its luring help call; an Anonymous pilot's extra hostility on first sight; being swept making an NPC suspicious of everyone in sight, a Scavenger keeping away from the spot and wandering clear of it, a Hunter sweeping back; a destroyed ward as a lead to investigate; car alarms kept by Hunters and the greedy, ignored by others, kept away from by Scavengers; a tagged squad's size read off the roster and weighing on a fight; a Hunter's search following the warmest heat mark a step along its heading; any wreck teaching its killer's name without a grudge |
| IndirectFireTest | indirect rounds flying over a building and a truck onto their point, roof bursts hurting no one, open-ground bursts, a shell landing right on a mecha hurting it, direct rounds going off at their landing point, building walls (generated and hand-made) blocking blasts both ways, a blast hurting its firer |
| LaserTest | the sweep laser: its data, the rectangle always reaching full range, the beam hitting every mecha in it once for a fixed amount (and nothing beside or behind it, nor the firer), the front sweeping near to far, the beam stopping at a wall |
| LootTableTest | loot tables, tiers, containers, bio salvage and Entity tables |
| MineTest | mine layers and mines: their data, a contact mine going off only when driven over, a burst of sensor mines landing in the circle and going off when a mecha comes near, a magnetic mine crawling to a mecha, a direct-fire mine bouncing off a wall, mines lasting with no limit on their number, mines_near() for NPC code, a settled mine running no process or physics, mines bursting on a roof |
| MissileTest | the cluster missile and VLS launchers: their data, firing at a locked target whatever the designator, gimbal or minimum range (up to max range), unlocked cluster submunitions dropping onto points in the circle (also when a wall stops the missile), locked VLS missiles over a building onto a target that moved, unlocked VLS missiles landing in the circle |
| MapStreamingTest | map chunks hidden away from the camera, streamed scenes loading near a mecha and freed when it leaves, their loot crates keeping their contents across reloads (no refilling), far NPCs thinking less often |
| MapVehiclesTest | map vehicles: mechas shoving cars, fire engines holding them back, cars shunting each other and stopping at walls, vehicles blocking shots by chance, not blocking sight, collision only near mechas |
| MapWallsTest | building walls and foliage: walls block sight between outside and inside, each wall costs a shot 1 AP, grenades go off at walls, Entities can't see through walls, trees hide mechas, merged walls still count |
| NPCIntentTest | how an NPC picks what to do: each of the fourteen intents winning where its old state was entered, the commitment bonus, minimum time and ties, the emergency Flag making an NPC flee from any intent (not a Rat) and dark, a flight that goes on while nobody shoots and ends far away and left alone, a lost target searched for at its last-known position and never its true one, the think-time probe and the intent log |
| NPCSteeringTest | how NPCs move round vehicles and buildings: steering, pushing through or round cars, unsticking, routing through gaps, tanks trampling cars, circling in a fight, sprinting and dashing, cars destroyed by shots, blasts and dashes, spawns clear of vehicles |
| NPCThinkCostTest *(slow)* | the think-time probe on Helwan with twelve NPCs: prints the microseconds per NPC per thinking frame (never fails on a timing) |
| NpcDesignsTest | every enemy design is valid and builds |
| OtherModesTest *(slow)* | Store, Ladder, Arena fights start and run |
| PartsTest | every part's data (name, image, weight, size, price, tech tier and composition), equipping, every weapon fires |
| PersonalityTest | the personality table and the voice: a Hunter never loots and is provoked by a Flagged mech that crowds it or keeps facing it (not one that looks away; a Professional isn't), a Guardian protecting a Flagged or badly hurt squadmate before a stranger and yielding only all but broken while a squadmate stands, a Professional extracting on schedule and a Scavenger on its greed's roll; every bark event with lines for every personality type and "any", a chance, the panicked variants with chances, and a panicked NPC using the panicked line |
| PlayerViewTest | what the player sees: mechas behind a building wall faded out, in-building and out-of-building sight (generated and hand-made buildings), Entities hidden too, nothing hidden while controls are locked |
| PlayerProgressTest | money, stash, stakes, materials, recycling, required parts |
| SandBodyTest | the sand creature looks (Coyote, Coyote Spitter, Fisher): building, walking, their attack moves, bursting into grains on death, the art bench |
| SaveFileTest | saving/loading on disk, a new profile's starting credits, backup recovery, abandoned runs on boot |
| SquadTest | NPC squads: a squad's designs (direct fire first, support third) and the personality draw, the tag in Local and none for an Anonymous squad; members' spaced slots beside and behind the leader, never in a line, and a member following into its slot, a straggler called back; the roles dealt, the flanker reaching 60° off the anchor's bearing while the anchor holds its range lit, the support member turning to put smoke on a mate that falls back; a callout landing in squadmates' stores after the delay and a mate taking it as its target; the leader's death passing the lead on, raising panic and judged by loyalty; a treacherous Rat leaving and turning on a hurt mate; shooting a member turning the squad on the shooter and a mate's stray round forgiven; a fallen member's wreck naming its killer for the whole squad |
| SmokeTest | smoke clouds and the smoke launcher: a cloud thickening, blocking sight into, out of and through it and clearing, the player's view hiding mechas in and behind smoke, NPCs and Entities not seeing through it, tap screening the mecha itself and hold sending canisters to the designator, canisters leaving clouds |
| StageDemoTest *(slow)* | the demo cutscene in a real Expedition: beats in order, the stage camera, frozen bystanders, the spawned NPC and obstacle, handing control and actors back, skipping, F4 and map triggers, ending on the player's death |
| StageDirectorTest | cutscene building blocks: steps in order, waits, skipping, pausing, aborting, cinema bars, taking control, camera look-at/follow/hand-back, dialogue lines, actors walking and shooting |
| StoryDirectorTest | story beats, flags, triggers, missions |
| TacticsTest | the position picker and the fire controller: the range band, cover with a line of fire, no picks inside buildings, the cover cache; a 1v1 in the open never closing to point-blank; a mortar firing at a last-known spot behind a building but never into one; a lost target searched for with a sweep, a drone and the lights off; overheating breaking contact with smoke, a decoy and a mine until cool; a Professional holding a poor shot and hot guns bursting; an idle NPC shooting an enemy ward |
| TestArenaTest *(slow)* | the test arena that Arena Mode opens: its NPCs (every personality type, a squad, the player's companion), buildings and vehicles, nothing at stake, dead NPCs replaced |
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
