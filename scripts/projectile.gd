class_name Projectile
extends Node2D
## Enemy ember bolt. Uses manual overlap checks instead of physics bodies
## to stay cheap on phones.

var velocity_vec := Vector2.ZERO
var damage := 8.0
var color := Color(1, 0.5, 0.2)
var life := 2.5
var _trail: Array[Vector2] = []


func _ready() -> void:
	z_index = 20


func _physics_process(delta: float) -> void:
	life -= delta
	_trail.push_front(position)
	if _trail.size() > 7:
		_trail.pop_back()
	position += velocity_vec * delta
	var dungeon: Dungeon = get_tree().get_first_node_in_group("dungeon")
	var player: Player = get_tree().get_first_node_in_group("player")
	if player and not player.dead and position.distance_to(player.position) < player.radius + 8.0:
		player.take_hit(damage, position - velocity_vec.normalized() * 10.0, 160.0)
		_pop()
		return
	if life <= 0.0 or (dungeon and not dungeon.is_floor(dungeon.world_to_cell(position))):
		_pop()
		return
	queue_redraw()


func _pop() -> void:
	Fx.burst(position, color, 10, 160, 0.35)
	queue_free()


func _draw() -> void:
	for i in _trail.size():
		var t := 1.0 - float(i) / _trail.size()
		draw_circle(_trail[i] - position, 6.0 * t, Color(color.r, color.g, color.b, 0.35 * t))
	draw_circle(Vector2.ZERO, 11.0, Color(color.r, color.g, color.b, 0.3))
	draw_circle(Vector2.ZERO, 6.0, color)
	draw_circle(Vector2.ZERO, 3.0, Color(1, 0.95, 0.8))
