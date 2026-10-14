class_name Hud
extends CanvasLayer
## Street-graffiti HUD: slanted scoreboard, squad portraits, the soul-stage track, prompt chips, style feed,
## banners and the full-time card. Menu-time overlays live in Menu; show_title/hide_title only toggle the match HUD.

const SOUL_W := 760.0
const STAGE_COLS := [Color("9aa3b5"), Color("39ff14"), Color("2d8cff"), Color("ff3b3b"), Color("b04dff")]

var game: Game
var brick_rects := [[], []]
var score_labels: Array[Label] = []
var team_names: Array[Label] = []
var feeds: Array[VBoxContainer] = []
var clock_label: Label
var score_label: Label
var banner_label: Label
var sub_label: Label
var banner_tw: Tween
var flash: ColorRect
var lines: SpeedLines
var lines_t := 0.0
var group: Control              # everything that should hide with the HUD toggle / on menus
var squads: VBoxContainer
var track: UI.Art
var soul_info: Label
var prompts: UI.Art
var result: Control
var result_label: Label
var result_sub: Label
var shown := false
var enabled := true             # Settings > HUD
var _squad_key := ""


class SpeedLines extends Control:
	var strength := 0.0

	func _draw() -> void:
		if strength <= 0.01:
			return
		var c := size / 2.0
		var r := size.length() / 2.0
		for i in 56:
			var a := randf() * TAU
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * r * randf_range(0.5, 0.8), c + d * r, Color(1, 1, 1, 0.55 * strength), randf_range(2.0, 7.0))


func _ready() -> void:
	layer = 5
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	_full(flash)
	add_child(flash)
	lines = SpeedLines.new()
	_full(lines)
	add_child(lines)
	group = _root()
	group.visible = false
	_build_logo()
	_build_scoreboard()
	_build_squads()
	_build_soul_track()
	_build_prompts()
	for i in 2:
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT if i == 0 else Control.PRESET_BOTTOM_RIGHT)
		v.offset_top = -520
		v.offset_bottom = -30 if i == 0 else -190
		v.offset_left = 30.0 if i == 0 else -510.0
		v.offset_right = 510.0 if i == 0 else -30.0
		v.alignment = BoxContainer.ALIGNMENT_END
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)
		feeds.append(v)
	banner_label = _label("", 150, Color.WHITE, 26)
	_full(banner_label)
	banner_label.modulate.a = 0.0
	add_child(banner_label)
	sub_label = _label("", 44, Color.WHITE, 12)
	_full(sub_label)
	sub_label.offset_top = 260
	sub_label.modulate.a = 0.0
	add_child(sub_label)
	_build_result()


func _root() -> Control:
	var c := Control.new()
	_full(c)
	c.theme = UI.theme()
	add_child(c)
	return c


func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _label(text: String, size: int, color: Color, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UI.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 4)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------ build

func _build_logo() -> void:
	var a := UI.art(func(c: Control) -> void:
		UI.brush(c, Vector2(-30, 50), Vector2(c.size.x, 70), 120, UI.INK, 5)
		UI.crown(c, Rect2(30, 4, 40, 25), UI.YELLOW)
		var f := UI.font()
		c.draw_string(f, Vector2(30, 70), "SOUL", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, UI.WHITE)
		c.draw_string(f, Vector2(150, 70), "SOCCER", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, UI.YELLOW))
	a.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	a.offset_right = 380
	a.offset_bottom = 110
	group.add_child(a)


func _build_scoreboard() -> void:
	var board := UI.Ink.new(Color(UI.INK, 0.94), UI.BLUE, 3)
	board.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	board.offset_top = 14
	board.add_theme_constant_override("margin_top", 10)
	board.add_theme_constant_override("margin_bottom", 10)
	group.add_child(board)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_child(row)
	row.add_child(_team_panel(0))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", -6)
	row.add_child(mid)
	score_label = _label("0 - 0", 56, UI.YELLOW, 6)
	score_label.custom_minimum_size = Vector2(190, 0)
	mid.add_child(score_label)
	clock_label = _label("3:00", 38, UI.WHITE, 4)
	mid.add_child(clock_label)
	row.add_child(_team_panel(1))


func _team_panel(team: int) -> Control:
	var info: Dictionary = game.TEAMS[team]
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	var col: Color = info.color
	var cr := UI.art(func(c: Control) -> void: UI.crest(c, Rect2(Vector2.ZERO, c.size), team, col), Vector2(34, 38))
	if team == 0:
		head.add_child(cr)
	var n := _label(info.name, 34, Color.WHITE, 8)
	team_names.append(n)
	head.add_child(n)
	if team == 1:
		head.add_child(cr)
	v.add_child(head)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 20)
	row.add_child(_spacer(0))
	for i in Game.WIN_BRICKS:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(40, 16)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(r)
		brick_rects[team].append(r)
	v.add_child(row)
	return v


func _build_squads() -> void:
	squads = VBoxContainer.new()
	squads.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	squads.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	squads.offset_top = 14
	squads.offset_right = -20
	squads.add_theme_constant_override("separation", 8)
	squads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(squads)


## Portrait cards for each human squad: the pad-controlled player is lit yellow, the headband bar is their soul.
func _refresh_squads() -> void:
	var key := "%d|%d|%d" % [game.format, game.human_team, int(game.two_player)]
	if key != _squad_key:
		_squad_key = key
		for c in squads.get_children():
			c.queue_free()
		for tm in (2 if game.two_player else 1):
			var team: int = game.human_team if tm == 0 else 1 - game.human_team
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.alignment = BoxContainer.ALIGNMENT_END
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			squads.add_child(row)
			var i := 0
			for p: Player in game.team_players[team]:
				i += 1
				var card := UI.art(_card_painter.bind(p, "P%d" % (tm + 1) if not p.is_keeper else "GK"), Vector2(112, 128))
				card.set_meta("p", p)
				row.add_child(card)
	for row in squads.get_children():
		for card in row.get_children():
			card.queue_redraw()


func _card_painter(c: Control, p: Player, tag: String) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	var on := p.human
	var info: Dictionary = p.st
	UI.ink_panel(c, r, UI.YELLOW if on else Color(UI.INK, 0.92), UI.WHITE if on else info.color, p.get_index() + 40)
	var shirt: Color = info.keeper if p.is_keeper else info.color
	UI.portrait(c, Rect2(8, 6, r.size.x - 16, r.size.y - 36), p.ch, shirt, info.alt)
	var tone: Color = Vessel.KINDS[p.sig].color
	c.draw_rect(Rect2(8, r.size.y - 28, r.size.x - 16, 22), tone if not p.is_keeper else Color(info.keeper))
	var f := UI.font()
	c.draw_string(f, Vector2(14, r.size.y - 11), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.INK)


func _build_soul_track() -> void:
	var box := UI.Ink.new(Color(UI.INK, 0.94), UI.BLUE, 8)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -20
	group.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	box.add_child(v)
	track = UI.art(_track_painter, Vector2(SOUL_W, 118))
	v.add_child(track)
	soul_info = _label("", 20, Color.WHITE, 5)
	v.add_child(soul_info)


func _track_painter(c: Control) -> void:
	var v := game.vessel
	var cur := int(v.stage())
	var f := UI.font()
	var n := Vessel.STAGES.size()
	var step := c.size.x / n
	for i in n:
		var cx := step * (i + 0.5)
		var col: Color = STAGE_COLS[i]
		var rad := 30.0 if i == cur else 21.0
		var cy := 36.0
		if i == cur:
			c.draw_circle(Vector2(cx, cy), rad + 8.0 + 3.0 * sin(game.t * 6.0), Color(col, 0.35))
		c.draw_circle(Vector2(cx, cy), rad, UI.INK if i != cur else col.darkened(0.55))
		c.draw_arc(Vector2(cx, cy), rad, 0, TAU, 28, col if i <= cur else Color(col, 0.35), 4.0 if i == cur else 3.0, true)
		UI.flame(c, Rect2(cx - rad * 0.4, cy - rad * 0.5, rad * 0.8, rad), col if i <= cur else Color(col, 0.3))
		var nm: String = Vessel.STAGES[i].name
		var fs := 22 if i == cur else 18
		var ext := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		c.draw_string(f, Vector2(cx - ext.x / 2.0, 90), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.YELLOW if i == cur else Color(1, 1, 1, 0.55 if i < cur else 0.35))
		if i < n - 1:
			var ax := cx + rad + 12.0
			var bx := step * (i + 1.5) - 21.0 - 12.0
			c.draw_line(Vector2(ax, cy), Vector2(bx, cy), Color(1, 1, 1, 0.4), 2.5)
			c.draw_colored_polygon(PackedVector2Array([Vector2(bx + 8, cy), Vector2(bx - 3, cy - 6), Vector2(bx - 3, cy + 6)]), Color(1, 1, 1, 0.4))
	# true-scale charge bar, notched at each stage threshold
	var by := 106.0
	var w := c.size.x
	c.draw_rect(Rect2(0, by, w, 10), Color(0, 0, 0, 0.7))
	var over: bool = cur == int(Vessel.Stage.OVERLOADED)
	var col := v.glow()
	if over:
		col = col.lerp(Color.BLACK, 0.5 + 0.4 * sin(game.t * 14.0))
	c.draw_rect(Rect2(0, by, w * v.charge / 100.0, 10), col)
	for s in range(1, n):
		c.draw_rect(Rect2(w * Vessel.STAGES[s].at / 100.0 - 1.5, by, 3, 10), Color.BLACK)


func _build_prompts() -> void:
	prompts = UI.art(_prompt_painter, Vector2(520, 100))
	prompts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	prompts.offset_left = -560
	prompts.offset_top = -120
	prompts.offset_right = -24
	prompts.offset_bottom = -20
	prompts.visible = not TouchControls.enabled()   # the on-screen buttons replace the key hints
	group.add_child(prompts)


func _prompt_painter(c: Control) -> void:
	UI.ink_panel(c, Rect2(Vector2.ZERO, c.size), Color(UI.INK, 0.94), UI.BLUE, 21)
	var pad := Input.get_connected_joypads().size() > 0
	var items := [["Y" if pad else "L", "SKILL", UI.YELLOW], ["A" if pad else "J", "PASS", UI.BLUE], ["B" if pad else "K", "SHOT", UI.RED], ["LB" if pad else "Q", "SOUL", Color("b04dff")]]
	var f := UI.font()
	var w := c.size.x / 4.0
	for i in 4:
		var cx := w * (i + 0.5)
		var col: Color = items[i][2]
		UI.prompt(c, Vector2(cx, 36), 24, items[i][0], col)
		var ext := f.get_string_size(items[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		c.draw_string(f, Vector2(cx - ext.x / 2.0, 86), items[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.WHITE)


func _build_result() -> void:
	result = Control.new()
	_full(result)
	result.visible = false
	add_child(result)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.1, 0.55)
	_full(shade)
	result.add_child(shade)
	var band := UI.art(func(c: Control) -> void:
		UI.ink_panel(c, Rect2(0, c.size.y * 0.12, c.size.x, c.size.y * 0.76), Color(UI.INK, 0.96), UI.BLUE, 31)
		UI.brush(c, Vector2(-40, c.size.y * 0.12), Vector2(c.size.x * 0.7, c.size.y * 0.06), 26, UI.YELLOW, 32)
		UI.brush(c, Vector2(c.size.x * 0.3, c.size.y * 0.95), Vector2(c.size.x + 40, c.size.y * 0.88), 22, UI.BLUE, 33))
	band.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	band.custom_minimum_size = Vector2(1500, 420)
	band.offset_left = -750
	band.offset_right = 750
	band.offset_top = -210
	band.offset_bottom = 210
	result.add_child(band)
	var v := VBoxContainer.new()
	_full(v)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	result.add_child(v)
	result_label = _label("", 130, Color.WHITE, 22)
	v.add_child(result_label)
	result_sub = _label("", 44, UI.YELLOW, 8)
	v.add_child(result_sub)
	v.add_child(_label("TAP  TO  CONTINUE" if TouchControls.enabled() else "PRESS  ENTER / START", 34, Color.WHITE, 8))


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ------------------------------------------------------------------ state

## Menus own the screen: hide the match HUD.
func show_title() -> void:
	shown = false
	result.visible = false
	group.visible = false
	_mark_player_team()


func hide_title() -> void:
	shown = true
	result.visible = false
	_squad_key = ""
	group.visible = enabled
	_mark_player_team()


func set_enabled(on: bool) -> void:
	enabled = on
	group.visible = shown and on


func show_winner(team: int) -> void:
	var info: Dictionary = game.TEAMS[team]
	result.visible = true
	result_label.text = "%s WIN!" % info.name
	result_label.add_theme_color_override("font_color", info.alt)
	result_sub.text = "%d  -  %d" % [game.score[0], game.score[1]] if game.street else ""
	goal_flash(info.color)


func _mark_player_team() -> void:
	for i in 2:
		team_names[i].text = String(game.TEAMS[i].name) + ("  ·  P1" if i == game.human_team else ("  ·  P2" if game.two_player else ""))
		team_names[i].add_theme_color_override("font_color", game.TEAMS[i].color.lerp(Color.WHITE, 0.35))


func refresh() -> void:
	var v := game.vessel
	for team in 2:
		var n: int = game.bricks[team]
		for i in Game.WIN_BRICKS:
			var r: ColorRect = brick_rects[team][i]
			r.visible = not game.street
			r.color = Color("d2462e") if i < n else Color(1, 1, 1, 0.14)
			if i < n and n == Game.WIN_BRICKS - 1:
				r.color = r.color.lerp(Color.WHITE, absf(sin(game.t * 6.0)) * 0.5)  # match point pulse
	lines_t = maxf(lines_t - get_process_delta_time(), 0.0)
	lines.strength = clampf(lines_t, 0.0, 1.0)
	lines.queue_redraw()
	if not group.visible:
		return
	score_label.text = "%d - %d" % [game.score[0], game.score[1]] if game.street else "VS"
	var c := ceili(game.clock)
	clock_label.text = "GOLDEN GOAL" if game.golden else "%d:%02d" % [floori(c / 60.0), c % 60]
	var kind := v.dominant()
	var hungry := v.is_hungry(game.t)
	var over := v.stage() == Vessel.Stage.OVERLOADED
	soul_info.text = "SERVING  %s" % game.TEAMS[v.bond].short \
			+ ("   ·   %s SOUL" % Vessel.KINDS[kind].name if kind >= 0 else "") \
			+ ("   ·   HUNGRY" if hungry else "") \
			+ ("   ·   GOAL = 2 BRICKS" if over and not game.street else "")
	soul_info.modulate.a = 0.55 + 0.45 * absf(sin(game.t * 8.0)) if hungry else 1.0
	track.queue_redraw()
	prompts.queue_redraw()
	_refresh_squads()


func popup(team: int, text: String, big := false) -> void:
	var info: Dictionary = game.TEAMS[team]
	var l := _label(text, 44 if big else 30, Color.WHITE if big else info.alt, 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if team == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	feeds[team].add_child(l)
	if feeds[team].get_child_count() > 6:
		feeds[team].get_child(0).queue_free()
	var tw := l.create_tween().set_ignore_time_scale(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.1).from(0.0)
	tw.tween_interval(1.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func banner(text: String, color: Color, hold: float, sub := "") -> void:
	if banner_tw:
		banner_tw.kill()
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner_label.pivot_offset = banner_label.size / 2.0
	banner_label.modulate.a = 1.0
	banner_label.scale = Vector2(2.2, 2.2)
	banner_label.rotation = -0.06
	sub_label.text = sub
	sub_label.modulate.a = 1.0
	banner_tw = create_tween().set_ignore_time_scale(true)
	banner_tw.tween_property(banner_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tw.tween_interval(hold)
	banner_tw.tween_property(banner_label, "modulate:a", 0.0, 0.3)
	banner_tw.parallel().tween_property(sub_label, "modulate:a", 0.0, 0.3)


func goal_flash(color: Color) -> void:
	flash.color = Color(color, 0.75)
	create_tween().set_ignore_time_scale(true).tween_property(flash, "color:a", 0.0, 0.6)


func speed_lines(duration: float) -> void:
	lines_t = maxf(lines_t, duration)
