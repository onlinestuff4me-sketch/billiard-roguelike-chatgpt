extends Node
## Global "juice" helpers: screen shake, hit-pause, particle bursts and
## floating combat text. Everything is generated at runtime so the game
## ships without external art.

var camera: Camera2D
var world: Node2D

var _trauma := 0.0
var _hitstop_until := 0.0
var _dot_tex: Texture2D
var _spark_tex: Texture2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_dot_tex = make_radial_texture(16, Color.WHITE, Color(1, 1, 1, 0))
	_spark_tex = make_radial_texture(8, Color.WHITE, Color(1, 1, 1, 0.0), 0.35)


static func make_radial_texture(size: int, inner: Color, outer: Color, hard := 0.0) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	if hard > 0.0:
		g.add_point(hard, inner)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


func _process(delta: float) -> void:
	if camera:
		_trauma = maxf(_trauma - delta * 2.2, 0.0)
		var s := _trauma * _trauma
		camera.offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 18.0 * s
		camera.rotation = _rng.randf_range(-1, 1) * 0.025 * s
	var now := Time.get_ticks_msec() / 1000.0
	if _hitstop_until > 0.0 and now >= _hitstop_until:
		_hitstop_until = 0.0
		Engine.time_scale = 1.0


func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Freeze-frame on heavy hits. Duration is in real seconds.
func hitstop(duration: float) -> void:
	Engine.time_scale = 0.04
	var until := Time.get_ticks_msec() / 1000.0 + duration
	_hitstop_until = maxf(_hitstop_until, until)


func burst(pos: Vector2, color: Color, amount := 14, speed := 220.0, life := 0.45, size := 1.0, gravity := 0.0) -> void:
	if world == null:
		return
	var p := CPUParticles2D.new()
	p.texture = _spark_tex
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = life
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = speed * 1.2
	p.damping_max = speed * 2.0
	p.gravity = Vector2(0, gravity)
	p.scale_amount_min = 1.2 * size
	p.scale_amount_max = 2.6 * size
	var ramp := Gradient.new()
	ramp.set_color(0, color.lightened(0.4))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.z_index = 50
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.2, true, false, true).timeout.connect(p.queue_free)


## A short-lived additive glow (muzzle flashes, impacts, level-ups).
func flash(pos: Vector2, color: Color, radius := 48.0, life := 0.18) -> void:
	if world == null:
		return
	var s := Sprite2D.new()
	s.texture = _dot_tex
	s.position = pos
	s.modulate = color
	s.scale = Vector2.ONE * radius / 8.0
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.z_index = 49
	world.add_child(s)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", s.scale * 1.6, life)
	tw.tween_property(s, "modulate:a", 0.0, life)
	tw.chain().tween_callback(s.queue_free)


## Expanding shockwave ring.
func ring(pos: Vector2, color: Color, radius := 200.0, life := 0.4) -> void:
	if world == null:
		return
	var line := Line2D.new()
	var pts := PackedVector2Array()
	for i in 41:
		pts.append(Vector2.from_angle(TAU * i / 40.0) * 10.0)
	line.points = pts
	line.width = 4.0
	line.default_color = color
	line.position = pos
	line.z_index = 48
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = mat
	world.add_child(line)
	var tw := line.create_tween()
	tw.set_parallel(true)
	tw.tween_property(line, "scale", Vector2.ONE * radius / 10.0, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(line, "width", 0.6, life)
	tw.tween_property(line, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(line.queue_free)


func float_text(pos: Vector2, text: String, color: Color, big := false) -> void:
	if world == null:
		return
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = 30 if big else 20
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.9)
	l.label_settings = ls
	l.position = pos + Vector2(_rng.randf_range(-14, 14), -30)
	l.z_index = 60
	l.pivot_offset = Vector2(20, 12)
	l.scale = Vector2.ONE * (1.7 if big else 1.3)
	world.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 46, 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)
