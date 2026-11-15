class_name Dungeon
extends Node2D
## Procedural rooms-and-corridors floor, drawn with code in a 3/4 view.

const TILE := 64
const W := 56
const H := 56

const THEMES := [
	{"name": "The Sunken Ossuary", "floor": Color(0.22, 0.2, 0.24), "wall": Color(0.33, 0.3, 0.36), "ambient": Color(0.2, 0.18, 0.26), "accent": Color(1.0, 0.7, 0.35)},
	{"name": "The Cinder Halls", "floor": Color(0.26, 0.17, 0.15), "wall": Color(0.4, 0.24, 0.2), "ambient": Color(0.26, 0.14, 0.12), "accent": Color(1.0, 0.45, 0.2)},
	{"name": "The Drowned Choir", "floor": Color(0.14, 0.21, 0.22), "wall": Color(0.2, 0.32, 0.33), "ambient": Color(0.11, 0.19, 0.22), "accent": Color(0.45, 0.95, 0.85)},
]

var grid: PackedByteArray  # 0 = wall, 1 = floor
var rooms: Array[Rect2i] = []
var theme: Dictionary
var depth := 1
var rng := RandomNumberGenerator.new()
var _decor: Array = []


func generate(p_depth: int, seed_value: int) -> void:
	depth = p_depth
	rng.seed = seed_value
	theme = THEMES[int((depth - 1) / 3) % THEMES.size()]
	grid = PackedByteArray()
	grid.resize(W * H)
	rooms.clear()
	var target := 7 + mini(depth, 6)
	var attempts := 0
	while rooms.size() < target and attempts < 400:
		attempts += 1
		var rw := rng.randi_range(6, 12)
		var rh := rng.randi_range(5, 10)
		var r := Rect2i(rng.randi_range(2, W - rw - 3), rng.randi_range(2, H - rh - 3), rw, rh)
		var ok := true
		for o in rooms:
			if r.grow(2).intersects(o):
				ok = false
				break
		if ok:
			rooms.append(r)
	# Sort rooms so the path from first to last wanders across the map.
	rooms.sort_custom(func(a, b): return a.position.x + a.position.y < b.position.x + b.position.y)
	for r in rooms:
		_carve(r)
	for i in range(1, rooms.size()):
		_corridor(_center(rooms[i - 1]), _center(rooms[i]))
	# A couple of loops so the map is not a single line.
	for i in 2:
		var a := rng.randi() % rooms.size()
		var b := rng.randi() % rooms.size()
		if a != b:
			_corridor(_center(rooms[a]), _center(rooms[b]))
	_place_decor()
	_build_collision()
	queue_redraw()


func _center(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


func _carve(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			grid[y * W + x] = 1


func _corridor(a: Vector2i, b: Vector2i) -> void:
	var p := a
	var horizontal_first := rng.randf() < 0.5
	for leg in 2:
		var horiz := horizontal_first if leg == 0 else not horizontal_first
		while (horiz and p.x != b.x) or (not horiz and p.y != b.y):
			for oy in 2:
				for ox in 2:
					var cx := clampi(p.x + ox, 1, W - 2)
					var cy := clampi(p.y + oy, 1, H - 2)
					grid[cy * W + cx] = 1
			if horiz:
				p.x += signi(b.x - p.x)
			else:
				p.y += signi(b.y - p.y)


func is_floor(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return false
	return grid[c.y * W + c.x] == 1


func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE, TILE) * 0.5


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func start_position() -> Vector2:
	return cell_to_world(_center(rooms[0]))


func exit_position() -> Vector2:
	return cell_to_world(_center(rooms[rooms.size() - 1]))


func random_floor_in_room(room_index: int) -> Vector2:
	var r := rooms[room_index]
	var c := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
	return cell_to_world(c)


func _place_decor() -> void:
	_decor.clear()
	for child in get_children():
		child.queue_free()
	var light_tex := Fx.make_radial_texture(128, Color.WHITE, Color(1, 1, 1, 0))
	for i in rooms.size():
		var r := rooms[i]
		# Braziers in the corners of some rooms: real lights, kept sparse for mobile.
		if i > 0 and rng.randf() < 0.6:
			var c := r.position + Vector2i(1, 1)
			var pos := cell_to_world(c)
			_decor.append({"type": "brazier", "pos": pos})
			var l := PointLight2D.new()
			l.texture = light_tex
			l.position = pos
			l.texture_scale = 3.2
			l.energy = 0.9
			l.color = theme["accent"]
			l.set_meta("flicker", rng.randf() * 10.0)
			add_child(l)
		for j in rng.randi_range(2, 6):
			var c2 := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
			_decor.append({"type": ["bones", "stain", "crack", "candle"][rng.randi() % 4], "pos": cell_to_world(c2) + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)), "rot": rng.randf() * TAU})


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for child in get_children():
		if child is PointLight2D and child.has_meta("flicker"):
			var f: float = child.get_meta("flicker")
			child.energy = 0.8 + sin(t * 9.0 + f) * 0.08 + sin(t * 23.0 + f * 2.0) * 0.05


func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	# Merge horizontal runs of wall cells that touch the floor into single boxes.
	for y in H:
		var run_start := -1
		for x in W + 1:
			var solid := x < W and grid[y * W + x] == 0 and _touches_floor(Vector2i(x, y))
			if solid and run_start < 0:
				run_start = x
			elif not solid and run_start >= 0:
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2((x - run_start) * TILE, TILE)
				shape.shape = rect
				shape.position = Vector2(run_start * TILE + rect.size.x * 0.5, y * TILE + TILE * 0.5)
				body.add_child(shape)
				run_start = -1


func _touches_floor(c: Vector2i) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if is_floor(c + Vector2i(ox, oy)):
				return true
	return false


func _draw() -> void:
	var floor_col: Color = theme["floor"]
	var wall_col: Color = theme["wall"]
	var noise := RandomNumberGenerator.new()
	noise.seed = rng.seed + 99
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var rect := Rect2(Vector2(c) * TILE, Vector2(TILE, TILE))
			if is_floor(c):
				# Flagstones with a little per-tile variation and mortar lines.
				var v := noise.randf_range(-0.035, 0.035)
				draw_rect(rect, floor_col.lightened(v) if v > 0 else floor_col.darkened(-v))
				draw_rect(rect.grow(-2), floor_col.lightened(0.04 + v), false, 1.0)
				if noise.randf() < 0.25:
					var a := rect.position + Vector2(noise.randf_range(8, 56), noise.randf_range(8, 56))
					draw_line(a, a + Vector2(noise.randf_range(-14, 14), noise.randf_range(-14, 14)), floor_col.darkened(0.3), 1.5)
				# Soft shadow cast by a wall directly above.
				if not is_floor(c + Vector2i(0, -1)):
					draw_rect(Rect2(rect.position, Vector2(TILE, 18)), Color(0, 0, 0, 0.35))
			elif _touches_floor(c):
				var v2 := noise.randf_range(-0.05, 0.05)
				var top := wall_col.lightened(v2 + 0.05)
				draw_rect(rect, top)
				# Brick seams on the top face.
				for row in 3:
					var yy := rect.position.y + row * 16 + 6
					draw_line(Vector2(rect.position.x, yy), Vector2(rect.end.x, yy), wall_col.darkened(0.25), 1.0)
				# Front face when the wall overlooks floor: a darker lip gives height.
				if is_floor(c + Vector2i(0, 1)):
					var lip := Rect2(rect.position + Vector2(0, TILE * 0.62), Vector2(TILE, TILE * 0.38))
					draw_rect(lip, wall_col.darkened(0.45))
					draw_line(lip.position, lip.position + Vector2(TILE, 0), wall_col.lightened(0.25), 2.0)
	for d in _decor:
		var p: Vector2 = d["pos"]
		match d["type"]:
			"brazier":
				draw_circle(p + Vector2(0, 10), 16, Color(0, 0, 0, 0.4))
				draw_rect(Rect2(p + Vector2(-10, -4), Vector2(20, 16)), Color(0.18, 0.15, 0.13))
				draw_circle(p + Vector2(0, -6), 9, theme["accent"])
				draw_circle(p + Vector2(0, -9), 5, Color(1, 0.95, 0.75))
			"bones":
				var dir := Vector2.from_angle(d["rot"])
				draw_line(p - dir * 10, p + dir * 10, Color(0.75, 0.72, 0.62), 3.0)
				draw_circle(p - dir * 11, 3, Color(0.75, 0.72, 0.62))
				draw_circle(p + dir * 11, 3, Color(0.75, 0.72, 0.62))
			"stain":
				draw_circle(p, 14, Color(0.25, 0.03, 0.04, 0.45))
				draw_circle(p + Vector2(9, 5), 7, Color(0.25, 0.03, 0.04, 0.4))
			"crack":
				var q := p
				for k in 4:
					var nq := q + Vector2.from_angle(d["rot"] + k * 0.7) * 9
					draw_line(q, nq, Color(0, 0, 0, 0.45), 1.5)
					q = nq
			"candle":
				draw_rect(Rect2(p + Vector2(-2, -8), Vector2(4, 9)), Color(0.85, 0.82, 0.7))
				draw_circle(p + Vector2(0, -11), 3, theme["accent"].lightened(0.3))
