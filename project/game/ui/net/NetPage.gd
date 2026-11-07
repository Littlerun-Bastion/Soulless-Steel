class_name NetPage
extends VBoxContainer

## One page of a NET site. NetWindow makes it (NetSites.build), calls open()
## at the start of a load and puts it in its page area once the load is done.
## Links ask the window to go somewhere (navigate_requested) and tell it what
## they point at while the mouse is over them (link_hovered, "" on leaving),
## for the status bar. NetUI builds the page's parts and wires its links.
##
## Right-click: a node on the page with the meta "net_part" ([part_type,
## part_id]) makes the MechOS context menu a store "part" context there.

signal navigate_requested(url: String)
signal link_hovered(url: String)

## Shown in the window title as "NET // <page_title>".
var page_title := ""
var domain := ""
var path := "/"
var query: Dictionary = {}


func _init() -> void:
	theme_type_variation = &"NetZeroStack"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


## Builds the page for this path and query. Pages override this.
func open(page_path: String, page_query: Dictionary) -> void:
	path = page_path
	query = page_query


func follow(url: String) -> void:
	navigate_requested.emit(url)


func hover(url: String) -> void:
	link_hovered.emit(url)


## The store part under the mouse, as a MechOS "part" context.
func get_context_target(_global_pos: Vector2) -> Dictionary:
	var node: Node = get_viewport().gui_get_hovered_control()
	while node != null and node != self:
		if node.has_meta("net_part"):
			var entry: Array = node.get_meta("net_part")
			return {"type": "part", "part_type": entry[0], "part_id": entry[1],
					"grade": Grades.STANDARD, "from_store": true}
		node = node.get_parent()
	if has_meta("net_part"):
		var entry: Array = get_meta("net_part")
		return {"type": "part", "part_type": entry[0], "part_id": entry[1],
				"grade": Grades.STANDARD, "from_store": true}
	return {}
