class_name Enemy
extends Actor
## Foes of the Gloam: shambling Hollowed, ember-spitting Wisps, and
## Gravebound Brutes whose slams are telegraphed on the floor.

signal dropped_loot(pos: Vector2, enemy: Enemy)

const KINDS := {
	"hollowed": {"hp": 26.0, "speed": 105.0, "damage": 7.0, "radius": 15.0, "xp": 8, "color": Color(0.52, 0.55, 0.45)},
	"wisp": {"hp": 16.0, "speed": 90.0, "damage": 8.0, "radius": 13.0, "xp": 10, "color": Color(1.0, 0.5, 0.2)},
	"brute": {"hp": 85.0, "speed": 62.0, "damage": 18.0, "radius": 24.0, "xp": 24, "color": Color(0.42, 0.38, 0.48)},
}

var kind := "hollowed"
var spd := 100.0
var dmg := 7.0
var xp_value := 8
var color := Color.WHITE
var elite := false
var boss := false
var title := ""
var awake := false
var attack_cd := 0.0
var windup := 0.0
var windup_pos := Vector2.ZERO
var lunge := 0.0
var strafe := 1.0
var hp_bar_t := 0.0


func configure(p_kind: String, depth: int, p_elite := false, p_boss := false) -> void:
	kind = p_kind
	var k: Dictionary = KINDS[kind]
	var scale_hp := 1.0 + (depth - 1) * 0.32
	var scale_dmg := 1.0 + (depth - 1) * 0.18
	elite = p_elite
	boss = p_boss
	max_hp = k["hp"] * scale_hp * (2.6 if elite else 1.0) * (9.0 if boss else 1.0)
	hp = max_hp
	dmg = k["damage"] * scale_dmg * (1.4 if elite else 1.0) * (1.6 if boss else 1.0)
	spd = k["speed"] * (1.12 if elite else 1.0)
	radius = k["radius"] * (1.3 if elite else 1.0) * (1.9 if boss else 1.0)
	xp_value = int(k["xp"] * (1.0 + depth * 0.25) * (3.0 if elite else 1.0) * (12.0 if boss else 1.0))
	color = k["color"]
	armor = depth * 0.8 + (6.0 if boss else 0.0)
	strafe = 1.0 if randf() < 0.5 else -1.0


func _ready() -> void:
	setup_collision(LAYER_ENEMY, LAYER_WALL | LAYER_ENEMY | LAYER_PLAYER)
	add_to_group("enemies")


func _physics_process(delta: float) -> void:
	if dead:
		return
	var player: Player = get_tree().get_first_node_in_group("player")
	attack_cd = maxf(attack_cd - delta, 0.0)
	hp_bar_t = maxf(hp_bar_t - delta, 0.0)
	var move := Vector2.ZERO
	if player and not player.dead:
		var to := player.global_position - global_position
		var dist := to.length()
		if not awake and (dist < 380.0 or hp < max_hp):
			awake = true
			Fx.float_text(global_position, "!", Color(1, 0.4, 0.3))
		if awake:
			match kind:
				"hollowed":
					move = _melee_ai(to, dist, delta, player)
				"brute":
					move = _brute_ai(to, dist, delta, player)
				"wisp":
					move = _wisp_ai(to, dist, delta)
	velocity = move * spd + knock
	if lunge > 0.0:
		lunge -= delta
	move_and_slide()
	if absf(velocity.x) > 5.0:
		facing = signf(velocity.x)
	tick_feedback(delta)


func _melee_ai(to: Vector2, dist: float, _delta: float, player: Player) -> Vector2:
	if dist < radius + player.radius + 14.0:
		if attack_cd <= 0.0:
			attack_cd = 1.0
			lunge = 0.15
			squash = Vector2(0.75, 1.3)
			player.take_hit(dmg, global_position, 200.0)
		return Vector2.ZERO
	return to.normalized()


func _brute_ai(to: Vector2, dist: float, delta: float, player: Player) -> Vector2:
	if windup > 0.0:
		windup -= delta
		if windup <= 0.0:
			# Slam: area damage on the telegraphed spot.
			Fx.shake(0.55 if not boss else 0.85)
			Fx.burst(windup_pos, Color(0.6, 0.55, 0.5), 30, 300, 0.6, 1.4, 200)
			Fx.ring(windup_pos, Color(1.0, 0.35, 0.25), 90.0 * (1.6 if boss else 1.0), 0.3)
			Sfx.play("nova", -8.0, 0.2)
			if player.global_position.distance_to(windup_pos) < 85.0 * (1.6 if boss else 1.0):
				player.take_hit(dmg, windup_pos, 520.0)
			attack_cd = 1.6 if not boss else 1.1
		return Vector2.ZERO
	if dist < radius + 70.0 and attack_cd <= 0.0:
		windup = 0.75 if not boss else 0.6
		windup_pos = global_position + to.normalized() * (radius + 30.0)
		return Vector2.ZERO
	return to.normalized()


func _wisp_ai(to: Vector2, dist: float, _delta: float) -> Vector2:
	var dir := to.normalized()
	if attack_cd <= 0.0 and dist < 420.0:
		attack_cd = 1.8 if not elite else 1.1
		_shoot(dir)
		if elite:
			_shoot(dir.rotated(0.25))
			_shoot(dir.rotated(-0.25))
	if dist < 170.0:
		return -dir
	if dist > 300.0:
		return dir
	return dir.orthogonal() * strafe * 0.6


func _shoot(dir: Vector2) -> void:
	var p := Projectile.new()
	p.velocity_vec = dir * 300.0
	p.damage = dmg
	p.color = Color(1.0, 0.5, 0.15)
	p.position = position + dir * (radius + 6.0)
	get_parent().add_child(p)
	Sfx.play("cast", -14.0, 0.2)
	Fx.flash(p.position, Color(1.0, 0.5, 0.2), 26, 0.12)


func _on_hurt(_dealt: float, _crit: bool) -> void:
	hp_bar_t = 2.5
	awake = true
	if windup > 0.0 and not boss and _crit:
		windup = 0.0  # crits interrupt a brute's slam
		attack_cd = 0.8


func _on_death() -> void:
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0
	Fx.burst(global_position, color.darkened(0.2), 26 if not boss else 80, 320, 0.7, 1.3, 300)
	Fx.burst(global_position, Color(0.6, 0.04, 0.06), 18 if not boss else 60, 220, 0.8, 1.0, 500)
	Fx.flash(global_position, Color(1, 0.6, 0.4), 60 if not boss else 220, 0.25)
	Sfx.play("die", -5.0 if not boss else 0.0)
	if boss:
		Fx.shake(1.0)
		Fx.hitstop(0.25)
	elif elite:
		Fx.shake(0.5)
		Fx.hitstop(0.1)
	dropped_loot.emit(global_position, self)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5).set_delay(0.3)
	tw.tween_callback(queue_free)


func _draw() -> void:
	if windup > 0.0:
		var r := 85.0 * (1.6 if boss else 1.0)
		var prog := 1.0 - windup / (0.75 if not boss else 0.6)
		var local := windup_pos - global_position
		draw_circle(local, r, Color(1, 0.1, 0.05, 0.12 + 0.15 * prog))
		draw_arc(local, r, 0, TAU, 40, Color(1, 0.25, 0.15, 0.8), 2.5)
		draw_circle(local, r * prog, Color(1, 0.2, 0.1, 0.25))
	draw_shadow()
	if elite or boss:
		var pulse := 0.5 + sin(anim_t * 5.0) * 0.2
		draw_circle(Vector2(0, radius * 0.8), radius * 1.3, Color(1.0, 0.75, 0.2, 0.18 * pulse) if elite else Color(0.8, 0.1, 0.9, 0.22 * pulse))
	var lean := Vector2(0, 0)
	if lunge > 0.0:
		lean = velocity.normalized() * 6.0
	draw_set_transform(lean, 0.0, squash * Vector2(facing, 1.0))
	var c := body_color(color)
	var dark := body_color(color.darkened(0.45))
	var bob := sin(anim_t * 7.0) * 2.0
	match kind:
		"hollowed":
			var r := radius
			draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.7, r * 0.9), Vector2(r * 0.7, r * 0.9), Vector2(r * 0.5, -r * 0.4 + bob), Vector2(-r * 0.6, -r * 0.3 + bob)]), dark)
			draw_circle(Vector2(r * 0.15, -r * 0.7 + bob), r * 0.55, c)
			draw_circle(Vector2(r * 0.35, -r * 0.75 + bob), r * 0.12, Color(0.9, 1.0, 0.6))
			draw_line(Vector2(r * 0.4, -r * 0.1 + bob), Vector2(r * 1.1, r * 0.25 + bob), c, 3.0)
		"brute":
			var r2 := radius
			draw_rect(Rect2(-r2 * 0.8, -r2 * 0.6 + bob * 0.5, r2 * 1.6, r2 * 1.5), dark)
			draw_circle(Vector2(-r2 * 0.75, -r2 * 0.45), r2 * 0.42, c)
			draw_circle(Vector2(r2 * 0.75, -r2 * 0.45), r2 * 0.42, c)
			draw_circle(Vector2(r2 * 0.1, -r2 * 0.85), r2 * 0.36, c.lightened(0.15))
			draw_rect(Rect2(r2 * 0.0, -r2 * 0.95, r2 * 0.35, r2 * 0.1), Color(1, 0.3, 0.2))
			draw_rect(Rect2(r2 * 0.6, -r2 * 0.2, r2 * 0.6, r2 * 0.9), body_color(Color(0.3, 0.28, 0.28)))
		"wisp":
			var r3 := radius
			var hover := sin(anim_t * 4.0) * 5.0 - 10.0
			draw_circle(Vector2(0, hover), r3 * 1.4, Color(1.0, 0.4, 0.1, 0.18))
			draw_circle(Vector2(0, hover), r3, c)
			draw_circle(Vector2(0, hover - 2), r3 * 0.6, body_color(Color(1.0, 0.85, 0.5)))
			draw_circle(Vector2(r3 * 0.25, hover - 3), r3 * 0.18, Color(0.15, 0.02, 0.0))
			for i in 3:
				var a := anim_t * 3.0 + i * TAU / 3.0
				draw_circle(Vector2(cos(a) * r3 * 1.5, hover + sin(a) * r3 * 0.6), 2.5, Color(1.0, 0.6, 0.2, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hp_bar_t > 0.0 and not boss:
		var w := radius * 2.4
		var y := -radius * 2.0 - 14.0
		draw_rect(Rect2(-w * 0.5, y, w, 5), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w * 0.5, y, w * hp / max_hp, 5), Color(0.85, 0.12, 0.12))
