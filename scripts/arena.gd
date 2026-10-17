class_name Arena
extends RefCounted
## Builds the Jabulani Cage: concrete pitch, graffiti walls, steel fence, stands, crowd, kasi skyline.
## Also hosts the shared toon-material / label helpers every other script uses.

const L := 20.0          # half pitch length (x): ~2s sprint per half (sprint 10 m/s), 4s end to end
const W := 12.0          # half pitch width (z)
const PITCH_K := L / 15.0   # scale vs the original 30x18 pitch; spreads formations and camera to match
const WALL_H := 1.4
const FENCE_H := 4.2
const GOAL_HALF := 2.5   # half width of the goal frame; bricks eat into it
const GOAL_H := 1.4
const STAND_S := 1.5     # stadium scale: stands, crowd, banner, floodlights and skyline (the pitch itself is unchanged)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_BALL := 4

const PAINT := [Color("ff2d95"), Color("00e5ff"), Color("ffe100"), Color("7cff3a"), Color("ff7a00"), Color("b04dff")]
const WORDS := ["KASI", "SHAYA!", "1 PAL", "JOZI", "EISH!", "LEKKER", "SHARP SHARP", "MZANSI", "HALALA", "SOWETO", "PFL", "HAYIBO!"]

static var _mats := {}
static var _font: SystemFont
static var _fence_mat: ShaderMaterial


static func toon(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = 0.85
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Impact", "Arial Black", "Segoe UI Black", "sans-serif"])
		_font.font_weight = 800
	return _font


static func fence_material() -> ShaderMaterial:
	if _fence_mat == null:
		_fence_mat = ShaderMaterial.new()
		_fence_mat.shader = load("res://shaders/fence.gdshader")
	return _fence_mat


static func mesh(parent: Node, m: Mesh, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = toon(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return mesh(parent, bm, pos, c)


## Invisible static collider. Groups drive ball events ("wall", "brick", "cage", "floor").
static func solid(parent: Node, size: Vector3, pos: Vector3, group := "wall") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.collision_layer = LAYER_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.add_to_group(group)
	parent.add_child(sb)
	return sb


static func label(parent: Node, text: String, pos: Vector3, c: Color, px := 0.01, size := 96) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = size
	l.pixel_size = px
	l.modulate = c
	l.outline_size = int(size / 5.0)
	l.outline_modulate = Color.BLACK
	l.position = pos
	l.double_sided = true
	parent.add_child(l)
	return l


## Make a label see-through (text alpha `a`, its outline fainter still), so painted words don't pull the eye off the ball.
static func faint(l: Label3D, a: float) -> Label3D:
	l.modulate.a = a
	l.outline_modulate.a = a * 0.5
	return l


static func fence_panel(parent: Node, pos: Vector3, size: Vector2, rot: Vector3) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = fence_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)


## Returns the crowd material so the game can pump its `excite` uniform.
static func build(root: Node3D) -> ShaderMaterial:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1976
	_environment(root)
	_pitch(root)
	_walls(root, rng)
	_fence(root)
	var crowd := _stands(root, rng)
	_skyline(root, rng)
	return crowd


static func _environment(root: Node3D) -> void:
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2a1b5e")
	sm.sky_horizon_color = Color("ff8a3d")
	sm.ground_horizon_color = Color("ff8a3d")
	sm.ground_bottom_color = Color("1a1030")
	var sky := Sky.new()
	sky.sky_material = sm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9a8fc0")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		env.tonemap_exposure = 0.65   # the GL renderer lights the same scene much hotter than Forward+/Mobile
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_color = Color("ffd9ae")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)


static func _pitch(root: Node3D) -> void:
	solid(root, Vector3(120, 1, 120), Vector3(0, -0.5, 0), "floor")
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var grad := Gradient.new()
	grad.set_color(0, Color("7b7d85"))
	grad.set_color(1, Color("a9abb1"))
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.color_ramp = grad
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.roughness = 1.0
	m.uv1_scale = Vector3(6, 4, 1) * PITCH_K
	var pm := PlaneMesh.new()
	pm.size = Vector2(2 * L, 2 * W)
	var concrete := MeshInstance3D.new()
	concrete.mesh = pm
	concrete.material_override = m
	root.add_child(concrete)
	var outer := PlaneMesh.new()
	outer.size = Vector2(160, 160)
	mesh(root, outer, Vector3(0, -0.02, 0), Color("3a3440"))

	var lc := Color(0.96, 0.95, 0.9)
	box(root, Vector3(0.12, 0.02, 2 * W), Vector3(0, 0.01, 0), lc)
	for s: float in [-1.0, 1.0]:
		box(root, Vector3(2 * L, 0.02, 0.12), Vector3(0, 0.01, s * (W - 0.3)), lc)
		box(root, Vector3(0.12, 0.02, 2 * W), Vector3(s * (L - 0.3), 0.01, 0), lc)
		box(root, Vector3(0.12, 0.02, 9.0), Vector3(s * (L - 4.0), 0.01, 0), lc)
		for z: float in [-4.5, 4.5]:
			box(root, Vector3(3.7, 0.02, 0.12), Vector3(s * (L - 2.15), 0.01, z), lc)
	var ring := TorusMesh.new()
	ring.inner_radius = 2.4
	ring.outer_radius = 2.55
	mesh(root, ring, Vector3(0, 0.01, 0), lc).scale = Vector3(1, 0.1, 1)
	var logo := faint(label(root, "1 PAL", Vector3(0, 0.03, 0), Color.WHITE, 0.0075, 180), 0.3)
	logo.rotation_degrees = Vector3(-90, 0, 0)


static func _walls(root: Node3D, rng: RandomNumberGenerator) -> void:
	var wc := Color("d8cfc0")
	var seg := W - GOAL_HALF
	for s: float in [-1.0, 1.0]:
		box(root, Vector3(2 * L + 0.6, WALL_H, 0.3), Vector3(0, WALL_H / 2, s * (W + 0.15)), wc)
		box(root, Vector3(2 * L + 0.6, 0.1, 0.4), Vector3(0, WALL_H, s * (W + 0.15)), Color("444a55"))
		solid(root, Vector3(2 * L + 0.6, FENCE_H, 0.3), Vector3(0, FENCE_H / 2, s * (W + 0.15)))
		for zs: float in [-1.0, 1.0]:
			var pos := Vector3(s * (L + 0.15), 0, zs * (GOAL_HALF + seg / 2))
			box(root, Vector3(0.3, WALL_H, seg), pos + Vector3(0, WALL_H / 2, 0), wc)
			solid(root, Vector3(0.3, FENCE_H, seg), pos + Vector3(0, FENCE_H / 2, 0))
		solid(root, Vector3(0.3, FENCE_H - GOAL_H, 2 * GOAL_HALF), Vector3(s * (L + 0.15), (FENCE_H + GOAL_H) / 2, 0))
	solid(root, Vector3(2 * L + 4, 0.3, 2 * W + 4), Vector3(0, 7.0, 0), "roof")

	# Graffiti on the far (camera-facing) wall.
	var x := -L + 0.5
	while x < L - 1.5:
		var w := rng.randf_range(1.6, 3.4)
		var c: Color = PAINT[rng.randi() % PAINT.size()]
		box(root, Vector3(w, rng.randf_range(0.7, 1.15), 0.04), Vector3(x + w / 2, WALL_H / 2, -W + 0.03), c)
		var word := faint(label(root, WORDS[rng.randi() % WORDS.size()], Vector3(x + w / 2, WALL_H / 2, -W + 0.07),
				PAINT[rng.randi() % PAINT.size()].lightened(0.3), 0.0035, 120), 0.45)
		word.rotation_degrees.z = rng.randf_range(-8, 8)
		x += w + rng.randf_range(0.2, 0.8)
	# ...and on the end walls beside each goal.
	for s: float in [-1.0, 1.0]:
		for zs: float in [-1.0, 1.0]:
			var c: Color = PAINT[rng.randi() % PAINT.size()]
			var pos := Vector3(s * (L - 0.03), WALL_H / 2, zs * (GOAL_HALF + seg / 2))
			box(root, Vector3(0.04, 1.0, seg - 0.6), pos, c)
			var word := faint(label(root, WORDS[rng.randi() % WORDS.size()], pos - Vector3(s * 0.05, 0, 0), Color.WHITE, 0.0035, 110), 0.45)
			word.rotation_degrees = Vector3(0, -90 * s, rng.randf_range(-6, 6))


static func _fence(root: Node3D) -> void:
	var steel := Color("3b3f48")
	var h := FENCE_H - WALL_H
	for s: float in [-1.0, 1.0]:
		fence_panel(root, Vector3(0, WALL_H + h / 2, s * (W + 0.15)), Vector2(2 * L, h), Vector3.ZERO)
		fence_panel(root, Vector3(s * (L + 0.15), (FENCE_H + GOAL_H) / 2, 0), Vector2(2 * W, FENCE_H - GOAL_H), Vector3(0, 90, 0))
		box(root, Vector3(2 * L + 0.4, 0.1, 0.1), Vector3(0, FENCE_H, s * (W + 0.15)), steel)
		box(root, Vector3(0.1, 0.1, 2 * W + 0.4), Vector3(s * (L + 0.15), FENCE_H, 0), steel)
		var x := -L
		while x <= L + 0.01:
			box(root, Vector3(0.1, h, 0.1), Vector3(x, WALL_H + h / 2, s * (W + 0.15)), steel)
			x += 2.5


static func _stands(root: Node3D, rng: RandomNumberGenerator) -> ShaderMaterial:
	var concrete := Color("8f8983")
	var spots: Array[Vector3] = []
	# Long sides: tall terrace opposite the camera, a low one in the foreground.
	for s: float in [-1.0, 1.0]:
		var rows := 5 if s < 0.0 else 2
		for r in rows:
			var top := (r + 1) * 0.5 * STAND_S
			var z := s * (W + 0.75 + (r + 0.5) * 0.9 * STAND_S)   # inner edge stays against the fence
			box(root, Vector3(2 * L + 8, top, 0.9 * STAND_S), Vector3(0, top / 2, z), concrete)
			var x := -L - 3.5
			while x < L + 3.5:
				if rng.randf() < 0.85:
					spots.append(Vector3(x + rng.randf_range(-0.1, 0.1), top + 0.55 * STAND_S, z))
				x += 0.6 * STAND_S
	# Behind each goal.
	for s: float in [-1.0, 1.0]:
		for r in 3:
			var top := (r + 1) * 0.5 * STAND_S
			var x := s * (L + 1.95 + (r + 0.5) * 0.9 * STAND_S)
			box(root, Vector3(0.9 * STAND_S, top, 2 * W + 2), Vector3(x, top / 2, 0), concrete)
			var z := -W
			while z < W:
				if rng.randf() < 0.8:
					spots.append(Vector3(x, top + 0.55 * STAND_S, z + rng.randf_range(-0.1, 0.1)))
				z += 0.6 * STAND_S

	var shirts := PAINT + [Color("ff5a1f"), Color("7b2ff7"), Color("ffc300"), Color("f2f2f2"), Color("1e90ff"), Color("e63946")]
	var skins := [Color("5a3825"), Color("7a4a2e"), Color("3e2618"), Color("8d5a3b")]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crowd.gdshader")
	var body := CapsuleMesh.new()
	body.radius = 0.22
	body.height = 1.1
	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	var mms: Array[MultiMesh] = []
	for part: Mesh in [body, head]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = part
		mm.instance_count = spots.size()
		mms.append(mm)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		root.add_child(mmi)
	for i in spots.size():
		var custom := Color(rng.randf(), rng.randf(), 0, 0)
		mms[0].set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * STAND_S), spots[i]))
		mms[0].set_instance_color(i, shirts[rng.randi() % shirts.size()])
		mms[0].set_instance_custom_data(i, custom)
		mms[1].set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * STAND_S), spots[i] + Vector3(0, 0.72 * STAND_S, 0)))
		mms[1].set_instance_color(i, skins[rng.randi() % skins.size()])
		mms[1].set_instance_custom_data(i, custom)

	# Event banner + floodlights over the far terrace.
	var far := W + 0.9 + 4.5 * STAND_S   # just behind the tall terrace
	box(root, Vector3(2 * L, 1.3 * STAND_S, 0.2), Vector3(0, 5.4 * STAND_S, -far), Color("d7263d"))
	label(root, "PFL  ·  1 PAL CUP  ·  JABULANI CAGE  ·  SOWETO", Vector3(0, 5.4 * STAND_S, -(far - 0.12)), Color.WHITE, 0.012 * STAND_S, 96)
	var lamp := StandardMaterial3D.new()
	lamp.emission_enabled = true
	lamp.emission = Color("fff4d6")
	lamp.emission_energy_multiplier = 4.0
	var lamp_x := L + 1.95 + 2.7 * STAND_S + 1.4   # clear of the end terraces
	for x: float in [-lamp_x, lamp_x]:
		for z: float in [-(far + 1.6), far + 1.6]:
			box(root, Vector3(0.35, 14, 0.35) * STAND_S, Vector3(x, 7 * STAND_S, z), Color("2b2e36"))
			box(root, Vector3(2.6, 1.2, 0.4) * STAND_S, Vector3(x, 14 * STAND_S, z), Color.WHITE).material_override = lamp
	return mat


static func _skyline(root: Node3D, rng: RandomNumberGenerator) -> void:
	var walls := [Color("f4d35e"), Color("ee964b"), Color("5fad56"), Color("3d85c6"), Color("e8e8e8"), Color("c9a0dc"), Color("f95738")]
	for i in 90:
		var a := rng.randf_range(PI * 0.9, PI * 2.1)  # mostly behind the far side
		var r := rng.randf_range(34, 70)
		var pos := Vector3(cos(a) * r * 1.3, 0, sin(a) * r)
		var size := Vector3(rng.randf_range(3, 6), rng.randf_range(2.4, 3.6), rng.randf_range(3, 5))
		if rng.randf() < 0.08:
			size.y = rng.randf_range(8, 14)  # hostel blocks / towers
		size *= STAND_S
		box(root, size, pos + Vector3(0, size.y / 2, 0), walls[rng.randi() % walls.size()])
		box(root, Vector3(size.x + 0.4, 0.25, size.z + 0.4), pos + Vector3(0, size.y + 0.12, 0),
				Color("8a8f98") if rng.randf() < 0.6 else Color("a0522d"))
