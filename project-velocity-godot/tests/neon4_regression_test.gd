extends SceneTree

const Main = preload("res://main.tscn")
const PopArt = preload("res://systems/population_art.gd")

const EXPECTED_CLIPS := [
	"idle", "walk", "jog", "run", "sprint", "boost_sprint", "extreme_sprint",
	"wall_run_left", "wall_run_right", "water_run", "jump", "fall", "land",
	"dodge", "slide", "attack_1", "attack_2", "attack_3", "heavy_attack",
	"counter", "hit_react", "knockdown", "get_up", "cast_lightning", "phase",
	"rewind", "tornado", "shockwave", "victory",
]

const EXPECTED_AUDIO := [
	"ambience", "boss_score", "boost", "counter", "footstep", "hit", "impact",
	"lightning", "mission", "phase", "portal", "rewind", "rift_ambience",
	"score", "shockwave", "slow", "sonic", "tornado", "ui",
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
	pop_art.setup()
	for variant in range(4):
		var car := pop_art.vehicle("car", variant, 4.4)
		var root_node: Node3D = car["root"]
		var wheels: Array = car.get("wheels", [])
		_check(wheels.size() == 4, "Civilian car variant %d has 4 wheel pivots" % variant)
		_check(root_node.get_node_or_null("ContactShadow") != null, "Civilian car variant %d has contact shadow" % variant)
		root_node.free()
	for kind in ["van", "police"]:
		var heavy := pop_art.vehicle(kind, 1, 5.1)
		var hroot: Node3D = heavy["root"]
		_check((heavy.get("wheels", []) as Array).size() == 4, "%s has 4 wheel pivots" % kind)
		_check(hroot.get_node_or_null("ContactShadow") != null, "%s has contact shadow" % kind)
		hroot.free()
	var human := pop_art.human(2, false)
	var h_node: Node3D = human["root"]
	_check((human.get("legs", []) as Array).size() == 2 and (human.get("arms", []) as Array).size() == 2, "Human rig exposes 2 legs and 2 arms")
	_check(h_node.get_node_or_null("ContactShadow") != null, "Human rig has contact shadow")
	h_node.free()

	# 5. Boot full game scene and test Neon 4 runtime integrations.
	var game: Node = Main.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	_check(game.runner.get_node_or_null("RunnerShadow") != null, "Hero has grounded RunnerShadow disc")

	# Combat bespoke bosses & archetypes + contact shadows + counter halos.
	var specs := [
		{"id": "n4_dark", "name": "Nullstride", "role": "rival_dark", "boss": true, "hp": 120.0, "position": Vector3(8.0, 0.0, -8.0)},
		{"id": "n4_yellow", "name": "Afterlight", "role": "rival_yellow", "boss": true, "hp": 120.0, "position": Vector3(-8.0, 0.0, -8.0)},
		{"id": "n4_guard", "name": "Guard", "role": "guard", "hp": 60.0, "position": Vector3(0.0, 0.0, -14.0)},
		{"id": "n4_speed", "name": "Speedster", "role": "speedster", "hp": 70.0, "position": Vector3(4.0, 0.0, -14.0)},
	]
	game.combat.spawn(specs)
	_check(game.combat.enemies.size() == 4, "Combat spawns all 4 Neon 4 enemy archetypes")
	for enemy in game.combat.enemies:
		var node: Node3D = enemy.node
		_check(node.get_node_or_null("ContactShadow") != null, "Enemy %s has ContactShadow" % enemy.id)
		_check(node.get_node_or_null("CounterHalo") != null, "Enemy %s has CounterHalo" % enemy.id)
	game.combat.clear()

	# Phase shader material override & clean restore.
	game.powers.cooldowns.clear()
	game.energy = 100.0
	var hero_mesh := _first_mesh(game.suit)
	_check(hero_mesh != null, "Hero suit contains mesh for phase shader test")
	game.powers.cast("phase")
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
