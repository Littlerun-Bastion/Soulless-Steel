class_name RepairBurst
extends Node2D

## What a repair kit leaves on the mecha that used it: a flash, rings running
## out from it and sparks, unshaded so they show in the dark, then gone.

const LIFETIME := 1.4
const RING_TIME := 0.8
const RING_DELAY := 0.18
const RING_FROM := 40.0
const RING_TO := 260.0
const RING_WIDTH := 6.0
const FLASH_TIME := 0.5
const FLASH_SCALE := 3.0
const SPARKS := 48
const COLOUR := Color(0.45, 1.0, 0.6)
const GLOW := preload("res://assets/images/light_sources/light_point_soft.png")

var _rings: Array[float] = [-1.0, -1.0]
var _age := 0.0


func _ready() -> void:
	z_index = 10
	material = _unshaded_add()
	_add_flash()
	_add_sparks()


func _process(dt: float) -> void:
	_age += dt
	for i in _rings.size():
		var t := (_age - RING_DELAY * i) / RING_TIME
		_rings[i] = t if t >= 0.0 and t <= 1.0 else -1.0
	queue_redraw()
	if _age >= LIFETIME:
		queue_free()


func _draw() -> void:
	for t in _rings:
		if t < 0.0:
			continue
		var eased := 1.0 - pow(1.0 - t, 3.0)
		var colour := COLOUR
		colour.a = 1.0 - t
		draw_arc(Vector2.ZERO, lerpf(RING_FROM, RING_TO, eased), 0.0, TAU, 64, colour, RING_WIDTH * (1.0 - t * 0.6), true)


func _add_flash() -> void:
	var flash := Sprite2D.new()
	flash.texture = GLOW
	flash.modulate = COLOUR
	flash.use_parent_material = true
	add_child(flash)
	var tween := flash.create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector2.ONE * FLASH_SCALE, FLASH_TIME).from(Vector2.ONE * 0.5)
	tween.tween_property(flash, "modulate:a", 0.0, FLASH_TIME).from(1.0)


func _add_sparks() -> void:
	var sparks := CPUParticles2D.new()
	sparks.amount = SPARKS
	sparks.one_shot = true
	sparks.explosiveness = 0.85
	sparks.lifetime = 0.7
	sparks.spread = 180.0
	sparks.gravity = Vector2.ZERO
	sparks.initial_velocity_min = 180.0
	sparks.initial_velocity_max = 480.0
	sparks.damping_min = 300.0
	sparks.damping_max = 500.0
	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 5.0
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(COLOUR, 0.0))
	sparks.color_ramp = fade
	sparks.use_parent_material = true
	add_child(sparks)
	sparks.emitting = true


func _unshaded_add() -> CanvasItemMaterial:
	var unshaded := CanvasItemMaterial.new()
	unshaded.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return unshaded
