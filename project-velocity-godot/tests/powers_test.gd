extends SceneTree

const Powers := preload("res://systems/powers.gd")
const Combat := preload("res://systems/combat.gd")
const Population := preload("res://systems/population.gd")
const RunnerRig := preload("res://assets/velocity-runner.glb")
const STEP := 1.0 / 60.0


class TestGame extends Node3D:
	var runner := CharacterBody3D.new()
	var powers := Powers.new()
	var combat := Combat.new()
	var population := Population.new()
	var animations: AnimationPlayer
	var hero_heading := 0.0
	var speed := 0.0
	var health := 100.0
	var energy := 100.0
	var safe_position := Vector3.ZERO
	var realm := "city"
	var paused := false
	var effects := true
	var quality := 2
	var events: Array[Dictionary] = []

	func _ready() -> void:
		runner.collision_layer = 2
		runner.collision_mask = 1 | 4 | 8
		var collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.40
		capsule.height = 1.8
		collider.shape = capsule
		collider.position.y = 0.90
		runner.add_child(collider)
		add_child(runner)
		var suit: Node3D = RunnerRig.instantiate()
		runner.add_child(suit)
		animations = suit.find_child("AnimationPlayer", true, false) as AnimationPlayer
		add_child(combat)
		add_child(population)
		add_child(powers)
		combat.setup(self)
		population.setup(self)
		powers.setup(self)

	func event(id: String, payload: Dictionary = {}) -> void:
		events.append({"id": id, "payload": payload})

	func announce(_label: String, _duration: float = 1.0) -> void:
		pass

	func pulse(_label: String, _at: Vector3, _strength: float) -> void:
		pass

	func damage(amount: float) -> void:
		health -= amount

	func teleport(at: Vector3, destination: String) -> void:
		realm = destination
		runner.position = at
		safe_position = at
		runner.force_update_transform()
		powers.clear_realm()


var _game := TestGame.new()
var _checked := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(_game)
	await physics_frame
	await _test_lightning()
	await _test_area_powers()
	await _test_phase()
	await physics_frame
	_test_time_and_redirect()
	_test_mirage_and_portal()
	print("Powers assertions: %d, failures: %d" % [_checked, _failed])
	quit(0 if _failed == 0 else 1)


func _test_lightning() -> void:
	_new_encounter()
	var open := _game.combat.spawn("open", Vector3(0, 0, -8), "guard")
	await physics_frame
	_expect(_game.powers.command("lightning"), "Lightning accepted a clear cast")
	_expect(is_equal_approx(_game.energy, 88.0) and _game.powers.cooldown_left("lightning") > 1.0, "Cast charged energy and set cooldown")
	_expect(not _game.powers.command("lightning") and is_equal_approx(_game.energy, 88.0), "Pending casts reject duplicate charges")
	_expect(is_equal_approx(float(open.data.hp), 46.0), "Lightning has a windup")
	_ticks(31)
	_expect(float(open.data.hp) < 46.0 and _event("lightning_hit").get("id") == "open", "Traveling electricity damaged a live enemy")

	_new_encounter()
	var cover := _box(Vector3(0, 1, -4.0), Vector3(4, 2, 0.45), 1)
	var shielded := _game.combat.spawn("covered", Vector3(0, 0, -4.58), "guard")
	await physics_frame
	_expect(_game.powers.command("lightning"), "Lightning can be aimed at cover")
	_ticks(34)
	_expect(is_equal_approx(float(shielded.data.hp), 46.0) and _event("lightning_hit").is_empty(), "Thin cover blocks electricity even next to the target")
	cover.queue_free()

	_new_encounter()
	var relay := _box(Vector3(1.6, 0, -7.0), Vector3(0.8, 1.8, 0.6), 1)
	var relay_collider: CollisionShape3D = relay.get_child(0)
	relay_collider.position.y = 0.9
	var shield := _box(Vector3(0.8, 1, -3.5), Vector3(3.5, 2, 0.35), 1)
	_game.powers.register_target("relay", relay)
	await physics_frame
	_expect(_game.powers.command("lightning"), "Obstructed relay can be tested with a cast")
	_ticks(33)
	_expect(_event("lightning_hit").is_empty(), "A registered target does not cause lightning through walls")
	shield.queue_free()
	_ticks(57)
	await physics_frame
	_expect(_game.powers.command("lightning"), "Relay accepts a second cast after the cooldown")
	_ticks(32)
	_expect(_event("lightning_hit").get("id") == "relay", "A forward lightning cast acquired the visible relay and hit its actual collider")
	relay.queue_free()


func _test_area_powers() -> void:
	_new_encounter()
	var foe := _game.combat.spawn("radius", Vector3(0, 0, -4), "guard")
	var barrel := _game.population.spawn("barrel.shock", "prop", Vector3(3, 0, -2))
	await physics_frame
	_expect(_game.powers.command("shockwave"), "Shockwave accepted the available charge")
	_ticks(18)
	_expect(float(foe.data.hp) < 46.0 and Vector3(barrel.vel).length() > 1.0, "Shockwave hit both fighter and lightweight prop")
	_expect(int(_event("shockwave_hit").get("count", 0)) >= 2, "Shockwave reported affected targets")
	_game.population.deactivate("barrel.shock")

	_new_encounter()
	var vortex_target := _game.population.spawn("barrel.vortex", "prop", Vector3(4, 0, 0))
	await physics_frame
	_expect(_game.powers.command("tornado"), "Vortex accepted the available charge")
	_ticks(18)
	var first := Vector3(vortex_target.vel)
	_expect(first.x < -1.0 and first.z > 1.0, "Vortex pulls the prop inward and adds tangential force")
	_ticks(24)
	_expect(Vector3(vortex_target.vel).length() > first.length() and Vector3(vortex_target.vel).length() <= 15.5, "Repeated, bounded vortex pulses applied force")
	_ticks(170)
	var stopped := Vector3(vortex_target.vel)
	_ticks(36)
	_expect(Vector3(vortex_target.vel).is_equal_approx(stopped), "Vortex stopped applying force when its duration ended")
	_game.population.deactivate("barrel.vortex")


func _test_phase() -> void:
	_new_encounter()
	var wall := _box(Vector3(0, 1, -3), Vector3(3.0, 2.0, 1.2), 4)
	await physics_frame
	_expect(_game.powers.command("phase"), "Phase activated without a windup")
	_expect(_game.powers.phased() and _game.runner.collision_mask == (1 | 8), "Phase removed only the eligible collision layer")
	var snapshot := _game.powers.snapshot()
	var original := _game.runner.global_position
	_game.runner.global_position = Vector3(0, 0, -3)
	_game.runner.force_update_transform()
	_ticks(108)
	_expect(_game.powers.phased() and _event("phase_exited").is_empty(), "An obstructed exit got a brief extension")
	_ticks(32)
	_expect(not _game.powers.phased() and _game.runner.collision_mask == (1 | 4 | 8), "Expired phase restored the original layer")
	_expect(_game.runner.global_position.is_equal_approx(original) and bool(_event("phase_exited").get("recovered", false)), "Obstructed phase returned to last safe ground")
	_game.powers.restore(snapshot)
	_expect(_game.powers.phased() and _game.runner.collision_mask == (1 | 8), "Rewind reinstates saved phase and collision state")
	_game.runner.global_position = Vector3(0, 0, -5)
	_game.runner.force_update_transform()
	_ticks(113)
	_expect(not _game.powers.phased() and _game.runner.global_position.z < -4.9 and not bool(_event("phase_exited").get("recovered", true)), "Phase can expire safely beyond an eligible wall")
	_game.powers.reset()
	_expect(_game.powers.command("phase") and _game.powers.phased(), "Phase can be used again after reset")
	var cost: float = _game.energy
	_expect(_game.powers.command("phase") and not _game.powers.phased() and is_equal_approx(_game.energy, cost), "Phase can end early without charging again")
	wall.queue_free()


func _test_time_and_redirect() -> void:
	_new_encounter()
	var foe := _game.combat.spawn("bolt_source", Vector3(0, 0, -9), "guard")
	_expect(not _game.powers.command("redirect") and is_equal_approx(_game.energy, 100.0), "Redirect without an inbound projectile spent no energy")
	_expect(_game.powers.command("slow"), "Slow time accepted the available charge")
	_ticks(5)
	var projectile := _game.powers.spawn_hostile(Vector3(0, 0.95, -6), Vector3(0, 0, 9), 9.0)
	_ticks(14)
	_expect(is_equal_approx(_game.powers.slow_factor(), 0.34), "World actors receive a bounded slow-time multiplier")
	var slow_view := _game.powers.snapshot()
	var offset := Vector3(_game.powers.bolts[0].pos).z + 6.0
	_expect(is_equal_approx(offset, 14.0 * STEP * 9.0 * 0.34), "Hostile projectile moved using its own scaled clock")
	_expect(_game.powers.command("redirect"), "An approaching original projectile can be intercepted")
	_ticks(6)
	var reflected := _game.powers.bolts[0]
	_expect(int(reflected.id) == projectile and not bool(reflected.hostile) and Vector3(reflected.v).z < 0.0, "Redirect preserves projectile identity and changes faction and direction")
	_expect(int(_event("projectile_redirected").get("id", -1)) == projectile, "Redirect emitted the reflected projectile identity")
	_ticks(17)
	_expect(float(foe.data.hp) < 46.0 and is_equal_approx(_game.health, 100.0), "Redirected projectile hit a live foe instead of harming the runner")
	_game.powers.restore(slow_view)
	_expect(_game.powers.bolts.size() == 1 and bool(_game.powers.bolts[0].hostile) and int(_game.powers.bolts[0].id) == projectile, "Rewind restored the original hostile projectile instead of retaining its reflection")
	_game.powers.clear_realm()
	_expect(_game.powers.bolts.is_empty() and is_equal_approx(_game.powers.slow_factor(), 1.0), "Realm changes clear time effects and projectiles")
	_game.powers.spawn_hostile(Vector3(0, 0.95, -2), Vector3(0, 0, 12), 9.0)
	_ticks(13)
	_expect(is_equal_approx(_game.health, 91.0) and _game.powers.bolts.is_empty(), "Unredirected projectiles collide with and hurt the runner")
	_expect(_game.powers.command("phase"), "Phase can be activated during projectile combat")
	_game.powers.spawn_hostile(Vector3(0, 0.95, -2), Vector3(0, 0, 12), 9.0)
	_ticks(15)
	_expect(is_equal_approx(_game.health, 91.0) and _game.powers.bolts.size() == 1, "Hostile projectiles pass through a phased runner")


func _test_mirage_and_portal() -> void:
	_new_encounter()
	_expect(not _game.powers.command("mirage"), "Mirage requires a captured movement history")
	for i in range(48):
		_game.runner.global_position = Vector3(float(i) * 0.13, 0, 0)
		_game.speed = 7.8
		var clip := "Jog" if i < 24 else "Heavy"
		_game.animations.play(clip)
		_game.animations.seek(0.21, true)
		_ticks(1)
	_expect(_game.powers.command("mirage"), "Mirage captured an actual recent route")
	_ticks(7)
	var start := _game.powers.decoy_position(Vector3.ZERO, 15.0)
	var trace := _game.powers.snapshot()
	_expect("Jog" in trace.mirage_clips and "Heavy" in trace.mirage_clips and is_equal_approx(trace.mirage_frames[0], 0.21), "Mirage samples the actual animation clips and frame positions")
	_ticks(68)
	var current := _game.powers.decoy_position(Vector3.ZERO, 15.0)
	_expect(start.is_finite() and current.is_finite() and current.x > start.x + 1.0, "AI can see a mirage that follows historical position and pose")
	_game.powers.restore(trace)
	_game.powers.render_restored()
	_expect(_game.powers.decoy_position(Vector3.ZERO, 15.0).is_equal_approx(start), "Mirage presentation and position can be rewound")
	_ticks(230)
	_expect(not _game.powers.decoy_position(Vector3.ZERO, 15.0).is_finite(), "The mirage became unavailable after its replay")
	_expect(not _game.powers.command("portal"), "Portal cannot be opened away from its gate")
	_game.runner.global_position = _game.powers.CITY_PORTAL + Vector3.UP * 15.0
	_expect(not _game.powers.command("portal"), "Portal cannot be triggered high above the anchor")
	_game.runner.global_position = _game.powers.CITY_PORTAL
	_expect(_game.powers.command("portal"), "A portal begins a windup at the anchor")
	_game.runner.global_position += Vector3.LEFT * 15.0
	_ticks(16)
	_expect(_game.realm == "city" and is_zero_approx(_game.powers.cooldown_left("portal")), "Leaving an anchor during the windup cancels travel and cooldown")
	_game.runner.global_position = _game.powers.CITY_PORTAL
	_expect(_game.powers.command("portal"), "City gate can perform portal travel")
	_ticks(16)
	_expect(_game.realm == "rift" and _game.runner.position.is_equal_approx(_game.powers.RIFT_ARRIVAL) and not _event("portal_entered").is_empty(), "Portal entered the rift at a dedicated arrival")
	_ticks(105)
	_game.runner.global_position = _game.powers.RIFT_EXIT
	_expect(_game.powers.command("portal"), "Rift exit enables a return cast")
	_ticks(16)
	_expect(_game.realm == "city" and _game.runner.position.is_equal_approx(_game.powers.CITY_RETURN) and not _event("portal_returned").is_empty(), "Portal round trip returned to the city gate")


func _new_encounter() -> void:
	_game.combat.clear_encounter()
	_game.powers.reset()
	_game.runner.position = Vector3.ZERO
	_game.runner.force_update_transform()
	_game.safe_position = Vector3.ZERO
	_game.health = 100.0
	_game.energy = 100.0
	_game.events.clear()


func _box(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_game.add_child(body)
	return body


func _ticks(count: int) -> void:
	for i in range(count):
		_game.powers.step(STEP)


func _event(id: String) -> Dictionary:
	for i in range(_game.events.size() - 1, -1, -1):
		if _game.events[i].id == id:
			return _game.events[i].payload
	return {}


func _expect(condition: bool, label: String) -> void:
	_checked += 1
	if not condition:
		_failed += 1
		push_error(label)
