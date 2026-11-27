extends "res://game/test/suites/CampTest.gd"

# PacingTest: how the ExpeditionDirector keeps an expedition from going
# quiet, on CampTest's stand-in arena with a real CampField. Every encounter
# the tension arms is within earshot of the player, and its gunfire reaches
# it: at a laid-out site when one is in range, else at a new spot in the
# ring. A fight that is over frees its slot for a new one. Only the player
# finding an encounter eases the tension (an NPC waking it doesn't, until
# the player comes upon it). The redirect waits for a lull by the tension's
# clock (time out of a fight), and landing a hit counts as a fight. A roamer
# sent toward the player hears no gunfire on the way, and NPCs within
# earshot of an encounter aren't the ones sent. Heat damage isn't a fight.

const DIRECTOR := preload("res://game/expedition/ExpeditionDirector.gd")

var _director = null


func run_tests() -> void:
	await case("every encounter is within earshot, and the player hears its gunfire", _test_earshot)
	await case("a laid-out site in range is used before a new one is made", _test_laid_out_site)
	await case("a fight that is over frees its slot for a new one", _test_slot_freed)
	await case("only the player finding an encounter eases the tension", _test_found_by_player)
	await case("the redirect waits for a lull out of a fight; landing a hit is a fight", _test_quiet_clock)
	await case("a roamer sent toward the player hears no gunfire on the way", _test_sent_roamer)
	await case("an NPC in earshot of an encounter isn't the one sent", _test_redirect_skips_fight)
	await case("heat damage isn't a fight", _test_heat)
	await _clear()


func before_each() -> void:
	await super()
	_director = DIRECTOR.new()
	_director.arena = _arena
	_director.camps = _field
	_field.camp_woken.connect(_director._on_camp_woken)
	_arena.add_child(_director)
	_director.set_process(false)
	# Every check arms one: the pressure is full and always enough.
	_director.encounter_chance = 100.0
	_director.tension.value = 1.0


func _distance(camp: Camp) -> float:
	return camp.site.distance_to(_player.global_position)


# ---- Cases ----

func _test_earshot() -> void:
	check(_director.encounter_reach() <= CampField.GUNFIRE_RANGE,
			"no encounter goes further out than its gunfire carries (%d of %d px)" % [_director.encounter_reach(), CampField.GUNFIRE_RANGE])
	_field.lay_out_sites([Vector2(_director.encounter_max_distance, 0.0)])
	_director.max_armed_encounters = 100
	for k in 12:
		_director._try_arm_encounter()
	var armed: Array = _field.armed_encounters()
	check_eq(armed.size(), 12, "one starts at every try")
	check(not _field.sites[0].used, "never at the laid-out site out of earshot")
	var in_ring := 0
	for camp in armed:
		if _distance(camp) >= _director.encounter_min_distance and _distance(camp) <= _director.encounter_reach():
			in_ring += 1
	check_eq(in_ring, armed.size(), "each in the ring out to the reach")
	for k in 20:
		_field.advance(0.5)
	var shots: Array = _arena.sounds.filter(func(s): return s.type == "gunshot")
	check(shots.size() >= armed.size(), "their fights make gunfire (%d shots)" % shots.size())
	var heard := 0
	for s in shots:
		if s.position.distance_to(_player.global_position) <= s.max_distance:
			heard += 1
	check_eq(heard, shots.size(), "and the player hears every shot")


func _test_laid_out_site() -> void:
	var at := Vector2(_director.encounter_min_distance + 1000.0, 0.0)
	_field.lay_out_sites([at])
	_director._try_arm_encounter()
	check(_field.sites[0].used, "the laid-out site is taken")
	check_eq(_field.sites.size(), 1, "and no new one is made")
	check_eq(_field.armed_encounters()[0].site, at, "the encounter is there")


func _test_slot_freed() -> void:
	_director.max_armed_encounters = 1
	_director._try_arm_encounter()
	_director._try_arm_encounter()
	check_eq(_field.armed_encounters().size(), 1, "while its fight goes on, no second one starts")
	_field.clock += CampField.ENCOUNTER_DURATION
	check(_field.fighting_encounters().is_empty(), "(its fight is over, with nobody there)")
	_director._try_arm_encounter()
	check_eq(_field.armed_encounters().size(), 2, "once it is over a new one starts, while the old one waits to be given up")
	check_eq(_field.fighting_encounters().size(), 1, "and that one is fighting")


func _test_found_by_player() -> void:
	var a := Vector2(_director.encounter_min_distance + 1000.0, 0.0)
	_field.lay_out_sites([a])
	_director._try_arm_encounter()
	var camp: Camp = _field.armed_encounters()[0]
	_director.tension.value = 0.8
	var npc := _make_enemy(_design(), "Passerby", a + Vector2(500.0, 0.0))
	npc.set_pause(true)
	npc._set_distant(false)
	_field.update()
	check(camp.state != Camp.State.DORMANT, "an NPC passing by wakes it")
	check(absf(_director.tension.value - 0.8) < 0.001, "which leaves the tension as it was")
	_director._check_unfound()
	check(absf(_director.tension.value - 0.8) < 0.001, "while the player is far from it")
	_player.global_position = a
	_director._check_unfound()
	var eased := 0.8 - TensionMeter.FOUND_DROP
	check(absf(_director.tension.value - eased) < 0.001, "the player coming upon it eases the tension")
	_director._check_unfound()
	check(absf(_director.tension.value - eased) < 0.001, "once")

	var b := Vector2(-_director.encounter_min_distance - 1000.0, 0.0)
	_player.global_position = Vector2.ZERO
	_field.lay_out_sites([b])
	_director._try_arm_encounter()
	var camp2: Camp = _field.armed_encounters()[0]
	check_eq(camp2.site, b, "(a second one, on the other side)")
	_director.tension.value = 0.8
	_player.global_position = b + Vector2(500.0, 0.0)
	_field.update()
	check(camp2.state != Camp.State.DORMANT, "the player wakes it")
	check(absf(_director.tension.value - eased) < 0.001, "and finding it eases the tension at once")


func _test_quiet_clock() -> void:
	var npc := _make_enemy(_design(), "Far", Vector2(_director.min_redirect_distance + 5000.0, 0.0))
	npc.set_pause(true)
	_director.time_since_last_player_damage = 999.0
	_director.tension.since_fight = 10.0
	_director._try_redirect()
	check_eq(_director.total_redirects, 0, "not hit for long, but only 10 s out of a fight: nobody is sent")
	_director.tension.since_fight = _director.quiet_threshold + 1.0
	_director._try_redirect()
	check_eq(_director.total_redirects, 1, "after a real lull an NPC is sent")
	check(not npc.senses.sounds.is_empty(), "it heard the call")
	check(not _director.player_in_fight(), "(the player isn't in a fight)")
	_director.notify_player_landed_hit()
	check(_director.player_in_fight(), "landing a hit is a fight")
	_director.tension.advance(1.0, _director.player_in_fight(), 0.0)
	check_eq(_director.tension.since_fight, 0.0, "which ends the lull")
	_director.time_since_player_landed_hit = DIRECTOR.FIGHT_MEMORY + 1.0
	check(not _director.player_in_fight(), "a few seconds after, it is over")


func _test_sent_roamer() -> void:
	seed(5)
	var camp := _field.add_roamer([_named()], Vector2(30000.0, 0.0))
	var dest := Vector2(500.0, 0.0)
	_field.send_roamer(camp, dest)
	var gunfire := Vector2(30000.0, 5000.0)
	for k in 20:
		_field.hear({"volume_type": "loud", "type": "gunshot", "position": gunfire, "source": null, "max_distance": 20000.0})
	check_eq(camp.destination, dest, "it keeps going where it was sent")
	camp.site = dest + Vector2(10.0, 0.0)
	_field._travel(camp, CampField.TICK)
	check(not camp.sent, "there, it is on its own again")
	for k in 20:
		_field.hear({"volume_type": "loud", "type": "gunshot", "position": gunfire, "source": null, "max_distance": 40000.0})
	check_eq(camp.destination, gunfire, "and gunfire draws it as before")


func _test_redirect_skips_fight() -> void:
	var site := Vector2(_director.encounter_min_distance + 2000.0, 0.0)
	_field.lay_out_sites([site])
	_director._try_arm_encounter()
	var near := _make_enemy(_design(), "NearTheFight", site + Vector2(3000.0, 0.0))
	var far := _make_enemy(_design(), "Elsewhere", Vector2(-15000.0, 0.0))
	near.set_pause(true)
	far.set_pause(true)
	check(_field.hears_encounter(near.global_position) and not _field.hears_encounter(far.global_position),
			"(one is in earshot of the fight, the other isn't)")
	var picks := []
	for k in 10:
		picks.append(_director._find_distant_idle_npc())
	check(picks.all(func(m): return m == far), "the one sent is always the NPC out of earshot")
	_field.clock += CampField.ENCOUNTER_DURATION
	check(not _field.hears_encounter(near.global_position), "once the fight is over there is no gunfire to hear")


func _test_heat() -> void:
	_player.component_damaged.connect(_director._on_player_component_damaged)
	var damaged := [0]
	_player.component_damaged.connect(func(_p, _c, _hp, _max): damaged[0] += 1)
	_director.time_since_last_player_damage = 999.0
	_player.overheat_damage_tick()
	check(damaged[0] > 0, "(an overheat tick damaged a component)")
	check_eq(_director.time_since_last_player_damage, 999.0, "but that isn't a fight")
	var part = _player.components.keys()[0]
	var comp = _player.components[part].keys()[0]
	_player.damage_component(part, comp, 1)
	check_eq(_director.time_since_last_player_damage, 0.0, "a hit on a component is")
