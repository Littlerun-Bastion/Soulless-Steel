extends RefCounted
class_name EntityPack

# Entities that move and hunt together (a Stalker pack). Members share a
# target: when one spots prey or is hurt, the rest join in. Only one member
# attacks at a time (it holds the attack token, then gives it back with a
# short cooldown), so the pack circles and darts in rather than piling on.
# A pack that loses half its members breaks: the survivors flee, then regroup
# as a smaller pack.
#
# The pack has no process of its own; its leader (first living member) ticks
# it from Entity._physics_process.

var members: Array = []
var target: Node2D = null
var broken := false

var _founding_size := 0
var _attacker: Node2D = null
var _token_cooldown := 0.0


func add(member: Node2D) -> void:
	if member in members:
		return
	members.append(member)
	member.pack = self
	_founding_size = maxi(_founding_size, members.size())


func remove(member: Node2D) -> void:
	members.erase(member)
	if _attacker == member:
		_attacker = null
	if _founding_size >= 2 and alive().size() * 2 <= _founding_size:
		broken = true


func alive() -> Array:
	return members.filter(func(m): return is_instance_valid(m) and not m.is_dead)


func leader() -> Node2D:
	var living := alive()
	return living[0] if not living.is_empty() else null


func is_leader(member: Node2D) -> bool:
	return leader() == member


func tick(dt: float) -> void:
	_token_cooldown = maxf(_token_cooldown - dt, 0.0)
	if _attacker != null and (not is_instance_valid(_attacker) or _attacker.is_dead):
		_attacker = null


# Everyone else in the pack turns on the prey too.
func alert(prey: Node2D, by: Node2D) -> void:
	target = prey
	for member in alive():
		if member != by:
			member.join_hunt(prey)


# Everyone heads for a noise together.
func investigate(point: Vector2, by: Node2D) -> void:
	for member in alive():
		if member != by:
			member.join_investigation(point)


func try_take_token(member: Node2D) -> bool:
	if _attacker != null and _attacker != member:
		return false
	if _attacker == null and _token_cooldown > 0.0:
		return false
	_attacker = member
	return true


func release_token(member: Node2D, cooldown: float) -> void:
	if _attacker == member:
		_attacker = null
		_token_cooldown = cooldown


func holds_token(member: Node2D) -> bool:
	return _attacker == member


# After fleeing, the survivors are a pack of their own size again.
func regroup() -> void:
	broken = false
	target = null
	_founding_size = alive().size()
