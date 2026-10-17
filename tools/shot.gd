extends Node
## Dev aid: run tools/shot.tscn; screenshots the title and a match to tools/shot_*.png, then quits.
func _ready() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Game
	add_child(game)
	get_window().size = Vector2i(1600, 900)
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("res://tools/shot_title.png")
	game.menu.booted = true
	game.menu._start(false)
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png("res://tools/shot_match.png")
	var p: Player = game.team_players[0][1]
	var q: Player = game.team_players[1][1]
	print("anim ok: ", p.anim.current_animation, " ", q.anim.current_animation, " gk:", game.team_players[0][0].anim.current_animation)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var who := [game.team_players[1][1], game.team_players[1][2], game.team_players[0][2]]
	for i in who.size():
		var pl: Player = who[i]
		game.cam.global_position = pl.global_position + Vector3(0, 1.3, 3.2)
		game.cam.look_at(pl.global_position + Vector3(0, 1.0, 0))
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png("res://tools/shot_p%d.png" % i)
	get_tree().quit()
