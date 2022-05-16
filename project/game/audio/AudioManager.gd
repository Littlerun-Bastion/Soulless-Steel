extends Node

#Bus
enum {MASTER_BUS, SFX_BUS}

#SFX
const MAX_SFX_NODES = 10
const MAX_POS_SFX_NODES = 10
const SFX_PATH = "res://database/audio/sfx/"
onready var SFXS = {}

var cur_sfx_player := 1
var cur_positional_sfx_player := 1

func _ready():
	setup_nodes()
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


func get_sfx_player(positional = false):
	var player
	if positional:
		player = $PositionalSFXS.get_child(cur_positional_sfx_player)
		cur_positional_sfx_player = (cur_positional_sfx_player+1)%$PositionalSFXS.get_child_count()
	else:
		player = $SFXS.get_child(cur_sfx_player)
		cur_sfx_player = (cur_sfx_player+1)%$SFXS.get_child_count()
	return player


func play_sfx(name: String, pos = false, override_pitch = false, override_db = false):
	if not SFXS.has(name):
		push_error("Not a valid sfx name: " + name)
		assert(false)
	var sfx = SFXS[name]
	var player = get_sfx_player(pos)
	player.stop()
	
	player.stream.audio_stream = sfx.asset
	
	if not override_db:
		var vol = sfx.base_db + rand_range(-sfx.random_db_var, sfx.random_db_var)
		player.volume_db = vol
	else:
		player.volume_db = override_db
	
	if override_pitch:
		override_pitch = max(override_pitch, 0.001)
		player.pitch_scale = override_pitch
	else:
		player.pitch_scale = sfx.base_pitch
	player.stream.random_pitch = 1.0 + sfx.random_pitch_var
	
	if pos:
		player.position = pos
	player.play()


func get_sfx_duration(name: String):
	if not SFXS.has(name):
		push_error("Not a valid sfx name: " + name)
		assert(false)
	return SFXS[name].asset.get_length()
