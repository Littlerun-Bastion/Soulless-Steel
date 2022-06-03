extends Control

const MESSAGE = preload("res://game/ui/Ticker/TickerMessage.tscn")
const SCROLL_SPEED = 150.0
const MARGIN = .5

var message_queue = []


func _ready():
# warning-ignore:return_value_discarded
	TickerManager.connect("new_message", self, "new_message")


func _process(_delta):
	if not message_queue.empty() and $Timer.is_stopped():
		add_message(message_queue.pop_front())


func new_message(text_data):
	var message = MESSAGE.instance()
	
	if text_data.type == "mecha_died":
		message.bbcode_text = "-  [color=red]%s[/color]" % text_data.source.to_upper()
		message.bbcode_text += "   [color=aqua][%s][/color]   " % text_data.weapon_name.to_upper()
		message.bbcode_text += "[color=red]%s[/color]  -" % text_data.self.to_upper()
	else:
		push_error("Not a valid message type: "+str(text_data.type))
	
	
	message_queue.append(message)


func add_message(message):
	$Messages.add_child(message)
	$Timer.wait_time = message.rect_size.x/SCROLL_SPEED + MARGIN
	$Timer.start()
	var length = -$BG.rect_size.x-message.rect_size.x
	var dur = abs(length)/SCROLL_SPEED
	$Tween.interpolate_property(message, "rect_position:x", 0, length, dur, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	$Tween.start()
	message.start_death_timer(dur)
