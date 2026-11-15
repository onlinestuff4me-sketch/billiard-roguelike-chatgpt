class_name Hud
extends Control
## Touch-first HUD, drawn entirely in code. Multi-touch: a floating stick on
## the left half of the screen, action buttons on the right.

signal restart_requested

var player: Player
var exit_pos := Vector2.ZERO
var boss: Enemy
var depth_name := ""
var depth := 1

var move_vector := Vector2.ZERO
var attack_held := false

var _touches := {}  # touch index -> role
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_active := false
var _toasts: Array = []
var _damage_pulse := 0.0
var _fade := 1.0
var _banner_t := 0.0
var _t := 0.0
var game_over := false
var _font: Font

const STICK_R := 80.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func toast(text: String, color: Color) -> void:
	_toasts.push_front({"text": text, "color": color, "t": 3.2})
	if _toasts.size() > 4:
		_toasts.pop_back()


func pulse_damage() -> void:
	_damage_pulse = 1.0


func show_floor_banner(p_depth: int, p_name: String) -> void:
	depth = p_depth
	depth_name = p_name
	_banner_t = 3.0
	_fade = 1.0


func _btn_layout() -> Dictionary:
	var s := size
	return {
		"attack": [Vector2(s.x - 140, s.y - 140), 74.0],
		"cleave": [Vector2(s.x - 295, s.y - 105), 48.0],
		"nova": [Vector2(s.x - 185, s.y - 290), 48.0],
		"potion": [Vector2(s.x - 62, s.y - 300), 38.0],
	}


func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	var drag := event as InputEventScreenDrag
	if touch:
		if touch.pressed:
			if game_over:
				restart_requested.emit()
				return
			var role := _role_at(touch.position)
			_touches[touch.index] = role
			match role:
				"attack":
					attack_held = true
				"cleave":
					if player: player.cast_cleave()
				"nova":
					if player: player.cast_nova()
				"potion":
					if player: player.drink_potion()
				"stick":
					_stick_active = true
					_stick_origin = touch.position
					_stick_pos = touch.position
					move_vector = Vector2.ZERO
		else:
			var r: String = _touches.get(touch.index, "")
			_touches.erase(touch.index)
			if r == "attack":
				attack_held = "attack" in _touches.values()
			elif r == "stick":
				_stick_active = false
				move_vector = Vector2.ZERO
	elif drag:
		if _touches.get(drag.index, "") == "stick":
			_stick_pos = drag.position
			var d: Vector2 = _stick_pos - _stick_origin
			if d.length() > STICK_R:
				# Drag the base along so the stick never "runs out".
				_stick_origin = _stick_pos - d.normalized() * STICK_R
				d = _stick_pos - _stick_origin
			move_vector = d / STICK_R if d.length() > 8.0 else Vector2.ZERO


func _role_at(pos: Vector2) -> String:
	var layout := _btn_layout()
	for k in layout:
		var c: Vector2 = layout[k][0]
		var r: float = layout[k][1]
		if pos.distance_to(c) <= r + 14.0:
			return k
	if pos.x < size.x * 0.55:
		return "stick"
	return "attack"  # anywhere else on the right half also attacks


func _process(delta: float) -> void:
	# Parent is a CanvasLayer, so anchors do not size us: follow the viewport.
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
	_t += delta
	_damage_pulse = maxf(_damage_pulse - delta * 2.5, 0.0)
	_fade = maxf(_fade - delta * 1.6, 0.0)
	_banner_t = maxf(_banner_t - delta, 0.0)
	for to in _toasts:
		to["t"] -= delta
	_toasts = _toasts.filter(func(x): return x["t"] > 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var s := size
	# Low-health vignette and hit pulse.
	var low := 1.0 - player.hp / player.max_hp
	var vig := maxf(_damage_pulse * 0.45, (low - 0.6) * 0.9 * (0.75 + sin(_t * 6.0) * 0.25))
	if vig > 0.0:
		for i in 6:
			var w := 18.0 + i * 18.0
			var col := Color(0.6, 0.0, 0.02, vig * (0.35 - i * 0.05))
			draw_rect(Rect2(0, 0, s.x, w), col)
			draw_rect(Rect2(0, s.y - w, s.x, w), col)
			draw_rect(Rect2(0, 0, w, s.y), col)
			draw_rect(Rect2(s.x - w, 0, w, s.y), col)

	_draw_orb(Vector2(70, 72), 52.0, player.hp / player.max_hp, Color(0.75, 0.05, 0.08), "%d" % int(ceil(player.hp)))
	_draw_orb(Vector2(165, 58), 36.0, player.mana / player.max_mana, Color(0.15, 0.3, 0.85), "%d" % int(player.mana))
	# Experience bar
	var xb := Rect2(20, 136, 200, 8)
	draw_rect(xb, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(xb.position, Vector2(xb.size.x * float(player.xp) / player.xp_next, xb.size.y)), Color(0.9, 0.75, 0.3))
	draw_rect(xb, Color(0.5, 0.42, 0.3), false, 1.0)
	_text(Vector2(20, 166), "Lv %d" % player.level, 18, Color(0.95, 0.88, 0.7))
	_text(Vector2(80, 166), "%d gold" % player.gold, 18, Color(1.0, 0.82, 0.3))
	_text(Vector2(s.x - 20, 34), "Depth %d" % depth, 20, Color(0.9, 0.85, 0.75), HORIZONTAL_ALIGNMENT_RIGHT)

	# Toasts
	for i in _toasts.size():
		var to: Dictionary = _toasts[i]
		var a := clampf(to["t"], 0.0, 1.0)
		var c: Color = to["color"]
		_text(Vector2(s.x * 0.5, 70 + i * 28), to["text"], 20, Color(c.r, c.g, c.b, a), HORIZONTAL_ALIGNMENT_CENTER)

	# Exit compass when the stairs are off-screen.
	var ppos := player.get_global_transform_with_canvas().origin
	var epos := player.get_canvas_transform() * exit_pos
	if s.x > 100.0 and s.y > 100.0 and not Rect2(Vector2.ZERO, s).grow(-40).has_point(epos):
		var dir := (epos - ppos).normalized()
		var edge := ppos + dir * minf(s.x, s.y) * 0.38
		var tip := edge + dir * 18
		draw_colored_polygon(PackedVector2Array([tip, edge + dir.orthogonal() * 10, edge - dir.orthogonal() * 10]), Color(0.6, 0.9, 1.0, 0.55 + sin(_t * 4) * 0.2))

	# Boss bar
	if boss and is_instance_valid(boss) and boss.awake and not boss.dead:
		var bw := minf(s.x * 0.5, 520.0)
		var br := Rect2(s.x * 0.5 - bw * 0.5, 18, bw, 14)
		draw_rect(br.grow(2), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(br.position, Vector2(bw * boss.hp / boss.max_hp, 14)), Color(0.6, 0.08, 0.6))
		_text(Vector2(s.x * 0.5, 52), boss.title, 18, Color(0.95, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER)

	# Controls
	var layout := _btn_layout()
	_draw_button(layout["attack"][0], layout["attack"][1], "STRIKE", Color(0.75, 0.2, 0.15), 0.0, attack_held)
	_draw_button(layout["cleave"][0], layout["cleave"][1], "CLEAVE", Color(1.0, 0.5, 0.15), player.cleave_cd / Player.CLEAVE_COOLDOWN, false, player.mana < Player.CLEAVE_COST)
	_draw_button(layout["nova"][0], layout["nova"][1], "NOVA", Color(0.45, 0.75, 1.0), player.nova_cd / Player.NOVA_COOLDOWN, false, player.mana < Player.NOVA_COST)
	_draw_button(layout["potion"][0], layout["potion"][1], "x%d" % player.potions, Color(0.85, 0.12, 0.2), 0.0, false, player.potions == 0)
	if _stick_active:
		draw_circle(_stick_origin, STICK_R, Color(1, 1, 1, 0.07))
		draw_arc(_stick_origin, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
		draw_circle(_stick_origin + move_vector * STICK_R, 34, Color(1, 0.9, 0.75, 0.35))
	else:
		var hint := Vector2(150, s.y - 150)
		draw_arc(hint, STICK_R, 0, TAU, 48, Color(1, 1, 1, 0.1), 2.0)
		draw_circle(hint, 30, Color(1, 1, 1, 0.06))

	# Floor banner and fade-in
	if _banner_t > 0.0:
		var a2 := clampf(_banner_t, 0.0, 1.0) * clampf((3.0 - _banner_t) * 3.0, 0.0, 1.0)
		_text(Vector2(s.x * 0.5, s.y * 0.32), depth_name, 40, Color(0.95, 0.85, 0.65, a2), HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(s.x * 0.5, s.y * 0.32 + 36), "Depth %d" % depth, 20, Color(0.8, 0.75, 0.65, a2), HORIZONTAL_ALIGNMENT_CENTER)
	if _fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, _fade))
	if game_over:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.1, 0, 0, 0.65))
		_text(Vector2(s.x * 0.5, s.y * 0.42), "THE LIGHT GOES OUT", 46, Color(0.9, 0.2, 0.15), HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(s.x * 0.5, s.y * 0.42 + 46), "Reached depth %d at level %d" % [depth, player.level], 20, Color(0.9, 0.8, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(s.x * 0.5, s.y * 0.42 + 90), "Tap to rise again", 22, Color(1, 0.9, 0.7, 0.6 + sin(_t * 3) * 0.3), HORIZONTAL_ALIGNMENT_CENTER)


func _text(pos: Vector2, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var w := 800.0
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	draw_string_outline(_font, Vector2(x, pos.y), text, align, w, font_size, 5, Color(0, 0, 0, color.a * 0.85))
	draw_string(_font, Vector2(x, pos.y), text, align, w, font_size, color)


func _draw_orb(c: Vector2, r: float, frac: float, col: Color, label: String) -> void:
	frac = clampf(frac, 0.0, 1.0)
	draw_circle(c, r + 5, Color(0.12, 0.1, 0.09))
	draw_circle(c, r, Color(0.04, 0.03, 0.03))
	if frac >= 0.985:
		draw_circle(c, r, col)
	elif frac > 0.015:
		# Liquid = circle segment under a gently waving surface.
		var dy := r - 2.0 * r * frac  # surface offset from centre (+ is down)
		var hw := sqrt(maxf(r * r - dy * dy, 0.0))
		var pts := PackedVector2Array()
		var steps := 14
		for i in steps + 1:
			var x := -hw + 2.0 * hw * float(i) / steps
			var wave := sin((c.x + x) * 0.12 + _t * 3.0) * 2.5 * sin(PI * float(i) / steps)
			var inside := sqrt(maxf(r * r - x * x, 0.0)) - 0.75
			pts.append(c + Vector2(x, clampf(dy + wave, -inside, inside)))
		var a0 := atan2(dy, hw)
		var a1 := PI - a0
		for i in range(1, 24):
			var a := a0 + (a1 - a0) * float(i) / 24.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		if hw > 3.0:
			draw_colored_polygon(pts, col)
	if frac > 0.015:
		draw_circle(c + Vector2(0, r * 0.35), r * 0.45, Color(col.r, col.g, col.b, 0.25).lightened(0.3))
	draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.18, Color(1, 1, 1, 0.22))
	draw_arc(c, r + 2, 0, TAU, 48, Color(0.55, 0.45, 0.3), 3.0)
	_text(c + Vector2(0, 7), label, 18, Color(1, 0.95, 0.9), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_button(c: Vector2, r: float, label: String, col: Color, cooldown: float, pressed := false, disabled := false) -> void:
	var sc := 0.92 if pressed else 1.0
	var rr := r * sc
	draw_circle(c, rr + 4, Color(0, 0, 0, 0.45))
	draw_circle(c, rr, Color(col.r, col.g, col.b, 0.28 if not disabled else 0.1))
	draw_arc(c, rr, 0, TAU, 48, Color(col.r, col.g, col.b, 0.9 if not disabled else 0.3), 3.0)
	if cooldown > 0.02:
		var pts := PackedVector2Array([c])
		var steps := 32
		for i in steps + 1:
			var a := -PI * 0.5 + TAU * cooldown * float(i) / steps
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
	_text(c + Vector2(0, 6), label, 16 if r < 60 else 20, Color(1, 0.95, 0.85, 1.0 if not disabled else 0.4), HORIZONTAL_ALIGNMENT_CENTER)
