class_name Loot
extends Node2D
## A drop on the floor: gold, a potion, or a piece of gear. Pops out of the
## enemy in an arc, then is collected automatically when the Warden is near.

signal collected(loot: Loot)

var kind := "gold"  # gold | potion | item
var amount := 0
var item := {}
var landed := false
var t := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _beam: PointLight2D


func launch(from: Vector2, to: Vector2) -> void:
	_from = from
	_to = to
	position = from


func _ready() -> void:
	z_index = 5
	if kind == "item" and item["rarity"] >= Items.Rarity.TEMPERED:
		_beam = PointLight2D.new()
		_beam.texture = Fx.make_radial_texture(64, Color.WHITE, Color(1, 1, 1, 0))
		_beam.texture_scale = 2.0
		_beam.energy = 0.0
		_beam.color = color()
		add_child(_beam)


func color() -> Color:
	match kind:
		"gold":
			return Color(1.0, 0.82, 0.25)
		"potion":
			return Color(0.95, 0.15, 0.2)
	return Items.RARITY_COLORS[item["rarity"]]


func _process(delta: float) -> void:
	t += delta
	if not landed:
		var k := minf(t / 0.45, 1.0)
		position = _from.lerp(_to, k) + Vector2(0, -sin(k * PI) * 70.0)
		if k >= 1.0:
			landed = true
			Fx.burst(position, color(), 8, 100, 0.3)
			if kind == "item" and item["rarity"] >= Items.Rarity.GILDED:
				Fx.flash(position, color(), 90, 0.5)
				Fx.shake(0.15)
	else:
		var player: Player = get_tree().get_first_node_in_group("player")
		if player and not player.dead:
			var d := position.distance_to(player.position)
			if kind == "gold" and d < 140.0:
				position = position.move_toward(player.position, delta * (200.0 + (140.0 - d) * 8.0))
			if d < 34.0:
				collected.emit(self)
				return
	if _beam:
		_beam.energy = 0.7 + sin(t * 4.0) * 0.2
	queue_redraw()


func _draw() -> void:
	var c := color()
	var bob := sin(t * 3.0) * 2.0 if landed else 0.0
	if landed:
		draw_circle(Vector2(0, 8), 8, Color(0, 0, 0, 0.35))
	if kind == "item" and landed and item["rarity"] >= Items.Rarity.TEMPERED:
		# Light pillar so good drops read from across the room.
		var h: float = 90.0 + 40.0 * item["rarity"]
		var a := 0.22 + sin(t * 4.0) * 0.06
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 6), Vector2(7, 6), Vector2(3, -h), Vector2(-3, -h)]), Color(c.r, c.g, c.b, a))
	match kind:
		"gold":
			for i in clampi(amount / 4, 1, 4):
				draw_circle(Vector2(i * 4 - 6, bob - i * 2), 5, c.darkened(0.15))
				draw_circle(Vector2(i * 4 - 6, bob - i * 2 - 1), 3.5, c)
		"potion":
			draw_circle(Vector2(0, bob), 8, c)
			draw_rect(Rect2(-3, bob - 14, 6, 7), Color(0.7, 0.65, 0.6))
			draw_circle(Vector2(-2, bob - 2), 2.5, Color(1, 0.7, 0.7))
		"item":
			match item["slot"]:
				"weapon":
					draw_line(Vector2(-9, 9 + bob), Vector2(9, -9 + bob), c, 4.0)
					draw_line(Vector2(-11, 3 + bob), Vector2(-3, 11 + bob), c.darkened(0.3), 3.0)
				"armor":
					draw_rect(Rect2(-9, -8 + bob, 18, 16), c.darkened(0.2))
					draw_rect(Rect2(-9, -8 + bob, 18, 16), c, false, 2.0)
				"charm":
					draw_circle(Vector2(0, bob), 7, c)
					draw_arc(Vector2(0, bob - 7), 5, PI, TAU, 8, c.lightened(0.3), 1.5)
