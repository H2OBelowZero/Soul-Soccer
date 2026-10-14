class_name BallFx
extends Node3D
## Kick VFX, all tinted to the ball's aura colour (Vessel.glow): a static (world-space) noise ribbon trail for shots
## and passes, a T_flare12 fireball head on a shot in flight, a T_flare81 flare riding a pass, and a quick burst of
## flattened-circle (T_circle42) sparks at a shot's contact point. Textures live in res://vfx/.

const SHOT_LIFE := 0.5     # seconds a shot's ribbon takes to fade out
const PASS_LIFE := 0.3

var ball: Ball
var pts := []              # ribbon points: {p, t, life, w, c, fire}
var ribbon := ImmediateMesh.new()
var head: MeshInstance3D   # shot fireball
var head_mat: ShaderMaterial
var head_k := 0.0
var star: MeshInstance3D   # pass flare
var star_mat: ShaderMaterial
var star_k := 0.0
var sparks: GPUParticles3D
var spark_pm: ParticleProcessMaterial
static var _spark_mat: ShaderMaterial


## A quad carrying the flattened-circle spark sprite, shared by the kick sparks and the confetti.
static func spark_quad(size: Vector2) -> QuadMesh:
	if _spark_mat == null:
		_spark_mat = ShaderMaterial.new()
		_spark_mat.shader = load("res://shaders/spark.gdshader")
		_spark_mat.set_shader_parameter("disc", load("res://vfx/T_circle42.PNG"))
	var q := QuadMesh.new()
	q.size = size
	q.material = _spark_mat
	return q


func _ready() -> void:
	top_level = true   # the ribbon lives in world space, so this node must not follow the ball
	var noise := load("res://vfx/T_VFX_Noi55.png") as Texture2D

	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/trail.gdshader")
	rm.set_shader_parameter("noise", noise)
	var rib := MeshInstance3D.new()
	rib.mesh = ribbon
	rib.material_override = rm
	rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rib)

	head_mat = ShaderMaterial.new()
	head_mat.shader = load("res://shaders/fireball.gdshader")
	head_mat.set_shader_parameter("noise", noise)
	head_mat.set_shader_parameter("flare", load("res://vfx/T_flare12.png"))
	head = _quad(head_mat, 2.0)

	star_mat = ShaderMaterial.new()
	star_mat.shader = load("res://shaders/flare.gdshader")
	star_mat.set_shader_parameter("flare", load("res://vfx/T_flare81.png"))
	star = _quad(star_mat, 1.7)

	sparks = GPUParticles3D.new()
	sparks.one_shot = true
	sparks.emitting = false
	sparks.amount = 14
	sparks.lifetime = 0.3
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	spark_pm = ParticleProcessMaterial.new()
	spark_pm.direction = Vector3.UP
	spark_pm.spread = 180.0
	spark_pm.initial_velocity_min = 4.0
	spark_pm.initial_velocity_max = 9.0
	spark_pm.damping_min = 3.0
	spark_pm.damping_max = 5.0
	spark_pm.gravity = Vector3(0, -9, 0)
	spark_pm.particle_flag_align_y = true   # long axis along the direction of travel (see spark.gdshader)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	spark_pm.color_ramp = gt
	sparks.process_material = spark_pm
	sparks.draw_pass_1 = spark_quad(Vector2(0.16, 0.42))   # the flattened circle
	add_child(sparks)


func _quad(mat: ShaderMaterial, size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## Called by the ball as it is kicked.
func kicked(type: String) -> void:
	if type == "shot":
		spark_pm.color = ball.game.aura()
		sparks.global_position = ball.global_position
		sparks.restart()


func _process(delta: float) -> void:
	var g := ball.game
	var age := g.t - ball.kick_t
	var flying := ball.carrier == null
	var shot := flying and ball.kick_type == "shot" and age < 1.4
	var pass_ := flying and ball.kick_type == "pass" and age < 1.0
	var p := ball.global_position
	var tint := g.aura()
	if not pts.is_empty() and p.distance_to(pts[-1].p) > 4.0:
		pts.clear()   # the ball was teleported (kick-off reset)
	if (shot or pass_) and (pts.is_empty() or p.distance_to(pts[-1].p) > 0.08):
		var c := tint
		c.a = 1.0 if shot else 0.8 + 0.2 * g.vessel.momentum()
		pts.append({"p": p, "t": g.t, "life": SHOT_LIFE if shot else PASS_LIFE, "w": 0.75 if shot else 0.26, "c": c, "fire": shot})
	pts = pts.filter(func(pt: Dictionary) -> bool: return g.t - pt.t < pt.life)
	_ribbon(g.t, g.cam.global_position)
	head_k = move_toward(head_k, 1.0 if shot else 0.0, delta * 10.0)
	star_k = move_toward(star_k, 1.0 if pass_ else 0.0, delta * 10.0)
	_glint(head, head_mat, head_k, p, tint)
	_glint(star, star_mat, star_k, p, tint)


func _glint(mi: MeshInstance3D, mat: ShaderMaterial, k: float, at: Vector3, tint: Color) -> void:
	mi.visible = k > 0.0
	mi.global_position = at
	mat.set_shader_parameter("fade", k)
	mat.set_shader_parameter("tint", tint)


## Camera-facing strip through the points: full width and brightness at the ball, tapering to nothing at the tail.
func _ribbon(now: float, cam: Vector3) -> void:
	ribbon.clear_surfaces()
	var n := pts.size()
	if n < 2:
		return
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var u := 0.0
	for i in n:
		var pt: Dictionary = pts[i]
		var at: Vector3 = pt.p
		var a: float = 1.0 - (now - pt.t) / pt.life
		var dir: Vector3 = pts[mini(i + 1, n - 1)].p - pts[maxi(i - 1, 0)].p
		var side: Vector3 = dir.cross(cam - at).normalized() * float(pt.w) * a * 0.5
		if i > 0:
			u += at.distance_to(pts[i - 1].p)
		var col: Color = pt.c
		if pt.fire:
			col = col.lerp(Color.WHITE, 0.1 * a * a)   # a touch hot at the ball, the pure aura colour at the tail
		col.a *= a
		for s in 2:
			ribbon.surface_set_color(col)
			ribbon.surface_set_uv(Vector2(u, float(s)))
			ribbon.surface_add_vertex(at + side * (1.0 if s == 0 else -1.0))
	ribbon.surface_end()
