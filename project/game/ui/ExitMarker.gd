extends Control
class_name ExitMarker

# HUD pointer to the nearest extraction exit: an arrow at the edge of the
# screen in the exit's direction, with the distance next to it. Hidden once
# the exit is close enough to see, and when there's no player or no exit.
# The Expedition map's exits are far out at its edges; this is how the
# player finds them. Expedition switches it on (PlayerHUD.setup_exit_marker).
#
# The camera doesn't rotate, so a direction in the world is the same
# direction on screen; the player is near the middle of it.
# Arrow G6, distance LabelMetaBright (MechTheme).

const EDGE_MARGIN := Vector2(110, 110)
## World distance under which the exit is on screen and the marker hides.
const HIDE_WITHIN := 900.0
const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
const ARROW_SIZE := 28.0
const LABEL_GAP := 64.0

var player = null
var exits: Array = []
var nearest: Node2D = null
var arrow_position := Vector2.ZERO
var arrow_dir := Vector2.RIGHT

@onready var distance_label: Label = $DistanceLabel


func _ready() -> void:
	visible = false


func setup(player_ref, exit_nodes: Array) -> void:
	player = player_ref
	exits = exit_nodes
	_update()


func _process(_dt: float) -> void:
	_update()


func _update() -> void:
	nearest = find_nearest()
	var showing := nearest != null
	if showing:
		var to_exit: Vector2 = nearest.global_position - player.global_position
		showing = to_exit.length() > HIDE_WITHIN
		if showing:
			arrow_dir = to_exit.normalized()
			arrow_position = edge_point(size, arrow_dir)
			distance_label.text = format_distance(to_exit.length())
			distance_label.position = arrow_position - arrow_dir * LABEL_GAP - distance_label.size / 2.0
	visible = showing
	queue_redraw()


func find_nearest() -> Node2D:
	if player == null or not is_instance_valid(player):
		return null
	var best: Node2D = null
	var best_distance := INF
	for exit in exits:
		if not is_instance_valid(exit):
			continue
		var d: float = player.global_position.distance_to(exit.global_position)
		if d < best_distance:
			best = exit
			best_distance = d
	return best


# Where a ray from the middle of an area of this size, going in dir, meets a
# rectangle EDGE_MARGIN inside its edges.
static func edge_point(area: Vector2, dir: Vector2) -> Vector2:
	var center := area / 2.0
	var half := center - EDGE_MARGIN
	var tx := INF if is_zero_approx(dir.x) else half.x / absf(dir.x)
	var ty := INF if is_zero_approx(dir.y) else half.y / absf(dir.y)
	return center + dir * minf(tx, ty)


static func format_distance(distance: float) -> String:
	return "EXIT %d" % roundi(distance)


func _draw() -> void:
	var tip := arrow_position + arrow_dir * ARROW_SIZE
	var side := arrow_dir.orthogonal() * ARROW_SIZE * 0.75
	var back := arrow_position - arrow_dir * ARROW_SIZE * 0.5
	var notch := arrow_position - arrow_dir * ARROW_SIZE * 0.05
	draw_colored_polygon(PackedVector2Array([tip, back + side, notch, back - side]),
			THEME.get_color(&"g6", &"MechTokens"))
