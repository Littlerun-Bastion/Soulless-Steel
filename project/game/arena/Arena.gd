extends Node2D

const PLAYER = preload("res://game/mecha/Player.tscn")
const ENEMY = preload("res://game/mecha/Enemy.tscn")


onready var NavInstance = $Navigation2D/NavigationPolygonInstance
onready var Mechas = $Mechas 
onready var Projectiles = $Projectiles
onready var PlayerHUD = $PlayerHUD
onready var ArenaCam = $ArenaCamera
onready var VCREffect = $ShaderEffects/VCREffect
onready var VCRTween = $ShaderEffects/Tween
onready var PauseMenu = $PauseMenu

var player
var current_cam
var all_mechas = []


func _ready():
	randomize()
	
	update_navigation_polygon()
	
	add_player()
	for _i in range(20):
		add_enemy()


func _input(event):
	if event is InputEventKey:
		if event.pressed and event.scancode == KEY_B:
			$ShaderEffects/VCREffect.visible = !$ShaderEffects/VCREffect.visible
		if event.pressed and event.scancode == KEY_C:
			# warning-ignore:return_value_discarded
			get_tree().change_scene("res://game/arena/Arena.tscn")
		if event.pressed and event.scancode == KEY_ESCAPE:
			PauseMenu.toggle_pause()


func _process(_dt):
	update_shader_effect()


func update_navigation_polygon():
	var arena_poly = NavInstance.get_navigation_polygon()
	
	#Resize arena to avoid navigation close to walls
	var polygon = NavigationPolygon.new()
	var outline = PoolVector2Array()
	var scaling = .93
	var transf = NavInstance.get_global_transform()
	for vertex in arena_poly.get_outline(0):
		vertex += NavInstance.position
		vertex *= scaling
		vertex -= NavInstance.position
		outline.append(transf.xform(vertex))
	polygon.add_outline(outline)
	polygon.make_polygons_from_outlines()
	arena_poly = polygon
	
	#Add props collision to navigation
	var distance = 250
	for prop in $Props.get_children():
		prop.add_collision_to_navigation(arena_poly, distance)
	arena_poly.make_polygons_from_outlines()
		
	NavInstance.set_navigation_polygon(arena_poly)
	NavInstance.enabled = false
	NavInstance.enabled = true


func add_player():
	player = PLAYER.instance()
	Mechas.add_child(player)
	player.position = get_start_position(1)
	player.connect("create_projectile", self, "_on_mecha_create_projectile")
	player.connect("died", self, "_on_mecha_died")
	player.connect("lost_health", self, "_on_player_lost_health")
	all_mechas.push_back(player)
	PlayerHUD.setup(player, all_mechas)
	current_cam = player.get_cam()


func add_enemy():
	var enemy = ENEMY.instance()
	Mechas.add_child(enemy)
	enemy.position = get_random_start_position([1])
	enemy.connect("create_projectile", self, "_on_mecha_create_projectile")
	enemy.connect("died", self, "_on_mecha_died")
	all_mechas.push_back(enemy)
	enemy.setup(all_mechas, $Navigation2D)


func player_died():
	player = null
	ArenaCam.current = true
	PlayerHUD.queue_free()
	current_cam = ArenaCam


func get_random_start_position(exclude_idx := []):
	var offset = 250
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


func _on_player_lost_health():
	damage_burst_effect()


func _on_mecha_create_projectile(mecha, args):
	yield(get_tree().create_timer(args.delay), "timeout")
	var data = ProjectileManager.create(mecha, args)
	if data.create_node:
		Projectiles.add_child(data.node)


func _on_mecha_died(mecha):
	var idx = all_mechas.find(mecha)
	if idx != -1:
		all_mechas.remove(idx)
	if mecha == player:
		player_died()
