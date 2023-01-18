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
onready var BGMS = {}

#SFX
const MAX_SFX_NODES = 30
const MAX_POS_SFX_NODES = 200
const SFX_PATH = "res://database/audio/sfx/"
onready var SFXS = {}

onready var FadeTween = $FadeTween

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
		player.stream = AudioStreamRandomPitch.new()
		player.bus = "SFX"
		$SFXS.add_child(player)
	for node in MAX_POS_SFX_NODES:
		var player = AudioStreamPlayer2D.new()
		player.stream = AudioStreamRandomPitch.new()
		player.bus = "SFX"
		$PositionalSFXS.add_child(player)


func setup_bgms():
	var dir = Directory.new()
	if dir.open(BGM_PATH) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				#Found bgm file, creating data on memory
				BGMS[file_name.replace(".tres", "")] = load(BGM_PATH + file_name)
				
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access bgms path.")
		assert(false)


func setup_sfxs():
	var dir = Directory.new()
	if dir.open(SFX_PATH) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				SFXS[file_name.replace(".tres", "")] = load(SFX_PATH + file_name)
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access sfxs path.")
		assert(false)

#Bus methods

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
		assert(false, "Not a valid bus to set volume: " + str(which_bus))


func get_bus_volume(which_bus: int):
	if which_bus in [MASTER_BUS, SFX_BUS, BGM_BUS]:
		return clamp(1.0 - AudioServer.get_bus_volume_db(which_bus)/float(MUTE_DB/CONTROL_MULTIPLIER), 0.0, 1.0)
	else:
		assert(false, "Not a valid bus to set volume: " + str(which_bus))

#BGM methods

func play_bgm(name, start_from_beginning = false, fade_in_speed_override = false):
	if cur_bgm:
		stop_bgm()
	
	assert(BGMS.has(name), "Not a valid bgm name: " + str(name))
	cur_bgm = name
	var player = $BGMS/BGMPlayer1
	player.stream = BGMS[name].asset
	player.volume_db = MUTE_DB
	if start_from_beginning:
		player.play(0)
	else:
		player.play(get_bgm_last_pos(name))
	var fade_speed = FADEIN_SPEED if not fade_in_speed_override else fade_in_speed_override
	var duration = (BGMS[name].base_db - MUTE_DB)/float(fade_speed)
	FadeTween.remove(player, "volume_db")
	FadeTween.interpolate_property(player, "volume_db", MUTE_DB, BGMS[name].base_db, duration, Tween.TRANS_LINEAR, Tween.EASE_IN, 0)
	FadeTween.start()


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
		FadeTween.remove(fadeout, "volume_db")
		FadeTween.interpolate_property(fadeout, "volume_db", vol, MUTE_DB, duration, Tween.TRANS_LINEAR, Tween.EASE_IN, 0)
		FadeTween.start()


func get_bgm_last_pos(name):
	if not bgms_last_pos.has(name):
		bgms_last_pos[name] = 0
	return bgms_last_pos[name]


func set_bgm_last_pos(name, pos):
	bgms_last_pos[name] = pos

#SFX methods

func play_sfx(name: String, pos = false, override_pitch = false, override_db = false, override_att = false, override_max_range = false):
	if not SFXS.has(name):
		push_error("Not a valid sfx name: " + name)
		assert(false)
	
	var sfx = SFXS[name]
	var player = get_sfx_player(pos)
	player.stop()
	
	player.stream.audio_stream = sfx.asset
	player.volume_db = override_db if override_db else sfx.base_db + rand_range(-sfx.random_db_var, sfx.random_db_var)
	player.pitch_scale = max(override_pitch, 0.001) if override_pitch else sfx.base_pitch
	player.stream.random_pitch = 1.0 + sfx.random_pitch_var
	
	
	if pos:
		player.position = pos
		player.max_distance = override_max_range if override_max_range else sfx.max_range
		player.attenuation = override_att if override_att else sfx.attenuation
		
	player.play()


func get_sfx_duration(name: String):
	if not SFXS.has(name):
		push_error("Not a valid sfx name: " + name)
		assert(false)
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

