extends SceneTree
## Exercises the authored campaign on the production scene. Waypoints between
## objectives are reached by controlled fixture placement when not under test.

const Level = preload("res://scenes/game.tscn")
var game
var passed := 0
var failures: Array[String] = []


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _check(holds: bool, label: String) -> void:
	if holds:
		passed += 1
		print("PASS ",label)
	else:
		failures.append(label)
		printerr("FAIL ",label," at ",game.campaign.mission_index,"/",game.campaign.step_index," ",game.objective_text," ",game.runner.position)


func _wait(frames: int) -> void:
	for _frame in range(frames):
		await physics_frame
	await process_frame


func _place(at: Vector3) -> void:
	game.world.prepare_destination(at)
	game.runner.position = at + Vector3.UP*.13
	game.runner.velocity = Vector3.ZERO
	game.safe_position = game.runner.position
	game.control_axis = Vector2.ZERO
	game.suit.visible = true
	await _wait(3)


func _aim(at: Vector3) -> void:
	var offset: Vector3 = at - game.runner.position
	game.orbit.x = atan2(-offset.x,-offset.z)
	game.hero_heading = game.orbit.x


func _command(label: String, frames: int = 30) -> void:
	game.command(label)
	await _wait(frames)


func _stage(mission: int, stage: int, label: String) -> void:
	await _wait(4)
	_check(game.campaign.mission_index==mission and game.campaign.step_index==stage,label)


func _hit_encounter(id: String, damage: float, attempts: int) -> void:
	for _hit in range(attempts):
		var foe = game.combat.fighters.get(id)
		if foe == null or foe.data.hp <= 0.0:
			break
		var position: Vector3 = foe.position
		await _place(position+Vector3(0,0,2.40))
		_aim(foe.position)
		game.health = 100.0
		game.energy = 100.0
		var contact := "redirect" if foe.data.phase == 3 else "test-contact"
		game.combat.strike_target(id,damage,game.runner.position,contact)
		await _wait(47)
	await _wait(55)


func _interact(at: Vector3) -> void:
	await _place(at)
	await _command("interact")


func _begin() -> void:
	game = Level.instantiate()
	root.add_child(game)
	current_scene=game
	await _wait(15)


func _run() -> void:
	if FileAccess.file_exists("user://velocity-profile.a") or FileAccess.file_exists("user://velocity-profile.b"):
		printerr("Campaign integration requires a fresh XDG_DATA_HOME.")
		quit(2)
		return
	await _begin()
	if not game.ready_to_play or game.campaign == null:
		printerr("Game failed to boot")
		quit(1)
		return
	_check(game.campaign.mission_index==0 and game.campaign.step_index==0,"New campaign starts in Calder")
	var needed := ["Idle","Walk","Jog","Sprint","Boost","Air","Wall","Water","Jab","Heavy","Dodge","Takedown","Land","Fall"]
	var animations_ok := true
	for clip in needed:
		animations_ok = animations_ok and game.animations.has_animation(clip)
	_check(animations_ok,"Required skeletal clips imported")
	Input.action_press("v_forward")
	Input.action_press("v_sprint")
	await _wait(105)
	Input.action_release("v_forward")
	Input.action_release("v_sprint")
	await _stage(0,1,"Keyboard movement reaches the first encounter")
	await _hit_encounter("crew_a",27.0,4)
	await _hit_encounter("crew_b",27.0,4)
	await _stage(0,2,"Real enemies settle the ground crew objective")
	await _interact(Vector3(3.5,0,-36))
	await _stage(0,3,"Courier rescue opens upgrade training")
	await _command("upgrade_speed")
	await _stage(0,4,"Currency purchase installs a speed upgrade")
	await _place(Vector3(-3,0,-55.1))
	Input.action_press("v_forward")
	Input.action_press("v_sprint")
	await _wait(41)
	Input.action_release("v_forward")
	Input.action_release("v_sprint")
	await _stage(1,0,"Upgraded sprint settles mission one")

	Input.action_press("v_forward")
	Input.action_press("v_sprint")
	await _wait(54)
	Input.action_release("v_forward")
	Input.action_release("v_sprint")
	await _stage(1,1,"Sprint through the Mach One gate")
	await _place(Vector3(0,0,-111))
	await _stage(1,2,"Brake under the junction speed limit")
	var suspect: Dictionary = game.population.query("interceptor")
	if suspect.has("pos"):
		await _interact(suspect.pos+Vector3(0,0,1.2))
	await _stage(1,3,"Intercept a real moving suspect")
	await _place(Vector3(0,0,-163))
	await _stage(2,0,"Deliver the routing module")

	await _interact(Vector3(2,0,-125))
	await _stage(2,1,"Interact with the crossing relay crew")
	await _place(Vector3(0,0,-138))
	_aim(Vector3(0,0,-144))
	await _command("lightning")
	await _stage(2,2,"Lightning hits the collision-backed signal relay")
	await _place(Vector3(0,0,-151))
	await _command("shockwave")
	await _stage(2,3,"Shockwave clears the physical debris")
	await _interact(Vector3(5,0,-161))
	await _stage(3,0,"Rescue the crossing pedestrian")

	await _place(Vector3(0,0,-200))
	await _stage(3,1,"Read the rail-line trace")
	await _place(Vector3(-2,0,-214))
	await _wait(60)
	await _command("mirage")
	await _stage(3,2,"Mirage opens the guard lane")
	await _place(Vector3(14,0,-227))
	await _stage(3,3,"Follow the rival's route")
	await _place(Vector3(30,0,-226))
	await _stage(4,0,"Collect the timeline fragment")

	await _place(Vector3(-98,0,-119))
	await _stage(4,1,"Approach the canal crossing")
	await _place(Vector3(-103.5,0,-125))
	await _wait(174)
	_check(bool(game.campaign.state.get("crashed",false)),"Van crosses and injures the civilian before rewind")
	await _command("rewind",202)
	_check(not game.history.active and game.campaign._ever_rewound and not game.campaign.state.get("crashed",false),"Rewind restores van and civilian before impact")
	await _place(Vector3(-104,0,-134))
	await _command("shockwave",35)
	await _stage(4,2,"Shockwave stops the rewound van")
	await _interact(Vector3(-102,0,-120))
	await _stage(4,3,"Help the courier clear the ramp")
	await _place(Vector3(-120,0,-119))
	await _stage(5,0,"Leave the canal scene safely")

	await _place(Vector3(110,0,-119))
	_aim(Vector3(128,0,-119))
	Input.action_press("v_forward")
	Input.action_press("v_sprint")
	await _command("phase",47)
	Input.action_release("v_sprint")
	Input.action_release("v_forward")
	await _wait(76)
	await _stage(5,1,"Phase across the real Calder barrier and rematerialize")
	await _place(Vector3(128,0,-119))
	await _command("portal",44)
	_check(game.realm == "rift","Portal commits actual realm and arrival")
	await _stage(5,2,"City portal advances the authored journey")
	await _place(Vector3(7,0,1356))
	await _stage(5,3,"First Rift platform advances")
	await _place(Vector3(-8,0,1381))
	await _stage(5,4,"Second Rift platform advances")
	await _place(Vector3(0,0,1319))
	await _wait(120)
	await _command("portal",44)
	await _stage(6,0,"Rift return settles mission six")

	await _place(Vector3(148,0,-187))
	await _stage(6,1,"Enter the authored Nullstride arena")
	await _wait(130)
	await _hit_encounter("nullstride",35.0,20)
	await _stage(6,2,"Nullstride encounter reaches real combat defeat")
	await _interact(Vector3(148,0,-218))
	await _stage(7,0,"Stabilize the relay yard")

	_aim(Vector3(113,0,-118))
	Input.action_press("v_forward")
	Input.action_press("v_sprint")
	await _wait(48)
	Input.action_release("v_forward")
	Input.action_release("v_sprint")
	await _stage(7,1,"Sprint on the service lane into the finale")
	await _place(Vector3(128,0,-119))
	await _command("portal",44)
	await _stage(7,2,"Enter the finale Rift gate")
	await _place(Vector3(-6,0,1371))
	await _stage(7,3,"Reach the timeline fracture")
	await _place(Vector3(0,0,1318))
	await _wait(120)
	await _command("portal",44)
	await _stage(7,4,"Return from the fracture to Calder")
	await _place(Vector3(148,0,-199))
	await _stage(7,5,"Enter Afterlight's separate encounter")
	await _wait(130)
	await _hit_encounter("afterlight",34.0,32)
	await _stage(7,6,"Afterlight encounter reaches real combat defeat")
	await _interact(Vector3(148,0,-223))
	_check(game.campaign.complete and game.progress.finished,"Ending unlocks postgame and persists the campaign flag")
	_check(game.progress.mission_flags.size()==8,"Exactly eight campaign transactions posted")
	var saved_balance: int = game.progress.credits
	game.queue_free()
	await process_frame
	await _begin()
	_check(game.campaign.complete and game.campaign.activity=="patrol","Fresh scene loads postgame")
	_check(game.progress.credits==saved_balance,"Relaunch retains rewards without paying again")
	game.command("replay_0")
	await _wait(10)
	_check(game.campaign.activity=="replay" and game.campaign.mission_index==0,"Completed chapter can be replayed")
	_check(game.progress.mission_index==8 and game.progress.mission_flags.size()==8,"Replaying a chapter leaves permanent mission progress intact")
	game.command("race")
	await _wait(10)
	for gate: Vector3 in game.campaign.route:
		await _place(gate)
	_check(game.progress.best_time>0.0 and game.progress.has_award("race:calder:first"),"Calder race awards and saves a personal best")
	game.command("rift_trial")
	await _wait(10)
	_check(game.realm=="rift" and game.campaign.activity=="rift_trial","Rift relay arrives in the dedicated realm")
	for gate: Vector3 in game.campaign._race_points():
		await _place(gate)
	_check(game.progress.has_award("race:rift:first"),"Rift relay traverses six platforms and records a reward")
	game.queue_free()
	await process_frame
	print("CAMPAIGN ",passed," passed, ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
