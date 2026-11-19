extends SceneTree

const Level = preload("res://scenes/game.tscn")
const PopArt = preload("res://systems/population_art.gd")

const EXPECTED_CLIPS := [
	"Idle", "Walk", "Jog", "Sprint", "Boost", "Wall", "Water", "Air", "Brake",
	"Jab", "Heavy", "Counter", "Dodge", "Slide", "Hit", "Launch", "Land",
	"Fall", "Rise", "Takedown", "Cast", "Phase", "Portal", "Slow", "Mirage",
	"Tornado", "Shockwave", "Redirect", "Turn",
]

const EXPECTED_AUDIO := [
	"atmosphere", "boost", "boss_score", "counter", "damage", "goal", "hit",
	"jump", "land", "lightning", "phase", "portal", "rewind", "rift_ambience",
	"score", "shockwave", "slide", "step", "wind",
]

const EXPECTED_SHADERS := [
	"world_facade", "world_asphalt", "world_sky", "world_water",
	"contact_shadow", "hero_phase",
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.push_back(label)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _run() -> void:
	# 1. Verify all 3 bespoke character/boss GLBs and their 29 animation clips.
	for path in [
		"res://assets/velocity-runner.glb",
		"res://assets/nullstride-boss.glb",
		"res://assets/afterlight-boss.glb",
	]:
		var scene: PackedScene = load(path)
		_check(scene != null, "GLB loads: %s" % path)
		if scene != null:
			var inst := scene.instantiate()
			var anim := _find_anim_player(inst)
			_check(anim != null, "GLB has AnimationPlayer: %s" % path)
			if anim != null:
				var list := PackedStringArray(anim.get_animation_list())
				var missing := 0
				for clip in EXPECTED_CLIPS:
					if not list.has(clip):
						missing += 1
				_check(missing == 0, "GLB exposes all 29 clips (%d missing): %s" % [missing, path])
			inst.free()

	# 2. Verify all 19 WAV audio cues load cleanly.
	for cue in EXPECTED_AUDIO:
		var stream: AudioStream = load("res://assets/audio/%s.wav" % cue)
		_check(stream != null, "Audio cue loads: %s.wav" % cue)

	# 3. Verify all 6 custom shaders compile/load cleanly.
	for shader_name in EXPECTED_SHADERS:
		var sh: Shader = load("res://assets/%s.gdshader" % shader_name)
		_check(sh != null, "Shader loads: %s.gdshader" % shader_name)

	# 4. Verify PopulationArt vehicle wheels, silhouettes, and sculpted human rigs.
	var pop_art := PopArt.new()
	for variant in range(4):
		var host := Node3D.new()
		var car := pop_art.vehicle(host, "car", variant)
		var wheels: Array = car.get("wheels", [])
		_check(wheels.size() == 4, "Civilian car variant %d has 4 wheel pivots" % variant)
		_check(host.get_node_or_null("ContactShadow") != null, "Civilian car variant %d has contact shadow" % variant)
		host.free()
	for kind in ["van", "police"]:
		var hhost := Node3D.new()
		var heavy := pop_art.vehicle(hhost, kind, 1)
		_check((heavy.get("wheels", []) as Array).size() == 4, "%s has 4 wheel pivots" % kind)
		_check(hhost.get_node_or_null("ContactShadow") != null, "%s has contact shadow" % kind)
		hhost.free()
	var h_node := Node3D.new()
	var human := pop_art.human(h_node, 2, false)
	_check((human.get("legs", []) as Array).size() == 2 and (human.get("arms", []) as Array).size() == 2, "Human rig exposes 2 legs and 2 arms")
	_check(h_node.get_node_or_null("ContactShadow") != null, "Human rig has contact shadow")
	h_node.free()

	# 5. Boot full game scene and test Neon 4 runtime integrations.
	var game: Node = Level.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	_check(game.runner.get_node_or_null("RunnerShadow") != null, "Hero has grounded RunnerShadow disc")

	# Combat bespoke bosses & archetypes + contact shadows + counter halos.
	var specs := [
		["n4_dark", Vector3(8.0, 0.0, -8.0), "rival_dark"],
		["n4_yellow", Vector3(-8.0, 0.0, -8.0), "rival_yellow"],
		["n4_guard", Vector3(0.0, 0.0, -14.0), "guard"],
		["n4_speed", Vector3(4.0, 0.0, -14.0), "speedster"],
	]
	for spec in specs:
		var foe = game.combat.spawn(spec[0], spec[1], spec[2])
		_check(foe != null, "Combat spawns archetype %s" % spec[2])
		if foe != null:
			_check(is_instance_valid(foe.shadow), "Archetype %s has ContactShadow" % spec[2])
			_check(is_instance_valid(foe.counter_halo), "Archetype %s has CounterHalo" % spec[2])
	game.combat.clear_encounter()

	# Phase shader material override & clean restore.
	game.powers.cooldowns.clear()
	game.energy = 100.0
	var hero_mesh := _first_mesh(game.suit)
	_check(hero_mesh != null, "Hero suit contains mesh for phase shader test")
	game.powers.command("phase")
	_check(game.powers.phased(), "Phase power activates cleanly")
	if hero_mesh != null:
		_check(hero_mesh.material_override != null, "Phase applies shimmering phase shader override")
	game.powers.clear_realm()
	_check(not game.powers.phased(), "Phase clears on realm reset")
	if hero_mesh != null:
		_check(hero_mesh.material_override == null, "Phase restores hero material_override to null")

	# Materials -> SFC exchange command.
	game.progress.materials = 7
	var before_credits: int = game.progress.credits
	game.command("redeem_materials")
	_check(game.progress.credits == before_credits + 2 and game.progress.materials == 1, "Redeem materials exchanges 6 materials for 2 SFC leaving 1")

	# Quality preset matrix (Low, Medium, High, Ultra).
	var expected_scales := [0.65, 0.85, 0.95, 1.0]
	var expected_shadows := [false, false, true, true]
	var expected_fars := [165.0, 240.0, 340.0, 440.0]
	for q in range(4):
		game.configure_settings("quality", q)
		_check(is_equal_approx(root.scaling_3d_scale, expected_scales[q]), "Quality %d sets scaling_3d_scale %.2f" % [q, expected_scales[q]])
		_check(game.world.sun.shadow_enabled == expected_shadows[q], "Quality %d sets sun shadows = %s" % [q, str(expected_shadows[q])])
		_check(is_equal_approx(game.camera.far, expected_fars[q]), "Quality %d sets camera.far = %.0f" % [q, expected_fars[q]])

	# Clean teardown.
	game.queue_free()
	await process_frame
	await process_frame

	for failure in failures:
		push_error(failure)
	print("NEON4_REGRESSION_CHECKS %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
