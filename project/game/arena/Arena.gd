extends Node2D

const PLAYER = preload("res://game/mecha/player/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")

export var is_tutorial := false

onready var NavInstance = $Navigation2D/NavigationPolygonInstance
onready var Mechas = $Mechas 
onready var Projectiles = $Projectiles
onready var PlayerHUD = $PlayerHUD
onready var ArenaCam = $ArenaCamera
onready var VCREffect = $ShaderEffects/VCREffect
onready var VCRTween = $ShaderEffects/Tween
onready var PauseMenu = $PauseMenu
export var EnemyCount = 1

var player
var current_cam
var all_mechas = []
var target_arena_zoom
var player_kills = 0


func _ready():
	randomize()
	player_kills = 0
	target_arena_zoom = ArenaCam.zoom
	
	update_navigation_polygon()
	
	add_player()
	for _i in range(EnemyCount):
		add_enemy()
	for exitposition in $Exits.get_children():
		exitposition.connect("mecha_extracting", self, "_on_ExitPos_mecha_extracting")
		exitposition.connect("extracting_cancelled", self, "_on_ExitPos_extracting_cancelled")
	$ShaderEffects/VCREffect.play_transition(0.0, 5000.0, 5.0)
	#TODO fix this
	$GameOver/Label.visible = false
	$GameOver/ReturnButton.visible = false


func _input(event):
	if event is InputEventKey:
		if event.pressed and event.scancode == KEY_B:
			$ShaderEffects/VCREffect.visible = !$ShaderEffects/VCREffect.visible
		if event.pressed and event.scancode == KEY_C:
			# warning-ignore:return_value_discarded
			get_tree().change_scene("res://game/arena/Arena.tscn")
		if event.pressed and event.scancode == KEY_ESCAPE:
			PauseMenu.toggle_pause()
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
	update_shader_effect()
	update_arena_cam(dt)


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


func update_navigation_polygon():
	var arena_poly = NavInstance.navpoly
	
	#Add props collision to navigation
	var distance = 40
	var prop_polygons = []
	for i in range(0, $NavBlocks.get_child_count()):
		var prop = $NavBlocks.get_child(i)
		prop_polygons.append(prop.create_collision_polygon(distance))
		
	
	merge_polygons(prop_polygons)
	for polygon in prop_polygons:
		arena_poly.add_outline(polygon)
	arena_poly.make_polygons_from_outlines()
	
	NavInstance.set_navigation_polygon(arena_poly)
	#Toggle needed to update the navigation
	NavInstance.enabled = false
	NavInstance.enabled = true


func merge_polygons(polygons):
	while(true):
		var merged_something = false
		for i in polygons.size():
			var polygon = polygons[i]
			for j in range(i + 1, polygons.size()):
				var other_polygon = polygons[j]
				var merged_polygon = Geometry.merge_polygons_2d(polygon, other_polygon)
				if merged_polygon.size() == 1 or Geometry.is_polygon_clockwise(merged_polygon[1]):
					polygons.append(merged_polygon[0])
					merged_something = [i, j]
					break
			if merged_something:
				break
		if not merged_something:
			break
		else:
			polygons.remove(merged_something[1])
			polygons.remove(merged_something[0])


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
	PlayerHUD.setup(player, all_mechas, is_tutorial)
	current_cam = player.get_cam()
	player_ammo_set()


func add_enemy():
	var enemy = ENEMY.instance()
	Mechas.add_child(enemy)
	enemy.position = get_random_start_position([1])
	enemy.connect("create_projectile", self, "_on_mecha_create_projectile")
	enemy.connect("died", self, "_on_mecha_died")
	enemy.connect("player_kill", self, "_on_mecha_player_kill")
	all_mechas.push_back(enemy)
	enemy.setup(all_mechas, $Navigation2D, is_tutorial)


func player_died():
	player = null
	ArenaCam.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if PauseMenu.is_paused():
		PauseMenu.toggle_pause()
	PlayerHUD.queue_free()
	current_cam = ArenaCam
	$ShaderEffects/VCREffect.play_transition(5000.0, 0.0, 4.0)
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


func update_shader_effect():
	if player and not VCRTween.is_active():
		#Noise Intensity
		var target_noise = ((player.max_hp - player.hp)/float(player.max_hp)) * 0.0035
		var value = lerp(VCREffect.material.get_shader_param("noiseIntensity"), target_noise, .9)
		VCREffect.material.set_shader_param("noiseIntensity", value)
		#Color Offset Intensity
		value = lerp(VCREffect.material.get_shader_param("colorOffsetIntensity"), 0.175, .9)
		VCREffect.material.set_shader_param("colorOffsetIntensity", value)


func damage_burst_effect():
	if VCRTween.is_active():
		return
	VCRTween.interpolate_property(VCREffect.material, "shader_param/noiseIntensity", null, 0.02, .1)
	VCRTween.interpolate_property(VCREffect.material, "shader_param/colorOffsetIntensity", null, 1.2, .1)
	VCRTween.start()


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


func _on_PauseMenu_pause_toggle(paused):
	if not paused:
		$ShaderEffects/VCREffect.play_transition(0.0, 5000.0, 2.0)
	if player:
		player.set_pause(paused)
		PlayerHUD.set_pause(paused)


func _on_player_lost_health():
	damage_burst_effect()


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
	if mecha == player:
		player_died()


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
		get_tree().change_scene("res://StartMenu.tscn")
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


func _on_PlayerHUD_entrance_status(status):
	for mecha in Mechas.get_children():
		mecha.set_pause(status)
	if not status and not is_tutorial:
		AudioManager.play_bgm("ambience", true, 40)
