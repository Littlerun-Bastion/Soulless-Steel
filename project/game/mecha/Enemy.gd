extends Mecha

onready var n = "res://game/mecha/Node.gd"
onready var g = "res://game/mecha/Graphs.gd"
onready var p = "res://game/mecha/Player.gd"

var health = 100
var state = "roaming"
var speed = 100
var mov_vec = Vector2()

func _ready():
	pass 

func set_up(name, state):
	n.add_a_node("idle")
	n.add_a_node("roaming")
	n.add_a_node("targeting")

	g.add_connection("idle", "roaming", funcref(self, "idle_to_roaming"))
	g.add_connection("idle", "targeting", funcref(self, "idle_to_targeting"))
	g.add_connection("roaming", "idle", funcref(self, "roaming_to_idle"))
	g.add_connection("roaming", "targeting", funcref(self, "roaming_to_targeting"))
	g.add_connection("targeting", "idle", funcref(self, "targeting_to_idle"))
	g.add_connection("targeting", "roaming", funcref(self, "targeting_to_roaming"))


func _update():
	pass
	
	
func _process(delta):
	if state == "roaming":
		var final_pos = random_pos()
		self.position.x += final_pos.x * speed * delta
		self.position.y += final_pos.y * speed * delta

	updateFiniteLogic()


func idle_to_roaming(args):
	return true
	
	
func idle_to_targeting(args):
	return false
	
	
func roaming_to_idle(args):
	return false


func roaming_to_targeting(args):
	return false
	
	
func targeting_to_idle(args):
	return false
	
	
func targeting_to_roaming(args):
	return false
	
	
func random_pos():
	return Vector2(rand_range(100, get_viewport_rect().size.x-100), \
				   rand_range(100, get_viewport_rect().size.y-100))


func updateFiniteLogic():
	pass







 
