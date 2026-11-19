extends SceneTree

const Race = preload("res://systems/midnight.gd")
const Progress = preload("res://systems/progress.gd")
var game
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func _run() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	var saved: Dictionary = game.progress.checkpoint.duplicate()
	var race = game.midnight
	var start: Vector3 = game.runner.position
	game.command("midnight")
	_expect(game.campaign.activity == "midnight" and game.world.circuit_lighting, "circuit enters at night")
	game._test_inputs = true
	game.control_axis = Vector2.UP * -1.0
	Input.action_press("v_boost")
	await create_timer(.8, false, true).timeout
	_expect(game.runner.position.distance_to(start) < .2 and race.elapsed == 0.0, "countdown locks racer and clock")
	var before: float = race.count
	game.command("pause_hud")
	await create_timer(.3, false, true).timeout
	_expect(is_equal_approx(race.count, before), "pause holds countdown")
	game.command("resume")
	var first: Vector3 = Race.GATES[0]
	var dir: Vector3 = race.direction(0)
	_expect(race._cross_fraction(first+dir, first-dir, first, dir, 5.0, 3.4) < 0.0, "backward gate crossing rejected")
	_expect(race._cross_fraction(first-dir+Vector3.RIGHT*6, first+dir+Vector3.RIGHT*6, first, dir, 5.0, 3.4) < 0.0, "wide gate miss rejected")
	_expect(is_equal_approx(race._cross_fraction(first-dir, first+dir, first, dir, 5.0, 3.4), .5), "forward segment detects precise crossing")
	var triggered := false
	# Follow the course using real movement and collisions, braking before each corner.
	for frame in range(60*55):
		if not race.finish_grade.is_empty():
			break
		var at: Vector3 = game.runner.position
		var i: int = race.gate
		var target: Vector3 = Race.GATES[i] + race.direction(i) * .55
		target.y = at.y
		var offset := target - at
		if Race.TURNS.has(i) and offset.length() < 22.0:
			Input.action_release("v_boost")
		else:
			Input.action_press("v_boost")
		game.control_axis = Vector2(offset.x, -offset.z).normalized()
		triggered = triggered or race.pad_time > 0.0
		await physics_frame
	Input.action_release("v_boost")
	Input.action_release("v_sprint")
	_expect(triggered, "real runner hit at least one boost strip")
	_expect(race.gate == 12 and not race.finish_grade.is_empty(), "runner completed all 12 gates, reached %d at %s time %.3f" % [race.gate,game.runner.position,race.elapsed])
	_expect(race.elapsed < Race.GOLD, "gold is achievable on standard stats: %.3f" % race.elapsed)
	_expect(game.progress.midnight_splits.size() == 12 and game.progress.best_time == 0.0, "best splits recorded independently of Calder time")
	var reload := Progress.new()
	reload.setup(null)
	_expect(reload.midnight_splits == game.progress.midnight_splits, "best survives reload")
	var elapsed: float = race.elapsed
	await create_timer(.4, false, true).timeout
	_expect(is_equal_approx(elapsed,race.elapsed), "finish freezes timer")
	game.command("restart")
	_expect(race.gate == 0 and race.count > 0.0 and race.previous_splits.size() == 12, "retry resets progress and loads comparison splits")
	game.command("next")
	_expect(game.campaign.activity == "campaign" and not game.world.circuit_lighting and not race.visible, "leaving restores campaign lighting")
	_expect(saved == game.progress.checkpoint, "campaign checkpoint preserved")
	print("MIDNIGHT_CIRCUIT ", "PASS" if errors.is_empty() else "FAIL", " run=", elapsed, " errors=", errors.size())
	game.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
