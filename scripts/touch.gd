class_name Touch
extends CanvasLayer
## On-screen pad for phones: a floating stick on the left half, action buttons on the right, a pause chip.
## It only injects the ordinary input actions, so the game (and the LAN client) cannot tell it from a keyboard.

const STICK_R := 150.0
const BTNS := [   # action, label, centre (1920x1080 canvas), radius, colour
	["shoot", "SHOT", Vector2(1730, 900), 105.0, UI.RED],
	["pass", "PASS", Vector2(1490, 940), 85.0, UI.BLUE],
	["skill", "SKILL", Vector2(1530, 720), 80.0, UI.WHITE],
	["ability", "SOUL", Vector2(1770, 680), 80.0, Color("b04dff")],
	["sprint", "RUN", Vector2(1290, 880), 70.0, Color("39ff14")],
]
const PAUSE := Rect2(40, 140, 110, 90)

var game: Game
var pad: Control
var stick_id := -1
var stick_c := Vector2.ZERO
var stick_v := Vector2.ZERO
var held := {}          # touch index -> button index
var _on := {}           # action -> bool currently pressed by us


static func available() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	pad = UI.art(_paint)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pad)


func _process(_d: float) -> void:
	var live := game.state != Game.S.TITLE and game.menu.current == Menu.NONE
	if live != visible:
		visible = live
		if not live:
			_release_all()
	if visible:
		pad.queue_redraw()


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventScreenTouch:
		var p := _canvas(e.position)
		if e.pressed:
			_down(e.index, p)
		else:
			_up(e.index)
	elif e is InputEventScreenDrag and e.index == stick_id:
		var d := _canvas(e.position) - stick_c
		stick_v = d / STICK_R if d.length() < STICK_R else d.normalized()
		_axes()


## Screen -> the 1920x1080 canvas the layout is drawn in.
func _canvas(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


func _down(idx: int, p: Vector2) -> void:
	if game.state == Game.S.OVER:
		_tap("start")
		return
	if PAUSE.grow(14).has_point(p):
		game.menu.pause()
		return
	for i in BTNS.size():
		if p.distance_to(BTNS[i][2]) < BTNS[i][3] * 1.2:
			held[idx] = i
			_hold(BTNS[i][0], true)
			return
	if p.x < 1000.0 and stick_id < 0:
		stick_id = idx
		stick_c = p
		stick_v = Vector2.ZERO


func _up(idx: int) -> void:
	if held.has(idx):
		_hold(BTNS[held[idx]][0], false)
		held.erase(idx)
	elif idx == stick_id:
		stick_id = -1
		stick_v = Vector2.ZERO
		_axes()


func _axes() -> void:
	var v := stick_v if stick_v.length() > 0.2 else Vector2.ZERO
	_strength("move_left", maxf(-v.x, 0.0))
	_strength("move_right", maxf(v.x, 0.0))
	_strength("move_up", maxf(-v.y, 0.0))
	_strength("move_down", maxf(v.y, 0.0))


func _strength(a: String, s: float) -> void:
	if is_equal_approx(_on.get(a, 0.0), s):
		return
	_on[a] = s
	if s > 0.0:
		Input.action_press(a, s)
	else:
		Input.action_release(a)


func _hold(a: String, on: bool) -> void:
	_strength(a, 1.0 if on else 0.0)


func _tap(a: String) -> void:
	Input.action_press(a)
	get_tree().create_timer(0.1, true, false, true).timeout.connect(Input.action_release.bind(a))


func _release_all() -> void:
	held.clear()
	stick_id = -1
	stick_v = Vector2.ZERO
	_axes()
	for b in BTNS:
		_hold(b[0], false)


func _paint(c: Control) -> void:
	var f := UI.font()
	for i in BTNS.size():
		var b: Array = BTNS[i]
		var down := held.values().has(i)
		c.draw_circle(b[2], b[3], Color(UI.INK, 0.55 if not down else 0.85))
		c.draw_arc(b[2], b[3], 0.0, TAU, 40, Color(b[4], 0.95 if down else 0.6), 6.0, true)
		var s := 26 if b[3] < 90.0 else 32
		c.draw_string(f, b[2] + Vector2(-b[3], s * 0.35), b[1], HORIZONTAL_ALIGNMENT_CENTER, b[3] * 2.0, s, UI.WHITE)
	var base := stick_c if stick_id >= 0 else Vector2(250, 840)
	c.draw_circle(base, STICK_R, Color(UI.INK, 0.4))
	c.draw_arc(base, STICK_R, 0.0, TAU, 48, Color(UI.WHITE, 0.45), 5.0, true)
	c.draw_circle(base + stick_v * STICK_R * 0.7, 58.0, Color(UI.WHITE, 0.55 if stick_id >= 0 else 0.3))
	c.draw_rect(PAUSE, Color(UI.INK, 0.6))
	c.draw_rect(PAUSE, Color(UI.WHITE, 0.6), false, 4.0)
	c.draw_string(f, PAUSE.position + Vector2(0, 58), "II", HORIZONTAL_ALIGNMENT_CENTER, PAUSE.size.x, 44, UI.WHITE)
