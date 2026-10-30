class_name StageStep
extends Node2D

signal done

var director: StageDirector = null

var _running := false


func run(stage_director: StageDirector) -> void:
	director = stage_director
	_running = true
	if director.is_skipping:
		_skip_to_end()
	else:
		_start()
	if _running:
		await done


func skip() -> void:
	if _running:
		_skip_to_end()


func stop() -> void:
	_finish()


func is_running() -> bool:
	return _running


func _start() -> void:
	_finish()


func _skip_to_end() -> void:
	_finish()


func _finish() -> void:
	if not _running:
		return
	_running = false
	done.emit()
