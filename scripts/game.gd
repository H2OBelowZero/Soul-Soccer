class_name Game
extends Node3D
## PFL 1 Pal Street Soccer: match flow, brick progression, the soul ball, camera and juice.
## Everything is built from code at startup; main.tscn only holds this node.

enum S { TITLE, KICKOFF, PLAY, GOAL, OVER }

const WIN_BRICKS := 4
const MATCH_TIME := 180.0
const STREET_TIMES := [120.0, 180.0, 240.0, 300.0]   # STREET mode: the player picks one
const BANK_KEEP := 0.5          # share of the ball's charge a goal banks for the scorer
const BURST_COST := 12.0
const QUICK_COST := 8.0
const SOUL_SHOT_COST := 25.0    # free when OVERLOADED: that shot is the cash-out
const PASS_CHARGE := 6.0        # ball charge gained for every second pass in a row
const SMALL_GOAL_INSET := 0.35  # 3v3 has no keepers, so each post is moved in this far
## AI knobs per difficulty (opponents only). speed: run speed · think: seconds between decisions ·
## tackle: tackle eagerness · dive: keeper dive chance · react: keeper reaction time · aim: shot inaccuracy ·
## chase: seconds an opponent waits before running at a ball that was just passed or shot.
const DIFFS := [
	{"name": "EASY", "speed": 0.85, "think": 1.6, "tackle": 0.6, "dive": 0.55, "react": 1.6, "aim": 1.8, "chase": 1.2},
	{"name": "NORMAL", "speed": 1.0, "think": 1.0, "tackle": 1.0, "dive": 1.0, "react": 1.0, "aim": 1.0, "chase": 0.8},
	{"name": "HARD", "speed": 1.08, "think": 0.6, "tackle": 1.4, "dive": 1.15, "react": 0.5, "aim": 0.6, "chase": 0.0},
]
const LATE_T := 30.0            # seconds left (and golden goal): opponents stop holding off the ball

## Soul Signature per slot: [keeper, centre, left, right]. Beat that player and the ball takes it.
var TEAMS := [
	{"name": "JOZI FLAMES", "short": "FLM", "blurb": "FAST  ·  TECHNICAL  ·  FLAIR\nFeeds the ball quickly — physically weaker",
		"color": Color("ff5a1f"), "alt": Color("ffd23f"), "keeper": Color("2de2e6"),
		"speed": 7.2, "sprint": 10.0, "strength": 0.85, "shot": 1.0, "tackle_range": 1.0, "pass_speed": 17.0, "feed": 1.25,
		"sigs": [Vessel.Kind.GUARD, Vessel.Kind.TRICK, Vessel.Kind.SPEED, Vessel.Kind.VISION]},
	{"name": "KASI KINGS", "short": "KNG", "blurb": "PHYSICAL  ·  STRONG TACKLES  ·  POWER SHOTS\nWins duels — slower ball movement",
		"color": Color("7b2ff7"), "alt": Color("ffc300"), "keeper": Color("39ff14"),
		"speed": 6.5, "sprint": 9.0, "strength": 1.3, "shot": 1.18, "tackle_range": 1.4, "pass_speed": 14.0, "feed": 1.0,
		"sigs": [Vessel.Kind.GUARD, Vessel.Kind.POWER, Vessel.Kind.GUARD, Vessel.Kind.SPEED]},
]

var state := S.TITLE
var t := 0.0
var format := 4                 # 4 = 4v4 (3 + keeper, default), 3 = 3v3 (no keeper, smaller goal)
var bricks := [1, 1]            # bricks on each team's own goal
var vessel := Vessel.new()      # the ball's souls
var was_hungry := false
var pass_chain := [0, 0]
var clock := MATCH_TIME
var golden := false             # sudden death: the next goal wins, whatever the bricks / score
var street := false             # STREET mode: timed, goals counted, the goal never shrinks. Off = BRICKS mode.
var street_time := 180.0        # chosen match length in STREET mode (STREET_TIMES)
var score := [0, 0]             # goals, STREET mode
var human_team := 0             # P1's team
var two_player := false         # local 2P: the other team is P2
var difficulty := 1             # index into DIFFS
var picks := [[0, 1, 2], [3, 4, 5]]   # per team: UI.CHARS indices for the three outfield slots (cosmetic look only)
var switch_t := -10.0           # last manual player switch (stops one press switching twice)
var possession := -1
var last_scorer := -1
var slowmo := false
var match_id := 0               # invalidates pending awaits on restart

var controlled: Array[Player] = [null, null]   # per team
var players: Array[Player] = []
var team_players := [[], []]
var goals: Array[Goal] = []
var ball: Ball
var hud: Hud
var menu: Menu
var sfx: Sfx
var cam: Camera3D
var focus := Vector3.ZERO
var trauma := 0.0
var excite := 0.1
var crowd_mat: ShaderMaterial


func _ready() -> void:
	randomize()
	crowd_mat = Arena.build(self)
	for side in 2:
		var g := Goal.new()
		add_child(g)
		g.setup(self, side)
		goals.append(g)
	ball = Ball.new()
	ball.game = self
	add_child(ball)
	set_format(format)
	cam = Camera3D.new()
	cam.fov = 44.0
	add_child(cam)
	cam.make_current()
	_add_post_process()
	sfx = Sfx.new()
	add_child(sfx)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	menu = Menu.new()
	menu.game = self
	add_child(menu)
	_setup_inputs()
	_place_for_kickoff(0)
	hud.show_title()
	menu.show_main()


func has_keeper() -> bool:
	return format == 4


## 4v4: three outfield + a keeper each. 3v3: three outfield, no keepers, posts moved in.
func set_format(n: int) -> void:
	format = n
	controlled = [null, null]
	ball.reset_to_center()   # drop refs to the players about to be freed
	for p in players:
		remove_child(p)  # frees the names for the new roster
		p.queue_free()
	players.clear()
	team_players = [[], []]
	for team in 2:
		if has_keeper():
			_add_player(team, 0, true)
		for i in 3:
			_add_player(team, i, false)
	for g in goals:
		g.set_inset(0.0 if has_keeper() else SMALL_GOAL_INSET)


func _add_player(team: int, idx: int, is_gk: bool) -> void:
	var p := Player.new()
	add_child(p)
	p.setup(self, team, idx, is_gk)
	players.append(p)
	team_players[team].append(p)


func _add_post_process() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/post.gdshader")
	m.render_priority = -128   # first in the transparent pass: it paints over everything drawn before it, so transparent things must come after
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -1)
	cam.add_child(mi)


# ------------------------------------------------------------------ flow

func _process(delta: float) -> void:
	t += delta
	excite = move_toward(excite, 0.1, delta * 0.25)
	crowd_mat.set_shader_parameter("excite", excite)
	sfx.set_excite(excite)
	match state:
		S.PLAY:
			_play(delta)
		S.OVER:
			if Input.is_action_just_pressed("start") or Input.is_action_just_pressed("pass"):
				to_title()
	_camera(delta)
	hud.refresh()


func to_title() -> void:
	match_id += 1
	sfx.hush()
	Engine.time_scale = 1.0
	state = S.TITLE
	last_scorer = -1
	_release_all()
	_place_for_kickoff(0)
	hud.show_title()
	menu.show_main()


func start_match(two := false) -> void:
	two_player = two
	_bind_inputs()
	match_id += 1
	sfx.hush()
	bricks = [1, 1]
	score = [0, 0]
	pass_chain = [0, 0]
	clock = street_time if street else MATCH_TIME
	golden = false
	last_scorer = -1
	Engine.time_scale = 1.0
	vessel.clear_bank()
	for g in goals:
		g.set_bricks(0 if street else 1)
	hud.hide_title()
	kickoff(randi() % 2)


func kickoff(team: int) -> void:
	var id := match_id
	state = S.KICKOFF
	vessel.reset(team, t)
	was_hungry = false
	_place_for_kickoff(team)
	_auto_switch(true)
	hud.banner("READY?", Color.WHITE, 0.8)
	await get_tree().create_timer(1.1, false).timeout
	if id != match_id:
		return
	state = S.PLAY
	hud.banner("AZISHE!", TEAMS[team].alt, 0.5)
	sfx.play("whistle")


func _place_for_kickoff(team: int) -> void:
	for p in players:
		var pos := p.home
		if p.team == team and not p.is_keeper:
			pos = Vector3(-p.dir * 0.7, 0, 0) if p == kicker(team) else Vector3(-p.dir * 3.0, 0, p.lane * 1.2)
		p.reset_to(pos)
	ball.give(kicker(team))


func _play(delta: float) -> void:
	if not golden:
		clock -= delta
		if clock <= 0.0:
			clock = 0.0
			var lead := _leader()
			if lead >= 0:
				end_match(lead)
				return
			golden = true
			hud.banner("GOLDEN GOAL!", Color("ffd23f"), 1.5, "NEXT GOAL WINS")
			sfx.play("whistle")
	vessel.tick(delta, t)
	var hungry := vessel.is_hungry(t)
	if hungry and not was_hungry:
		hud.popup(vessel.bond, "THE BALL IS HUNGRY — FEED IT")
	was_hungry = hungry
	_auto_switch()
	_match_point_slowmo()


## The team ahead when the clock runs out, or -1 for level. BRICKS: fewer bricks wins. STREET: more goals wins.
func _leader() -> int:
	if street:
		return -1 if score[0] == score[1] else (0 if score[0] > score[1] else 1)
	return -1 if bricks[0] == bricks[1] else (0 if bricks[0] < bricks[1] else 1)


## Would a goal in `side`'s net end the match? Sudden death always does; BRICKS also at the last brick.
func _is_decider(side: int) -> bool:
	return golden or (not street and bricks[side] == WIN_BRICKS - 1)


## BRICKS: every goal puts +1 brick on the conceding goal (+2 for an OVERLOADED ball), shrinking it; reach WIN_BRICKS
## and it's over. STREET: every goal is +1 to the score and the goal never changes. In either mode a goal in
## sudden death (golden) ends the match outright, whatever the bricks / score. A goal cashes the ball out, but
## half of the scorer's charge is banked for them (see Vessel.bank).
func on_goal(side: int) -> void:
	if state != S.PLAY:
		return
	var id := match_id
	var scorer := 1 - side
	var team: Dictionary = TEAMS[scorer]
	last_scorer = scorer
	state = S.GOAL
	slowmo = false
	var soul_goal := vessel.bond == scorer and vessel.stage() == Vessel.Stage.OVERLOADED
	var add := 2 if soul_goal and not street else 1
	if street:
		score[scorer] += 1
	else:
		bricks[side] = mini(bricks[side] + add, WIN_BRICKS)
	var win: bool = golden or (not street and bricks[side] >= WIN_BRICKS)
	excite = 1.0
	shake(1.0)
	sfx.play("net")
	sfx.play("whistle")
	sfx.play("cheer")
	sfx.play("goal", -6.0)
	var fx := fx_color(team.color)   # the cash-out below resets the ball, so read its colour first
	burst(ball.global_position, 110)
	comic("GOAL!", ball.global_position, fx, 2.0)
	hud.goal_flash(fx)
	var own := ball.last_touch != null and ball.last_touch.team == side
	hud.banner("SOUL GOAL!" if soul_goal else "GOAL!", team.alt, 1.8,
			("OWN GOAL — " if own else "") + String(team.name) + (("  ·  BALL CASHED OUT" + ("" if street else "  ·  +2 BRICKS")) if soul_goal else ""))
	if soul_goal:
		burst(ball.global_position, 90, true)
		sfx.play("soul_big")
	if vessel.bond == scorer:
		vessel.bank(scorer, BANK_KEEP)
	vessel.reset(side, t)
	Engine.time_scale = 0.12 if win else 0.35
	await get_tree().create_timer(2.4 if win else 1.0, false, false, true).timeout
	if id != match_id:
		return
	Engine.time_scale = 1.0
	if not street:
		goals[side].set_bricks(bricks[side], true)
		hud.popup(side, "+%d BRICK%s  —  GOAL SHRINKS" % [add, "S" if add > 1 else ""], true)
		await get_tree().create_timer(0.55, false).timeout
		if id != match_id:
			return
		shake(0.6)
		sfx.play("clunk")
		comic("CLUNK!", Vector3(goals[side].line_x(), 0.5, 0), Color("ff7a5c"), 1.4)
		await get_tree().create_timer(1.4, false).timeout
		if id != match_id:
			return
	if win:
		end_match(scorer)
		return
	if not street and bricks[side] == WIN_BRICKS - 1:
		hud.banner("MATCH POINT", Color("ff3b30"), 0.8, String(TEAMS[scorer].name))
	kickoff(side)


func end_match(winner: int) -> void:
	state = S.OVER
	last_scorer = winner
	excite = 1.0
	Engine.time_scale = 1.0
	sfx.play("roar")
	sfx.play("whistle")
	_release_all()
	hud.show_winner(winner)


# ------------------------------------------------------------------ local multiplayer inputs

var _arrow_events := {}     # action -> arrow InputEventKey pulled off P1 in 2P mode


## One-time: P2 actions (arrows + right-hand keys, gamepad 2) and left-hand alternates for P1.
func _setup_inputs() -> void:
	var p2 := {"move_left": KEY_LEFT, "move_right": KEY_RIGHT, "move_up": KEY_UP, "move_down": KEY_DOWN,
			"pass": KEY_COMMA, "shoot": KEY_PERIOD, "tackle": KEY_SLASH, "skill": KEY_SEMICOLON,
			"sprint": KEY_SHIFT, "ability": KEY_APOSTROPHE}
	var pad := {"pass": JOY_BUTTON_A, "shoot": JOY_BUTTON_B, "tackle": JOY_BUTTON_X, "skill": JOY_BUTTON_Y,
			"ability": JOY_BUTTON_LEFT_SHOULDER}
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
			"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0], "sprint": [JOY_AXIS_TRIGGER_RIGHT, 1.0]}
	for a: String in p2:
		var n := "p2_" + a
		if not InputMap.has_action(n):
			InputMap.add_action(n, 0.2)
		var k := InputEventKey.new()
		k.device = -1
		k.physical_keycode = p2[a]
		if a == "sprint":
			k.location = KEY_LOCATION_RIGHT
		InputMap.action_add_event(n, k)
		if pad.has(a):
			var b := InputEventJoypadButton.new()
			b.device = 1
			b.button_index = pad[a]
			InputMap.action_add_event(n, b)
		if axes.has(a):
			var m := InputEventJoypadMotion.new()
			m.device = 1
			m.axis = axes[a][0]
			m.axis_value = axes[a][1]
			InputMap.action_add_event(n, m)
	# P1 left-hand alternates so two people fit on one keyboard.
	for a: String in ["pass", "shoot", "tackle", "skill"]:
		var k := InputEventKey.new()
		k.device = -1
		k.physical_keycode = {"pass": KEY_F, "shoot": KEY_G, "tackle": KEY_H, "skill": KEY_T}[a]
		InputMap.action_add_event(a, k)


## 2P: arrows belong to P2 (and P1 sprint is Left Shift only). 1P: P1 gets them back.
func _bind_inputs() -> void:
	for a: String in ["move_left", "move_right", "move_up", "move_down"]:
		if two_player:
			for e in InputMap.action_get_events(a):
				if e is InputEventKey and e.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
					_arrow_events[a] = e
					InputMap.action_erase_event(a, e)
		elif _arrow_events.has(a):
			InputMap.action_add_event(a, _arrow_events[a])
			_arrow_events.erase(a)
	for e in InputMap.action_get_events("sprint"):
		if e is InputEventKey:
			e.location = KEY_LOCATION_LEFT if two_player else KEY_LOCATION_UNSPECIFIED


# ------------------------------------------------------------------ the soul ball

## Outplaying `victim` draws their soul into the ball. Dribbling feeds it, tackling steals with it.
func feed(team: int, text: String, amt: float, victim: Player = null) -> void:
	if amt <= 0.0:
		hud.popup(team, text)  # showboating with nobody to beat: looks nice, feeds nothing
		return
	if team != vessel.bond:
		_exposed(team, victim)  # took it off them without a clean pickup (shoulder, parry)
	var gain: float = amt * TEAMS[team].feed
	var kind: int = victim.sig if is_instance_valid(victim) else -1
	var before := vessel.feed(gain, kind, t)
	if text != "":
		hud.popup(team, "%s  +%d %s" % [text, roundi(gain), Vessel.KINDS[kind].name if kind >= 0 else "SOUL"])
	var now := vessel.stage()
	if now > before:
		_stage_up(team, now)


func _stage_up(team: int, s: int) -> void:
	var col := vessel.glow()
	hud.popup(team, String(Vessel.STAGES[s].name), true)
	comic(Vessel.STAGES[s].name + "!", ball.global_position, col, 0.7 + s * 0.15)
	burst(ball.global_position, 16 + s * 10, s == Vessel.Stage.OVERLOADED)
	sfx.play("soul_big" if s >= Vessel.Stage.HUNGRY else "power")
	if s >= Vessel.Stage.HUNGRY:
		excite = maxf(excite, 0.5 + 0.1 * s)
		shake(0.15 * s)


## Passing protects it: the ball's hunger eases off for a while.
func steady(team: int, text: String, secs: float) -> void:
	vessel.steady(t, secs)
	if text != "":
		hud.popup(team, text + "  ·  STEADY")


## Borrow power from the ball. `need` = minimum stage; cost comes out of the charge.
func spend(team: int, label: String, cost: float, need := Vessel.Stage.STIRRING) -> bool:
	if vessel.bond != team or vessel.stage() < need or vessel.charge < cost:
		if is_human(team):
			hud.popup(team, "BALL NEEDS TO BE %s" % Vessel.STAGES[need].name)
		return false
	vessel.spend(cost)
	hud.popup(team, label, true)
	sfx.play("power")
	return true


func soul_shot(team: int, label: String) -> bool:
	var cost := 0.0 if vessel.stage() == Vessel.Stage.OVERLOADED else SOUL_SHOT_COST
	return spend(team, label, cost, Vessel.Stage.POSSESSED)


## Possession left the bonded team: mid charge scatters, overload backlashes on whoever lost it.
func _exposed(team: int, victim: Player) -> void:
	match vessel.turnover(team, t):
		Vessel.Lost.SCATTER:
			hud.popup(1 - team, "LOST IT — THE SOULS SCATTER")
			comic("SCATTER!", ball.global_position, Color("c8c8c8"), 0.8)
		Vessel.Lost.BACKLASH:
			hud.popup(team, "BACKLASH — POWER STOLEN!", true)
			comic("BACKLASH!", ball.global_position, vessel.glow(), 1.3)
			burst(ball.global_position + Vector3.UP * 0.5, 50, true)
			shake(0.7)
			sfx.play("soul_big")
			excite = 1.0
			if is_instance_valid(victim) and victim.team != team:
				victim.stun_t = maxf(victim.stun_t, 1.2)


func on_possession(team: int, from: Player = null) -> void:
	if team != vessel.bond:
		_exposed(team, from)
	var before := vessel.stage()
	var banked := vessel.claim_bank(team, t)
	if banked > 0.0:
		hud.popup(team, "GOAL MOMENTUM  +%d" % roundi(banked))
		if vessel.stage() > before:
			_stage_up(team, vessel.stage())
	if team != possession:
		pass_chain[1 - team] = 0
		possession = team


func on_pass_complete(from: Player, to: Player, wall: bool) -> void:
	if wall:
		steady(to.team, "WALL PASS!", 2.5)
	if from == to:
		return
	pass_chain[to.team] += 1
	var n: int = pass_chain[to.team]
	steady(to.team, ("PASS CHAIN x%d" % n) if n >= 3 else "", 1.0 + n * 0.5)
	if to.last_pass_to == from and t - to.last_pass_t < 3.0:
		steady(to.team, "ONE-TWO!", 3.0)
	if n % 2 == 0:
		feed(to.team, "TEAMWORK", PASS_CHARGE)   # every second pass in a chain charges the ball (saturating its colour)


# ------------------------------------------------------------------ control

func is_human(team: int) -> bool:
	return two_player or team == human_team


## Give a team's human pad to p (or to nobody: pass null and the team).
func set_controlled(p: Player, team := -1) -> void:
	var tm := p.team if p else team
	if controlled[tm]:
		controlled[tm].set_human(false)
	controlled[tm] = p
	if p:
		p.set_human(true)


func _release_all() -> void:
	set_controlled(null, 0)
	set_controlled(null, 1)


func _auto_switch(force := false) -> void:
	for tm in 2:
		if is_human(tm):
			_auto_switch_team(tm, force)


func _auto_switch_team(tm: int, force: bool) -> void:
	var c := ball.carrier
	var pick: Player = null
	if c and c.team == tm and not c.is_keeper:
		pick = c
	elif c == null and ball.kick_type == "pass" and ball.pass_target and ball.pass_target.team == tm \
			and not ball.pass_target.is_keeper and t - ball.kick_t < 1.5 and controlled[tm]:
		pick = controlled[tm]   # the receiver runs onto it on his own; the pad follows once he has the ball
	else:
		var bd := INF
		for p: Player in team_players[tm]:
			if p.is_keeper:
				continue
			var d := p.global_position.distance_to(ball.global_position)
			if d < bd:
				bd = d
				pick = p
		var cur := controlled[tm]
		if cur and not force and pick != cur:
			if cur.lunge_t > 0.0 or cur.global_position.distance_to(ball.global_position) < bd + 2.0:
				pick = cur
	if pick != controlled[tm]:
		set_controlled(pick, tm)


func chaser(team: int) -> Player:
	var best: Player = null
	var bd := INF
	for p: Player in team_players[team]:
		if p.is_keeper:
			continue
		var d := p.global_position.distance_to(ball.global_position)
		if d < bd:
			bd = d
			best = p
	return best


## null in 3v3.
func keeper(team: int) -> Player:
	var p: Player = team_players[team][0]
	return p if p.is_keeper else null


## 3v3 only: the outfielder nearest our goal who isn't chasing the ball stays home.
func last_man(team: int) -> Player:
	if has_keeper():
		return null
	var chase := chaser(team)
	var gx := goals[team].line_x()
	var best: Player = null
	var bd := INF
	for p: Player in team_players[team]:
		var d := absf(p.global_position.x - gx)
		if p != chase and p != ball.carrier and not p.human and d < bd:
			bd = d
			best = p
	return best


## The centre man takes kick-offs.
func kicker(team: int) -> Player:
	return team_players[team][1 if has_keeper() else 0]


# ------------------------------------------------------------------ camera & juice

func _match_point_slowmo() -> void:
	var slow := false
	if ball.carrier == null and ball.kick_type == "shot" and ball.last_touch:
		var side := 1 - ball.last_touch.team
		if _is_decider(side):
			var gx := goals[side].line_x()
			slow = absf(ball.global_position.x - gx) < 5.0 and ball.linear_velocity.x * signf(gx) > 4.0
	if slow != slowmo:
		slowmo = slow
		Engine.time_scale = 0.3 if slow else 1.0


func _camera(delta: float) -> void:
	var f := ball.global_position
	if state == S.TITLE:
		f = Vector3(sin(t * 0.25) * 8.0, 0, 0)
	f.y = 0.0
	focus = focus.lerp(f, 1.0 - exp(-3.5 * delta))
	var close := state == S.GOAL or state == S.OVER
	cam.fov = lerpf(cam.fov, 30.0 if close else 44.0, 1.0 - exp(-2.0 * delta))
	cam.global_position = Vector3(focus.x * 0.75, 13.0 * 1.25, Arena.W + 5.5 + focus.z * 0.3)   # ponytail: 1.25x height (not full pitch scale) so the ball stays big on screen
	cam.look_at(Vector3(focus.x * 0.9, 0.0, focus.z * 0.5 - 0.8))
	trauma = maxf(trauma - delta * 1.6, 0.0)
	var s := trauma * trauma
	cam.h_offset = randf_range(-1.0, 1.0) * s * 0.6
	cam.v_offset = randf_range(-1.0, 1.0) * s * 0.6


func shake(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func hitstop() -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.07, true, false, true).timeout
	if state == S.PLAY and not slowmo:
		Engine.time_scale = 1.0


## Comic-book impact word floating over the action.
## Effect colour: the ball's own once it has woken (saturating as the momentum builds), `fallback` while it sleeps.
func fx_color(fallback := Color.WHITE) -> Color:
	return vessel.glow() if vessel.stage() > Vessel.Stage.DORMANT else fallback


## Comic-book impact word floating over the action, in the ball's colour.
func comic(text: String, pos: Vector3, col: Color, size := 1.0) -> void:
	var l := Arena.label(self, text, pos + Vector3(0, 1.8, 0), fx_color(col), 0.009 * size, 110)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 30
	l.render_priority = 20
	l.outline_render_priority = 19
	l.scale = Vector3.ONE * 0.2
	var tw := l.create_tween().set_ignore_time_scale(true)
	tw.tween_property(l, "scale", Vector3.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.08)
	tw.parallel().tween_property(l, "position:y", l.position.y + 0.6, 0.7)
	tw.tween_interval(0.3)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)


## The ball's aura colour for effects: deepened a little so it reads on the pale pitch, and a still-white ball
## borrows its last toucher's team colour.
func aura() -> Color:
	var c := vessel.glow()
	if c.s < 0.15 and ball.last_touch:
		c = ball.last_touch.st.color
	return Color.from_hsv(c.h, minf(c.s * 1.25, 1.0), c.v * 0.85)


## Confetti: the kick sparks' flattened-circle streaks, a little bigger, in the aura colour (fading to a lighter
## tint, or to black when `dark`) and fading out as they fall.
func burst(pos: Vector3, amount := 60, dark := false) -> void:
	var col := aura()
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.explosiveness = 1.0
	p.lifetime = 2.6
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 75.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 12.0
	m.damping_min = 1.5
	m.damping_max = 3.5
	m.gravity = Vector3(0, -5, 0)   # a gentle fall, so the pieces hang in the air instead of hitting the floor in a second
	m.particle_flag_align_y = true   # long axis along the direction of travel (see spark.gdshader)
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color.BLACK if dark else col.lerp(Color.WHITE, 0.3))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_initial_ramp = gt
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.7, Color.WHITE)
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	m.color_ramp = ft
	p.process_material = m
	p.draw_pass_1 = BallFx.spark_quad(Vector2(0.22, 0.58))   # the kick sparks are 0.16 x 0.42
	p.position = pos
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
