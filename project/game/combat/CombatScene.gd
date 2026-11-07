extends Node2D

# CombatScene is the shared base for gameplay scenes where mechas fight:
# Arena (game/arena/Arena.gd) and Expedition (game/expedition/Expedition.gd).
# It holds everything both modes do the same way — projectile/FX spawning with
# budget caps, casings, bodies of the dead, sound propagation, death and game over, pause,
# extraction, map triggers, the intro, FX prewarming and the debug camera /
# navigation overlay — so fixes land in both modes at once.
#
# Subclasses own their _ready (map setup, spawning, missions) and can hook in:
#   _before_mecha_removed(mecha)  called on death before the mecha is removed
#   _leave_body(mecha)            leaves what's left of a dead mecha; by
#                                 default a MechaBody with no loot
#   _before_entity_removed(entity) called when an Entity (creature) dies
#   _plays_ambience()             whether to start ambient BGM after the intro
#   _on_player_lost_health()      override and call super to add reactions
#   _on_player_destroyed()        the player just died; returns extra text for
#                                 the game-over screen (e.g. what was lost)
#
# Required scene children (both Arena.tscn and Expedition.tscn have them):
#   Mechas, Projectiles, Trails, Flashes, Smoke, Explosions, ScrapParts,
#   Casings (CasingsQueue), HeatmapEffects, PlayerHUD, PauseMenu, GameOver,
#   Intro/IntroAnimation, ArenaCamera, DebugNavigation, WindsTimer

const PLAYER = preload("res://game/mecha/player/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")
const PART_DESTRUCTION_EXPLOSION = preload("res://game/weapons/PartDestructionExplosion.tscn")
const NAV_TARGET_SPRITE = preload("res://assets/images/decals/bullet_hole_large.png")

# Impact / explosion scenes whose first render compiles a GPU pipeline
# (~135ms stall, measured via FrameSpikeDetector). Pre-rendered once during
# the intro by _prewarm_fx so the stall never lands mid-combat.
const FX_TO_PREWARM := [
	preload("res://game/weapons/BallisticImpact.tscn"),
	preload("res://game/weapons/BallisticImpactMini.tscn"),
	preload("res://game/weapons/ShapedChargeImpact.tscn"),
	preload("res://game/weapons/OMRivetImpact.tscn"),
	preload("res://game/weapons/MissileDirectedImpact.tscn"),
	preload("res://game/weapons/PartDestructionExplosion.tscn"),
]

# Visual-effect container caps. Once the budget is hit, the OLDEST child is
# queue_freed before the new one is added. Pure graceful degradation —
# gameplay (projectiles) is never capped, only the eye-candy layers.
const MAX_ACTIVE_TRAILS := 40
const MAX_ACTIVE_EXPLOSIONS := 20
const MAX_ACTIVE_FLASHES := 12

# Parts coming off a dead mecha's body (MechaBody.shed), protections against
# cascade overload:
#   1. Kills the player can't see (_player_can_see_point) drop them straight
#      where they land, with no throw and no explosion
#   2. Hard cap on their explosions in ScrapParts: when reached, this death
#      contributes NO new ones (we'd rather lose visual fidelity than tank FPS)
const MAX_ACTIVE_SCRAPS := 16
## How far (px) past the screen's edges a point still counts as on screen
## for _player_can_see_point.
const SEE_POINT_MARGIN := 400.0
const SHED_EXPLOSION_SCALE := 0.6
# Bodies left where no wreck is (_leave_body), oldest removed first.
const MAX_BODIES := 12
const STAGE_SCENE_DIR := "res://game/stage/scenes/"

@onready var Mechas = $Mechas
@onready var Projectiles = $Projectiles
@onready var Trails = $Trails
@onready var Flashes = $Flashes
@onready var Smoke = $Smoke
@onready var Explosions = $Explosions
@onready var ScrapParts = $ScrapParts
@onready var Heatmap = $HeatmapEffects
@onready var PlayerHUD = $PlayerHUD
@onready var PauseMenu = $PauseMenu
@onready var GameOver = $GameOver
@onready var IntroAnimation = $Intro/IntroAnimation
@onready var ArenaCam = $ArenaCamera
@onready var DebugNavigation = $DebugNavigation

var player
var all_mechas: Array = []
# Living Entities (creatures; only Expedition spawns them, via register_entity).
var all_entities: Array = []
# Names of NPCs the player downed (exposed) and killed this match.
var player_downs: Array = []
var player_kills: Array = []
# Local, this match's chat channel (LocalPilots). Subclasses call
# _join_local for each mecha once it is set up.
var local_pilots := LocalPilots.new()
# The NPC squads on the map (Squad), made by Expedition.add_squad; the
# player's companions are the squad the player leads (player_squad).
var squads: Array = []
# A buddy-up offer waiting for the player's answer: {"npc", "until" (match
# time)}, empty for none (offer_buddy, accept_offer, decline_offer).
var pending_offer := {}
## How long (s) an offer waits for an answer. Placeholder.
const OFFER_TIME := 15.0
# Warm marks moving mechas leave (HeatTrails), and blood on the ground
# (BloodStains); made by _setup_heatmap.
var heat_trails: HeatTrails = null
var blood_stains: BloodStains = null
# Dead mechas' bodies outside wrecks (_leave_body); made when first needed.
var Bodies: Node2D = null

var current_stage: StageDirector = null

# Debug free-cam state. Only used when activated via debug_1 input.
var allow_debug_cam: bool = false
var target_arena_zoom: Vector2 = Vector2(0.1, 0.1)


# ---- Hooks for subclasses ----

# Called when any mecha dies, before it's removed from all_mechas.
func _before_mecha_removed(_mecha) -> void:
	pass


# Called when an Entity dies, after it's left all_entities.
func _before_entity_removed(_entity) -> void:
	pass


# Whether ambient BGM starts once the intro ends and mechas unfreeze.
func _plays_ambience() -> bool:
	return true


# Called once when the player dies, before the game-over fade. Whatever it
# returns is shown on the game-over screen; "" keeps the default text only.
func _on_player_destroyed() -> String:
	return ""


# Whether killing pilots changes the player's reputation in this mode.
func _applies_reputation() -> bool:
	return true


# ---- Frame / input ----

func _enter_tree() -> void:
	LocalPilots.current = local_pilots


func _process(dt: float) -> void:
	if player and not PauseMenu.is_paused():
		ShaderEffects.update_shader_effect(player)
	local_pilots.now += dt
	# An offer nobody answered lapses.
	if not pending_offer.is_empty() and local_pilots.now > float(pending_offer.until):
		pending_offer = {}
		AICombatLog.record_squad("offer_lapsed")

	# Debug overlays (cheap when disabled — single Debug.get_setting check)
	if allow_debug_cam and ArenaCam.enabled:
		_update_arena_cam(dt)
	if Debug.get_setting("navigation"):
		_update_enemies_debug_navigation()


func _input(event: InputEvent) -> void:
	# Mouse-wheel zoom for the debug free-cam
	if event is InputEventMouseButton and allow_debug_cam and ArenaCam.enabled:
		var amount := Vector2(.8, .8)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_arena_zoom -= amount
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_arena_zoom += amount

	if event.is_action_pressed("toggle_fullscreen"):
		Global.toggle_fullscreen()
	elif event.is_action_pressed("escape") and player:
		if MechOS.context_menu.is_open():
			MechOS.context_menu.close()
		else:
			MechOS.close_all()
			PauseMenu.toggle_pause()
	elif event.is_action_pressed("debug_1"):
		activate_debug_cam()
	elif event.is_action_pressed("debug_2"):
		# Hit the player for 500 to test the damage/death flow.
		if player:
			player.take_damage(500, 1.0, 1.0, 0, 0, false, false, player)
	elif event.is_action_pressed("debug_4"):
		play_stage(Debug.get_setting("stage_scene"))


# ---- Setup helpers ----

# Connects the signals every mecha (player or NPC) needs. Player-only signals
# (lost_health, mecha_extracted) are connected by the subclass.
func _connect_mecha_signals(mecha) -> void:
	mecha.connect("create_projectile", Callable(self, "_on_mecha_create_projectile"))
	mecha.connect("create_casing", Callable(self, "_on_mecha_create_casing"))
	mecha.connect("died", Callable(self, "_on_mecha_died"))
	mecha.connect("exposed", Callable(self, "_on_mecha_exposed"))
	mecha.connect("made_sound", Callable(self, "_on_mecha_made_sound"))
	mecha.spoke.connect(_on_mecha_spoke)
	# The Flag, for reputation (LocalPilots): who raised it, who lowered it.
	mecha.flag_raised.connect(func(m, voluntary, _pressured_by): local_pilots.note_flag_raised(m, voluntary))
	mecha.flag_lowered.connect(func(m): local_pilots.note_flag_lowered(m))


# Registers a mecha on Local, once its setup has given it its callsign and
# Anonymous flag (named NPCs, the player).
func _join_local(mecha) -> void:
	local_pilots.applies_reputation = _applies_reputation()
	local_pilots.join(mecha)


# Heatmap depends on the player's head part; call after the player spawns.
# Also sets up the rest of the world's information: the heat trails under the
# mechas (HeatTrails, shown in that IR view), the blood under the wrecks
# (BloodStains) and car alarms (VehicleField).
func _setup_heatmap() -> void:
	if player and player.build.head and player.build.head.heatmap:
		Heatmap.change_heatmap(player.build.head.heatmap)
	if heat_trails == null:
		heat_trails = HeatTrails.new()
		heat_trails.name = "HeatTrails"
		add_child(heat_trails)
		move_child(heat_trails, Mechas.get_index())
	if blood_stains == null:
		blood_stains = BloodStains.new()
		blood_stains.name = "BloodStains"
		var under: Node = get_node_or_null("Wrecks")
		add_child(blood_stains)
		move_child(blood_stains, (under if under else Mechas).get_index())
	var vehicles := VehicleField.find(self)
	if vehicles != null and not vehicles.alarm_started.is_connected(_on_car_alarm):
		vehicles.alarm_started.connect(_on_car_alarm)


# Wire every ExitPoint in the tree (group "exit_point") so any mecha entering
# an exit area starts the extract timer, and leaving cancels.
func _setup_exits() -> void:
	for exit in get_tree().get_nodes_in_group("exit_point"):
		_connect_exit(exit)


# Safe to call more than once for the same exit.
func _connect_exit(exit) -> void:
	if not exit.is_connected("mecha_extracting", Callable(self, "_on_exit_mecha_extracting")):
		exit.connect("mecha_extracting", Callable(self, "_on_exit_mecha_extracting"))
	if not exit.is_connected("extracting_cancelled", Callable(self, "_on_exit_extracting_cancelled")):
		exit.connect("extracting_cancelled", Callable(self, "_on_exit_extracting_cancelled"))


# ---- Arena interface (read by Player.gd / Enemy.gd / behaviours) ----

func get_mechas() -> Array:
	return all_mechas


func get_entities() -> Array:
	return all_entities


# Tracks a spawned Entity: deaths, kill credit, sounds, the intro freeze.
func register_entity(entity) -> void:
	all_entities.append(entity)
	entity.died.connect(_on_entity_died)


func get_lock_areas() -> Array:
	var areas := []
	for m in all_mechas:
		if is_instance_valid(m) and m.has_method("get_lock_area"):
			areas.append(m.get_lock_area())
	return areas


# ---- Projectiles and effects ----

func _evict_oldest_if_full(container: Node, limit: int) -> void:
	# queue_free is deferred — the child stays in the tree until end of frame.
	# So a while loop on get_child_count() would spin forever within the
	# same frame, freezing the game. Use remove_child to immediately detach,
	# then queue_free for cleanup, and only evict ONE (cap is enforced per
	# call to this helper, called right before each new effect is added).
	if container.get_child_count() >= limit:
		var oldest = container.get_child(0)
		if is_instance_valid(oldest):
			container.remove_child(oldest)
			oldest.queue_free()


func _on_mecha_create_projectile(mecha, args, weapon) -> void:
	# Handle bullet-spread delay before spawning (some weapons have spread shots)
	if args.bullet_spread_delay > 0:
		var delay = randf_range(0, args.bullet_spread_delay)
		if delay > 0:
			await get_tree().create_timer(delay).timeout
			if not is_instance_valid(self):
				return

	var profile_start := FrameProfiler.start()
	_spawn_projectile(mecha, args, weapon)
	FrameProfiler.add("shots", profile_start)


# A shot's round and its muzzle flash (_on_mecha_create_projectile).
func _spawn_projectile(mecha, args, weapon) -> void:
	var data = ProjectileManager.create(mecha, args, weapon)
	if data and data.create_node:
		Projectiles.add_child(data.node)
		# Wire downstream FX signals so impacts spawn explosions and trails
		if data.node.has_signal("bullet_impact"):
			data.node.connect("bullet_impact", Callable(self, "_on_bullet_impact"))
		if data.node.has_signal("create_trail"):
			data.node.connect("create_trail", Callable(self, "_on_create_trail"))
		if data.node.has_signal("create_projectile"):
			data.node.connect("create_projectile", Callable(self, "_on_mecha_create_projectile"))
		# Muzzle flash at the firing point
		if args.muzzle_flash != null and args.pos_reference != null and is_instance_valid(args.node_reference):
			_evict_oldest_if_full(Flashes, MAX_ACTIVE_FLASHES)
			var flash = ProjectileManager.create_muzzle_flash(args.node_reference, args.muzzle_flash, args.pos_reference, args.dir)
			Flashes.add_child(flash)


func _on_mecha_create_casing(args) -> void:
	# Ejects a spent bullet casing from the CasingsQueue particle pool.
	var next_casing = $Casings.get_next_particle()
	next_casing.global_position = args.casing_ejector_pos
	next_casing.rotation_degrees = args.casing_eject_angle
	$Casings.trigger(args.casing_size)


func _on_bullet_impact(projectile, effect, clear, body) -> void:
	if effect:
		var profile_start := FrameProfiler.start()
		_evict_oldest_if_full(Explosions, MAX_ACTIVE_EXPLOSIONS)
		var impact_effect = ProjectileManager.create_explosion(projectile, effect)
		var mecha_hit = false
		if is_instance_valid(body) and (body.is_in_group("mecha") or body.is_in_group("entity")):
			mecha_hit = true
		impact_effect.setup(projectile.impact_size, projectile.global_rotation, mecha_hit, projectile.shield_hit)
		Explosions.add_child(impact_effect)
		FrameProfiler.add("impacts", profile_start)
	if clear:
		projectile.queue_free()


func _on_create_trail(projectile, trail) -> void:
	if trail:
		var profile_start := FrameProfiler.start()
		_evict_oldest_if_full(Trails, MAX_ACTIVE_TRAILS)
		var created_trail = ProjectileManager.create_trail(projectile, trail)
		Trails.add_child(created_trail)
		FrameProfiler.add("trails", profile_start)


# ---- Damage, downs, deaths ----

func _on_player_lost_health() -> void:
	ShaderEffects.damage_burst_effect()


func _on_mecha_exposed(mecha) -> void:
	# Record NPCs the player downed.
	if _was_hit_by_player(mecha):
		player_downs.append(mecha.mecha_name)


# last_damage_source is a Dictionary {body, name} populated by projectile impacts.
func _was_hit_by_player(mecha) -> bool:
	return mecha.last_damage_source \
			and typeof(mecha.last_damage_source) == TYPE_DICTIONARY \
			and mecha.last_damage_source.get("name") == "Player"


# ---- Companions (Squad, Phase 5) ----

## The squad the player leads, or null; made when `create`.
func player_squad(create := false) -> Squad:
	for squad in squads:
		if squad.is_player_led():
			return squad
	if not create or not is_instance_valid(player):
		return null
	var squad := Squad.new()
	squad.setup("", false)
	squad.leader = player
	squads.append(squad)
	return squad


## `npc` offers to buddy up (Enemy.offer_buddy): the prompt goes up for
## OFFER_TIME s. One offer at a time. Returns whether it was put up.
func offer_buddy(npc) -> bool:
	if not is_instance_valid(player) or player.is_dead or not pending_offer.is_empty() or not is_instance_valid(npc):
		return false
	pending_offer = {"npc": npc, "until": local_pilots.now + OFFER_TIME}
	if is_instance_valid(PlayerHUD):
		PlayerHUD.show_offer(LocalPilots.name_of(npc), OFFER_TIME)
	return true


## The player takes the pending offer (the accept key): the NPC joins the
## player's squad. Returns the new companion, or null.
func accept_offer():
	if pending_offer.is_empty():
		return null
	var npc = pending_offer.npc
	pending_offer = {}
	if not is_instance_valid(npc) or npc.is_dead or not is_instance_valid(player):
		return null
	var squad := player_squad(true)
	squad.add(npc)
	AICombatLog.record_squad("accepted")
	if npc.has_method("on_buddy_accepted"):
		npc.on_buddy_accepted()
	if is_instance_valid(PlayerHUD):
		PlayerHUD.show_squad_notice("%s JOINED YOUR SQUAD" % LocalPilots.name_of(npc).to_upper())
	return npc


## The player declines the pending offer (the decline key).
func decline_offer() -> void:
	if pending_offer.is_empty():
		return
	pending_offer = {}
	AICombatLog.record_squad("declined")
	if is_instance_valid(PlayerHUD):
		PlayerHUD.show_squad_notice("")


## The player's order to its companions (HudSquadOrders): `kind` is one of
## Squad.ORDERS; "hold" is where the player stands, "attack" the target
## under the player's reticle or lock (Player.pointed_target). Returns
## whether anyone was there to take it.
func give_order(kind: String) -> bool:
	var squad := player_squad(false)
	if squad == null or squad.alive_members().is_empty():
		if is_instance_valid(PlayerHUD):
			PlayerHUD.show_squad_notice("NO SQUAD")
		return false
	var target = player.pointed_target() if kind == "attack" and player.has_method("pointed_target") else null
	if kind == "attack" and target == null:
		if is_instance_valid(PlayerHUD):
			PlayerHUD.show_squad_notice("NO TARGET")
		return false
	squad.give_order(kind, player.global_position, target)
	AICombatLog.record_squad("order_" + kind)
	if is_instance_valid(PlayerHUD):
		var label: String = str(Squad.ORDER_LABELS.get(kind, kind.to_upper()))
		if target != null:
			label += " · " + LocalPilots.name_of(target).to_upper()
		PlayerHUD.show_squad_notice("ORDER: " + label)
	return true


## `npc` joins `other`'s squad (made for it if it has none), as a Guardian
## standing with a pilot it saw attacked. Returns whether it joined.
func buddy_up(npc, other) -> bool:
	if not is_instance_valid(npc) or not is_instance_valid(other) or not ("knowledge" in other):
		return false
	if npc.knowledge.squad != null:
		return false
	var squad: Squad = other.knowledge.squad
	if squad == null:
		squad = Squad.new()
		squad.setup("", false)
		squad.add(other)
		squads.append(squad)
	elif squad.members.size() >= 3:
		return false
	squad.add(npc)
	return true


# The body behind a mecha's last damage source (what killed it), or null.
func _killer_of(mecha):
	var source = mecha.get("last_damage_source")
	if typeof(source) == TYPE_DICTIONARY:
		var body = source.get("body")
		return body if is_instance_valid(body) else null
	if source is Node and is_instance_valid(source):
		return source
	return null


func _on_mecha_died(mecha) -> void:
	# An NPC that extracts arrives here too, without having died (die() sets
	# is_dead): it leaves Local the same way, but isn't anyone's kill.
	var was_killed: bool = mecha.is_dead
	mecha.is_dead = true
	local_pilots.leave(mecha)
	# Its squad is told (Squad.on_member_died), with who killed it; the
	# player's companions too, when the player dies.
	for squad in squads:
		if squad.is_in(mecha):
			squad.on_member_died(mecha, _killer_of(mecha) if was_killed else null, was_killed)
			if squad.members.is_empty():
				squads.erase(squad)
			break
	if not pending_offer.is_empty() and (mecha == player or pending_offer.npc == mecha):
		pending_offer = {}
	if was_killed and mecha != player and _was_hit_by_player(mecha):
		local_pilots.score_player_kill(player, mecha)
	_before_mecha_removed(mecha)
	FrameSpikeDetector.mark("died:body")
	# The body is in the tree before the mecha is freed: no frame without it.
	if was_killed:
		_leave_body(mecha)
	var idx = all_mechas.find(mecha)
	if idx != -1:
		all_mechas.remove_at(idx)
	if mecha == player:
		player_died()
	else:
		# Player kills: recorded by name and counted toward mission objectives.
		if _was_hit_by_player(mecha):
			player_kills.append(mecha.mecha_name)
			MissionManager.report_kill()
		FrameSpikeDetector.mark("died:queue_free")
		mecha.queue_free()


# The Entity frees itself after its corpse fades (Entity.die).
func _on_entity_died(entity) -> void:
	all_entities.erase(entity)
	_before_entity_removed(entity)
	if _was_hit_by_player(entity):
		player_kills.append(entity.mecha_name)
		MissionManager.report_kill()


# Match-end on player death: hold the view on the arena camera, tear down
# HUD/pause, fade out, show GameOver.
func player_died() -> void:
	if not is_instance_valid(player):
		return
	FrameSpikeDetector.mark("player_died:teardown")
	if is_instance_valid(current_stage):
		current_stage.abort()
	var game_over_text := _on_player_destroyed()
	MechOS.close_all()  # cargo/container windows belong to the dead player
	activate_arena_cam()
	player.queue_free()
	player = null
	PlayerHUD.player_died()
	if PauseMenu.is_paused():
		PauseMenu.toggle_pause()
	var dur := 4.0
	ShaderEffects.play_transition(5000.0, 0.0, dur)
	await get_tree().create_timer(dur).timeout
	if not is_instance_valid(self):
		return
	PlayerHUD.queue_free()
	PauseMenu.queue_free()
	_show_death_screen(game_over_text)


func _show_death_screen(game_over_text: String) -> void:
	GameOver.killed(game_over_text)


# Leaves the dead mecha's body (MechaBody) where it died, with no loot, and
# sheds its parts. Expedition overrides this to leave a Wreck for NPCs.
func _leave_body(mecha) -> void:
	if Bodies == null:
		Bodies = Node2D.new()
		Bodies.name = "Bodies"
		add_child(Bodies)
		move_child(Bodies, Mechas.get_index())
	var body := MechaBody.new()
	body.position = mecha.global_position
	body.copy_from(mecha)
	Bodies.add_child(body)
	_shed_parts(body, mecha, [])
	while Bodies.get_child_count() > MAX_BODIES:
		var oldest := Bodies.get_child(0)
		Bodies.remove_child(oldest)
		oldest.queue_free()


# The one or two parts that come off a body (MechaBody.choose_shed), each with
# a small explosion. `loot` is the wreck's, so its weapons stay on the body.
func _shed_parts(body: MechaBody, mecha, loot: Array) -> void:
	_shed(body, MechaBody.choose_shed(mecha, loot), mecha == player or _player_can_see_point(mecha.global_position))


# Whether the player can see `point`: on screen (MapSenses.screen_rect, which
# follows the camera's pan, grown by SEE_POINT_MARGIN) and inside its sight
# circle. With no player (the observer arena), always.
func _player_can_see_point(point: Vector2) -> bool:
	if not is_instance_valid(player):
		return true
	return MapSenses.screen_rect(player, SEE_POINT_MARGIN).has_point(point) \
			and player.global_position.distance_to(point) <= player.sight_radius()


# Sheds `slots` off a body in the tree: thrown, with an explosion each, when
# on_screen; otherwise straight to where they land.
func _shed(body: MechaBody, slots: Array, on_screen: bool) -> void:
	for slot in slots:
		var at := body.shed(slot, on_screen)
		if on_screen and ScrapParts.get_child_count() < MAX_ACTIVE_SCRAPS:
			var explosion = PART_DESTRUCTION_EXPLOSION.instantiate()
			explosion.scale = Vector2(SHED_EXPLOSION_SCALE, SHED_EXPLOSION_SCALE)
			ScrapParts.add_child(explosion)
			explosion.global_position = at


# ---- Sound ----

func _on_mecha_made_sound(sound_data) -> void:
	# A sweep (Mecha.sweep) is a sound only creatures hear.
	if sound_data.get("entities_only", false):
		_tell_entities(sound_data)
		return
	for m in all_mechas:
		if m == sound_data.source or not is_instance_valid(m):
			continue
		# NPCs act on sounds (Enemy.heard_sound); the player gets a sound
		# wedge for its radar (Player.heard_sound).
		if not m.has_method("heard_sound"):
			continue
		if m.global_position.distance_to(sound_data.position) <= sound_data.max_distance:
			m.heard_sound(sound_data)
	_tell_entities(sound_data)


# A car alarm (VehicleField.start_alarm): a loud sound at the car that NPCs
# and creatures hear, and a ping contact (kind and source "alarm", no body)
# at the car for every mecha within earshot, live while it sounds.
func _on_car_alarm(_index: int, at: Vector2) -> void:
	_on_mecha_made_sound({
		"volume_type": "loud",
		"type": "car_alarm",
		"position": at,
		"max_distance": VehicleField.ALARM_SOUND_RANGE,
		"source": null,
		"entities_only": false,
	})
	for mecha in all_mechas:
		if is_instance_valid(mecha) and not mecha.is_dead \
				and mecha.global_position.distance_to(at) <= VehicleField.ALARM_SOUND_RANGE:
			mecha.contacts.report(null, "alarm", at, "alarm", VehicleField.ALARM_TIME)
	if is_instance_valid(player) and player.global_position.distance_to(at) <= VehicleField.ALARM_SOUND_RANGE:
		MechLog.write("SNS", "Car alarm", MechLog.Kind.COMBAT)


func _tell_entities(sound_data) -> void:
	for entity in all_entities:
		if entity == sound_data.source or not is_instance_valid(entity):
			continue
		if entity.global_position.distance_to(sound_data.position) <= sound_data.max_distance:
			entity.heard_sound(sound_data)


# ---- Speech ----

# Mecha.say: the player hears a speaker within Barks.EARSHOT (walls don't
# stop it), always hears itself, and always hears always_heard speech. Heard
# speech shows a box over the speaker and goes to Local as a bark line.
func _on_mecha_spoke(mecha, text: String, seconds: float, always_heard: bool) -> void:
	if not is_instance_valid(mecha) or not is_instance_valid(player):
		return
	var heard: bool = always_heard or mecha == player \
			or mecha.global_position.distance_to(player.global_position) <= Barks.EARSHOT
	if not heard:
		return
	if is_instance_valid(PlayerHUD):
		PlayerHUD.show_speech(mecha, text, seconds)
	local_pilots.post_bark(mecha, text)


# ---- Extraction ----

func _on_exit_mecha_extracting(extracting_mech) -> void:
	if not is_instance_valid(extracting_mech):
		return
	if extracting_mech.has_method("extracting"):
		extracting_mech.extracting()
	if extracting_mech == player:
		if Debug.get_setting("verbose_logging"):
			print("[", name, "] Player is extracting")
		_set_hud_extracting(true)


func _on_exit_extracting_cancelled(extracting_mech) -> void:
	if not is_instance_valid(extracting_mech):
		return
	if extracting_mech.has_method("cancel_extract"):
		extracting_mech.cancel_extract()
	if extracting_mech == player:
		_set_hud_extracting(false)


# The HUD is freed after the player dies, so guard every access.
func _set_hud_extracting(value: bool) -> void:
	if is_instance_valid(PlayerHUD):
		PlayerHUD.set_extracting(value)


# ---- Map triggers ----

# "story:<command>" goes to StoryDirector; "stage:<name>" plays a scripted
# scene from game/stage/scenes; any other name calls the matching method on the
# scene if one exists (e.g. Arena's tutorial1).
func _on_player_trigger_entered(trigger: String) -> void:
	if trigger.begins_with("story:"):
		StoryDirector.handle_trigger(trigger.trim_prefix("story:"))
	elif trigger.begins_with("stage:"):
		play_stage(trigger.trim_prefix("stage:"))
	elif has_method(trigger):
		call(trigger)
	else:
		push_warning(str(name) + ": no handler for map trigger '" + trigger + "'")


func play_stage(stage_name) -> StageDirector:
	if not stage_name is String or stage_name == "":
		return null
	if is_instance_valid(current_stage) and current_stage.is_playing:
		return null
	var path: String = STAGE_SCENE_DIR + stage_name + ".tscn"
	if not ResourceLoader.exists(path):
		push_warning(str(name) + ": no stage scene at '" + path + "'")
		return null
	var director = load(path).instantiate()
	add_child(director)
	current_stage = director
	director.finished.connect(_drop_stage.bind(director), CONNECT_ONE_SHOT)
	if director.has_method("start"):
		director.start()
	else:
		director.play()
	return director


func _drop_stage(director) -> void:
	if current_stage == director:
		current_stage = null
	if is_instance_valid(director):
		director.queue_free()


# ---- Game flow ----

# Pauses or unpauses all mechas (and Entities) in the scene. Used during the
# intro animation and could be reused for cutscenes. When unblocking AFTER the
# intro, kick off ambient BGM unless the mode opts out.
func set_mechas_block_status(status: bool) -> void:
	for mecha in Mechas.get_children():
		if mecha.has_method("set_pause"):
			mecha.set_pause(status)
	for entity in all_entities:
		if is_instance_valid(entity):
			entity.set_pause(status)
	if not status and _plays_ambience():
		AudioManager.play_bgm("ambience", true, 40)


func _on_PauseMenu_pause_toggle(paused: bool) -> void:
	# Coming out of pause: re-fade the world in.
	if not paused:
		ShaderEffects.play_transition(0.0, 5000.0, 2.0)
	if is_instance_valid(current_stage):
		current_stage.set_paused(paused)
	if player:
		player.set_pause(paused)
		PlayerHUD.set_pause(paused)


func _on_IntroAnimation_animation_ending() -> void:
	# Intro finished — unblock AI and start ambient BGM. Pilots who join Local
	# from now on are announced.
	set_mechas_block_status(false)
	local_pilots.go_live()
	# Tear down the Intro entirely. Two reasons:
	#   1. VCREffect / VCREffect2 are full-screen canvas-item shaders
	#      (noise + scanlines, noiseQuality up to 5000) that keep rendering
	#      every frame as long as they're in the tree.
	#   2. Even hidden, the AnimationPlayer keeps ticking track
	#      interpolations and pushing shader-uniform values.
	# Stop the player explicitly, hide for the rest of this frame's tweens,
	# then queue_free a beat later so any in-flight fade tweens can finish.
	if has_node("Intro"):
		if has_node("Intro/IntroAnimation/AnimationPlayer"):
			$Intro/IntroAnimation/AnimationPlayer.stop()
		$Intro.visible = false
		await get_tree().create_timer(1.5).timeout
		if is_instance_valid(self) and has_node("Intro"):
			$Intro.queue_free()


func _on_WindsTimer_timeout() -> void:
	# Stub — kept for a future ambient wind layer.
	pass


# ---- FX prewarm ----

# Pre-compile combat-FX shader pipelines by rendering one instance of every
# scene the first fight can spawn: the static impact/explosion list plus
# database-derived muzzle flashes, projectiles, and each projectile's
# trail / impact effect. Each distinct ParticleProcessMaterial generates its
# own shader, so ALL of these compile on first render (~135ms stall each,
# measured) — warming only the impact scenes still left first-shot spikes.
# Rendered in-frustum (off-screen sprites get culled and never compile),
# hidden by near-zero alpha and the intro transition, silenced by emptying
# per-instance SFX pools (AudioManager players outlive any mute window).
# Call it after the intro cover is up and while mechas are frozen.
func _prewarm_fx() -> void:
	var holder := Node2D.new()
	holder.position = player.global_position if player else Vector2.ZERO
	holder.modulate = Color(1, 1, 1, 0.01)
	holder.z_index = -4096  # behind everything already on screen
	add_child(holder)

	# Collect unique scenes: statics + every weapon's muzzle flash and
	# projectile from the parts database (covers player and all NPCs).
	var seen := {}
	var scenes: Array = []
	for scene in FX_TO_PREWARM:
		if not seen.has(scene):
			seen[scene] = true
			scenes.append(scene)
	for weapons in [PartManager.ARM_WEAPONS, PartManager.SHOULDER_WEAPONS]:
		for key in weapons:
			var w = weapons[key]
			for prop in ["muzzle_flash", "projectile"]:
				var s = w.get(prop)
				if s is PackedScene and not seen.has(s):
					seen[s] = true
					scenes.append(s)

	# Instantiate one of each. Projectile instances expose their own trail /
	# impact_effect scenes — collect those for a second pass.
	var nested: Array = []
	for scene in scenes:
		var inst = _spawn_prewarm_instance(scene, holder)
		for prop in ["trail", "impact_effect"]:
			var s = inst.get(prop)
			if s is PackedScene and not seen.has(s):
				seen[s] = true
				nested.append(s)
	for scene in nested:
		_spawn_prewarm_instance(scene, holder)

	# Mecha hit-reaction particles (blood, shield ring, fire/status effects)
	# live inside every mecha and first emit on first DAMAGE — movement
	# particles warm naturally as NPCs walk, but these compile right when
	# the first brawl starts. Force-emit the player's set for the same
	# window (the intro transition hides it), then restore each one to what
	# it was doing before (some, like the dash-cooldown sparks, start on).
	# The pooled casing emitter ($Casings) has the same first-use profile.
	var warmed_particles: Array = []
	if player:
		_collect_particles(player, warmed_particles)
	_collect_particles($Casings, warmed_particles)
	var was_emitting := {}
	for p in warmed_particles:
		was_emitting[p] = p.emitting
		p.emitting = true

	# A few frames so the render thread finishes the pipeline compiles.
	for _i in 4:
		await get_tree().process_frame

	for p in warmed_particles:
		if is_instance_valid(p):
			p.emitting = was_emitting[p]
	holder.queue_free()


# Instantiate a scene for prewarm: inert, silent, but rendering. Returns the
# instance (already added to the holder).
func _spawn_prewarm_instance(scene: PackedScene, holder: Node2D) -> Node:
	var inst = scene.instantiate()
	# Projectiles (all four variants) early-return _physics_process on
	# `dying` — without setup() their `dir` is null and movement would crash.
	if "dying" in inst:
		inst.set("dying", true)
	# Trails follow home_projectile; give them the holder so they neither
	# crash on null nor stop themselves (SmokeTrail kills emission when its
	# projectile is gone).
	if "home_projectile" in inst:
		inst.set("home_projectile", holder)
	# Silence: FX _ready() pick_randoms from these pools via the global
	# AudioManager. Exported arrays are per-instance copies — clear in place.
	for pool in ["on_hit_sfxs", "on_shield_sfxs", "on_miss_sfxs"]:
		if pool in inst:
			inst.get(pool).clear()
	holder.add_child(inst)
	# Force every particle system to emit so its shader/pipeline compiles.
	# Also keeps scenes alive that self-free when nothing emits (MuzzleFlash
	# queue_frees unless its Linger child is emitting).
	var particles: Array = []
	_collect_particles(inst, particles)
	for p in particles:
		p.emitting = true
	return inst


# Collect every particle system in a subtree (prewarm: force-emit for
# pipeline compiles, and restore the player's set afterward).
func _collect_particles(node: Node, out: Array) -> void:
	if node is GPUParticles2D or node is CPUParticles2D:
		out.append(node)
	for child in node.get_children():
		_collect_particles(child, out)


# ---- Cameras and debug tools ----

# Freeze the view where the player's camera was (used when the player dies,
# since their Camera2D is freed with them).
func activate_arena_cam() -> void:
	ArenaCam.enabled = true
	if player:
		var player_cam = player.get_camera_3d()
		ArenaCam.zoom = player_cam.zoom
		ArenaCam.position = player_cam.get_screen_center_position()
		ArenaCam.reset_smoothing()


# Switch to the spectator free-cam. Triggered by debug_1 input.
# After activation: wheel zooms, mouse near a screen edge pans.
func activate_debug_cam() -> void:
	ArenaCam.enabled = true
	allow_debug_cam = true
	# Seed the target zoom from the cam's current value so the first wheel
	# tick doesn't snap dramatically.
	target_arena_zoom = ArenaCam.zoom


# Mouse-edge panning + smooth zoom interp. Called from _process each frame
# while the free-cam is active.
func _update_arena_cam(dt: float) -> void:
	var speed: float = 4600 * (ArenaCam.zoom.x / 10.0)
	var margin: int = 55
	var mpos: Vector2 = get_viewport().get_mouse_position()
	var move_vec := Vector2()
	if mpos.x <= margin:
		move_vec.x -= 1
	elif mpos.x >= get_viewport_rect().size.x - margin:
		move_vec.x += 1
	if mpos.y <= margin:
		move_vec.y -= 1
	elif mpos.y >= get_viewport_rect().size.y - margin:
		move_vec.y += 1

	ArenaCam.position += speed * dt * move_vec.normalized()
	ArenaCam.zoom = lerp(ArenaCam.zoom, target_arena_zoom, 10 * dt)


# Draws each NPC's NavAgent path as a magenta Line2D plus a target sprite
# at the destination. Only runs when Debug.navigation = true. Children are
# freed and rebuilt each frame.
func _update_enemies_debug_navigation() -> void:
	for path in DebugNavigation.get_children():
		path.queue_free()
	for mecha in Mechas.get_children():
		if not mecha.has_method("is_player") or mecha.is_player():
			continue
		# Path line
		if mecha.has_method("get_navigation_path"):
			var path_points = mecha.get_navigation_path()
			if path_points:
				var line = Line2D.new()
				line.width = 20
				line.default_color = Color(0.89, 0, 1.0, 1.0)
				var pts = []
				for point in path_points:
					pts.append(point)
				line.points = pts
				DebugNavigation.add_child(line)
		# Target marker
		if mecha.has_method("get_target_navigation_pos"):
			var target_pos = mecha.get_target_navigation_pos()
			if target_pos:
				var target = Sprite2D.new()
				target.texture = NAV_TARGET_SPRITE
				target.global_position = target_pos
				DebugNavigation.add_child(target)

# Run HUD and OS setups
func _register_player() -> void:
	PlayerHUD.setup(player, all_mechas)
	PlayerHUD.setup_local(local_pilots)
	if Heatmap.has_method("set_player"):
		Heatmap.set_player(player)
	MechOS.set_player(player)
	MouseManager.set_aim_available(true)


func _exit_tree() -> void:
	local_pilots.close()
	MechOS.close_all()
	MouseManager.reset()
