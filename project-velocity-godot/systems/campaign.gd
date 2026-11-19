extends Node

const HOME = Vector3(0,0,8)
const GATE_HOME = Vector3(128,0,-119)
const GATE_RIFT = Vector3(0,0,1317)
const RIFT_TRIAL = [Vector3(8,0,1353),Vector3(-10,0,1364),Vector3(-15,0,1380),
	Vector3(13,0,1400),Vector3(8,0,1382),Vector3(0,0,1360)]
const MISSION = [
	{"title":"First Lightning","reward":40,"start":Vector3(0,0,8),"line":"Control, the transit alarms just tripped. I’m going down to the street.",
	 "steps":[
		["move","Follow the markers down Calder Avenue.",Vector3(0,0,-18)],
		["guard","Stop the ground crew before they reach the courier.",Vector3(0,0,-30)],
		["rescue","Check on the injured courier.",Vector3(3.5,0,-37)],
		["upgrade","Open Ops and install an upgrade.",Vector3(0,0,-38)],
		["prove","Sprint to the next marker with the upgrade installed.",Vector3(-3,0,-61)]]},
	{"title":"City at Mach One","reward":62,"start":Vector3(0,0,-85),"line":"Dispatch: An interceptor is running south. We need it stopped before the crosswalk.",
	 "steps":[
		["gate","Cross the first gate at a sprint.",Vector3(0,0,-97)],
		["brake","Brake at the junction. Stop at the checkpoint below 32 km/h.",Vector3(0,0,-112)],
		["chase","Catch the fleeing interceptor and use Interact when close.",Vector3(6,0,-146)],
		["move","Bring the routing module to the signal crew.",Vector3(0,0,-166)]]},
	{"title":"Red Signal","reward":58,"start":Vector3(0,0,-113),"line":"All four lights switched green together. Someone hardwired the junction.",
	 "steps":[
		["meet","Reach the repair zone and check the relay.",Vector3(2,0,-126)],
		["relay","Aim down the street and strike the flashing relay with Lightning.",Vector3(0,0,-144)],
		["blast","Shockwave the jammed obstruction away from the crossing.",Vector3(0,0,-154)],
		["rescue","Reach the fallen pedestrian and help them.",Vector3(5,0,-162)]]},
	{"title":"Ghost in the Street","reward":62,"start":Vector3(0,0,-175),"line":"Yellow lightning. The same turn, twice. Someone is leaving a trail on purpose.",
	 "steps":[
		["move","Trace the first signal under the rail line.",Vector3(0,0,-202)],
		["echo","Cast Mirage to pull a relay guard away, then take the marked lane.",Vector3(-2,0,-216)],
		["trace","Follow the rival’s trail to the next block.",Vector3(14,0,-226)],
		["move","Recover the abandoned timeline fragment.",Vector3(31,0,-226)]]},
	{"title":"The Second Before","reward":75,"start":Vector3(-82,0,-119),"line":"A van is headed for the canal crossing. Watch the curve and be ready to rewind.",
	 "steps":[
		["move","Reach the scene at the east bridge ramp.",Vector3(-96,0,-119)],
		["reverse","Watch the crash, then rewind and stop it with Shockwave.",Vector3(-105,0,-119)],
		["rescue","Reach and help the courier across the ramp.",Vector3(-102,0,-121)],
		["move","Clear the scene at the crossing.",Vector3(-122,0,-119)]]},
	{"title":"Through the Wall","reward":82,"start":Vector3(104,0,-119),"line":"A cover wall hides the breach. With phase you can get through from street level.",
	 "steps":[
		["phase","Phase through the blue barrier and exit safely.",Vector3(123,0,-119)],
		["enter","Open the rift at the portal anchor.",Vector3(128,0,-119)],
		["rift_gate","Cross the first platform marker.",Vector3(7,0,1356)],
		["rift_gate","Follow the lit line to the far platform.",Vector3(-8,0,1381)],
		["return","Return through the rift gate.",Vector3(0,0,1317)]]},
	{"title":"Black Velocity","reward":125,"start":Vector3(148,0,-150),"line":"The dark speedster is holding this district out of sync. There is still time to get it back.",
	 "steps":[
		["move","Enter the relay yard.",Vector3(148,0,-189)],
		["dark","Defeat Nullstride. Watch for rushes, slow-time attacks and redirect openings.",Vector3(148,0,-201)],
		["meet","Stabilize the yard relay.",Vector3(148,0,-219)]]},
	{"title":"Infinite Moment","reward":180,"start":Vector3(101,0,-119),"line":"Nullstride opened the fracture. Afterlight is using the repeat to make it permanent.",
	 "steps":[
		["gate","Sprint down the service lane toward the fracture.",Vector3(111,0,-117)],
		["enter","Phase behind the barrier, then open the rift at its anchor.",Vector3(128,0,-119)],
		["rift_gate","Reach the center of the fracture.",Vector3(-6,0,1371)],
		["return","Return to the city for the last encounter.",Vector3(0,0,1317)],
		["move","Reach Afterlight in the eastern yard.",Vector3(148,0,-201)],
		["yellow","Defeat Afterlight. Read the real tell, keep pace, and break the repeat.",Vector3(148,0,-211)],
		["ending","Close the fracture and return to the city.",Vector3(148,0,-225)]]},
]
const KEY_PREFIX = "M%02d"
var game
var mission_index := 0
var step_index := 0
var complete := false
var activity := "campaign"
var state: Dictionary = {}
var race_index := 0
var race_time := 0.0
var route: Array[Vector3] = []
var _age := 0.0
var _marker: Node3D
var _caption: Label3D
var _target_body: StaticBody3D
var _body_mesh: MeshInstance3D
var _hidden := false
var _ever_rewound := false
var _memory_lock := false
var _start_state: Dictionary = {}


func setup(owner) -> void:
	game = owner
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/course.json"))
	for point: Array in spec["checkpoints"]:
		route.append(Vector3(point[0],0,point[1]))
	_make_marker()
	complete = bool(game.progress.finished)
	mission_index = clampi(int(game.progress.mission_index),0,7)
	if complete:
		choose_activity("patrol")
	else:
		var saved := str(game.progress.mission_stage)
		var stage := int(saved) if saved.is_valid_int() else 0
		_open(mission_index,stage,true)


func _make_marker() -> void:
	_marker = Node3D.new()
	add_child(_marker)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.56
	ring.outer_radius = 1.74
	ring.rings = 28
	ring.ring_segments = 8
	var light := StandardMaterial3D.new()
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.albedo_color = Color("#ffbd73")
	var instance := MeshInstance3D.new()
	instance.mesh = ring
	instance.material_override = light
	instance.position.y = .085
	_marker.add_child(instance)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.albedo_color = Color(1.0, 0.72, 0.36, 0.085)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.14
	beam.bottom_radius = 0.58
	beam.height = 7.6
	beam.radial_segments = 16
	var beam_node := MeshInstance3D.new()
	beam_node.mesh = beam
	beam_node.material_override = beam_mat
	beam_node.position.y = 3.8
	beam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(beam_node)
	var wedge := MeshInstance3D.new()
	var shard := CylinderMesh.new()
	shard.top_radius = .22
	shard.bottom_radius = 0.0
	shard.height = .58
	shard.radial_segments = 4
	wedge.mesh = shard
	wedge.material_override = light
	wedge.position.y = 1.25
	_marker.add_child(wedge)
	_caption = Label3D.new()
	_caption.font_size = 40
	_caption.outline_size = 8
	_caption.pixel_size = .01
	_caption.modulate = Color("#ffd5a8")
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_caption.position.y = 2.05
	_marker.add_child(_caption)


func _mission() -> Dictionary:
	return MISSION[mission_index]


func _current() -> Array:
	var steps: Array = _mission()["steps"]
	return steps[mini(step_index,steps.size()-1)]


func _id() -> String:
	return KEY_PREFIX % (mission_index+1)


func _open(index: int, step_number := 0, restore_saved := false, replaying := false) -> void:
	activity = "replay" if replaying else "campaign"
	mission_index = clampi(index,0,7)
	step_index = clampi(step_number,0,_mission()["steps"].size()-1)
	game.population.set_patrol(false)
	_reset_encounter()
	var spec := _mission()
	var at: Vector3 = spec["start"]
	var destination := "city"
	var objective: String = _current()[0]
	if step_index > 0:
		var previous: Vector3 = spec["steps"][step_index-1][2]
		at = previous + Vector3(0,0,4.8)
	if objective in ["rift_gate","return"]:
		destination = "rift"
		at=Vector3(0,0,1360)
	if objective == "enter":
		at = Vector3(118,0,-119) if mission_index==5 else Vector3(118,0,-115.3)
	if objective in ["dark","yellow"]:
		at=Vector3(148,0,-186)
	if objective in ["meet","ending"] and mission_index>=6:
		at=Vector3(148,0,-216)
	if objective == "phase":
		at=Vector3(104,0,-119)
	if objective=="reverse":
		at=Vector3(-96,0,-119)
	if restore_saved and destination==game.progress.checkpoint.get("realm",""):
		var persisted: Vector3 = game.progress.checkpoint.get("position",Vector3.INF)
		if persisted.is_finite() and absf(persisted.y)<2.0 and persisted.distance_to(at)<24.0 and not game.world.water_at(persisted):
			at = persisted
	game.reset_runner(at,destination)
	game.mission_title=spec["title"]
	game.say(spec["line"],5.4)
	_begin_step(false)
	if activity=="campaign":
		game.progress.save_checkpoint(mission_index,str(step_index),at,destination)


func _reset_encounter(ambient := true) -> void:
	game.midnight.end()
	game.combat.clear_encounter()
	game.population.reset_scene(false, ambient)
	_unregister_switch()
	_start_state = {}
	state = {}
	_age = 0.0
	_ever_rewound=false
	_memory_lock=false


func retry() -> void:
	if _in_story():
		_open(mission_index,step_index,false,activity=="replay")
	else:
		choose_activity(activity)


func resume_campaign() -> void:
	if complete:
		choose_activity("patrol")
	elif activity != "campaign":
		_open(game.progress.mission_index,int(game.progress.mission_stage) if str(game.progress.mission_stage).is_valid_int() else 0,true)


func replay(index: int) -> void:
	if index>=0 and index<MISSION.size() and game.progress.mission_flags.has(KEY_PREFIX % (index+1)):
		_open(index,0,false,true)


func _in_story() -> bool:
	return activity in ["campaign","replay"]


func choose_activity(which: String) -> void:
	if which not in ["race","patrol","rift_trial","midnight"]:
		return
	_reset_encounter(which != "midnight")
	activity=which
	if which == "midnight":
		game.population.set_patrol(false)
		game.reset_runner(game.midnight.START)
		game.mission_title = "Midnight Circuit"
		game.say("", 0.0)
		game.announce("", 0.0)
		_hidden = true
		_marker.hide()
		game.midnight.begin()
		return
	race_index=0
	race_time=0.0
	game.reset_runner(Vector3(0,0,1360) if which=="rift_trial" else HOME,"rift" if which=="rift_trial" else "city")
	if which=="patrol":
		game.population.set_patrol(true)
		game.mission_title="City Patrol"
		game.objective_text="Follow city dispatch, race, or visit the Rift."
		game.target_position=HOME
		_hidden=true
	else:
		game.population.set_patrol(false)
		game.mission_title="Rift Relay" if which=="rift_trial" else "Calder Time Trial"
		game.objective_text="Follow the lit Rift route." if which=="rift_trial" else "Run through the seven gates."
		_hidden=false
		var gates := _race_points()
		_set_marker(gates[0],"Gate 1 / %d"%gates.size())


func _race_points() -> Array:
	return RIFT_TRIAL if activity=="rift_trial" else route


func _begin_step(persist := true) -> void:
	state = {}
	_age = 0.0
	_hidden=false
	var current := _current()
	var key: String = current[0]
	var at: Vector3 = current[2]
	game.objective_text=current[1]
	game.target_position=at
	_set_marker(at,_marker_label(key))
	_unregister_switch()
	match key:
		"guard":
			game.combat.spawn("crew_a",at+Vector3(-1.6,0,-4),"guard")
			game.combat.spawn("crew_b",at+Vector3(3.1,0,-7),"guard")
		"rescue":
			game.population.spawn("objective_civilian","civilian",at,{"status":"injured","health":0.0,"held":true,"mission":true})
		"upgrade":
			game.progress.award("tutorial:first-kit",24)
			var stats: Dictionary = game.progress.stats
			if int(stats["speed"])+int(stats["accel"])+int(stats["turn"])>0:
				_advance()
		"chase":
			var chase: Array[Vector3]=[
				Vector3(6,0,-154),Vector3(6,0,-205),Vector3(7,0,-226),Vector3(72,0,-222),Vector3(142,0,-222),
				Vector3(143,0,-120),Vector3(70,0,-116),Vector3(6,0,-116)
			]
			game.population.spawn("interceptor","suspect", at, {"route":chase,"speed":14.0,"loop":true,"mission":true})
			game.population.spawn("pursuit_unit","police",at+Vector3(0,0,10),{"target":"interceptor","speed":15.5})
		"relay":
			_register_switch(at)
			game.say("Control: A clean line to the strip on the relay should reset it.")
		"blast":
			game.population.spawn("debris","prop",at+Vector3(0,0,-1.2),{"held":false,"mission":true})
		"echo":
			game.combat.spawn("tail_guard",at+Vector3(-4,0,-5),"guard")
			game.say("Cast Mirage while the guard is looking. Take the open lane.")
		"trace":
			game.population.spawn("echo_trace","suspect",Vector3(9,0,-226),{"route":[Vector3(20,0,-226),at],"speed":13.0})
			game.cinema(Vector3(6,1.8,-218),Vector3(14,1.0,-226),.95)
		"reverse":
			game.population.spawn("crash_van","van",Vector3(-105,0,-139),{"goal":Vector3(-105,0,-119),"speed":12.0,
				"route":[Vector3(-105,0,-127),Vector3(-105,0,-119)],"mission":true})
			game.population.spawn("crash_civilian","civilian",Vector3(-105,0,-117.2),{"held":true,"mission":true})
			game.population.spawn("crash_crate","prop",Vector3(-104,0,-121.2),{"mission":true})
			game.say("Listen for the collision. Rewind the scene, then use Shockwave to halt the van.")
		"enter","return":
			game.powers.configure_portal(GATE_HOME,Vector3(0,0,1360),GATE_RIFT,GATE_HOME+Vector3(4,0,0))
		"dark":
			game.combat.clear_encounter()
			game.combat.spawn("nullstride",at+Vector3(0,0,-3),"rival_dark")
			game.cinema(at+Vector3(7,2.4,11),at+Vector3(0,1.2,-3),1.75)
			game.say("Nullstride: You keep arriving in the same second. Make this one count.")
		"yellow":
			game.combat.clear_encounter()
			game.combat.spawn("afterlight",at+Vector3(0,0,-4),"rival_yellow")
			game.cinema(at+Vector3(-6,2.1,9),at+Vector3(0,1.2,-4),1.75)
			game.say("Afterlight: This city runs in a loop. Catch me on the next turn.")
	_start_state=state.duplicate(true)
	if persist and activity=="campaign":
		game.progress.save_checkpoint(mission_index,str(step_index),game.runner.position,game.realm)


func _marker_label(key: String) -> String:
	match key:
		"gate","prove","brake","rift_gate": return "RUN TO THE MARKER"
		"meet","rescue","ending": return "INTERACT"
		"chase","trace": return "INTERCEPT"
		"relay": return "LIGHTNING"
		"blast": return "SHOCKWAVE"
		"enter","return": return "RIFT GATE"
		"dark","yellow","guard": return "ENCOUNTER"
		"phase": return "PHASE EXIT"
		"reverse": return "CROSSING"
		"echo": return "MIRAGE"
	return "OBJECTIVE"


func _set_marker(at: Vector3, text: String) -> void:
	game.target_position=at
	_marker.position=at
	_caption.text=text


func _register_switch(at: Vector3) -> void:
	_target_body=StaticBody3D.new()
	_target_body.name="SignalRelay"
	_target_body.position=at
	_target_body.collision_layer=1
	_target_body.collision_mask=0
	add_child(_target_body)
	var hit:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(.80,1.8,.60)
	hit.shape=shape
	hit.position.y=.9
	_target_body.add_child(hit)
	_body_mesh=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=shape.size
	_body_mesh.mesh=box
	var steel:=StandardMaterial3D.new()
	steel.albedo_color=Color("#567593")
	steel.emission_enabled=true
	steel.emission=Color("#4bd5f4")
	steel.emission_energy_multiplier=.54
	_body_mesh.material_override=steel
	_body_mesh.position=hit.position
	_target_body.add_child(_body_mesh)
	game.powers.register_target("signal_relay",_target_body)


func _unregister_switch() -> void:
	if is_instance_valid(_target_body):
		if game.powers.has_method("unregister_target"):
			game.powers.unregister_target("signal_relay")
		_target_body.queue_free()
		_target_body=null


func _range(to: Vector3) -> float:
	var at: Vector3 = game.runner.position
	return Vector2(to.x-at.x,to.z-at.z).length()


func _advance() -> void:
	if not _in_story() or _memory_lock:
		return
	_memory_lock=true
	call_deferred("_commit_advance")


func _commit_advance() -> void:
	if not _in_story():
		_memory_lock=false
		return
	_memory_lock=false
	if step_index+1<_mission()["steps"].size():
		game.history.clear()
		step_index+=1
		_begin_step()
		game.pulse("goal",game.runner.position)
		return
	if activity=="replay":
		game.announce("Chapter replay complete")
		resume_campaign()
		return
	var final:=mission_index==7
	if not game.progress.settle_mission(_id(),int(_mission()["reward"]),mission_index+1,"0",game.runner.position,game.realm):
		game.announce("The checkpoint could not be written. Retry after freeing local storage.",5.0)
		return
	if final:
		complete=true
		game.progress.finished=true
		game.progress.save()
		activity="patrol"
		game.population.set_patrol(true)
		game.mission_title="City Restored"
		game.objective_text="Explore Calder, take city dispatch, or race."
		var at: Vector3 = game.runner.position
		game.cinema(at+Vector3(4,2.4,7),at+Vector3(0,1.28,0),3.1)
		game.say("The clocks agree again. Back to the city.",7.0)
		game.event("campaign_completed")
		_hidden=true
		if game.hud.has_method("show_ending"):
			game.hud.show_ending()
	else:
		game.announce("Mission complete  •  +%d SFC"%int(_mission()["reward"]),4.2)
		_open(mission_index+1)


func interact() -> bool:
	if not _in_story():
		return false
	var current := _current()
	var key: String=current[0]
	var at: Vector3=current[2]
	if key=="rescue":
		var civilian: Dictionary=game.population.query("objective_civilian")
		return not civilian.is_empty() and game.population.interact_id("objective_civilian")
	if key=="chase":
		return game.population.interact_id("interceptor")
	if _range(at)>6.0:
		return false
	if key in ["meet","ending"]:
		_advance()
		return true
	if key in ["enter","return"]:
		return game.powers.command("portal")
	return false


func step(dt: float) -> void:
	_age += dt
	_marker.visible=not _hidden
	if not _hidden:
		_marker.rotation.y+=dt*.35
	if activity in ["race","rift_trial"]:
		var gates := _race_points()
		race_time+=dt
		if race_index<gates.size() and _range(gates[race_index])<4.9:
			race_index+=1
			game.pulse("goal",game.runner.position)
			if race_index<gates.size():
				_set_marker(gates[race_index],"Gate %d / %d"%[race_index+1,gates.size()])
				game.objective_text="Gate %d / %d   •   %.2f s"%[race_index+1,gates.size(),race_time]
			else:
				_hidden=true
				var best := false
				if activity=="race":
					game.progress.award("race:calder:first",32)
					best = game.progress.record_trial(race_time)
				else:
					game.progress.award("race:rift:first",42)
				game.objective_text="%s   •   %.2f s"%[game.mission_title,race_time]
				game.announce(("Personal best" if best else "Finish")+"  •  %.2f seconds"%race_time,8.0)
		return
	if activity=="patrol":
		var incident: Dictionary = game.population.crime
		if incident.get("outcome","") == "active":
			_hidden = false
			_set_marker(incident.get("pos",HOME),str(incident.get("title","DISPATCH")).to_upper())
			game.objective_text = str(incident.get("objective","Respond to the active dispatch."))
		else:
			_hidden = true
			game.objective_text = "Explore Calder, take city dispatch, or race."
		return
	if not _in_story():
		return
	var current:=_current()
	var key: String=current[0]
	var at: Vector3=current[2]
	if key=="move" and _range(at)<5.0:
		_advance()
	elif key in ["gate","prove"] and _range(at)<5.4 and game.speed>9.0:
		_advance()
	elif key=="brake" and _range(at)<6.0 and game.speed<9.0:
		_advance()
	elif key=="rift_gate" and game.realm=="rift" and _range(at)<5.0:
		_advance()
	elif key=="enter" and game.realm=="rift":
		_advance()
	elif key=="return" and game.realm=="city":
		_advance()
	elif key=="phase" and game.runner.position.x>120.0 and game.runner.position.x<133.0 and absf(game.runner.position.z+119.0)<6.0 and bool(state.get("phase",false)) and not game.powers.phased():
		_advance()
	elif key=="echo" and bool(state.get("mirage",false)) and _range(at)<5.8:
		_advance()
	elif key=="trace" and _range(at)<5.7:
		_advance()
	elif key=="chase":
		var suspect: Dictionary=game.population.query("interceptor")
		if suspect.has("pos"):
			_set_marker(suspect.pos,"INTERCEPT")
	elif key=="reverse":
		_crash_step()
	elif key in ["dark","yellow"]:
		if bool(state.get("boss_down",false)):
			_advance()


func _crash_step() -> void:
	var van: Dictionary=game.population.query("crash_van")
	if van.is_empty():
		return
	var point: Vector3=van.get("pos",Vector3(-105,0,-119))
	if bool(state.get("prevented",false)):
		game.population.hold("crash_van")
		game.say("The van is stopped. This time everyone gets out.")
		_advance()
	elif point.z>=-123.0 and not bool(state.get("crashed",false)):
		state["crashed"]=true
		game.population.hold("crash_van")
		game.population.injure("crash_civilian")
		game.population.area_effect(Vector3(-105,0,-121),6.0,13.5,"shockwave")
		game.pulse("impact",Vector3(-105,0,-121))
		game.announce("Rewind now. Stop the van before the crash.",7.0)
	if _ever_rewound and not bool(state.get("crashed",false)):
		game.objective_text="Shockwave the van before it reaches the crossing."
		_set_marker(point,"STOP THE VAN")


func on_event(key: String, payload: Dictionary) -> void:
	if not _in_story() or (complete and activity!="replay"):
		return
	var step_name: String=_current()[0]
	var id:=str(payload.get("id",""))
	match key:
		"enemy_down":
			if step_name=="guard" and id.begins_with("crew_"):
				state[id]=true
				if state.get("crew_a",false) and state.get("crew_b",false):
					_advance()
			elif (step_name=="dark" and id=="nullstride") or (step_name=="yellow" and id=="afterlight"):
				state["boss_down"]=true
				game.announce("Encounter cleared")
		"population_rescued":
			if step_name=="rescue" and id=="objective_civilian":
				_advance()
		"population_intercepted":
			if step_name=="chase" and id=="interceptor":
				_advance()
		"lightning_hit":
			if step_name=="relay" and id=="signal_relay":
				_advance()
		"shockwave_hit":
			if step_name=="blast":
				var at: Vector3=payload.get("position",game.runner.position)
				if at.distance_to(_current()[2])<10.0 and int(payload.get("count",0))>0:
					_advance()
		"population_staggered":
			if step_name=="reverse" and id=="crash_van" and _ever_rewound and not bool(state.get("crashed",false)):
				state["prevented"]=true
		"rewind_finished":
			if step_name=="reverse":
				_ever_rewound=true
				if state.get("crashed",false):
					game.objective_text="Rewind farther or retry the crossing."
		"ability_cast":
			if step_name=="phase" and id=="phase":
				state["phase"]=true
			if step_name=="echo" and id=="mirage":
				state["mirage"]=true
		"mirage_spawned":
			if step_name=="echo":
				state["mirage"]=true
		"upgrade":
			if step_name=="upgrade":
				_advance()


func ledger() -> Array[Dictionary]:
	var items: Array[Dictionary]=[]
	for i in MISSION.size():
		var earned: bool = game.progress.mission_flags.has(KEY_PREFIX % (i+1))
		var stage := "Complete" if earned else "Active" if i==game.progress.mission_index else "Locked"
		items.append({"title":MISSION[i].title,"name":MISSION[i].title,"status":stage,"index":i})
	return items


func snapshot() -> Dictionary:
	return {"mission":mission_index,"step":step_index,"activity":activity,"state":state.duplicate(true),
		"age":_age,"race_gate":race_index,"race_time":race_time}


func restore(frame: Dictionary) -> void:
	if frame.state == null or frame.mission!=mission_index or frame.step!=step_index or frame.activity!=activity:
		return
	state=frame.state.duplicate(true)
	_age=frame.age
	race_index=frame.race_gate
	race_time=frame.race_time
