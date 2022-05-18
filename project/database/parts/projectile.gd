extends Resource

enum TYPE {INSTANT, REGULAR}

export (TYPE) var type
export var damage:= 10
export var image: Resource
export var decal_type:= "bullet_hole"
export var collision_extents: Vector2
export var scale:= Vector2(1, 1)
export var speed:= 400
export var light_energy:= 0.5
