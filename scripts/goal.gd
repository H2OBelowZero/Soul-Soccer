class_name Goal
extends Node3D
## A street goal: steel cage, and brick pillars that grow inward with every goal conceded.
## `count` bricks sit on EACH side of the mouth, so the opening shrinks by 2 × BRICK_W per goal.

const BRICK_W := 0.55
const DEPTH := 1.3

var game: Game
var side := 0        # team defending this goal
var sgn := -1.0      # -x end for team 0, +x end for team 1
var count := 0
var columns: Array[Node3D] = []
var inset := 0.0     # 3v3: steel posts moved in from each side — a smaller target, no keeper
var posts: Array[Node3D] = []


func setup(g: Game, s: int) -> void:
	game = g
	side = s
	sgn = -1.0 if s == 0 else 1.0
	name = "Goal%d" % s
	var L := Arena.L
	var gh := Arena.GOAL_H
	var gw := Arena.GOAL_HALF
	var cx := sgn * (L + DEPTH / 2)

	Arena.solid(self, Vector3(0.2, gh, 2 * gw + 0.4), Vector3(sgn * (L + DEPTH + 0.1), gh / 2, 0), "cage")
	for zs: float in [-1.0, 1.0]:
		Arena.solid(self, Vector3(DEPTH, gh, 0.2), Vector3(cx, gh / 2, zs * (gw + 0.1)), "cage")
	Arena.solid(self, Vector3(DEPTH + 0.2, 0.2, 2 * gw + 0.4), Vector3(cx, gh + 0.1, 0), "cage")

	var steel := Color("2b2e36")
	for x: float in [sgn * L, sgn * (L + DEPTH)]:
		for zs: float in [-1.0, 1.0]:
			Arena.box(self, Vector3(0.12, gh, 0.12), Vector3(x, gh / 2, zs * gw), steel)
		Arena.box(self, Vector3(0.12, 0.12, 2 * gw + 0.12), Vector3(x, gh, 0), steel)
	Arena.box(self, Vector3(0.05, gh, 2 * gw), Vector3(sgn * (L + DEPTH + 0.25), gh / 2, 0), (game.TEAMS[s].color as Color).darkened(0.35))
	Arena.fence_panel(self, Vector3(sgn * (L + DEPTH), gh / 2, 0), Vector2(2 * gw, gh), Vector3(0, 90, 0))
	Arena.fence_panel(self, Vector3(cx, gh, 0), Vector2(DEPTH, 2 * gw), Vector3(-90, 0, 0))
	for zs: float in [-1.0, 1.0]:
		Arena.fence_panel(self, Vector3(cx, gh / 2, zs * gw), Vector2(DEPTH, gh), Vector3.ZERO)

	var sensor := Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = Arena.LAYER_BALL
	sensor.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(DEPTH - 0.35, gh, 2 * gw)
	cs.shape = sh
	sensor.position = Vector3(sgn * (L + 0.35 + (DEPTH - 0.35) / 2), gh / 2, 0)
	sensor.add_child(cs)
	add_child(sensor)
	sensor.body_entered.connect(func(b: Node3D) -> void:
		if b is Ball:
			game.on_goal(side))
	set_bricks(1)


func line_x() -> float:
	return sgn * Arena.L


func opening_half() -> float:
	return Arena.GOAL_HALF - inset - count * BRICK_W


func set_inset(w: float) -> void:
	inset = w
	for p in posts:
		p.queue_free()
	posts.clear()
	if w > 0.0:
		for zs: float in [-1.0, 1.0]:
			var sb := Arena.solid(self, Vector3(0.5, Arena.GOAL_H, w), Vector3(sgn * (Arena.L - 0.28), Arena.GOAL_H / 2, zs * (Arena.GOAL_HALF - w / 2)), "cage")
			Arena.box(sb, Vector3(0.5, Arena.GOAL_H, w), Vector3.ZERO, Color("2b2e36"))
			Arena.box(sb, Vector3(0.52, 0.12, w + 0.02), Vector3(0, Arena.GOAL_H / 2 - 0.25, 0), Color("ffd23f"))
			posts.append(sb)
	var n := count
	set_bricks(0)
	set_bricks(n)


func set_bricks(n: int, animate := false) -> void:
	if n < count:
		for c in columns:
			c.queue_free()
		columns.clear()
		count = 0
	while count < n:
		for zs: float in [-1.0, 1.0]:
			var col := _column(Vector3(sgn * (Arena.L - 0.28), Arena.GOAL_H / 2, zs * (Arena.GOAL_HALF - inset - BRICK_W * (count + 0.5))))
			columns.append(col)
			if animate:
				var rest := col.position.y
				col.position.y = 9.0
				col.create_tween().tween_property(col, "position:y", rest, 0.6) \
						.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		count += 1


func _column(pos: Vector3) -> StaticBody3D:
	var sb := Arena.solid(self, Vector3(0.5, Arena.GOAL_H, BRICK_W), pos, "brick")
	var rows := 5
	var bh := Arena.GOAL_H / rows
	for r in rows:
		var shade := Color("c0452f").lerp(Color("8e2f22"), randf())
		Arena.box(sb, Vector3(0.5 - randf() * 0.05, bh - 0.035, BRICK_W - 0.04),
				Vector3(randf_range(-0.02, 0.02), -Arena.GOAL_H / 2 + bh * (r + 0.5), 0), shade)
	return sb
