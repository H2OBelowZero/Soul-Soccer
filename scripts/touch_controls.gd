class_name TouchControls
extends CanvasLayer
## On-screen controls for phones and tablets. Floating left-thumb stick + right-thumb action cluster.
## It never reads gameplay state: it only presses / releases the same InputMap actions the keyboard and pad use,
## so Player, Menu and Game need no touch-specific input code. Multi-touch is tracked per finger index.
## Desktop testing: launch with `-- --touch`.

const STICK_R := 120.0          # radius the thumb has to travel for full tilt
const SPRINT_AT := 0.9          # tilt past this fraction = sprint (outer ring)
const DEAD := 0.12
const BTN_ALPHA := 0.62

## name -> {action, label, col, r (radius), at (offset from the bottom-right anchor), toggle}
const BUTTONS := {
	"shoot": {"action": "shoot", "label": "SHOT", "col": Color("ff3b3b"), "r": 112.0, "at": Vector2(-190, -200)},
	"pass": {"action": "pass", "label": "PASS", "col": Color("1e9bff"), "r": 92.0, "at": Vector2(-410, -130)},
	"skill": {"action": "skill", "label": "SKILL", "col": Color("ffe600"), "r": 84.0, "at": Vector2(-120, -420)},
	"ability": {"action": "ability", "label": "SOUL", "col": Color("b04dff"), "r": 84.0, "at": Vector2(-340, -340)},
	"sprint": {"action": "sprint", "label": "RUN", "col": Color("2de2e6"), "r": 62.0, "at": Vector2(-530, -300), "toggle": true},
}
const MOVE_ACTIONS := ["move_left", "move_right", "move_up", "move_down"]

var game: Game
var active := false

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_rest := Vector2.ZERO
var _fingers := {}              # finger index -> button name
var _held := {}                 # button name -> true while pressed
var _latched := {}              # toggle buttons that are switched on
var _pause_finger := -1
var _tap_finger := -1
var _view := Vector2(1920, 1080)
var _safe := Rect2()            # safe area in viewport coordinates
var _canvas: TouchCanvas


static func enabled() -> bool:
	return OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()


## Draws everything; owns no state of its own.
class TouchCanvas extends Control:
	var tc: TouchControls

	func _draw() -> void:
		tc._paint(self)


func _ready() -> void:
	layer = 6   # above the HUD (5), below the menus (10)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = TouchCanvas.new()
	_canvas.tc = self
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_set_active(false)


func _process(_d: float) -> void:
	var playing := game.state in [Game.S.KICKOFF, Game.S.PLAY, Game.S.GOAL] \
			and game.menu.current == Menu.NONE and not get_tree().paused
	if playing != active:
		_set_active(playing)
	if active:
		_canvas.queue_redraw()


## Viewport size and safe area (notch / gesture bar) in viewport coordinates.
func _layout() -> void:
	_view = get_viewport().get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	_safe = Rect2(Vector2.ZERO, _view)
	if win.x > 0.0 and win.y > 0.0 and safe.size.x > 0.0:
		var k := _view / win
		var r := Rect2(safe.position * k, safe.size * k)
		_safe = Rect2(Vector2.ZERO, _view).intersection(r)
		if _safe.size.x < _view.x * 0.5:   # nonsense from the OS: ignore it
			_safe = Rect2(Vector2.ZERO, _view)
	_stick_rest = Vector2(_safe.position.x + 270.0, _safe.end.y - 250.0)


func _btn_pos(b: Dictionary) -> Vector2:
	return Vector2(_safe.end.x, _safe.end.y) + (b.at as Vector2)


func _pause_rect() -> Rect2:
	return Rect2(_safe.end.x - 150.0, _safe.position.y + 20.0, 120.0, 90.0)


func _set_active(on: bool) -> void:
	active = on
	_canvas.visible = on
	if not on:
		_release_all()


func _release_all() -> void:
	_stick_finger = -1
	_pause_finger = -1
	_fingers.clear()
	_held.clear()
	_latched.clear()
	for a in MOVE_ACTIONS:
		Input.action_release(a)
	for k: String in BUTTONS:
		Input.action_release(BUTTONS[k].action)


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if game.state == Game.S.OVER and game.menu.current == Menu.NONE:
		var t := event as InputEventScreenTouch
		if t != null and t.pressed:
			game.to_title()
			get_viewport().set_input_as_handled()
		return
	if not active:
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_down(touch.index, touch.position)
		else:
			_up(touch.index)
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		if drag.index == _stick_finger:
			_stick_pos = drag.position
			_apply_stick()
		get_viewport().set_input_as_handled()


func _down(finger: int, p: Vector2) -> void:
	if _pause_rect().grow(18.0).has_point(p):
		_pause_finger = finger
		game.menu.pause()
		return
	for k: String in BUTTONS:
		var b: Dictionary = BUTTONS[k]
		if p.distance_to(_btn_pos(b)) <= b.r + 26.0:
			_fingers[finger] = k
			if b.get("toggle", false):
				_latched[k] = not _latched.get(k, false)
				_drive(k, _latched[k])
			else:
				_held[k] = true
				_drive(k, true)
			return
	if _stick_finger == -1 and p.x < _view.x * 0.55:
		_stick_finger = finger
		_stick_origin = p
		_stick_pos = p
		_apply_stick()


func _up(finger: int) -> void:
	if finger == _stick_finger:
		_stick_finger = -1
		_apply_stick()
	if finger == _pause_finger:
		_pause_finger = -1
	if _fingers.has(finger):
		var k: String = _fingers[finger]
		_fingers.erase(finger)
		if not BUTTONS[k].get("toggle", false):
			_held.erase(k)
			_drive(k, false)


func _drive(button: String, down: bool) -> void:
	var a: String = BUTTONS[button].action
	if down:
		Input.action_press(a)
	else:
		Input.action_release(a)


## Stick -> move_* actions (analog strength) + sprint when pushed to the outer ring.
func _apply_stick() -> void:
	var v := Vector2.ZERO
	if _stick_finger != -1:
		v = (_stick_pos - _stick_origin) / STICK_R
		if v.length() > 1.0:
			_stick_origin = _stick_pos - v.normalized() * STICK_R   # the stick follows the thumb
			v = v.normalized()
		if v.length() < DEAD:
			v = Vector2.ZERO
	_set_axis("move_left", "move_right", v.x)
	_set_axis("move_up", "move_down", v.y)
	var run: bool = v.length() >= SPRINT_AT or _latched.get("sprint", false)
	if run:
		Input.action_press("sprint")
	elif not _held.has("sprint"):
		Input.action_release("sprint")


func _set_axis(neg: String, pos: String, v: float) -> void:
	if v < 0.0:
		Input.action_press(neg, -v)
		Input.action_release(pos)
	elif v > 0.0:
		Input.action_press(pos, v)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


# ------------------------------------------------------------------ drawing

func _paint(c: Control) -> void:
	var f := UI.font()
	# stick
	var base := _stick_origin if _stick_finger != -1 else _stick_rest
	var knob := base
	if _stick_finger != -1:
		knob = base + (_stick_pos - base).limit_length(STICK_R)
	var running: bool = _stick_finger != -1 and (knob - base).length() >= STICK_R * SPRINT_AT
	c.draw_circle(base, STICK_R + 28.0, Color(UI.INK, 0.35))
	c.draw_arc(base, STICK_R + 28.0, 0.0, TAU, 64, Color(UI.YELLOW if running else UI.WHITE, 0.5), 5.0)
	c.draw_arc(base, STICK_R * SPRINT_AT * 0.78, 0.0, TAU, 48, Color(UI.WHITE, 0.14), 3.0)
	c.draw_circle(knob, 58.0, Color(UI.YELLOW if running else UI.WHITE, 0.75 if _stick_finger != -1 else 0.4))
	c.draw_arc(knob, 58.0, 0.0, TAU, 40, UI.INK, 5.0)
	# action buttons
	for k: String in BUTTONS:
		var b: Dictionary = BUTTONS[k]
		var pos := _btn_pos(b)
		var down: bool = _held.has(k) or _latched.get(k, false)
		var r: float = b.r * (0.92 if down else 1.0)
		var col: Color = b.col
		c.draw_circle(pos, r + 6.0, UI.INK)
		c.draw_circle(pos, r, Color(col, 1.0 if down else BTN_ALPHA))
		c.draw_arc(pos, r - 4.0, 0.0, TAU, 48, Color(1, 1, 1, 0.55 if down else 0.3), 4.0)
		var fs := int(r * 0.4)
		var w := f.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tone: Color = UI.INK if k in ["skill", "sprint"] else UI.WHITE
		c.draw_string(f, pos + Vector2(-w / 2.0, fs * 0.35), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tone)
	# pause
	var pr := _pause_rect()
	c.draw_rect(pr, Color(UI.INK, 0.6))
	c.draw_rect(pr, Color(UI.WHITE, 0.55), false, 4.0)
	var cx := pr.get_center()
	c.draw_rect(Rect2(cx + Vector2(-22, -22), Vector2(14, 44)), UI.WHITE)
	c.draw_rect(Rect2(cx + Vector2(8, -22), Vector2(14, 44)), UI.WHITE)
