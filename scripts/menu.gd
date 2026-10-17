class_name Menu
extends CanvasLayer
## Street-graffiti menus: title, main, stage select, character select, settings, controls, music and the pause menu.
## Keyboard / pad navigable (ui_* actions); pausing freezes the tree, the Jukebox autoload keeps playing.
## Flow:  TITLE -> MAIN -> STAGE (format) -> TEAM (pick the 3 outfielders, P2 picks next in local 2P) -> match.

const NONE := &""

var game: Game
var root: Control
var backdrop: UI.Art
var dim: ColorRect
var pages := {}                 # StringName -> Control
var current := NONE             # NONE = no menu (match running)
var booted := false             # title page shows once per launch
var back_to := &"main"          # where SETTINGS / MUSIC / CONTROLS return to

# match setup
var two_p := false
var pass_team := 0              # whose squad the character page is picking
var sel: Array[int] = []        # picked UI.CHARS indices, in slot order (centre, left, right)
var focus_idx := 0

# settings
var rows: Array = []            # [Chooser, getter Callable] pairs, re-read after any change
var tab_buttons: Array[Button] = []
var tab_panels: Array[Control] = []
var tab_cur := 0
var match_rows: Array[Control] = []   # next-match-only rows (hidden in the pause-time settings)
var time_row: Control
var vol := {"master": 1.0, "music": 1.0}

# pages' live bits
var setup_label: Label
var cards: Array[CharCard] = []
var team_tabs: Array[Button] = []
var confirm_btn: Button
var preview: UI.Art
var lineup: UI.Art
var count_chip: UI.Art
var stage_cards: Array[StageCard] = []
var music_card: UI.Art
var song_list: VBoxContainer
var shuffle_btn: Button
var play_btn: Button
var music_back := &"main"
var restart_btn: Control
var lan_menu: Control
var lan_info: Label
var lan_list: VBoxContainer
var lan_ip: LineEdit
var wait_label: Label


# ------------------------------------------------------------------ inner widgets

## Character card: portrait on the character's colour, name plate, pick badge.
class CharCard extends Button:
	var menu: Menu
	var idx := 0

	func _init(m: Menu, i: int) -> void:
		menu = m
		idx = i
		custom_minimum_size = Vector2(200, 300)
		flat = true
		for s: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())   # the frame is drawn in _draw, focus included
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(grab_focus)

	func _draw() -> void:
		var ch: Dictionary = UI.CHARS[idx]
		var r := Rect2(Vector2.ZERO, size)
		var tone: Color = ch.tone
		var info: Dictionary = menu.game.TEAMS[menu.pass_team]
		var order := menu.sel.find(idx)
		UI.ink_panel(self, r, tone.darkened(0.15), UI.YELLOW if has_focus() else UI.INK, idx + 90)
		UI.portrait(self, Rect2(8, 14, size.x - 16, size.y - 100), ch, tone, UI.WHITE)
		var plate := Rect2(0, size.y - 84, size.x, 84)
		draw_rect(plate, Color(UI.INK, 0.95))
		var f := UI.font()
		draw_string(f, Vector2(12, size.y - 54), ch.name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 26, UI.WHITE)
		draw_string(f, Vector2(12, size.y - 30), "\"%s\"" % ch.nick, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 20, info.alt)
		draw_string(f, Vector2(12, size.y - 10), ch.last, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 17, Color(1, 1, 1, 0.7))
		if has_focus():
			draw_rect(r.grow(-2), UI.YELLOW, false, 6.0)
		if order >= 0:
			draw_rect(r, Color(0, 0, 0, 0.35))
			draw_circle(Vector2(size.x - 34, 34), 24, UI.YELLOW)
			draw_string(f, Vector2(size.x - 45, 46), str(order + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UI.INK)
		if disabled:
			draw_rect(r, Color(0, 0, 0, 0.6))
			draw_string(f, Vector2(0, size.y * 0.45), "TAKEN", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color(1, 1, 1, 0.8))


## Stage card: a painted court, name plate and sub-label. Locked cards are greyed out.
class StageCard extends Button:
	var title := ""
	var sub := ""
	var variant := 0
	var locked := false

	func _init(t: String, s: String, v: int, lock: bool) -> void:
		title = t
		sub = s
		variant = v
		locked = lock
		custom_minimum_size = Vector2(360, 480)
		flat = true
		for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(grab_focus)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var art := Rect2(10, 10, size.x - 20, size.y - 150)
		draw_rect(r, UI.YELLOW if has_focus() else Color(UI.BLUE, 0.9))
		draw_rect(r.grow(-6), UI.INK)
		_court(art)
		var f := UI.font()
		draw_string(f, Vector2(20, size.y - 82), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 34, UI.WHITE if not locked else Color(1, 1, 1, 0.6))
		var lines := sub.split("\n")
		for i in lines.size():
			draw_string(f, Vector2(20, size.y - 48 + i * 28), lines[i], HORIZONTAL_ALIGNMENT_LEFT, size.x - 30, 24, UI.YELLOW if not locked else Color(1, 1, 1, 0.4))

	func _court(a: Rect2) -> void:
		draw_rect(a, UI.SKY if not locked else Color("3a3f4a"))
		var gy := a.position.y + a.size.y * 0.52
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + variant
		var x := a.position.x
		while x < a.end.x:
			var w := rng.randf_range(24, 52)
			var h := rng.randf_range(a.size.y * 0.1, a.size.y * 0.3)
			draw_rect(Rect2(x, gy - h, minf(w, a.end.x - x), h), Color("0c3b80") if not locked else Color("22262e"))
			x += w
		draw_rect(Rect2(a.position.x, gy, a.size.x, a.end.y - gy), Color("2a3a58") if not locked else Color("1b1e25"))
		if locked:
			draw_string(UI.font(), Vector2(a.position.x, a.position.y + a.size.y * 0.62), "?", HORIZONTAL_ALIGNMENT_CENTER, a.size.x, 170, Color(1, 1, 1, 0.3))
			return
		# fence + graffiti wall
		draw_rect(Rect2(a.position.x, gy - 18, a.size.x, 22), Color("101a30"))
		for i in 6:
			draw_rect(Rect2(a.position.x + 12 + i * 52, gy - 14, 36, 12), [UI.YELLOW, UI.RED, UI.BLUE, Color("b04dff"), Color("39ff14"), UI.WHITE][i])
		# floor: perspective court
		var l0 := Vector2(a.position.x + a.size.x * 0.2, gy + 4)
		var l1 := Vector2(a.end.x - a.size.x * 0.2, gy + 4)
		var b0 := Vector2(a.position.x + 6, a.end.y - 6)
		var b1 := Vector2(a.end.x - 6, a.end.y - 6)
		draw_colored_polygon(PackedVector2Array([l0, l1, b1, b0]), Color("d9a441") if variant == 0 else Color("e8743b"))
		var line := Color(1, 1, 1, 0.9)
		draw_polyline(PackedVector2Array([l0, l1, b1, b0, l0]), line, 3.0)
		var mid_t := l0.lerp(l1, 0.5)
		var mid_b := b0.lerp(b1, 0.5)
		draw_line(mid_t, mid_b, line, 3.0)
		draw_arc(mid_t.lerp(mid_b, 0.5), a.size.x * 0.12, 0, TAU, 20, line, 3.0)
		var gw := 26.0 if variant == 0 else 16.0   # 3v3: small goals
		for g in [l0.lerp(b0, 0.5), l1.lerp(b1, 0.5)]:
			draw_rect(Rect2(g - Vector2(gw * 0.5, 30), Vector2(gw, 60)), UI.WHITE, false, 3.0)


# ------------------------------------------------------------------ lifecycle

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.theme()
	add_child(root)
	backdrop = UI.art(UI.backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.12, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	_build_title()
	_build_main()
	_build_stage()
	_build_team()
	_build_settings()
	_build_controls()
	_build_music()
	_build_pause()
	_build_lan()
	_build_wait()
	game.net.linked_changed.connect(_net_linked)
	game.net.hosts_changed.connect(_lan_refresh)
	get_tree().set_quit_on_go_back(false)   # Android back = ui_cancel, see _notification
	Jukebox.changed.connect(_refresh_music)
	get_viewport().gui_focus_changed.connect(func(c: Control) -> void:
		if current != NONE and c is BaseButton:
			game.sfx.play("ui_move"))
	_refresh_music()
	_go(NONE)


func _process(_d: float) -> void:
	if current == &"music":
		music_card.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var jb := event as InputEventJoypadButton
	var start_pad := jb != null and jb.pressed and jb.button_index == JOY_BUTTON_START
	if not (event.is_action_pressed("ui_cancel") or start_pad):
		return
	if _cancel():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_cancel()


## Esc / pad Start / Android back. False when there was nothing to do.
func _cancel() -> bool:
	if current == NONE:
		if game.state == Game.S.TITLE or game.state == Game.S.OVER:
			return false
		pause()
	elif current == &"pause":
		resume()
	elif current in [&"title", &"main"]:
		return false
	else:
		game.sfx.play("ui_back")
		_back()
	return true


# ------------------------------------------------------------------ navigation

func show_main() -> void:
	get_tree().paused = false
	_sync_setup()
	_go(&"main" if booted else &"title")


func pause() -> void:
	get_tree().paused = not Net.active()   # over LAN the other player keeps playing: the match cannot stop
	restart_btn.visible = not Net.active()
	_go(&"pause")


func resume() -> void:
	get_tree().paused = false
	_go(NONE)


func _go(page: StringName) -> void:
	current = page
	for k: StringName in pages:
		pages[k].visible = k == page
	var paused := get_tree().paused or (Net.active() and game.state != Game.S.TITLE)
	backdrop.visible = page != NONE and not paused
	dim.visible = page != NONE and paused
	Jukebox.set_menu(page != NONE)
	if page == NONE:
		return
	var p: Control = pages[page]
	p.modulate.a = 0.0
	create_tween().tween_property(p, "modulate:a", 1.0, 0.14)
	var b := _first_button(p)
	if b:
		b.call_deferred("grab_focus")


func _back() -> void:
	match current:
		&"lan", &"wait":
			_lan_back()
		&"stage":
			if Net.active():
				_lan_back()
			else:
				_go(&"main")
		&"team":
			if Net.active():
				_lan_back()
			elif two_p and pass_team != game.human_team:
				_begin_squad(game.human_team)   # P2 steps back to P1's picks
			else:
				_go(&"stage")
		&"settings":
			var f := get_viewport().gui_get_focus_owner()
			if f is UI.Chooser or (f is Button and not tab_buttons.has(f)):
				tab_buttons[tab_cur].grab_focus()
			else:
				_go(back_to)
		_:
			_go(back_to if current != &"music" else music_back)


func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Control and not c.visible:
			continue
		if c is Button and not c.disabled:
			return c
		var b := _first_button(c)
		if b:
			return b
	return null


func _open(page: StringName) -> void:
	back_to = &"pause" if current == &"pause" else &"main"
	if page == &"music":
		music_back = back_to
	if page == &"settings":
		for r in match_rows:
			r.visible = back_to == &"main"
		_sync()
	_go(page)


func _start(two: bool) -> void:
	game.sfx.play("ui_start")
	_go(NONE)
	if Net.is_host():
		game.net.begin()
	game.start_match(two)


func _restart() -> void:
	get_tree().paused = false
	_go(NONE)
	game.start_match(game.two_player)


func _to_title() -> void:
	game.to_title()   # -> show_main()


# ------------------------------------------------------------------ squad / match setup

func _open_stage(two: bool) -> void:
	two_p = two
	for c in stage_cards:
		if not c.locked:
			c.set_meta("fmt", 4 if c.variant == 0 else 3)
	_go(&"stage")
	for c in stage_cards:
		if c.get_meta("fmt", 0) == game.format:
			c.call_deferred("grab_focus")


func _pick_stage(c: StageCard) -> void:
	if c.locked:
		return
	game.set_format(c.get_meta("fmt"))
	game._place_for_kickoff(0)
	game.sfx.play("ui")
	_sync_setup()
	_begin_squad(game.human_team)
	_go(&"team")


func _begin_squad(team: int) -> void:
	pass_team = team
	sel.assign(game.picks[team])
	if two_p and team != game.human_team:   # P2 can't reuse faces P1 took
		sel.assign(sel.filter(func(i: int) -> bool: return not game.picks[game.human_team].has(i)))
	focus_idx = sel[0] if sel.size() > 0 else 0
	for c in cards:
		c.disabled = two_p and team != game.human_team and game.picks[game.human_team].has(c.idx)
	for i in 2:
		team_tabs[i].disabled = two_p and team != game.human_team and i != team
		team_tabs[i].theme_type_variation = &"Cta" if i == team else &""
	_sync_squad()
	if current == &"team":
		cards[focus_idx].call_deferred("grab_focus")


func _toggle_pick(i: int) -> void:
	if sel.has(i):
		sel.erase(i)
	elif sel.size() < 3:
		sel.append(i)
	game.sfx.play("ui_party" if sel.has(i) else "ui_side")
	_sync_squad()


func _pick_team(team: int) -> void:
	if two_p:
		return
	game.human_team = team
	game.sfx.play("ui_tab")
	game.hud.show_title()
	_begin_squad(team)
	team_tabs[team].call_deferred("grab_focus")


func _sync_squad() -> void:
	confirm_btn.disabled = sel.size() < 3
	confirm_btn.text = "CONFIRM TEAM" if not two_p or pass_team != game.human_team else "NEXT: PLAYER 2"
	for c in cards:
		c.queue_redraw()
	preview.queue_redraw()
	lineup.queue_redraw()
	count_chip.queue_redraw()


func _confirm_squad() -> void:
	if sel.size() < 3:
		return
	game.picks[pass_team] = sel.duplicate()
	if Net.is_client():
		game.net.send_picked(sel)
		_wait("WAITING FOR THE HOST TO START...")
		return
	if two_p and pass_team == game.human_team:
		if Net.is_host():
			game.net.ask_pick()   # player 2 picks on their own device
			_wait("WAITING FOR PLAYER 2 TO PICK THEIR TEAM...")
		else:
			_begin_squad(1 - game.human_team)
		return
	if not two_p:
		var pool := range(UI.CHARS.size()).filter(func(i: int) -> bool: return not sel.has(i))
		pool.shuffle()
		game.picks[1 - pass_team] = pool.slice(0, 3)
	game.set_format(game.format)   # rebuild the squads with the chosen faces
	_start(two_p)


# ------------------------------------------------------------------ settings model

func _sync_setup() -> void:
	if setup_label:
		setup_label.text = "FORMAT   %s\nMODE     %s\nLEVEL    %s" % [
			"4v4 · 3 + KEEPER" if game.has_keeper() else "3v3 · NO KEEPERS",
			"STREET · %d MIN" % roundi(game.street_time / 60.0) if game.street else "BRICKS · GOAL SHRINKS",
			Game.DIFFS[game.difficulty].name]


func _sync() -> void:
	for r: Array in rows:
		r[0].set_value(r[1].call())
	time_row.visible = game.street and back_to == &"main"
	_sync_setup()


func _row(parent: Control, title: String, getter: Callable, stepper: Callable, next_match := false) -> UI.Chooser:
	var c := UI.Chooser.new(title)
	c.set_value(getter.call())
	c.stepped.connect(func(d: int) -> void:
		stepper.call(d)
		game.sfx.play("ui_side")
		_sync())
	rows.append([c, getter])
	parent.add_child(c)
	if next_match:
		match_rows.append(c)
	return c


func _toggle_format(_d: int) -> void:
	game.set_format(3 if game.has_keeper() else 4)
	game._place_for_kickoff(0)


func _on_off(v: bool) -> String:
	return "ON" if v else "OFF"


func _wrap(i: int, d: int, n: int) -> int:
	return posmod(i + d, n)


func _set_vol(key: String, d: int) -> void:
	vol[key] = clampf(snappedf(vol[key] + d * 0.1, 0.1), 0.0, 1.0)
	var bus := 0 if key == "master" else AudioServer.get_bus_index(Jukebox.VENUE_BUS)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol[key], 0.0001)))
	AudioServer.set_bus_mute(bus, vol[key] <= 0.0)


func _reset_settings() -> void:
	game.difficulty = 1
	game.street = false
	game.street_time = 180.0
	game.hud.set_enabled(true)
	Jukebox.shuffle = false
	for k: String in vol:
		vol[k] = 1.0
		_set_vol(k, 0)
	get_window().mode = Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if not game.has_keeper() and back_to == &"main":
		game.set_format(4)
		game._place_for_kickoff(0)
	game.sfx.play("ui")
	_sync()
	_refresh_music()


# ------------------------------------------------------------------ page chrome

func _page(name: StringName) -> Control:
	var p := Control.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	root.add_child(p)
	pages[name] = p
	return p


func _put(c: Control, left: float, top: float, w: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = left + w
	c.offset_bottom = top + h


func _put_right(c: Control, right: float, top: float, w: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	c.offset_right = -right
	c.offset_left = -right - w
	c.offset_top = top
	c.offset_bottom = top + h


## Black brush banner with the crown, a big title and an optional yellow sub-line.
func _header(p: Control, title: String, sub := "") -> void:
	var f := UI.font()
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 84).x
	var a := UI.art(func(c: Control) -> void:
		UI.brush(c, Vector2(-40, 82), Vector2(tw + 250, 74), 128, UI.INK, 41)
		UI.crown(c, Rect2(56, 18, 54, 34), UI.YELLOW)
		c.draw_string(f, Vector2(60, 110), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 84, UI.WHITE)
		if sub != "":
			var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			UI.brush(c, Vector2(30, 152), Vector2(sw + 150, 150), 50, UI.YELLOW, 42)
			c.draw_string(f, Vector2(80, 162), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UI.INK))
	_put(a, 0, 0, tw + 360, 200)
	p.add_child(a)


## Bottom-left prompt strip + page name, like the console menus it is modelled on.
func _footer(p: Control, name: String, hints: Array) -> void:
	var f := UI.font()
	var a := UI.art(func(c: Control) -> void:
		UI.brush(c, Vector2(-30, 46), Vector2(c.size.x, 40), 90, UI.INK, 51)
		var x := 50.0
		for h: Array in hints:
			UI.prompt(c, Vector2(x, 44), 20, h[0], UI.WHITE)
			c.draw_string(f, Vector2(x + 32, 54), h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UI.WHITE)
			x += 60 + f.get_string_size(h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 24
		UI.brush(c, Vector2(-30, 112), Vector2(c.size.x * 0.8, 108), 54, UI.INK, 52)
		UI.crown(c, Rect2(40, 92, 36, 22), UI.YELLOW)
		c.draw_string(f, Vector2(96, 118), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UI.WHITE))
	a.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	a.offset_left = 0
	a.offset_top = -140
	a.offset_right = 780
	a.offset_bottom = -10
	p.add_child(a)


func _menu_list(p: Control, left: float, top: float, w: float, items: Array, seed_n := 3) -> UI.Ink:
	var panel := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, seed_n)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	for it: Array in items:
		v.add_child(UI.button(it[0], it[1], w - 56, 70))
	p.add_child(panel)
	_put(panel, left, top, w, items.size() * 80 + 50)
	return panel


# ------------------------------------------------------------------ pages

func _build_title() -> void:
	var p := _page(&"title")
	var f := UI.font()
	var art := UI.art(func(c: Control) -> void:
		UI.brush(c, Vector2(-60, 330), Vector2(c.size.x + 120, 190), 340, UI.INK, 61)
		var w1 := f.get_string_size("SOUL ", HORIZONTAL_ALIGNMENT_LEFT, -1, 190).x
		var w2 := f.get_string_size("SOCCER", HORIZONTAL_ALIGNMENT_LEFT, -1, 190).x
		var x := (c.size.x - w1 - w2) * 0.5
		UI.crown(c, Rect2(c.size.x * 0.5 - 70, 150, 140, 88), UI.YELLOW)
		c.draw_string(f, Vector2(x, 480), "SOUL ", HORIZONTAL_ALIGNMENT_LEFT, -1, 190, UI.WHITE)
		c.draw_string(f, Vector2(x + w1, 480), "SOCCER", HORIZONTAL_ALIGNMENT_LEFT, -1, 190, UI.YELLOW)
		UI.brush(c, Vector2(c.size.x * 0.5 - 420, 560), Vector2(c.size.x * 0.5 + 420, 560), 70, UI.YELLOW, 62)
		c.draw_string(f, Vector2(0, 580), "SOWETO FOOTBALL BUILDS DREAMS", HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 44, UI.INK))
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(art)
	var go := UI.label("TAP TO START" if Touch.available() else "PRESS  ENTER  /  START", 48, UI.WHITE, 8)
	go.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	go.grow_horizontal = Control.GROW_DIRECTION_BOTH
	go.offset_top = -330
	p.add_child(go)
	create_tween().set_loops().set_ignore_time_scale(true).tween_property(go, "modulate:a", 0.25, 0.8).from(1.0).set_trans(Tween.TRANS_SINE)
	var b := UI.button("", func() -> void:   # the whole screen is the start button: Enter, pad or a tap
		booted = true
		game.sfx.play("ui_start")
		_go(&"main"))
	b.flat = true
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(b)
	_footer(p, "TITLE PAGE", [["x", "START"]])


func _build_main() -> void:
	var p := _page(&"main")
	_header(p, "MAIN MENU", "PICK YOUR GAME")
	_menu_list(p, 90, 250, 600, [
		["1 PLAYER", _open_stage.bind(false)],
		["2 PLAYERS  ·  LOCAL", _open_stage.bind(true)],
		["2 PLAYERS  ·  LAN", _open_lan],
		["SETTINGS", _open.bind(&"settings")],
		["MUSIC", _open.bind(&"music")],
		["CONTROLS", _open.bind(&"controls")],
		["QUIT", get_tree().quit]])
	var f := UI.font()
	var tag := UI.art(func(c: Control) -> void:
		UI.brush(c, Vector2(0, 150), Vector2(c.size.x, 120), 230, UI.YELLOW, 71)
		UI.crown(c, Rect2(c.size.x * 0.5 - 30, 20, 60, 38), UI.INK)
		c.draw_set_transform(Vector2(c.size.x * 0.5, 120), -0.07, Vector2.ONE)
		for i in 3:
			var line: String = ["SOWETO", "FOOTBALL", "BUILDS DREAMS"][i]
			c.draw_string(f, Vector2(-290, i * 70), line, HORIZONTAL_ALIGNMENT_CENTER, 580, [76, 66, 54][i], UI.INK))
	_put_right(tag, 110, 230, 620, 360)
	p.add_child(tag)
	var card := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 9)
	var v := VBoxContainer.new()
	card.add_child(v)
	v.add_child(UI.label("MATCH SETUP", 30, UI.YELLOW))
	setup_label = UI.label("", 28)
	v.add_child(setup_label)
	p.add_child(card)
	_put_right(card, 110, 640, 620, 190)
	_footer(p, "MAIN MENU", [["x", "SELECT"]])


func _build_stage() -> void:
	var p := _page(&"stage")
	_header(p, "STAGE SELECT", "PICK YOUR BATTLEFIELD")
	var band := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 17)
	band.add_theme_constant_override("margin_top", 26)
	band.add_theme_constant_override("margin_bottom", 26)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	band.add_child(row)
	var defs := [
		["JABULANI CAGE", "4v4  ·  3 + KEEPER\nBIG GOALS", 0, false],
		["JABULANI CAGE", "3v3  ·  NO KEEPERS\nSMALL GOALS", 1, false],
		["???", "COMING SOON", 2, true],
		["???", "COMING SOON", 3, true]]
	for d: Array in defs:
		var c := StageCard.new(d[0], d[1], d[2], d[3])
		c.pressed.connect(_pick_stage.bind(c))
		row.add_child(c)
		stage_cards.append(c)
	p.add_child(band)
	_put(band, 70, 250, 1780, 600)
	_footer(p, "STAGE SELECT", [["x", "SELECT"], ["o", "BACK"]])


func _build_team() -> void:
	var p := _page(&"team")
	var f := UI.font()
	_header(p, "CHARACTER SELECT", "CHOOSE YOUR 3 PLAYERS")
	count_chip = UI.art(func(c: Control) -> void:
		UI.ink_panel(c, Rect2(Vector2.ZERO, c.size), UI.INK, UI.BLUE, 81)
		var info: Dictionary = game.TEAMS[pass_team]
		UI.crest(c, Rect2(18, 12, 34, 36), pass_team, info.color)
		var who := "P%d" % (1 if pass_team == game.human_team else 2)
		c.draw_string(f, Vector2(66, 44), "%s  %d / 3" % [who, sel.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UI.WHITE), Vector2(300, 60))
	_put_right(count_chip, 50, 40, 300, 60)
	p.add_child(count_chip)
	# focused character + their team's stats
	var left := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 12)
	preview = UI.art(_preview_painter, Vector2(344, 560))
	left.add_child(preview)
	p.add_child(left)
	_put(left, 50, 220, 400, 620)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for i in UI.CHARS.size():
		var c := CharCard.new(self, i)
		c.pressed.connect(_toggle_pick.bind(i))
		c.focus_entered.connect(func() -> void:
			focus_idx = i
			preview.queue_redraw())
		grid.add_child(c)
		cards.append(c)
	p.add_child(grid)
	_put(grid, 490, 230, 842, 614)
	# lineup
	var right := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 14)
	lineup = UI.art(_lineup_painter, Vector2(384, 560))
	right.add_child(lineup)
	p.add_child(right)
	_put_right(right, 50, 220, 440, 620)
	# team tabs + confirm
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 20)
	for i in 2:
		var b := UI.button(String(game.TEAMS[i].name), _pick_team.bind(i), 360, 76)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tabs.add_child(b)
		team_tabs.append(b)
	p.add_child(tabs)
	_put(tabs, 490, 868, 800, 76)
	confirm_btn = UI.button("CONFIRM TEAM", _confirm_squad, 440, 90, &"Cta")
	confirm_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_btn.add_theme_font_size_override("font_size", 42)
	p.add_child(confirm_btn)
	_put_right(confirm_btn, 50, 862, 440, 90)
	_footer(p, "CHARACTER SELECT", [["x", "PICK / DROP"], ["o", "BACK"]])


func _preview_painter(c: Control) -> void:
	var f := UI.font()
	var info: Dictionary = game.TEAMS[pass_team]
	var ch: Dictionary = UI.CHARS[focus_idx]
	var order := sel.find(focus_idx)
	UI.brush(c, Vector2(0, 120), Vector2(c.size.x, 120), 230, info.color, 91)
	UI.portrait(c, Rect2(10, 0, c.size.x - 20, 260), ch, info.color.darkened(0.3), info.alt)
	var tag := "CAPTAIN" if order == 0 else ("PICKED  #%d" % (order + 1) if order > 0 else "AVAILABLE")
	UI.brush(c, Vector2(0, 280), Vector2(190, 280), 40, UI.YELLOW, 92)
	c.draw_string(f, Vector2(16, 292), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UI.INK)
	c.draw_string(f, Vector2(0, 336), ch.name, HORIZONTAL_ALIGNMENT_LEFT, c.size.x, 44, UI.WHITE)
	c.draw_string(f, Vector2(0, 366), ch.last, HORIZONTAL_ALIGNMENT_LEFT, c.size.x, 26, Color(1, 1, 1, 0.75))
	c.draw_string(f, Vector2(0, 394), info.name, HORIZONTAL_ALIGNMENT_LEFT, c.size.x, 26, info.alt)
	var stats := [["SPEED", "speed", 7.2], ["STRENGTH", "strength", 1.3], ["SHOT", "shot", 1.18], ["TACKLE", "tackle_range", 1.4], ["PASSING", "pass_speed", 17.0]]
	for i in stats.size():
		var y := 424.0 + i * 26.0
		c.draw_string(f, Vector2(0, y + 18), stats[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.WHITE)
		c.draw_rect(Rect2(140, y + 4, 200, 14), Color(1, 1, 1, 0.14))
		c.draw_rect(Rect2(140, y + 4, 200.0 * clampf(float(info[stats[i][1]]) / (stats[i][2] * 1.05), 0.1, 1.0), 14), UI.YELLOW)


func _lineup_painter(c: Control) -> void:
	var f := UI.font()
	var info: Dictionary = game.TEAMS[pass_team]
	c.draw_string(f, Vector2(0, 40), "TEAM LINEUP", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UI.WHITE)
	var roles := ["CENTRE  ·  KICK-OFF", "LEFT WING", "RIGHT WING"]
	var n := 4 if game.has_keeper() else 3
	var h := 118.0
	for i in n:
		var y := 64.0 + i * (h + 6)
		var is_gk := i == 3
		var r := Rect2(0, y, c.size.x, h)
		UI.ink_panel(c, r, Color(UI.INK2, 0.9), info.alt if (i == 0 and sel.size() > 0) else UI.BLUE, i + 120)
		if is_gk:
			UI.portrait(c, Rect2(10, y + 8, 100, h - 14), UI.KEEPERS[pass_team], info.keeper, info.alt)
			c.draw_string(f, Vector2(124, y + 44), UI.KEEPERS[pass_team].name + " \"" + UI.KEEPERS[pass_team].nick + "\"", HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 130, 28, UI.WHITE)
			c.draw_string(f, Vector2(124, y + 78), "GOALKEEPER  ·  DEFAULT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, info.keeper)
			continue
		if i < sel.size():
			var ch: Dictionary = UI.CHARS[sel[i]]
			UI.portrait(c, Rect2(10, y + 8, 100, h - 14), ch, info.color, info.alt)
			c.draw_string(f, Vector2(124, y + 40), ch.name, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 170, 30, UI.WHITE)
			if i == 0:
				UI.crown(c, Rect2(c.size.x - 52, y + 16, 34, 22), UI.YELLOW)
			var kind: int = info.sigs[i + 1]
			c.draw_string(f, Vector2(124, y + 70), roles[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.7))
			c.draw_rect(Rect2(124, y + 82, 16, 16), Vessel.KINDS[kind].color)
			c.draw_string(f, Vector2(148, y + 97), "%s SOUL" % Vessel.KINDS[kind].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Vessel.KINDS[kind].color)
		else:
			c.draw_string(f, Vector2(24, y + 52), "EMPTY SLOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.35))
			c.draw_string(f, Vector2(24, y + 86), roles[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.25))


func _build_settings() -> void:
	var p := _page(&"settings")
	_header(p, "SETTINGS")
	var names := ["GAMEPLAY", "AUDIO", "GRAPHICS", "RESET"]
	var side := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 21)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 10)
	side.add_child(tv)
	for i in names.size():
		var b := UI.button(names[i], _tab_enter.bind(i), 380, 76, &"Tab")
		b.focus_entered.connect(_show_tab.bind(i))
		tv.add_child(b)
		tab_buttons.append(b)
	p.add_child(side)
	_put(side, 90, 230, 440, 4 * 86 + 40)
	var panel := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 22)
	var host := Control.new()
	host.custom_minimum_size = Vector2(840, 440)
	panel.add_child(host)
	p.add_child(panel)
	_put(panel, 580, 230, 920, 520)
	for i in 4:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 12)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(v)
		tab_panels.append(v)
	var g: Control = tab_panels[0]
	_row(g, "DIFFICULTY", func() -> String: return Game.DIFFS[game.difficulty].name,
			func(d: int) -> void: game.difficulty = _wrap(game.difficulty, d, Game.DIFFS.size()))
	_row(g, "MATCH MODE", func() -> String: return "STREET · TIMED" if game.street else "BRICKS · GOAL SHRINKS",
			func(_d: int) -> void: game.street = not game.street, true)
	time_row = _row(g, "MATCH TIME", func() -> String: return "%d MINS" % roundi(game.street_time / 60.0),
			func(d: int) -> void: game.street_time = Game.STREET_TIMES[_wrap(Game.STREET_TIMES.find(game.street_time), d, Game.STREET_TIMES.size())])
	_row(g, "FORMAT", func() -> String: return "4v4 · KEEPERS" if game.has_keeper() else "3v3 · NO KEEPERS", _toggle_format, true)
	_row(g, "HUD", func() -> String: return _on_off(game.hud.enabled),
			func(_d: int) -> void: game.hud.set_enabled(not game.hud.enabled))
	var a: Control = tab_panels[1]
	_row(a, "MASTER VOLUME", func() -> String: return "%d%%" % roundi(vol.master * 100), func(d: int) -> void: _set_vol("master", d))
	_row(a, "MUSIC VOLUME", func() -> String: return "%d%%" % roundi(vol.music * 100), func(d: int) -> void: _set_vol("music", d))
	_row(a, "SHUFFLE", func() -> String: return _on_off(Jukebox.shuffle),
			func(_d: int) -> void:
				Jukebox.shuffle = not Jukebox.shuffle
				_refresh_music())
	var gr: Control = tab_panels[2]
	_row(gr, "WINDOW", func() -> String: return "FULLSCREEN" if get_window().mode == Window.MODE_FULLSCREEN else "WINDOWED",
			func(_d: int) -> void: get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN)
	_row(gr, "VSYNC", func() -> String: return _on_off(DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED),
			func(_d: int) -> void: DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_DISABLED if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else DisplayServer.VSYNC_ENABLED))
	var rs: Control = tab_panels[3]
	rs.add_child(UI.label("Put every setting back to its default.", 26))
	rs.add_child(UI.button("RESET TO DEFAULTS", _reset_settings, 520, 72))
	_footer(p, "SETTINGS MENU", [["x", "SELECT"], ["o", "BACK"]])
	_show_tab(0)


func _show_tab(i: int) -> void:
	tab_cur = i
	for j in tab_panels.size():
		tab_panels[j].visible = j == i
		tab_buttons[j].theme_type_variation = &"Cta" if j == i else &"Tab"


func _tab_enter(i: int) -> void:
	_show_tab(i)
	var b := _first_button(tab_panels[i])
	if b:
		b.grab_focus()


func _build_controls() -> void:
	var p := _page(&"controls")
	_header(p, "CONTROLS")
	var panel := UI.Ink.new(Color(UI.INK, 0.92), UI.BLUE, 31)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 50)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var data := [
		["", "PLAYER 1  ·  KEYBOARD / PAD", "PLAYER 2  ·  LOCAL"],
		["MOVE", "WASD  /  L-STICK", "ARROWS"],
		["PASS / SWITCH", "J or F  /  A", ","],
		["SHOOT / TACKLE", "K or G  /  B", "."],
		["SKILL / DODGE", "L or T  /  Y", ";"],
		["SPRINT", "L-SHIFT  /  RT", "R-SHIFT"],
		["SOUL", "Q  /  LB", "'"],
		["PAUSE", "ESC  /  START", "ESC  /  START"]]
	for r in data.size():
		for c in 3:
			var l := UI.label(data[r][c], 28 if r > 0 else 24, UI.YELLOW if (c == 0 or r == 0) else UI.WHITE, 4)
			l.custom_minimum_size = Vector2([300, 460, 300][c], 0)
			g.add_child(l)
	var tips := UI.label("SOUL (Q / LB):  tap = Burst Sprint (Stirring)  ·  hold + Pass = Vision Pass  ·  hold + Shoot = Soul Shot (Possessed)  ·  hold + Skill = Curve (Possessed)\n"
			+ "Beat players to feed the ball and steal their soul  ·  Pass to steady it (every 2nd pass charges it)  ·  Lose it and the souls turn  ·  BRICKS: overloaded goal = 2 bricks", 20, UI.WHITE, 4)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD
	tips.custom_minimum_size = Vector2(1100, 0)
	v.add_child(tips)
	var back := UI.button("BACK", func() -> void: _go(back_to), 240, 64)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)
	p.add_child(panel)
	_put(panel, 90, 230, 1180, 540)
	_footer(p, "CONTROLS", [["o", "BACK"]])


func _build_pause() -> void:
	var p := _page(&"pause")
	var f := UI.font()
	var hd := UI.art(func(c: Control) -> void:
		UI.brush(c, Vector2(-20, 40), Vector2(c.size.x, 36), 80, UI.INK, 141)
		UI.crown(c, Rect2(50, 4, 40, 26), UI.YELLOW)
		c.draw_string(f, Vector2(100, 56), "SOUL", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, UI.WHITE)
		c.draw_string(f, Vector2(250, 56), "SOCCER", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, UI.YELLOW)
		UI.brush(c, Vector2(40, 106), Vector2(c.size.x - 20, 104), 50, UI.YELLOW, 142)
		c.draw_string(f, Vector2(90, 118), "PAUSE  /  MATCH MENU", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UI.INK))
	_put(hd, 640, 150, 640, 140)
	p.add_child(hd)
	var pause_list := _menu_list(p, 660, 300, 600, [
		["RESUME", resume],
		["SETTINGS", _open.bind(&"settings")],
		["MUSIC", _open.bind(&"music")],
		["CONTROLS", _open.bind(&"controls")],
		["RESTART MATCH", _restart],
		["QUIT TO MENU", _to_title]], 5)
	restart_btn = pause_list.get_child(0).get_child(4)


# ------------------------------------------------------------------ LAN (one pair: host = P1, client = P2)

func _open_lan() -> void:
	back_to = &"main"
	lan_info.text = ""
	lan_ip.visible = false
	for c in lan_list.get_children():
		c.queue_free()
	_go(&"lan")


func _build_lan() -> void:
	var p := _page(&"lan")
	_header(p, "LAN PLAY", "TWO DEVICES  ·  SAME WI-FI")
	lan_menu = _menu_list(p, 90, 250, 600, [
		["HOST A GAME", _lan_host],
		["JOIN A GAME", _lan_join],
		["BACK", func() -> void: _go(&"main")]], 7)
	var panel := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 63)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	lan_info = UI.label("", 30)
	lan_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	lan_info.custom_minimum_size = Vector2(920, 0)
	v.add_child(lan_info)
	lan_list = VBoxContainer.new()
	lan_list.add_theme_constant_override("separation", 10)
	v.add_child(lan_list)
	lan_ip = LineEdit.new()
	lan_ip.placeholder_text = "OR TYPE THE HOST IP, e.g. 192.168.1.5"
	lan_ip.custom_minimum_size = Vector2(920, 64)
	lan_ip.add_theme_font_size_override("font_size", 30)
	lan_ip.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	lan_ip.text_submitted.connect(func(t: String) -> void: _lan_connect(t))
	lan_ip.visible = false
	v.add_child(lan_ip)
	p.add_child(panel)
	_put(panel, 760, 250, 1040, 560)
	_footer(p, "LAN PLAY", [["x", "SELECT"], ["o", "BACK"]])


func _lan_host() -> void:
	if not game.net.host():
		lan_info.text = "COULD NOT START HOSTING.\nIS ANOTHER COPY OF THE GAME ALREADY HOSTING?"
		return
	lan_ip.visible = false
	for c in lan_list.get_children():
		c.queue_free()
	var ips := game.net.local_ips()
	lan_info.text = "HOSTING  ·  YOU ARE PLAYER 1\nWAITING FOR PLAYER 2 TO JOIN...\n\nTHEY SHOULD SEE YOU AUTOMATICALLY. IF NOT, TYPE:  %s" % ("  /  ".join(ips) if ips.size() > 0 else "(connect to Wi-Fi first)")
	var b := UI.button("CANCEL", _lan_back, 300, 64)
	lan_list.add_child(b)
	b.call_deferred("grab_focus")


func _lan_join() -> void:
	game.net.search()
	lan_ip.visible = true
	_lan_refresh()


func _lan_refresh() -> void:
	if current != &"lan" or game.net.mode != Net.Mode.OFF:
		return
	for c in lan_list.get_children():
		c.queue_free()
	lan_info.text = "SEARCHING FOR A HOST ON THIS WI-FI..." if game.net.hosts.is_empty() else "TAP A GAME TO JOIN:"
	for ip: String in game.net.hosts:
		lan_list.add_child(UI.button("%s   ·   %s" % [game.net.hosts[ip].name, ip], _lan_connect.bind(ip), 900, 64))


func _lan_connect(ip: String) -> void:
	if ip.strip_edges() == "" or not game.net.join(ip):
		lan_info.text = "THAT ADDRESS DOES NOT WORK."
		return
	lan_ip.visible = false
	for c in lan_list.get_children():
		c.queue_free()
	lan_info.text = "CONNECTING TO %s ..." % ip


## Leave the LAN set-up from any page: drop the link and go back to the main menu.
func _lan_back() -> void:
	game.net.close()
	game.sfx.play("ui_back")
	_go(&"main")


func _net_linked() -> void:
	if not game.net.linked or current != &"lan":
		return
	if Net.is_host():
		_open_stage(true)   # the host sets the match up, player 2 picks their squad later
	else:
		lan_info.text = "CONNECTED  ·  YOU ARE PLAYER 2\nWAITING FOR THE HOST TO SET UP THE MATCH..."
		var b := UI.button("LEAVE", _lan_back, 300, 64)
		lan_list.add_child(b)
		b.call_deferred("grab_focus")


## Client: the host wants my three.
func net_pick() -> void:
	two_p = true
	_begin_squad(1 - game.human_team)
	_go(&"team")


## Client: the match is on.
func net_begin() -> void:
	_go(NONE)


## Host: player 2 picked, go.
func net_started() -> void:
	_start(true)


func _build_wait() -> void:
	var p := _page(&"wait")
	_header(p, "PLEASE WAIT")
	var panel := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 64)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	panel.add_child(v)
	wait_label = UI.label("", 36)
	v.add_child(wait_label)
	v.add_child(UI.button("CANCEL", _lan_back, 300, 64))
	p.add_child(panel)
	_put(panel, 90, 250, 1100, 240)


func _wait(text: String) -> void:
	wait_label.text = text
	_go(&"wait")


## A short note on whatever page is showing (link lost, etc).
func toast(text: String) -> void:
	var l := UI.label(text, 44, UI.YELLOW, 10)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.offset_top = 40
	root.add_child(l)
	var tw := l.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _build_music() -> void:
	var p := _page(&"music")
	var f := UI.font()
	_header(p, "MUSIC")
	var left := UI.Ink.new(Color(UI.INK, 0.9), UI.BLUE, 41)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	song_list = VBoxContainer.new()
	song_list.add_theme_constant_override("separation", 6)
	sc.add_child(song_list)
	left.add_child(sc)
	p.add_child(left)
	_put(left, 90, 230, 640, 500)
	music_card = UI.art(func(c: Control) -> void:
		UI.ink_panel(c, Rect2(Vector2.ZERO, c.size), Color(UI.INK, 0.92), UI.BLUE, 42)
		UI.brush(c, Vector2(20, 130), Vector2(c.size.x - 20, 130), 220, UI.BLUE, 43)
		UI.portrait(c, Rect2(60, 20, c.size.x - 120, 230), UI.CHARS[7], UI.INK2, UI.YELLOW)
		c.draw_arc(Vector2(c.size.x / 2.0, 118), 92, PI * 1.05, PI * 1.95, 24, UI.YELLOW, 12.0, true)
		var title := String(Jukebox.now_playing()) if Jukebox.index >= 0 else "No songs yet"
		c.draw_string(f, Vector2(24, 296), title, HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 48, 40, UI.WHITE)
		var dur := 0.0
		var pos := 0.0
		if Jukebox.player.stream:
			dur = Jukebox.player.stream.get_length()
			pos = Jukebox.player.get_playback_position()
		c.draw_rect(Rect2(24, 324, c.size.x - 48, 8), Color(1, 1, 1, 0.2))
		if dur > 0.0:
			c.draw_rect(Rect2(24, 324, (c.size.x - 48) * clampf(pos / dur, 0.0, 1.0), 8), UI.YELLOW)
		c.draw_string(f, Vector2(24, 366), "%d:%02d" % [int(pos) / 60, int(pos) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.WHITE)
		c.draw_string(f, Vector2(0, 366), "%d:%02d" % [int(dur) / 60, int(dur) % 60], HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 24, 22, UI.WHITE), Vector2(480, 390))
	p.add_child(music_card)
	_put(music_card, 780, 230, 480, 390)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for it: Array in [["PREV", Jukebox.prev, 130], ["PAUSE", Jukebox.toggle, 160], ["NEXT", Jukebox.next, 130], ["SHUFFLE", _toggle_shuffle, 220]]:
		var b := UI.button(it[0], it[1], it[2], 64)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 28)
		row.add_child(b)
		if it[0] == "PAUSE":
			play_btn = b
		if it[0] == "SHUFFLE":
			shuffle_btn = b
	p.add_child(row)
	_put(row, 780, 640, 480, 64)
	_footer(p, "MUSIC MENU", [["x", "SELECT"], ["o", "BACK"]])


func _toggle_shuffle() -> void:
	Jukebox.shuffle = not Jukebox.shuffle
	_refresh_music()


func _refresh_music() -> void:
	if not song_list:
		return
	play_btn.text = "PAUSE" if Jukebox.is_playing() else "PLAY"
	shuffle_btn.text = "SHUFFLE " + ("ON" if Jukebox.shuffle else "OFF")
	for c in song_list.get_children():
		c.queue_free()
	if Jukebox.songs.is_empty():
		var l := UI.label("Drop audio files (mp3 / ogg / wav) into res://sounds/music/", 22)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(500, 0)
		song_list.add_child(l)
	for i in Jukebox.songs.size():
		var b := UI.button(("▶  " if i == Jukebox.index else "     ") + String(Jukebox.songs[i].title), Jukebox.play_index.bind(i), 540, 52)
		b.add_theme_font_size_override("font_size", 26)
		if i == Jukebox.index:
			b.theme_type_variation = &"Cta"
		song_list.add_child(b)
	if current == &"music":
		play_btn.call_deferred("grab_focus")   # a rebuilt song button may have held focus
