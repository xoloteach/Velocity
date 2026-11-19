extends SceneTree

const RIGS := ["velocity-runner", "nullstride-boss", "afterlight-boss"]
const LABELS := ["Idle", "Walk", "Jog", "Sprint", "Boost", "Wall", "Water", "Air", "Brake", "Jab", "Heavy", "Counter", "Dodge", "Slide", "Hit", "Launch", "Land", "Fall", "Rise", "Takedown", "Cast", "Phase", "Portal", "Slow", "Mirage", "Tornado", "Shockwave", "Redirect", "Turn"]
var failed := 0
var sampled := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for rig: String in RIGS:
		var model: Node = (load("res://assets/%s.glb" % rig) as PackedScene).instantiate()
		root.add_child(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		if player == null or skeletons.size() != 1:
			failed += 1
			push_error("Missing animation player or single skeleton: %s" % rig)
			model.free()
			continue
		var skeleton := skeletons[0] as Skeleton3D
		for label: String in LABELS:
			if not player.has_animation(label):
				failed += 1
				push_error("Missing animation: %s/%s" % [rig, label])
				continue
			var clip := player.get_animation(label)
			var valid := clip.length > 0.0 and clip.get_track_count() > 0
			var anchor := player.get_node(player.root_node)
			for track in clip.get_track_count():
				var path := clip.track_get_path(track)
				var target := anchor.get_node_or_null(NodePath(path.get_concatenated_names()))
				if target != skeleton or path.get_subname_count() != 1 or skeleton.find_bone(path.get_subname(0)) < 0:
					valid = false
			player.play(label)
			for i in range(13):
				player.seek(clip.length * float(i) / 12.0, true)
				player.advance(0.0)
				for bone in skeleton.get_bone_count():
					if not skeleton.get_bone_global_pose(bone).is_finite():
						valid = false
			if valid:
				sampled += 1
			else:
				failed += 1
				push_error("Invalid animation track or pose: %s/%s" % [rig, label])
		model.free()
	print("SOL62_ANIMATION ", sampled, "/", RIGS.size() * LABELS.size(), " valid clips; failures=", failed)
	quit(0 if failed == 0 else 1)
