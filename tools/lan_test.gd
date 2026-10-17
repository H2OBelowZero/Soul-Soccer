extends Node
## Dev aid: run two copies to exercise the LAN link on one machine.
##   godot --path . res://tools/lan_test.tscn -- host        (P1: hosts, picks the stage, plays)
##   godot --path . res://tools/lan_test.tscn -- client      (P2: joins 127.0.0.1, picks, plays)
## Each saves tools/lan_<role>_N.png and prints what it sees, then quits.

var role := "host"
var game: Game


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = "client" if args.has("client") else "host"
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Game
	add_child(game)
	get_window().size = Vector2i(960, 540)
	get_window().position = Vector2i(40 if role == "host" else 1000, 100)
	await get_tree().create_timer(1.0).timeout
	game.menu.booted = true
	game.menu._open_lan()
	if role == "host":
		await _host()
	else:
		await _client()
	_shot("end")
	get_tree().quit()


func _shot(tag: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://tools/lan_%s_%s.png" % [role, tag])


func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs and not cond.call():
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return cond.call()


func _host() -> void:
	game.menu._lan_host()
	print("host: waiting for client")
	print("host: linked=", await _wait_for(func() -> bool: return game.net.linked, 40.0))
	await get_tree().create_timer(0.5).timeout
	print("host: page=", game.menu.current)
	game.menu._pick_stage(game.menu.stage_cards[0])
	await get_tree().create_timer(0.3).timeout
	game.menu._confirm_squad()   # P1's picks; asks P2
	print("host: waiting page=", game.menu.current)
	await _wait_for(func() -> bool: return game.state == Game.S.PLAY, 30.0)
	print("host: state=", game.state, " picks=", game.picks)
	var p2: Player = game.controlled[1]
	var start := p2.global_position
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		var k: Player = game.controlled[0]
		if i == 2 and k and k.has_ball():
			k.do_shoot()
			print("host: shot fired")
		print("host t=", i, " ball=", game.ball.global_position, " p2 moved=", p2.global_position - start)
		if i == 4:
			_shot("mid")
	print("host: P2 pos=");
	print("host: P2 pos=", game.controlled[1].global_position if game.controlled[1] else "none")


func _client() -> void:
	game.menu._lan_join()
	await get_tree().create_timer(3.0).timeout
	print("client: beacons=", game.net.hosts.keys())
	game.menu._lan_connect("127.0.0.1")
	print("client: linked=", await _wait_for(func() -> bool: return game.net.linked, 20.0))
	print("client: waiting for the pick request")
	await _wait_for(func() -> bool: return game.menu.current == &"team", 60.0)
	print("client: page=", game.menu.current, " disabled=", game.menu.cards.filter(func(c: Variant) -> bool: return c.disabled).size())
	_shot("pick")
	await get_tree().create_timer(0.3).timeout
	game.menu._confirm_squad()
	await _wait_for(func() -> bool: return game.state == Game.S.PLAY, 30.0)
	print("client: state=", game.state, " picks=", game.picks, " mode=", game.net.mode)
	Input.action_press("move_left")   # P2 runs for the -x goal
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		print("client t=", i, " ball=", game.ball.global_position, " kick=", game.ball.kick_type, " human=", game.players.filter(func(p: Player) -> bool: return p.human).map(func(p: Player) -> Vector3: return p.global_position))
		if i == 4:
			_shot("mid")
	Input.action_release("move_left")
