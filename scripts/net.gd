class_name Net
extends Node
## Two-player LAN link, one pair only. The HOST runs the whole match as P1 (it is the only simulation); the CLIENT
## (P2) sends its pad every frame and draws the snapshots the host streams back. Events that make noise on the host
## (banners, popups, sounds, bursts, shakes) are relayed to the client as they happen, see fx().
## A UDP beacon lets the client find the host without typing an IP; a manual IP stays as the fallback.

signal linked_changed          # the other device connected / left
signal hosts_changed           # the client's list of beacons changed
signal dropped(reason: String)

const PORT := 24680
const BEACON_PORT := 24681
const MAGIC := "SOULSOCCER1"
const SEND_MS := 33            # host snapshot period (30 Hz)
const INPUT_MS := 16           # client pad period
const BUTTONS := ["pass", "shoot", "tackle", "skill", "sprint", "ability"]
const KICKS := ["", "pass", "shot", "flick", "parry", "loose"]
const ACTS := ["", "soccer_pass", "kick_soccerball"]

enum Mode { OFF, HOST, CLIENT }

static var inst: Net

var game: Game
var mode := Mode.OFF
var linked := false
var hosts := {}                # ip -> {"name": String, "seen": int msec}
var _peer: ENetMultiplayerPeer
var _udp: PacketPeerUDP
var _beacon_ms := 0
var _send_ms := 0
var _held := {}                # p2_ action -> last strength injected (host) / last pad state (client)
var _f: PackedFloat32Array
var _i := 0
var _recv_ms := 0
var _tgt: Array[Dictionary] = []   # per player: latest snapshot pose
var _ball_tgt := {"p": Vector3.ZERO, "v": Vector3.ZERO}
var _bricks := [-1, -1]
var _last_state := -1


static func is_host() -> bool:
	return inst != null and inst.mode == Mode.HOST


static func is_client() -> bool:
	return inst != null and inst.mode == Mode.CLIENT


static func active() -> bool:
	return inst != null and inst.mode != Mode.OFF


## Host only: tell the client "do this on your screen too".
static func fx(kind: StringName, args: Array) -> void:
	if inst != null and inst.mode == Mode.HOST and inst.linked:
		inst._rx_fx.rpc(kind, args)


func _ready() -> void:
	inst = self
	name = "Net"
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _drop("COULD NOT CONNECT"))
	multiplayer.server_disconnected.connect(func() -> void: _drop("THE HOST LEFT"))


# ------------------------------------------------------------------ connect / disconnect

## Addresses a friend can type in: this device's private IPv4s.
func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and (a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172.")):
			out.append(a)
	return out


func host() -> bool:
	close()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_server(PORT, 1) != OK:   # 1 = a pair, never a lobby
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	mode = Mode.HOST
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	return true


## Start listening for hosts (beacons); call join() with one of them, or with a typed IP.
func search() -> void:
	close()
	hosts.clear()
	_udp = PacketPeerUDP.new()
	_udp.bind(BEACON_PORT)
	hosts_changed.emit()


func join(ip: String) -> bool:
	if _udp:
		_udp.close()
		_udp = null
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(ip.strip_edges(), PORT) != OK:
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	mode = Mode.CLIENT
	return true


func close() -> void:
	if _udp:
		_udp.close()
		_udp = null
	linked = false
	mode = Mode.OFF
	_release_inputs()
	_tgt.clear()
	_bricks = [-1, -1]
	_last_state = -1
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null


## Match over / quit to menu: tell the other device, then cut the link a moment later so the message gets out.
func leave() -> void:
	if mode == Mode.HOST and linked:
		_rx_fx.rpc(&"title", [])
		var keep := _peer
		linked = false
		mode = Mode.OFF
		_release_inputs()
		get_tree().create_timer(0.4, true, false, true).timeout.connect(func() -> void:
			if keep == _peer:
				close())
	else:
		close()


func _drop(reason: String) -> void:
	close()
	dropped.emit(reason)


func _on_peer_connected(_id: int) -> void:
	if mode == Mode.HOST:
		linked = true
		_udp.close()
		_udp = null
		linked_changed.emit()


func _on_peer_gone(_id: int) -> void:
	if mode == Mode.HOST and linked:
		_drop("PLAYER 2 LEFT")


func _on_connected() -> void:
	linked = true
	linked_changed.emit()


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if mode == Mode.HOST:
		if _udp and not linked and now - _beacon_ms > 1000:
			_beacon_ms = now
			_beacon()
		if linked and game.state != Game.S.TITLE and now - _send_ms >= SEND_MS:
			_send_ms = now
			_rx_state.rpc(_pack())
	elif mode == Mode.CLIENT:
		if linked:
			if now - _send_ms >= INPUT_MS:
				_send_ms = now
				_send_pad()
			_follow(delta)
	elif _udp:
		_listen(now)


func _beacon() -> void:
	var msg := ("%s|%s" % [MAGIC, OS.get_model_name() if OS.has_feature("mobile") else OS.get_environment("COMPUTERNAME")]).to_utf8_buffer()
	var targets := ["255.255.255.255"]
	for ip in local_ips():
		targets.append(ip.rsplit(".", true, 1)[0] + ".255")   # directed broadcast: some hotspots drop the global one
	for t: String in targets:
		_udp.set_dest_address(t, BEACON_PORT)
		_udp.put_packet(msg)


func _listen(now: int) -> void:
	var changed := false
	while _udp.get_available_packet_count() > 0:
		var parts := _udp.get_packet().get_string_from_utf8().split("|")
		var ip := _udp.get_packet_ip()
		if parts.size() == 2 and parts[0] == MAGIC:
			changed = changed or not hosts.has(ip)
			hosts[ip] = {"name": parts[1], "seen": now}
	for ip: String in hosts.keys():
		if now - hosts[ip].seen > 4000:
			hosts.erase(ip)
			changed = true
	if changed:
		hosts_changed.emit()


# ------------------------------------------------------------------ client pad -> host

func _send_pad() -> void:
	var mask := 0
	var v := Vector2.ZERO
	if game.menu.current == Menu.NONE:   # a pause menu on this device must not keep the player running
		v = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		for i in BUTTONS.size():
			if Input.is_action_pressed(BUTTONS[i]):
				mask |= 1 << i
	_rx_pad.rpc_id(1, mask, v.x, v.y)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rx_pad(mask: int, mx: float, my: float) -> void:
	if mode != Mode.HOST or not linked:
		return
	for i in BUTTONS.size():
		_inject("p2_" + BUTTONS[i], 1.0 if mask & (1 << i) else 0.0)
	_inject("p2_move_left", maxf(-mx, 0.0))
	_inject("p2_move_right", maxf(mx, 0.0))
	_inject("p2_move_up", maxf(-my, 0.0))
	_inject("p2_move_down", maxf(my, 0.0))


## Only on change: re-pressing a held action would keep re-firing is_action_just_pressed.
func _inject(action: String, s: float) -> void:
	if is_equal_approx(_held.get(action, 0.0), s):
		return
	_held[action] = s
	if s > 0.0:
		Input.action_press(action, s)
	else:
		Input.action_release(action)


func _release_inputs() -> void:
	for a: String in _held:
		Input.action_release(a)
	_held.clear()


# ------------------------------------------------------------------ host -> client

func _pack() -> PackedFloat32Array:
	var g := game
	var b := g.ball
	var v := g.vessel
	var f := PackedFloat32Array()
	f.append_array([float(g.state), g.clock, float(g.bricks[0]), float(g.bricks[1]), float(g.score[0]), float(g.score[1]),
			float(g.golden), g.excite, Engine.time_scale, float(g.last_scorer),
			v.charge, float(v.bond), g.t - v.last_feed, v.steady_until - g.t])
	f.append_array(v.souls)
	f.append_array([b.global_position.x, b.global_position.y, b.global_position.z,
			b.linear_velocity.x, b.linear_velocity.y, b.linear_velocity.z,
			float(g.players.find(b.carrier)), float(g.players.find(b.last_touch)),
			float(maxi(KICKS.find(b.kick_type), 0)), g.t - b.kick_t, b.charge])
	for p in g.players:
		var flags := (1 if p.diving else 0) | (2 if p.charging or p.lobbing else 0) | (4 if p.human else 0)
		f.append_array([p.global_position.x, p.global_position.y, p.global_position.z, p.velocity.x, p.velocity.z,
				p.facing.x, p.facing.z, p.mv.x, p.mv.z, p.stun_t, p.lunge_t, p.spin_t, p.push_cd,
				float(maxi(ACTS.find(p.act), 0)), p.act_end - g.t, float(flags)])
	return f


func _n() -> float:
	_i += 1
	return _f[_i - 1]


@rpc("authority", "call_remote", "unreliable_ordered")
func _rx_state(f: PackedFloat32Array) -> void:
	if mode != Mode.CLIENT or not linked:
		return
	var g := game
	_f = f
	_i = 0
	var state := int(_n())
	g.clock = _n()
	g.bricks = [int(_n()), int(_n())]
	g.score = [int(_n()), int(_n())]
	g.golden = _n() > 0.5
	g.excite = _n()
	Engine.time_scale = _n()
	g.last_scorer = int(_n())
	var v := g.vessel
	v.charge = _n()
	v.bond = int(_n())
	v.last_feed = g.t - _n()
	v.steady_until = g.t + _n()
	for k in 5:
		v.souls[k] = _n()
	var b := g.ball
	_ball_tgt.p = Vector3(_n(), _n(), _n())
	_ball_tgt.v = Vector3(_n(), _n(), _n())
	b.carrier = _player(int(_n()))
	b.last_touch = _player(int(_n()))
	b.kick_type = KICKS[int(_n())]
	b.kick_t = g.t - _n()
	b.charge = _n()
	if g.players.size() * 16 != f.size() - _i:
		return   # the roster differs (mid format change): wait for the next one
	if _tgt.size() != g.players.size():
		_tgt.clear()
		for p in g.players:
			_tgt.append({"p": p.global_position, "v": Vector3.ZERO})
	for i in g.players.size():
		var p := g.players[i]
		var t := _tgt[i]
		t.p = Vector3(_n(), _n(), _n())
		t.v = Vector3(_n(), 0.0, _n())
		p.facing = Vector3(_n(), 0.0, _n())
		p.mv = Vector3(_n(), 0.0, _n())
		p.stun_t = _n()
		p.lunge_t = _n()
		p.spin_t = _n()
		p.push_cd = _n()
		p.act = ACTS[int(_n())]
		p.act_end = g.t + _n()
		var flags := int(_n())
		p.diving = flags & 1 != 0
		p.charging = flags & 2 != 0
		var human := flags & 4 != 0
		if human != p.human:
			p.human = human
			p.ring.visible = human
			p.arrow.visible = human
	_recv_ms = Time.get_ticks_msec()
	if state != _last_state:
		_last_state = state
		g.state = state as Game.S
		if g.state == Game.S.OVER:
			g.hud.show_winner(g.last_scorer, false)
	g.state = state as Game.S


func _player(i: int) -> Player:
	return game.players[i] if i >= 0 and i < game.players.size() else null


## Client: ease the pieces to where the host says they are, pushed on by their velocity since the snapshot.
func _follow(delta: float) -> void:
	if _tgt.size() != game.players.size():
		return
	var age := minf((Time.get_ticks_msec() - _recv_ms) / 1000.0, 0.15)
	var ts := Engine.time_scale
	var k := 1.0 - exp(-30.0 * delta)
	for i in _tgt.size():
		var want: Vector3 = _tgt[i].p + _tgt[i].v * age * ts
		var p := game.players[i]
		p.global_position = want if p.global_position.distance_to(want) > 2.5 else p.global_position.lerp(want, k)
	var b := game.ball
	var bv: Vector3 = _ball_tgt.v
	var bw: Vector3 = _ball_tgt.p + bv * age * ts
	if b.carrier == null:
		bw.y = maxf(_ball_tgt.p.y + bv.y * age * ts - 0.5 * 9.8 * Ball.GRAV * age * age * ts * ts, Ball.R)
	var from := b.global_position
	b.global_position = bw if from.distance_to(bw) > 3.0 else from.lerp(bw, 1.0 - exp(-35.0 * delta))
	var moved := b.global_position - from   # roll the pattern with the travel, as Ball._carry does
	moved.y = 0.0
	var axis := Vector3.UP.cross(moved)
	if axis.length() > 0.0001:
		b.visual.global_rotate(axis.normalized(), moved.length() / Ball.R)


@rpc("authority", "call_remote", "reliable")
func _rx_fx(kind: StringName, a: Array) -> void:
	if mode != Mode.CLIENT:
		return
	match kind:
		&"popup": game.hud.popup(a[0], a[1], a[2])
		&"banner": game.hud.banner(a[0], a[1], a[2], a[3])
		&"flash": game.hud.goal_flash(a[0])
		&"lines": game.hud.speed_lines(a[0])
		&"sfx": game.sfx.play(a[0], a[1])
		&"burst": game.burst(a[0], a[1], a[2])
		&"shake": game.shake(a[0])
		&"bricks": game.goals[a[0]].set_bricks(a[1], true)
		&"title": game.to_title()


# ------------------------------------------------------------------ match set-up handshake

## Host -> client: "pick your three" (with P1's faces already taken).
func ask_pick() -> void:
	_rx_pick.rpc(_cfg())


## Host -> client: the match is starting with these settings.
func begin() -> void:
	_rx_begin.rpc(_cfg())


func _cfg() -> Dictionary:
	var g := game
	return {"fmt": g.format, "team": g.human_team, "picks": g.picks, "street": g.street, "time": g.street_time}


func _adopt(c: Dictionary) -> void:
	var g := game
	g.human_team = c.team
	g.picks = c.picks
	g.street = c.street
	g.street_time = c.time
	g.two_player = true
	g.set_format(c.fmt)   # rebuilds both squads with the chosen faces
	g.ball.freeze = true


@rpc("authority", "call_remote", "reliable")
func _rx_pick(c: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	_adopt(c)
	game.menu.net_pick()


@rpc("authority", "call_remote", "reliable")
func _rx_begin(c: Dictionary) -> void:
	if mode != Mode.CLIENT:
		return
	_adopt(c)
	for goal in game.goals:
		goal.set_bricks(0 if game.street else 1)
	game.hud.hide_title()
	game.menu.net_begin()


func send_picked(sel: Array) -> void:
	_rx_picked.rpc_id(1, sel)


@rpc("any_peer", "call_remote", "reliable")
func _rx_picked(sel: Array) -> void:
	if mode != Mode.HOST or not linked or game.menu.current != &"wait":
		return
	var mine: Array = game.picks[game.human_team]
	var seen := {}
	for i in sel:
		if not (i is int) or i < 0 or i >= UI.CHARS.size() or mine.has(i) or seen.has(i):
			return   # not a legal squad: ignore it, the client stays on its pick screen
		seen[i] = true
	if sel.size() != 3:
		return
	game.picks[1 - game.human_team] = sel
	game.set_format(game.format)
	game.menu.net_started()


func request_title() -> void:
	_rx_title.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rx_title() -> void:
	if mode == Mode.HOST and linked and game.state == Game.S.OVER:
		game.to_title()
