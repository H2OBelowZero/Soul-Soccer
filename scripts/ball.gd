class_name Ball
extends RigidBody3D
## Heavy arcade ball. Free = physics; carried = frozen kinematic, glued to the carrier's feet.

const R := 0.3
const GRAV := 1.5

var game: Game
var carrier: Player
var last_touch: Player
var kick_type := ""          # "pass", "shot", "flick", "parry", "loose"
var pass_target: Player
var kick_t := -10.0
var spin := 0.0              # curve: Magnus force strength around +Y
var power := false
var charge := 0.0            # shot charge 0..1; survives passes, lost when the other team gets the ball
var quick := false
var wall_touch := false
var near_miss := false
var no_pickup := {}          # Player -> game time until they may touch it
var visual: Node3D
var fx: BallFx
var skin: StandardMaterial3D   # own copy: its glow shows the souls inside
var glow: OmniLight3D
var aura: GPUParticles3D
var aura_mat: ParticleProcessMaterial
var spark_mat: StandardMaterial3D   # aura dots; pushed past 1.0 so the glow pass blooms them

const SCUFFED := Color("d9d3c4")


static func ballistic(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	var t := maxf(flat.length() / speed, 0.05)
	var g := 9.8 * GRAV
	return flat / t + Vector3.UP * ((to.y - from.y) / t + 0.5 * g * t)


func _ready() -> void:
	name = "Ball"
	mass = 0.45
	gravity_scale = GRAV
	linear_damp = 0.25
	angular_damp = 0.6
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = Arena.LAYER_BALL
	collision_mask = Arena.LAYER_WORLD | Arena.LAYER_PLAYER
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55
	pm.friction = 0.6
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = R
	cs.shape = sh
	add_child(cs)

	visual = Node3D.new()
	add_child(visual)
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = 2 * R
	skin = Arena.toon(SCUFFED).duplicate()
	skin.emission_enabled = true
	Arena.mesh(visual, sm, Vector3.ZERO, SCUFFED).material_override = skin
	glow = OmniLight3D.new()
	glow.omni_range = 3.5
	glow.light_energy = 0.0
	add_child(glow)
	aura = GPUParticles3D.new()
	aura.amount = 20
	aura.lifetime = 0.7
	aura.local_coords = false
	aura.emitting = false
	aura_mat = ParticleProcessMaterial.new()
	aura_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	aura_mat.emission_sphere_radius = R
	aura_mat.direction = Vector3.UP
	aura_mat.spread = 60.0
	aura_mat.initial_velocity_min = 0.4
	aura_mat.initial_velocity_max = 1.4
	aura_mat.gravity = Vector3(0, 1.0, 0)
	aura_mat.scale_min = 0.4
	aura_mat.scale_max = 1.0
	aura.process_material = aura_mat
	var patch := SphereMesh.new()
	patch.radius = R * 0.36
	patch.height = R * 0.72
	for d in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		Arena.mesh(visual, patch, d * R * 0.78, Color("d7263d") if d.y == 0.0 else Color("111111"))

	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	aura_mat.color_ramp = ft
	var wisp := SphereMesh.new()
	wisp.radius = 0.035
	wisp.height = 0.07
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	spark_mat = dm
	wisp.material = dm
	aura.draw_pass_1 = wisp
	add_child(aura)
	fx = BallFx.new()
	fx.ball = self
	add_child(fx)

	body_entered.connect(_on_body_entered)


## Dormant → Stirring → Possessed → Hungry → Overloaded: the colour is whose soul dominates;
## overloaded goes black at the core and won't sit still. As the momentum builds the body takes on the
## colour, the glow brightens and the trail / aura thicken. Every effect reads Vessel.glow().
func _process(_delta: float) -> void:
	var v := game.vessel
	var s := v.stage()
	var m := v.momentum()
	var col := v.glow()
	var live := s > Vessel.Stage.DORMANT
	var pulse := 0.5 + 0.5 * sin(game.t * (3.0 + s * 3.0))
	if v.is_hungry(game.t):
		pulse *= 0.4 + 0.6 * absf(sin(game.t * 11.0))  # flickers when starving
	var over := s == Vessel.Stage.OVERLOADED
	var energy := lerpf(2.2, 5.0, m) if live else 0.0
	if over:
		skin.albedo_color = Color(0.07, 0.05, 0.09)
	elif live:
		skin.albedo_color = SCUFFED.lerp(col, lerpf(0.7, 1.0, m))
	else:
		skin.albedo_color = SCUFFED
	skin.emission = col
	skin.emission_energy_multiplier = energy * (0.5 + 0.5 * pulse)
	glow.light_color = col
	glow.light_energy = energy * 0.75 * (0.6 + 0.4 * pulse)
	glow.omni_range = lerpf(3.5, 6.0, m)
	aura_mat.color = col
	var k := lerpf(1.0, 2.6, m)
	spark_mat.albedo_color = Color(k, k, k)
	aura.emitting = live
	aura.amount_ratio = lerpf(0.3, 1.0, m)
	visual.scale = Vector3.ONE * (1.0 + charge * 0.4)  # a charged ball swells
	visual.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.025 if over else Vector3.ZERO


func _physics_process(_delta: float) -> void:
	if carrier:
		_carry()
		return
	if spin != 0.0:
		apply_central_force(Vector3(0, spin, 0).cross(linear_velocity) * mass)
	if quick and game.t - kick_t > 1.0:
		quick = false
		collision_mask = Arena.LAYER_WORLD | Arena.LAYER_PLAYER
	var p := global_position
	if absf(p.x) > Arena.L + 4 or absf(p.z) > Arena.W + 3 or p.y < -3:
		reset_to_center()
		return
	if game.state == Game.S.PLAY:
		_try_pickup()


func _carry() -> void:
	var c := carrier
	var target := c.global_position + c.facing * 0.62
	target.x = clampf(target.x, -Arena.L + 0.35, Arena.L - 0.35)
	target.z = clampf(target.z, -Arena.W + 0.35, Arena.W - 0.35)
	target.y = R
	var moved := target - global_position
	moved.y = 0.0
	global_position = target
	var axis := Vector3.UP.cross(moved)
	if axis.length() > 0.0001:
		visual.global_rotate(axis.normalized(), moved.length() / R)


func kick(p: Player, vel: Vector3, type: String, target: Player = null, spin_y := 0.0,
		is_power := false, is_quick := false) -> void:
	carrier = null
	freeze = false
	collision_mask = Arena.LAYER_WORLD if is_quick else Arena.LAYER_WORLD | Arena.LAYER_PLAYER
	linear_velocity = vel
	angular_velocity = Vector3.ZERO
	last_touch = p
	kick_type = type
	pass_target = target
	kick_t = game.t
	spin = spin_y
	power = is_power
	quick = is_quick
	wall_touch = false
	near_miss = false
	if type != "pass":
		charge = 0.0
	no_pickup[p] = game.t + (0.2 if type == "flick" else 0.35)
	game.sfx.play("boom" if is_power else "kick")
	fx.kicked(type)


func give(p: Player) -> void:
	var from := last_touch
	if from == null or from.team != p.team:
		charge = 0.0
	carrier = p
	freeze = true
	collision_mask = Arena.LAYER_WORLD
	linear_velocity = Vector3.ZERO
	spin = 0.0
	power = false
	quick = false
	last_touch = p
	kick_type = ""
	pass_target = null
	game.on_possession(p.team, from)
	game.sfx.play("touch")
	p.on_receive(from)


func reset_to_center() -> void:
	carrier = null
	freeze = false
	global_position = Vector3(0, 3, 0)
	linear_velocity = Vector3.ZERO
	kick_type = ""
	last_touch = null
	charge = 0.0


func _try_pickup() -> void:
	if global_position.y > 1.25:
		return
	var best: Player = null
	var bd := 99.0
	for p: Player in game.players:
		if p.stun_t > 0.0 or no_pickup.get(p, -1.0) > game.t:
			continue
		if quick and last_touch and p.team != last_touch.team:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		var reach := 1.1 if p.is_keeper else 0.75
		if kick_type == "pass" and last_touch and p.team == last_touch.team:
			reach += 0.9 * p.charge_assist()   # a charged ball is easier to receive
		if d < reach and d < bd:
			best = p
			bd = d
	if best:
		receive(best)


## Someone reaches the loose ball: saves, parries, interceptions and completed passes are judged here.
func receive(p: Player) -> void:
	var spd := linear_velocity.length()
	var from := last_touch
	var rival := from != null and from.team != p.team
	var note := ""
	var amt := 0.0
	if p.is_keeper and rival and kick_type == "shot":
		if power:
			# Power shots blast straight through the keeper.
			p.stun_t = 0.8
			p.knock = Vector3(linear_velocity.x, 0, linear_velocity.z).normalized() * 5.0
			no_pickup[p] = game.t + 1.0
			add_collision_exception_with(p)
			get_tree().create_timer(0.8).timeout.connect(remove_collision_exception_with.bind(p))
			game.comic("KAPOW!", p.global_position, Color("ff3b30"))
			game.shake(0.6)
			return
		if spd > 25.0:
			linear_velocity = Vector3(-linear_velocity.x * 0.35, 4.0, linear_velocity.z * 0.4 + randf_range(-5, 5))
			kick_type = "parry"
			spin = 0.0
			last_touch = p
			no_pickup[p] = game.t + 0.6
			game.feed(p.team, "PARRY!", 8, from)
			game.comic("PARRY!", p.global_position, Color("2de2e6"))
			game.sfx.play("thud")
			game.sfx.play("gasp")
			return
		note = "SAVE!"
		amt = 12.0
		game.sfx.play("gasp")
	elif rival and spd > 24.0 and not p.is_keeper:
		no_pickup[p] = game.t + 0.25  # too hot to trap: it deflects off the body
		return
	elif from and kick_type == "pass":
		if rival:
			note = "INTERCEPTION!"
			amt = 15.0
		else:
			game.on_pass_complete(from, p, wall_touch)
	give(p)  # possession first, so the exposure rule runs before the taker feeds
	if note != "":
		game.feed(p.team, note, amt, from)


func _on_body_entered(body: Node) -> void:
	if carrier or body.is_in_group("floor"):
		return
	spin = 0.0
	var spd := linear_velocity.length()
	var hard := body.is_in_group("wall") or body.is_in_group("cage") or body.is_in_group("brick")
	if hard and spd > 6.0:
		game.sfx.play("thud", linear_to_db(clampf(spd / 25.0, 0.2, 1.0)))
		if spd > 18.0:
			game.comic("BAM!", global_position, Color("ffe100"), 0.8)
			game.shake(0.25)
	if body.is_in_group("wall") and kick_type == "pass":
		wall_touch = true
	if kick_type == "shot" and not near_miss and last_touch:
		var by_goal := absf(global_position.x) > Arena.L - 1.0 and absf(global_position.z) < Arena.GOAL_HALF + 1.5
		if body.is_in_group("brick") or (body.is_in_group("wall") and by_goal):
			near_miss = true
			game.hud.popup(last_touch.team, "SO CLOSE!")
			game.sfx.play("gasp")
