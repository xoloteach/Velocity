extends SceneTree

const COMBAT = preload("res://systems/combat.gd")
const DT := 1.0 / 60.0

class PowerFixture extends Node:
	var projectiles: Array[Dictionary] = []
	var time_scale := 1.0
	var mirage := Vector3.INF
	var phase_active := false

	func slow_factor() -> float:
		return time_scale

	func decoy_position(_observer: Vector3, _radius: float) -> Vector3:
		return mirage

	func spawn_hostile(at: Vector3, velocity: Vector3, amount: float) -> int:
		projectiles.append({"position": at, "velocity": velocity, "damage": amount})
		return projectiles.size()

	func phased() -> bool:
		return phase_active

class GameFixture extends Node3D:
	var runner: CharacterBody3D
	var powers := PowerFixture.new()
	var realm := "city"
	var health := 100.0
	var hero_heading := 0.0
	var orbit := Vector2.ZERO
	var control_axis := Vector2.ZERO
	var paused := false
	var _cinema_timer := 0.0
	var events: Array[Dictionary] = []

	func announce(_message: String, _duration: float = 2.6) -> void:
		pass

	func pulse(_key: String, _where: Vector3, _strength: float = 1.0) -> void:
		pass

	func damage(amount: float) -> void:
		health = maxf(0.0, health - amount)

	func event(key: String, payload: Dictionary = {}) -> void:
		events.append({"key": key, "data": payload})

var combat
var game := GameFixture.new()
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.add_child(game)
	game.add_child(game.powers)
	game.runner = CharacterBody3D.new()
	game.runner.collision_layer = 2
	game.runner.collision_mask = 1 | 4 | 8
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.79
	var runner_shape := CollisionShape3D.new()
	runner_shape.shape = capsule
	runner_shape.position.y = 0.895
	game.runner.add_child(runner_shape)
	game.add_child(game.runner)
	_static_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	combat = COMBAT.new()
	game.add_child(combat)
	combat.setup(game)
	await physics_frame

	await _verify_melee()
	_verify_timing()
	_verify_mirage_and_real_time()
	_verify_group_pressure()
	_verify_boss("rival_dark", ["rush", "cross", "singularity"])
	_verify_boss("rival_yellow", ["feint", "relay", "feedback"])
	_verify_boss_win_through_commands("rival_dark")
	_verify_boss_win_through_commands("rival_yellow")
	if failures == 0:
		print("COMBAT_CHECKS_PASSED melee occlusion lock combo group pressure defensive timing mirage slow phases cinematic hold swept attacks projectiles gates and restore")
	quit(failures)

func _verify_melee() -> void:
	_reset()
	var foe: CharacterBody3D = combat.spawn("guard_a", Vector3(0, 0, -2.15), "guard")
	_check(foe.collision_layer == 8, "fighters have an active capsule")
	_check(combat.target_center("guard_a").is_finite(), "foes provide real target centers")
	var wall := _static_box(Vector3(0, 1, -1.07), Vector3(4, 2.4, 0.4))
	await physics_frame
	_check(combat.command("light"), "light attack inputs ahead of the contact frame")
	_tick(14)
	_check(is_equal_approx(foe.data.hp, 46.0), "world collision occludes melee")
	_check(combat.ray_target(Vector3(0, 0.9, 0), Vector3(0, 0.9, -3)) == "", "world blocks projectile target fallback")
	wall.queue_free()
	await process_frame
	await physics_frame
	_tick(10)
	_check(combat.command("lock") and combat.status().id == "guard_a", "lock acquires a visible fighter")
	_check(combat.command("heavy"), "heavy attack after recovery")
	_tick(18)
	_check(is_equal_approx(foe.data.hp, 22.0), "heavy strike lands after a real windup")
	_check(foe.data.state == "stagger", "heavy attack opens a stagger window")
	var checkpoint: Dictionary = combat.snapshot()
	_tick(25)
	_check(combat.command("interact"), "interact initiates a contextual takedown")
	_tick(15)
	_check(_count("enemy_down") == 1, "guard defeat emitted once")
	combat.restore(checkpoint)
	_check(foe.data.state == "stagger" and is_equal_approx(foe.data.hp, 22.0), "restoring a living guard restores its collision and hp")
	_check(foe.collision_layer == 8 and _count("enemy_down") == 1, "restore itself never emits defeat")
	game.realm = "rift"
	_tick(1)
	_check(not foe.visible and foe.collision_layer == 0, "actors leave collision across realms")
	_check(not combat.strike_target("guard_a", 100.0), "cross-realm target cannot be hit")

	_reset()
	foe = combat.spawn("late_contact", Vector3(0, 0, -4.20), "guard")
	_check(combat.command("light"), "light attack can begin outside range")
	_tick(7)
	_check(is_equal_approx(foe.data.hp, 46.0), "early active frames require contact")
	game.runner.global_position.z = -1.65
	_tick(3)
	_check(foe.data.hp < 46.0, "contact later in the active window still deals damage")

	_reset()
	foe = combat.spawn("camera_target", Vector3(0, 0, 2.1), "guard")
	game.orbit.x = PI
	_check(combat.target_center("camera_target").is_finite() and combat.target_position(3.0).z > 0.0, "camera direction acquires a deliberately viewed target")
	game.control_axis = Vector2(0.0, 1.0)
	_check(combat.command("dodge") and combat.dodge_velocity().z > 0.0, "directional dodge follows movement and camera")

func _verify_timing() -> void:
	_reset()
	var foe: CharacterBody3D = combat.spawn("timing_guard", Vector3(0, 0, -2.65), "guard")
	_check(_wait_for(foe, "telegraph"), "guard communicates its attack")
	_check(not combat.command("counter"), "early counter does not connect")
	while foe.data.state == "telegraph" and float(foe.data.clock) > 0.27:
		_tick(1)
	_check(combat.status().counter_window, "HUD exposes the open defense window")
	_check(combat.command("counter"), "timed counter interrupts the guard")
	_check(foe.data.state == "stagger" and _count("counter") == 1, "counter has real enemy state effects")
	_check(combat.invulnerable(), "successful counter protects during follow-through")

	_reset()
	foe = combat.spawn("dodge_guard", Vector3(0, 0, -2.35), "guard")
	_check(_wait_for(foe, "telegraph"), "second guard communicates its attack")
	while foe.data.state == "telegraph" and float(foe.data.clock) > 0.08:
		_tick(1)
	_check(combat.command("dodge") and combat.dodge_velocity().length() > 5.0, "dodge provides real movement and protection")
	_check(_wait_for(foe, "recover"), "attack reaches its recovery")
	_check(is_equal_approx(game.health, 100.0) and _count("evaded") == 1, "dodging evades the swept attack exactly once")

	_reset()
	foe = combat.spawn("sweep_guard", Vector3(0, 0, -2.3), "guard")
	_check(_wait_for(foe, "recover"), "guard must approach, tell and attack")
	_check(is_equal_approx(game.health, 90.0), "an unavoided guard sweep damages exactly once")

func _verify_mirage_and_real_time() -> void:
	_reset()
	var foe: CharacterBody3D = combat.spawn("mirage_guard", Vector3(0, 0, -3), "guard")
	game.powers.mirage = Vector3(2.3, 0, -3)
	_check(_wait_for(foe, "telegraph"), "guard attacks a believable mirage")
	_check(foe.data.aim.distance_to(game.powers.mirage) < 0.15, "mirage changes aim and facing")
	_check(_wait_for(foe, "recover") and is_equal_approx(game.health, 100.0), "mirage collision never damages the real hero remotely")

	_reset()
	foe = combat.spawn("slow_guard", Vector3(0, 0, -2.2), "guard")
	game.powers.time_scale = 0.30
	_check(combat.command("light"), "player winds up immediately in slow time")
	_tick(10)
	_check(foe.data.hp < 46.0 and foe.data.state == "approach", "local slow scales opponents and preserves hero attack cadence")

func _verify_group_pressure() -> void:
	_reset()
	var lead: CharacterBody3D = combat.spawn("lead", Vector3(0, 0, -2.31), "guard")
	var flank: CharacterBody3D = combat.spawn("flank", Vector3(-2.12, 0, -1.7), "speedster")
	var back: CharacterBody3D = combat.spawn("back", Vector3(2.09, 0, -2.1), "guard")
	game._cinema_timer = 0.7
	_tick(60)
	_check(_count("enemy_telegraph") == 0, "cinematics hold attacks before the player regains control")
	game._cinema_timer = 0.0
	_check(_wait_for(lead, "telegraph"), "group lead takes a turn first")
	_check(flank.data.state == "approach" and back.data.state == "approach", "a group allows only one attack lane")
	_check(combat.command("lock") and combat.status().id == "lead", "select a known group target")
	_check(combat.command("light"), "first light attack starts a combo")
	_tick(13)
	_check(combat.command("light"), "second light buffers in the cancel window")
	_tick(18)
	_check(combat.status().combo == 2 and _count("melee_hit") == 2, "combo chains through a real buffer")
	_check(combat.command("lock") and combat.status().id == "flank", "target switches to a different fighter")

func _verify_boss(kind: String, expected: Array) -> void:
	_reset()
	var foe: CharacterBody3D = combat.spawn(kind, Vector3(0, 0, -2.85), kind)
	var pre_phase: Dictionary = combat.snapshot()
	_check(combat.strike_target(foe, 1000.0, Vector3.ZERO, "redirect") and foe.data.phase == 1, "%s cannot skip its first tell" % kind)
	combat.restore(pre_phase)
	for phase in range(1, 4):
		game.health = 100.0
		_check(_wait_for(foe, "telegraph"), "%s phase %d enters its attack" % [kind, phase])
		_check(foe.data.attack == expected[phase - 1], "%s phase %d uses %s" % [kind, phase, expected[phase - 1]])
		_check(combat.status().phase == phase, "%s reports the current phase to HUD" % kind)
		if phase == 1:
			_check(_wait_for(foe, "recover"), "%s opening pattern has a recovery window" % kind)
		if phase == 2:
			var saved: Dictionary = combat.snapshot()
			_tick(30)
			if kind == "rival_dark":
				_check(is_equal_approx(combat.movement_factor(), 0.68), "Nullstride distorts movement only inside its phase-two tell")
				game.runner.global_position.x = 7.0
				_check(is_equal_approx(combat.movement_factor(), 1.0), "leaving the local distortion restores normal movement")
				game.runner.global_position.x = 0.0
			combat.restore(saved)
			_check(float(foe.data.clock) == float(saved.fighters[kind].data.clock), "rewind restores %s tell cadence" % kind)
			_tick(20)
		if phase == 3:
			if kind == "rival_dark":
				_check(foe.gates.size() == 2 and foe.gates[0].collision_layer == 4, "Nullstride deploys two phaseable physical gates")
				var gate: StaticBody3D = foe.gates[0]
				game.runner.global_position = Vector3(gate.global_position.x, 0.0, gate.global_position.z)
				_tick(1)
				_check(gate.collision_layer == 4, "closed gates remain solid even when a runner phases inside")
				game.runner.global_position = Vector3.ZERO
			var projectile_count := game.powers.projectiles.size()
			_check(_wait_for(foe, "recover"), "%s final pattern leaves a recovery window" % kind)
			_check(game.powers.projectiles.size() > projectile_count, "%s final pattern emits a redirectable projectile" % kind)
			_check(game.health < 100.0, "%s final pattern uses a real hazard hitbox" % kind)
			_check(combat.strike_target(kind, 1000.0, Vector3.ZERO, "heavy") and foe.data.hp > 0.0, "%s has a final defense that demands an interruption" % kind)
			_check(_wait_for(foe, "recover"), "another readable chance follows a missed window")
			if kind == "rival_yellow":
				combat.timeline_reversed()
				_check(foe.data.temporally_exposed and _count("boss_exposed") == 1, "rewind breaks Afterlight's repeat")
		var before: Dictionary = combat.snapshot()
		_check(combat.strike_target(kind, 1000.0, Vector3.ZERO, "redirect", 5.0), "redirected hit affects %s phase %d" % [kind, phase])
		if phase < 3:
			_check(foe.data.phase == phase + 1 and foe.data.state == "shift", "%s moves to its next phase" % kind)
			_check(not combat.strike_target(kind, 1000.0), "transformation cannot be skipped by repeated damage")
		else:
			_check(foe.data.state == "finish" and _count("enemy_down") == 0, "boss shows a finishing beat before notifying the campaign")
			_check(_wait_for(foe, "down") and _count("enemy_down") == 1, "one defeat closes the encounter")
			combat.restore(before)
			_check(foe.data.phase == 3 and foe.data.state == "recover" and foe.collision_layer == 8, "rewind reopens the final boss phase")
	_check(_count("boss_phase") == 2, "%s emits both phase boundaries exactly once" % kind)

func _verify_boss_win_through_commands(kind: String) -> void:
	_reset()
	var foe: CharacterBody3D = combat.spawn("duel", Vector3(0, 0, -2.70), kind)
	combat.command("lock")
	for frame in 1650:
		var status: Dictionary = combat.status()
		if status.get("counter_window", false):
			combat.command("counter")
		elif foe.data.state in ["stagger", "recover"] and not combat.hand_busy() and combat.hero_pose.is_empty():
			combat.command("heavy")
		_tick(1)
		if foe.data.state == "down":
			break
	_check(foe.data.state == "down" and _count("enemy_down") == 1, "%s can be beaten solely with exposed combat commands" % kind)
	_check(_count("boss_phase") == 2 and _count("boss_exposed") == 1 and _count("counter") >= 3, "%s cooldown, interrupts and phase gates work through timed player counters" % kind)

func _reset() -> void:
	combat.clear_encounter()
	game.realm = "city"
	game.health = 100.0
	game.hero_heading = 0.0
	game.orbit = Vector2.ZERO
	game.control_axis = Vector2.ZERO
	game.runner.global_position = Vector3.ZERO
	game.runner.velocity = Vector3.ZERO
	game.events.clear()
	game.powers.projectiles.clear()
	game.powers.mirage = Vector3.INF
	game.powers.time_scale = 1.0

func _static_box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var box := BoxShape3D.new()
	box.size = size
	var collision := CollisionShape3D.new()
	collision.shape = box
	body.add_child(collision)
	game.add_child(body)
	body.global_position = at
	return body

func _wait_for(foe: CharacterBody3D, state: String) -> bool:
	for tick in 360:
		if foe.data.state == state:
			return true
		_tick(1)
	return false

func _tick(count: int) -> void:
	for tick in count:
		combat.step(DT)

func _count(key: String) -> int:
	var result := 0
	for entry in game.events:
		if entry.key == key:
			result += 1
	return result

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("COMBAT_CHECK_FAILED %s" % message)
