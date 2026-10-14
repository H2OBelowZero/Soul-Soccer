class_name Player
extends CharacterBody3D
## A street baller. Driven by the pad when `human`, otherwise by the simple role AI below.
## Moves on a borrowed body: Vessel stage multipliers when their team holds the ball's bond.

var game: Game
var team := 0
var st: Dictionary
var is_keeper := false
var ch: Dictionary          # cosmetic identity (UI.CHARS / UI.KEEPERS)
var sig := 0                # Soul Signature (Vessel.Kind) the ball steals when you beat this player
var beat_watch := {}        # opponent -> last time they were squarely in front of me (dribble-past check)
var human := false
var home := Vector3.ZERO
var lane := 0.0
var dir := 1.0              # +x for team 0 (attacks the +x goal)
var facing := Vector3.RIGHT
var mv := Vector3.ZERO      # controlled planar velocity
var knock := Vector3.ZERO   # shoulder/tackle knockback, decays
var sprinting := false

var stun_t := 0.0
var lunge_t := 0.0
var lunge_vel := Vector3.ZERO
var diving := false
var tackle_won := false
var tackle_cd := 0.0
var skill_t := 0.0          # tackle-immune window during skill moves
var skill_cd := 0.0
var dodge_t := 0.0          # dodging: tackles, shoulders and keeper shoves pass through
var dodge_cd := 0.0
var ai_dodge_for: Player    # attacker the AI already decided about, so it rolls once per hit
var spin_t := 0.0
var burst_t := 0.0
var shove_t := 0.0
var push_cd := 0.0          # keeper shove cooldown
var charging := false       # holding shoot: the charge itself lives on the ball

const CHARGE_T := 1.2       # seconds to a full charge
const DODGE_COST := 15.0    # ball charge a dodge burns
const DODGE_WINDOW := 0.22  # a dodge only lands if the hit would connect within this many seconds
const DODGE_T := 0.4        # untouchable time after a dodge

var think_t := 0.0
var ai_move := Vector3.ZERO
var ai_sprint := false
var seen_shot := -1.0
var react_at := 0.0
var will_dive := false

var received_t := -10.0
var last_pass_to: Player
var last_pass_t := -10.0
var combo_used := false
var buffered := ""
var buffered_t := -10.0

var rig: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var ring: MeshInstance3D
var arrow: MeshInstance3D
var step := 0.0


## idx: outfield slot 0..2 (centre, left, right); ignored for keepers.
func setup(g: Game, t: int, idx: int, keeper: bool) -> void:
	game = g
	team = t
	st = game.TEAMS[t]
	is_keeper = keeper
	sig = st.sigs[0 if keeper else idx + 1]
	ch = UI.KEEPERS[t] if keeper else UI.CHARS[game.picks[t][idx]]
	dir = 1.0 if t == 0 else -1.0
	name = "%s_%s" % [st.short, "GK" if keeper else str(idx + 1)]
	lane = 0.0 if keeper else [0.0, -3.5, 3.5][idx] * Arena.PITCH_K
	home = Vector3(-dir * (Arena.L - 1.0), 0, 0) if keeper else Vector3(-dir * (7.0 if idx == 0 else 5.0) * Arena.PITCH_K, 0, lane)
	collision_layer = Arena.LAYER_PLAYER
	collision_mask = Arena.LAYER_WORLD | Arena.LAYER_PLAYER
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_build_rig()


func _build_rig() -> void:
	rig = Node3D.new()
	add_child(rig)
	var shirt: Color = st.keeper if is_keeper else st.color
	var skin: Color = ch.skin
	for sx: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(sx * 0.14, 0.9, 0)
		rig.add_child(hip)
		legs.append(hip)
		var leg := CapsuleMesh.new()
		leg.radius = 0.11
		leg.height = 0.9
		Arena.mesh(hip, leg, Vector3(0, -0.45, 0), st.alt)
		var boot := BoxMesh.new()
		boot.size = Vector3(0.16, 0.1, 0.3)
		Arena.mesh(hip, boot, Vector3(0, -0.86, 0.06), Color("111111"))
		var sh := Node3D.new()
		sh.position = Vector3(sx * 0.38, 1.5, 0)
		rig.add_child(sh)
		arms.append(sh)
		var arm := CapsuleMesh.new()
		arm.radius = 0.08
		arm.height = 0.62
		Arena.mesh(sh, arm, Vector3(0, -0.28, 0), skin)
	var torso := CapsuleMesh.new()
	torso.radius = 0.3
	torso.height = 0.85
	Arena.mesh(rig, torso, Vector3(0, 1.28, 0), shirt)
	var head := SphereMesh.new()
	head.radius = 0.21
	head.height = 0.42
	Arena.mesh(rig, head, Vector3(0, 1.9, 0), skin)
	# Headband shows the Soul Signature, so you can see whose identity you're about to steal.
	var soul_col: Color = Vessel.KINDS[sig].color
	var band := TorusMesh.new()
	band.inner_radius = 0.19
	band.outer_radius = 0.24
	Arena.mesh(rig, band, Vector3(0, 1.97, 0), soul_col)
	var brim := BoxMesh.new()
	brim.size = Vector3(0.18, 0.05, 0.14)
	Arena.mesh(rig, brim, Vector3(0, 1.99, 0.2), soul_col)

	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("ffe100")
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.7
	ring = MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = glow
	ring.scale = Vector3(1, 0.1, 1)
	ring.position.y = 0.03
	ring.visible = false
	add_child(ring)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.4
	arrow = MeshInstance3D.new()
	arrow.mesh = cone
	arrow.material_override = glow
	arrow.position.y = 2.6
	arrow.visible = false
	add_child(arrow)


func set_human(on: bool) -> void:
	human = on
	ring.visible = on
	arrow.visible = on
	buffered_t = -10.0
	charging = false


## Input action for this player's pad: P1 uses the plain names, P2 the p2_ ones.
func _a(action: String) -> String:
	return action if game.human_team == team else "p2_" + action


func has_ball() -> bool:
	return game.ball.carrier == self


func reset_to(pos: Vector3) -> void:
	global_position = pos
	mv = Vector3.ZERO
	knock = Vector3.ZERO
	velocity = Vector3.ZERO
	stun_t = 0.0
	lunge_t = 0.0
	diving = false
	burst_t = 0.0
	skill_t = 0.0
	dodge_t = 0.0
	dodge_cd = 0.0
	spin_t = 0.0
	charging = false
	facing = Vector3(dir, 0, 0)


func on_receive(from: Player) -> void:
	received_t = game.t
	beat_watch.clear()
	if human and game.t - buffered_t < 0.4:  # one-touch: pass/shoot pressed just before the ball arrived
		buffered_t = -10.0
		var v := Input.get_vector(_a("move_left"), _a("move_right"), _a("move_up"), _a("move_down"))
		if buffered == "pass":
			do_pass(false, Vector3(v.x, 0, v.y))
		else:
			do_shoot(false, false, v.y)


# ------------------------------------------------------------------ movement

func _physics_process(delta: float) -> void:
	stun_t = maxf(stun_t - delta, 0.0)
	tackle_cd = maxf(tackle_cd - delta, 0.0)
	skill_t = maxf(skill_t - delta, 0.0)
	skill_cd = maxf(skill_cd - delta, 0.0)
	dodge_t = maxf(dodge_t - delta, 0.0)
	dodge_cd = maxf(dodge_cd - delta, 0.0)
	spin_t = maxf(spin_t - delta, 0.0)
	burst_t = maxf(burst_t - delta, 0.0)
	shove_t = maxf(shove_t - delta, 0.0)
	push_cd = maxf(push_cd - delta, 0.0)

	var move := Vector3.ZERO
	sprinting = false
	if game.state == Game.S.PLAY and stun_t <= 0.0 and lunge_t <= 0.0:
		if human:
			move = _human_input()
		else:
			_ai(delta)
			_ai_dodge()
			move = ai_move
			sprinting = ai_sprint

	if lunge_t > 0.0:
		lunge_t -= delta
		mv = lunge_vel
		if not diving:
			_check_tackle()
		if lunge_t <= 0.0:
			_end_lunge()
	else:
		var v := game.vessel
		var spd: float = (st.sprint if sprinting else st.speed) * v.boost(team, "speed")
		if v.perk(team) == Vessel.Kind.SPEED:
			spd *= 1.1
		if has_ball():
			spd *= 0.9
		spd *= _lvl().speed
		if burst_t > 0.0:
			spd *= 1.5
		mv = mv.move_toward(move.limit_length(1.0) * spd, 55.0 * v.boost(team, "accel") * delta)
		if move.length() > 0.15:
			var want := move.normalized()
			var turn := 16.0 * v.boost(team, "turn")
			facing = want if facing.dot(want) < -0.8 else facing.lerp(want, clampf(turn * delta, 0.0, 1.0)).normalized()
	if has_ball() and game.state == Game.S.PLAY:
		_check_beaten()
	if is_keeper and game.state == Game.S.PLAY:
		_keeper_push()

	knock = knock.move_toward(Vector3.ZERO, 25.0 * delta)
	velocity.x = mv.x + knock.x
	velocity.z = mv.z + knock.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 25.0 * delta
	move_and_slide()
	for i in get_slide_collision_count():
		var o := get_slide_collision(i).get_collider() as Player
		if o and o.team != team:
			_shoulder(o)


func _process(delta: float) -> void:
	var sp := Vector2(mv.x, mv.z).length()
	step += delta * sp * 1.7
	var swing := sin(step) * clampf(sp / 6.0, 0.0, 1.0) * 0.9
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing
	arms[0].rotation.x = -swing * 0.8
	arms[1].rotation.x = swing * 0.8
	rig.rotation = Vector3(clampf(sp / 12.0, 0.0, 0.35), atan2(facing.x, facing.z), 0)
	rig.position.y = absf(sin(step)) * 0.06
	if spin_t > 0.0:
		rig.rotation.y += TAU * (1.0 - spin_t / 0.45)
	if diving:
		rig.rotation.z = -signf(lunge_vel.z) * dir * 1.3
	elif lunge_t > 0.0:
		rig.rotation.x = 0.8
	elif stun_t > 0.0:
		rig.rotation.x = -0.6
	var celebrating := (game.state == Game.S.GOAL or game.state == Game.S.OVER) and team == game.last_scorer
	if celebrating:
		rig.position.y = absf(sin(game.t * 9.0 + lane)) * 0.5
		arms[0].rotation.x = -2.8
		arms[1].rotation.x = -2.8
	arrow.position.y = 2.6 + sin(game.t * 6.0) * 0.08
	if push_cd > 0.35:
		arms[0].rotation.x = -1.5
		arms[1].rotation.x = -1.5
	var ch := game.ball.charge if charging else 0.0
	ring.scale = Vector3(1.0 + ch * 0.8, 0.1, 1.0 + ch * 0.8)
	(ring.material_override as StandardMaterial3D).albedo_color = Color("ffe100").lerp(Color("ff3b30"), ch)


# ------------------------------------------------------------------ human

func _human_input() -> Vector3:
	var v := Input.get_vector(_a("move_left"), _a("move_right"), _a("move_up"), _a("move_down"))
	var move := Vector3(v.x, 0, v.y)
	sprinting = Input.is_action_pressed(_a("sprint"))
	var lb := Input.is_action_pressed(_a("ability"))
	if Input.is_action_just_pressed(_a("ability")):
		combo_used = false
		if not has_ball():
			try_burst()
	if has_ball():
		if charging:
			var b := game.ball
			var was := b.charge
			b.charge = minf(was + get_physics_process_delta_time() / CHARGE_T, 1.0)
			if was < 1.0 and b.charge >= 1.0:
				game.sfx.play("power")
		if Input.is_action_just_pressed(_a("pass")):
			combo_used = true
			do_pass(lb and game.spend(team, "VISION PASS!", Game.QUICK_COST), move)  # keeps the charge
		elif Input.is_action_just_pressed(_a("shoot")):
			combo_used = true
			charging = true
		elif charging and not Input.is_action_pressed(_a("shoot")):
			do_shoot(lb and game.soul_shot(team, "SOUL SHOT!"), false, move.z)
		elif Input.is_action_just_pressed(_a("skill")):
			combo_used = true
			if lb and game.soul_shot(team, "CURVE SHOT!"):
				do_shoot(false, true, move.z)
			elif not try_dodge():
				do_skill(move)
		elif Input.is_action_just_released(_a("ability")) and not combo_used:
			try_burst()
	else:
		# One button: shoot on offence (buffered, so the one-touch fires as the ball arrives), tackle on defence.
		if Input.is_action_just_pressed(_a("shoot")):
			if _offensive():
				buffered = "shoot"
				buffered_t = game.t
			else:
				do_tackle()
		if Input.is_action_just_pressed(_a("pass")):
			if _offensive():
				buffered = "pass"
				buffered_t = game.t
			else:
				_switch_player()
		if Input.is_action_just_pressed(_a("skill")):
			try_dodge()
		charging = false
	if charging:  # planted while winding up
		sprinting = false
		return Vector3.ZERO
	return move


# ------------------------------------------------------------------ actions

func do_pass(quick := false, hint := Vector3.ZERO) -> void:
	if not has_ball():
		return
	var aim := hint.normalized() if hint.length() > 0.2 else facing
	var best: Player = null
	var best_s := -INF
	for m: Player in game.team_players[team]:
		if m == self:
			continue
		var to := m.global_position - global_position
		to.y = 0.0
		var d := maxf(to.length(), 0.1)
		var s := aim.dot(to / d) * 2.0 - d * 0.05 - (0.8 if m.is_keeper else 0.0)
		if s > best_s:
			best_s = s
			best = m
	var b := game.ball
	var speed: float = st.pass_speed * (1.45 if quick else 1.0) * (1.0 + 0.6 * b.charge) * 1.3  # snappy, assisted passes
	var perk := game.vessel.perk(team)
	if perk == Vessel.Kind.SPEED or perk == Vessel.Kind.VISION:
		speed *= 1.15
	var target: Vector3
	if best:  # always at a teammate: the stick/facing only picks which one
		var lead := best.global_position.distance_to(global_position) / speed
		target = best.global_position + best.mv * lead * 0.8
	else:
		best = null  # no one there: play it into space (or off the wall)
		target = global_position + aim * 9.0
	var flat := target - b.global_position
	flat.y = 0.0
	var pdir := flat.normalized()
	var vel := pdir * speed + Vector3.UP * (0.6 + maxf(flat.length() - 11.0, 0.0) * 0.35)
	if facing.dot(pdir) < -0.3:
		game.steady(team, "HEEL PASS!", 1.5)
	if game.t - received_t < 0.45:
		game.steady(team, "ONE TOUCH!", 1.0)
	b.kick(self, vel, "pass", best, 0.0, false, quick)
	last_pass_to = best
	last_pass_t = game.t


func do_shoot(power := false, curve := false, aim_hint := 0.0) -> void:
	if not has_ball():
		return
	var b := game.ball
	var ch := _take_charge()
	if ch >= 1.0:
		power = true  # fully charged = power shot
	var g: Goal = game.goals[1 - team]
	var oh := g.opening_half()
	var aim_z: float
	if absf(aim_hint) > 0.25:
		aim_z = signf(aim_hint) * oh * 0.7
	else:
		var k := game.keeper(1 - team)
		var kz := k.global_position.z if k else 0.0
		aim_z = (-signf(kz) if absf(kz) > 0.15 else [-1.0, 1.0].pick_random()) * oh * 0.65
	var target := Vector3(g.line_x(), randf_range(0.35, 0.9), aim_z)
	var flat := target - b.global_position
	flat.y = 0.0
	var d := maxf(flat.length(), 4.0)
	var pressure := 0.0
	for o: Player in game.team_players[1 - team]:
		if not o.is_keeper and o.global_position.distance_to(global_position) < 1.8:
			pressure = 1.0
	var perk := game.vessel.perk(team)
	var spread: float = (0.1 + d * 0.035 + pressure * 0.5) * (1.0 - 0.65 * charge_assist()) * (0.5 if power else 1.0) * (0.5 if perk == Vessel.Kind.VISION else 1.0) * (1.0 - ch * (0.5 + 0.45 * clampf(1.0 - d / 18.0, 0.0, 1.0))) * _lvl().aim
	var attacking := global_position.x * dir > 0.0  # past the halfway line: aim assist, stays inside the posts
	target.z += randf_range(-spread, spread) * (0.25 if attacking else 1.0)
	if attacking or ch >= 0.5:
		target.z = clampf(target.z, -oh * 0.9, oh * 0.9)
	var to_goal := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if to_goal.length() > 0.01:
		facing = to_goal.normalized()  # snap to face the goal
	var speed: float = (35.0 if power else (22.0 if curve else 24.0)) * st.shot * game.vessel.boost(team, "shot") * (1.0 + 0.4 * ch)
	if perk == Vessel.Kind.POWER:
		speed *= 1.12
	var spin := 0.0
	if curve:
		# Aim outside the post and let the Magnus force bend it back in: offset c needs spin 2cv/d².
		var side := Vector3.UP.cross(flat.normalized())
		var c := 2.2 * signf(target.z if target.z != 0.0 else 1.0) * signf(side.z if side.z != 0.0 else 1.0)
		target += side * c
		spin = -2.0 * c * speed / (d * d)
	b.kick(self, Ball.ballistic(b.global_position, target, speed), "shot", null, spin, power)
	game.shake(0.55 if power else 0.3)
	game.comic("KAPOW!" if power else "POW!", b.global_position, st.alt, 1.2 if power else 0.9)
	if power and human:
		game.hud.speed_lines(0.6)


func do_tackle() -> void:
	if tackle_cd > 0.0 or has_ball() or stun_t > 0.0 or lunge_t > 0.0:
		return
	tackle_cd = 0.9
	var to_ball := game.ball.global_position - global_position
	to_ball.y = 0.0
	if to_ball.length() > 0.01:
		facing = to_ball.normalized()  # always lunge at the ball
	lunge_t = 0.28
	diving = false
	tackle_won = false
	lunge_vel = facing * 13.0
	game.sfx.play("lunge")


func _check_tackle() -> void:
	var b := game.ball
	var c := b.carrier
	var tip := global_position + facing * 0.5
	if c and c.is_keeper:
		return  # a keeper holding the ball can't be tackled
	if c and c.team != team:
		var reach: float = st.tackle_range * (0.7 if game.vessel.perk(c.team) == Vessel.Kind.GUARD else 1.0)
		if _flat(c.global_position - tip) < reach and c.skill_t <= 0.0 and c.dodge_t <= 0.0:
			tackle_won = true
			lunge_t = 0.0
			c.stun_t = 0.7
			c.knock = facing * 7.0
			b.give(self)
			game.feed(team, "TACKLE!", 12, c)
			game.comic(["BAM!", "WHAM!", "CRUNCH!"].pick_random(), c.global_position, st.color)
			game.burst(c.global_position + Vector3.UP, 20)
			game.hitstop()
			game.shake(0.45)
			game.sfx.play("bam")
	elif c == null and _flat(b.global_position - tip) < 0.9 and b.global_position.y < 1.0:
		tackle_won = true
		lunge_t = 0.0
		b.receive(self)


func _end_lunge() -> void:
	if diving:
		diving = false
		stun_t = 0.45
		return
	if not tackle_won:
		stun_t = 0.55  # whiffed: vulnerable
		var c := game.ball.carrier
		if c and c.team != team and _flat(c.global_position - global_position) < 3.0:
			game.feed(c.team, "SKINNED!", 8, self)
		game.comic("WHIFF!", global_position, Color.WHITE, 0.6)


## Skill is extraction: each move only feeds the ball if it beats somebody.
## Rainbow flick and the roulette burst need the ball awake (STIRRING) — the leg isn't there yet.
func do_skill(move: Vector3) -> void:
	if not has_ball() or skill_cd > 0.0:
		return
	var amp := 1.0 + game.ball.charge  # a charged skill hits up to twice as hard
	charging = false
	# Risk decides the charge: dodging a tackle that's coming in gains some, a skill in open space loses some.
	var dodge := false
	for o: Player in game.team_players[1 - team]:
		if o.lunge_t > 0.0 and not o.diving and _flat(o.global_position - global_position) < 3.5:
			dodge = true
	var charge_delta := 0.4 if dodge else (0.0 if _nearest_opponent(3.0) else -0.3)
	var trick := game.vessel.perk(team) == Vessel.Kind.TRICK
	var awake := game.vessel.stage() >= Vessel.Stage.STIRRING
	skill_cd = 0.35 if trick else 0.7
	var immune := (1.5 if trick else 1.0) * amp
	var b := game.ball
	var def := _opponent_ahead(2.4)
	var near := _nearest_opponent(3.0)
	if def:
		# Nutmeg: ball through the legs, go round him.
		b.kick(self, facing * 8.5 * amp + Vector3.UP * 0.4, "flick", self)
		b.add_collision_exception_with(def)
		add_collision_exception_with(def)
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			b.remove_collision_exception_with(def)
			remove_collision_exception_with(def))
		b.no_pickup[def] = game.t + 0.9
		def.stun_t = maxf(def.stun_t, 0.4 * amp)
		skill_t = 0.6 * immune
		knock = facing.cross(Vector3.UP) * 4.0 * amp * [-1.0, 1.0].pick_random()
		game.feed(team, "NUTMEG!", 18 * amp, def)
		game.comic("NUTMEG!", def.global_position, Color("ff2d95"))
	elif sprinting and awake:
		b.kick(self, facing * 7.0 * amp + Vector3.UP * 7.0 * amp, "flick", self)
		b.no_pickup[self] = game.t + 0.5
		skill_t = 0.7 * immune
		game.feed(team, "RAINBOW FLICK!", (10 if near else 0) * amp, near)
		game.comic("RAINBOW!", global_position, Color("7cff3a"))
	elif move.length() < 0.2:
		var bitten: Player = null
		for o: Player in game.team_players[1 - team]:
			if not o.human and _flat(o.global_position - global_position) < 5.0 * amp:
				o.stun_t = maxf(o.stun_t, 0.5 * amp)  # they bite
				bitten = o
		game.feed(team, "FAKE SHOT!", (8 if bitten else 0) * amp, bitten)
		game.comic("FAKE!", global_position, Color("00e5ff"))
	else:
		spin_t = 0.45
		skill_t = 0.5 * immune
		if awake:
			burst_t = maxf(burst_t, 0.35 * amp)
		game.feed(team, "ROULETTE!", (8 if near else 0) * amp, near)
	game.ball.charge = clampf(game.ball.charge + charge_delta, 0.0, 1.0)  # after any kick, which would reset it
	if dodge:
		game.comic("DODGED!", global_position, Color("ffe100"), 0.9)
	game.sfx.play("skill")


## Well-timed dodge, for anyone (keepers included) against anyone: press as a tackle, shoulder charge or
## keeper shove is about to land. Burns ball charge; a mistimed press does nothing and costs half a second.
func try_dodge() -> bool:
	if dodge_cd > 0.0 or stun_t > 0.0 or lunge_t > 0.0 or game.state != Game.S.PLAY:
		return false
	var o := _incoming_hit()
	if o == null:
		dodge_cd = 0.5
		return false
	if not game.vessel.spend(DODGE_COST):
		if human:
			game.hud.popup(team, "NO CHARGE TO DODGE")
		return false
	dodge_t = DODGE_T
	dodge_cd = 0.9
	var away := global_position - o.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -facing
	var side := Vector3.UP.cross(away)   # sidestep across the attacker's line, towards the middle of the pitch
	if absf(global_position.z) > 3.0:
		if side.z * global_position.z > 0.0:
			side = -side
	elif randf() < 0.5:
		side = -side
	knock = side * 9.0
	game.comic("DODGED!", global_position, Color("ffe100"), 0.9)
	game.burst(global_position + Vector3.UP, 12)
	game.sfx.play("skill")
	if team == game.vessel.bond:
		game.feed(team, "PERFECT DODGE!", 8, o)
	return true


## The opponent whose hit on me lands soonest, if it lands within DODGE_WINDOW: a lunge at the ball carrier,
## a shoulder charge, or a keeper about to shove me.
func _incoming_hit() -> Player:
	var best: Player = null
	var best_ttc := DODGE_WINDOW
	for o: Player in game.team_players[1 - team]:
		if o.stun_t > 0.0 or o.diving:
			continue
		var to := global_position - o.global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.01:
			continue
		var away := to / d
		var closing := (o.mv - mv).dot(away)
		var reach := 0.8   # shoulder: bodies touching
		if o.lunge_t > 0.0:
			if not has_ball() or is_keeper or closing < 1.0 or o.facing.dot(away) < 0.5:
				continue
			reach = o.st.tackle_range + 0.5
		elif o.is_keeper:
			reach = o._push_reach()
			if reach <= 0.0 or o.push_cd > 0.0 or closing < 1.0:
				continue
		elif closing < 3.0 or o.facing.dot(away) < 0.5:
			continue
		var ttc := maxf(d - reach, 0.0) / closing
		if ttc < best_ttc:
			best_ttc = ttc
			best = o
	return best


## The AI reads the hit too, with a reaction that gets worse the slower its difficulty thinks.
func _ai_dodge() -> void:
	var o := _incoming_hit()
	if o == null:
		ai_dodge_for = null
	elif o != ai_dodge_for:
		ai_dodge_for = o
		if randf() < minf(0.6 / _lvl().think, 1.0):
			try_dodge()


func try_burst() -> void:
	if burst_t <= 0.0 and game.spend(team, "BURST SPRINT!", Game.BURST_COST):
		burst_t = 1.3
		if human:
			game.hud.speed_lines(1.3)


func _shoulder(o: Player) -> void:
	if shove_t > 0.0:
		return
	shove_t = 0.4
	if o.dodge_t > 0.0:
		return
	var d := o.global_position - global_position
	d.y = 0.0
	d = d.normalized()
	var mine: float = st.strength * (1.25 if game.vessel.perk(team) == Vessel.Kind.POWER else 1.0)
	var theirs: float = o.st.strength * (1.25 if game.vessel.perk(o.team) == Vessel.Kind.GUARD else 1.0)
	var force: float = (2.0 + mv.length() * 0.5) * mine / theirs
	o.knock += d * force
	knock -= d * force * 0.25
	if o.has_ball() and not o.is_keeper and sprinting and o.skill_t <= 0.0 and mine * randf_range(0.7, 1.3) > theirs:
		var b := game.ball
		b.kick(o, d * 3.0 + mv * 0.4 + Vector3.UP * 2.0, "loose")
		b.no_pickup[o] = game.t + 0.6
		o.stun_t = maxf(o.stun_t, 0.35)
		game.feed(team, "SHOULDER!", 8, o)
		game.comic("WHAM!", o.global_position, st.color)
		game.shake(0.3)
		game.sfx.play("bam")


# ------------------------------------------------------------------ AI

func _ai(delta: float) -> void:
	if is_keeper:
		_ai_keeper()
		return
	var b := game.ball
	if b.carrier == null and b.kick_type == "pass" and b.pass_target == self and game.t - b.kick_t < 2.0:
		# A pass is coming to me: run onto the ball at once (no think delay) and take it in stride.
		var aim := b.global_position + b.linear_velocity * 0.3
		aim.y = 0.0
		ai_move = _seek(aim, 0.0)
		ai_sprint = true
		return
	think_t -= delta
	if think_t > 0.0:
		return
	var lv := _lvl()
	think_t = randf_range(0.1, 0.2) * lv.think
	var c := b.carrier
	var bp := Vector3(b.global_position.x, 0, b.global_position.z)
	ai_sprint = false
	if c == self:
		_ai_attack()
		return
	if game.last_man(team) == self:
		# 3v3, no keeper: hang back and stand between the ball and our goal mouth.
		var gx := game.goals[team].line_x()
		var deep := 2.2 if c == null or c.team != team else 9.0
		var tgt0 := Vector3(gx + dir * deep, 0, clampf(bp.z * 0.35, -1.6, 1.6))
		ai_move = _seek(tgt0, 0.2)
		ai_sprint = _flat(tgt0 - global_position) > 3.0
		if c and c.team != team and _flat(c.global_position - global_position) < st.tackle_range + 0.6 \
				and tackle_cd <= 0.0 and randf() < 0.4 * lv.tackle:
			var to0 := c.global_position - global_position
			to0.y = 0.0
			facing = to0.normalized()
			do_tackle()
		return
	if c and c.team == team:
		# Support run: ahead of the carrier, holding a lane.
		var tgt := Vector3(clampf(c.global_position.x + dir * 5.5, -Arena.L + 2.0, Arena.L - 2.5), 0,
				lane * 1.4 + sin(game.t * 0.7 + lane) * 1.5)
		ai_move = _seek(tgt)
		ai_sprint = _flat(tgt - global_position) > 4.0
		return
	if game.chaser(team) == self and not _holds_off():
		var aim := bp + b.linear_velocity * 0.3 if c == null else c.global_position + c.facing * 0.7
		aim.y = 0.0
		ai_move = _seek(aim, 0.0)
		ai_sprint = true
		if c and c.team != team:
			var d := _flat(c.global_position - global_position)
			if d < st.tackle_range + 0.8 and tackle_cd <= 0.0 and randf() < 0.35 * lv.tackle:
				var to := c.global_position - global_position
				to.y = 0.0
				facing = to.normalized()
				do_tackle()
		elif c == null and game.vessel.bond == team and game.vessel.charge > 50.0 and randf() < 0.05:
			try_burst()
		return
	# Goal-side shape.
	var tgt := Vector3(game.goals[team].line_x(), 0, 0).lerp(bp, 0.55) + Vector3(0, 0, lane * 0.8)
	ai_move = _seek(tgt)
	ai_sprint = _flat(tgt - global_position) > 5.0


func _ai_attack() -> void:
	var g: Goal = game.goals[1 - team]
	var to_goal := Vector3(g.line_x(), 0, 0) - global_position
	to_goal.y = 0.0
	var dg := to_goal.length()
	var threat := _opponent_ahead(2.6)
	var held := game.t - received_t
	if held < 0.3 and randf() < 0.1:
		do_pass()  # one-touch flair
		return
	var v := game.vessel
	var s := v.stage()
	# An overloaded ball wants cashing out — from further out, before someone takes it.
	var range_ := 15.0 if s == Vessel.Stage.OVERLOADED else 12.0
	if dg < range_ and (dg < 7.5 or randf() < (0.6 if s == Vessel.Stage.OVERLOADED else 0.25)):
		if s >= Vessel.Stage.POSSESSED and randf() < 0.6:
			if randf() < 0.6:
				if game.soul_shot(team, "SOUL SHOT!"):
					do_shoot(true)
					return
			elif game.soul_shot(team, "CURVE SHOT!"):
				do_shoot(false, true)
				return
		do_shoot()
		return
	if threat:
		var r := randf()
		var greed := 0.45 if v.is_hungry(game.t) else 0.25  # hungry ball: take him on, feed it
		if r < greed and skill_cd <= 0.0:
			do_skill(ai_move)
			return
		if r < 0.7:
			do_pass()
			return
	elif held > 2.5 and randf() < 0.2:
		do_pass()
		return
	var steer := to_goal.normalized()
	if threat:
		var away := global_position - threat.global_position
		away.y = 0.0
		steer = (steer + away.normalized() * 1.2).normalized()
	steer.z += sin(game.t * 1.5 + lane) * 0.35
	ai_move = steer.normalized()
	ai_sprint = threat == null


func _ai_keeper() -> void:
	var b := game.ball
	var c := b.carrier
	var g: Goal = game.goals[team]
	var gx := g.line_x()
	var bp := b.global_position
	ai_sprint = false
	if c == self:
		ai_move = Vector3.ZERO
		if game.t - received_t > 0.8:
			facing = Vector3(dir, 0, 0)
			do_pass()
		return
	if c == null and b.kick_type == "shot" and b.last_touch and b.last_touch.team != team:
		if b.kick_t != seen_shot:
			seen_shot = b.kick_t
			react_at = b.kick_t + randf_range(0.06, 0.22) * _lvl().react
			will_dive = randf() < 0.85 * _lvl().dive
		var v := b.linear_velocity
		if will_dive and game.t >= react_at and v.x * dir < -3.0:
			var tt := (global_position.x - bp.x) / v.x
			if tt > 0.0 and tt < 0.4:
				var dz := bp.z + v.z * tt - global_position.z
				if absf(dz) > 0.45 and absf(dz) < 2.6:
					will_dive = false
					diving = true
					lunge_t = 0.32
					lunge_vel = Vector3(0, 0, signf(dz) * minf(absf(dz) / 0.3, 9.0))
					game.sfx.play("lunge")
					return
	var oh := maxf(g.opening_half() - 0.25, 0.0)
	var tgt := Vector3(gx + dir * 1.0, 0, clampf(bp.z * 0.45, -oh, oh))
	if c == null and _flat(bp - Vector3(gx, 0, 0)) < 5.0 and b.linear_velocity.length() < 9.0 and bp.y < 1.0:
		tgt = Vector3(bp.x, 0, bp.z)  # sweep up loose balls in the box
		ai_sprint = true
	ai_move = _seek(tgt, 0.15)


# ------------------------------------------------------------------ helpers

## How far the keeper's shove reaches right now (0 = not shoving).
func _push_reach() -> float:
	if has_ball():
		return 3.0
	return 2.0 if absf(global_position.x - game.goals[team].line_x()) < 5.0 else 0.0


## The keeper knocks rivals away while he holds the ball, and from the goalmouth whenever they crowd him.
func _keeper_push() -> void:
	if push_cd > 0.0:
		return
	var reach := _push_reach()
	var near: Player = null
	var nd := reach
	for o: Player in game.team_players[1 - team]:
		var l := _flat(o.global_position - global_position)
		if l > 0.01 and l < reach and o.dodge_t <= 0.0:
			var d := o.global_position - global_position
			d.y = 0.0
			o.knock = d.normalized() * 12.0
			o.stun_t = maxf(o.stun_t, 0.3)
			if l < nd:
				nd = l
				near = o
	if near:
		push_cd = 0.6
		facing = (near.global_position - global_position).normalized()
		game.comic("SHOVE!", near.global_position, st.color, 0.9)
		game.shake(0.25)
		game.sfx.play("bam")


## Spend the ball's shot charge (0..1) and stop winding up.
func _take_charge() -> float:
	var c := game.ball.charge
	game.ball.charge = 0.0
	charging = false
	return c



## Dribble-past: an opponent squarely in front, then behind within a second, while I keep the ball.
func _check_beaten() -> void:
	for o: Player in game.team_players[1 - team]:
		var to := o.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > 2.6 or d < 0.01:
			continue
		var dot := facing.dot(to / d)
		if dot > 0.35:
			beat_watch[o] = game.t
		elif dot < -0.3 and game.t - beat_watch.get(o, -10.0) < 1.0:
			beat_watch.erase(o)
			game.feed(team, "ROUNDED THE KEEPER!" if o.is_keeper else "BEAT HIM!", 14 if o.is_keeper else 10, o)
			game.comic("SKIP!", o.global_position, Vessel.KINDS[o.sig].color, 0.8)


func _nearest_opponent(r: float) -> Player:
	var best: Player = null
	for o: Player in game.team_players[1 - team]:
		var d := _flat(o.global_position - global_position)
		if d < r:
			r = d
			best = o
	return best


func _opponent_ahead(r: float) -> Player:
	for o: Player in game.team_players[1 - team]:
		var to := o.global_position - global_position
		to.y = 0.0
		if to.length() < r and facing.dot(to.normalized()) > 0.55:
			return o
	return null


func _seek(tgt: Vector3, dead := 0.3) -> Vector3:
	var d := tgt - global_position
	d.y = 0.0
	var l := d.length()
	if l < dead:
		return Vector3.ZERO
	return d / l * clampf(l / 1.2, 0.0, 1.0)


## 0..1: how much the ball's charge helps my team (only the team the ball serves). Tightens shots and widens
## the catch on passes, and ignores the score and the bricks, so scoring and passing feed each other.
func charge_assist() -> float:
	return game.vessel.momentum() if game.vessel.bond == team else 0.0


## Opposition doesn't sprint at a ball the instant it's passed or shot: it waits a beat (none on HARD, and none
## in the last LATE_T seconds or golden goal). Never applies to the human's side.
func _holds_off() -> bool:
	var b := game.ball
	if b.carrier or game.is_human(team) or game.golden or game.clock < Game.LATE_T:
		return false
	return (b.kick_type == "pass" or b.kick_type == "shot") and game.t - b.kick_t < _lvl().chase


## AI knobs for the chosen difficulty; the human's side and local 2P stay at NORMAL.
func _lvl() -> Dictionary:
	if human or game.two_player or team == game.human_team:
		return Game.DIFFS[1]
	return Game.DIFFS[game.difficulty]


## Defending: take over the teammate nearest the ball.
func _switch_player() -> void:
	if game.t - game.switch_t < 0.25:
		return
	var best: Player = null
	var bd := INF
	for m: Player in game.team_players[team]:
		if m == self or m.is_keeper:
			continue
		var d := m.global_position.distance_to(game.ball.global_position)
		if d < bd:
			bd = d
			best = m
	if best:
		game.switch_t = game.t
		game.set_controlled(best)
		game.sfx.play("ui")


## My side has the ball (or it's a pass on its way to me): nothing to tackle.
func _offensive() -> bool:
	var b := game.ball
	if b.carrier:
		return b.carrier.team == team
	return b.pass_target != null and b.pass_target.team == team and game.t - b.kick_t < 1.5   # my pass is in the air


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
