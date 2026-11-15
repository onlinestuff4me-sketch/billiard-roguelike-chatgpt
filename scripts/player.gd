class_name Player
extends Actor
## The Warden. Touch controls: left stick moves, hold ATTACK to auto-target
## the nearest foe, two skills on cooldowns, and a potion button.

signal stats_changed
signal leveled_up(level: int)
signal item_equipped(item: Dictionary)

var hud  # Hud, set by Main
var speed := 230.0
var level := 1
var xp := 0
var xp_next := 40
var gold := 0
var potions := 3
var max_potions := 5
var mana := 40.0
var max_mana := 40.0
var base_damage := 9.0
var base_hp := 80.0
var equipment := {"weapon": {}, "armor": {}, "charm": {}}

var damage := 9.0
var crit := 0.05
var lifesteal := 0.0
var attack_speed := 0.0

var attack_cd := 0.0
var cleave_cd := 0.0
var nova_cd := 0.0
const CLEAVE_COOLDOWN := 3.5
const NOVA_COOLDOWN := 8.0
const CLEAVE_COST := 12.0
const NOVA_COST := 20.0

var swing_t := 1.0
var swing_dir := Vector2.RIGHT
var swing_wide := false
var aim := Vector2.RIGHT
var light: PointLight2D
var invuln := 0.0
var walk_phase := 0.0


func _ready() -> void:
	radius = 16.0
	setup_collision(LAYER_PLAYER, LAYER_WALL | LAYER_ENEMY)
	add_to_group("player")
	light = PointLight2D.new()
	light.texture = Fx.make_radial_texture(256, Color.WHITE, Color(1, 1, 1, 0))
	light.texture_scale = 4.2
	light.energy = 1.5
	light.color = Color(1.0, 0.83, 0.6)
	add_child(light)
	recalc()
	hp = max_hp


func recalc() -> void:
	var lvl := level - 1
	damage = base_damage + lvl * 2.0
	max_hp = base_hp + lvl * 12.0
	armor = lvl * 0.5
	crit = 0.05
	lifesteal = 0.0
	attack_speed = 0.0
	for slot in equipment:
		var item: Dictionary = equipment[slot]
		if item.is_empty():
			continue
		var s: Dictionary = item["stats"]
		damage += s.get("damage", 0)
		armor += s.get("armor", 0)
		max_hp += s.get("max_hp", 0)
		crit += s.get("crit", 0.0)
		lifesteal += s.get("lifesteal", 0.0)
		attack_speed += s.get("attack_speed", 0.0)
	hp = minf(hp, max_hp)
	stats_changed.emit()


func try_equip(item: Dictionary) -> bool:
	var slot: String = item["slot"]
	if Items.score(item) > Items.score(equipment[slot]):
		equipment[slot] = item
		recalc()
		item_equipped.emit(item)
		return true
	return false


func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = int(xp_next * 1.45) + 10
		recalc()
		hp = max_hp
		mana = max_mana
		leveled_up.emit(level)
		Sfx.play("level", -3.0, 0.0)
		Fx.flash(global_position, Color(1.0, 0.85, 0.4), 140, 0.6)
		Fx.burst(global_position, Color(1.0, 0.8, 0.3), 40, 380, 0.9, 1.4, -200)
		Fx.float_text(global_position + Vector2(0, -30), "LEVEL %d" % level, Color(1.0, 0.85, 0.35), true)
	stats_changed.emit()


func _physics_process(delta: float) -> void:
	if dead:
		tick_feedback(delta)
		return
	attack_cd = maxf(attack_cd - delta, 0.0)
	cleave_cd = maxf(cleave_cd - delta, 0.0)
	nova_cd = maxf(nova_cd - delta, 0.0)
	invuln = maxf(invuln - delta, 0.0)
	mana = minf(max_mana, mana + delta * 4.0)
	swing_t = minf(swing_t + delta * 4.5, 1.0)

	var move := Vector2.ZERO
	if hud:
		move = hud.move_vector
	var kb := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if kb != Vector2.ZERO:
		move = kb.normalized()
	var attacking: bool = (hud != null and hud.attack_held) or Input.is_key_pressed(KEY_SPACE)

	var target := nearest_enemy(300.0)
	if target:
		aim = (target.global_position - global_position).normalized()
	elif move.length() > 0.1:
		aim = move.normalized()

	if attacking and target and move.length() < 0.1:
		var dist := global_position.distance_to(target.global_position)
		if dist > 72.0:
			move = aim  # auto-approach so one thumb can fight
	if attacking and attack_cd <= 0.0 and (target == null or global_position.distance_to(target.global_position) <= 90.0):
		basic_attack()

	if Input.is_key_pressed(KEY_Q):
		cast_cleave()
	if Input.is_key_pressed(KEY_E):
		cast_nova()
	if Input.is_key_pressed(KEY_R):
		drink_potion()

	var slow := 0.55 if swing_t < 0.6 else 1.0
	velocity = move * speed * slow + knock
	move_and_slide()
	keep_on_floor()
	if absf(aim.x) > 0.2:
		facing = signf(aim.x)
	if move.length() > 0.1:
		walk_phase += delta * 12.0
	tick_feedback(delta)


func nearest_enemy(max_dist: float) -> Actor:
	var best: Actor = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _hit_arc(dir: Vector2, reach: float, arc_deg: float, mult: float, knockback: float) -> int:
	var hits := 0
	var cos_limit := cos(deg_to_rad(arc_deg * 0.5))
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector2 = e.global_position - global_position
		if to.length() > reach + e.radius:
			continue
		if to.length() > 8.0 and to.normalized().dot(dir) < cos_limit:
			continue
		var is_crit := randf() < crit
		var amount := damage * mult * randf_range(0.85, 1.15) * (2.0 if is_crit else 1.0)
		var dealt: float = e.take_hit(amount, global_position, knockback * (1.6 if is_crit else 1.0), is_crit)
		hits += 1
		if lifesteal > 0.0:
			hp = minf(max_hp, hp + dealt * lifesteal)
		Fx.float_text(e.global_position, str(int(dealt)) + ("!" if is_crit else ""), Color(1.0, 0.85, 0.2) if is_crit else Color(1, 1, 1), is_crit)
		Fx.burst(e.global_position, Color(0.75, 0.05, 0.08), 10 if not is_crit else 22, 260, 0.5, 1.0, 400)
		if is_crit:
			Sfx.play("crit", -4.0)
			Fx.hitstop(0.09)
			Fx.shake(0.45)
		else:
			Sfx.play("hit", -6.0)
	if hits > 0:
		Fx.hitstop(0.035 if hits == 1 else 0.06)
		Fx.shake(0.18 + hits * 0.05)
	return hits


func basic_attack() -> void:
	attack_cd = 0.42 / (1.0 + attack_speed)
	swing_t = 0.0
	swing_dir = aim
	swing_wide = false
	Sfx.play("swing", -10.0, 0.15)
	_hit_arc(aim, 70.0, 120.0, 1.0, 240.0)


func cast_cleave() -> void:
	if cleave_cd > 0.0 or mana < CLEAVE_COST or dead:
		return
	mana -= CLEAVE_COST
	cleave_cd = CLEAVE_COOLDOWN
	swing_t = 0.0
	swing_dir = aim
	swing_wide = true
	Sfx.play("cast", -4.0)
	Fx.shake(0.35)
	for i in 5:
		var a := aim.rotated(deg_to_rad(-80 + i * 40)) * 80.0
		Fx.burst(global_position + a, Color(1.0, 0.45, 0.1), 12, 200, 0.6, 1.3, -120)
	Fx.flash(global_position + aim * 60, Color(1.0, 0.5, 0.15), 110, 0.25)
	_hit_arc(aim, 125.0, 210.0, 2.2, 380.0)


func cast_nova() -> void:
	if nova_cd > 0.0 or mana < NOVA_COST or dead:
		return
	mana -= NOVA_COST
	nova_cd = NOVA_COOLDOWN
	Sfx.play("nova", -2.0, 0.0)
	Fx.shake(0.6)
	Fx.hitstop(0.07)
	Fx.ring(global_position, Color(0.6, 0.85, 1.0), 230.0, 0.4)
	Fx.flash(global_position, Color(0.5, 0.8, 1.0), 200, 0.35)
	Fx.burst(global_position, Color(0.55, 0.85, 1.0), 48, 520, 0.6, 1.4)
	_hit_arc(Vector2.RIGHT, 230.0, 360.0, 1.4, 720.0)


func drink_potion() -> void:
	if potions <= 0 or dead or hp >= max_hp or attack_cd > 0.3:
		return
	potions -= 1
	attack_cd = 0.35
	heal(max_hp * 0.45)
	mana = minf(max_mana, mana + 15)
	Sfx.play("potion", -4.0)
	Fx.burst(global_position, Color(0.9, 0.15, 0.2), 24, 160, 0.7, 1.0, -260)
	stats_changed.emit()


func take_hit(amount: float, from: Vector2, knockback := 260.0, crit_hit := false) -> float:
	if invuln > 0.0:
		return 0.0
	var dealt := super.take_hit(amount, from, knockback * 0.5, crit_hit)
	if dealt > 0.0:
		invuln = 0.25
		Fx.float_text(global_position, "-%d" % int(dealt), Color(1.0, 0.3, 0.3))
		Fx.shake(0.3)
		Sfx.play("hurt", -4.0)
		if hud:
			hud.pulse_damage()
	stats_changed.emit()
	return dealt


func _on_death() -> void:
	Fx.burst(global_position, Color(0.7, 0.05, 0.05), 60, 300, 1.2, 1.6, 300)
	Fx.shake(1.0)
	Sfx.play("die", 0.0, 0.0)


func _draw() -> void:
	draw_shadow()
	var bob := sin(walk_phase) * 2.5
	var sx := squash.x * facing
	var sy := squash.y
	var tf := Transform2D(0, Vector2(sx, sy), 0, Vector2(0, bob))
	draw_set_transform_matrix(tf)
	if dead:
		draw_set_transform(Vector2(0, 8), PI * 0.5 * facing, Vector2.ONE)
	var cloak := body_color(Color(0.42, 0.09, 0.1))
	var cloak_dark := body_color(Color(0.24, 0.05, 0.07))
	var metal := body_color(Color(0.62, 0.6, 0.58))
	# Cloak
	draw_colored_polygon(PackedVector2Array([Vector2(-15, 14), Vector2(15, 14), Vector2(10, -12), Vector2(-10, -12)]), cloak)
	draw_colored_polygon(PackedVector2Array([Vector2(-15, 14), Vector2(-4, 14), Vector2(-6, -10), Vector2(-10, -12)]), cloak_dark)
	# Pauldrons and hood
	draw_circle(Vector2(0, -14), 11, cloak_dark)
	draw_circle(Vector2(2, -16), 9, cloak)
	draw_circle(Vector2(6, -16), 5, Color(0.05, 0.03, 0.04))
	draw_circle(Vector2(8, -17), 1.6, Color(1.0, 0.75, 0.35))
	draw_rect(Rect2(-12, -8, 24, 5), metal)
	# Lantern at the hip
	draw_line(Vector2(-12, 0), Vector2(-14, 8), metal, 1.5)
	draw_rect(Rect2(-18, 8, 8, 9), Color(1.0, 0.8, 0.4))
	draw_rect(Rect2(-18, 8, 8, 9), metal, false, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Weapon and slash trail, drawn unflipped in world-space direction.
	var base_ang := swing_dir.angle()
	var sweep := (PI * 1.25 if swing_wide else PI * 0.8)
	var reach := 78.0 if swing_wide else 52.0
	if swing_t < 1.0:
		var e := 1.0 - pow(1.0 - swing_t, 3.0)
		var cur := base_ang - sweep * 0.5 + sweep * e
		var trail := PackedVector2Array()
		var steps := 10
		for i in steps + 1:
			var a := base_ang - sweep * 0.5 + sweep * e * float(i) / steps
			trail.append(Vector2.from_angle(a) * reach)
		for i in range(steps, -1, -1):
			var a2 := base_ang - sweep * 0.5 + sweep * e * float(i) / steps
			trail.append(Vector2.from_angle(a2) * reach * 0.55)
		var col := Color(1.0, 0.55, 0.2, 0.55 * (1.0 - swing_t)) if swing_wide else Color(1, 0.95, 0.85, 0.5 * (1.0 - swing_t))
		if trail.size() >= 3 and sweep * e > 0.2:
			draw_colored_polygon(trail, col)
		draw_line(Vector2.from_angle(cur) * 10, Vector2.from_angle(cur) * reach * 0.9, metal, 4.0)
	else:
		var rest := Vector2(10 * facing, -2)
		draw_line(rest, rest + Vector2(14 * facing, 18), metal, 4.0)
