extends RefCounted

# Base AI behaviour: the intents an NPC can have, with a score and a do_
# method for each, the entry and exit hooks, the shared helpers, and the
# tunables that shape them. Concrete behaviours in behaviours/ (default,
# aggressive, cautious, ...) extend this and override only the tunable vars
# in their _init(). Pure data + methods; held by EnemyLogic (RefCounted),
# never in the scene tree, so the whole AI chain auto-frees with the NPC.
#
# Intents (EnemyLogic scores every one each evaluation; the highest wins):
#   roam         wander, and in time decide to leave ("shift over")
#   investigate  go to a sound, or to where it was shot from; wary wandering
#                once the lead is used up
#   loot         go to a container and search it
#   extract      go to an exit and leave
#   ambush       hold at half throttle where something quiet was heard
#   engage       fight a target: close in and lock on (stance "closing"),
#                then the attack or defend stance with the kite bands,
#                blind fire, shield use and stance hysteresis
#   flee         run from every known threat to an exit, dark and sprinting,
#                until it is far from them and left alone for a while
#   identify     something is out there: an unknown or unseen track, met by
#                the type's doctrine (see IDENTIFY)
# Scores are on a 0 to 1 ladder (the SCORE_ constants) that keeps the order
# the old transition priorities had, so the same intent wins in the same
# situation. An NPC in the emergency Flag (Mecha.is_exposed) flees above
# everything; its weapons are locked, so engage never scores for it.
#
# The illuminator is chosen per intent (illuminator_mode): off by default,
# on only to engage a target it has a track or lock on (steady, or flashing
# from SKILL_LIGHT_DISCIPLINE), to execute, and for identify's light; never
# for a Rat.
#
# NOT selectable on its own — it lives outside behaviours/ so combat_behaviour
# names never resolve to it. Add a variant by subclassing, not by editing here.

const POSITIONAL_ACCURACY = 400.0
const THROTTLE_CHANGE_TIME = 1.0
## How far round a lost target's last-known spot an NPC searches (px).
const SEARCH_RADIUS = 600.0
## The base tunables below are tuned for a 2000 px weapon range
## (weapon.ai_engage_range's default). A balanced build scales them by its
## own range (see _get_effective_distances).
const BASE_WEAPON_RANGE = 2000.0
## A target this much past max kite range still counts as in range for
## entering combat.
const COMBAT_ENTRY_SLACK = 1.1

## The score ladder (see above). Each step that must win at once over the
## intent below it is more than EnemyLogic.COMMIT_BONUS above it.
## Placeholders.
const SCORE_ROAM := 0.01
const SCORE_EXTRACT_SHIFT := 0.15
const SCORE_INVESTIGATE := 0.2
const SCORE_LOOT := 0.25
const SCORE_AMBUSH := 0.35
const SCORE_EXTRACT_AFTER_FLIGHT := 0.35
const SCORE_INVESTIGATE_FIRE := 0.4
const SCORE_EXTRACT_CASH_OUT := 0.45
const SCORE_ENGAGE_CLOSING := 0.55
const SCORE_ENGAGE_IN_RANGE := 0.65
const SCORE_ENGAGE_FIGHTING := 0.75
const SCORE_EXTRACT_COMMITTED := 0.8
const SCORE_FLEE := 0.9
const SCORE_FLEE_FOR_LIFE := 1.0

## Fleeing: the flight ends once every known threat is further than
## FLEE_SAFE_DISTANCE (px, 300 m) and the NPC has seen no threat and taken no
## hit for FLEE_SAFE_TIME s (scaled by courage unless it flees for its life).
## It picks its exit again every FLEE_EXIT_REPICK_TIME s, runs
## FLEE_RUN_DISTANCE px past the threats when there is no exit, and after a
## flight takes an exit within FLEE_EXTRACT_RANGE px. Placeholders.
const FLEE_SAFE_DISTANCE := 6000.0
const FLEE_SAFE_TIME := 20.0
const FLEE_EXIT_REPICK_TIME := 5.0
const FLEE_RUN_DISTANCE := 2000.0
const FLEE_EXTRACT_RANGE := 3000.0
## How long (s) an alarmed NPC stays wary, wandering with its shield ready,
## after its leads are used up. Placeholder.
const WARY_TIME := 30.0
## Scans of the scene for containers and exits are refreshed this often (s).
const SCAN_INTERVAL := 1.0

## Searching and disengaging: a target unseen for SEARCH_AFTER s turns the
## fight into a search; a fight it is losing (aggression at or under
## DISENGAGE_AGGRESSION while under fire) or overheating into a disengage,
## held for DISENGAGE_MIN_TIME s and until the guns are cool, then not again
## for DISENGAGE_COOLDOWN s. Placeholders.
const SCORE_ENGAGE_LOST := 0.5
const SCORE_SEARCH := 0.65
const SCORE_DISENGAGE := 0.88
const SEARCH_AFTER := 2.0
const DISENGAGE_MIN_TIME := 4.0
const DISENGAGE_AGGRESSION := -2.0
const DISENGAGE_COOLDOWN := 8.0
## A picked position counts as reached within this distance (px).
const PICK_ARRIVE := 250.0
## A mine is laid this far (px) toward the foe, on the way it will come.
const MINE_LAY_DISTANCE := 400.0
## A flare goes out before closing on a target unseen this far away (px).
const FLARE_PUSH_DISTANCE := 1000.0
## The position picker's weights per intent (Positioning). Placeholders.
const ENGAGE_WEIGHTS := {"range": 1.0, "cover": 0.5, "fire_line": 1.5, "travel": 0.3, "way": 0.2,
		"open": 0.4, "spacing": -0.5, "mines": -1.0, "smoke": -0.5, "travel_scale": 1500.0}
const DEFEND_WEIGHTS := {"range": 1.0, "cover": 0.8, "fire_line": 1.2, "travel": 0.3, "way": 0.3,
		"open": 0.4, "spacing": -0.5, "mines": -1.0, "smoke": -0.3, "travel_scale": 1500.0}
const SEARCH_WEIGHTS := {"range": 0.4, "view": 0.8, "cover": 0.3, "travel": 0.5, "open": 0.5,
		"mines": -1.0, "travel_scale": 1200.0}
const AMBUSH_WEIGHTS := {"range": 0.4, "cover": 1.0, "view": 0.8, "travel": 0.5, "open": 0.5,
		"mines": -1.0, "travel_scale": 1500.0}
## Ambush waits for whatever it heard at most AMBUSH_PATIENCE s (a Rat's lure
## keeps its own LURE_TIME); then it goes to look (investigate) and won't lie
## in wait again for AMBUSH_REST s, so a walker heard nearby that never comes
## can't hold it in place. Placeholders.
const AMBUSH_PATIENCE := 20.0
const AMBUSH_REST := 30.0
const DISENGAGE_WEIGHTS := {"cover": 1.2, "far": 1.0, "travel": 0.3, "way": 0.5, "open": 0.3,
		"smoke": 0.5, "mines": -1.0, "travel_scale": 2000.0, "far_scale": 3000.0}

## The Flag and panic (Phase 3):
##   execute     finishing a Flagged mech it is willing to shoot (a Rat, a
##               Hunter it provoked, a traitor): a bark, then it closes in,
##               lit, for at least the grace window before it fires
##   stalk       a Rat following a distracted target with its Flag up, to
##               lower it and strike from behind
##   protect     a Guardian standing by a Flagged or badly damaged mech that
##               isn't hostile
##   raise_flag  surrender: losing and panicked, it raises its Flag, pleads
##               in Local, and runs the flight to an exit; a Rat may lower it
##               again when its sparer comes close and looks away
## Placeholders.
const SCORE_PROTECT := 0.5
const SCORE_EXECUTE := 0.7
const SCORE_STALK := 0.7
const SCORE_RAISE_FLAG := 0.95
## Panic at which each personality surrenders (none for Hunters), when its
## aggression is negative (a Professional's clearly so: SURRENDER_AGGRESSION).
const SURRENDER_PANIC := {
	Personality.Type.SCAVENGER: 0.6,
	Personality.Type.RAT: 0.6,
	Personality.Type.PROFESSIONAL: 0.7,
	Personality.Type.GUARDIAN: 0.85,
}
const SURRENDER_AGGRESSION := -2.0
## A Guardian with a living squadmate yields only at this panic (Phase 7).
const SURRENDER_PANIC_GUARDIAN_WITH_MATES := 0.98
## A Professional extracts on schedule: this long (s) after it arrived,
## whatever its greed. Placeholder.
const PRO_EXTRACT_TIME := 300.0
## Panic above which a fight under fire becomes a disengage, and above which
## the NPC sprints where it would walk.
const PANIC_DISENGAGE := 0.6
const PANIC_SPRINT := 0.5
## How much panic raises the health share at which it flees.
const PANIC_FLEE_HEALTH := 0.3
## Sparing: a surrendered NPC left alone this long (s) by the pilot it
## yielded to tells Local it was spared.
const SPARE_TIME := 10.0
## A Rat's fake surrender: it lowers its Flag again when its sparer is within
## this distance (px, 40 m) and facing away.
const FAKE_SURRENDER_RANGE := 800.0
## A Rat wandering raises its Flag at this rate per second times treachery.
const RAT_WANDER_FLAG_RATE := 0.05
## A Guardian protects a mech at or under this structural health, from this
## far (px).
const PROTECT_DAMAGE := 0.4
const PROTECT_RANGE := 600.0
const STALK_WEIGHTS := {"range": 0.8, "behind": 1.5, "travel": 0.4, "open": 0.3, "mines": -1.0, "travel_scale": 1500.0}
const PROTECT_WEIGHTS := {"range": 1.0, "cover": 0.3, "travel": 0.3, "open": 0.4, "mines": -1.0, "travel_scale": 1500.0}

## Squads (Phase 4, see Squad):
##   follow      a member keeps its travel slot beside or behind the leader
##               while the leader is calm (not in a fight), and stands by it
##               while it loots; it loots a crate of its own if there is one
## In a fight each member runs its own tactics in its role: the flanker's
## picker weighs the flank term (FLANK_WEIGHTS, at least Squad.FLANK_ANGLE
## off the anchor's bearing to the foe); the support member screens a
## squadmate that is breaking off with smoke (_support_cover). The leader
## calls stragglers back (Squad.call_regroup). A member's death is judged in
## on_mate_died: the leader's death by loyalty, and a treacherous Rat leaves
## or turns on a hurt mate. Placeholders.
const SCORE_FOLLOW := 0.45
## A companion under the player's follow, hold or regroup order (Squad.order)
## keeps to it above any fight; flee and raise_flag still win.
const SCORE_ORDER := 0.87
## A member closer than this (px) to its slot stands.
const FOLLOW_SLACK := 150.0
## Support smoke for a squadmate at most this often (s), for a mate within
## this range (px); beyond the launcher's reach the smoke lands on the way.
const SUPPORT_COVER_COOLDOWN := 10.0
const SUPPORT_COVER_RANGE := 4000.0
## The least rate (deg/s) the support member turns at to cover a mate.
const COVER_TURN_RATE := 60.0
## Loyalty under which a member breaks when its leader dies (if its courage
## is under LOYALTY_FLEE_COURAGE), and at or over which it avenges.
const LOYALTY_FLEE := 0.3
const LOYALTY_FLEE_COURAGE := 0.5
const LOYALTY_AVENGE := 0.6
## Treachery over which a Rat leaves its squad when a member dies, turning
## on a mate at or under this health share (or Flagged) on the way out.
const BETRAY_TREACHERY := 0.7
const BETRAY_HEALTH := 0.4
const FLANK_WEIGHTS := {"range": 0.8, "flank": 1.5, "fire_line": 1.0, "cover": 0.3, "travel": 0.3,
		"open": 0.4, "spacing": -0.8, "mines": -1.0, "smoke": -0.5, "travel_scale": 1500.0}

## The information systems (Phase 6):
##   help      go to a squadmate in trouble (under fire and hurt: always),
##             or to a Local help call it decided to answer (by personality,
##             HELP_CHANCE, and its standing with the caller), at the
##             call's blurred position; seeing the caller hit, it turns on
##             the attacker (Enemy._on_attack_witnessed)
##   vulture   Hunters and Rats: toward a fight heard (gunfire, or a help
##             call) while in good shape, to a covered spot VULTURE_STANDOFF
##             from it, dark, until the shooting has stopped for
##             VULTURE_QUIET s; then whoever it sees there is prey. Seeing
##             nobody, it goes in to VULTURE_LOOK of the spot to look; nobody
##             there either, it is done with that fight, and only gunfire or a
##             help call heard after that brings it back
##   scout     Professionals and Hunters: before a trip further than
##             SCOUT_TRIP, or into ground it took fire on, a sweep toward the
##             goal or a drone, at most every SCOUT_INTERVAL s
## Investigate reads loot shouts too (Scavengers always, others by greed),
## car alarms (Enemy.heard_sound) and a destroyed device's spot; Search
## follows heat trails (Hunters, Professionals: the warmest mark near the
## spot, a step along its heading, TRAIL_RADIUS and TRAIL_STEP). Rats lie
## in Local: a fake loot shout from an ambush and, now and then, a fake help
## call that lures (RAT_LIE_CHANCE, RAT_LURE_RATE). Placeholders.
const SCORE_SCOUT := 0.3
const SCORE_VULTURE := 0.45
const SCORE_HELP := 0.5
const SCORE_HELP_SQUAD := 0.6
const HELP_CHANCE := {
	Personality.Type.GUARDIAN: 0.9,
	Personality.Type.PROFESSIONAL: 0.5,
	Personality.Type.SCAVENGER: 0.1,
	Personality.Type.HUNTER: 0.0,
	Personality.Type.RAT: 0.0,
}
const HELP_RANGE := 6000.0
const HELP_MATE_HEALTH := 0.5
const VULTURE_RANGE := 6000.0
const VULTURE_STANDOFF := 2500.0
const VULTURE_QUIET := 8.0
const VULTURE_LOOK := 600.0
const VULTURE_PATIENCE := 45.0
const VULTURE_HEALTH := 0.6
const VULTURE_HOSTILITY := 1.0
const SCOUT_TRIP := 2500.0
const SCOUT_DANGER := 1500.0
const SCOUT_INTERVAL := 30.0
const SCOUT_SWEEP_WIDTH := 90.0
const LOOT_SHOUT_GREED := 0.5
const TRAIL_RADIUS := 600.0
const TRAIL_STEP := 500.0
const RAT_LIE_CHANCE := 0.5
const RAT_LURE_RATE := 0.01
const LURE_TIME := 40.0
const AVOID_RADIUS := 2500.0
const VULTURE_WEIGHTS := {"range": 0.6, "cover": 1.0, "view": 0.8, "travel": 0.4, "open": 0.5, "mines": -1.0, "travel_scale": 2000.0}

#Essential variables
var intents = ["roam", "investigate", "loot", "extract", "follow", "ambush", "engage", "search", "disengage",
		"execute", "stalk", "protect", "raise_flag", "flee", "help", "vulture", "scout", "identify"]
var initial_state = "roam"

#Custom variables
var engage_distance = 1800
var min_kite_distance = 1500
var max_kite_distance = 1700
var cqb_distance = 1200
var max_shooting_distance = 2000
var weapon_heat_threshold = 0.75
var general_heat_threshold = 0.9
var reaction_speed = 2

# Attack<->defend stance hysteresis. aggression sums quantized diffs
# recomputed every frame, so near zero it flickers across the sign — without
# damping, the stance (and its movement regime) thrashes frame to frame.
# Swapping requires BOTH: aggression clear of the +/- band, and at least
# MIN_DWELL seconds in the current stance. The first pick when the fight
# starts is a plain sign check, and flee / target-lost exits are never gated.
const STANCE_HYSTERESIS = 0.5
const STANCE_MIN_DWELL = 1.0


var point_of_interest
var aggression = 0
var aiming_at_enemy = false
var reaction_timer = 0.0
var target_container = null
var target_exit = null
var times_looted = 0
var _wants_to_extract := false  # "shift over" decision, made in do_roam (dt-scaled)
var _cash_out := false  # a greedy NPC leaving after a successful loot
var _leave_after_flight := false  # a flight ended near an exit, or Flagged
## The engage intent's stance: "closing" (locking on and moving into range),
## "attack" or "defend".
var stance := "closing"
var stance_time = 0.0  # seconds in the current attack/defend stance
var _start_tick_msec = 0  # lazy-initialized; tracks behaviour lifetime
var _wary_time := 0.0
# Tools used once per fight, search, ambush, loot or disengage.
var _flare_used := false
var _search_swept := false
var _search_drone := false
var _search_reading := {}
var _ambush_ward := false
var _ambush_mine := false
var _ambush_time := 0.0
var _ambush_rest_until := -INF
var _loot_ward := false
var _disengage_time := 0.0
var _disengage_ok_at := -INF
var _disengage_smoke := false
var _disengage_decoy := false
var _disengage_mine := false
var _was_seen := false
# The information systems.
var _help_lead: Dictionary = {}
var _help_mate = null
var _vulture_lead = null
var _vulture_point := Vector2.INF
var _vulture_time := 0.0
var _vulture_looked := false
var _vulture_done_at := -INF
var _scouted_at := -INF
var _scout_goal := Vector2.INF
var _trail_point := Vector2.INF
var _trail_found := false
var _trail_said := false
var _lure_until := -INF
var _lure_point := Vector2.INF
var _loot_lead: Dictionary = {}
# The squad.
var _flank_reached := false
var _anchor_at_pick = null
var _cover_ok_at := -INF
var _cover_aim = null
# The Flag intents.
var _execute_time := 0.0
var _execute_barked := false
var _stalk_raised := false
var _protege = null
var _surrendered_to = null
var _spare_time := 0.0
var _spare_hurt := false
var _spared_noted := false
# The flight (do_flee).
var _flight_over := false
var _flee_calm := 0.0
var _flee_time := 0.0
var _flee_exit_timer := 0.0
var _flee_smoke_used := false
var _flee_decoy_used := false
var _flee_point = null
# Scene scans, refreshed every SCAN_INTERVAL s of the NPC's time.
var _loot_scan_time := -INF
var _loot_found = null
var _exit_scan_time := -INF
var _exits_found: Array = []
var _exit_nearest = null

func get_nodes():
	return intents


## INTENT SCORES ##
# Pure and cheap: they read the NPC and its knowledge, never the scene.

func score_roam(_enemy) -> float:
	return SCORE_ROAM


func score_investigate(enemy) -> float:
	var current := _current(enemy)
	if enemy.under_fire_timer > 0 or (current == "investigate" and enemy.last_attack_position):
		return SCORE_INVESTIGATE_FIRE
	if enemy.get_loud_lead() or enemy.get_most_recent_quiet_noise():
		return SCORE_INVESTIGATE
	if current == "investigate" and _wary_time > 0.0:
		return SCORE_INVESTIGATE
	# A loot shout in Local it believes (Scavengers always, others by greed).
	if not enemy.valid_target and not _loot_lead_for(enemy).is_empty():
		return SCORE_INVESTIGATE
	return 0.0


# The loot shout this NPC would go to: the newest one it believes, within
# HELP_RANGE, from a pilot it has nothing against. {} for none.
func _loot_lead_for(enemy) -> Dictionary:
	if not _loot_lead.is_empty() and enemy.knowledge.local_leads.has(_loot_lead):
		return _loot_lead
	var type = enemy.personality.type
	if type == Personality.Type.HUNTER:
		return {}
	if type != Personality.Type.SCAVENGER and enemy.personality.greed <= LOOT_SHOUT_GREED:
		return {}
	for lead in enemy.knowledge.loot_leads():
		if enemy.global_position.distance_to(lead.position) > HELP_RANGE:
			continue
		if is_instance_valid(lead.sender) and enemy.get_relationship(lead.sender).hostility > enemy.STANDING_HOSTILITY:
			continue
		return lead
	return {}


func score_help(enemy) -> float:
	if enemy.is_flagged() or enemy.is_exposed or enemy.under_fire_timer > 0:
		return 0.0
	if enemy.valid_target and is_instance_valid(enemy.valid_target):
		return 0.0
	var current := _current(enemy)
	if current == "help":
		if _help_mate != null:
			return SCORE_HELP_SQUAD if _mate_in_trouble(enemy, _help_mate) else 0.0
		return SCORE_HELP if enemy.knowledge.local_leads.has(_help_lead) else 0.0
	if _find_mate_in_trouble(enemy) != null:
		return SCORE_HELP_SQUAD
	return SCORE_HELP if not _help_lead_for(enemy).is_empty() else 0.0


# A squadmate under fire and hurt, the nearest, or null.
func _find_mate_in_trouble(enemy):
	var squad = enemy.knowledge.squad
	if squad == null:
		return null
	var best = null
	var best_dist := INF
	for mate in squad.mates_of(enemy):
		if not _mate_in_trouble(enemy, mate):
			continue
		var d: float = enemy.global_position.distance_to(mate.global_position)
		if d < best_dist:
			best = mate
			best_dist = d
	return best


# A squadmate's trouble is squad radio: it says it is under fire and hurt.
func _mate_in_trouble(enemy, mate) -> bool:
	if not is_instance_valid(mate) or mate.is_dead or not ("under_fire_timer" in mate):
		return false
	var squad = enemy.knowledge.squad
	if squad == null or not squad.is_in(mate):
		return false
	return mate.under_fire_timer > 0.0 and NPCKnowledge._structural_health(mate) < HELP_MATE_HEALTH


# The help call this NPC answers: the newest within HELP_RANGE from a pilot
# it has nothing against, each rolled once by personality (HELP_CHANCE; the
# player's by its standing). {} for none.
func _help_lead_for(enemy) -> Dictionary:
	for lead in enemy.knowledge.help_leads():
		if lead.answer == false:
			continue
		if lead.answer == null:
			lead.answer = _answers_call(enemy, lead)
			if lead.answer:
				AICombatLog.record_info("help_answered")
			else:
				continue
		return lead
	return {}


func _answers_call(enemy, lead: Dictionary) -> bool:
	if enemy.global_position.distance_to(lead.position) > HELP_RANGE:
		return false
	var sender = lead.sender
	if is_instance_valid(sender):
		if sender.has_method("is_player") and sender.is_player() and not enemy.standing_with_player():
			return false
		if enemy.get_relationship(sender).hostility > enemy.STANDING_HOSTILITY:
			return false
	return randf() < float(HELP_CHANCE.get(enemy.personality.type, 0.0))


## The pilot this NPC is on its way to help (the help intent clears it on
## leaving), for the witness rule; null for none.
func helping():
	if _help_mate != null:
		return _help_mate
	return _help_lead.get("sender") if not _help_lead.is_empty() else null


func score_vulture(enemy) -> float:
	var type = enemy.personality.type
	if type != Personality.Type.HUNTER and type != Personality.Type.RAT:
		return 0.0
	if enemy.is_flagged() or enemy.is_exposed or enemy.under_fire_timer > 0:
		return 0.0
	if enemy.valid_target and is_instance_valid(enemy.valid_target):
		return 0.0
	var current := _current(enemy)
	if current == "vulture":
		if _vulture_looked or _vulture_time >= VULTURE_PATIENCE:
			return 0.0
		return SCORE_VULTURE if _vulture_point != Vector2.INF else 0.0
	var state = _get_self_state(enemy)
	if state.is_hot or state.no_ammo or _structural_health(enemy) < VULTURE_HEALTH:
		return 0.0
	return SCORE_VULTURE if _fight_heard(enemy, _vulture_done_at) != Vector2.INF else 0.0


# Where a fight is, as far as this NPC can tell: the newest gunfire heard,
# else the newest help call's blurred spot, within VULTURE_RANGE. Only what
# was heard after `since` (the NPC's time) counts.
func _fight_heard(enemy, since := -INF) -> Vector2:
	var newest = null
	for sound in enemy.knowledge.sounds:
		if sound.volume_type == "loud" and _is_gunfire(sound) \
				and (newest == null or sound.lifetime > newest.lifetime):
			newest = sound
	if newest != null and _heard_at(enemy, newest) > since \
			and enemy.global_position.distance_to(newest.position) <= VULTURE_RANGE:
		return newest.position
	for lead in enemy.knowledge.help_leads():
		if float(lead.time) > since and enemy.global_position.distance_to(lead.position) <= VULTURE_RANGE:
			return lead.position
	return Vector2.INF


# When (the NPC's time) a sound was heard: it is remembered SOUND_LIFETIME s
# and its lifetime counts down from that.
static func _heard_at(enemy, sound: Dictionary) -> float:
	return enemy.knowledge.now() - (float(enemy.SOUND_LIFETIME) - float(sound.lifetime))


func score_scout(enemy) -> float:
	var type = enemy.personality.type
	if type != Personality.Type.PROFESSIONAL and type != Personality.Type.HUNTER:
		return 0.0
	var current := _current(enemy)
	if current == "scout":
		return SCORE_SCOUT if _scout_goal != Vector2.INF else 0.0
	if current != "roam" and current != "investigate" and current != "help":
		return 0.0
	if enemy.under_fire_timer > 0 or (enemy.valid_target and is_instance_valid(enemy.valid_target)):
		return 0.0
	if enemy.knowledge.now() - _scouted_at < SCOUT_INTERVAL:
		return 0.0
	if not (enemy.fire.can_sweep() or enemy.fire.has_internal("drone")):
		return 0.0
	return SCORE_SCOUT if _trip_worth_scouting(enemy) else 0.0


# A trip worth a look first: further than SCOUT_TRIP, or into ground this
# NPC took fire on.
func _trip_worth_scouting(enemy) -> bool:
	if not point_of_interest:
		return false
	var goal: Vector2 = point_of_interest
	if enemy.global_position.distance_to(goal) > SCOUT_TRIP:
		return true
	for pos in enemy.knowledge.recent_fire_positions():
		if goal.distance_to(pos) < SCOUT_DANGER:
			return true
	return false


func score_loot(enemy) -> float:
	# A Hunter hunts pilots; crates are beneath it.
	if enemy.personality.type == Personality.Type.HUNTER:
		return 0.0
	var current := _current(enemy)
	if current == "loot":
		return SCORE_LOOT if _container_usable(target_container) else 0.0
	if (current != "roam" and current != "follow") or enemy.under_fire_timer > 0 or enemy.valid_target:
		return 0.0
	return SCORE_LOOT if _find_loot_target(enemy) else 0.0


func score_extract(enemy) -> float:
	var current := _current(enemy)
	var exit = target_exit if is_instance_valid(target_exit) else _find_nearest_exit(enemy)
	if exit == null:
		return 0.0
	if current == "extract":
		return SCORE_EXTRACT_COMMITTED
	if _cash_out:
		return SCORE_EXTRACT_CASH_OUT
	if _leave_after_flight:
		return SCORE_EXTRACT_AFTER_FLIGHT
	# A squad member leaves when its leader does (follow), not on its own.
	if _wants_to_extract and not _follows(enemy):
		return SCORE_EXTRACT_SHIFT
	return 0.0


func score_follow(enemy) -> float:
	if not _follows(enemy):
		return 0.0
	if enemy.is_flagged() or enemy.is_exposed:
		return 0.0
	# A companion under a standing order (follow, hold, regroup) keeps to it
	# over any fight; only fleeing and surrendering come before it. Under an
	# attack order it fights its target and otherwise moves up.
	var squad = enemy.knowledge.squad
	if squad.order == "follow" or squad.order == "hold" or squad.order == "regroup":
		return SCORE_ORDER
	if enemy.under_fire_timer > 0:
		return 0.0
	if enemy.valid_target and is_instance_valid(enemy.valid_target):
		return 0.0
	var current := _current(enemy)
	# Looting a crate of its own: finish it first.
	if current == "loot" and _container_usable(target_container):
		return 0.0
	# The leader looting: a member with a crate within reach loots too.
	if current == "follow" and enemy.knowledge.squad.intent() == "loot" and _find_loot_target(enemy) != null:
		return 0.0
	return SCORE_FOLLOW


# Whether `enemy` is a squad member with a living leader to follow.
func _follows(enemy) -> bool:
	var squad = enemy.knowledge.squad
	return squad != null and not squad.is_leader(enemy) and squad.leader_alive()


func score_ambush(enemy) -> float:
	if enemy.valid_target:
		return 0.0
	var current := _current(enemy)
	# A Rat waiting for whoever its fake help call brings.
	if enemy.knowledge.now() < _lure_until and enemy.under_fire_timer <= 0:
		return SCORE_AMBUSH
	if current == "ambush":
		if _ambush_time >= AMBUSH_PATIENCE:
			return 0.0
		return SCORE_AMBUSH if (enemy.get_most_recent_loud_noise() or enemy.get_most_recent_quiet_noise()) else 0.0
	if current == "investigate" and enemy.get_most_recent_quiet_noise() and enemy.under_fire_timer <= 0 \
			and enemy.knowledge.now() >= _ambush_rest_until:
		return SCORE_AMBUSH
	return 0.0


func score_engage(enemy) -> float:
	# The Flag locks the weapons: nothing to fight with.
	if enemy.is_flagged():
		return 0.0
	if not enemy.valid_target or not is_instance_valid(enemy.valid_target):
		return 0.0
	# A target whose Flag it respects isn't fought; one it doesn't respect is
	# executed (score_execute), unless it ignores the Flag outright.
	if enemy.valid_target.get("flag_up") == true and not enemy.ignores_flag_of(enemy.valid_target):
		return 0.0
	var current := _current(enemy)
	# A target out of sight for a while: the fight becomes a search.
	if current == "engage" and not enemy.is_seeing(enemy.valid_target) \
			and enemy.time_unseen(enemy.valid_target) >= SEARCH_AFTER:
		return SCORE_ENGAGE_LOST
	if current == "engage" and stance != "closing" and enemy.current_target:
		return SCORE_ENGAGE_FIGHTING
	if enemy.get_locked_to() or _in_combat_range(enemy):
		return SCORE_ENGAGE_IN_RANGE
	return SCORE_ENGAGE_CLOSING


func score_execute(enemy) -> float:
	if enemy.is_flagged():
		return 0.0
	var target = enemy.valid_target
	if not target or not is_instance_valid(target) or target.get("flag_up") != true:
		return 0.0
	if enemy.ignores_flag_of(target) or not enemy.should_attack(target):
		return 0.0
	return SCORE_EXECUTE


func score_stalk(enemy) -> float:
	if enemy.personality.type != Personality.Type.RAT or enemy.is_exposed:
		return 0.0
	var target = enemy.valid_target
	if not target or not is_instance_valid(target):
		return 0.0
	var current := _current(enemy)
	if current == "stalk":
		# Until it lowers the Flag and strikes.
		return SCORE_STALK if enemy.is_flagged() and enemy.is_seeing(target) else 0.0
	if enemy.under_fire_timer > 0 or not enemy.is_seeing(target):
		return 0.0
	if current == "engage" and stance != "closing":
		return 0.0
	return SCORE_STALK if _is_distracted(enemy, target) else 0.0


func score_protect(enemy) -> float:
	if enemy.personality.type != Personality.Type.GUARDIAN or enemy.is_flagged():
		return 0.0
	if enemy.valid_target and is_instance_valid(enemy.valid_target) and enemy.valid_target.get("flag_up") != true:
		return 0.0
	var current := _current(enemy)
	if current == "protect":
		return SCORE_PROTECT if _protege_valid(enemy, _protege) else 0.0
	return SCORE_PROTECT if _find_protege(enemy) != null else 0.0


func score_raise_flag(enemy) -> float:
	var current := _current(enemy)
	if current == "raise_flag":
		# Until the flight is over (then it leaves), or the Flag came down
		# again (a Rat's strike).
		return SCORE_RAISE_FLAG if enemy.is_flagged() and not _flight_over else 0.0
	if enemy.is_flagged() or enemy.is_exposed:
		return 0.0
	if not (current == "engage" or current == "search" or current == "disengage" or current == "flee"):
		return 0.0
	var type = enemy.personality.type
	if not SURRENDER_PANIC.has(type):
		return 0.0
	var threshold: float = float(SURRENDER_PANIC[type])
	# A Guardian with a squadmate still standing all but never yields.
	if type == Personality.Type.GUARDIAN and enemy.knowledge.squad != null \
			and not enemy.knowledge.squad.mates_of(enemy).is_empty():
		threshold = SURRENDER_PANIC_GUARDIAN_WITH_MATES
	if enemy.knowledge.panic < threshold:
		return 0.0
	var losing: bool = aggression < 0.0
	if type == Personality.Type.PROFESSIONAL:
		losing = aggression <= SURRENDER_AGGRESSION
	return SCORE_RAISE_FLAG if losing else 0.0


func score_search(enemy) -> float:
	if enemy.is_flagged():
		return 0.0
	var target = enemy.valid_target
	if not target or not is_instance_valid(target) or enemy.is_seeing(target):
		return 0.0
	if enemy.time_unseen(target) < SEARCH_AFTER:
		return 0.0
	return SCORE_SEARCH


func score_disengage(enemy) -> float:
	if enemy.is_flagged():
		return 0.0
	var current := _current(enemy)
	var state = _get_self_state(enemy)
	if current == "disengage":
		if _disengage_time < DISENGAGE_MIN_TIME or state.is_hot:
			return SCORE_DISENGAGE
		return 0.0
	if enemy.knowledge.now() < _disengage_ok_at:
		return 0.0
	if current == "engage" and stance != "closing" and enemy.current_target:
		if state.is_overheating:
			return SCORE_DISENGAGE
		if aggression <= DISENGAGE_AGGRESSION and enemy.under_fire_timer > 0:
			return SCORE_DISENGAGE
		# Panic: it breaks off sooner.
		if enemy.knowledge.panic >= PANIC_DISENGAGE and enemy.under_fire_timer > 0:
			return SCORE_DISENGAGE
	return 0.0


func score_flee(enemy) -> float:
	var current := _current(enemy)
	var rat: bool = enemy.personality != null and enemy.personality.type == Personality.Type.RAT
	if enemy.is_exposed and not rat:
		# One more hit may kill it: it runs for its life from any intent,
		# until the flight is over (then it leaves, carefully) or it is shot
		# at again.
		if current == "flee":
			return 0.0 if _flight_over else SCORE_FLEE_FOR_LIFE
		if _flight_over and enemy.under_fire_timer <= 0:
			return 0.0
		return SCORE_FLEE_FOR_LIFE
	if current == "flee":
		return 0.0 if _flight_over else SCORE_FLEE
	if current == "engage" and _should_flee(enemy):
		return SCORE_FLEE
	return 0.0


func _current(enemy) -> String:
	return str(enemy.logic.get_current_state())


# A target the NPC can fight from where it stands: hard-locked, or within
# the build's kite range.
func _in_combat_range(enemy) -> bool:
	if not enemy.valid_target:
		return false
	if enemy.get_locked_to():
		return true
	var eff = _get_effective_distances(enemy)
	var distance = enemy.global_position.distance_to(enemy.get_target_position(enemy.valid_target))
	return distance < eff.max_kite * COMBAT_ENTRY_SLACK


## ILLUMINATOR ##

# The doctrine's illuminator (Enemy._update_illuminator): off in every intent
# but these.
#   engage    on to get visual and aim, for a target it has a track or a
#             lock on: steady under SKILL_LIGHT_DISCIPLINE (held
#             Enemy.ILLUMINATOR_HOLD_TIME at a time), flashing from it
#             (LIGHT_FLASH: Enemy's light discipline). In a squad the anchor
#             is lit while the squad engages (the spotter, whose cone lights
#             the foe for the others), the flanker dark.
#   execute   lit: an execution must be seen, a Rat's too
#   identify  lit only for its "light" response
# Otherwise a Rat never lights up.
const LIGHT_OFF := "off"
const LIGHT_ON := "on"
const LIGHT_FLASH := "flash"


func illuminator_mode(enemy, intent: String) -> String:
	var type = enemy.personality.type if enemy.personality else Personality.Type.PROFESSIONAL
	if intent == "execute":
		return LIGHT_ON
	if type == Personality.Type.RAT:
		return LIGHT_OFF
	if intent == "identify":
		return LIGHT_ON if _identify_response == "light" else LIGHT_OFF
	if intent != "engage":
		return LIGHT_OFF
	var role: String = enemy.knowledge.role()
	if role == Squad.ROLE_ANCHOR:
		return LIGHT_ON
	if role == Squad.ROLE_FLANKER:
		return LIGHT_OFF
	var target = enemy.current_target if is_instance_valid(enemy.current_target) else enemy.valid_target
	if not is_instance_valid(target):
		return LIGHT_OFF
	if not (enemy.knowledge.knows(target) or is_same(enemy.get_locked_to(), target)):
		return LIGHT_OFF
	return LIGHT_FLASH if enemy.skill() >= SKILL_LIGHT_DISCIPLINE else LIGHT_ON


# Whether the NPC runs lit in `intent` (illuminator_mode not off).
func wants_illuminator(enemy, intent: String) -> bool:
	return illuminator_mode(enemy, intent) != LIGHT_OFF


## ENTRY AND EXIT HOOKS ##
# Called once by EnemyLogic when the intent changes. Scores are evaluated
# every time for ranking, so they stay pure; on-enter mutations live here.

func enter_investigate(_enemy):
	_wary_time = WARY_TIME
	target_container = null


func enter_loot(enemy):
	# Claim the container found during scoring. The scan is cached, so this
	# is the container score_loot saw.
	target_container = _find_loot_target(enemy)
	_loot_ward = false


func enter_ambush(enemy):
	_ambush_ward = false
	_ambush_mine = false
	_ambush_time = 0.0
	enemy.positioning.request()
	# A Rat baits its ambush with a loot shout that isn't true.
	if enemy.personality.type == Personality.Type.RAT and randf() < RAT_LIE_CHANCE * enemy.personality.treachery \
			and enemy.knowledge.now() >= _lure_until:
		enemy.broadcast("found_loot")
		AICombatLog.record_info("rat_lie")


func exit_ambush(enemy):
	if _ambush_time >= AMBUSH_PATIENCE:
		_ambush_rest_until = enemy.knowledge.now() + AMBUSH_REST


func enter_search(enemy):
	_search_swept = false
	_search_drone = false
	_search_reading = {}
	_trail_point = Vector2.INF
	_trail_found = false
	_trail_said = false
	aiming_at_enemy = false
	enemy.fire.cease()
	enemy.positioning.request()


func enter_help(enemy):
	_help_mate = _find_mate_in_trouble(enemy)
	_help_lead = {} if _help_mate != null else _help_lead_for(enemy)
	aiming_at_enemy = false
	enemy.going_to_position = false
	point_of_interest = false
	enemy.bark("investigating")


func exit_help(enemy):
	if not _help_lead.is_empty():
		enemy.knowledge.drop_lead(_help_lead)
	_help_lead = {}
	_help_mate = null
	enemy.going_to_position = false
	point_of_interest = false


func enter_vulture(enemy):
	_vulture_point = _fight_heard(enemy, _vulture_done_at)
	_vulture_time = 0.0
	_vulture_looked = false
	_vulture_lead = null
	aiming_at_enemy = false
	enemy.positioning.request()
	enemy.bark("vulturing")
	AICombatLog.record_info("vultured")


func exit_vulture(enemy):
	_vulture_point = Vector2.INF
	_vulture_done_at = enemy.knowledge.now()
	enemy.going_to_position = false
	point_of_interest = false


func enter_scout(enemy):
	_scout_goal = point_of_interest if point_of_interest else Vector2.INF
	enemy.going_to_position = false
	enemy.bark("scouting")


func exit_scout(enemy):
	_scout_goal = Vector2.INF
	# The trip goes on from where it was.
	if point_of_interest:
		enemy.going_to_position = true


func enter_disengage(enemy):
	_disengage_time = 0.0
	_disengage_smoke = false
	_disengage_decoy = false
	_disengage_mine = false
	aiming_at_enemy = false
	enemy.is_locking = false
	enemy.fire.cease()
	enemy.positioning.request()
	if enemy.knowledge.squad != null:
		enemy.knowledge.squad.callout(enemy, "falling_back")


func enter_follow(enemy):
	aiming_at_enemy = false
	enemy.going_to_position = false
	point_of_interest = false
	var squad = enemy.knowledge.squad
	if squad != null and squad.order == "free" and not (squad.intent() in ["roam", "investigate", "loot", "extract", "ambush", "follow"]):
		squad.callout(enemy, "moving_up")


func exit_follow(enemy):
	enemy.going_to_position = false
	point_of_interest = false
	enemy.fire.cease()


func exit_disengage(enemy):
	_disengage_ok_at = enemy.knowledge.now() + DISENGAGE_COOLDOWN


func enter_extract(_enemy):
	_cash_out = false
	_leave_after_flight = false
	target_exit = null


func enter_engage(enemy):
	stance = "closing"
	stance_time = 0.0
	aiming_at_enemy = false
	_flare_used = false
	_was_seen = false
	_flank_reached = false
	enemy.current_target = false
	enemy.positioning.request()
	if enemy.knowledge.role() == Squad.ROLE_FLANKER and _anchor_position(enemy) != Vector2.INF:
		enemy.knowledge.squad.callout(enemy, "flanking", enemy.valid_target)


func exit_engage(enemy):
	stance = "closing"
	enemy.is_locking = false
	enemy.current_target = false
	enemy.fire.cease()


func enter_flee(enemy):
	_begin_flight(enemy)
	# A Rat on the run puts its Flag back up.
	if enemy.personality.type == Personality.Type.RAT and not enemy.is_flagged():
		enemy.raise_flag(true)


func _begin_flight(enemy) -> void:
	_flight_over = false
	_flee_calm = 0.0
	_flee_time = 0.0
	_flee_exit_timer = 0.0
	_flee_smoke_used = false
	_flee_decoy_used = false
	_flee_point = null
	_leave_after_flight = false
	aiming_at_enemy = false
	enemy.valid_target = false
	enemy.current_target = false
	enemy.is_locking = false
	enemy.going_to_position = false


func enter_execute(enemy):
	_execute_time = 0.0
	_execute_barked = false
	enemy.current_target = enemy.valid_target
	enemy.fire.cease()


func exit_execute(enemy):
	enemy.current_target = false
	enemy.fire.cease()


func enter_stalk(enemy):
	_stalk_raised = false
	enemy.positioning.request()


func enter_protect(enemy):
	_protege = _find_protege(enemy)
	enemy.positioning.request()


func exit_protect(_enemy):
	_protege = null


func enter_raise_flag(enemy):
	_surrendered_to = enemy.pressured_by()
	_spare_time = 0.0
	_spare_hurt = false
	_spared_noted = false
	_begin_flight(enemy)
	enemy.raise_flag(true)
	enemy.broadcast("surrender")
	enemy.bark("surrender_plea")
	AICombatLog.record_flag("surrender")


## SHARED STATE HELPERS ##

# Standard movement preamble: ramp throttle up to full cruise.
func _ramp_throttle_full(dt, enemy):
	if enemy.throttle < 1.0:
		enemy.increase_throttle(false, dt/THROTTLE_CHANGE_TIME)
	else:
		enemy.decrease_throttle(1.0, 1.0)


# Wander: pick a random map point when we have nowhere to go, clear of the
# spot it keeps away from (a few tries).
func _wander_if_idle(enemy):
	if not enemy.going_to_position:
		var point: Vector2 = enemy.arena.get_random_position()
		for i in 8:
			if not enemy.knowledge.avoids(point, AVOID_RADIUS):
				break
			point = enemy.arena.get_random_position()
		point_of_interest = point
		enemy.going_to_position = true


# Head toward the most recent loud noise it acts on; on arrival consume it.
func _investigate_loud_noise(enemy):
	var recent = enemy.get_loud_lead()
	if not recent:
		return
	if enemy.global_position.distance_to(recent.position) > POSITIONAL_ACCURACY:
		point_of_interest = recent.position
		enemy.going_to_position = true
	else:
		enemy.senses.sounds.erase(recent)
		enemy.going_to_position = false
		point_of_interest = false


# Head toward the most recent quiet noise; on arrival consume every quiet
# sound from that source so we don't immediately re-investigate it.
func _investigate_quiet_noise(enemy):
	var recent = enemy.get_most_recent_quiet_noise()
	if not recent:
		return
	if enemy.global_position.distance_to(recent.position) > POSITIONAL_ACCURACY:
		point_of_interest = recent.position
		enemy.going_to_position = true
	else:
		var to_erase = []
		for sound in enemy.senses.sounds:
			if sound.source and\
			   sound.volume_type == "quiet" and sound.source == recent.source:
				to_erase.append(sound)
		to_erase.append(recent)
		for sound in to_erase:
			enemy.senses.sounds.erase(sound)
		enemy.going_to_position = false
		point_of_interest = false


# Push the point of interest into the nav agent (if far enough to matter).
func _push_poi_to_nav(enemy):
	if point_of_interest:
		if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
			enemy.NavAgent.target_position = point_of_interest


# On arrival, clear movement intent.
func _clear_arrival(enemy):
	if enemy.arrived():
		enemy.going_to_position = false
		point_of_interest = false


# Combat readiness: positive = press the attack, negative = back off.
func _update_aggression(enemy, state):
	var base_aggression = health_diff(enemy) + heat_diff(enemy) + status_diff(enemy)
	var personality_mod = (enemy.personality.aggression - 0.5) * 2.0
	aggression = base_aggression + personality_mod + _self_state_aggression_mod(state)


## INTENT METHODS ##

func do_roam(dt, enemy):
	if is_instance_valid(enemy):
		aiming_at_enemy = false
		_ramp_throttle_full(dt, enemy)
		_wander_if_idle(enemy)
		_push_poi_to_nav(enemy)
		_check_targets(enemy)
		enemy.fire.shoot_devices(dt)
		enemy.navigate_to_target(dt, 0, 0.65, false)
		_clear_arrival(enemy)
		_lead_squad(enemy)
		# A treacherous Rat wanders with its Flag up, a disguise for a stalk,
		# and now and then calls for help it doesn't need, to lure whoever
		# answers into an ambush where it stands.
		if enemy.personality.type == Personality.Type.RAT:
			if not enemy.is_flagged() and randf() < RAT_WANDER_FLAG_RATE * enemy.personality.treachery * dt:
				enemy.raise_flag(true)
			if randf() < RAT_LURE_RATE * enemy.personality.treachery * dt:
				_lure(enemy)

		# "Shift over": after staying long enough (courage-scaled threshold),
		# roll a dt-scaled chance to decide to leave. Rate preserves the old
		# tuning as observed at 144fps (0.001+greed*0.002 per frame ~=
		# 0.15+greed*0.3 per second). score_extract reads the flag.
		if not _wants_to_extract:
			if enemy.personality.type == Personality.Type.PROFESSIONAL:
				# On schedule: a fixed time on the ground, then out.
				if _time_alive_seconds() > PRO_EXTRACT_TIME:
					_wants_to_extract = true
			else:
				# Min 30s, max 300s alive before this even starts firing.
				var shift_duration = lerpf(300.0, 30.0, 1.0 - enemy.personality.courage)
				if _time_alive_seconds() > shift_duration:
					var leave_rate_per_sec = 0.15 + enemy.personality.greed * 0.3
					if randf() < leave_rate_per_sec * dt:
						_wants_to_extract = true


# A squad member's travel: to its slot beside or behind the leader
# (Squad.travel_goal; round the hold point under a hold order), on the
# leader's heels when it is leaving, at a pace that closes the gap,
# sprinting after it when far behind or ordered to regroup. In its slot it
# stands and watches for targets. A companion under orders fires on the move
# at a target in sight (the fire controller), without leaving its slot.
func do_follow(dt, enemy):
	if not is_instance_valid(enemy):
		return
	aiming_at_enemy = false
	_check_targets(enemy)
	var squad = enemy.knowledge.squad
	var target = enemy.valid_target if enemy.valid_target and is_instance_valid(enemy.valid_target) else null
	if target != null and enemy.is_seeing(target) and not enemy.holds_fire_at(target):
		var state = _get_self_state(enemy)
		enemy.ai_aim_point = enemy.compute_lead_point(target) if enemy.can_see_target(target) else enemy.get_target_position(target)
		if not state.is_hot and not state.no_ammo:
			_fire(dt, enemy, target, true, _get_effective_distances(enemy), state)
		else:
			enemy.fire.cease()
	else:
		enemy.fire.cease()
		enemy.fire.shoot_devices(dt)
	if squad == null or not squad.leader_alive():
		return
	var goal: Vector2 = squad.leader.global_position if squad.intent() == "extract" else squad.travel_goal(enemy)
	if goal == Vector2.INF:
		return
	var dist: float = enemy.global_position.distance_to(goal)
	if dist <= FOLLOW_SLACK:
		enemy.going_to_position = false
		point_of_interest = false
		enemy.decrease_throttle(0, 0.05)
		enemy.navigate_to_target(dt, 0.0, 0.0, false)
		return
	enemy.going_to_position = true
	point_of_interest = goal
	enemy.NavAgent.target_position = goal
	# Pace: full ahead when the gap is a spacing or more, easing in near it.
	var pace := clampf(dist / Squad.SPACING, 0.4, 1.0)
	if enemy.throttle < pace:
		enemy.increase_throttle(pace, dt / THROTTLE_CHANGE_TIME)
	else:
		enemy.decrease_throttle(pace, dt / THROTTLE_CHANGE_TIME)
	enemy.navigate_to_target(dt, 0.0, 0.0, dist > Squad.REGROUP_DISTANCE or squad.order == "regroup")


# A Rat's lure: a fake help call in Local, then it lies in wait where it
# stands for LURE_TIME (score_ambush, do_ambush).
func _lure(enemy) -> void:
	enemy.broadcast("need_help")
	_lure_until = enemy.knowledge.now() + LURE_TIME
	_lure_point = enemy.global_position
	AICombatLog.record_info("rat_lie")


# Going to help: a squadmate in trouble, where it is (squad radio), or a
# help call's blurred spot; lit, watching for targets, dropping the lead on
# arrival or once it has gone stale.
func do_help(dt, enemy):
	if not is_instance_valid(enemy):
		return
	aiming_at_enemy = false
	_check_targets(enemy)
	enemy.fire.shoot_devices(dt)
	var goal := Vector2.INF
	if _help_mate != null and is_instance_valid(_help_mate):
		goal = _help_mate.global_position
	elif not _help_lead.is_empty():
		goal = _help_lead.position
	if goal == Vector2.INF:
		return
	_ramp_throttle_full(dt, enemy)
	if enemy.global_position.distance_to(goal) > POSITIONAL_ACCURACY:
		enemy.going_to_position = true
		point_of_interest = goal
		enemy.NavAgent.target_position = goal
		enemy.navigate_to_target(dt, 0.0, 0.0, enemy.knowledge.panic < PANIC_SPRINT)
	else:
		# There: the call is answered as far as it can be.
		if not _help_lead.is_empty():
			enemy.knowledge.drop_lead(_help_lead)
			_help_lead = {}
		enemy.going_to_position = false
		point_of_interest = false
	shield_check(enemy)


# Vulturing: to a covered spot VULTURE_STANDOFF from the fight, dark, at
# half throttle, watching it, until the shooting has stopped for
# VULTURE_QUIET s; then whoever it sees there is prey (hostility, so the
# target rules let it engage). Seeing nobody, it goes in toward the spot
# (the picker's choice VULTURE_LOOK from it, or straight there if the picker
# keeps it where it stands); within VULTURE_LOOK * 1.5 of the spot with
# nobody in sight, it has looked (_vulture_looked) and the intent ends.
func do_vulture(dt, enemy):
	if not is_instance_valid(enemy):
		return
	_vulture_time += dt
	aiming_at_enemy = false
	_check_targets(enemy)
	var heard := _fight_heard(enemy, _vulture_done_at)
	if heard != Vector2.INF:
		_vulture_point = heard
	if _vulture_point == Vector2.INF:
		return
	enemy.ai_aim_point = _vulture_point
	if enemy.throttle > 0.5:
		enemy.decrease_throttle(false, dt / THROTTLE_CHANGE_TIME)
	else:
		enemy.increase_throttle(0.5, 0.5)
	# The fight over: the survivors it sees are prey. It stands off further
	# than its engage range, so it closes on the nearest to its kite range,
	# where the target rules pick it up and engage takes over.
	var prey = null
	var quiet := _quiet_for(enemy) >= VULTURE_QUIET
	if quiet:
		var prey_dist := INF
		for body in enemy.knowledge.seen_bodies():
			if body.is_in_group("entity") or (enemy.knowledge.squad != null and enemy.knowledge.squad.is_in(body)):
				continue
			enemy.add_hostility(body, VULTURE_HOSTILITY)
			var d: float = enemy.global_position.distance_to(enemy.get_target_position(body))
			if d < prey_dist:
				prey = body
				prey_dist = d
	var standoff := VULTURE_STANDOFF
	var looking := false
	if prey != null:
		_vulture_point = enemy.get_target_position(prey)
		standoff = _get_effective_distances(enemy).max_kite
		_ramp_throttle_full(dt, enemy)
	elif quiet:
		if enemy.global_position.distance_to(_vulture_point) <= VULTURE_LOOK * 1.5:
			_vulture_looked = true
		looking = true
		standoff = VULTURE_LOOK
	if _tactical_move(dt, enemy, _vulture_point, standoff, VULTURE_WEIGHTS, false, _vulture_point):
		pass
	elif looking and not _vulture_looked:
		point_of_interest = _vulture_point
		enemy.going_to_position = true
		_push_poi_to_nav(enemy)
		enemy.navigate_to_target(dt, 0, 0, false)
		_clear_arrival(enemy)
	else:
		enemy.going_to_position = false
		point_of_interest = false
	shield_check(enemy)


# A sound that is a fight: gunfire or a blast.
static func _is_gunfire(sound: Dictionary) -> bool:
	return sound.type == "shooting" or sound.type == "gunshot" or sound.type == "explosion"


# Seconds since the last gunfire this NPC heard (INF for none remembered).
func _quiet_for(enemy) -> float:
	var newest := -INF
	for sound in enemy.knowledge.sounds:
		if sound.volume_type == "loud" and _is_gunfire(sound):
			newest = maxf(newest, float(sound.lifetime))
	if newest == -INF:
		return INF
	return float(enemy.SOUND_LIFETIME) - newest


# Scouting: a sweep toward the trip's goal, else a drone that way, once;
# then the trip goes on, unless the sweep reported strangers: that reading
# is a reason to identify (identify_reason), which outscores the trip.
func do_scout(dt, enemy):
	if not is_instance_valid(enemy):
		return
	_check_targets(enemy)
	enemy.decrease_throttle(0, 0.05)
	enemy.navigate_to_target(dt, 0.0, 0.0, false)
	if _scout_goal == Vector2.INF:
		return
	var dir: Vector2 = enemy.global_position.direction_to(_scout_goal)
	enemy.ai_aim_point = _scout_goal
	var done := false
	if enemy.fire.can_sweep():
		done = enemy.fire.sweep(dir if dir != Vector2.ZERO else enemy.get_facing(), SCOUT_SWEEP_WIDTH)
		if done:
			AICombatLog.record_info("sweep_" + str(enemy.fire.last_sweep.verdict))
	elif enemy.fire.has_internal("drone"):
		done = enemy.fire.launch_drone(_scout_goal)
	if done:
		AICombatLog.record_info("scouted")
	_scouted_at = enemy.knowledge.now()
	_scout_goal = Vector2.INF


# IDENTIFY: "something is out there". The one intent for an unknown or
# unseen track (identify_reason), in this order:
#   a lock wedge (someone locking it now), a shot wedge, a sweep of its own
#   that reported strangers (a scout's, say), an UNKNOWN IR track, a sound
#   wedge, an alarm, a ghost of a mech it holds something against;
# each with no visual on its cause (no body it sees inside the wedge or the
# sweep's cone, or the track's body not in sight), at least its reaction
# delay old (Enemy.reaction_delay; not for its own sweep) and not handled
# already. It picks one response (doctrine_response), by panic (nervous),
# the reason, its type and skill:
#   watch       turn toward it and look (any type under SKILL_TOOLS)
#   scan        a sweep toward it (Hunters, Rats and Scavengers only sweep;
#               Professionals and Guardians send a drone when the sweep
#               isn't ready); what the sweep reads (FireController.read_sweep)
#               decides the next step: nothing there ends it, strangers get
#               the type's step (sweep_response)
#   push        a Hunter: toward the sweep's point, lock searching on the way
#   lock        a lock search on a mech inside the reason's area (the sweep's
#               cone once it has swept; Enemy.lock_search_target, the lock
#               rules decide), a Professional or a Hunter sending its drone
#               there too, a Hunter firing at its lock or a live track
#   confirm     a sweep caught squadmates and more mechs than them: it holds
#               and checks before it acts (_identify_confirm)
#   light       its light on, turned toward it (a Guardian's way to make
#               sure before it fires)
#   flank       a Rat that can't sweep: dark, round to a point beside the
#               track, never a lock
#   leave       away from it, and keeping away (knowledge.set_avoid): a
#               Scavenger that can't sweep, and a Rat or a Scavenger whose
#               sweep reports strangers (backing off from that direction)
#   fire        blind fire at it (fire.blind_fire_at, search's code)
#   smoke       smoke round itself, then break line
#   break_line  to cover from it (the disengage weights)
# It ends when the track becomes visual (engage, or nothing, takes over),
# when it is lost, or after IDENTIFY_TIME s; standing and looking with
# nothing to show for it (watch, light, or lock with nothing in the area to
# lock and no drone out) ends after IDENTIFY_WATCH_TIME s, and investigate
# goes to look. A reason handled once is not taken up again, nor a sweep
# reading. Its score sits under engage when a target is in sight and above
# roam, loot and investigate; a lock warning puts it above a fight
# (SCORE_IDENTIFY_LOCKED), under disengage and flee. A companion under
# orders, or an NPC with its Flag up, doesn't run it.

## Placeholders.
const SCORE_IDENTIFY := 0.42
const SCORE_IDENTIFY_LOCKED := 0.78
const IDENTIFY_TIME := 15.0
const IDENTIFY_WATCH_TIME := 5.0
## The skill breakpoints (see NPC AI.md): from SKILL_TOOLS a sweep or a drone
## to identify a track; from SKILL_LIGHT_DISCIPLINE flashing its light; from
## SKILL_LOCK_BACK a lock search back at whoever locks it (a lock search on a
## shot wedge from Enemy.SKILL_LOCK_ON_WEDGE).
const SKILL_TOOLS := 0.3
const SKILL_LIGHT_DISCIPLINE := 0.5
const SKILL_LOCK_BACK := 0.7
## Nervous: above this panic, an NPC with at least NERVOUS_COURAGE fires at
## any track, one with less leaves on any track.
const NERVOUS_PANIC := 0.5
const NERVOUS_COURAGE := 0.4
## How far (px) leaving takes it from a track, and how far beside a track a
## Rat goes round.
const IDENTIFY_LEAVE_DISTANCE := 2500.0
const IDENTIFY_FLANK_DISTANCE := 1200.0
## Sweep readings (FireController.read_sweep): one with strangers is a reason
## for SWEEP_READING_FRESH s; it gives no distance, so its point is
## SWEEP_GUESS px along it; one wider than SWEEP_AIMED_WIDTH points nowhere
## (a Hunter's sweep back all round) and is no reason. Confirming keeps the
## second sweep CONFIRM_MATE_CLEARANCE px clear of each squadmate.
const SWEEP_READING_FRESH := 10.0
const SWEEP_GUESS := 3000.0
const SWEEP_AIMED_WIDTH := 180.0
const CONFIRM_MATE_CLEARANCE := 300.0
## The responses.
const RESPONSES := ["watch", "scan", "push", "lock", "confirm", "light", "flank", "leave", "fire", "smoke", "break_line"]
## Reason kinds by urgency, first first.
const REASON_RANK := {"lock": 0, "shot": 1, "sweep": 2, "ir": 3, "sound": 4, "alarm": 5, "ghost": 6}

# The reason being handled ({kind, point, key, wedge or contact, body; a
# sweep reading once it has one, "sweep"; a point a squadmate settled,
# "fix"}), what it does about it, how long it has, and what is done already.
var _identify := {}
var _identify_response := ""
var _identify_time := 0.0
var _identify_scanned := false
var _identify_drone := false
var _identify_smoked := false
var _identify_leave_to := Vector2.INF
var _confirm_swept := false
# Reasons already handled (their keys), not taken up again.
var _identified := {}


func score_identify(enemy) -> float:
	if enemy.is_flagged() or enemy.is_exposed or _under_orders(enemy):
		return 0.0
	if _current(enemy) == "identify":
		if _identify_time >= IDENTIFY_TIME or not _identify_holds(enemy):
			return 0.0
		return SCORE_IDENTIFY_LOCKED if _identify.get("kind") == "lock" else SCORE_IDENTIFY
	# A target of its own, seen or lost, is engage's or search's: only a lock
	# on it takes the NPC from that.
	var fighting: bool = enemy.valid_target and is_instance_valid(enemy.valid_target)
	var reason := identify_reason(enemy, fighting)
	if reason.is_empty():
		return 0.0
	if reason.kind == "lock":
		return SCORE_IDENTIFY_LOCKED
	return 0.0 if fighting else SCORE_IDENTIFY


# A companion the player has given an order (SCORE_ORDER's intents).
func _under_orders(enemy) -> bool:
	var squad = enemy.knowledge.squad
	return squad != null and squad.is_player_led() and squad.order != "free"


## The most urgent unknown or unseen track this NPC hasn't handled (see
## above): {kind, point, key, and wedge, or contact and body}; {} for none.
## With `locks_only`, only a lock on it counts (an NPC busy with a target of
## its own).
func identify_reason(enemy, locks_only := false) -> Dictionary:
	var store: ContactStore = enemy.contacts
	var delay: float = enemy.reaction_delay()
	var seen: Array = enemy.knowledge.seen_bodies()
	var best := {}
	var best_rank := 99
	for wedge in store.wedges({"live": true}):
		var rank: int = REASON_RANK.get(wedge.source, 99)
		if rank >= best_rank or store.now - float(wedge.since) < delay:
			continue
		if wedge.source == "lock":
			if store.now - float(wedge.time) > Mecha.LOCK_WARNING_FRESH:
				continue
		elif locks_only:
			continue
		var key := "%s@%s" % [wedge.source, str(wedge.since)]
		if _identified.has(key) or _seen_inside(seen, wedge):
			continue
		best = {"kind": wedge.source, "point": ContactStore.estimate_point(wedge), "key": key, "wedge": wedge}
		best_rank = rank
	if locks_only or best_rank == 0:
		return best
	var reading: Dictionary = enemy.fire.last_sweep
	if REASON_RANK.sweep < best_rank and not reading.is_empty() and reading.verdict != "none" \
			and float(reading.width) < SWEEP_AIMED_WIDTH and store.now - float(reading.time) <= SWEEP_READING_FRESH:
		var sweep_key := _sweep_key(reading)
		if not _identified.has(sweep_key) and not _stranger_seen_in(enemy, reading):
			best = {"kind": "sweep", "point": sweep_point(reading), "key": sweep_key, "sweep": reading}
			best_rank = REASON_RANK.sweep
	var squad = enemy.knowledge.squad
	for contact in store.view():
		var kind := ""
		if contact.live and contact.source == IRSensing.SOURCE:
			kind = "ir"
		elif contact.live and contact.source == "alarm":
			kind = "alarm"
		elif not contact.live and contact.kind == "mech" and contact.body != null:
			kind = "ghost"
		else:
			continue
		var rank: int = REASON_RANK[kind]
		if rank >= best_rank or store.now - float(contact.since) < delay:
			continue
		var body = contact.body
		if body != null:
			if not is_instance_valid(body) or body.get("is_dead") == true or enemy.is_seeing(body):
				continue
			if squad != null and squad.is_in(body):
				continue
			# A mech it holds something against (should_attack is too heavy to
			# ask of every ghost every think).
			if kind == "ghost" and enemy.get_relationship(body).hostility <= 0.0:
				continue
		var key := "%s:%d@%s" % [kind, int(contact.body_id), str(contact.since)]
		if _identified.has(key):
			continue
		best = {"kind": kind, "point": contact.position, "key": key, "contact": contact, "body": body}
		best_rank = rank
	return best


# Whether any of the bodies seen is inside the wedge (its cause is visual).
static func _seen_inside(seen: Array, wedge: Dictionary) -> bool:
	for body in seen:
		if is_instance_valid(body) and ContactStore.wedge_contains(wedge, body.global_position):
			return true
	return false


# Whether it sees a mecha that isn't a squadmate inside a sweep's cone: the
# sweep's returns are visual.
func _stranger_seen_in(enemy, reading: Dictionary) -> bool:
	var squad = enemy.knowledge.squad
	for body in enemy.knowledge.seen_bodies():
		if not is_instance_valid(body) or body.is_in_group("entity") or (squad != null and squad.is_in(body)):
			continue
		if FireController.in_sweep(reading, body.global_position):
			return true
	return false


## Where a sweep reading puts what it found: SWEEP_GUESS px along it (a
## sweep gives no distance).
static func sweep_point(reading: Dictionary) -> Vector2:
	return Vector2(reading.origin) + Vector2(reading.direction).normalized() * SWEEP_GUESS


static func _sweep_key(reading: Dictionary) -> String:
	return "sweep@%s#%s" % [str(reading.get("time", 0.0)), str(reading.get("serial", 0))]


## The response this NPC makes to `reason` (see above), by panic, the
## reason, its type and its skill.
func doctrine_response(enemy, reason: Dictionary) -> String:
	var p = enemy.personality
	var type = p.type if p != null else Personality.Type.PROFESSIONAL
	var skill: float = enemy.skill()
	if enemy.knowledge.panic > NERVOUS_PANIC:
		return "fire" if p == null or p.courage >= NERVOUS_COURAGE else "leave"
	if reason.get("kind") == "sweep":
		return sweep_response(enemy, reason.sweep)
	if type == Personality.Type.SCAVENGER:
		return "scan" if reason.get("kind") != "lock" and _can_sweep_scan(enemy) else "leave"
	if reason.get("kind") == "lock":
		if type != Personality.Type.RAT and skill >= SKILL_LOCK_BACK:
			return "lock"
		if enemy.fire.has_smoke():
			return "smoke"
		return "break_line"
	if type == Personality.Type.RAT:
		return "scan" if _can_sweep_scan(enemy) else "flank"
	if type == Personality.Type.GUARDIAN:
		return "scan" if _can_scan(enemy) else "light"
	if skill < SKILL_TOOLS:
		return "watch"
	if type == Personality.Type.PROFESSIONAL and _can_scan(enemy):
		return "scan"
	if type == Personality.Type.HUNTER and _can_sweep_scan(enemy):
		return "scan"
	return "lock"


## What `enemy` does about a sweep reading with strangers in it: one that
## also caught squadmates is confirmed first ("confirm"; a Scavenger may just
## back off instead, by its courage), else the type's step (_sweep_step).
func sweep_response(enemy, reading: Dictionary) -> String:
	var p = enemy.personality
	var type = p.type if p != null else Personality.Type.PROFESSIONAL
	if reading.get("verdict") == "ambiguous":
		if type == Personality.Type.SCAVENGER and randf() >= (p.courage if p != null else 0.5):
			return "leave"
		return "confirm"
	return _sweep_step(type)


# A type's step on strangers a sweep reported: a Hunter pushes that way to
# get a lock, a Professional sends its drone and lock searches where it
# stands, a Guardian lights it up, a Rat or a Scavenger backs off from it.
static func _sweep_step(type) -> String:
	match type:
		Personality.Type.HUNTER:
			return "push"
		Personality.Type.PROFESSIONAL:
			return "lock"
		Personality.Type.GUARDIAN:
			return "light"
	return "leave"


func _can_scan(enemy) -> bool:
	return enemy.skill() >= SKILL_TOOLS and (enemy.fire.can_sweep() or enemy.fire.has_internal("drone"))


# A scan that can only be a sweep (Hunters, Rats, Scavengers).
func _can_sweep_scan(enemy) -> bool:
	return enemy.skill() >= SKILL_TOOLS and enemy.fire.can_sweep()


func enter_identify(enemy):
	_identify = identify_reason(enemy)
	_identify_time = 0.0
	_identify_scanned = false
	_identify_drone = false
	_identify_smoked = false
	_identify_leave_to = Vector2.INF
	_confirm_swept = false
	_identify_response = doctrine_response(enemy, _identify) if not _identify.is_empty() else "watch"
	if _identify_response == "confirm":
		_call_confirm(enemy)
	else:
		enemy.bark("sweep_contact" if _identify.get("kind") == "sweep" else "identifying")
	AICombatLog.record_info("identify_" + _identify_response)


func exit_identify(enemy):
	if not _identify.is_empty():
		_identified[_identify.key] = true
	if is_instance_valid(enemy) and _identify_response in ["lock", "push"] and not enemy.get_locked_to():
		enemy.lock_search_target = null
	_identify = {}
	_identify_response = ""


## What identify is doing now: {"reason": the reason, "response"} ({} when
## it isn't).
func identifying() -> Dictionary:
	return {} if _identify.is_empty() else {"reason": _identify, "response": _identify_response}


# Whether the reason still stands: still there, and its cause not in sight.
# Once it has a sweep reading, until it sees a stranger inside the cone.
func _identify_holds(enemy) -> bool:
	if _identify.is_empty():
		return false
	if _identify.has("sweep"):
		return not _stranger_seen_in(enemy, _identify.sweep)
	if _identify.has("wedge"):
		var wedge: Dictionary = _identify.wedge
		if not enemy.contacts.wedges().has(wedge):
			return false
		if _identify.kind == "lock":
			return not enemy.lock_warning().is_empty()
		if not wedge.live:
			return false
		return not _seen_inside(enemy.knowledge.seen_bodies(), wedge)
	var body = _identify.get("body")
	if body != null and (not is_instance_valid(body) or enemy.is_seeing(body)):
		return false
	var contact: Dictionary = _identify.contact
	if not enemy.contacts.view().has(contact):
		return false
	return contact.live or _identify.kind == "ghost"


# Where the reason puts its cause now: where a squadmate or a confirming
# sweep settled it, else the wedge's estimate, the track, or the point.
func _identify_point() -> Vector2:
	if _identify.has("fix"):
		return _identify.fix
	if _identify.has("wedge"):
		return ContactStore.estimate_point(_identify.wedge)
	if _identify.has("contact"):
		return _identify.contact.position
	return _identify.get("point", Vector2.ZERO)


## A mech inside the reason's area that this NPC could lock (Enemy's lock
## rules: inside the sweep's cone once it has one, inside the wedge, or
## within LOCK_SEARCH_RADIUS of the point), never a squadmate, the nearest
## to the point; null for none. Only what is really there is found, as a
## reticle swept over the area would find it.
func lock_candidate(enemy, reason: Dictionary):
	if reason.is_empty() or not (enemy.arena is Node) or not enemy.arena.has_method("get_mechas"):
		return null
	var point: Vector2
	if reason.has("fix"):
		point = reason.fix
	elif reason.has("wedge"):
		point = ContactStore.estimate_point(reason.wedge)
	elif reason.has("point"):
		point = reason.point
	else:
		point = sweep_point(reason.sweep)
	var squad = enemy.knowledge.squad
	var best = null
	var best_dist := INF
	for mecha in enemy.arena.get_mechas():
		if not is_instance_valid(mecha) or mecha == enemy or not enemy.can_start_lock(mecha):
			continue
		if squad != null and squad.is_in(mecha):
			continue
		var at: Vector2 = mecha.global_position
		var inside: bool
		if reason.has("sweep"):
			inside = FireController.in_sweep(reason.sweep, at)
		elif reason.has("wedge"):
			inside = ContactStore.wedge_contains(reason.wedge, at)
		else:
			inside = at.distance_to(point) <= enemy.LOCK_SEARCH_RADIUS
		if not inside:
			continue
		var dist := at.distance_to(point)
		if dist < best_dist:
			best = mecha
			best_dist = dist
	return best


func do_identify(dt, enemy):
	if not is_instance_valid(enemy) or _identify.is_empty():
		return
	_identify_time += dt
	var point := _identify_point()
	enemy.ai_aim_point = point
	aiming_at_enemy = false
	match _identify_response:
		"leave":
			_identify_leave(dt, enemy, point)
			return
		"flank":
			_identify_flank(dt, enemy, point)
			return
		"push":
			_identify_push(dt, enemy, point)
			return
		"break_line":
			_identify_break_line(dt, enemy, point)
			return
		"smoke":
			if not _identify_smoked:
				_identify_smoked = true
				enemy.fire.screen_self()
			_identify_break_line(dt, enemy, point)
			return
	# The rest stand and turn toward it.
	enemy.decrease_throttle(0, 0.05)
	enemy.navigate_to_target(dt, 0.0, 0.0, false)
	match _identify_response:
		"scan":
			_identify_scan(enemy, point)
		"lock":
			_identify_lock(dt, enemy, point)
		"confirm":
			_identify_confirm(enemy)
		"fire":
			enemy.fire.blind_fire_at(point)
	if _identify_time >= IDENTIFY_WATCH_TIME and _identify_response in ["watch", "light", "lock"] \
			and not _identify_drone and not is_instance_valid(enemy.lock_search_target) and not enemy.get_locked_to():
		_identify_time = IDENTIFY_TIME


# A sweep toward the track (else a drone, for a Professional or a Guardian),
# once. What it reads decides the rest: nothing there (no mech, or only
# squadmates) ends it; strangers get sweep_response, toward the sweep's cone
# from then on.
func _identify_scan(enemy, point: Vector2) -> void:
	if _identify_scanned:
		return
	_identify_scanned = true
	var dir: Vector2 = enemy.global_position.direction_to(point)
	if enemy.fire.can_sweep() and enemy.fire.sweep(dir if dir != Vector2.ZERO else enemy.get_facing(), SCOUT_SWEEP_WIDTH):
		var reading: Dictionary = enemy.fire.last_sweep
		_identified[_sweep_key(reading)] = true
		AICombatLog.record_info("sweep_" + str(reading.verdict))
		if reading.verdict == "none":
			_identify_time = IDENTIFY_TIME
			return
		_identify.sweep = reading
		_identify_response = sweep_response(enemy, reading)
		if _identify_response == "confirm":
			_call_confirm(enemy)
		else:
			enemy.bark("sweep_contact")
	elif enemy.fire.launch_drone(point):
		_identify_drone = true


# A Hunter's push: toward the point at full throttle, lock searching on the
# way (_identify_lock: whatever comes inside the area within its lock
# rules). With a lock it stops to hold it; arriving with nothing to lock
# ends it.
func _identify_push(dt, enemy, point: Vector2) -> void:
	_identify_lock(dt, enemy, point)
	if enemy.get_locked_to():
		enemy.decrease_throttle(0, 0.05)
		enemy.navigate_to_target(dt, 0.0, 0.0, false)
		return
	if enemy.global_position.distance_to(point) <= POSITIONAL_ACCURACY:
		_identify_time = IDENTIFY_TIME
		return
	point_of_interest = point
	enemy.going_to_position = true
	_push_poi_to_nav(enemy)
	_ramp_throttle_full(dt, enemy)
	enemy.navigate_to_target(dt, 0.0, 0.0, false)


# The squad hears it ask (a callout), so the line shows who is confirming.
func _call_confirm(enemy) -> void:
	var squad = enemy.knowledge.squad
	if squad != null:
		squad.callout(enemy, "sweep_confirm")
	else:
		enemy.bark("sweep_confirm")
	AICombatLog.record_info("sweep_confirm")


# Confirming a sweep that caught squadmates and more mechs than them, where
# it stands, turned toward it:
#   - a squadmate (or the player leading the squad) that has a stranger in
#     sight inside the cone settles it: it shares the contact (squad radio)
#     and that is where the type's step (_sweep_step) goes
#   - else, once its sweep is ready, a narrower sweep clear of every mate
#     (_clear_of_mates): strangers in it settle it the same way, toward
#     where that sweep points; none, and it stands down
# Nothing settled by IDENTIFY_TIME, it stands down.
func _identify_confirm(enemy) -> void:
	var reading: Dictionary = _identify.sweep
	var type = enemy.personality.type if enemy.personality != null else Personality.Type.PROFESSIONAL
	var spotted := _mate_spotted(enemy, reading)
	if not spotted.is_empty():
		enemy.knowledge.squad.share_contact(spotted.mate, spotted.body, spotted.position)
		_identify.fix = spotted.position
		_identify_response = _sweep_step(type)
		enemy.bark("sweep_contact")
		AICombatLog.record_info("sweep_confirmed")
		return
	if _confirm_swept or not enemy.fire.can_sweep():
		return
	var gap := _clear_of_mates(enemy, reading)
	if gap.is_empty():
		return
	_confirm_swept = true
	if not enemy.fire.sweep(gap.direction, gap.width):
		return
	var again: Dictionary = enemy.fire.last_sweep
	_identified[_sweep_key(again)] = true
	if int(again.unknown) > 0:
		_identify.sweep = again
		_identify.fix = sweep_point(again)
		_identify_response = _sweep_step(type)
		enemy.bark("sweep_contact")
		AICombatLog.record_info("sweep_confirmed")
	else:
		_identify_time = IDENTIFY_TIME
		AICombatLog.record_info("sweep_stood_down")


# A stranger that a squadmate (or the player leading the squad) has in
# sight inside the sweep's cone: {"body", "position", "mate"}; {} for none.
func _mate_spotted(enemy, reading: Dictionary) -> Dictionary:
	var squad = enemy.knowledge.squad
	if squad == null:
		return {}
	var mates: Array = squad.mates_of(enemy)
	if squad.is_player_led() and not is_same(squad.leader, enemy):
		mates.append(squad.leader)
	for mate in mates:
		var store = mate.get("contacts")
		if not (store is ContactStore):
			continue
		for contact in store.live_from("sight"):
			var body = contact.body
			if body == null or not is_instance_valid(body) or not body.is_in_group("mecha") or body.get("is_dead") == true:
				continue
			if squad.is_in(body) or is_same(body, enemy):
				continue
			if FireController.in_sweep(reading, contact.position):
				return {"body": body, "position": contact.position, "mate": mate}
	return {}


## The widest part of a sweep reading's cone, seen from where `enemy` stands
## now, that keeps CONFIRM_MATE_CLEARANCE px clear of every squadmate in it:
## {"direction", "width" (degrees)}; {} if no part is SWEEP_MIN_WIDTH wide.
func _clear_of_mates(enemy, reading: Dictionary) -> Dictionary:
	var origin: Vector2 = enemy.global_position
	var centre: float = Vector2(reading.direction).angle()
	var half := deg_to_rad(float(reading.width)) * 0.5
	var squad = enemy.knowledge.squad
	var blocked: Array = []
	if squad != null:
		var mates: Array = squad.mates_of(enemy)
		if squad.is_player_led() and not is_same(squad.leader, enemy):
			mates.append(squad.leader)
		for mate in mates:
			var offset: Vector2 = mate.global_position - origin
			var distance := offset.length()
			if distance <= 0.0 or distance > Mecha.SWEEP_RANGE:
				continue
			var at := angle_difference(centre, offset.angle())
			var pad := asin(minf(CONFIRM_MATE_CLEARANCE / distance, 1.0))
			if absf(at) - pad > half:
				continue
			blocked.append(Vector2(at - pad, at + pad))
	blocked.sort_custom(func(a, b): return a.x < b.x)
	var best_from := 0.0
	var best_width := -1.0
	var from := -half
	for span in blocked:
		if span.x - from > best_width:
			best_width = span.x - from
			best_from = from
		from = maxf(from, span.y)
	if half - from > best_width:
		best_width = half - from
		best_from = from
	if rad_to_deg(best_width) < Mecha.SWEEP_MIN_WIDTH:
		return {}
	return {"direction": Vector2.from_angle(centre + best_from + best_width * 0.5), "width": rad_to_deg(best_width)}


# A lock search on a mech inside the reason's area; a Professional or a
# Hunter sends its drone there too; a Hunter fires at its lock, or blind at
# a live track, without visual. A lock made on a mech it would fight makes
# that mech its target: engage takes over, lights up to get visual and aim,
# and fires.
func _identify_lock(dt, enemy, point: Vector2) -> void:
	if not is_instance_valid(enemy.lock_search_target) and not enemy.get_locked_to():
		var found = lock_candidate(enemy, _identify)
		if found != null:
			enemy.lock_search_target = found
	var made = enemy.get_locked_to()
	if made and not enemy.valid_target and enemy.should_attack(made):
		enemy.valid_target = made
	var type = enemy.personality.type
	if not _identify_drone and (type == Personality.Type.HUNTER or type == Personality.Type.PROFESSIONAL) \
			and enemy.fire.has_internal("drone"):
		_identify_drone = enemy.fire.launch_drone(point)
	if type != Personality.Type.HUNTER:
		return
	var locked = enemy.get_locked_to()
	if locked:
		var eff = _get_effective_distances(enemy)
		enemy.fire.engage(dt, locked, false, eff, _get_self_state(enemy), false)
	elif _identify.kind == "ir" and _identify.contact.live:
		enemy.fire.blind_fire_at(point)


# Away from the track and keeping away, as from an alarm: a point
# IDENTIFY_LEAVE_DISTANCE off on the far side, picked once.
func _identify_leave(dt, enemy, point: Vector2) -> void:
	enemy.knowledge.set_avoid(point)
	if _identify_leave_to == Vector2.INF:
		var away: Vector2 = (enemy.global_position - point).normalized()
		if away == Vector2.ZERO:
			away = -enemy.get_facing()
		_identify_leave_to = enemy.global_position + away * IDENTIFY_LEAVE_DISTANCE
	point_of_interest = _identify_leave_to
	enemy.going_to_position = true
	_push_poi_to_nav(enemy)
	_ramp_throttle_full(dt, enemy)
	enemy.navigate_to_target(dt, 0, 0, false)


# A Rat round to a point beside the track, dark and at half throttle, to get
# behind whatever is there.
func _identify_flank(dt, enemy, point: Vector2) -> void:
	var side: Vector2 = (point - enemy.global_position).orthogonal().normalized()
	point_of_interest = point + side * IDENTIFY_FLANK_DISTANCE
	enemy.going_to_position = true
	_push_poi_to_nav(enemy)
	enemy.decrease_throttle(0.5, 0.01)
	enemy.navigate_to_target(dt, 0, 0, false)


# To cover from the track (the disengage weights, as breaking contact).
func _identify_break_line(dt, enemy, point: Vector2) -> void:
	if not _tactical_move(dt, enemy, point, 0.0, DISENGAGE_WEIGHTS, true):
		enemy.decrease_throttle(0, 0.05)
		enemy.navigate_to_target(dt, 0.0, 0.0, false)


# The leader calls a straggler back (Squad.call_regroup).
func _lead_squad(enemy) -> void:
	var squad = enemy.knowledge.squad
	if squad == null or not squad.is_leader(enemy):
		return
	for mate in squad.mates_of(enemy):
		if squad.strayed(mate):
			squad.call_regroup(enemy)
			return


# Three leads, in order: where it was shot from (alert: shield ready, go
# there, then look round for quiet sounds), a loud noise (seek), and
# otherwise wary wandering that follows quiet sounds (alert roam).
func do_investigate(dt, enemy):
	if not is_instance_valid(enemy):
		return
	aiming_at_enemy = false
	_ramp_throttle_full(dt, enemy)
	_wary_time = maxf(_wary_time - dt, 0.0)
	if enemy.under_fire_timer > 0:
		_wary_time = WARY_TIME
	if enemy.under_fire_timer > 0 or enemy.last_attack_position:
		shield_check(enemy)
		_check_targets(enemy)
		if enemy.last_attack_position:
			if enemy.global_position.distance_to(enemy.last_attack_position) > POSITIONAL_ACCURACY:
				point_of_interest = enemy.last_attack_position
				enemy.going_to_position = true
			else:
				# The lead is used up.
				enemy.last_attack_position = false
		_investigate_quiet_noise(enemy)
		_push_poi_to_nav(enemy)
		_clear_arrival(enemy)
		enemy.navigate_to_target(dt, 0, 0, false)
	elif enemy.get_loud_lead():
		_investigate_loud_noise(enemy)
		_push_poi_to_nav(enemy)
		enemy.navigate_to_target(dt, 0, 0, false)
		_clear_arrival(enemy)
		_check_targets(enemy)
	elif not _loot_lead_for(enemy).is_empty():
		# A loot shout: to its blurred spot, then the lead is used up.
		_loot_lead = _loot_lead_for(enemy)
		if enemy.global_position.distance_to(_loot_lead.position) > POSITIONAL_ACCURACY:
			point_of_interest = _loot_lead.position
			enemy.going_to_position = true
		else:
			enemy.knowledge.drop_lead(_loot_lead)
			_loot_lead = {}
			enemy.going_to_position = false
			point_of_interest = false
		_push_poi_to_nav(enemy)
		_check_targets(enemy)
		enemy.navigate_to_target(dt, 0, 0, false)
		_clear_arrival(enemy)
	else:
		_wander_if_idle(enemy)
		_investigate_quiet_noise(enemy)
		_drop_shield(enemy)
		_push_poi_to_nav(enemy)
		_check_targets(enemy)
		enemy.fire.shoot_devices(dt)
		enemy.navigate_to_target(dt, 0, 0, false)
		_clear_arrival(enemy)


# Lying in wait where something quiet was heard: a covered spot with a view
# of where it will come from (the position picker), a ward out, a mine on
# the approach, at half throttle.
func do_ambush(dt, enemy):
	if is_instance_valid(enemy):
		_ambush_time += dt
		aiming_at_enemy = false
		# Ambush idles at half throttle — quieter, harder to detect.
		if enemy.throttle > 0.5:
			enemy.decrease_throttle(false, dt/THROTTLE_CHANGE_TIME)
		else:
			enemy.increase_throttle(0.5, 0.5)
		_check_targets(enemy)
		var noise = enemy.get_most_recent_quiet_noise()
		if not noise:
			noise = enemy.get_most_recent_loud_noise()
		if not noise and enemy.knowledge.now() < _lure_until:
			# Lying in wait for whoever its fake call brings: it watches the
			# way it came from, where it stands.
			noise = {"position": _lure_point + enemy.get_facing() * 600.0}
		if noise:
			var approach: Vector2 = noise.position
			enemy.ai_aim_point = approach
			if not _ambush_ward:
				_ambush_ward = true
				enemy.fire.place_ward()
			if not _ambush_mine:
				_ambush_mine = true
				enemy.fire.lay_mine(enemy.global_position + enemy.global_position.direction_to(approach) * MINE_LAY_DISTANCE)
			var eff = _get_effective_distances(enemy)
			if not _tactical_move(dt, enemy, approach, eff.max_kite * 0.8, AMBUSH_WEIGHTS, false, approach):
				# In position: hold here and watch.
				enemy.going_to_position = false
				point_of_interest = false
		else:
			_wander_if_idle(enemy)
			_push_poi_to_nav(enemy)
			enemy.navigate_to_target(dt, 0, 0)
			_clear_arrival(enemy)
		shield_check(enemy)


# Moves toward the position picker's choice against a foe believed at
# `foe_pos` (see Positioning.choose). Returns false when the NPC is already
# there, or nothing beats where it stands. Panicked, it sprints.
func _tactical_move(dt, enemy, foe_pos: Vector2, wanted_range: float, weights: Dictionary, sprint: bool,
		watch := Vector2.INF, foe_facing := Vector2.ZERO, anchor := Vector2.INF) -> bool:
	var picker: Positioning = enemy.positioning
	if picker.due(enemy, foe_pos):
		picker.choose(enemy, foe_pos, wanted_range, weights, foe_pos, watch, foe_facing, anchor)
	if not picker.has_pick():
		return false
	var target: Vector2 = picker.pick_position()
	if enemy.global_position.distance_to(target) <= PICK_ARRIVE:
		return false
	enemy.going_to_position = true
	point_of_interest = target
	enemy.NavAgent.target_position = target
	enemy.increase_throttle(1, 0.01)
	enemy.navigate_to_target(dt, 0.0, 0.0, sprint or enemy.knowledge.panic >= PANIC_SPRINT)
	return true


# Whether `target` isn't watching `enemy`: fighting someone else, looting,
# or facing away (what a stalker waits for).
func _is_distracted(enemy, target) -> bool:
	if "valid_target" in target and target.get("logic") != null:
		# An NPC: fighting someone else, or looting.
		var their_target = target.valid_target
		if their_target and is_instance_valid(their_target) and not is_same(their_target, enemy):
			return true
		if str(target.logic.get_current_state()) == "loot":
			return true
	elif target.get("current_open_container") != null:
		return true
	if target.has_method("get_facing"):
		var facing: Vector2 = target.get_facing()
		var to_enemy: Vector2 = target.global_position.direction_to(enemy.global_position)
		return facing.dot(to_enemy) < -0.2
	return false


# A Flagged or badly damaged mech in the Guardian's knowledge that isn't
# hostile to it, the nearest, or null.
func _find_protege(enemy):
	# Squadmates first: a Flagged or hurt mate, wherever it is (squad radio).
	var squad = enemy.knowledge.squad
	if squad != null:
		var mate_best = null
		var mate_dist := INF
		for mate in squad.mates_of(enemy):
			if not (mate.get("flag_up") == true or NPCKnowledge._structural_health(mate) <= PROTECT_DAMAGE):
				continue
			var d: float = enemy.global_position.distance_to(mate.global_position)
			if d < mate_dist:
				mate_best = mate
				mate_dist = d
		if mate_best != null:
			return mate_best
	var best = null
	var best_dist := INF
	for entry in enemy.knowledge.known_mechas():
		var body = entry.body
		if not _protege_valid(enemy, body):
			continue
		var d: float = enemy.global_position.distance_to(entry.position)
		if d < best_dist:
			best = body
			best_dist = d
	return best


func _protege_valid(enemy, body) -> bool:
	if body == null or not is_instance_valid(body) or body == enemy or body.get("is_dead") == true:
		return false
	# A squadmate is known by radio, and worth protecting Flagged or hurt.
	var squad = enemy.knowledge.squad
	if squad != null and squad.is_in(body):
		return body.get("flag_up") == true or NPCKnowledge._structural_health(body) <= PROTECT_DAMAGE
	if not enemy.knowledge.knows(body) or body.is_in_group("entity"):
		return false
	var rel = enemy.get_relationship(body)
	if rel.is_traitor or rel.hostility >= 0.3:
		return false
	return body.get("flag_up") == true or enemy.knowledge.health_of(body) <= PROTECT_DAMAGE


# Finishing a Flagged mech, in the open: it says so, closes in lit and
# deliberately, and fires only after the grace window's length has passed
# since it decided to.
func do_execute(dt, enemy):
	if not is_instance_valid(enemy):
		return
	_check_targets(enemy)
	var target = enemy.valid_target
	if not target or not is_instance_valid(target):
		return
	_execute_time += dt
	enemy.current_target = target
	var pos: Vector2 = enemy.get_target_position(target)
	enemy.ai_aim_point = pos
	if not _execute_barked:
		_execute_barked = true
		enemy.bark("traitor" if enemy.get_relationship(target).is_traitor else "execute", target)
		AICombatLog.record_flag("executed")
	var eff = _get_effective_distances(enemy)
	var distance: float = enemy.global_position.distance_to(pos)
	enemy.going_to_position = true
	point_of_interest = pos
	enemy.NavAgent.target_position = pos
	if distance > eff.cqb:
		enemy.increase_throttle(1, 0.01)
		enemy.navigate_to_target(dt, 0.0, 0.3, false)
	else:
		enemy.decrease_throttle(0, 0.05)
		enemy.navigate_to_target(dt, 0.0, 0.0, false)
	if _execute_time >= Mecha.FLAG_GRACE_TIME and distance < eff.max_shoot:
		enemy.fire.engage(dt, target, enemy.is_seeing(target), eff, _get_self_state(enemy), false)
	else:
		enemy.fire.cease()


# A Rat's stalk: Flag up, it follows a distracted target round to its back,
# and lowers the Flag once close behind it; engage takes over when the Flag
# is down.
func do_stalk(dt, enemy):
	if not is_instance_valid(enemy):
		return
	_check_targets(enemy)
	var target = enemy.valid_target
	if not target or not is_instance_valid(target):
		return
	if not _stalk_raised:
		_stalk_raised = true
		if not enemy.is_flagged():
			enemy.raise_flag(true)
	var pos: Vector2 = enemy.get_target_position(target)
	enemy.ai_aim_point = pos
	var facing: Vector2 = target.get_facing() if target.has_method("get_facing") else Vector2.ZERO
	var eff = _get_effective_distances(enemy)
	var distance: float = enemy.global_position.distance_to(pos)
	var behind: bool = facing != Vector2.ZERO and facing.dot(pos.direction_to(enemy.global_position)) < -0.3
	if distance <= eff.cqb and behind and _is_distracted(enemy, target) and not enemy.is_lowering_flag():
		enemy.lower_flag()
	if not _tactical_move(dt, enemy, pos, eff.cqb * 0.8, STALK_WEIGHTS, false, Vector2.INF, facing):
		enemy.going_to_position = false


# A Guardian by a Flagged or damaged mech: it stays within PROTECT_RANGE,
# lit, watching for threats and shooting enemy devices.
func do_protect(dt, enemy):
	if not is_instance_valid(enemy):
		return
	_check_targets(enemy)
	if not _protege_valid(enemy, _protege):
		_protege = _find_protege(enemy)
		if _protege == null:
			return
	var squad = enemy.knowledge.squad
	var pos: Vector2 = _protege.global_position if squad != null and squad.is_in(_protege) else enemy.knowledge.position_of(_protege)
	enemy.fire.shoot_devices(dt)
	_ramp_throttle_full(dt, enemy)
	if not _tactical_move(dt, enemy, pos, PROTECT_RANGE, PROTECT_WEIGHTS, false):
		enemy.going_to_position = false
	shield_check(enemy)


# Surrender: the Flag is up and the flight runs; left alone by the pilot it
# yielded to for SPARE_TIME, it tells Local it was spared. A Rat whose
# sparer comes close and looks away lowers its Flag again.
func do_raise_flag(dt, enemy):
	if not is_instance_valid(enemy):
		return
	do_flee(dt, enemy)
	_spare_time += dt
	var sparer = _surrendered_to
	if is_instance_valid(sparer):
		if enemy.under_fire_timer > 0 and is_same(enemy.most_recent_attacker, sparer):
			_spare_hurt = true
		if not _spared_noted and not _spare_hurt and _spare_time >= SPARE_TIME:
			_spared_noted = true
			var local = enemy._local_pilots()
			if local != null:
				local.note_spared(enemy, sparer)
			enemy.bark("spared", sparer)
		if enemy.personality.type == Personality.Type.RAT and enemy.is_flagged() and not enemy.is_lowering_flag() \
				and enemy.global_position.distance_to(sparer.global_position) <= FAKE_SURRENDER_RANGE \
				and sparer.has_method("get_facing") \
				and sparer.get_facing().dot(sparer.global_position.direction_to(enemy.global_position)) < -0.2:
			enemy.lower_flag()
			enemy.valid_target = sparer
			_flight_over = true


# Where the NPC's trouble is: its target where it believes it is, else where
# it was last attacked from, else where it last took fire from, else here.
func _threat_position(enemy) -> Vector2:
	if enemy.valid_target and is_instance_valid(enemy.valid_target):
		return enemy.get_target_position(enemy.valid_target)
	if enemy.last_attack_position:
		return enemy.last_attack_position
	var fire_positions: Array[Vector2] = enemy.knowledge.recent_fire_positions()
	if not fire_positions.is_empty():
		return fire_positions[fire_positions.size() - 1]
	return enemy.global_position


# Searching for a lost target from where it was last seen or heard: the
# picker keeps the NPC moving round that spot with a view of it, a sweep
# (Professionals, Hunters) and a drone (Hunters; a Professional too when its
# sweep reported strangers) once, blind and indirect fire at the spot while
# the memory is fresh. A sweep that reported strangers puts a lock search on
# a mech in its cone, the nearest to the spot (lock_candidate).
func do_search(dt, enemy):
	if not is_instance_valid(enemy):
		return
	_check_targets(enemy)
	var target = enemy.valid_target
	if not target or not is_instance_valid(target):
		return
	var last: Vector2 = enemy.get_target_position(target)
	enemy.ai_aim_point = last
	var type = enemy.personality.type
	var dir: Vector2 = enemy.global_position.direction_to(last)
	if not _search_swept and (type == Personality.Type.PROFESSIONAL or type == Personality.Type.HUNTER):
		_search_swept = true
		if enemy.fire.sweep(dir if dir != Vector2.ZERO else enemy.get_facing()):
			var reading: Dictionary = enemy.fire.last_sweep
			_identified[_sweep_key(reading)] = true
			AICombatLog.record_info("sweep_" + str(reading.verdict))
			if reading.verdict != "none":
				_search_reading = reading
	if not _search_drone and (type == Personality.Type.HUNTER
			or (type == Personality.Type.PROFESSIONAL and not _search_reading.is_empty())):
		_search_drone = true
		enemy.fire.launch_drone(last)
	if not _search_reading.is_empty() and not enemy.get_locked_to() and not is_instance_valid(enemy.lock_search_target):
		var found = lock_candidate(enemy, {"sweep": _search_reading, "point": last})
		if found != null:
			enemy.lock_search_target = found
	var eff = _get_effective_distances(enemy)
	var state = _get_self_state(enemy)
	if not state.is_hot and not state.no_ammo and not state.low_ammo:
		enemy.fire.engage(dt, target, false, eff, state, type == Personality.Type.PROFESSIONAL)
		enemy.fire.blind_fire(target)
	_ramp_throttle_full(dt, enemy)
	# Hunters and Professionals follow the trail: the warmest mark near the
	# spot, a step along its heading, is the next spot to search round.
	if type == Personality.Type.HUNTER or type == Personality.Type.PROFESSIONAL:
		_follow_trail(enemy, last)
	var spot: Vector2 = _trail_point if _trail_point != Vector2.INF else last
	if not _tactical_move(dt, enemy, spot, SEARCH_RADIUS, SEARCH_WEIGHTS, false, spot):
		# There: look round somewhere else next.
		enemy.positioning.request()
		enemy.going_to_position = false
	shield_check(enemy)


# Heat trails (HeatTrails.marks_near): from the spot the NPC searches round
# (the last-known position, or the last trail step), the warmest mark
# within TRAIL_RADIUS gives a heading; the next spot is TRAIL_STEP along it.
# Once per search it says whether it found a trail.
func _follow_trail(enemy, last: Vector2) -> void:
	var trails: HeatTrails = HeatTrails.find(enemy)
	if trails == null:
		return
	var from: Vector2 = _trail_point if _trail_point != Vector2.INF else last
	if enemy.global_position.distance_to(from) > SEARCH_RADIUS:
		return
	var best: Dictionary = {}
	for mark in trails.marks_near(from, TRAIL_RADIUS):
		if best.is_empty() or float(mark.warmth) > float(best.warmth):
			best = mark
	if best.is_empty():
		if not _trail_said:
			_trail_said = true
			enemy.bark("lost_trail")
			AICombatLog.record_info("trail_lost")
		return
	_trail_point = Vector2(best.position) + Vector2(best.heading) * TRAIL_STEP
	enemy.positioning.request()
	if not _trail_found:
		_trail_found = true
		_trail_said = true
		enemy.bark("found_trail")
		AICombatLog.record_info("trail_found")


# Breaking contact: to cover away from the foe, dark, shield up when cool,
# smoke round itself, a decoy, a mine on the way the foe will come, guns
# silent until they are cool.
func do_disengage(dt, enemy):
	if not is_instance_valid(enemy):
		return
	_check_targets(enemy)
	_disengage_time += dt
	var foe_pos := _threat_position(enemy)
	enemy.ai_aim_point = foe_pos
	enemy.fire.cease()
	if _can_shield(enemy) and enemy.internal_temp < enemy.overheat_temp * general_heat_threshold:
		enemy.shield_up()
	if not _disengage_smoke:
		_disengage_smoke = true
		enemy.fire.screen_self()
	if not _disengage_decoy and _disengage_time > 0.5:
		_disengage_decoy = true
		enemy.fire.throw_decoy()
	if not _disengage_mine and _disengage_time > 1.0 and foe_pos != enemy.global_position:
		_disengage_mine = true
		enemy.fire.lay_mine(enemy.global_position + enemy.global_position.direction_to(foe_pos) * MINE_LAY_DISTANCE)
	var eff = _get_effective_distances(enemy)
	var state = _get_self_state(enemy)
	var sprint: bool = not state.is_hot
	if not _tactical_move(dt, enemy, foe_pos, eff.max_kite * 1.5, DISENGAGE_WEIGHTS, sprint):
		# Nowhere better in reach: back away from the foe.
		enemy.going_to_position = true
		point_of_interest = foe_pos
		enemy.NavAgent.target_position = foe_pos
		enemy.increase_throttle(1, 0.01)
		enemy.navigate_to_target(dt, 1.0, 0.65, sprint)


func _get_effective_distances(enemy) -> Dictionary:
	var eff = {
		"min_kite": min_kite_distance,
		"max_kite": max_kite_distance,
		"max_shoot": max_shooting_distance,
		"cqb": cqb_distance,
	}
	match enemy.combat_style:
		"balanced":
			var k = enemy.preferred_combat_range / BASE_WEAPON_RANGE
			eff.max_shoot = max_shooting_distance * k
			eff.min_kite = min_kite_distance * k
			eff.max_kite = max_kite_distance * k
			eff.cqb = cqb_distance * k
		"sniper":
			eff.max_shoot = enemy.preferred_combat_range
			eff.min_kite = enemy.preferred_combat_range * 0.75
			eff.max_kite = enemy.preferred_combat_range * 0.9
			eff.cqb = enemy.preferred_combat_range * 0.5
		"brawler":
			eff.max_shoot = enemy.preferred_combat_range
			eff.min_kite = 400
			eff.max_kite = 700
			eff.cqb = 500
		"artillery":
			eff.max_shoot = enemy.preferred_combat_range
			eff.min_kite = enemy.preferred_combat_range * 0.8
			eff.max_kite = enemy.preferred_combat_range
			eff.cqb = enemy.preferred_combat_range * 0.6
	return eff


# --- Self-aware mech state helpers ---

# The NPC's own condition (NPCKnowledge.self_state), with this behaviour's
# heat thresholds. Frame-cached there.
func _get_self_state(enemy) -> Dictionary:
	return enemy.knowledge.self_state(weapon_heat_threshold, general_heat_threshold)


func _self_state_aggression_mod(state: Dictionary) -> float:
	# Returns a modifier based on the mech's own condition
	var mod := 0.0

	if state.is_overheating:
		mod -= 2.0
	elif state.is_hot:
		mod -= 1.0

	if state.no_ammo:
		mod -= 2.0
	elif state.weapons_working == 0:
		mod -= 3.0
	elif state.low_ammo:
		mod -= 0.5

	if state.mobility_damaged:
		mod -= 0.5

	return mod


func _effective_engage_distance(enemy) -> float:
	return engage_distance * enemy.disabled_systems.sensors


# Runs Enemy.check_for_targets with this behaviour's ranges: a target can be
# picked up as far as the NPC can see (engage_distance, or its kite range if
# that is longer, cut by sensor damage) and is kept up to its shooting range.
func _check_targets(enemy) -> void:
	var profile_start := FrameProfiler.start()
	var eff = _get_effective_distances(enemy)
	var engage = maxf(_effective_engage_distance(enemy), eff.max_kite * enemy.disabled_systems.sensors)
	enemy.check_for_targets(engage, maxf(max_shooting_distance, eff.max_shoot))
	FrameProfiler.add("  targets (in behaviour)", profile_start)
	# The player's attack order: its target, once the callout has landed
	# (fairness: the squad contact), over whatever the threat scores said.
	var squad = enemy.knowledge.squad
	if squad != null and squad.order == "attack":
		var ordered = squad.order_target
		if is_instance_valid(ordered) and not ordered.is_dead and not is_same(enemy.valid_target, ordered) \
				and enemy.knowledge.knows(ordered) and enemy.should_attack(ordered):
			enemy.valid_target = ordered
			enemy.positioning.request()


func _should_flee(enemy) -> bool:
	var state = _get_self_state(enemy)

	# No working weapons — can't fight
	if state.weapons_working == 0:
		return true

	# Out of ammo on all weapons
	if state.no_ammo:
		return true

	# Structural health very low — courage determines threshold
	# courage 0.0 -> flee at 40% health
	# courage 0.5 -> flee at 25% health
	# courage 1.0 -> flee at 10% health
	# Panic raises it by up to PANIC_FLEE_HEALTH.
	var flee_threshold = lerpf(0.4, 0.1, enemy.personality.courage) + enemy.knowledge.panic * PANIC_FLEE_HEALTH
	var health = _structural_health(enemy)
	if health < flee_threshold:
		return true

	return false


func _container_usable(container) -> bool:
	return container != null and is_instance_valid(container) and not container.is_open and not container.npc_searched


# The nearest unsearched container within the NPC's search range, or null.
# The scene scan is refreshed every SCAN_INTERVAL s.
func _find_loot_target(enemy):
	var now: float = enemy.knowledge.now()
	if now - _loot_scan_time < SCAN_INTERVAL and _container_usable(_loot_found):
		return _loot_found
	if now - _loot_scan_time < SCAN_INTERVAL and _loot_found == null:
		return null
	_loot_scan_time = now
	var containers = enemy.get_tree().get_nodes_in_group("loot_container")
	var best = null
	var best_dist = INF

	# Scavengers search wider, greedy NPCs moderate, others only loot if very close
	var search_range = 800.0
	if enemy.personality.type == Personality.Type.SCAVENGER:
		search_range = 3000.0
	elif enemy.personality.greed > 0.5:
		search_range = 1500.0

	for container in containers:
		if not _container_usable(container):
			continue
		var dist = enemy.global_position.distance_to(container.global_position)
		if dist < search_range and dist < best_dist:
			best = container
			best_dist = dist

	_loot_found = best
	return best


# The engage intent: close in and lock on, then fight in the attack or defend
# stance.
func do_engage(dt, enemy):
	if not is_instance_valid(enemy):
		return
	# Mid-combat threat re-evaluation (interval-gated inside Enemy) — a
	# flanker shooting us can displace the duel partner. A hard lock-on
	# keeps priority over threat switching. is_same, not !=: current_target
	# is false after a Flagged target is dropped
	# (Enemy.recheck_flagged_target), and != can't compare an Object with
	# a bool.
	_check_targets(enemy)
	if not enemy.valid_target:
		enemy.is_locking = false
		return
	var eff = _get_effective_distances(enemy)
	if stance == "closing":
		if enemy.get_locked_to() or _in_combat_range(enemy):
			_start_fight(enemy)
		else:
			_close_in(dt, enemy, eff)
			return
	if not enemy.get_locked_to() and enemy.valid_target \
			and not is_same(enemy.valid_target, enemy.current_target):
		enemy.current_target = enemy.valid_target
		reaction_timer = 0.0  # re-acquiring: brief aim delay on the new target
	if not is_instance_valid(enemy.current_target):
		return
	stance_time += dt
	var state = _get_self_state(enemy)
	_update_aggression(enemy, state)
	# Stance hysteresis: see STANCE_HYSTERESIS.
	if stance == "attack" and stance_time >= STANCE_MIN_DWELL and aggression <= -STANCE_HYSTERESIS:
		stance = "defend"
		stance_time = 0.0
	elif stance == "defend" and stance_time >= STANCE_MIN_DWELL and aggression >= STANCE_HYSTERESIS:
		stance = "attack"
		stance_time = 0.0
	# The support member may need to turn to cover a mate (_cover_aim).
	_support_cover(enemy)
	if stance == "attack":
		_do_attack(dt, enemy, eff, state)
	else:
		_do_defend(dt, enemy, eff, state)


# Commit to a target: the fight starts. Lock takes precedence over
# proximity sighting. The first stance is a plain sign check on aggression.
func _start_fight(enemy) -> void:
	if enemy.get_locked_to():
		enemy.current_target = enemy.get_locked_to()
	else:
		enemy.current_target = enemy.valid_target
	if enemy.current_target and is_instance_valid(enemy.current_target):
		AICombatLog.record_engage(enemy.global_position.distance_to(enemy.get_target_position(enemy.current_target)))
	shield_check(enemy)
	_update_aggression(enemy, _get_self_state(enemy))
	stance = "attack" if aggression > 0 else "defend"
	stance_time = 0.0


# Closing in on a target out of range: lock on and move to kite range. Under
# fire it drives at full throttle (the old defending_lock); unseen, it eases
# the throttle to approach quietly (the old ambush_lock). Before pushing on a
# target it can't see far off, it puts a flare out there, if it has one.
func _close_in(dt, enemy, eff: Dictionary) -> void:
	aiming_at_enemy = false
	enemy.going_to_position = true
	point_of_interest = enemy.get_target_position(enemy.valid_target)
	var distance = enemy.global_position.distance_to(point_of_interest)
	var under_fire: bool = enemy.under_fire_timer > 0
	if not _flare_used and distance > FLARE_PUSH_DISTANCE and not enemy.is_seeing(enemy.valid_target):
		_flare_used = true
		enemy.fire.fire_flare(point_of_interest)
	if distance < eff.min_kite:
		if under_fire:
			enemy.increase_throttle(1, 0.01)
		else:
			enemy.decrease_throttle(0.25, 0.01)
		enemy.navigate_to_target(dt, 1.0, 0.65)
	elif distance > eff.max_kite:
		if under_fire:
			enemy.increase_throttle(1, 0.01)
		else:
			enemy.decrease_throttle(0.75, 0.01)
		enemy.navigate_to_target(dt, 0.0, 0.65)
	else:
		enemy.decrease_throttle(0, 0.05)
		enemy.navigate_to_target(dt, 1.0, 0.8)
	enemy.is_locking = true
	shield_check(enemy)


func _do_attack(dt, enemy, eff: Dictionary, state: Dictionary) -> void:
	var target = enemy.current_target
	# In sight: lead the target so our weapons track its movement (see
	# compute_lead_point). Out of sight: face where it was last seen or
	# heard, ready to fire blind or as it reappears.
	var seen: bool = enemy.is_seeing(target)
	var target_pos: Vector2 = enemy.get_target_position(target)
	if _cover_aim != null:
		enemy.ai_aim_point = _cover_aim
	elif seen and enemy.can_see_target(target):
		enemy.ai_aim_point = enemy.compute_lead_point(target)
	else:
		enemy.ai_aim_point = target_pos
	var distance: float = enemy.global_position.distance_to(target_pos)
	_drop_shield(enemy)
	_note_sight(enemy, seen)

	# Shooting: check heat, ammo, distance, reaction time
	var can_fire = reaction_timer >= reaction_speed \
		and distance < eff.max_shoot \
		and not state.is_hot \
		and not state.no_ammo
	# Low ammo: conserve — only fire at close range, and never blind
	if state.low_ammo and (distance > eff.cqb or not seen):
		can_fire = false
	if can_fire:
		_fire(dt, enemy, target, seen, eff, state)
	else:
		enemy.fire.cease()
		reaction_timer += dt

	# The support member stands and turns to put smoke on a mate.
	if _cover_aim != null:
		_turn_to_cover(dt, enemy)
		return

	enemy.going_to_position = true

	if seen:
		point_of_interest = target_pos
		aiming_at_enemy = true
	else:
		_search(enemy, target_pos)

	# Don't sprint when hot — sprinting generates heat
	var allow_sprint = not state.is_hot

	# A better spot (range, cover, a line of fire; the flank, for a squad's
	# flanker): go there; otherwise the kite bands round the foe.
	var anchor := _anchor_position(enemy)
	_note_flank(enemy, target_pos, anchor)
	if seen and _tactical_move(dt, enemy, target_pos, (eff.min_kite + eff.max_kite) * 0.5,
			FLANK_WEIGHTS if anchor != Vector2.INF else ENGAGE_WEIGHTS, allow_sprint, Vector2.INF, Vector2.ZERO, anchor):
		return

	if enemy.get_locked_to() and aiming_at_enemy and reaction_timer >= reaction_speed:
		if distance < eff.min_kite:
			enemy.increase_throttle(1, 0.01)
			enemy.navigate_to_target(dt, 1.0, 0.65, allow_sprint)
		elif distance > eff.max_kite:
			enemy.increase_throttle(1, 0.01)
			enemy.navigate_to_target(dt, 0.0, 0.65, allow_sprint)
		else:
			enemy.decrease_throttle(0, 0.05)
			enemy.navigate_to_target(dt, 1.0, 0.8)
	elif aiming_at_enemy and reaction_timer >= reaction_speed:
		if distance > eff.cqb:
			enemy.increase_throttle(1, 0.01)
			enemy.navigate_to_target(dt, 0.0, 0.65, allow_sprint)
		else:
			enemy.increase_throttle(1, 0.01)
			enemy.navigate_to_target(dt, 1.0, 0.65)
	else:
		enemy.increase_throttle(1, 0.01)
		enemy.navigate_to_target(dt, 0.0, 0.65)

	if point_of_interest:
		if enemy.global_position.distance_to(point_of_interest) > POSITIONAL_ACCURACY:
			enemy.NavAgent.target_position = point_of_interest

	if enemy.arrived():
		enemy.going_to_position = false
		point_of_interest = false


# Out of sight: go to where the target was last seen or heard, then look
# round that spot (within SEARCH_RADIUS) until it shows up or the NPC gives up
# on it (Enemy.TARGET_MEMORY_TIME).
func _search(enemy, last_known: Vector2) -> void:
	if aiming_at_enemy:
		# Just lost sight: half a reaction to re-aim at the last-known spot.
		aiming_at_enemy = false
		reaction_timer = minf(reaction_timer, reaction_speed * 0.5)
		point_of_interest = last_known
	elif not point_of_interest:
		if enemy.global_position.distance_to(last_known) > SEARCH_RADIUS:
			point_of_interest = last_known
		else:
			point_of_interest = enemy.get_random_point_on_radius(last_known, SEARCH_RADIUS)


func _do_defend(dt, enemy, eff: Dictionary, state: Dictionary) -> void:
	var target = enemy.current_target
	# Aim as in attack: lead it in sight, face its last-known spot out of
	# sight. Defending holds range from where it is believed to be.
	var seen: bool = enemy.is_seeing(target)
	var target_pos: Vector2 = enemy.get_target_position(target)
	if _cover_aim != null:
		enemy.ai_aim_point = _cover_aim
	elif seen and enemy.can_see_target(target):
		enemy.ai_aim_point = enemy.compute_lead_point(target)
	else:
		enemy.ai_aim_point = target_pos
	var distance: float = enemy.global_position.distance_to(target_pos)
	shield_check(enemy)
	enemy.going_to_position = true
	point_of_interest = target_pos
	_note_sight(enemy, seen)

	# Overheating or out of ammo: retreat harder to create distance
	var retreat_mult = 1.0
	if state.is_overheating or state.no_ammo:
		retreat_mult = 1.5

	# A covered spot at the far edge of the band beats plain kiting (the
	# flank for a squad's flanker). The support member turning to put smoke
	# on a mate stands.
	var anchor := _anchor_position(enemy)
	_note_flank(enemy, target_pos, anchor)
	if _cover_aim != null:
		_turn_to_cover(dt, enemy)
	elif not (seen and retreat_mult == 1.0 and _tactical_move(dt, enemy, target_pos, eff.max_kite,
			FLANK_WEIGHTS if anchor != Vector2.INF else DEFEND_WEIGHTS, false, Vector2.INF, Vector2.ZERO, anchor)):
		if distance < eff.max_kite * retreat_mult:
			enemy.increase_throttle(1, 0.01)
			enemy.navigate_to_target(dt, 1.0, 0.65)  # retreat when too close
		else:
			enemy.decrease_throttle(0, 0.05)
			enemy.navigate_to_target(dt, 0.0, 0.8)  # approach to kite range

	if seen:
		aiming_at_enemy = true
	elif aiming_at_enemy:
		# Just lost sight: half a reaction to re-aim at the last-known spot.
		aiming_at_enemy = false
		reaction_timer = minf(reaction_timer, reaction_speed * 0.5)

	# Only shoot if not overheating and have ammo
	var can_fire = not state.is_hot and not state.no_ammo
	# Low ammo: conserve — only fire at close range, and never blind
	if state.low_ammo and (distance > eff.cqb or not seen):
		can_fire = false

	if can_fire and distance < eff.max_kite:
		if reaction_timer >= reaction_speed:
			_fire(dt, enemy, target, seen, eff, state)
		else:
			reaction_timer += dt
	else:
		enemy.fire.cease()


# Every shot of a fight goes through the fire controller: the guns, the
# skillshots, the lock-on and indirect weapons; a Professional holds fire on
# a poor shot. Out of sight, blind fire at the last-known spot too.
func _fire(dt, enemy, target, seen: bool, eff: Dictionary, state: Dictionary) -> void:
	var disciplined: bool = enemy.personality.type == Personality.Type.PROFESSIONAL
	enemy.fire.engage(dt, target, seen, eff, state, disciplined)
	if not seen:
		enemy.fire.blind_fire(target)


# Losing or regaining sight of the target is an event for the picker.
func _note_sight(enemy, seen: bool) -> void:
	if seen != _was_seen:
		_was_seen = seen
		enemy.positioning.request()


## SQUAD HELPERS ##

# Where the squad's anchor stands, for a flanker: Vector2.INF for anyone
# else, or when the anchor is this NPC or gone. The anchor moving a good way
# since the flanker's last pick is an event for the picker (the flank is
# measured off the anchor), like the foe moving.
func _anchor_position(enemy) -> Vector2:
	var squad = enemy.knowledge.squad
	if squad == null or squad.role_of(enemy) != Squad.ROLE_FLANKER:
		return Vector2.INF
	var anchor = squad.anchor()
	if anchor == null or is_same(anchor, enemy):
		return Vector2.INF
	var at: Vector2 = anchor.global_position
	if _anchor_at_pick == null or at.distance_to(_anchor_at_pick) > Positioning.MOVE_REPICK:
		_anchor_at_pick = at
		enemy.positioning.request()
	return at


# The flanker reaching its angle off the anchor's bearing to the foe, once
# per fight, for the log.
func _note_flank(enemy, foe_pos: Vector2, anchor: Vector2) -> void:
	if _flank_reached or anchor == Vector2.INF:
		return
	if flank_angle(enemy.global_position, foe_pos, anchor) >= Squad.FLANK_ANGLE:
		_flank_reached = true
		AICombatLog.record_squad("flank_reached")


## The angle (rad) between the anchor's bearing to the foe and `from`'s.
static func flank_angle(from: Vector2, foe_pos: Vector2, anchor: Vector2) -> float:
	if from.distance_squared_to(foe_pos) < 1.0 or anchor.distance_squared_to(foe_pos) < 1.0:
		return 0.0
	return absf(foe_pos.direction_to(anchor).angle_to(foe_pos.direction_to(from)))


# Standing still, turning the body toward the cover point (_cover_aim) until
# the launcher's gimbal reaches it: the usual turn (Mecha.apply_rotation_by_
# point, which slows as it closes) but never under COVER_TURN_RATE deg/s, so
# the last degrees don't take seconds.
func _turn_to_cover(dt, enemy) -> void:
	enemy.going_to_position = false
	point_of_interest = false
	if enemy.is_sprinting:
		enemy.stop_sprinting(enemy.get_facing())
	enemy.apply_movement(dt, Vector2.ZERO)
	enemy.apply_rotation_by_point(dt, _cover_aim, true)
	var target_rot: float = rad_to_deg(enemy.global_position.angle_to_point(_cover_aim)) + 90.0
	var diff: float = enemy.get_best_rotation_diff(enemy.rotation_degrees, target_rot)
	var step: float = maxf(absf(diff) * enemy.rotation_acc * dt, minf(absf(diff), COVER_TURN_RATE * dt))
	enemy.rotation_degrees += signf(diff) * step


# The support member screens a squadmate that is breaking off (disengaging,
# fleeing or surrendering) with smoke, at most every SUPPORT_COVER_COOLDOWN.
func _support_cover(enemy) -> void:
	_cover_aim = null
	var squad = enemy.knowledge.squad
	if squad == null or squad.role_of(enemy) != Squad.ROLE_SUPPORT:
		return
	if enemy.knowledge.now() < _cover_ok_at or not enemy.fire.has_role("smoke"):
		return
	for mate in squad.mates_of(enemy):
		if mate.get("logic") == null:
			continue
		var state := str(mate.logic.get_current_state())
		if state != "disengage" and state != "flee" and state != "raise_flag":
			continue
		if enemy.global_position.distance_to(mate.global_position) > SUPPORT_COVER_RANGE:
			continue
		# On the mate, or as far toward it as the launcher reaches.
		var point: Vector2 = enemy.fire.reach_toward(mate.global_position)
		if enemy.fire.screen_at(point):
			_cover_ok_at = enemy.knowledge.now() + SUPPORT_COVER_COOLDOWN
			AICombatLog.record_squad("covered")
			squad.callout(enemy, "covering", mate)
			return
		# The launcher's gimbal can't reach: turn to the mate for a moment
		# (the stance's aim defers to _cover_aim).
		if enemy.fire.cover_blocked_by_facing(point):
			_cover_aim = point
			return
	_cover_aim = null


# A squadmate died (Enemy.on_squadmate_died). A treacherous Rat leaves the
# squad, turning on a mate that is hurt or Flagged on the way out, and cashes
# out. The leader's death is judged by loyalty: low, with little courage, it
# breaks and flees; high, it hunts the killer; between, it fights on.
func on_mate_died(enemy, _member, killer, was_leader: bool) -> void:
	var p: Personality = enemy.personality
	var squad = enemy.knowledge.squad
	if squad == null:
		return
	if p.type == Personality.Type.RAT and p.treachery > BETRAY_TREACHERY:
		var turned := false
		for mate in squad.mates_of(enemy):
			if mate.is_flagged() or _structural_health(mate) <= BETRAY_HEALTH:
				enemy.add_hostility(mate, 1.0)
				turned = true
		squad.remove(enemy)
		AICombatLog.record_squad("betrayed" if turned else "abandoned")
		if not turned:
			_cash_out = true
		return
	if not was_leader:
		return
	if p.loyalty < LOYALTY_FLEE and p.courage < LOYALTY_FLEE_COURAGE:
		AICombatLog.record_squad("broke")
		if not enemy.is_flagged():
			enemy.logic.force_intent(enemy, "flee")
	elif p.loyalty >= LOYALTY_AVENGE and is_instance_valid(killer) and not killer.is_dead \
			and not squad.is_member(killer):
		AICombatLog.record_squad("avenge")
		enemy.add_hostility(killer, 1.0)
		# The dying mate's last call: where its killer was.
		enemy._remember(killer, killer.global_position)
	else:
		AICombatLog.record_squad("held")


# The flight: away from every known threat toward the exit that doesn't take
# it past them, dark, sprinting while its heat allows, shield up when cool,
# with smoke and a decoy if it has them, never stopping to fight. It ends
# when the threats are far and it has been left alone for a while, or when
# the NPC extracts.
func do_flee(dt, enemy):
	if not is_instance_valid(enemy):
		return
	_flee_time += dt
	_flee_exit_timer -= dt
	var threats := _flee_threats(enemy)

	# Left alone: no hit and no threat in sight.
	var threat_seen := false
	for entry in enemy.knowledge.known_mechas():
		if entry.live and _is_threat(enemy, entry.body):
			threat_seen = true
			break
	if enemy.under_fire_timer > 0 or threat_seen:
		_flee_calm = 0.0
	else:
		_flee_calm += dt
	var far := true
	for pos in threats:
		if enemy.global_position.distance_to(pos) < FLEE_SAFE_DISTANCE:
			far = false
			break
	var safe_time := FLEE_SAFE_TIME
	var flagged: bool = enemy.is_exposed or enemy.is_flagged()
	if not flagged:
		safe_time *= lerpf(1.5, 0.5, enemy.personality.courage)
	if far and _flee_calm >= safe_time:
		_flight_over = true
		var exit = _find_nearest_exit(enemy)
		_leave_after_flight = flagged or (exit != null \
				and enemy.global_position.distance_to(exit.global_position) < FLEE_EXTRACT_RANGE)
		return

	# Shield up while fleeing
	if _can_shield(enemy) and enemy.internal_temp < enemy.overheat_temp * general_heat_threshold:
		enemy.shield_up()
	enemy.increase_throttle(1, 0.01)

	# Tools: smoke round itself, a decoy, once each per flight.
	if not _flee_smoke_used and _flee_time > 0.3:
		_flee_smoke_used = true
		enemy.fire.screen_self()
	if not _flee_decoy_used and _flee_time > 0.6:
		_flee_decoy_used = true
		enemy.fire.throw_decoy()

	# Where to: the exit away from the threats, picked again now and then, or
	# a point past them when the map has no exit.
	if _flee_point == null or _flee_exit_timer <= 0.0 \
			or enemy.global_position.distance_to(_flee_point) < POSITIONAL_ACCURACY:
		_flee_exit_timer = FLEE_EXIT_REPICK_TIME
		_flee_point = _flee_destination(enemy, threats)
	point_of_interest = _flee_point
	enemy.going_to_position = true
	enemy.NavAgent.target_position = _flee_point
	var sprint: bool = enemy.heat_ratio() < enemy.SPRINT_HEAT_STOP
	enemy.navigate_to_target(dt, 0.0, 0.3, sprint)

	# Never a fight.
	enemy.valid_target = false
	enemy.current_target = false
	enemy.is_locking = false


# Where the known threats are: every mecha the NPC holds a grudge against or
# was last attacked by, where it believes they are, plus where it took fire
# from lately, plus creatures it knows of.
func _flee_threats(enemy) -> Array[Vector2]:
	var found: Array[Vector2] = []
	for entry in enemy.knowledge.known_mechas():
		if _is_threat(enemy, entry.body):
			found.append(entry.position)
	for contact in enemy.knowledge.contacts.query({"live": true}):
		if contact.kind != "mech" and contact.source == "sight":
			found.append(contact.position)
	for pos in enemy.knowledge.recent_fire_positions():
		found.append(pos)
	return found


func _is_threat(enemy, body) -> bool:
	if is_same(body, enemy.most_recent_attacker):
		return true
	return enemy.get_relationship(body).hostility > 0.0


# The exit whose way lies furthest from the threats' bearings (nearest on a
# tie), or with no exit a point FLEE_RUN_DISTANCE px straight away from them.
func _flee_destination(enemy, threats: Array[Vector2]) -> Vector2:
	var pos: Vector2 = enemy.global_position
	var exits := _find_exits(enemy)
	if not exits.is_empty():
		var best = null
		var best_angle := -1.0
		var best_dist := INF
		for exit in exits:
			var to_exit: Vector2 = exit.global_position - pos
			var angle := PI
			for threat in threats:
				var to_threat := threat - pos
				if to_threat.length_squared() > 1.0 and to_exit.length_squared() > 1.0:
					angle = minf(angle, absf(to_exit.angle_to(to_threat)))
			var dist := to_exit.length()
			if angle > best_angle + 0.01 or (absf(angle - best_angle) <= 0.01 and dist < best_dist):
				best = exit
				best_angle = angle
				best_dist = dist
		if best != null:
			return best.global_position
	var away := Vector2.ZERO
	for threat in threats:
		var from_threat := pos - threat
		var dist := from_threat.length()
		if dist > 1.0:
			away += from_threat / dist / maxf(dist, 1.0)
	if away.length_squared() < 0.000001:
		away = Vector2.from_angle(enemy.global_rotation - PI * 0.5)
		if _flee_point != null:
			away = pos - _flee_point if pos != _flee_point else away
	return pos + away.normalized() * FLEE_RUN_DISTANCE


func do_loot(dt, enemy):
	if is_instance_valid(enemy):
		_check_targets(enemy)
		if not _container_usable(target_container):
			target_container = null
			return

		var dist = enemy.global_position.distance_to(target_container.global_position)

		if dist > POSITIONAL_ACCURACY:
			# Path toward the container
			enemy.going_to_position = true
			enemy.NavAgent.target_position = target_container.global_position
			point_of_interest = target_container.global_position
			if enemy.throttle < 1.0:
				enemy.increase_throttle(false, dt / THROTTLE_CHANGE_TIME)
			enemy.navigate_to_target(dt, 0.0, 0.0, false)
		else:
			# Close enough: a ward to watch its back, then search the crate.
			if not _loot_ward:
				_loot_ward = true
				enemy.fire.place_ward()
			if target_container.has_method("interact"):
				target_container.interact(enemy)
				_read_kill_record(enemy, target_container)
				times_looted += 1
				# Greedy NPCs cash out after a successful loot: greed 0.0
				# never, greed 1.0 always.
				if randf() < enemy.personality.greed:
					_cash_out = true
			target_container = null
			enemy.going_to_position = false
			point_of_interest = false

		if enemy.arrived():
			enemy.going_to_position = false


# A wreck's kill record (Wreck.kill_record), read on opening it: a fallen
# squadmate's names its killer, and the whole squad bears the grudge.
func _read_kill_record(enemy, container) -> void:
	var record = container.get("kill_record")
	if not (record is Dictionary) or record.is_empty():
		return
	var squad = enemy.knowledge.squad
	if squad != null and squad.is_fallen(str(record.get("victim", ""))):
		squad.learn_killer(record)
	else:
		# Anyone's wreck: the name is learnt, no grudge.
		enemy.knowledge.learn_killer(record, false)


# Leaving: path to the nearest exit. Flagged, it goes carefully: no sprint,
# and dark (wants_illuminator). Walking into the exit area is what triggers
# extraction (the host scene's signal handler calls enemy.extracting()).
func do_extract(dt, enemy):
	if not is_instance_valid(enemy):
		return

	# Pick (or re-pick) an exit if needed
	if target_exit == null or not is_instance_valid(target_exit):
		target_exit = _find_nearest_exit(enemy)
		if target_exit == null:
			# No exits available — score_extract drops to 0 next evaluation.
			return

	# Drop combat — we're leaving, not fighting.
	enemy.valid_target = false
	enemy.current_target = false
	enemy.is_locking = false
	aiming_at_enemy = false

	if enemy.throttle < 1.0:
		enemy.increase_throttle(false, dt / THROTTLE_CHANGE_TIME)

	var careful: bool = enemy.is_flagged() or enemy.is_exposed
	var dist = enemy.global_position.distance_to(target_exit.global_position)
	if dist > POSITIONAL_ACCURACY:
		enemy.going_to_position = true
		enemy.NavAgent.target_position = target_exit.global_position
		point_of_interest = target_exit.global_position
		enemy.navigate_to_target(dt, 0.0, 0.2, not careful)
	else:
		enemy.navigate_to_target(dt, 0.0, 0.0, false)

	if enemy.arrived():
		enemy.going_to_position = false


# The ExitPoints on the map (group "exit_point", see ExitPoint.tscn), scanned
# every SCAN_INTERVAL s.
func _find_exits(enemy) -> Array:
	var now: float = enemy.knowledge.now()
	if now - _exit_scan_time < SCAN_INTERVAL:
		return _exits_found
	_exit_scan_time = now
	_exits_found = []
	_exit_nearest = null
	var best_dist := INF
	for exit in enemy.get_tree().get_nodes_in_group("exit_point"):
		if not is_instance_valid(exit):
			continue
		_exits_found.append(exit)
		var d: float = enemy.global_position.distance_to(exit.global_position)
		if d < best_dist:
			best_dist = d
			_exit_nearest = exit
	return _exits_found


# Looks up the closest ExitPoint, or null.
func _find_nearest_exit(enemy):
	_find_exits(enemy)
	return _exit_nearest if is_instance_valid(_exit_nearest) else null


# Lazily initialized timestamp; first call sets it, subsequent calls measure from then.
func _time_alive_seconds() -> float:
	if _start_tick_msec == 0:
		_start_tick_msec = Time.get_ticks_msec()
	return float(Time.get_ticks_msec() - _start_tick_msec) / 1000.0


# Frame-scoped cache: health_diff / heat_diff / _should_flee can ask for the
# NPC's own structural health several times per frame (heat_diff even
# re-enters health_diff).
var _health_cache := -1.0
var _health_cache_frame := -1

func _structural_health(mecha) -> float:
	var frame = Engine.get_physics_frames()
	if _health_cache_frame != frame:
		_health_cache_frame = frame
		_health_cache = NPCKnowledge._structural_health(mecha)
	return _health_cache


# The target's health as this NPC last saw it (NPCKnowledge), against its own.
func health_diff(enemy):
	if is_instance_valid(enemy) and enemy.current_target:
		if is_instance_valid(enemy.current_target):
			var my_health = _structural_health(enemy)
			var their_health: float = enemy.knowledge.health_of(enemy.current_target)
			var diff = my_health - their_health  # positive = I'm healthier
			if their_health <= 0.25:
				return 2  # target is crippled, press the attack
			if diff >= 0.2:
				return 2  # significantly healthier
			elif diff >= 0.0:
				return 1  # slightly healthier
			elif diff >= -0.2:
				return 0  # roughly even
			else:
				return -1  # significantly worse off
		else:
			return 0
	else:
		return 0

func heat_diff(enemy):
	if is_instance_valid(enemy) and enemy.current_target:
		if is_instance_valid(enemy.current_target):
			if enemy.overheat_temp <= 0 or enemy.current_target.overheat_temp <= 0:
				return 0
			var heat_pc = enemy.internal_temp/enemy.overheat_temp
			var heat_target_pc = enemy.current_target.internal_temp/enemy.current_target.overheat_temp
			if heat_pc > weapon_heat_threshold:
				if heat_pc > general_heat_threshold:
					if health_diff(enemy) == 2:
						return 1
					else:
						return -2
				else:
					return -1
			if heat_pc >= heat_target_pc:
				if heat_pc - 0.33 >= heat_target_pc:
					return 1
				else:
					return 0
			else:
				return 0
		else:
			return 0
	else:
		return 0

func status_diff(enemy):
	if is_instance_valid(enemy) and enemy.current_target:
		if is_instance_valid(enemy.current_target):
			if enemy.has_any_status():
				if enemy.current_target.has_any_status():
					return 0
				else:
					return -1
			else:
				if enemy.current_target.has_any_status():
					if heat_diff(enemy) >= 0:
						return 1
					else:
						return 0
				else:
					return 0
		else:
			return 0
	else:
		return 0

# The shield up while under fire and cool enough, down otherwise. The calls
# say what the NPC wants (Mecha.shield_wanted); the toggle lock decides when
# the shield follows, as for the player.
func shield_check(enemy):
	if is_instance_valid(enemy):
		if enemy.under_fire_timer > 0.0:
			if _can_shield(enemy) and enemy.internal_temp < enemy.overheat_temp*general_heat_threshold:
				enemy.shield_up()
		else:
			_drop_shield(enemy)


# Whether it is worth asking for the shield: not already wanted, and it could
# go up (SC left, a projector working, a generator).
func _can_shield(enemy) -> bool:
	return not enemy.shield_wanted and enemy.can_raise_shield()


func _drop_shield(enemy) -> void:
	if enemy.shield_wanted:
		enemy.shield_down()
