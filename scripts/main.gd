extends Node2D
## Game controller: builds each depth, spawns foes and loot, and runs the
## descend / death / restart loop.

const BOSS_TITLES := [
	"Grell, Warden of the Ossuary",
	"Mother Kiln, the Ash-Wife",
	"The Choirmaster Below",
	"Vesk the Lantern-Eater",
]

var rng := RandomNumberGenerator.new()
var depth := 1
var world: Node2D
var dungeon: Dungeon
var stairs: Stairs
var player: Player
var camera: Camera2D
var hud: Hud
var ambient: CanvasModulate
var boss: Enemy
var transitioning := false
var dead_timer := 0.0
var kills := 0


func _ready() -> void:
	rng.randomize()
	ambient = CanvasModulate.new()
	add_child(ambient)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.zoom = Vector2(1.05, 1.05)
	add_child(camera)
	Fx.camera = camera
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.restart_requested.connect(_restart)
	_new_player()
	start_floor(1)


func _new_player() -> void:
	if player:
		player.queue_free()
	player = Player.new()
	player.hud = hud
	hud.player = player
	player.leveled_up.connect(func(lvl): hud.toast("You feel the Vigil strengthen. Level %d" % lvl, Color(1, 0.85, 0.4)))
	player.item_equipped.connect(func(item): hud.toast("Equipped %s  (%s)" % [item["name"], Items.describe(item)], Items.RARITY_COLORS[item["rarity"]]))
	player.died.connect(func(_a): dead_timer = 1.2)


func start_floor(d: int) -> void:
	depth = d
	transitioning = false
	if world:
		if player.get_parent() == world:
			world.remove_child(player)
		world.queue_free()
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	move_child(world, 0)
	Fx.world = world
	dungeon = Dungeon.new()
	dungeon.add_to_group("dungeon")
	dungeon.z_index = -5
	world.add_child(dungeon)
	dungeon.generate(depth, rng.randi())
	ambient.color = dungeon.theme["ambient"]
	stairs = Stairs.new()
	stairs.position = dungeon.exit_position()
	world.add_child(stairs)
	player.position = dungeon.start_position()
	player.knock = Vector2.ZERO
	world.add_child(player)
	camera.global_position = player.global_position
	camera.reset_smoothing()
	_populate()
	hud.exit_pos = stairs.position
	hud.boss = boss
	hud.show_floor_banner(depth, dungeon.theme["name"])


func _populate() -> void:
	boss = null
	var last := dungeon.rooms.size() - 1
	for i in range(1, dungeon.rooms.size()):
		var count := rng.randi_range(2, 3) + int(depth / 2)
		var elite_room := rng.randf() < 0.12 + depth * 0.02
		for j in count:
			var kind := "hollowed"
			var roll := rng.randf()
			if depth >= 2 and roll < 0.14 + depth * 0.01:
				kind = "brute"
			elif roll < 0.42:
				kind = "wisp"
			_spawn(kind, dungeon.random_floor_in_room(i), elite_room and j == 0, false)
	if depth % 3 == 0:
		boss = _spawn("brute", dungeon.exit_position() + Vector2(0, -90), false, true)
		boss.title = BOSS_TITLES[(depth / 3 - 1) % BOSS_TITLES.size()]
		stairs.sealed = true


func _spawn(kind: String, pos: Vector2, elite: bool, is_boss: bool) -> Enemy:
	var e := Enemy.new()
	e.configure(kind, depth, elite, is_boss)
	e.position = pos
	e.dropped_loot.connect(_on_enemy_died)
	world.add_child(e)
	return e


func _on_enemy_died(pos: Vector2, e: Enemy) -> void:
	kills += 1
	player.gain_xp(e.xp_value)
	if e.boss:
		stairs.sealed = false
		hud.toast("%s has fallen. The way down is open." % e.title, Color(0.95, 0.7, 1.0))
	var drops := []
	if rng.randf() < 0.65 or e.elite or e.boss:
		drops.append({"kind": "gold", "amount": rng.randi_range(3, 9) * (1 + depth) * (3 if e.elite else 1) * (6 if e.boss else 1)})
	var potion_chance := 0.1 + (0.12 if player.potions < 2 else 0.0)
	if rng.randf() < potion_chance or e.boss:
		drops.append({"kind": "potion"})
	var item_rolls := (1 if rng.randf() < 0.16 else 0) + (1 if e.elite else 0) + (3 if e.boss else 0)
	for i in item_rolls:
		drops.append({"kind": "item", "item": Items.generate(rng, depth, 0.15 if e.elite else (0.35 if e.boss else 0.0))})
	for dd in drops:
		var l := Loot.new()
		l.kind = dd["kind"]
		l.amount = dd.get("amount", 0)
		l.item = dd.get("item", {})
		var target := pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(24, 70)
		if not dungeon.is_floor(dungeon.world_to_cell(target)):
			target = pos
		l.launch(pos, target)
		l.collected.connect(_on_loot)
		world.add_child(l)
		if l.kind == "item":
			Sfx.play("loot", -8.0 if l.item["rarity"] < Items.Rarity.GILDED else -2.0, 0.0)


func _on_loot(l: Loot) -> void:
	match l.kind:
		"gold":
			player.gold += l.amount
			Sfx.play("gold", -10.0, 0.15)
			Fx.float_text(player.global_position, "+%dg" % l.amount, Color(1, 0.85, 0.3))
		"potion":
			if player.potions < player.max_potions:
				player.potions += 1
				hud.toast("Picked up a Crimson Draught", Color(0.95, 0.35, 0.35))
			else:
				player.gold += 10 * depth
			Sfx.play("potion", -10.0)
		"item":
			if not player.try_equip(l.item):
				var value: int = (5 + 5 * l.item["rarity"]) * depth
				player.gold += value
				hud.toast("Salvaged %s for %d gold" % [l.item["name"], value], Items.RARITY_COLORS[l.item["rarity"]].darkened(0.2))
			else:
				Fx.flash(player.global_position, Items.RARITY_COLORS[l.item["rarity"]], 90, 0.4)
				Fx.burst(player.global_position, Items.RARITY_COLORS[l.item["rarity"]], 24, 260, 0.6, 1.2, -200)
			Sfx.play("loot", -4.0, 0.0)
	player.stats_changed.emit()
	l.queue_free()


func _restart() -> void:
	hud.game_over = false
	kills = 0
	if world and player.get_parent() == world:
		world.remove_child(player)
	_new_player()
	start_floor(1)


func _process(delta: float) -> void:
	if player and not player.dead:
		camera.global_position = player.global_position + player.aim * 36.0
		if not transitioning and not stairs.sealed and player.global_position.distance_to(stairs.position) < 40.0:
			transitioning = true
			Sfx.play("stairs", -2.0, 0.0)
			player.heal(player.max_hp * 0.3)
			start_floor(depth + 1)
	elif player and player.dead and dead_timer > 0.0:
		dead_timer -= delta
		if dead_timer <= 0.0:
			hud.game_over = true
