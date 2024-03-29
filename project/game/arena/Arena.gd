extends Node2D

const PLAYER = preload("res://game/mecha/player/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")
const SCRAP_PART = preload("res://game/arena/ScrapPart.tscn")
const TARGET_SPRITE = preload("res://assets/images/decals/bullet_hole_large.png")


@onready var Mechas = $Mechas 
@onready var Projectiles = $Projectiles
@onready var Trails = $Trails
@onready var Smoke = $Smoke
@onready var Flashes = $Flashes
@onready var Explosions = $Trails
@onready var ScrapParts = $ScrapParts
@onready var PlayerHUD = $PlayerHUD
@onready var GameOver = $GameOver
@onready var ArenaCam = $ArenaCamera
@onready var PauseMenu = $PauseMenu
@onready var DebugNavigation = $DebugNavigation
@onready var IntroAnimation = $Intro/IntroAnimation
@onready var Heatmap = $HeatmapEffects

var player
var all_mechas = []
var player_downs = []
var player_kills = []
var is_tutorial := false
var trigger_data

# Debug vars
var allow_debug_cam = false
var target_arena_zoom


func _ready():
	randomize()
	
	setup_arena()
	
	player_downs = []
	player_kills = []
	target_arena_zoom = ArenaCam.zoom
	
	add_player()
	if ArenaManager.mode == "Challenge":
		for enemy in ArenaManager.current_challengers:
			var enemy_design = NPCManager.get_design_data(NPCManager.get_special_npc(enemy))
			add_enemy(enemy_design, enemy)
	elif ArenaManager.mode == "Exhibition":
		for enemy in ArenaManager.exhibitioner_count:
			var enemy_design = NPCManager.get_design_data(NPCManager.get_random_npc())
			add_enemy(enemy_design, enemy)
	elif ArenaManager.mode == "Tutorial":
		var enemy_design = NPCManager.get_design_data(NPCManager.get_random_npc())
		add_enemy(enemy_design, 1)
	
	for exitposition in $Exits.get_children():
		exitposition.connect("mecha_extracting",Callable(self,"_on_ExitPos_mecha_extracting"))
		exitposition.connect("extracting_cancelled",Callable(self,"_on_ExitPos_extracting_cancelled"))
	
	ShaderEffects.reset_shader_effect("arena")
	ShaderEffects.play_transition(0.0, 5000.0, 5.0)
	
	
	set_mechas_block_status(true)
	
	if player and player.build.head and player.build.head.heatmap:
		Heatmap.change_heatmap(player.build.head.heatmap)
	
	if is_tutorial:
		IntroAnimation.play("simEntrance")
	else:
		IntroAnimation.play("Entrance")
	
	if Debug.get_setting("skip_intro"):
		await get_tree().create_timer(.01).timeout
		IntroAnimation.stop_animation()
	if Debug.get_setting("use_debug_cam"):
		activate_debug_cam()


func _input(event):
	if event is InputEventMouseButton:
		if allow_debug_cam and ArenaCam.enabled:
			var amount = Vector2(.8, .8)
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_arena_zoom -= amount
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_arena_zoom += amount
	
	if event.is_action_pressed("toggle_fullscreen"):
		Global.toggle_fullscreen()
	elif event.is_action_pressed("escape") and player:
		PauseMenu.toggle_pause()
	elif event.is_action_pressed("debug_1"):
		activate_debug_cam()
	elif event.is_action_pressed("debug_2"):
		if player:
			player.take_damage(500, 1.0, 1.0, 0, 0, false, false, player)


func _process(dt):
	if player and not PauseMenu.is_paused():
		ShaderEffects.update_shader_effect(player)
	
	#Debug
	if allow_debug_cam and ArenaCam.enabled:
		update_arena_cam(dt)
	if Debug.get_setting("navigation"):
		update_enemies_debug_navigation()


func setup_arena():
	var arena_data = ArenaManager.get_current_map()
	
	is_tutorial = arena_data.is_tutorial
	
	var data_bg = arena_data.get_bg()
	$BG.texture = data_bg.texture
	$BG.position = data_bg.position
	$BG.scale = data_bg.scale
	
	for child in arena_data.get_bushes():
		$Bushes.add_child(child.duplicate(7))
	for child in arena_data.get_props():
		$Props.add_child(child.duplicate(7))
	for child in arena_data.get_walls():
		$Walls.add_child(child.duplicate(7))
	for child in arena_data.get_start_positions():
		$StartPositions.add_child(child.duplicate(7))
	for child in arena_data.get_exits():
		$Exits.add_child(child.duplicate(7))
	for child in arena_data.get_trees():
		$Trees.add_child(child.duplicate(7))
	for child in arena_data.get_buildings():
		$Buildings.add_child(child.duplicate(7))
	for child in arena_data.get_texts():
		$Texts.add_child(child.duplicate(7))
	for child in arena_data.get_triggers():
		var obj = child.duplicate(7)
		$Triggers.add_child(obj)
		obj.connect("trigger_entered",Callable(self,"_on_player_trigger_entered"))
	
	$NavigationPolygon.navpoly = arena_data.get_navigation_polygon()


func update_arena_cam(dt):
	var speed = 4600*(ArenaCam.zoom.x/10.0)
	var margin = 55
	var mpos = get_viewport().get_mouse_position()
	var move_vec = Vector2()
	if mpos.x <= margin:
		move_vec.x -= 1
	elif mpos.x >= get_viewport_rect().size.x - margin:
		move_vec.x += 1
	if mpos.y <= margin:
		move_vec.y -= 1
	elif mpos.y >= get_viewport_rect().size.y - margin:
		move_vec.y += 1
	
	ArenaCam.position += speed*dt*move_vec.normalized()
	
	ArenaCam.zoom = lerp(ArenaCam.zoom, target_arena_zoom, 10*dt)


func update_enemies_debug_navigation():
	for path in DebugNavigation.get_children():
		path.queue_free()
	for mecha in Mechas.get_children():
		if not mecha.is_player():
			#Create pathings
			var path = mecha.get_navigation_path()
			if path:
				var line = Line2D.new()
				line.width = 20
				line.default_color = Color(0.89, 0, 1.0, 1.0)
				var points = []
				for point in path:
					points.append(point)
				line.points = points
				DebugNavigation.add_child(line)
			#Create endings
			var target_pos = mecha.get_target_navigation_pos()
			if target_pos:
				var target = Sprite2D.new()
				target.texture = TARGET_SPRITE
				target.global_position = target_pos
				DebugNavigation.add_child(target)



func add_player():
	player = PLAYER.instantiate()
	Mechas.add_child(player)
	player.setup(self)
	player.position = get_start_position(0)
	player.connect("create_projectile", Callable(self,"_on_mecha_create_projectile"))
	player.connect("create_casing", Callable(self,"_on_mecha_create_casing"))
	player.connect("died", Callable(self,"_on_mecha_died"))
	player.connect("exposed", Callable(self,"_on_mecha_exposed"))
	player.connect("lost_health", Callable(self,"_on_player_lost_health"))
	player.connect("mecha_extracted", Callable(self,"_on_player_mech_extracted"))
	player.connect("made_sound", Callable(self,"_on_mecha_made_sound"))
	all_mechas.push_back(player)
	PlayerHUD.setup(player, all_mechas)
	player_ammo_set()


func add_enemy(design_data, enemy_name):
	var enemy = ENEMY.instantiate()
	Mechas.add_child(enemy)
	enemy.position = get_random_start_position([0])
	enemy.connect("create_projectile",Callable(self,"_on_mecha_create_projectile"))
	enemy.connect("create_casing",Callable(self,"_on_mecha_create_casing"))
	enemy.connect("died",Callable(self,"_on_mecha_died"))
	enemy.connect("exposed",Callable(self,"_on_mecha_exposed"))
	enemy.connect("made_sound", Callable(self,"_on_mecha_made_sound"))
	all_mechas.push_back(enemy)
	enemy.setup(self, design_data, enemy_name)


func get_mechas():
	return all_mechas


func player_died():
	activate_arena_cam()
	player.queue_free()
	player = null
	PlayerHUD.player_died()
	if PauseMenu.is_paused():
		PauseMenu.toggle_pause()
	var dur = 4.0
	ShaderEffects.play_transition(5000.0, 0.0, dur)
	
	await get_tree().create_timer(dur).timeout

	PlayerHUD.queue_free()
	PauseMenu.queue_free()
	$GameOver.killed()


func get_random_start_position(exclude_idx := []):
	var offset = 500
	var rand_offset = Vector2(randf_range(-offset, offset), randf_range(-offset, offset))
	var n_pos = $StartPositions.get_child_count()
	var idx = randi()%n_pos
	while exclude_idx.has(idx):
		idx = randi()%n_pos
	return get_start_position(idx) + rand_offset


func get_start_position(idx):
	return $StartPositions.get_child(idx).position


func get_random_position():
	var w = $BG.texture.get_width()*$BG.scale.x
	var h = $BG.texture.get_height()*$BG.scale.y
	var point = Vector2(randf_range(-w/2, w/2),\
						randf_range(-h/2, h/2)) - $BG.position
	var poly = $NavigationPolygon.navpoly.get_outline(0)
	while not Geometry2D.is_point_in_polygon(point, poly):
		point = Vector2(randf_range(-w/2, w/2),\
							randf_range(-h/2, h/2)) - $BG.position
	return point


func player_ammo_set():
	if PlayerStatManager.NumberofExtracts > 0:
		player.hp = PlayerStatManager.PlayerHP
		player.set_ammo("arm_weapon_right", PlayerStatManager.RArmAmmo)
		player.set_ammo("arm_weapon_left", PlayerStatManager.LArmAmmo)
		player.set_ammo("shoulder_weapon_right", PlayerStatManager.RShoulderAmmo)
		player.set_ammo("shoulder_weapon_left", PlayerStatManager.LShoulderAmmo)
		$PlayerHUD.update_cursor()
		$PlayerHUD.update_arsenal()


func random_wind_sound():
	pass
#	var x = randf_range(-10000.00,10000.00)
#	var y = randf_range(-10000.00,10000.00)
#	var sound_pos = Vector2(x,y)
	#var rand_wind = "small_shield_impact" + str((randi()%3) + 1)
	#AudioManager.play_sfx(rand_wind, sound_pos, null, null, 2.5, 3000)


func set_mechas_block_status(status):
	for mecha in Mechas.get_children():
		mecha.set_pause(status)
	if not status and not is_tutorial:
		AudioManager.play_bgm("ambience", true, 40)


func create_mecha_scraps(mecha):
	for part in mecha.get_scrapable_parts():
		var scrap = SCRAP_PART.instantiate()
		scrap.setup(part.texture)
		scrap.position = mecha.position
		scrap.update_scale(mecha.scale)
		var mat = part.material
		scrap.set_heat_parameters(mat.get_shader_parameter("heat"), mat.get_shader_parameter("min_darkness"))

		var impulse_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var impulse_force = randf_range(400,700)
		var impulse_torque = randf_range(10, 20)
		if randf() > .5:
			impulse_torque = -impulse_torque
		scrap.apply_impulse(impulse_dir*impulse_force, Vector2())
		scrap.apply_torque_impulse(impulse_torque)
		ScrapParts.call_deferred("add_child", scrap)


func activate_arena_cam():
	ArenaCam.enabled = true
	if player:
		var player_cam = player.get_camera_3d()
		ArenaCam.zoom = player_cam.zoom
		ArenaCam.position = player_cam.get_screen_center_position()
		ArenaCam.reset_smoothing()


func get_lock_areas():
	var areas = []
	for mecha in all_mechas:
		areas.append(mecha.get_lock_area())
	return areas


func activate_debug_cam():
	ArenaCam.enabled = true
	allow_debug_cam = true


func _on_PauseMenu_pause_toggle(paused):
	if not paused:
		ShaderEffects.play_transition(0.0, 5000.0, 2.0)
	if player:
		player.set_pause(paused)
		PlayerHUD.set_pause(paused)


func _on_player_lost_health():
	ShaderEffects.damage_burst_effect()


func _on_mecha_create_projectile(mecha, args, weapon):
	if args.bullet_spread_delay > 0:
		var delay = randf_range(0, args.bullet_spread_delay)
		if delay > 0:
			await get_tree().create_timer(delay).timeout
		
	var data = ProjectileManager.create(mecha, args, weapon)
	if data and data.create_node:
		Projectiles.add_child(data.node)
		if data.node.has_signal("bullet_impact"):
			data.node.connect("bullet_impact",Callable(self,"_on_bullet_impact"))
		if data.node.has_signal("create_trail"):
			data.node.connect("create_trail",Callable(self,"_on_create_trail"))
		if data.node.has_signal("create_projectile"):
			data.node.connect("create_projectile",Callable(self,"_on_mecha_create_projectile"))
		if args.muzzle_flash != null and args.pos_reference != null and is_instance_valid(args.node_reference):
			var flash = ProjectileManager.create_muzzle_flash(args.node_reference, args.muzzle_flash, args.pos_reference, args.dir)
			Flashes.add_child(flash)

func _on_mecha_create_casing(args):
	var next_casing = $Casings.get_next_particle()
	next_casing.global_position = args.casing_ejector_pos
	next_casing.rotation_degrees = args.casing_eject_angle
	$Casings.trigger(args.casing_size)

func _on_bullet_impact(projectile, effect, clear, body):
	if effect:
		var impact_effect = ProjectileManager.create_explosion(projectile, effect)
		var mecha_hit
		if body and body.is_in_group("mecha"):
			mecha_hit = true
		impact_effect.setup(projectile.impact_size, projectile.global_rotation, mecha_hit, projectile.shield_hit)
		Explosions.add_child(impact_effect)
	if clear:
		projectile.queue_free()

func _on_create_trail(projectile, trail):
	if trail:
		var created_trail = ProjectileManager.create_trail(projectile, trail)
		Trails.add_child(created_trail)

func _on_mecha_exposed(mecha):
	if mecha.last_damage_source.name == "Player":
		player_downs.append(mecha.mecha_name)
		print(player_downs)

func _on_mecha_died(mecha):
	mecha.is_dead = true
	
	var idx = all_mechas.find(mecha)
	if idx != -1:
		all_mechas.remove_at(idx)
	
	create_mecha_scraps(mecha)
	if mecha == player:
		player_died()
	else:
		if mecha.last_damage_source.name == "Player":
			player_kills.append(mecha.mecha_name)
			print(player_kills)
		mecha.queue_free()


func _on_mecha_made_sound(sound_data):
	for mecha in all_mechas:
		if not mecha.is_player() and sound_data.source != mecha and\
		   mecha.global_position.distance_to(sound_data.position) <= sound_data.max_distance:
			mecha.heard_sound(sound_data)


func _on_ExitPos_mecha_extracting(extractingMech):
	print(str(extractingMech.name) + str(" is extracting"))
	extractingMech.extracting()
	if extractingMech.name == "Player":
		$PlayerHUD/SubViewportContainer/SubViewport/ExtractingLabel.visible = true


func _on_ExitPos_extracting_cancelled(extractingMech):
	if extractingMech == null:
		pass
	else:
		extractingMech.cancel_extract()
	if extractingMech.name == "Player":
		$PlayerHUD/SubViewportContainer/SubViewport/ExtractingLabel.visible = false

func _on_player_trigger_entered(trigger):
	if has_method(trigger):
		call(trigger)

func _on_player_mech_extracted(playerMech):
	if is_tutorial:
		TransitionManager.transition_to("res://game/start_menu/StartMenu.tscn", "Rebooting System...")
	else:
		var right_arm_ammo_cost = 0.0
		if player.get_max_ammo("arm_weapon_right") and player.get_ammo_cost("arm_weapon_right"):
			right_arm_ammo_cost = (player.get_max_ammo("arm_weapon_right") - player.get_total_ammo("arm_weapon_right")) * player.get_ammo_cost("arm_weapon_right")
		
		var left_arm_ammo_cost = 0.0
		if player.get_max_ammo("arm_weapon_left") and player.get_ammo_cost("arm_weapon_left"):
			left_arm_ammo_cost = (player.get_max_ammo("arm_weapon_left") - player.get_total_ammo("arm_weapon_left")) * player.get_ammo_cost("arm_weapon_left")
		
		var right_shoulder_ammo_cost = 0.0
		if player.get_max_ammo("shoulder_weapon_right") and player.get_ammo_cost("shoulder_weapon_right"):
			right_shoulder_ammo_cost = (player.get_max_ammo("shoulder_weapon_right") - player.get_total_ammo("shoulder_weapon_right")) * player.get_ammo_cost("shoulder_weapon_right")
		
		var left_shoulder_ammo_cost = 0.0
		if player.get_max_ammo("shoulder_weapon_left") and player.get_ammo_cost("shoulder_weapon_left"):
			left_shoulder_ammo_cost = (player.get_max_ammo("shoulder_weapon_left") - player.get_total_ammo("shoulder_weapon_left")) * player.get_ammo_cost("shoulder_weapon_left")
		print("Player Extracted! Kills: " + str(PlayerStatManager.PlayerKills))
		
		var total_ammo_cost = right_arm_ammo_cost + left_arm_ammo_cost + right_shoulder_ammo_cost + left_shoulder_ammo_cost
		
		var payout = 0
		if ArenaManager.tier == "Civ-Grade":
			payout = ArenaManager.CIV_GRADE_PAYOUT
		elif ArenaManager.tier == "Mil-Grade":
			payout = ArenaManager.MIL_GRADE_PAYOUT
		elif ArenaManager.tier == "State-Of-The-Art":
			payout = ArenaManager.SOA_GRADE_PAYOUT
		
		var conduct_kill_deduction = player_kills.size() * payout
		var conduct_downs_reward = player_downs.size() * payout * 0.25
		if conduct_kill_deduction > 0:
			conduct_downs_reward = 0
			payout = 0
		var conduct = conduct_downs_reward - conduct_kill_deduction
		
		var total_payout = (payout * 1.5) + conduct - total_ammo_cost
		
		ArenaManager.last_match = {
			"mode": ArenaManager.mode,
			"tier": ArenaManager.tier,
			"payout": payout,
			"total_payout": total_payout,
			"win": true,
			"downs": player_downs,
			"kills": player_kills,
			"conduct": conduct,
			"conduct_kill_deduction": conduct_kill_deduction,
			"conduct_downs_reward": conduct_downs_reward,
			"damage_taken": playerMech.max_hp - playerMech.hp,
			"right_arm_ammo_cost": right_arm_ammo_cost,
			"left_arm_ammo_cost": left_arm_ammo_cost,
			"right_shoulder_ammo_cost": right_shoulder_ammo_cost,
			"left_shoulder_ammo_cost": left_shoulder_ammo_cost,
			"total_ammo_cost": total_ammo_cost,
		}
		if ArenaManager.mode == "Exhibition" or ArenaManager.mode == "Challenge":
			TransitionManager.transition_to("res://game/ui/ladder/Ladder.tscn", "Downloading Data...")
			ArenaManager.last_match_unread = true
		elif ArenaManager.mode == "Tutorial":
			TransitionManager.transition_to("res://StartMenu.tscn", "Downloading Data...")


func _on_WindsTimer_timeout():
	random_wind_sound()


func _on_IntroAnimation_animation_ending():
	set_mechas_block_status(false)

#---TRIGGERS---

func tutorial1():
	var tutorial_text = PlayerHUD.get_node("SubViewportContainer/SubViewport/Tutorial")
	tutorial_text.play("t1")
