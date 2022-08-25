extends Node2D

const PLAYER = preload("res://game/mecha/player/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")
const SCRAP_PART = preload("res://game/arena/ScrapPart.tscn")
const TARGET_SPRITE = preload("res://assets/images/decals/bullet_hole_large.png")


onready var Mechas = $Mechas 
onready var Projectiles = $Projectiles
onready var ScrapParts = $ScrapParts
onready var PlayerHUD = $PlayerHUD
onready var GameOver = $GameOver
onready var ArenaCam = $ArenaCamera
onready var PauseMenu = $PauseMenu
onready var DebugNavigation = $DebugNavigation
onready var IntroAnimation = $Intro/IntroAnimation

var player
var all_mechas = []
var target_arena_zoom
var player_kills = 0
var is_tutorial := false


func _ready():
	randomize()
	
	setup_arena()
	
	player_kills = 0
	target_arena_zoom = ArenaCam.zoom
	
	add_player()
	for _i in range(1):
		add_enemy()
	for exitposition in $Exits.get_children():
		exitposition.connect("mecha_extracting", self, "_on_ExitPos_mecha_extracting")
		exitposition.connect("extracting_cancelled", self, "_on_ExitPos_extracting_cancelled")
	ShaderEffects.play_transition(0.0, 5000.0, 5.0)
	
	set_mechas_block_status(true)
	if is_tutorial:
		IntroAnimation.play("simEntrance")
	else:
		IntroAnimation.play("Entrance")


func _input(event):
	if event is InputEventKey:
		if event.pressed and event.scancode == KEY_ESCAPE:
			PauseMenu.toggle_pause()
		elif event.pressed and event.scancode == KEY_P:
			activate_arena_cam()
	if event is InputEventMouseButton:
		if ArenaCam.current:
			var amount = Vector2(.8, .8)
			if event.button_index == BUTTON_WHEEL_UP:
				target_arena_zoom -= amount
			elif event.button_index == BUTTON_WHEEL_DOWN:
				target_arena_zoom += amount
	if event.is_action_pressed("toggle_fullscreen"):
		OS.window_fullscreen = not OS.window_fullscreen
		OS.window_borderless = OS.window_fullscreen


func _process(dt):
	if player:
		ShaderEffects.update_shader_effect(player)
	update_arena_cam(dt)
	if Debug.ACTIVE:
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
	for child in arena_data.get_texts():
		$Texts.add_child(child.duplicate(7))
	
	for polygon in arena_data.get_navigation_polygons():
		$Navigation.add_child(polygon.duplicate(7))


func update_arena_cam(dt):
	if ArenaCam.current:
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
				var target = Sprite.new()
				target.texture = TARGET_SPRITE
				target.global_position = target_pos
				DebugNavigation.add_child(target)



func add_player():
	player = PLAYER.instance()
	Mechas.add_child(player)
	player.setup()
	player.position = get_start_position(1)
	player.connect("create_projectile", self, "_on_mecha_create_projectile")
	player.connect("died", self, "_on_mecha_died")
	player.connect("lost_health", self, "_on_player_lost_health")
	player.connect("mecha_extracted", self, "_on_player_mech_extracted")
	all_mechas.push_back(player)
	PlayerHUD.setup(player, all_mechas)
	player_ammo_set()


func add_enemy():
	var enemy = ENEMY.instance()
	Mechas.add_child(enemy)
	enemy.position = get_random_start_position([1])
	enemy.connect("create_projectile", self, "_on_mecha_create_projectile")
	enemy.connect("died", self, "_on_mecha_died")
	enemy.connect("player_kill", self, "_on_mecha_player_kill")
	all_mechas.push_back(enemy)
	enemy.setup(all_mechas, is_tutorial)


func player_died():
	player.queue_free()
	player = null
	PlayerHUD.player_died()
	if PauseMenu.is_paused():
		PauseMenu.toggle_pause()
	
	ShaderEffects.play_transition(5000.0, 0.0, 4.0)
	
	yield(get_tree().create_timer(5.0), "timeout")
	PlayerHUD.queue_free()
	$GameOver.killed()


func get_random_start_position(exclude_idx := []):
	var offset = 500
	var rand_offset = Vector2(rand_range(-offset, offset), rand_range(-offset, offset))
	var n_pos = $StartPositions.get_child_count()
	var idx = randi()%n_pos + 1
	while exclude_idx.has(idx):
		idx = randi()%n_pos + 1
	return $StartPositions.get_node("Pos"+str(idx)).position + rand_offset


func get_start_position(idx):
	return $StartPositions.get_node("Pos"+str(idx)).position


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
	var x = rand_range(-10000.00,10000.00)
	var y = rand_range(-10000.00,10000.00)
	var sound_pos = Vector2(x,y)
	var rand_wind = "small_shield_impact" + str((randi()%3) + 1)
	AudioManager.play_sfx(rand_wind, sound_pos, null, null, 2.5, 3000)
	print("Sound playing at location: " + str(x) + ", " + str(y))


func set_mechas_block_status(status):
	for mecha in Mechas.get_children():
		mecha.set_pause(status)
	if not status and not is_tutorial:
		AudioManager.play_bgm("ambience", true, 40)


func create_mecha_scraps(mecha):
	for texture in mecha.get_scraps():
		var scrap = SCRAP_PART.instance()
		scrap.setup(texture)
		scrap.position = mecha.position
		scrap.set_scale(mecha.scale)

		var impulse_dir = Vector2(rand_range(-1.0, 1.0), rand_range(-1.0, 1.0)).normalized()
		var impulse_force = rand_range(400,700)
		var impulse_torque = rand_range(5, 15)
		if randf() > .5:
			impulse_torque = -impulse_torque
		scrap.apply_impulse(Vector2(), impulse_dir*impulse_force)
		scrap.apply_torque_impulse(impulse_torque)
		ScrapParts.call_deferred("add_child", scrap)


func activate_arena_cam():
	ArenaCam.current = true
	if player:
		var player_cam = player.get_camera()
		ArenaCam.zoom = player_cam.zoom
		ArenaCam.position = player_cam.get_camera_screen_center()
		ArenaCam.reset_smoothing()


func _on_PauseMenu_pause_toggle(paused):
	if not paused:
		ShaderEffects.play_transition(0.0, 5000.0, 2.0)
	if player:
		player.set_pause(paused)
		PlayerHUD.set_pause(paused)


func _on_player_lost_health():
	ShaderEffects.damage_burst_effect()


func _on_mecha_create_projectile(mecha, args):
	#To avoid warning when mecha is killed during delay
	if args.delay > 0:
		var timer = Timer.new()
		timer.wait_time = args.delay
		add_child(timer)
		timer.start()
		yield(timer, "timeout")
		timer.queue_free()
	var data = ProjectileManager.create(mecha, args)
	if data.create_node:
		Projectiles.add_child(data.node)


func _on_mecha_died(mecha):
	var idx = all_mechas.find(mecha)
	if idx != -1:
		all_mechas.remove(idx)
	
	create_mecha_scraps(mecha)
	if mecha == player:
		player_died()
	else:
		mecha.queue_free()


func _on_mecha_player_kill():
	player_kills += 1


func _on_ExitPos_mecha_extracting(extractingMech):
	print(str(extractingMech.name) + str(" is extracting"))
	extractingMech.extracting()
	if extractingMech.name == "Player":
		$PlayerHUD/ExtractingLabel.visible = true


func _on_ExitPos_extracting_cancelled(extractingMech):
	if extractingMech == null:
		pass
	else:
		extractingMech.cancel_extract()
	if extractingMech.name == "Player":
		$PlayerHUD/ExtractingLabel.visible = false


func _on_player_mech_extracted(playerMech):
	if is_tutorial:
# warning-ignore:return_value_discarded
		get_tree().change_scene("res://game/start_menu/StartMenu.tscn")
	else:
		#TODO: Fix this
		PlayerStatManager.PlayerKills += player_kills
		PlayerStatManager.PlayerHP = playerMech.hp
		PlayerStatManager.PlayerMaxHP = playerMech.max_hp
		PlayerStatManager.NumberofExtracts += 1
		PlayerStatManager.Armor = playerMech.hp
		PlayerStatManager.RArmAmmo = player.get_total_ammo("arm_weapon_right")
		PlayerStatManager.RArmAmmoMax = player.get_max_ammo("arm_weapon_right")
		PlayerStatManager.RArmCost = player.get_ammo_cost("arm_weapon_right")
		PlayerStatManager.LArmAmmo = player.get_total_ammo("arm_weapon_left")
		PlayerStatManager.LArmAmmoMax = player.get_max_ammo("arm_weapon_left")
		PlayerStatManager.LArmCost = player.get_ammo_cost("arm_weapon_left")
		PlayerStatManager.RShoulderAmmo = player.get_total_ammo("shoulder_weapon_right")
		PlayerStatManager.RShoulderAmmoMax = player.get_max_ammo("shoulder_weapon_right")
		PlayerStatManager.RShoulderCost = player.get_ammo_cost("shoulder_weapon_right")
		PlayerStatManager.LShoulderAmmo = player.get_total_ammo("shoulder_weapon_left")
		PlayerStatManager.LShoulderAmmoMax = player.get_max_ammo("shoulder_weapon_left")
		PlayerStatManager.LShoulderCost = player.get_ammo_cost("shoulder_weapon_left")
		PlayerStatManager.RepairedLastRound = false
		print("Player Extracted! Kills: " + str(PlayerStatManager.PlayerKills))
# warning-ignore:return_value_discarded
		get_tree().change_scene("res://ScoreScreen.tscn")


func _on_WindsTimer_timeout():
	random_wind_sound()


func _on_IntroAnimation_animation_ending():
	set_mechas_block_status(false)
