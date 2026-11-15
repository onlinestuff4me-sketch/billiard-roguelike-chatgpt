class_name Actor
extends CharacterBody2D
## Shared combat body: health, armor, knockback and hit feedback.

signal died(actor: Actor)

const LAYER_WALL := 1
const LAYER_ENEMY := 2
const LAYER_PLAYER := 4

var max_hp := 50.0
var hp := 50.0
var armor := 0.0
var radius := 18.0
var dead := false
var knock := Vector2.ZERO
var flash_t := 0.0
var squash := Vector2.ONE
var anim_t := 0.0
var facing := 1.0


func setup_collision(layer: int, mask: int) -> void:
	collision_layer = layer
	collision_mask = mask
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)


## Returns the damage actually dealt.
func take_hit(amount: float, from: Vector2, knockback := 260.0, crit := false) -> float:
	if dead:
		return 0.0
	var dealt := maxf(1.0, amount * (100.0 / (100.0 + armor * 4.0)))
	hp -= dealt
	flash_t = 0.12
	squash = Vector2(1.35, 0.7)
	knock += (global_position - from).normalized() * knockback
	_on_hurt(dealt, crit)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		_on_death()
		died.emit(self)
	return dealt


func heal(amount: float) -> void:
	if dead:
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if hp - before >= 1.0:
		Fx.float_text(global_position, "+%d" % int(hp - before), Color(0.45, 1.0, 0.5))


func _on_hurt(_dealt: float, _crit: bool) -> void:
	pass


func _on_death() -> void:
	pass


func tick_feedback(delta: float) -> void:
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	squash = squash.lerp(Vector2.ONE, minf(delta * 14.0, 1.0))
	knock = knock.lerp(Vector2.ZERO, minf(delta * 10.0, 1.0))
	queue_redraw()


func body_color(base: Color) -> Color:
	return Color(3, 3, 3) if flash_t > 0.0 else base


func draw_shadow(size := 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * radius * 1.1 * size, sin(a) * radius * 0.45 * size + radius * 0.8))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
