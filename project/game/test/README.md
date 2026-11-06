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
| DoctrineTest | the NPC engagement doctrine: each type's response to an UNKNOWN IR track, a shot wedge and a lock wedge, and identify running it (a Professional sweeping, then a lock search with nothing showing until it locks; a Scavenger leaving and keeping away; a Guardian lighting it up); the skill breakpoints (tools from 0.3, light discipline from 0.5, a lock search on a shot wedge and a lock back from 0.7, never a Rat) and the reaction delay; lights off when calm, steady under 0.5, the flash cycle from 0.5, the anchor lit, the flanker dark, a Rat dark but to execute; nervous NPCs firing or leaving by courage; identify ending on visual, loss and timeout, a watch with nothing to show for it after IDENTIFY_WATCH_TIME (one waiting on a drone not hurried), under engage with a target in sight; a lock warning noted, panic once locked, identify above a fight; the fairness rule (no track: no lock search, no aim, no approach); the new barks' lines |
| EconomyTest | credits: selling at half value (stacks, parts, weapons), never mid-run, nothing for worthless things, Sell all salvage leaving parts, what the cargo would sell for, the Sell menu actions; the repair bill on a real mecha (nothing undamaged, a quarter of what each damaged section is worth), debt from repairs and paying it off |
| EntityTest | the first Entity species, which the Expedition doesn't spawn (other suites use the Stalker as a stand-in Entity): bullets, blasts and armour; bites by facing; Stalker pack hunting, fleeing, scattering, hearing gunfire; Spitter range and acid; Brute charge, ram, stomp, stun, rage; Cysts waking, hatching leashed guards, brood limit; death; bio loot and carcasses |
| ExpeditionHudTest | mission tracker, weight readout, exit marker, extraction debrief with its sale value, repair bill, credits and debt note |
| ExpeditionRunTest *(slow)* | a real Expedition: spawn, the map's site name, shooting, wrecks and loot, extraction (with the repair bill charged), death and the written-off debrief, pause, quitting; Coyote packs (each with a Spitter, a Coyote leading), dormant Fishers and tick swarms placed and none of the first species, NPCs fighting Coyotes, carcasses |
| FabricatorTest | blueprints and the Fabricator: recycling copies of a part teaches its blueprint (one Refined copy is enough, salvage teaches nothing), build costs, what stops a build (no Fabricator, no blueprint, high tech below Mk II, materials, credits, stash room), building into the stash, blueprints saving, the FAB window |
| FacilitiesTest | Hangar facilities: where they start, upgrade costs and refusals (credits, materials, top level, debt), the Recycler raising yields, the Workshop cutting a real mecha's repair bill, the Stash growing with items left in place (and on load), the Fabricator's grade odds, levels saving, the FAC window |
| FlagTest | the Flag, panic and mines: a Flag raised at once and lowered with a wind-up, locking the weapons but not smoke or the bay, the emergency Flag and the HUD, the key, who pressed a mecha into its Flag; NPCs respecting a Flag by personality and the reputation roll; treachery (lowering a Flag raised by choice and attacking) and its cost, witnesses, the cost of killing a Flagged pilot and the reward for sparing one; surrender and a Rat's fake; a Rat's execution and stalk, a Guardian's protection; panic's rises, falls and effect on aim; mines seen or missed by panic; the stage step |
| FlagFixTest | the emergency Flag: the core shell keeping the cockpit from hits, blasts and overheat, both ways in (core shell, hp at 0) starting one grace window of three to five seconds in which nothing hurts the mecha, killing it after the window, the weapons locked, the emergency_flagged signal; the splatter thrown away from the attacker, the death pool and the stain cap; hits on internal components leaking drops, a destroying hit throwing a small splatter and a full droplet jet along it, bleeding from internal damage rather than low hp; a dead mecha's body showing every fitted part (single chassis too) but the one or two that came off, never the core, chassis or a weapon in the loot, being solid (blocking movement, shots and sight lines, but not where a part came off, also when left inside a physics callback) and being in the tree before the mecha is freed; NPCs dropping a Flagged target, a Rat holding fire through the grace window |
| FrameCostProbe *(slow)* | where a frame's script time goes on Helwan with twelve NPCs, the engine's step with scripted walkers, and the sight circle's costs (NPC senses, streaming, building shadows, full-rate NPCs) at 850 m and 150 m with the camera still, panned and panning; prints, never fails on a timing |
| GameLoopTest *(slow)* | Hangar -> Expedition -> Hangar with the player's gear and loot |
| GradesTest | part grades: the grade table, wreck weapon drops rolling grades at their odds, grade scaling value, recycling and repairs, grades scaling a real mecha's summed stats and walk speed (and the stats panel the same), saving and loading grades, old saves as Standard, names showing the grade, a lost run resetting them |
| HangarTest | Hangar windows, recycling, Materials window, selling and the credits readout (debt shown inverted), leave guard, swapping parts, a part keeping its grade on and off the mecha, closing the game mid-refit |
| IlluminationTest | IR illuminators: what a mecha's own light and its cone light (any of a body in the cone, not only its centre), walls shadowing it, a building's inside apart; the player seeing lit bodies through walls and losing its cone with the light off; the illuminator key and the HUD's IR row; an NPC seeing lit targets through walls and unlit ones only close by with its own light off, in its cone with it on; NPC behaviours running dark by intent and holding the setting; every light adding or taking away; the cone drawn in code at the head's angle |
| IlluminatorTest | the illuminator: its reach the head's visual range (not shortened by sensor damage, 20 m with no head), drawn to scale with the circle round the mecha and the fades the same size, one texture per angle and reach, a mecha whose near edge is inside it lit; the cone turning with the head and stopping at its range; with the light off, an NPC and the player seeing only lit bodies, IR-identified ones and those within peripheral sight; the key (hold, release, double-tap latch, one press to go dark, a slow second press a fresh hold), the HUD's HELD / LATCHED / DARK, C and B in SYS → CONTROLS; lock head tracking (the head to the locked target within its range, the body and arms to the cursor, off with the setting or no lock, another mecha's lock still turning it whole); the setting on by default, saved, listed after Designator Look Limits |
| InfoSystemsTest | NPCs using the information systems: a Local help call or loot shout as a lead at a spot blurred once within 150 m, kept a minute, acted on instead of the true position; help by personality (a Guardian's roll, a Hunter never), a hated caller unanswered, a squadmate under fire and hurt helped at once where it is, a helper turning on whoever hits the caller; a Hunter vulturing a fight heard, dark, and preying on the survivor once it is quiet, going in to look when it sees nobody and then done with that fight until new gunfire, not when running hot, a Scavenger never; a Professional scouting with a sweep before a long trip or one into ground it took fire on, once in a while; a Rat's fake loot shout from an ambush and its luring help call; an Anonymous pilot's extra hostility on first sight; being swept making an NPC suspicious of everyone in sight, a Scavenger keeping away from the spot and wandering clear of it, a Hunter sweeping back; a destroyed ward as a lead to investigate; car alarms kept by Hunters and the greedy, ignored by others, kept away from by Scavengers; a tagged squad's size read off the roster and weighing on a fight; a Hunter's search following the warmest heat mark a step along its heading; any wreck teaching its killer's name without a grudge |
| IndirectFireTest | indirect rounds flying over a building and a truck onto their point, roof bursts hurting no one, open-ground bursts, a shell landing right on a mecha hurting it, direct rounds going off at their landing point, building walls (generated and hand-made) blocking blasts both ways, a blast hurting its firer |
| LaserTest | the sweep laser: its data, the rectangle always reaching full range, the beam hitting every mecha in it once for a fixed amount (and nothing beside or behind it, nor the firer), the front sweeping near to far, the beam stopping at a wall |
| LootTableTest | loot tables, tiers, containers, bio salvage and Entity tables (the Coyote, Coyote Spitter and Fisher tables included) |
| MineTest | mine layers and mines: their data, a contact mine going off only when driven over, a burst of sensor mines landing in the circle and going off when a mecha comes near, a magnetic mine crawling to a mecha, a direct-fire mine bouncing off a wall, mines lasting with no limit on their number, mines_near() for NPC code, a settled mine running no process or physics, mines bursting on a roof |
| MissileTest | the cluster missile and VLS launchers: their data, firing at a locked target whatever the designator, gimbal or minimum range (up to max range), unlocked cluster submunitions dropping onto points in the circle (also when a wall stops the missile), a locked cluster missile breaking up at a wall with nothing released, locked VLS missiles over a building onto a target that moved, unlocked VLS missiles landing in the circle |
| MapStreamingTest | map chunks hidden away from the camera, streamed scenes loading near a mecha and freed when it leaves, their loot crates keeping their contents across reloads (no refilling), far NPCs thinking less often |
| MapVehiclesTest | map vehicles: mechas shoving cars, fire engines holding them back, cars shunting each other and stopping at walls, vehicles blocking shots by chance, not blocking sight, collision only near mechas |
| MapWallsTest | building walls and foliage: walls block sight between outside and inside, each wall costs a shot 1 AP, grenades go off at walls, Entities can't see through walls, trees hide mechas, merged walls still count |
| NPCIntentTest | how an NPC picks what to do: each of the fourteen intents winning where its old state was entered, an ambush running out of patience and resting before the next, the commitment bonus, minimum time and ties, the emergency Flag making an NPC flee from any intent (not a Rat) and dark, a flight that goes on while nobody shoots and ends far away and left alone, a lost target searched for at its last-known position and never its true one, the think-time probe and the intent log |
| NPCSteeringTest | how NPCs move round vehicles and buildings: steering, pushing through or round cars, unsticking, routing through gaps, tanks trampling cars, circling in a fight, sprinting and dashing, cars destroyed by shots, blasts and dashes, spawns clear of vehicles |
| NPCThinkCostTest *(slow)* | the think-time probe on Helwan with twelve NPCs: prints the microseconds per NPC per thinking frame (never fails on a timing) |
| NpcDesignsTest | every enemy design is valid and builds |
| ObserverArenaTest | the observer arena that OBSERVE opens: loading with no player, its spectator camera, darkness, buildings, cars and foliage; spawning an NPC of each personality type, a squad and a dummy; each event (a car alarm and its tracks, a loud noise heard, a round and a sweep from the phantom, which no list of mechas holds, a ward and a drone the dummy's); each dummy behaviour (patrol, light on, off and flashing, firing at the selected NPC and at a point, never with the Flag up, the Flag); clicks picking, placing and cancelling, and a real mouse click on the map getting through to it; think tags (name, intent, scores, how long it has stood still, the selected one's detail) and barks heard with no player and shown over the speaker; following and zooming; pause stopping the NPCs and the speeds; delete and clear |
| OtherModesTest *(slow)* | Store, Ladder, Arena fights start and run |
| PartLossTest | mecha parts coming off: a shoulder whose hit facing is stripped and whose internal components are all destroyed coming off with the weapons on its side (hidden, its collision off, lighter, its weapons offline and gone from the HUD, nothing picking it to damage, a large explosion, debris on the ground), armour left on that facing holding it on, shots passing through the gap, the head coming off with every head component destroyed, the core and chassis never coming off, a wreck keeping lost parts missing (body, solid shape, shedding, loot), the debrief writing a lost section off with no repair bill, showing it and its parts UNSALVAGEABLE, and standard parts fitted in the written-off slots |
| PartsTest | every part's data (name, image, weight, size, price, tech tier and composition), equipping, every weapon fires |
| PersonalityTest | the personality table and the voice: a Hunter never loots and is provoked by a Flagged mech that crowds it or keeps facing it (not one that looks away; a Professional isn't), a Guardian protecting a Flagged or badly hurt squadmate before a stranger and yielding only all but broken while a squadmate stands, a Professional extracting on schedule and a Scavenger on its greed's roll; every bark event with lines for every personality type and "any", a chance, the panicked variants with chances, and a panicked NPC using the panicked line |
| PlayerViewTest | what the player sees: mechas behind a building wall faded out, in-building and out-of-building sight (generated and hand-made buildings), Entities hidden too, nothing hidden while controls are locked; the head's IR sensor: a body above IR sensitivity a live UNKNOWN track that follows it and fades as a ghost, above IR identification seen through walls, not into another building or without a head, an Entity's body temperature the same; a Fisher with its harpoon in the player always shown |
| PlayerProgressTest | money, stash, stakes, materials, recycling, required parts |
| SandBodyTest | the sand creature looks (Coyote, Coyote Spitter, Fisher): building, walking, their attack moves, bursting into grains on death, nothing drawn under the ground (below z 0) and the body a z over its top_level legs and trailing tails (the Fisher's shell over its legs), its legs and tails fading with it out of the player's view, the Fisher half again its first size, the art bench |
| SandEntityTest | the sand Entities and ticks on a stand-in arena: heat finding prey and cooling releasing it; a mecha with its illuminator on found and kept within a screen, cold or not, and let go once the light is off; memory: lost prey hunted where it was last had then let go, a Coyote shot by a cold mecha taking it on and calling Coyotes nearby in, a cold dark mecha very close found, a Spitter and a gun firing at where they last had their prey, a Fisher stalking to where it last had its prey; a Coyote's bite (heat drain, a slow that stacks and wears off), its whip only hurting external components, a pack hunting one at a time, a hurt Coyote fleeing; a Coyote Spitter's medium-AP globs from range, never lunging; a Fisher sleeping through heat, waking on noise or a shot, latching and drawing on its prey every 2 s and healing, letting go, a tether snapping, leaping back and to the side when rushed, three fast leaps in a row then a wait, leaping round a mecha that turns to face it, its draw doing nothing in the Flag's grace window; carcasses; the director's packs; a blast's hit marked AoE and a direct one not; tick swarms (hp as ground motes, nearest-mote and three-mote blast kills, a shot between motes missing, jumping only on a hot mecha close by, attached ticks draining, glowing and biting, damage shaking them off, syncing into a brood that doubles, dispersing, the cap fading the oldest unseen swarm), frenzy; Coyotes scavenging a wreck, picking up a wreck's shed part (which leaves its unsalvageable list) and a live mecha's lost part off the ground, ripping a part off a Flagged mecha, a front-only shield that breaks, a scavenged gun firing its own rounds credited to the Coyote, the parts in its carcass; a glob flying as a drop of fluid and splashing into droplets; sweeps and the Biosensor naming the new species, and what they carry or leave fading with them |
| SaveFileTest | saving/loading on disk, a new profile's starting credits, backup recovery, abandoned runs on boot |
| SquadTest | NPC squads: a squad's designs (direct fire first, support third) and the personality draw, the tag in Local and none for an Anonymous squad; members' spaced slots beside and behind the leader, never in a line, and a member following into its slot, a straggler called back; the roles dealt, the flanker reaching 60° off the anchor's bearing while the anchor holds its range lit, the support member turning to put smoke on a mate that falls back; a callout landing in squadmates' stores after the delay and a mate taking it as its target; the leader's death passing the lead on, raising panic and judged by loyalty; a treacherous Rat leaving and turning on a hurt mate; shooting a member turning the squad on the shooter and a mate's stray round forgiven; a fallen member's wreck naming its killer for the whole squad |
| SightCircleTest | the sight circle: its radius from the head in metres, halved by sensor damage, 20 m with no head; the camera pan held to it, its speed (the radius in MOVE_CAMERA_PAN_TIME at the edge, a quarter halfway into the margin, a corner no faster), none with no head, a shake leaving the pan; the black mask past it (centre, radius, off with no player, with controls locked and once dead); the player seeing and tracking nothing past it, by sight or IR; an NPC seeing nothing past its circle, a cold lit mecha seen to the edge as a hot one is, IR inside the circle only, the circle halved by sensor damage; lights noticed inside the circle, an Entity's within a screen; the darkness on the panned camera's centre and the audio listener at the player; building shadows and a streamed scene following the panned camera, shadows not past the sight circle; an NPC the player can see running at full rate; spawn zones the player can see refused, and parts flying only where it can see |
| SmokeTest | smoke clouds and the smoke launcher: a cloud thickening, blocking sight into, out of and through it and clearing, the player's view hiding mechas in and behind smoke, NPCs and Entities not seeing through it, tap screening the mecha itself and hold sending canisters to the designator, canisters leaving clouds |
| StageDemoTest *(slow)* | the demo cutscene in a real Expedition: beats in order, the stage camera, frozen bystanders, the spawned NPC and obstacle, handing control and actors back, skipping, F4 and map triggers, ending on the player's death |
| StageDirectorTest | cutscene building blocks: steps in order, waits, skipping, pausing, aborting, cinema bars, taking control, camera look-at/follow/hand-back, dialogue lines, actors walking and shooting |
| StoryDirectorTest | story beats, flags, triggers, missions |
| TacticsTest | the position picker and the fire controller: the range band, cover with a line of fire, no picks inside buildings, the cover cache; a 1v1 in the open never closing to point-blank; a mortar firing at a last-known spot behind a building but never into one; a lost target searched for with a sweep, a drone and the lights off; overheating breaking contact with smoke, a decoy and a mine until cool; a Professional holding a poor shot and hot guns bursting; an idle NPC shooting an enemy ward |
| TestArenaTest *(slow)* | the test arena that Arena Mode opens: its NPCs (every personality type, a squad, the player's companion), buildings and vehicles, nothing at stake, dead NPCs replaced; its Coyote pack, Fisher and tick swarms, replaced when they die, and broods without the director |
| TracksAndLockTest | wedge tracks, locks and the radar: shot, sound and lock wedges (bearing, width, band, the estimate point a guess with the source always inside, ageing into ghosts, no body, none for a source in sight); an NPC going by the estimate point; the player's lock (nothing before the settle, the reveal, a reset when the reticle leaves, no start in or behind smoke or past the sight circle, each break, a lock contact that isn't sight); the lock warning narrowing to a line, LOCKING and LOCKED, the beep quickening; an NPC's lock (no reason or the target outside it refused, the search time by skill, the slip with no live track only, no search with one, none past its circle); direct lock-on rounds held behind walls, indirect ones not; RCS (facing widths, the largest-plus-fraction sum, a part shot off, the reference, rcs_factor) and the signature multiplier; sweep kinds by relative RCS and aspect, ticks one by one, a decoy as a mech; the radar's marks, chevrons, ghosts and lock bracket, marks spreading apart along their lane (one bearing, across ±PI, room left alone, a crowded ring shared), shot, sound and lock arcs each on a lane and in a style of their own, nothing without a track; the chipset's radar stats gone and RCS (front) in the stats panel |
| WreckTest | wreck loot, weapon drops, Take / Take all; shed parts listed UNSALVAGEABLE and crossed out under the loot, never in the inventory, gone from the list once taken |

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
