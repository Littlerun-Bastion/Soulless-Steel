extends Resource

enum TYPE {INSTANT, REGULAR}

export (TYPE) var type
export var damage:= 10
export var image: Resource
export var collision_extents: Vector2
export var scale:= Vector2(1, 1)
export var speed:= 300

