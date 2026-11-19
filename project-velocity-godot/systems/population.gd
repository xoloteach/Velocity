extends Node3D
## Traffic, pedestrians, police dispatch and reversible lightweight street props.

const Art = preload("res://systems/population_art.gd")
const CROSSINGS := [-119.0,-226.0]
const KIND_VEHICLE := ["car","van","police"]
const REWIND_MARGIN := 12.0
const STRIDE := 25
const MAX_ACTIVE := 54
const MAX_SPECS := 190
const STYLES := [14,21,26,31]
var game
var _art := Art.new()
var _actors: Dictionary = {}
var _specs: Dictionary = {}
var _nodes: Dictionary = {}
var _lights: Array[Dictionary] = []
var _serial: int = 0
var _clock: float = 0.0
var _local_tick: int = 0
var _hero_collision: float = 0.0
var _crime_cooldown: float = 18.0
var _crime_seq: int = 0
var _crime_run: int = 0
var _patrol: bool = false
var _reduced_flash: bool = false
var crime: Dictionary = {}

func setup(coordinator) -> void:
	game = coordinator
	_crime_run = int(Time.get_unix_time_from_system() * 1000000.0)
	_reset_ambient()
	for crossing in CROSSINGS:
		for arm in range(4):
			var direction: Vector3 = [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT][arm]
			var right := direction.cross(Vector3.UP)
			var pole := Node3D.new()
			pole.position = Vector3(0,0,crossing) - direction*8.2 + right*9.7
			pole.rotation.y = atan2(direction.x,direction.z)
			add_child(pole)
			var fixture := _art.signal_head(pole)
			fixture.root = pole
			fixture.crossing = crossing
			fixture.axis = 0 if arm < 2 else 1
			_lights.append(fixture)

func set_reduced_flash(enabled: bool) -> void:
	_reduced_flash = enabled

func reset_scene(keep_named: bool = false) -> void:
	if not crime.is_empty():
		_clear_crime()
	for id in _actors.keys():
		var actor: Dictionary = _actors[id]
		if not keep_named or actor.ambient:
			deactivate(id)
	crime.clear()
	_crime_cooldown = 18.0
	_hero_collision = 0.0
	_reset_ambient()

func _reset_ambient() -> void:
	# Independent routes give lawful directional traffic through both intersections.
	var north: Array[Vector3] = [Vector3(3.7,0,20),Vector3(3.7,0,-302)]
	var south: Array[Vector3] = [Vector3(-3.7,0,-300),Vector3(-3.7,0,25)]
	var west: Array[Vector3] = [Vector3(97,0,-122.7),Vector3(-204,0,-122.7)]
	var east: Array[Vector3] = [Vector3(-196,0,-115.3),Vector3(94,0,-115.3)]
	var turn_south: Array[Vector3] = [Vector3(-84,0,-222.3),Vector3(-8.2,0,-222.3),Vector3(-3.7,0,-214.7),Vector3(-3.7,0,8)]
	var turn_east: Array[Vector3] = [Vector3(3.7,0,-57),Vector3(3.7,0,-219.2),Vector3(11.5,0,-222.3),Vector3(89,0,-222.3)]
	for i in range(5):
		spawn("road.north.%d"%i,"van" if i==2 else "car",Vector3(3.7,0,-18-i*48),
			{"ambient":true,"priority":i,"route":north,"leg":1,"speed":8.2+i%3,"loop":true,"variant":i})
		spawn("road.south.%d"%i,"van" if i==3 else "car",Vector3(-3.7,0,-42-i*48),
			{"ambient":true,"priority":i,"route":south,"leg":1,"speed":8.8+i%2,"loop":true,"variant":i+2})
	for i in range(2):
		spawn("road.west.%d"%i,"car",Vector3(61-i*119,0,-122.7),
			{"ambient":true,"priority":i+2,"route":west,"leg":1,"speed":8.6,"loop":true,"variant":i+3})
		spawn("road.east.%d"%i,"van" if i==0 else "car",Vector3(-156+i*124,0,-115.3),
			{"ambient":true,"priority":i+2,"route":east,"leg":1,"speed":8.3,"loop":true,"variant":i+1})
	spawn("road.turn.south","car",Vector3(-51,0,-222.3),{"ambient":true,"priority":3,"route":turn_south,"leg":1,"speed":8.5,"loop":true,"variant":4})
	spawn("road.turn.east","car",Vector3(3.7,0,-156),{"ambient":true,"priority":3,"route":turn_east,"leg":1,"speed":8.1,"loop":true,"variant":5})
	for i in range(16):
		var side := 1.0 if i%2==0 else -1.0
		var z := -12.0 - i * 14.7
		var route: Array[Vector3] = [Vector3(side*11.5,0,z+6),Vector3(side*11.5,0,z-10)]
		if i==4:
			route = [Vector3(11.5,0,-84),Vector3(11.5,0,-110.8),Vector3(-11.5,0,-110.8),Vector3(-11.5,0,-84)]
			z = -88
		elif i==7:
			route = [Vector3(-11.5,0,-146),Vector3(-11.5,0,-127.2),Vector3(11.5,0,-127.2),Vector3(11.5,0,-146)]
			z = -144
		spawn("walk.%d"%i,"civilian",Vector3(side*11.5,0,z),
			{"ambient":true,"priority":i%5,"route":route,"leg":1,"speed":0.89+(i%5)*0.14,"loop":true,"variant":i})
	var barrels: Array[Vector3] = [Vector3(8.2,0,-39.0),Vector3(-8.4,0,-95.0),Vector3(8.8,0,-152.7),Vector3(-8.4,0,-206),Vector3(-98,0,-124),Vector3(107,0,-125)]
	for i in range(barrels.size()):
		spawn("prop.%d"%i,"prop",barrels[i],{"ambient":true,"priority":1,"variant":i})

func spawn(id: String, kind: String, at: Vector3, options: Dictionary = {}) -> Dictionary:
	if not at.is_finite() or id.is_empty():
		return {}
	if _actors.has(id):
		deactivate(id)
	if _actors.size() >= MAX_ACTIVE:
		for key in _actors.keys():
			if _actors[key].ambient and _actors[key].priority >= 4:
				deactivate(key)
				break
	if _actors.size() >= MAX_ACTIVE:
		return {}
	_serial += 1
	var realm: String = str(options.get("realm","city" if options.get("ambient",false) or game == null else game.realm))
	var route: Array[Vector3] = []
	if options.get("route",[]) is Array or options.get("route") is PackedVector3Array:
		for point in options.get("route",[]):
			if point is Vector3 and point.is_finite():
				route.append(point)
	var descriptor := {
		"id":id,"kind":kind,"realm":realm,"route":route,"ambient":bool(options.get("ambient",false)),
		"priority":int(options.get("priority",0)),"variant":int(options.get("variant",posmod(id.hash(),6))),
		"target":str(options.get("target","")),"max_speed":maxf(0.1,float(options.get("speed",8.6 if kind in KIND_VEHICLE else 1.55))),
		"loop":bool(options.get("loop",false)),"spawn":at,"generation":_serial,"record_until":_clock+REWIND_MARGIN,
		"patrol_chase":bool(options.get("chase",false)),
	}
	_specs[_serial] = descriptor
	var leg := clampi(int(options.get("leg",0)),0,route.size()-1) if not route.is_empty() else -1
	var goal: Vector3 = options.get("goal",route[leg] if leg >= 0 else at)
	var direction := _ground_direction(at,goal)
	var actor: Dictionary = descriptor.duplicate()
	actor.merge({
		"pos":at,"vel":Vector3.ZERO,"yaw":atan2(-direction.x,-direction.z) if direction.length_squared()>0.1 else 0.0,
		"health":clampf(float(options.get("health",100.0)),0.0,100.0),"timer":0.0,"speed":0.0,"leg":leg,
		"status":str(options.get("status","drive" if kind in KIND_VEHICLE else "idle")),"goal":goal,
		"hold":bool(options.get("held",false)),"step_progress":0.0,"arrived":false,"custom_goal":options.has("goal"),
		"waiting":0.0,"hazard":at,"last_goal_distance":0.0,"police_contact":false,"impact_delay":0.0,
	})
	_actors[id] = actor
	return actor

func query(id: String) -> Dictionary:
	return _actors.get(id,{})

func move_goal(id: String, goal: Vector3) -> bool:
	if not _actors.has(id) or not goal.is_finite():
		return false
	var actor: Dictionary = _actors[id]
	actor.goal = goal
	actor.hold = false
	actor.arrived = false
	actor.custom_goal = true
	if actor.status in ["arrived","held","stopped","idle"]:
		actor.status = "drive" if actor.kind in KIND_VEHICLE else "walk"
	return true

func follow_route(id: String, route: Array[Vector3], repeat: bool = false) -> bool:
	var actor := query(id)
	if actor.is_empty() or route.is_empty():
		return false
	var metadata: Dictionary = _specs[actor.generation]
	# New generations preserve old routes already recorded by history.
	metadata = metadata.duplicate()
	_serial += 1
	metadata.route = route.duplicate()
	metadata.loop = repeat
	metadata.generation = _serial
	metadata.record_until = _clock + REWIND_MARGIN
	_specs[_serial] = metadata
	actor.generation = _serial
	actor.route = metadata.route
	actor.loop = repeat
	actor.leg = 0
	move_goal(id,route[0])
	actor.custom_goal = false
	return true

func hold(id: String, held: bool = true) -> bool:
	var actor := query(id)
	if actor.is_empty():
		return false
	actor.hold = held
	if held:
		actor.speed = 0.0
		actor.vel = Vector3.ZERO
	if actor.status in ["drive","walk","idle","chase","held","brake","stopped"]:
		actor.status = "held" if held else ("drive" if actor.kind in KIND_VEHICLE else "walk")
	return true

func set_status(id: String, status: String) -> bool:
	var actor := query(id)
	if actor.is_empty() or status.is_empty():
		return false
	if status == "crashed":
		status = "crash"
	actor.status = status
	if status in ["injured","rescued","crash","disabled","held","intercepted"]:
		actor.speed = 0.0
		actor.vel = Vector3.ZERO
	return true

func injure(id: String, amount: float = 100.0) -> bool:
	var actor := query(id)
	if actor.is_empty() or actor.status in ["injured","disabled","rescued"] or amount <= 0.0:
		return false
	actor.health = maxf(0.0,float(actor.health)-amount)
	if actor.health <= 25.0:
		if actor.kind in KIND_VEHICLE:
			set_status(id,"crash")
		else:
			set_status(id,"injured")
		_emit("population_injured",actor)
	return true

func deactivate(id: String) -> void:
	if _actors.has(id):
		var actor: Dictionary = _actors[id]
		var descriptor: Dictionary = _specs.get(actor.generation,{})
		if not descriptor.is_empty():
			descriptor.record_until = _clock+REWIND_MARGIN
		if _nodes.has(id):
			var prev: Dictionary = _nodes[id]
			var body: AnimatableBody3D = prev.body
			body.visible = false
			body.collision_layer = 0
			var sound: AudioStreamPlayer3D = prev.get("siren",prev.get("motor"))
			if sound != null:
				sound.stop()
			body.queue_free()
			_nodes.erase(id)
		_actors.erase(id)

func _emit(key: String, actor: Dictionary, extra: Dictionary = {}) -> void:
	if game != null and game.has_method("event"):
		var payload := {"id":actor.get("id",""),"kind":actor.get("kind",""),"pos":actor.get("pos",Vector3.ZERO),"status":actor.get("status","")}
		payload.merge(extra,true)
		game.event(key,payload)

func _announce(message: String, duration: float = 3.5) -> void:
	if game != null and game.has_method("announce"):
		game.announce(message,duration)

func _ground_direction(a: Vector3,b: Vector3) -> Vector3:
	var d := b-a
	d.y = 0.0
	return d.normalized()

func _ground_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func traffic_phase(crossing: float = -119.0) -> float:
	return fposmod(_clock + (4.5 if crossing < -180.0 else 0.0),16.0)

func has_right_of_way(axis: int, crossing: float = -119.0) -> bool:
	var phase := traffic_phase(crossing)
	return phase < 6.2 if axis == 0 else (phase>=7.1 and phase<13.7)

func _walk_signal(crossing: float) -> bool:
	var phase := traffic_phase(crossing)
	return phase >= 6.8 and phase < 14.0

func step(dt: float) -> void:
	if game == null or dt <= 0.0:
		return
	_clock += dt
	_local_tick += 1
	_hero_collision = maxf(0.0,_hero_collision-dt)
	var hero: Vector3 = game.runner.global_position
	var realm: String = str(game.realm)
	var preset: int = clampi(int(game.quality),0,3)
	var ambient_max: int = STYLES[preset]
	var visual_radius: float = [57.0,76.0,95.0,112.0][preset]
	var new_nodes := 0
	var ambient_count := 0
	for id in _actors.keys():
		if not _actors.has(id):
			continue
		var actor: Dictionary = _actors[id]
		var dist := _ground_distance(actor.pos,hero)
		var local: bool = actor.realm == realm
		var near_contact := dist<38.0
		var eligible: bool = near_contact or not actor.ambient or actor.priority <= (2 if preset == 0 else 4)
		if local and actor.ambient and eligible and dist<visual_radius:
			ambient_count += 1
		if actor.realm == realm and (eligible or dist<40.0):
			var tick_rate := 1 if dist < 58.0 or not actor.ambient else (3 if dist < 150.0 else 10)
			if _local_tick % tick_rate == posmod(id.hash(),tick_rate):
				var local_dt := minf(0.18,dt*tick_rate)
				actor.impact_delay = maxf(0.0,float(actor.impact_delay)-local_dt)
				if actor.kind in KIND_VEHICLE:
					_tick_car(actor,local_dt,hero)
				elif actor.kind == "prop":
					_tick_prop(actor,local_dt,hero)
				else:
					_tick_person(actor,local_dt,hero)
		var visible_actor: bool = local and eligible and dist<visual_radius and (near_contact or not actor.ambient or ambient_count<=ambient_max)
		if not _nodes.has(id) and visible_actor and new_nodes<2 and _actors.has(id):
			_make_node(actor)
			new_nodes += 1
		if _nodes.has(id) and _actors.has(id):
			_sync_node(actor,visible_actor,visible_actor and dist<44.0,false,dist<20.0)
	if realm == "city":
		_sync_lights(hero)
		_tick_crime(dt,hero)
	else:
		_sync_lights(Vector3(0,0,1360))
	if _local_tick % 45 == 0:
		_prune_specs()

func _prune_specs() -> void:
	if _specs.size() < 60:
		return
	var active_ids: Dictionary = {}
	for actor in _actors.values():
		active_ids[actor.generation] = true
	for gen in _specs.keys():
		if not active_ids.has(gen) and (_specs[gen].record_until < _clock or _specs.size()>MAX_SPECS):
			_specs.erase(gen)

func _sync_lights(hero: Vector3) -> void:
	for marker in _lights:
		var root: Node3D = marker.root
		var crossing: float = marker.crossing
		root.visible = _ground_distance(hero,root.position)<105.0
		if not root.visible:
			continue
		var p := traffic_phase(crossing)
		var green := has_right_of_way(marker.axis,crossing)
		var amber := (p>=6.2 and p<7.1) if marker.axis==0 else (p>=13.7 and p<14.7)
		for i in range(3):
			marker.bulbs[i].visible = i==(2 if green else (1 if amber else 0))

func _make_node(actor: Dictionary, silent: bool = false) -> void:
	var body := AnimatableBody3D.new()
	body.name = "Actor_%s"%str(actor.id).validate_node_name()
	body.sync_to_physics = false
	body.collision_layer = 0
	body.collision_mask = 0
	body.position = actor.pos
	body.rotation.y = actor.yaw
	add_child(body)
	var collider := CollisionShape3D.new()
	body.add_child(collider)
	var visual := Node3D.new()
	visual.name = &"Model"
	body.add_child(visual)
	var art_parts: Dictionary
	if actor.kind in KIND_VEHICLE:
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.92,1.19,4.80 if actor.kind=="van" else 4.08)
		collider.shape = shape
		collider.position.y = 0.66
		art_parts = _art.vehicle(visual,actor.kind,actor.variant)
	elif actor.kind == "prop":
		var shape := CylinderShape3D.new()
		shape.radius = 0.36
		shape.height = 0.76
		collider.shape = shape
		collider.position.y = 0.38
		art_parts = _art.prop(visual,actor.variant)
	else:
		var shape := CapsuleShape3D.new()
		shape.radius = 0.24
		shape.height = 1.52
		collider.shape = shape
		collider.position.y = 0.80
		art_parts = _art.human(visual,actor.variant,actor.kind=="suspect")
	_nodes[actor.id] = art_parts
	_nodes[actor.id].body = body
	_nodes[actor.id].visual = visual
	_nodes[actor.id].collider = collider
	_sync_node(actor,not silent,not silent)
	
func _sync_node(actor: Dictionary, visible_actor: bool, solid: bool, muted: bool = false, engine_audible: bool = false) -> void:
	var draw: Dictionary = _nodes[actor.id]
	var body: AnimatableBody3D = draw.body
	body.position = actor.pos
	body.rotation.y = actor.yaw
	body.visible = visible_actor
	body.collision_layer = 8 if solid and actor.status not in ["injured","rescued","intercepted","disabled"] else 0
	if not visible_actor:
		var sound: AudioStreamPlayer3D = draw.get("siren",draw.get("motor"))
		if sound != null and sound.playing:
			sound.stop()
		return
	var visual: Node3D = draw.visual
	if actor.kind in KIND_VEHICLE:
		draw.brake_lamps.visible = actor.status in ["brake","wait","held","stagger"] or (actor.status=="crash" and (_reduced_flash or fposmod(_clock,0.86)<0.42))
		if draw.has("wheels"):
			var spin := -float(actor.step_progress)
			for wheel_node in draw.wheels:
				if is_instance_valid(wheel_node):
					wheel_node.rotation.x = spin
		if draw.has("motor"):
			var motor: AudioStreamPlayer3D = draw.motor
			var active: bool = engine_audible and not muted and actor.status not in ["crash","disabled","intercepted"]
			if active:
				motor.pitch_scale = 0.72+clampf(float(actor.speed)*0.057,0.0,1.2)
				motor.volume_db = lerpf(-29.0,-20.0,clampf(float(actor.speed)*0.08,0.0,1.0))
				if not motor.playing:
					motor.play()
			elif motor.playing:
				motor.stop()
	if actor.kind == "prop":
		visual.rotation.z = clampf(actor.vel.x * 0.075, -0.35, 0.35)
	elif actor.kind == "police":
		var target: Dictionary = query(actor.target)
		var chasing: bool = not actor.hold and not target.is_empty() and target.status not in ["intercepted","rescued","disabled"]
		var alternation := fposmod(_clock,0.58)<0.29
		draw.red.visible = chasing and (_reduced_flash or alternation)
		draw.blue.visible = chasing and (_reduced_flash or not alternation)
		if chasing and solid and not muted and not draw.siren.playing:
			draw.siren.play()
		elif (not chasing or not solid or muted) and draw.siren.playing:
			draw.siren.stop()
	elif actor.kind not in KIND_VEHICLE:
		var down: bool = actor.status == "injured"
		var fearful: bool = actor.status == "cover"
		visual.rotation.x = -PI * 0.5 if down else (0.18 if fearful else 0.0)
		var sidewalk := 0.06 if absf(Vector3(actor.pos).x)>8.7 and actor.ambient else 0.0
		visual.position.y = (0.27 if down else (-0.13 if fearful else 0.027*absf(sin(float(actor.step_progress)*2.0)))) + sidewalk
		var foot := sin(float(actor.step_progress))*minf(0.71,float(actor.speed)*0.26)
		for i in [0,1]:
			draw.legs[i].rotation.x = foot*(1.0 if i==0 else -1.0)
			draw.arms[i].rotation.x = -foot*(0.82 if i==0 else -0.82)

func _tick_car(actor: Dictionary, dt: float, hero: Vector3) -> void:
	if actor.hold or actor.status in ["injured","crash","disabled","intercepted","arrived"]:
		actor.speed = 0.0
		actor.vel = Vector3.ZERO
		return
	if actor.status=="stagger":
		actor.timer = maxf(0.0,float(actor.timer)-dt)
		actor.speed = 0.0
		actor.vel = Vector3.ZERO
		if actor.timer>0.0:
			return
		actor.status = "drive"
	var source: Vector3 = actor.pos
	var goal: Vector3 = actor.goal
	if actor.kind=="police" and _actors.has(actor.target):
		var suspect: Dictionary = _actors[actor.target]
		if suspect.status in ["intercepted","rescued","disabled"]:
			hold(actor.id)
			return
		var behind := _ground_direction(suspect.pos, source)
		goal = suspect.pos + behind * (4.9 if suspect.kind in KIND_VEHICLE else 3.5)
		var suspect_leg: int = suspect.leg
		if suspect_leg>0 and actor.leg!=suspect_leg and suspect_leg<suspect.route.size():
			var corner: Vector3 = suspect.route[suspect_leg-1]
			var route_direction := _ground_direction(corner,suspect.route[suspect_leg])
			if _ground_distance(source,corner)>3.2 and (source-corner).dot(route_direction)<1.7:
				goal = corner
			else:
				actor.leg = suspect_leg
		if _ground_distance(source,suspect.pos)<6.0 and not actor.police_contact:
			actor.police_contact = true
			suspect.impact_delay = 2.0
			_emit("population_police_contact",suspect,{"officer":actor.id})
			area_effect(source,7.0,0.0,"siren")
	elif _advance_route(actor,1.1):
		return
	else:
		goal = actor.goal
	var forward := _ground_direction(source,goal)
	if forward.length_squared() < 0.1:
		actor.speed = move_toward(float(actor.speed),0.0,dt*8.0)
		return
	var across := forward.cross(Vector3.UP)
	var speed_max: float = actor.max_speed
	if actor.impact_delay>0.0:
		speed_max *= 0.51
	var speed_goal := speed_max
	if not actor.patrol_chase:
		var axis := 0 if absf(forward.z)>=absf(forward.x) else 1
		for crossing in CROSSINGS:
			var center_dist := absf(source.z-crossing)
			if axis == 1 and center_dist>9.5:
				continue
			var sign_axis := signf(forward.z if axis==0 else forward.x)
			var distance: float = (crossing-source.z if axis==0 else -source.x)*sign_axis-8.7
			if distance>=-0.12 and distance<16.0 and not has_right_of_way(axis,crossing):
				var clearance := 0.0
				if actor.kind=="police" and not actor.target.is_empty() and not _intersection_occupied(actor,crossing):
					clearance = 3.3
				speed_goal = minf(speed_goal,maxf(clearance,sqrt(maxf(distance-0.40,0.0)*9.0)))
	if speed_goal>0.0:
		var lookahead := maxf(4.1,float(actor.speed)*0.61+2.9)
		for other in _actors.values():
			if other.id==actor.id or other.realm!=actor.realm or other.kind=="prop":
				continue
			var diff: Vector3 = other.pos-source
			if absf(diff.x)>lookahead+3.0 or absf(diff.z)>lookahead+3.0:
				continue
			var projected := diff.dot(forward)
			var width := 1.76 if other.kind in KIND_VEHICLE else 0.92
			if projected>0.0 and projected<lookahead and absf(diff.dot(across))<width and other.status!="rescued":
				var clearance := 4.64 if other.kind in KIND_VEHICLE else 2.62
				var ahead_speed := 0.0
				if other.kind in KIND_VEHICLE or other.id==actor.target:
					var ahead_velocity: Vector3 = other.vel
					ahead_speed = maxf(0.0,ahead_velocity.dot(forward))
				speed_goal = minf(speed_goal, maxf(0.0,ahead_speed+(projected-clearance)*0.83))
	# Real collision surfaces still win if a route is blocked.
	if speed_goal>0.0 and _ground_distance(source,hero)<86.0:
		var test_length := maxf(2.45,minf(8.0,float(actor.speed)*0.51+2.5))
		var allowed := _probe(source+Vector3.UP*0.63,forward,test_length)
		if allowed < test_length:
			speed_goal = minf(speed_goal,maxf(0.0,(allowed-2.04)*2.7))
	actor.speed = move_toward(float(actor.speed),speed_goal,(4.5 if speed_goal>actor.speed else 10.5)*dt)
	actor.vel = forward * actor.speed
	var next := source + Vector3(actor.vel)*dt
	var hero_delta := hero-next
	if absf(hero.y-source.y)<1.60 and absf(hero_delta.dot(forward))<2.04 and absf(hero_delta.dot(across))<1.09:
		if actor.speed>3.2 and _hero_collision<=0.0 and game.has_method("damage"):
			_hero_collision=0.85
			game.damage(minf(18.0,float(actor.speed)*0.87))
			_emit("population_collision",actor,{"other":"player"})
		actor.speed = minf(float(actor.speed),1.4)
		actor.vel = forward*actor.speed
		next = source+Vector3(actor.vel)*dt
	var new_yaw := atan2(-forward.x,-forward.z)
	actor.yaw = lerp_angle(float(actor.yaw),new_yaw,minf(1.0,8.0*dt))
	actor.pos = next
	actor.step_progress = fposmod(float(actor.step_progress) + float(actor.speed) * dt / 0.34, TAU * 20.0)
	actor.last_goal_distance = _ground_distance(next,goal)
	if actor.speed<0.3:
		actor.waiting = float(actor.waiting)+dt
		actor.status = "wait"
		if actor.ambient and actor.waiting>7.5 and _ground_distance(hero,source)>69.0:
			_loop_actor(actor)
	else:
		actor.waiting = 0.0
		actor.status = "chase" if actor.kind=="police" or actor.patrol_chase else ("brake" if speed_goal<float(actor.max_speed)*0.80 else "drive")
	if actor.speed>2.4:
		_bump_nearby_actor(actor,next,forward,across)

func _bump_nearby_actor(actor: Dictionary, at: Vector3, forward: Vector3, across: Vector3) -> void:
	for other in _actors.values():
		if other.realm!=actor.realm or other.kind not in ["civilian","prop"]:
			continue
		var relative: Vector3 = other.pos-at
		var ahead := relative.dot(forward)
		var lateral := relative.dot(across)
		if absf(ahead)>2.4 or absf(lateral)>1.11 or absf(relative.y)>1.05:
			continue
		if other.kind=="prop" and not other.hold and other.impact_delay<=0.0:
			var side := 1.0 if lateral>=0.0 else -1.0
			other.vel = (forward*0.7+across*0.47*side)*minf(7.7,float(actor.speed)*0.68)
			other.impact_delay = 0.44
		elif other.kind=="civilian" and actor.speed>5.8 and absf(ahead)<1.94 and absf(lateral)<0.94 and other.status not in ["injured","rescued"]:
			injure(other.id,78.0)
			_emit("population_collision",actor,{"other":other.id})
			area_effect(at,7.0,0.0,"collision")
			actor.speed=minf(float(actor.speed),2.0)
			break

func _intersection_occupied(driver: Dictionary, crossing: float) -> bool:
	for actor in _actors.values():
		if actor.id==driver.id or actor.realm!=driver.realm or actor.kind=="prop":
			continue
		var pos: Vector3 = actor.pos
		if absf(pos.x)<8.4 and absf(pos.z-crossing)<8.4:
			return true
	return false

func _advance_route(actor: Dictionary, arrive_distance: float) -> bool:
	if _ground_distance(actor.pos,actor.goal)>arrive_distance:
		return false
	if actor.route.is_empty() and not actor.custom_goal:
		actor.vel = Vector3.ZERO
		actor.speed = 0.0
		return true
	if actor.custom_goal:
		actor.vel = Vector3.ZERO
		actor.speed = 0.0
		if not actor.arrived:
			actor.arrived = true
			if actor.status not in ["injured","rescued","escort"]:
				actor.status = "arrived"
			_emit("population_arrived",actor)
		return true
	var route: Array = actor.route
	if actor.leg+1 < route.size():
		actor.leg += 1
		actor.goal = route[actor.leg]
		return false
	if actor.loop:
		if actor.kind not in KIND_VEHICLE:
			actor.leg = 0
			actor.goal = route[0]
			return false
		if _ground_distance(game.runner.global_position,actor.pos)>46.0:
			_loop_actor(actor)
		else:
			actor.status = "wait"
			actor.vel = Vector3.ZERO
			actor.speed = 0.0
		return true
	actor.vel = Vector3.ZERO
	actor.speed = 0.0
	if not actor.arrived:
		actor.arrived = true
		actor.status = "arrived"
		_emit("population_arrived",actor)
	return true

func _loop_actor(actor: Dictionary) -> void:
	if actor.route.size()<2:
		return
	var start: Vector3 = actor.route[0]
	# If the beginning is in view, park until resetting would be less visible.
	if _ground_distance(game.runner.global_position,start)<44.0:
		actor.speed = 0.0
		actor.vel = Vector3.ZERO
		return
	for other in _actors.values():
		if other.id!=actor.id and _ground_distance(start,other.pos)<4.5:
			actor.speed = 0.0
			actor.vel = Vector3.ZERO
			return
	actor.leg = 1
	actor.pos = start
	actor.goal = actor.route[1]
	var direction := _ground_direction(start,actor.goal)
	actor.yaw = atan2(-direction.x,-direction.z)
	actor.waiting = 0.0
	actor.speed = 0.0
	actor.vel = Vector3.ZERO

func _probe(pos: Vector3, direction: Vector3, distance: float) -> float:
	if not is_inside_tree() or distance<0.001:
		return distance
	var world := get_world_3d()
	if world == null:
		return distance
	var q := PhysicsRayQueryParameters3D.create(pos,pos+direction*distance,1|4)
	q.hit_from_inside = true
	var hit := world.direct_space_state.intersect_ray(q)
	return distance if hit.is_empty() else pos.distance_to(hit.position)

func _tick_person(actor: Dictionary, dt: float, hero: Vector3) -> void:
	if actor.hold or actor.status in ["injured","rescued","disabled","intercepted"]:
		actor.vel = Vector3.ZERO
		actor.speed = 0.0
		return
	var source: Vector3 = actor.pos
	var goal: Vector3 = actor.goal
	var speed: float = actor.max_speed
	if actor.impact_delay>0.0:
		speed *= 0.56
	if actor.status in ["flee","panic","investigate","cover"]:
		actor.timer = maxf(0.0,float(actor.timer)-dt)
	if actor.kind=="civilian" and actor.status not in ["flee","panic","cover","escort"] and game.speed>16.0:
		if _ground_distance(hero,source)<3.2 and hero.y<1.8:
			_react_person(actor,hero,"sonic")
	if actor.status=="panic":
		actor.status = "flee"
	if actor.status=="flee":
		speed = maxf(3.7,speed*2.70)
		var away := _ground_direction(actor.hazard,source)
		if away.length_squared() < 0.1:
			away = Vector3(1.0 if source.x>=0.0 else -1.0,0,0)
		var curb := 11.45 if source.x>=0.0 else -11.45
		var escape_x := curb if absf(source.x)<13.0 else (source.x+away.x*3.2)
		goal = Vector3(escape_x,source.y,source.z+away.z*3.2)
		if actor.timer<=0.0:
			actor.status = "cover"
			actor.timer = 1.4
	elif actor.status=="cover":
		actor.speed=0.0
		actor.vel=Vector3.ZERO
		if actor.timer>0.0:
			return
		actor.status="walk"
	elif actor.status=="investigate":
		# Look at the cue first, then resume the scheduled pavement route.
		var facing := _ground_direction(source,actor.hazard)
		actor.yaw=lerp_angle(float(actor.yaw),atan2(-facing.x,-facing.z),minf(1.0,dt*4.5))
		if actor.timer>0.0:
			actor.speed=0.0
			actor.vel=Vector3.ZERO
			return
		actor.status="walk"
	if actor.status not in ["flee","panic"] and _advance_route(actor,0.42):
		return
	if actor.status not in ["flee","panic"]:
		goal = actor.goal
	var direction := _ground_direction(source,goal)
	if direction.length_squared()<0.1:
		actor.vel = Vector3.ZERO
		actor.speed = 0.0
		return
	var crosswalk: bool = absf(direction.x)>0.58 and absf(source.x)<13.0 and absf(goal.x-source.x)>2.0 and actor.ambient and actor.status!="flee"
	if crosswalk and absf(source.x)>=9.3:
		var nearest_crossing := -119.0 if absf(source.z+119.0)<absf(source.z+226.0) else -226.0
		var gap := _walk_signal(nearest_crossing)
		if gap:
			for other in _actors.values():
				if other.kind in KIND_VEHICLE and absf(Vector3(other.pos).z-source.z)<7.5 and absf(Vector3(other.pos).x)<8.0 and other.speed>1.3:
					gap = false
					break
		if not gap:
			actor.status = "wait"
			actor.speed = 0.0
			actor.vel = Vector3.ZERO
			return
	if actor.status not in ["flee","escort"]:
		actor.status = "cross" if crosswalk else ("escape" if actor.kind=="suspect" else "walk")
	if _ground_distance(hero,source)<52.0:
		for other in _actors.values():
			if other.id==actor.id or other.kind!="civilian" or other.realm!=actor.realm:
				continue
			var offset: Vector3 = other.pos-source
			if absf(offset.x)<0.75 and absf(offset.z)<0.75 and offset.dot(direction)>0.04:
				direction = (direction+direction.cross(Vector3.UP)*0.43).normalized()
				speed *= 0.79
				break
		if _probe(source+Vector3.UP*0.57,direction,maxf(0.44,speed*dt+0.30))<0.38:
			var alternate := (direction + direction.cross(Vector3.UP)*0.54).normalized()
			if _probe(source+Vector3.UP*0.57,alternate,0.44)>=0.42:
				direction = alternate
			else:
				speed = 0.0
	actor.speed = lerpf(float(actor.speed),speed,minf(dt*10.0,1.0))
	actor.vel = direction*actor.speed
	actor.pos = source+Vector3(actor.vel)*dt
	actor.step_progress = fposmod(actor.step_progress+actor.speed*dt*3.7,TAU*30.0)
	actor.yaw = lerp_angle(float(actor.yaw),atan2(-direction.x,-direction.z),minf(dt*10.0,1.0))

func _tick_prop(actor: Dictionary,dt: float,hero: Vector3) -> void:
	var vel: Vector3 = actor.vel
	if not actor.hold and actor.impact_delay<=0.0 and game.speed>3.5 and absf(hero.y-Vector3(actor.pos).y)<1.0:
		var reach := _ground_distance(actor.pos,hero)
		if reach<1.08:
			vel += _ground_direction(hero,actor.pos)*minf(6.5,float(game.speed)*0.38)
			actor.impact_delay = 0.34
	if actor.hold or vel.length_squared()<0.0064:
		actor.vel = Vector3.ZERO
		return
	var source: Vector3 = actor.pos
	var planar := Vector3(vel.x,0.0,vel.z)
	var distance := planar.length()*dt
	var heading := planar.normalized()
	var allowed := _probe(source+Vector3.UP*0.41,heading,distance+0.37)
	if allowed<distance+0.35:
		actor.vel = -vel*0.29
		actor.pos = source+heading*maxf(allowed-0.37,0.0)
		return
	actor.pos = source+vel*dt
	actor.yaw = fposmod(float(actor.yaw)+distance*0.87,TAU)
	actor.vel = vel.move_toward(Vector3.ZERO,dt*5.3)

func _react_person(actor: Dictionary, origin: Vector3, mode: String) -> bool:
	if actor.kind!="civilian" or actor.status in ["injured","rescued","escort","disabled"] or actor.hold:
		return false
	actor.hazard = origin
	actor.status = "investigate" if mode=="lightning" and _ground_distance(actor.pos,origin)>4.5 else "panic"
	actor.timer = 1.7 if actor.status=="investigate" else (3.7 if mode in ["enemy","collision","crime"] else 2.7)
	return true

func area_effect(at: Vector3, radius: float, force: float = 0.0, mode: String = "shockwave") -> int:
	if radius<=0.0 or not at.is_finite():
		return 0
	var affected := 0
	var realm: String = str(game.realm)
	for actor in _actors.values():
		if actor.realm!=realm or _ground_distance(actor.pos,at)>radius or absf(Vector3(actor.pos).y-at.y)>3.0:
			continue
		if actor.kind=="prop" and not actor.hold and force>0.0 and affected<15:
			var outward := _ground_direction(at,actor.pos)
			if outward.length_squared()<0.1:
				outward=Vector3.RIGHT
			var impulse: Vector3
			if mode=="tornado":
				impulse=(outward.cross(Vector3.UP)*0.9-outward*0.70)*force
			else:
				impulse=outward*force*maxf(0.14,1.0-_ground_distance(actor.pos,at)/radius)
			actor.vel=(Vector3(actor.vel)+impulse).limit_length(15.5)
			affected+=1
		elif mode=="shockwave" and force>=9.0 and actor.kind in KIND_VEHICLE and not actor.hold and actor.status not in ["crash","disabled","intercepted"] and _ground_distance(actor.pos,at)<=radius*0.81:
			var amount := _ground_distance(actor.pos,at)
			if _probe(at+Vector3.UP*0.65,_ground_direction(at,actor.pos),amount)+0.20>=amount:
				actor.speed = 0.0
				actor.vel = Vector3.ZERO
				actor.status = "stagger"
				actor.timer = 1.35
				actor.impact_delay = 2.8
				affected += 1
				_emit("population_staggered",actor,{"origin":at})
		elif _react_person(actor,at,mode):
			affected+=1
	return affected

func can_interact() -> bool:
	return not _nearby_action().is_empty()

func interact() -> bool:
	var candidate := _nearby_action()
	return not candidate.is_empty() and interact_id(candidate)

func _nearby_action() -> String:
	if game==null:
		return ""
	var hero: Vector3 = game.runner.global_position
	var candidate := ""
	var distance := 5.0
	for actor in _actors.values():
		if not _can_interact(actor,hero):
			continue
		var remaining := _ground_distance(hero,actor.pos)
		if remaining<distance:
			candidate = actor.id
			distance = remaining
	return candidate

func interact_id(id: String) -> bool:
	var actor := query(id)
	if actor.is_empty() or not _can_interact(actor,game.runner.global_position):
		return false
	var rescue: bool = actor.kind=="civilian"
	var status := "rescued" if rescue else "intercepted"
	set_status(id,status)
	hold(id)
	_emit("population_rescued" if rescue else "population_intercepted",actor)
	if crime.get("primary_id","")==id:
		_finish_crime(true,actor.pos)
	return true

func _can_interact(actor: Dictionary, hero: Vector3) -> bool:
	if actor.realm!=str(game.realm) or absf(Vector3(actor.pos).y-hero.y)>2.2:
		return false
	var distance := _ground_distance(hero,actor.pos)
	if actor.kind=="civilian":
		return distance<=3.6 and actor.status in ["injured","escort"]
	if actor.status in ["rescued","intercepted","disabled"]:
		return false
	var chase: bool = actor.patrol_chase or actor.kind=="suspect"
	if not chase or distance>4.4:
		return false
	return float(actor.speed)<(15.0 if actor.kind=="suspect" else 13.0) and float(game.speed)<24.0

func begin_escort(id: String, goal: Vector3) -> bool:
	var actor := query(id)
	if actor.is_empty() or actor.status!="injured" or not _can_interact(actor,game.runner.global_position):
		return false
	set_status(id,"escort")
	return move_goal(id,goal)

func set_patrol(enabled: bool) -> void:
	_patrol = enabled
	if not enabled and not crime.is_empty():
		_clear_crime()

func _tick_crime(dt: float, hero: Vector3) -> void:
	if not _patrol:
		return
	if crime.is_empty():
		_crime_cooldown = maxf(0.0,_crime_cooldown-dt)
		if _crime_cooldown<=0.0 and absf(hero.x)<45.0 and hero.z>-279.0 and hero.z<22.0 and absf(hero.y)<6.0:
			_begin_crime(hero)
		return
	if crime.outcome!="active":
		crime.time = float(crime.time)-dt
		if crime.time<=0.0:
			_clear_crime()
		return
	crime.time = float(crime.time)-dt
	var primary := query(crime.primary_id)
	if not primary.is_empty():
		crime.pos = primary.pos
	if crime.time<=0.0 or primary.is_empty() or primary.status=="arrived":
		_finish_crime(false,crime.pos)

func _begin_crime(hero: Vector3) -> void:
	var incident_type: String = ["pursuit","rescue","escape"][_crime_seq%3]
	_crime_seq += 1
	var incident_id := "calder.%d.%d"%[_crime_run,_crime_seq]
	var actor_id := incident_id+".target"
	var end_direction := -1.0 if hero.z>-135.0 else 1.0
	var spacing := 30.0 + float(posmod(_crime_run + _crime_seq*7,11))
	var start_z := hero.z+end_direction*spacing
	var lane := -3.7*end_direction
	var side := 1.0 if hero.x>=0.0 else -1.0
	var at := Vector3(lane,0.0,start_z)
	var end := Vector3(lane,0.0, -295.0 if end_direction<0.0 else 18.0)
	var others: Array[String] = []
	var title: String
	var objective: String
	var payout: int
	var allotted: float
	match incident_type:
		"pursuit":
			title = "Dispatch · Stolen courier van"
			objective = "Catch the marked van and interact beside it."
			payout = 45
			allotted = 39.0
			spawn(actor_id,"van",at,{"goal":end,"speed":10.5,"chase":true,"status":"chase","variant":2})
			var officer_id := incident_id+".patrol"
			spawn(officer_id,"police",at-Vector3(0,0,end_direction*15.0),{"goal":end,"speed":15.6,"target":actor_id})
			others.append(officer_id)
		"rescue":
			title = "Dispatch · Collision on Calder"
			objective = "Check on the injured pedestrian next to the disabled van."
			payout = 35
			allotted = 45.0
			at.x = side*9.4
			spawn(actor_id,"civilian",at,{"health":19.0,"status":"injured","held":true})
			var wreck_id := incident_id+".wreck"
			spawn(wreck_id,"van",at+Vector3(-side*2.6,0,2.2),{"status":"crash","held":true,"variant":3})
			others.append(wreck_id)
		"escape":
			title = "Dispatch · Suspect on foot"
			objective = "Catch the marked runner and interact at close range."
			payout = 38
			allotted = 34.0
			at.x = side*11.35
			at.z = hero.z+end_direction*26.0
			end.x = at.x
			spawn(actor_id,"suspect",at,{"goal":end,"speed":5.4,"chase":true,"status":"escape"})
	if query(actor_id).is_empty():
		for id in others:
			deactivate(id)
		_crime_cooldown = 8.0
		return
	crime = {
		"id":incident_id,"kind":incident_type,"primary_id":actor_id,"others":others,"pos":at,
		"title":title,"objective":objective,"payout":payout,"time":allotted,"outcome":"active",
	}
	area_effect(at,14.0,0.0,"crime")
	_announce(title,4.0)
	_emit("crime_started",crime,crime.duplicate(true))

func _finish_crime(success: bool, at: Vector3) -> void:
	if crime.is_empty() or crime.outcome!="active":
		return
	crime.pos = at
	crime.outcome = "complete" if success else "failed"
	crime.time = 4.0
	var target := query(crime.primary_id)
	if not success and not target.is_empty():
		hold(target.id)
	for id in crime.others:
		hold(id)
	_announce("Incident resolved" if success else "Dispatch closed the incident")
	_emit("crime_completed" if success else "crime_failed",crime,crime.duplicate(true))

func _clear_crime() -> void:
	deactivate(crime.primary_id)
	for id in crime.others:
		deactivate(id)
	crime.clear()
	_crime_cooldown = 24.0

func snapshot() -> Dictionary:
	var generations := PackedInt32Array()
	var status := PackedStringArray()
	var motion := PackedFloat32Array()
	generations.resize(_actors.size())
	status.resize(_actors.size())
	motion.resize(_actors.size()*STRIDE)
	var ix := 0
	for actor in _actors.values():
		generations[ix] = actor.generation
		status[ix] = actor.status
		var offset := ix*STRIDE
		var pos: Vector3 = actor.pos
		var vel: Vector3 = actor.vel
		var goal: Vector3 = actor.goal
		var hazard: Vector3 = actor.hazard
		motion[offset] = pos.x
		motion[offset+1] = pos.y
		motion[offset+2] = pos.z
		motion[offset+3] = vel.x
		motion[offset+4] = vel.y
		motion[offset+5] = vel.z
		motion[offset+6] = actor.yaw
		motion[offset+7] = actor.health
		motion[offset+8] = actor.timer
		motion[offset+9] = actor.speed
		motion[offset+10] = actor.leg
		motion[offset+11] = goal.x
		motion[offset+12] = goal.y
		motion[offset+13] = goal.z
		motion[offset+14] = 1.0 if actor.hold else 0.0
		motion[offset+15] = actor.step_progress
		motion[offset+16] = 1.0 if actor.arrived else 0.0
		motion[offset+17] = 1.0 if actor.custom_goal else 0.0
		motion[offset+18] = actor.waiting
		motion[offset+19] = hazard.x
		motion[offset+20] = hazard.y
		motion[offset+21] = hazard.z
		motion[offset+22] = actor.last_goal_distance
		motion[offset+23] = 1.0 if actor.police_contact else 0.0
		motion[offset+24] = actor.impact_delay
		ix += 1
	return {
		"generations":generations,"status":status,"motion":motion,"clock":_clock,
		"tick":_local_tick,"player_impact":_hero_collision,"cooldown":_crime_cooldown,
		"crime_seq":_crime_seq,"patrol":_patrol,"crime":crime.duplicate(true),
	}

func restore(state: Dictionary) -> void:
	var generations: PackedInt32Array = state.get("generations",PackedInt32Array())
	var status: PackedStringArray = state.get("status",PackedStringArray())
	var motion: PackedFloat32Array = state.get("motion",PackedFloat32Array())
	if status.size()!=generations.size() or motion.size()!=generations.size()*STRIDE or not state.has("clock"):
		return
	_clock = state.clock
	_local_tick = state.tick
	_hero_collision = state.player_impact
	_crime_cooldown = state.cooldown
	_crime_seq = state.crime_seq
	_patrol = state.patrol
	crime = state.crime.duplicate(true)
	var restored: Dictionary = {}
	var hero: Vector3 = game.runner.global_position
	var realm: String = str(game.realm)
	var new_nodes := 0
	for ix in range(generations.size()):
		var generation := generations[ix]
		if not _specs.has(generation):
			continue
		var spec: Dictionary = _specs[generation]
		var id: String = spec.id
		var actor := query(id)
		if actor.is_empty() or actor.generation!=generation:
			# A future incarnation of the same named actor can use a different model.
			deactivate(id)
			actor = spec.duplicate()
			_actors[id] = actor
		restored[id] = actor
		_load_motion(actor,status[ix],motion,ix*STRIDE)
		var dist_sq := hero.distance_squared_to(actor.pos)
		var near: bool = actor.realm == realm and dist_sq<6400.0
		if near and not _nodes.has(id) and new_nodes<2:
			_make_node(actor,true)
			new_nodes += 1
		if _nodes.has(id):
			_sync_node(actor,near,near and dist_sq<1936.0,true)
	for id in _actors.keys():
		if not restored.has(id):
			deactivate(id)
	_actors = restored
	_sync_lights(hero if realm=="city" else Vector3(0,0,1360))

func _load_motion(actor: Dictionary, status: String, motion: PackedFloat32Array, offset: int) -> void:
	actor.status = status
	actor.pos = Vector3(motion[offset],motion[offset+1],motion[offset+2])
	actor.vel = Vector3(motion[offset+3],motion[offset+4],motion[offset+5])
	actor.yaw = motion[offset+6]
	actor.health = motion[offset+7]
	actor.timer = motion[offset+8]
	actor.speed = motion[offset+9]
	actor.leg = int(motion[offset+10])
	actor.goal = Vector3(motion[offset+11],motion[offset+12],motion[offset+13])
	actor.hold = motion[offset+14]>0.5
	actor.step_progress = motion[offset+15]
	actor.arrived = motion[offset+16]>0.5
	actor.custom_goal = motion[offset+17]>0.5
	actor.waiting = motion[offset+18]
	actor.hazard = Vector3(motion[offset+19],motion[offset+20],motion[offset+21])
	actor.last_goal_distance = motion[offset+22]
	actor.police_contact = motion[offset+23]>0.5
	actor.impact_delay = motion[offset+24]
