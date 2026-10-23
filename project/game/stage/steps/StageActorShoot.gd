class_name StageActorShoot
extends StageStep

@export var actor := ""
@export var target_actor := ""
@export var weapon := "arm_weapon_left"
@export var shots := 3
@export var interval := 0.45
@export var aim_time := 0.6

var _mech: Node = null
var _fired := 0
var _timer := 0.0


func _start() -> void:
	_mech = director.find_actor(actor)
	if _mech == null or not _mech.has_method("shoot"):
		_finish()
		return
	if _mech.has_method("set_scripted"):
		_mech.set_scripted(true)
	_fired = 0
	_timer = aim_time
	_aim()


func _process(dt: float) -> void:
	if not is_running():
		return
	if not is_instance_valid(_mech):
		_finish()
		return
	_aim()
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = interval
	_mech.shoot(weapon)
	_fired += 1
	if _fired >= shots:
		_finish()


func _aim() -> void:
	var target := director.find_actor(target_actor)
	if target is Node2D:
		_mech.scripted_aim = target.global_position
