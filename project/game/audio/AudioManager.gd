extends Node

#Bus
enum {MASTER_BUS, SFX_BUS, BGM_BUS}

#Volume/Fades
const MUTE_DB = -80
const CONTROL_MULTIPLIER = 2.5
const FADEOUT_SPEED = 20
const FADEIN_SPEED = 60

#BGM
const BGM_PATH = "res://database/audio/bgm/"
@onready var BGMS = {}

#SFX
const MAX_SFX_NODES = 30
const MAX_POS_SFX_NODES = 200
const SFX_PATH = "res://database/audio/sfx/"
@onready var SFXS = {}

var bgms_last_pos = {}
var cur_bgm
var cur_sfx_player := 1
var cur_positional_sfx_player := 1

func _ready():
	setup_nodes()
	setup_bgms()
	setup_sfxs()


func setup_nodes():
	for node in MAX_SFX_NODES:
		var player = AudioStreamPlayer.new()
		player.stream = AudioStreamRandomizer.new()
		player.bus = "SFX"
		$SFXS.add_child(player)
	for node in MAX_POS_SFX_NODES:
		var player = AudioStreamPlayer2D.new()
		player.stream = AudioStreamRandomizer.new()
		player.bus = "SFX"
		$PositionalSFXS.add_child(player)


func setup_bgms():
	var dir = DirAccess.open(BGM_PATH)
	if dir:
		dir.list_dir_begin() # TODOGODOT4 fill missing arguments https://github.com/godotengine/godot/pull/40547
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				#Found bgm file, creating data on memory
				BGMS[file_name.replace(".tres", "")] = load(BGM_PATH + file_name)
				
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access bgms path: " + str(DirAccess.get_open_error()))


func setup_sfxs():
	var dir = DirAccess.open(SFX_PATH)
	if dir:
		dir.list_dir_begin() # TODOGODOT4 fill missing arguments https://github.com/godotengine/godot/pull/40547
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				SFXS[file_name.replace(".tres", "")] = load(SFX_PATH + file_name)
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access sfxs path: " + str(DirAccess.get_open_error()))

##BUS METHODS

#Expects a value between 0 and 1
func set_bus_volume(which_bus: int, value: float):
	var db
	if value <= 0.0:
		db = MUTE_DB
	else:
		db = (1-value)*MUTE_DB/CONTROL_MULTIPLIER
	
	if which_bus in [MASTER_BUS, BGM_BUS, SFX_BUS]:
		AudioServer.set_bus_volume_db(which_bus, db)
	else:
		push_error("Not a valid bus to set volume: " + str(which_bus))


func get_bus_volume(which_bus: int):
	if which_bus in [MASTER_BUS, SFX_BUS, BGM_BUS]:
		return clamp(1.0 - AudioServer.get_bus_volume_db(which_bus)/float(MUTE_DB/CONTROL_MULTIPLIER), 0.0, 1.0)
	else:
		push_error("Not a valid bus to set volume: " + str(which_bus))

##BGM METHODS

func play_bgm(bgm_name, start_from_beginning = false, fade_in_speed_override = false):
	if cur_bgm:
		stop_bgm()
	
	assert(BGMS.has(bgm_name),"Not a valid bgm name: " + str(bgm_name))
	cur_bgm = bgm_name
	var player = $BGMS/BGMPlayer1
	player.stream = BGMS[bgm_name].asset
	player.volume_db = MUTE_DB
	if start_from_beginning:
		player.play(0)
	else:
		player.play(get_bgm_last_pos(bgm_name))
	var fade_speed = fade_in_speed_override
	if not fade_speed:
		fade_speed = FADEIN_SPEED
	var duration = (BGMS[bgm_name].base_db - MUTE_DB)/float(fade_speed)
	var tween = get_tree().create_tween()
	tween.tween_property(player, "volume_db", BGMS[bgm_name].base_db, duration)


func stop_bgm():
	var fadein = $BGMS/BGMPlayer1
	if fadein.is_playing():
		var fadeout = $BGMS/FadeOutBGMPlayer1
		var pos = fadein.get_playback_position()
		set_bgm_last_pos(cur_bgm, pos)
		var vol = fadein.volume_db
		fadein.stop()
		fadeout.stop()
		fadeout.volume_db = vol
		fadeout.stream = fadein.stream
		fadeout.play(pos)
		var duration = (vol - MUTE_DB)/FADEOUT_SPEED
		var tween = get_tree().create_tween()
		tween.tween_property(fadeout, "volume_db", MUTE_DB, duration)


func get_bgm_last_pos(bgm_name):
	if not bgms_last_pos.has(bgm_name):
		bgms_last_pos[bgm_name] = 0
	return bgms_last_pos[bgm_name]


func set_bgm_last_pos(bgm_name, pos):
	bgms_last_pos[bgm_name] = pos

#SFX methods

func play_sfx(sfx_name: String, pos = false, override_pitch = false, override_db = false, override_att = false, override_max_range = false):
	if not SFXS.has(sfx_name):
		push_error("Not a valid sfx name: " + sfx_name)
	
	var sfx = SFXS[sfx_name]
	var player = get_sfx_player(pos)
	player.stop()
	
	player.stream.add_stream(0, sfx.asset)
	player.volume_db = override_db if override_db else sfx.base_db + randf_range(-sfx.random_db_var, sfx.random_db_var)
	player.pitch_scale = max(override_pitch, 0.001) if override_pitch else sfx.base_pitch
	player.stream.random_pitch = 1.0 + sfx.random_pitch_var
	
	
	if pos:
		player.position = pos
		player.max_distance = override_max_range if override_max_range else sfx.max_range
		player.attenuation = override_att if override_att else sfx.attenuation
		
	player.play()


func get_sfx_duration(sfx_name: String):
	if not SFXS.has(sfx_name):
		push_error("Not a valid sfx name: " + sfx_name)
	return SFXS[name].asset.get_length()


func get_sfx_player(positional = false):
	var player
	if positional:
		player = $PositionalSFXS.get_child(cur_positional_sfx_player)
		cur_positional_sfx_player = (cur_positional_sfx_player+1)%$PositionalSFXS.get_child_count()
	else:
		player = $SFXS.get_child(cur_sfx_player)
		cur_sfx_player = (cur_sfx_player+1)%$SFXS.get_child_count()
	return player

