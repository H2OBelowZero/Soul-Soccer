class_name UI
extends RefCounted
## Street-graffiti UI kit (black ink panels, electric blue, hazard yellow, brush slashes).
## One shared Theme, a few procedural painters (brush strokes, crowns, crests, portraits, skyline)
## and small widgets. Everything is drawn from code: no art files.

const INK := Color("0a0d16")
const INK2 := Color("141a2b")
const YELLOW := Color("ffe600")
const BLUE := Color("1e9bff")
const SKY := Color("42b6ff")
const DEEP := Color("0b4f9e")
const WHITE := Color("f4f7ff")
const RED := Color("ff3b3b")

const SKEW := -0.18   # the italic slant shared by type and slabs

## Roster pool for the character select. Cosmetic only: look and name. Gameplay stays tied to the team slot.
## hair: 0 curls · 1 bald · 2 braids · 3 cap · 4 afro · 5 headband
const CHARS := [
	{"name": "AIDEN", "last": "JACOBS", "nick": "ACE", "skin": Color("7a4a2e"), "hair": 0, "hc": Color("14110f"), "tone": Color("ffe600")},
	{"name": "SIBUSISO", "last": "ZULU", "nick": "TEMPO", "skin": Color("5a3825"), "hair": 1, "hc": Color("14110f"), "tone": Color("ff3b3b")},
	{"name": "LUVO", "last": "MBEKI", "nick": "GRANITE", "skin": Color("3e2618"), "hair": 5, "hc": Color("14110f"), "tone": Color("1e9bff")},
	{"name": "KYLE", "last": "VAN DER MERWE", "nick": "FLASH", "skin": Color("e0b08a"), "hair": 3, "hc": Color("f2c94c"), "tone": Color("ffe600")},
	{"name": "ZARA", "last": "NAIDOO", "nick": "ZEE", "skin": Color("8d5a3b"), "hair": 2, "hc": Color("1b120d"), "tone": Color("ff3b3b")},
	{"name": "THANDO", "last": "KHUMALO", "nick": "TIGER", "skin": Color("4a2e1e"), "hair": 4, "hc": Color("0d0b0a"), "tone": Color("39ff14")},
	{"name": "NALEDI", "last": "DLAMINI", "nick": "NOVA", "skin": Color("6b4028"), "hair": 2, "hc": Color("2a1a12"), "tone": Color("b04dff")},
	{"name": "JABU", "last": "NDLOVU", "nick": "JAZZ", "skin": Color("8d5a3b"), "hair": 0, "hc": Color("2a1a12"), "tone": Color("1e9bff")},
]
## Default keepers (one per team, not pickable).
const KEEPERS := [
	{"name": "THABO", "last": "MAHLANGU", "nick": "WALL", "skin": Color("5a3825"), "hair": 1, "hc": Color("14110f"), "tone": Color("2de2e6")},
	{"name": "SIZWE", "last": "RADEBE", "nick": "GLOVES", "skin": Color("3e2618"), "hair": 5, "hc": Color("14110f"), "tone": Color("39ff14")},
]

static var _theme: Theme
static var _font: FontVariation
static var _font_flat: SystemFont


## Impact, sheared into an italic slab face.
static func font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = Arena.font()
		_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(SKEW, 1), Vector2.ZERO)
	return _font


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 30
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_outline_color", "Label", Color.BLACK)
	t.set_constant("outline_size", "Label", 6)
	# Menu row: ink slab, goes hazard-yellow with black type on focus.
	t.set_font("font", "Button", font())
	t.set_font_size("font_size", "Button", 34)
	for c: String in ["font_color", "font_pressed_color"]:
		t.set_color(c, "Button", WHITE)
	for c: String in ["font_focus_color", "font_hover_color", "font_hover_pressed_color", "font_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_stylebox("normal", "Button", slab(Color(INK, 0.88), Color(BLUE, 0.55), false))
	t.set_stylebox("hover", "Button", slab(YELLOW, WHITE, true))
	t.set_stylebox("focus", "Button", slab(YELLOW, WHITE, true))
	t.set_stylebox("pressed", "Button", slab(WHITE, YELLOW, true))
	t.set_stylebox("disabled", "Button", slab(Color(INK, 0.5), Color(1, 1, 1, 0.1), false))
	# Variation: the big call-to-action (CONFIRM / PRESS START).
	t.add_type("Cta")
	t.set_type_variation("Cta", "Button")
	t.set_stylebox("normal", "Cta", slab(YELLOW, INK, true))
	t.set_color("font_color", "Cta", INK)
	t.set_stylebox("focus", "Cta", slab(WHITE, YELLOW, true))
	t.set_stylebox("hover", "Cta", slab(WHITE, YELLOW, true))
	# Variation: bare tab on the left of a settings page.
	t.add_type("Tab")
	t.set_type_variation("Tab", "Button")
	t.set_stylebox("normal", "Tab", slab(Color(INK, 0.9), Color(BLUE, 0.35), false))
	_theme = t
	return t


## Skewed slab stylebox. `lit` slabs get a thick contrasting edge.
static func slab(fill: Color, edge: Color, lit: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(0)
	s.border_width_bottom = 3
	if lit:
		s.set_border_width_all(4)
		s.border_width_left = 10
	s.skew = Vector2(SKEW, 0)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


# ------------------------------------------------------------------ painting

## A Control that paints itself with a Callable(canvas: Control). Resizes redraw.
class Art extends Control:
	var painter: Callable

	func _init(p: Callable = Callable()) -> void:
		painter = p
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## A container that paints a ragged ink panel behind its children.
class Ink extends MarginContainer:
	var fill := UI.INK
	var edge := UI.BLUE
	var seed_n := 1

	func _init(f := UI.INK, e := UI.BLUE, s := 1) -> void:
		fill = f
		edge = e
		seed_n = s
		for side in ["left", "right"]:
			add_theme_constant_override("margin_" + side, 28)
		for side in ["top", "bottom"]:
			add_theme_constant_override("margin_" + side, 20)
		resized.connect(queue_redraw)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		UI.ink_panel(self, Rect2(Vector2.ZERO, size), fill, edge, seed_n)


static func art(p: Callable, min_size := Vector2.ZERO) -> Art:
	var a := Art.new(p)
	a.custom_minimum_size = min_size
	return a


## Ragged-edged slanted panel: a dark fill, a blue rim and a few chipped corners.
static func ink_panel(c: Control, r: Rect2, fill: Color, edge: Color, seed_n := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n * 7919
	var k := 14.0
	var corners := [r.position + Vector2(k, 0), r.position + Vector2(r.size.x, 0), r.position + Vector2(r.size.x - k, r.size.y), r.position + Vector2(0, r.size.y)]
	var mid := r.get_center()
	var pts := PackedVector2Array()
	for e in 4:   # slanted corners, edges chipped inwards
		var p0: Vector2 = corners[e]
		var p1: Vector2 = corners[(e + 1) % 4]
		var n := maxi(int(p0.distance_to(p1) / 46.0), 1)
		for i in n:
			var p := p0.lerp(p1, float(i) / n)
			if i > 0:
				p += (mid - p).normalized() * rng.randf_range(0.0, k * 0.4)
			pts.append(p)
	c.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	c.draw_polyline(closed, edge, 3.0, true)


## A tapered, ragged brush stroke from a to b.
static func brush(c: Control, a: Vector2, b: Vector2, w: float, col: Color, seed_n := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n * 104729
	var d := (b - a)
	var n := d.orthogonal().normalized()
	var steps := maxi(int(d.length() / 18.0), 4)
	var up := PackedVector2Array()
	var down := PackedVector2Array()
	for i in steps + 1:
		var f := float(i) / steps
		var taper := minf(minf(f * 5.0, (1.0 - f) * 2.2), 1.0)
		var half := w * 0.5 * taper * rng.randf_range(0.7, 1.15)
		var p := a + d * f
		up.append(p + n * half)
		down.append(p - n * half * rng.randf_range(0.6, 1.1))
	down.reverse()
	up.append_array(down)
	if up.size() >= 3:
		c.draw_colored_polygon(up, col)


## Five-point crown.
static func crown(c: Control, r: Rect2, col: Color) -> void:
	var p := r.position
	var s := r.size
	var pts := PackedVector2Array([
		p + Vector2(0, s.y), p + Vector2(0, s.y * 0.25), p + Vector2(s.x * 0.25, s.y * 0.6), p + Vector2(s.x * 0.5, 0),
		p + Vector2(s.x * 0.75, s.y * 0.6), p + Vector2(s.x, s.y * 0.25), p + Vector2(s.x, s.y)])
	c.draw_colored_polygon(pts, col)


## Flame (JOZI FLAMES crest).
static func flame(c: Control, r: Rect2, col: Color) -> void:
	var p := r.position
	var s := r.size
	var pts := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20.0
		var x := 0.5 + 0.5 * sin(a) * (0.9 - 0.45 * maxf(-cos(a), 0.0))
		var y := 0.5 - 0.5 * cos(a) * (1.0 if cos(a) > 0 else 0.9)
		pts.append(p + Vector2(x * s.x, y * s.y))
	c.draw_colored_polygon(pts, col)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(s.x * 0.5, s.y * 0.4), p + Vector2(s.x * 0.72, s.y * 0.78), p + Vector2(s.x * 0.5, s.y * 0.95), p + Vector2(s.x * 0.3, s.y * 0.78)]), Color(INK, 0.55))


static func crest(c: Control, r: Rect2, team: int, col: Color) -> void:
	if team == 0:
		flame(c, r, col)
	else:
		crown(c, r.grow_individual(0, -r.size.y * 0.1, 0, -r.size.y * 0.1), col)


## Round prompt chip. kind: "x" "o" "tri" "sq" or a single letter.
static func prompt(c: Control, center: Vector2, rad: float, kind: String, col := WHITE) -> void:
	c.draw_circle(center, rad, INK)
	c.draw_arc(center, rad, 0, TAU, 28, col, 3.0, true)
	var q := rad * 0.42
	match kind:
		"x":
			c.draw_line(center + Vector2(-q, -q), center + Vector2(q, q), col, 3.5, true)
			c.draw_line(center + Vector2(q, -q), center + Vector2(-q, q), col, 3.5, true)
		"o":
			c.draw_arc(center, q * 1.05, 0, TAU, 20, col, 3.5, true)
		"tri":
			c.draw_polyline(PackedVector2Array([center + Vector2(0, -q * 1.1), center + Vector2(q * 1.1, q * 0.8), center + Vector2(-q * 1.1, q * 0.8), center + Vector2(0, -q * 1.1)]), col, 3.5, true)
		_:
			var f := font()
			var fs := int(rad * 1.25)
			var ext := f.get_string_size(kind, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			c.draw_string(f, center + Vector2(-ext.x / 2.0, fs * 0.36), kind, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Cartoon bust of a character, in a team's colours. r = the area to fill; scales to it.
static func portrait(c: Control, r: Rect2, ch: Dictionary, shirt: Color, trim: Color, band: Color = Color(0, 0, 0, 0)) -> void:
	var u := minf(r.size.x, r.size.y * 0.85)
	var cx := r.position.x + r.size.x * 0.5
	var base := r.position.y + r.size.y
	var skin: Color = ch.skin
	var hc: Color = ch.hc
	# shoulders + jersey
	var sh_y := base - u * 0.34
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx - u * 0.52, base), Vector2(cx - u * 0.42, sh_y + u * 0.06), Vector2(cx - u * 0.18, sh_y - u * 0.02),
			Vector2(cx + u * 0.18, sh_y - u * 0.02), Vector2(cx + u * 0.42, sh_y + u * 0.06), Vector2(cx + u * 0.52, base)]), shirt)
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx - u * 0.17, sh_y - u * 0.02), Vector2(cx, sh_y + u * 0.14), Vector2(cx + u * 0.17, sh_y - u * 0.02)]), skin.darkened(0.15))
	c.draw_polyline(PackedVector2Array([Vector2(cx - u * 0.19, sh_y - u * 0.02), Vector2(cx, sh_y + u * 0.16), Vector2(cx + u * 0.19, sh_y - u * 0.02)]), trim, maxf(u * 0.03, 2.0), true)
	# neck + head
	var head_c := Vector2(cx, base - u * 0.62)
	c.draw_rect(Rect2(cx - u * 0.07, head_c.y + u * 0.15, u * 0.14, u * 0.2), skin.darkened(0.2))
	var hr := u * 0.27
	if ch.hair == 4:
		c.draw_circle(head_c + Vector2(0, -hr * 0.12), hr * 1.32, hc)
	if ch.hair == 2:
		for sx in [-1.0, 1.0]:
			c.draw_colored_polygon(PackedVector2Array([head_c + Vector2(sx * hr * 0.8, -hr * 0.4), head_c + Vector2(sx * hr * 1.25, hr * 0.2), head_c + Vector2(sx * hr * 1.05, hr * 1.5), head_c + Vector2(sx * hr * 0.7, hr * 0.6)]), hc)
	c.draw_set_transform(head_c, 0.0, Vector2(0.9, 1.0))
	c.draw_circle(Vector2.ZERO, hr, skin)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match ch.hair:
		0, 2:
			c.draw_circle(head_c + Vector2(0, -hr * 0.55), hr * 0.78, hc)
			c.draw_circle(head_c + Vector2(-hr * 0.55, -hr * 0.55), hr * 0.45, hc)
			c.draw_circle(head_c + Vector2(hr * 0.55, -hr * 0.55), hr * 0.45, hc)
			c.draw_circle(head_c + Vector2(0, -hr * 0.25), hr * 0.7, skin)   # forehead cut-out
			c.draw_rect(Rect2(head_c + Vector2(-hr * 0.8, -hr * 0.2), Vector2(hr * 1.6, hr * 0.15)), skin)
		3:
			c.draw_colored_polygon(PackedVector2Array([head_c + Vector2(-hr, -hr * 0.2), head_c + Vector2(-hr * 0.8, -hr * 1.1), head_c + Vector2(hr * 0.8, -hr * 1.1), head_c + Vector2(hr, -hr * 0.2)]), shirt)
			c.draw_rect(Rect2(head_c + Vector2(-hr * 0.2, -hr * 0.4), Vector2(hr * 1.5, hr * 0.2)), shirt.darkened(0.2))
			c.draw_colored_polygon(PackedVector2Array([head_c + Vector2(-hr, -hr * 0.2), head_c + Vector2(-hr * 1.2, hr * 0.1), head_c + Vector2(-hr * 0.9, hr * 0.5)]), hc)
		5:
			c.draw_circle(head_c + Vector2(0, -hr * 0.78), hr * 0.62, hc)
	if band.a > 0.0 or ch.hair == 5:
		var bc: Color = band if band.a > 0.0 else ch.tone
		c.draw_rect(Rect2(head_c + Vector2(-hr * 0.92, -hr * 0.52), Vector2(hr * 1.84, hr * 0.26)), bc)
	# face
	for sx in [-1.0, 1.0]:
		var ec := head_c + Vector2(sx * hr * 0.36, -hr * 0.02)
		c.draw_circle(ec, hr * 0.12, Color.WHITE)
		c.draw_circle(ec + Vector2(sx * hr * 0.02, 0), hr * 0.07, INK)
		c.draw_line(ec + Vector2(-hr * 0.16, -hr * 0.2), ec + Vector2(hr * 0.16, -hr * (0.2 + 0.07 * sx)), INK, maxf(u * 0.018, 1.5))
	c.draw_arc(head_c + Vector2(0, hr * 0.28), hr * 0.3, 0.25, PI - 0.25, 10, INK, maxf(u * 0.02, 1.5), true)


## Sky, skyline, towers, hazard slashes: the screen backdrop.
static func backdrop(c: Control) -> void:
	var s := c.size
	var rng := RandomNumberGenerator.new()
	rng.seed = 1990
	var top := DEEP
	var bot := SKY
	var strips := 36
	for i in strips:
		var f := float(i) / strips
		c.draw_rect(Rect2(0, s.y * f, s.x, s.y / strips + 1), top.lerp(bot, f))
	for i in 9:   # cloud smears
		var y := rng.randf_range(0.05, 0.45) * s.y
		brush(c, Vector2(rng.randf() * s.x, y), Vector2(rng.randf() * s.x * 0.3 + s.x * 0.3, y - 14), rng.randf_range(24, 60), Color(1, 1, 1, 0.14), i + 3)
	# skyline
	var gy := s.y * 0.78
	var x := -20.0
	while x < s.x:
		var w := rng.randf_range(50.0, 120.0)
		var h := rng.randf_range(s.y * 0.1, s.y * 0.36)
		c.draw_rect(Rect2(x, gy - h, w, h + s.y), Color("0a2f66").lerp(Color("123f80"), rng.randf()))
		for wy in int(h / 26.0):
			for wx in int(w / 22.0):
				if rng.randf() < 0.16:
					c.draw_rect(Rect2(x + 8 + wx * 22, gy - h + 10 + wy * 26, 8, 10), Color(YELLOW, 0.55))
		x += w + rng.randf_range(0, 8)
	var tx := s.x * 0.62   # the tower
	c.draw_colored_polygon(PackedVector2Array([Vector2(tx - 12, gy), Vector2(tx - 5, gy - s.y * 0.5), Vector2(tx + 5, gy - s.y * 0.5), Vector2(tx + 12, gy)]), Color("07224d"))
	c.draw_circle(Vector2(tx, gy - s.y * 0.47), 22, Color("07224d"))
	# ground
	c.draw_rect(Rect2(0, gy, s.x, s.y - gy), Color("0a2a5c"))
	for i in 7:
		var gx := s.x * i / 6.0
		c.draw_line(Vector2(gx, gy), Vector2((gx - s.x * 0.5) * 2.4 + s.x * 0.5, s.y), Color(BLUE, 0.25), 3)
	# slashes
	brush(c, Vector2(-40, s.y * 0.1), Vector2(s.x * 0.5, -10), 46, Color(YELLOW, 0.95), 11)
	brush(c, Vector2(s.x * 0.55, s.y + 20), Vector2(s.x + 40, s.y * 0.82), 54, Color(YELLOW, 0.95), 12)
	brush(c, Vector2(-30, s.y * 0.97), Vector2(s.x * 0.35, s.y * 0.86), 30, Color(YELLOW, 0.9), 13)
	brush(c, Vector2(s.x * 0.7, -10), Vector2(s.x + 30, s.y * 0.14), 34, Color(INK, 0.9), 14)
	brush(c, Vector2(-30, s.y * 0.2), Vector2(s.x * 0.18, s.y * 0.05), 22, Color(INK, 0.85), 15)


# ------------------------------------------------------------------ widgets

static func label(text: String, size := 30, color := WHITE, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, cb: Callable, w := 460.0, h := 64.0, variation := &"") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	if variation != &"":
		b.theme_type_variation = variation
	b.pressed.connect(cb)
	return b


## Settings row: NAME  ◀ VALUE ▶.  Left/right step, click steps forward.
class Chooser extends Button:
	signal stepped(dir: int)
	var value_label: Label

	func _init(title: String, w := 700.0) -> void:
		custom_minimum_size = Vector2(w, 64)
		focus_mode = Control.FOCUS_ALL
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 26
		row.offset_right = -26
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var name_l := Label.new()
		name_l.text = title
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.add_theme_font_size_override("font_size", 28)
		row.add_child(name_l)
		row.add_child(_arrow("◀"))
		value_label = Label.new()
		value_label.custom_minimum_size = Vector2(320, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.add_theme_font_size_override("font_size", 28)
		row.add_child(value_label)
		row.add_child(_arrow("▶"))
		pressed.connect(func() -> void: stepped.emit(1))
		focus_entered.connect(_recolor)
		focus_exited.connect(_recolor)
		mouse_entered.connect(_recolor)
		mouse_exited.connect(_recolor)
		_recolor()

	func _arrow(g: String) -> Label:
		var l := Label.new()
		l.text = g
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_constant_override("outline_size", 0)
		return l

	## Row labels stay readable on the yellow focus slab: black on yellow, white on ink.
	func _recolor() -> void:
		var lit := has_focus() or is_hovered()
		for n in find_children("*", "Label", true, false):
			n.add_theme_color_override("font_color", UI.INK if lit else UI.WHITE)
			n.add_theme_constant_override("outline_size", 0 if lit else 6)

	func _gui_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left"):
			stepped.emit(-1)
			accept_event()
		elif e.is_action_pressed("ui_right"):
			stepped.emit(1)
			accept_event()

	func set_value(t: String) -> void:
		value_label.text = t
