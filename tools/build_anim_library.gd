extends SceneTree
## Merges every Mixamo clip in res://animations/ into res://animations/soccer_library.res.
## Run: godot --headless --path . --script tools/build_anim_library.gd
## Clips become snake_case ("Soccer Idle" -> soccer_idle); "(1)" duplicates are skipped.
## Hips x/z travel is pinned so clips play in place: the body is moved by gameplay code.

const DIR := "res://animations/"
const OUT := "res://animations/soccer_library.res"
const LOOPS := ["idle", "jog", "dribble", "dancing", "walk", "strafe"]


func _init() -> void:
	var lib := AnimationLibrary.new()
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".fbx") or "(" in f:
			continue
		var scene := (load(DIR + f) as PackedScene).instantiate()
		var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		var clip: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		var key := f.get_basename().to_lower().replace(" ", "_")
		clip.loop_mode = Animation.LOOP_LINEAR if LOOPS.any(func(l: String) -> bool: return l in key) else Animation.LOOP_NONE
		var t := clip.find_track(NodePath("Skeleton3D:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		if t >= 0:
			var p0: Vector3 = clip.position_track_interpolate(t, 0.0)
			for k in clip.track_get_key_count(t):
				var p: Vector3 = clip.track_get_key_value(t, k)
				clip.track_set_key_value(t, k, Vector3(p0.x, p.y, p0.z))
		lib.add_animation(key, clip)
		scene.free()
	print("VERIFY: ", ResourceSaver.save(lib, OUT), " ", lib.get_animation_list().size(), " clips")
	quit()
