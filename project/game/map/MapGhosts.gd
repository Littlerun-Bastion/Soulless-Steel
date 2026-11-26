class_name MapGhosts
extends RefCounted

# The mechas and Entities near the screen that a map layer drawn above them
# (the talls in TallsLean, the overheads in OverheadMeshFade) fades over, so
# the layer never hides a body the player could see without it. Each ghost
# has a weight: the body's modulate alpha, which the player's view sets to 0
# for a body it can't see, so the layer never gives away what the player
# can't see either.
#
# gather() lists the bodies (not the player, not dead) within MARGIN px of
# what the screen shows, nearest its centre first, at most MAX. write() puts
# the listed bodies' current positions and weights in a material's `ghosts`
# (vec3 x, y, weight) and `ghost_count`; a body hidden, freed or dead since
# the last gather is left out. update() gathers every LIST_TIME s and writes
# every call. With no Camera2D nothing is listed.

## The size of the shaders' ghosts arrays.
const MAX := 16
const LIST_TIME := 0.25
const MARGIN := 1500.0
const GROUPS := ["mecha", "entity"]

var bodies: Array[Node2D] = []
var _timer := 0.0
var _packed := PackedVector3Array()


func update(viewport: Viewport, player: Node2D, mat: ShaderMaterial, delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = LIST_TIME
		gather(viewport, player)
	write(mat)


func gather(viewport: Viewport, player: Node2D) -> void:
	bodies.clear()
	if viewport == null or viewport.get_camera_2d() == null:
		return
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var view := (to_world * viewport.get_visible_rect()).grow(MARGIN)
	var tree := viewport.get_tree()
	for group in GROUPS:
		for body in tree.get_nodes_in_group(group):
			var node := body as Node2D
			if node == null or node == player or node.get("is_dead") == true:
				continue
			if view.has_point(node.global_position):
				bodies.append(node)
	if bodies.size() > MAX:
		var centre := view.get_center()
		bodies.sort_custom(func(a: Node2D, b: Node2D) -> bool:
			return a.global_position.distance_squared_to(centre) < b.global_position.distance_squared_to(centre))
		bodies.resize(MAX)


func write(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	if _packed.size() != MAX:
		_packed.resize(MAX)
	var count := 0
	for node in bodies:
		if not is_instance_valid(node) or not node.is_visible_in_tree() or node.get("is_dead") == true:
			continue
		var weight := clampf(node.modulate.a, 0.0, 1.0)
		if weight <= 0.0:
			continue
		var p := node.global_position
		_packed[count] = Vector3(p.x, p.y, weight)
		count += 1
	mat.set_shader_parameter("ghosts", _packed)
	mat.set_shader_parameter("ghost_count", count)
