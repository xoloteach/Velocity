extends SceneTree

const Level = preload("res://scenes/game.tscn")


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	var game: Node = Level.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var names := ["Low", "Medium", "High", "Ultra"]
	for q in range(4):
		game.configure_settings("quality", q, false)
		for _warmup in range(8):
			await process_frame
		var samples: Array[float] = []
		for _i in range(45):
			var t0 := Time.get_ticks_usec()
			await process_frame
			var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0
			samples.append(dt_ms)
		samples.sort()
		var sum := 0.0
		for v in samples:
			sum += v
		var avg_ms := sum / float(samples.size())
		var p95_ms: float = samples[mini(samples.size() - 1, int(floor(samples.size() * 0.95)))]
		var w_info: Dictionary = game.world.stats() if game.world.has_method("stats") else {}
		print("PRESET_BENCH %s quality=%d scale=%.2f shadows=%s far=%.0f avg_ms=%.2f p95_ms=%.2f resident=%d cap=%d" % [
			names[q],
			q,
			root.scaling_3d_scale,
			str(game.world.sun.shadow_enabled),
			game.camera.far,
			avg_ms,
			p95_ms,
			int(w_info.get("resident", 0)),
			int(w_info.get("cap", 0)),
		])
	game.queue_free()
	await process_frame
	await process_frame
	quit(0)
