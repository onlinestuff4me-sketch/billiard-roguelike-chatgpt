class_name Stairs
extends Node2D
## Descent to the next depth: a stairwell with a cold, pulsing glow.

var t := 0.0
var sealed := false  # sealed while a floor boss lives


func _ready() -> void:
	z_index = -1
	var l := PointLight2D.new()
	l.texture = Fx.make_radial_texture(128, Color.WHITE, Color(1, 1, 1, 0))
	l.texture_scale = 2.2
	l.color = Color(0.45, 0.8, 1.0)
	l.energy = 0.9
	add_child(l)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var glow := 0.5 + sin(t * 2.5) * 0.2
	draw_rect(Rect2(-40, -40, 80, 80), Color(0.02, 0.02, 0.03))
	for i in 5:
		var y := -32.0 + i * 14.0
		var w := 64.0 - i * 8.0
		draw_rect(Rect2(-w * 0.5, y, w, 8), Color(0.25, 0.25, 0.3).darkened(i * 0.15))
	var col := Color(1.0, 0.3, 0.6, glow) if sealed else Color(0.45, 0.85, 1.0, glow)
	draw_arc(Vector2.ZERO, 46, 0, TAU, 40, col, 3.0)
	for i in 6:
		var a := t * 0.8 + i * TAU / 6.0
		draw_circle(Vector2(cos(a), sin(a)) * 46.0, 3.0, col)
