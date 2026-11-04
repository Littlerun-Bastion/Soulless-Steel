class_name HudSquadOrders
extends PanelContainer

## The squad orders menu (Phase 5), the quick chat menu's twin. The
## squad_orders key (Z) opens it; 1 to 4 give that order (Squad.ORDERS:
## follow me, hold here, attack my target, regroup) through
## Player.give_order, and close it; the key again or Esc closes it. It
## doesn't open while controls are locked (cutscenes), the player is paused
## or dead, or the free cursor is held. PlayerHUD makes it beside the quick
## chat menu and hands it input first (handle_input). HudPanel, title
## LabelMetaBright, orders LabelBody.

const NUMBER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]
## The key's action (Player.ORDERS_ACTION; Player.gd has no class name).
const ORDERS_ACTION := "squad_orders"

var player = null

var _title: Label


func _ready() -> void:
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := MechUI.vbox(&"TightStack")
	_title = MechUI.label(&"LabelMetaBright")
	rows.add_child(_title)
	for i in Squad.ORDERS.size():
		var kind: String = Squad.ORDERS[i]
		rows.add_child(MechUI.label(&"LabelBody", "%d  %s" % [i + 1, str(Squad.ORDER_LABELS.get(kind, kind.to_upper()))]))
	add_child(rows)
	MechUI.ignore_mouse(self)
	visible = false


func setup(player_ref) -> void:
	player = player_ref


func player_died() -> void:
	player = null
	close()


func open() -> void:
	_title.text = "SQUAD ORDERS [%s]" % MechUI.key_name(ORDERS_ACTION)
	visible = true


func close() -> void:
	visible = false


## Gives order `index` (0-based) as the player, and closes. Returns whether
## the squad took it.
func send(index: int) -> bool:
	close()
	if not is_instance_valid(player) or index < 0 or index >= Squad.ORDERS.size():
		return false
	return player.give_order(Squad.ORDERS[index])


## Takes the keys the menu uses; true if it used `event`.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed(ORDERS_ACTION):
		if visible:
			close()
		elif _can_open():
			open()
		else:
			return false
		return true
	if not visible:
		return false
	if event.is_action_pressed("escape"):
		close()
		return true
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		var key: Key = key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
		var index := NUMBER_KEYS.find(key)
		if index >= 0:
			send(index)
			return true
	return false


func _can_open() -> bool:
	if not is_instance_valid(player):
		return false
	return not (player.controls_locked or player.paused or player.is_dead or MouseManager.free_cursor_held)
