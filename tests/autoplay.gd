extends Node
## Bot playtest: drives the Warden through the game through the same HUD
## inputs a thumb would use, then reports what happened.
## Usage: godot --path . tests/autoplay.tscn -- [seconds] [screenshot_dir]

var main: Node
var seconds := 120.0
var shot_dir := ""
var elapsed := 0.0
var next_shot := 3.0
var shots := 0
var deaths := 0
var max_depth := 1
var astar := AStarGrid2D.new()
var astar_for: Dungeon
var path: PackedVector2Array = []
var repath := 0.0
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var errors := 0
var next_status := 20.0
var last_status_pos := Vector2.ZERO
var dumped := false
var target: Actor
var last_status_depth := 0
var dump_frames := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seconds = float(args[0])
	if args.size() > 1:
		shot_dir = args[1]
		DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _build_astar(d: Dungeon) -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, Dungeon.W, Dungeon.H)
	astar.cell_size = Vector2(Dungeon.TILE, Dungeon.TILE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in Dungeon.H:
		for x in Dungeon.W:
			astar.set_point_solid(Vector2i(x, y), not d.is_floor(Vector2i(x, y)))
	astar_for = d


func _process(delta: float) -> void:
	elapsed += delta
	var p: Player = main.player
	var hud: Hud = main.hud
	var d: Dungeon = main.dungeon
	if p == null or d == null:
		return
	if astar_for != d:
		_build_astar(d)
		path = PackedVector2Array()
	max_depth = maxi(max_depth, main.depth)

	if hud.game_over:
		deaths += 1
		print("[bot] died on depth %d at level %d" % [main.depth, p.level])
		hud.restart_requested.emit()
		return
	if p.dead:
		hud.move_vector = Vector2.ZERO
		hud.attack_held = false
		return

	for e in get_tree().get_nodes_in_group("enemies"):
		var ec := d.world_to_cell(e.global_position)
		if not d.is_floor(ec) and not e.has_meta("in_wall"):
			e.set_meta("in_wall", true)
			errors += 1
			print("[bot] ENEMY IN WALL kind=%s boss=%s elite=%s pos=%s prev=%s vel=%s knock=%s depth=%d" % [e.kind, e.boss, e.elite, e.global_position, e.get_meta("prev", Vector2.ZERO), e.velocity, e.knock, main.depth])
		e.set_meta("prev", e.global_position)
	# Pick a goal: nearest awake/visible enemy, otherwise the stairs.
	var goal: Vector2 = main.stairs.position
	var near: Actor = p.nearest_enemy(1e9)
	var enemies_left := get_tree().get_nodes_in_group("enemies").size()
	# Lock onto one foe until it dies (clear the floor), then take the stairs.
	if target == null or not is_instance_valid(target) or target.dead:
		target = near
	if target:
		goal = target.global_position
	var close: Actor = p.nearest_enemy(260.0)
	hud.attack_held = close != null
	if close:
		var crowd := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if p.global_position.distance_to(e.global_position) < 200.0:
				crowd += 1
		if crowd >= 3:
			p.cast_nova()
		if crowd >= 2 or (close as Enemy).elite or (close as Enemy).boss:
			p.cast_cleave()
	if p.hp < p.max_hp * 0.4:
		p.drink_potion()

	repath -= delta
	if repath <= 0.0 or path.is_empty():
		repath = 0.4
		path = astar.get_point_path(d.world_to_cell(p.global_position), d.world_to_cell(goal))
		if path.size() > 0:
			path.remove_at(0)
	var move := Vector2.ZERO
	if close == null or p.global_position.distance_to(close.global_position) > 80.0:
		while path.size() > 0 and p.global_position.distance_to(path[0] + Vector2(32, 32)) < 24.0:
			path.remove_at(0)
		var target := goal if path.is_empty() else path[0] + Vector2(32, 32)
		move = (target - p.global_position).normalized()
	hud.move_vector = move
	stuck_t = stuck_t + delta if p.global_position.distance_to(last_pos) < 0.5 and move != Vector2.ZERO else 0.0
	last_pos = p.global_position
	if stuck_t > 3.0:
		var gc := d.world_to_cell(goal)
		print("[bot] stuck at %s cell %s on depth %d; goal %s cell %s floor=%s path=%d enemy_dist=%.0f" % [p.global_position, d.world_to_cell(p.global_position), main.depth, goal, gc, d.is_floor(gc), path.size(), p.global_position.distance_to(near.global_position) if near else -1.0])
		stuck_t = 0.0
		repath = 0.0

	if dump_frames > 0:
		dump_frames -= 1
		print("[bot] frame pos=%s last_safe=%s vel=%s move=%s path0=%s" % [p.global_position, p._last_safe, p.velocity, move, path[0] if path.size() > 0 else Vector2.ZERO])
	if elapsed >= next_status:
		next_status += 20.0
		if p.global_position.distance_to(last_status_pos) < 4.0 and not dumped and main.depth == last_status_depth:
			dumped = true
			dump_frames = 6
			var c := d.world_to_cell(p.global_position)
			for oy in range(-2, 3):
				var row := ""
				for ox in range(-2, 3):
					row += "." if d.is_floor(c + Vector2i(ox, oy)) else "#"
				print("[bot] grid ", row)
		last_status_pos = p.global_position
		last_status_depth = main.depth
		print("[bot] status t=%d depth=%d pos=%s cell=%s goal=%s path=%d move=%s close=%s near_d=%.0f kills=%d enemies=%d sealed=%s" % [int(elapsed), main.depth, p.global_position.round(), d.world_to_cell(p.global_position), goal.round(), path.size(), move, close != null, p.global_position.distance_to(target.global_position) if target else -1.0, main.kills, enemies_left, main.stairs.sealed])

	if shot_dir != "" and elapsed >= next_shot:
		next_shot += 10.0
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png("%s/shot_%02d.png" % [shot_dir, shots])
			shots += 1

	if elapsed >= seconds:
		var items := []
		for slot in p.equipment:
			if not p.equipment[slot].is_empty():
				items.append("%s [%s]" % [p.equipment[slot]["name"], Items.RARITY_NAMES[p.equipment[slot]["rarity"]]])
		print("[bot] SUMMARY time=%ds depth=%d max_depth=%d level=%d kills=%d gold=%d potions=%d deaths=%d hp=%d/%d dmg=%.1f" % [
			int(elapsed), main.depth, max_depth, p.level, main.kills, p.gold, p.potions, deaths, int(p.hp), int(p.max_hp), p.damage])
		print("[bot] gear: ", ", ".join(items))
		get_tree().quit()
