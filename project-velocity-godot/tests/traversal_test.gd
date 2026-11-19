extends SceneTree

const Level = preload("res://scenes/game.tscn")
var game
var failed: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func _require(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:
		failed.append(label)


func _input(name_: String, enabled: bool) -> void:
	if enabled:
		Input.action_press("v_"+name_)
	else:
		Input.action_release("v_"+name_)


func _body(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var box := BoxShape3D.new()
	box.size = dimensions
	var col := CollisionShape3D.new()
	col.shape = box
	body.add_child(col)
	game.add_child(body)
	body.position = at
	return body


func _run() -> void:
	game=Level.instantiate()
	root.add_child(game)
	game.campaign.choose_activity("patrol")
	game.population.set_patrol(false)
	await _frames(18)
	var baseline: Dictionary = game.velocity_profile(1.0)
	var previously := 0.0
	var monotonic := true
	for index in range(10,101):
		var value: float = game.velocity_profile(index*.01).limiter
		monotonic = monotonic and previously<value
		previously=value
	_require(monotonic and is_equal_approx(previously,1.0),"Limiter is finite and strictly monotonic")
	game.progress.stats["speed"]=1
	var fast: Dictionary=game.velocity_profile(1.0)
	_require(fast.top>baseline.top and fast.turning==baseline.turning and fast.acceleration==baseline.acceleration,
		"Speed upgrade affects physical top speed independently")
	game.progress.stats["turn"]=1
	game.progress.stats["accel"]=1
	var response: Dictionary=game.velocity_profile(1.0)
	_require(response.turning>fast.turning and response.acceleration>fast.acceleration and response.top==fast.top,
		"Acceleration and turning have independent movement hooks")
	game.progress.stats["speed"]=33
	game.teleport(Vector3(0,0,24))
	await _frames(9)
	_input("forward",true)
	_input("boost",true)
	var saw_transit := false
	var peak := 0.0
	for _frame in 160:
		await physics_frame
		saw_transit = saw_transit or game.transit_active
		peak = maxf(peak,game.speed)
	_input("forward",false)
	_input("boost",false)
	_require(saw_transit and peak>response.top and peak<=165.0,"Authored straight road enables bounded extreme transit at high rank")
	await _frames(65)
	_require(not game.transit_active and game.speed<1.0 and game.runner.position.is_finite(),
		"Releasing the controls brakes extreme transit without invalid coordinates")
	print("Peak measured physical speed ",peak," m/s")
	game.teleport(Vector3(0,0,23))
	var obstacle := _body(Vector3(0,1,-7),Vector3(12,2,.22))
	await _frames(12)
	_input("forward",true)
	_input("boost",true)
	await _frames(112)
	_input("forward",false)
	_input("boost",false)
	_require(game.runner.position.z>-6.9 and not game.transit_active,
		"A 22cm collider blocks a high-speed swept capsule")
	obstacle.queue_free()
	game.teleport(Vector3(0,0,3))
	await _frames(10)
	_input("forward",true)
	_input("sprint",true)
	await _frames(35)
	var wall := _body(Vector3(.93,2.5,-24),Vector3(.25,5,60))
	await _frames(5)
	game.command("jump")
	var reached_wall := false
	for _frame in 36:
		await physics_frame
		reached_wall = reached_wall or game.wall_riding
	_require(reached_wall and game.runner.position.y>.50,"Sprint and jump attach to the wall tangent")
	_input("forward",false)
	_input("sprint",false)
	wall.queue_free()
	game.teleport(Vector3(-114,0,-145))
	await _frames(9)
	game.safe_position=Vector3(-106,.02,-145)
	game.runner.position=Vector3(-114,.02,-145)
	game.runner.velocity=Vector3(-42,0,0)
	game.orbit.x=PI/2.0
	_input("forward",true)
	_input("boost",true)
	await _frames(8)
	_require(game.on_water and game.speed>24.0 and game.runner.position.x<-115.0,
		"Fast motion runs across the real canal surface")
	_input("forward",false)
	_input("boost",false)
	await _frames(65)
	_require(not game.on_water and not game.world.water_at(game.runner.position),
		"Below the required speed the runner recovers on safe land")
	game.queue_free()
	await process_frame
	quit(0 if failed.is_empty() else 1)
