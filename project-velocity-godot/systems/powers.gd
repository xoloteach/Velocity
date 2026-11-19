extends Node3D
## Combat and traversal abilities run on the game's fixed-step clock.

const Fx := preload("res://systems/power_fx.gd")
const HERO_PHASE := preload("res://assets/hero_phase.gdshader")
const PHASE_LAYER := 4
const BODY_MASK := 1 | PHASE_LAYER | 8
const MAX_BOLTS := 24
const TRACE_RATE := 1.0 / 24.0
const MAX_TRACE := 90
const SLOW_SCALE := 0.34
const CITY_PORTAL := Vector3(128, 0, -119)
const CITY_RETURN := Vector3(132, 0, -119)
const RIFT_ARRIVAL := Vector3(0, 0, 1360)
const RIFT_EXIT := Vector3(0, 0, 1317)

var game
var specs: Dictionary = {}
var cooldowns: Dictionary = {}
var hero_pose := ""
var pose_time := 0.0
var bolts: Array[Dictionary] = []
var _bolt_index := 0
var _fx: Node3D
var _targets: Dictionary = {}
var _pending := ""
var _windup := 0.0
var _pending_target := -1
var _phase_active := false
var _phase_time := 0.0
var _phase_mask := BODY_MASK
var _phase_origin := Vector3.ZERO
var _phase_extension := 0.0
var _slow_time := 0.0
var _tornado_time := 0.0
var _tornado_pos := Vector3.ZERO
var _tornado_pulse := 0.0
var _trace_timer := 0.0
var _trace: Array[Vector3] = []
var _trace_pose: Array[Vector3] = []
var _trace_clips: Array[String] = []
var _trace_frames: Array[float] = []
var _mirage_path := PackedVector3Array()
var _mirage_pose := PackedVector3Array()
var _mirage_clips := PackedStringArray()
var _mirage_frames := PackedFloat32Array()
var _mirage_left := 0.0
var _mirage_location := Vector3.INF
var _city_portal := CITY_PORTAL
var _city_return := CITY_RETURN
var _rift_portal := RIFT_EXIT
var _rift_arrival := RIFT_ARRIVAL
var _visible_gate := true
var _clock := 0.0
var _phase_shader_mat: ShaderMaterial
var _phase_visual_applied := false


func setup(owner_game) -> void:
	game = owner_game
	specs = JSON.parse_string(FileAccess.get_file_as_string("res://shared/power_specs.json")).powers
	for id: String in specs:
		cooldowns[id] = 0.0
	_fx = Fx.new()
	add_child(_fx)
	_phase_shader_mat = ShaderMaterial.new()
	_phase_shader_mat.shader = HERO_PHASE


func _sync_phase_visual() -> void:
	if _phase_visual_applied == _phase_active or game == null:
		return
	var suit_node: Variant = game.get("suit")
	if not (suit_node is Node) or not is_instance_valid(suit_node):
		return
	_phase_visual_applied = _phase_active
	for node in (suit_node as Node).find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if is_instance_valid(mi):
			mi.material_override = _phase_shader_mat if _phase_active else null


func configure_portal(city_at: Vector3, rift_at: Vector3, rift_return: Vector3, city_return: Vector3) -> void:
	_city_portal = city_at
	_city_return = city_return
	_rift_portal = rift_return
	_rift_arrival = rift_at


func set_portal_visible(active: bool) -> void:
	_visible_gate = active


func register_target(id: String, node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	_targets[id] = node


func unregister_target(id: String) -> void:
	_targets.erase(id)


func phased() -> bool:
	return _phase_active


func slow_factor() -> float:
	return SLOW_SCALE if _slow_time > 0.0 else 1.0


func decoy_position(observer: Vector3, radius: float = 18.0) -> Vector3:
	if _mirage_left <= 0 or not _mirage_location.is_finite():
		return Vector3.INF
	if observer.distance_squared_to(_mirage_location) > radius * radius:
		return Vector3.INF
	if not _line_clear(observer + Vector3.UP, _mirage_location + Vector3.UP):
		return Vector3.INF
	return _mirage_location


func cooldown_left(id: String) -> float:
	return float(cooldowns.get(id, 0.0))


func command(action: String) -> bool:
	if not specs.has(action):
		return false
	var spec: Dictionary = specs[action]
	var name_text: String = spec.name
	if game.paused or game.health <= 0:
		return false
	if action == "phase" and _phase_active:
		_phase_time = 0.0
		_finish_phase(0.0)
		return true
	if _pending != "":
		game.announce("Finish the current cast", 0.8)
		return false
	if cooldown_left(action) > 0.0:
		game.announce("%s ready in %.1fs" % [name_text, cooldown_left(action)], 1.25)
		return false
	if game.energy < float(spec.cost):
		game.announce("More charge needed for %s" % name_text, 1.35)
		return false
	var selected := -1
	match action:
		"portal":
			var anchor := _rift_portal if game.realm == "rift" else _city_portal
			if not _near_gate(game.runner.global_position, anchor, float(spec.range)):
				game.announce("Reach the glowing rift gate", 2.0)
				return false
		"redirect":
			selected = _find_redirect()
			if selected < 0:
				game.announce("Face a hostile bolt as it approaches", 1.6)
				return false
		"mirage":
			if _trace.size() < 8:
				game.announce("Keep moving to build a mirage trail", 1.6)
				return false
	game.energy = maxf(0.0, game.energy - float(spec.cost))
	cooldowns[action] = float(spec.cooldown)
	hero_pose = String(spec.pose)
	pose_time = float(spec.windup) + float(spec.recovery)
	_pending = action
	_pending_target = selected
	_windup = float(spec.windup)
	if action == "shockwave":
		_fx.ring(game.runner.global_position, Color("#bd7a45"), _windup, float(spec.range))
	elif action == "portal":
		_fx.ring(game.runner.global_position, Color("#be89f4"), _windup, 3.2)
	if _windup <= 0.0:
		_resolve()
	return true


func step(dt: float) -> void:
	if game.paused or dt <= 0.0:
		return
	_clock += dt
	pose_time = maxf(0.0, pose_time - dt)
	if pose_time == 0.0:
		hero_pose = ""
	for id: String in cooldowns:
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - dt)
	_record_trace(dt)
	if _pending != "":
		_windup -= dt
		if _windup <= 0.0:
			_resolve()
	_slow_time = maxf(0.0, _slow_time - dt)
	if _phase_active:
		_phase_time -= dt
		if _phase_time <= 0.0:
			_finish_phase(dt)
		elif game.effects and fmod(_clock, 0.12) < dt:
			_fx.ring(game.runner.global_position, Color("#94dffc"), 0.24, 1.2)
	_step_tornado(dt)
	_step_bolts(dt)
	_step_mirage(dt)
	_render_effects(dt)


func render_restored() -> void:
	_step_mirage(0.0)
	_render_effects(0.0)


func _resolve() -> void:
	var action := _pending
	var selected := _pending_target
	_pending = ""
	_pending_target = -1
	_windup = 0.0
	if action.is_empty():
		return
	var at: Vector3 = game.runner.global_position
	var spec: Dictionary = specs[action]
	var color := Color(String(spec.color))
	var succeeded := true
	match action:
		"lightning":
			_lightning(at + Vector3.UP * 1.24)
		"shockwave":
			var enemy_count: int = game.combat.damage_near(at + Vector3.UP * 0.6, float(spec.range), 22.0, 10.0)
			var objects: int = game.population.area_effect(at, float(spec.range), 13.0, "shockwave")
			game.event("shockwave_hit", {"count": enemy_count + objects, "position": at})
			_fx.ring(at, color, 0.40, float(spec.range))
			_fx.ring(at, Color("#ffedb6"), 0.24, float(spec.range) * 0.86)
			if enemy_count + objects == 0:
				game.announce("Shockwave cleared the area", 0.9)
		"phase":
			if not _phase_active:
				_phase_mask = game.runner.collision_mask
			_phase_active = true
			_phase_time = float(spec.active)
			_phase_extension = 0.0
			_phase_origin = at if _placement_clear(at) else game.safe_position
			game.runner.collision_mask = _phase_mask & ~PHASE_LAYER
			_sync_phase_visual()
			_fx.ring(at, color, 0.31, 2.3)
		"tornado":
			_tornado_time = float(spec.active)
			_tornado_pos = at
			_tornado_pulse = 0.0
			_fx.ring(at, color, 0.43, float(spec.range))
		"redirect":
			succeeded = _redirect(selected)
		"mirage":
			_mirage_path = PackedVector3Array(_trace)
			_mirage_pose = PackedVector3Array(_trace_pose)
			_mirage_clips = PackedStringArray(_trace_clips)
			_mirage_frames = PackedFloat32Array(_trace_frames)
			_mirage_left = float(spec.active)
			_mirage_location = _mirage_path[0]
			game.event("mirage_spawned", {"start": _mirage_location, "samples": _mirage_path.size()})
			_fx.ring(at, color, 0.27, 1.7)
		"slow":
			_slow_time = float(spec.active)
			_fx.ring(at, color, 0.50, 5.7)
		"portal":
			succeeded = _portal()
	if succeeded:
		game.pulse(String(spec.audio), at, 1.0)
		game.event("ability_cast", {"id": action, "position": at})
	else:
		game.energy = minf(100.0, game.energy + float(spec.cost))
		cooldowns[action] = 0.0
		hero_pose = ""
		pose_time = 0.0


func _forward() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, float(game.hero_heading))


func _lightning(start: Vector3) -> void:
	var facing := _forward()
	var reach := float(specs.lightning.range)
	var destination: Vector3 = game.combat.target_position(reach)
	var distance := reach
	if destination.is_finite() and _line_clear(start, destination):
		distance = start.distance_to(destination)
	else:
		destination = Vector3.INF
	for id: String in _targets:
		var target = _targets[id]
		if not is_instance_valid(target) or not target.is_inside_tree():
			continue
		var point: Vector3 = target.global_position + Vector3.UP * 0.8
		var delta := point - start
		if delta.length() < distance and facing.dot(delta.normalized()) > 0.68 and _reaches_target(start, point, target):
			destination = point
			distance = delta.length()
	var direction := facing
	if destination.is_finite():
		direction = (destination - start).normalized()
	_add_bolt(start, direction * 52.0, 23.0, false, "lightning")
	_fx.arc(start - Vector3.UP * 0.16, start + direction * 1.55, "amber", _bolt_index)


func spawn_hostile(pos: Vector3, velocity: Vector3, amount: float) -> int:
	if not pos.is_finite() or not velocity.is_finite() or not is_finite(amount) or amount <= 0.0 or velocity.is_zero_approx():
		return -1
	return _add_bolt(pos, velocity.limit_length(66.0), amount, true, "hostile")


func _add_bolt(pos: Vector3, speed: Vector3, amount: float, hostile: bool, kind: String) -> int:
	if bolts.size() == MAX_BOLTS:
		bolts.pop_front()
	_bolt_index += 1
	bolts.append({"id": _bolt_index, "pos": pos, "last": pos, "v": speed,
		"damage": amount, "hostile": hostile, "kind": kind, "left": 1.9 if hostile else 0.73})
	return _bolt_index


func _step_bolts(dt: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var bolt := bolts[i]
		var is_hostile := bool(bolt.hostile)
		var scaled := dt * slow_factor() if is_hostile else dt
		bolt.left = float(bolt.left) - scaled
		if float(bolt.left) <= 0.0:
			bolts.remove_at(i)
			continue
		var start: Vector3 = bolt.pos
		var end := start + Vector3(bolt.v) * scaled
		bolt.last = start
		var wall := _ray(start, end, 1 | PHASE_LAYER)
		if not wall.is_empty():
			end = Vector3(wall.position)
		bolt.pos = end
		var collided := false
		if is_hostile:
			var chest: Vector3 = game.runner.global_position + Vector3.UP * 0.91
			if start.distance_squared_to(end) > 0.0001 and not phased() and _segment_distance(chest, start, end) < 0.66:
				game.damage(float(bolt.damage))
				collided = true
		else:
			var target_hit: String = game.combat.ray_target(start, end, 0.63)
			var marked := _find_switch(start, end, wall.get("collider"))
			var enemy: Vector3 = game.combat.target_center(target_hit)
			var enemy_first := enemy.is_finite() and (marked.is_empty() or _projection(enemy, start, end) <= _projection(_target_center(marked), start, end))
			if enemy_first and game.combat.strike_target(target_hit, float(bolt.damage), start, String(bolt.kind), 4.5):
				game.event("lightning_hit", {"id": target_hit, "position": end, "projectile": int(bolt.id)})
				collided = true
			elif not marked.is_empty():
				game.event("lightning_hit", {"id": marked, "position": end, "projectile": int(bolt.id)})
				collided = true
		if collided or not wall.is_empty():
			if not is_hostile:
				game.population.area_effect(end, 3.8, 2.2, "lightning")
				if not wall.is_empty() and game.quality > 0:
					_fx.scorch(end, wall.normal, int(bolt.id))
			var palette := "violet" if is_hostile else "amber"
			_fx.arc(start, end, palette, int(bolt.id))
			_fx.ring(end - Vector3.UP * 0.28, Color("#b397ff") if is_hostile else Color("#ffc274"), 0.25, 1.8)
			game.pulse("impact", end, 0.69)
			bolts.remove_at(i)


func _find_switch(start: Vector3, end: Vector3, surface: Object) -> String:
	var near := ""
	var distance := INF
	for id: String in _targets:
		var target = _targets[id]
		if not is_instance_valid(target) or not target.is_inside_tree():
			continue
		if surface == target:
			return id
		var point := _target_center(id)
		if _segment_distance(point, start, end) < 0.65 and point.distance_squared_to(start) < distance and _reaches_target(start, point, target):
			near = id
			distance = point.distance_squared_to(start)
	return near


func _target_center(id: String) -> Vector3:
	return _targets[id].global_position + Vector3.UP * 0.8


func _find_redirect() -> int:
	var start: Vector3 = game.runner.global_position + Vector3.UP * 0.95
	var facing := _forward()
	var chosen := -1
	var distance := float(specs.redirect.range)
	for bolt: Dictionary in bolts:
		if not bool(bolt.hostile):
			continue
		var point: Vector3 = bolt.pos
		var offset := point - start
		var close := offset.length()
		var front := facing.dot(offset.normalized()) > -0.20
		var inbound := Vector3(bolt.v).normalized().dot(-offset.normalized()) > 0.15
		if close < distance and front and inbound and _line_clear(start, point):
			distance = close
			chosen = int(bolt.id)
	return chosen


func _redirect(id: int) -> bool:
	var start: Vector3 = game.runner.global_position + Vector3.UP
	for bolt: Dictionary in bolts:
		if int(bolt.id) != id or not bool(bolt.hostile):
			continue
		var point: Vector3 = bolt.pos
		if point.distance_to(start) > float(specs.redirect.range) + 0.75 or not _line_clear(start, point):
			break
		var direction := _forward()
		var enemy: Vector3 = game.combat.target_position(32.0)
		if enemy.is_finite() and _line_clear(point, enemy):
			direction = (enemy - point).normalized()
		bolt.hostile = false
		bolt.v = direction * 51.0
		bolt.damage = maxf(25.0, float(bolt.damage) * 1.70)
		bolt.kind = "redirect"
		bolt.left = 0.80
		_fx.ring(point - Vector3.UP * 0.32, Color("#ffe39a"), 0.3, 2.5)
		_fx.arc(point, point + direction * 2.7, "amber", id)
		game.announce("Projectile redirected", 1.2)
		game.event("projectile_redirected", {"id": id, "position": point, "velocity": bolt.v})
		return true
	game.announce("Redirect window missed", 1.15)
	return false


func _step_tornado(dt: float) -> void:
	if _tornado_time <= 0.0:
		return
	_tornado_time = maxf(0, _tornado_time - dt)
	_tornado_pulse -= dt
	if _tornado_pulse <= 0.0:
		_tornado_pulse += 0.24
		var radius := float(specs.tornado.range)
		game.population.area_effect(_tornado_pos, radius, 5.9, "tornado")
		game.combat.damage_near(_tornado_pos + Vector3.UP * 0.6, radius, 2.25, 0.4, "tornado")
		_fx.ring(_tornado_pos, Color("#a8eedb"), 0.33, radius * 0.74)
	if not game.effects:
		return
	for stem in range(5):
		var angle := _clock * (5.2 + stem * 0.13) + stem * TAU / 5
		var base := Vector3(cos(angle), 0.0, sin(angle))
		var tip := Vector3(cos(angle + 0.49), 0.0, sin(angle + 0.49))
		for level in range(3):
			var radius := 2.15 + level * 1.25
			var from := _tornado_pos + base * radius + Vector3.UP * (0.24 + level * 0.88)
			var to := _tornado_pos + tip * (radius + 0.51) + Vector3.UP * (0.47 + level * 0.99)
			_fx.arc(from, to, "mint", stem * 7 + level)


func _finish_phase(dt: float) -> void:
	var at: Vector3 = game.runner.global_position
	var recovered := false
	if not _placement_clear(at):
		if _phase_extension < 0.34:
			if _phase_extension == 0.0:
				game.announce("Move out of the barrier to end phase", 0.8)
			_phase_extension += dt
			return
		var safe := _phase_escape()
		if not safe.is_finite():
			return
		game.runner.global_position = safe
		game.runner.reset_physics_interpolation()
		game.runner.velocity = Vector3.ZERO
		game.announce("Phase exit obstructed. Returned to clear ground.", 2.4)
		recovered = true
	_phase_active = false
	_phase_time = 0.0
	_restore_phase_mask()
	_sync_phase_visual()
	_fx.ring(game.runner.global_position, Color("#a9e2ff"), 0.22, 1.55)
	game.event("phase_exited", {"recovered": recovered, "position": game.runner.global_position})


func _restore_phase_mask() -> void:
	game.runner.collision_mask = (game.runner.collision_mask & ~PHASE_LAYER) | (_phase_mask & PHASE_LAYER)


func _phase_escape() -> Vector3:
	var last_safe: Vector3 = game.safe_position
	for safe: Vector3 in [_phase_origin, last_safe]:
		if _placement_clear(safe):
			return safe
	for radius: float in [0.9, 1.8, 3.2]:
		for index in range(8):
			var offset := Vector3.RIGHT.rotated(Vector3.UP, index * TAU / 8.0) * radius
			if _placement_clear(last_safe + offset):
				return last_safe + offset
	return Vector3.INF


func _placement_clear(at: Vector3) -> bool:
	var hero: CharacterBody3D = game.runner
	var shape: CollisionShape3D
	for child: Node in hero.get_children():
		if child is CollisionShape3D and not child.disabled:
			shape = child
			break
	if not is_instance_valid(shape) or not at.is_finite():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	var target := shape.global_transform
	target.origin += at - hero.global_position
	target.origin.y += 0.035
	query.transform = target
	query.exclude = [hero.get_rid()]
	query.collision_mask = BODY_MASK
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _record_trace(dt: float) -> void:
	_trace_timer -= dt
	if _trace_timer > 0.0:
		return
	_trace_timer += TRACE_RATE
	if _trace.size() >= MAX_TRACE:
		_trace.pop_front()
		_trace_pose.pop_front()
		_trace_clips.pop_front()
		_trace_frames.pop_front()
	_trace.append(game.runner.global_position)
	_trace_pose.append(Vector3(game.hero_heading, game.speed, 0.0 if game.runner.is_on_floor() else 1.0))
	var animation := game.get("animations") as AnimationPlayer
	var running := is_instance_valid(animation) and animation.is_playing()
	_trace_clips.append(animation.current_animation if running else "")
	_trace_frames.append(animation.current_animation_position if running else 0.0)


func _step_mirage(dt: float) -> void:
	if _mirage_left <= 0.0:
		return
	_mirage_left = maxf(0.0, _mirage_left - dt)
	if _mirage_left == 0.0 or _mirage_path.is_empty():
		_fx.hide_ghost()
		_mirage_location = Vector3.INF
		return
	var span := float(specs.mirage.active)
	var elapsed := 1.0 - _mirage_left / span
	var offset := elapsed * (_mirage_path.size() - 1)
	var from := int(offset)
	var to := mini(from + 1, _mirage_path.size() - 1)
	_mirage_location = _mirage_path[from].lerp(_mirage_path[to], fmod(offset, 1.0))
	var pose := _mirage_pose[from]
	_fx.ghost(_mirage_location, pose.x, pose.y, pose.z > 0.5, _mirage_left, _mirage_clips[from], _mirage_frames[from])


func _portal() -> bool:
	var realm: String = game.realm
	var from: Vector3 = game.runner.global_position
	var incoming := realm == "city"
	var target_realm := "rift" if incoming else "city"
	var target := _rift_arrival if incoming else _city_return
	var anchor := _city_portal if incoming else _rift_portal
	if not _near_gate(from, anchor, float(specs.portal.range) + 1.25):
		game.announce("Portal cast interrupted. Stay at the gate.", 2.2)
		return false
	if _phase_active:
		_restore_phase_mask()
		_phase_active = false
		_sync_phase_visual()
	game.teleport(target, target_realm)
	if game.realm != target_realm:
		game.announce("Rift unavailable. Your position was preserved.", 2.4)
		return false
	clear_realm()
	_fx.ring(target, Color("#cda9ff"), 0.57, 5.0)
	game.announce("Rift reached" if incoming else "Returned to Calder", 1.5)
	game.event("portal_entered" if incoming else "portal_returned", {"from": from, "to": target})
	return true


func _render_effects(dt: float) -> void:
	if not is_instance_valid(_fx):
		return
	var at: Vector3 = game.runner.global_position
	var low_motion := not bool(game.effects)
	_fx.gates(_city_portal, _rift_portal, at if _visible_gate else Vector3.INF, game.realm == "rift", low_motion)
	for bolt: Dictionary in bolts:
		var point: Vector3 = bolt.pos
		var previous: Vector3 = bolt.last
		var direction := Vector3(bolt.v).normalized()
		var palette := "violet" if bool(bolt.hostile) else "amber"
		_fx.arc(previous - direction * 0.44, point + direction * 0.16, palette, int(bolt.id))
		if not low_motion and game.quality >= 2:
			var side := direction.cross(Vector3.UP) * 0.44
			_fx.arc(previous - direction * 0.72, point + side * sin(_clock * 30 + int(bolt.id)), palette, int(bolt.id) + 19)
	_fx.frame(dt, low_motion, int(game.quality))


func _near_gate(from: Vector3, to: Vector3, reach: float) -> bool:
	return absf(from.y - to.y) < 3.2 and Vector2(from.x, from.z).distance_squared_to(Vector2(to.x, to.z)) <= reach * reach


func _line_clear(from: Vector3, to: Vector3) -> bool:
	return _ray(from, to, 1 | PHASE_LAYER).is_empty()


func _reaches_target(from: Vector3, to: Vector3, target: Node3D) -> bool:
	var hit := _ray(from, to, 1 | PHASE_LAYER)
	return hit.is_empty() or hit.get("collider") == target


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	if not from.is_finite() or not to.is_finite() or from.distance_squared_to(to) < 0.00001:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [game.runner.get_rid()])
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _segment_distance(point: Vector3, from: Vector3, to: Vector3) -> float:
	return point.distance_to(from.lerp(to, _projection(point, from, to)))


func _projection(point: Vector3, from: Vector3, to: Vector3) -> float:
	var line := to - from
	var size := line.length_squared()
	if size < 0.00001:
		return 0.0
	return clampf((point - from).dot(line) / size, 0.0, 1.0)


func clear_realm() -> void:
	_pending = ""
	_pending_target = -1
	_windup = 0.0
	if _phase_active:
		_restore_phase_mask()
	_phase_active = false
	_sync_phase_visual()
	_phase_time = 0.0
	_phase_extension = 0.0
	_slow_time = 0.0
	_tornado_time = 0.0
	_mirage_left = 0.0
	_mirage_location = Vector3.INF
	_mirage_path.clear()
	_mirage_pose.clear()
	_mirage_clips.clear()
	_mirage_frames.clear()
	_trace.clear()
	_trace_pose.clear()
	_trace_clips.clear()
	_trace_frames.clear()
	_trace_timer = 0.0
	bolts.clear()
	_fx.clear()


func reset() -> void:
	clear_realm()
	_targets.clear()
	pose_time = 0.0
	hero_pose = ""
	for id: String in cooldowns:
		cooldowns[id] = 0.0


func snapshot() -> Dictionary:
	return {
		"cooldowns": cooldowns.duplicate(), "bolts": bolts.duplicate(true), "bolt_id": _bolt_index,
		"pending": _pending, "windup": _windup, "pending_target": _pending_target,
		"phase_active": _phase_active, "phase_time": _phase_time, "phase_mask": _phase_mask,
		"phase_origin": _phase_origin, "phase_extension": _phase_extension,
		"slow": _slow_time, "tornado_pos": _tornado_pos, "tornado_time": _tornado_time,
		"tornado_pulse": _tornado_pulse, "pose": hero_pose, "pose_time": pose_time,
		"mirage_left": _mirage_left, "mirage_path": _mirage_path.duplicate() if _mirage_left > 0 else PackedVector3Array(),
		"mirage_pose": _mirage_pose.duplicate() if _mirage_left > 0 else PackedVector3Array(),
		"mirage_clips": _mirage_clips.duplicate() if _mirage_left > 0 else PackedStringArray(),
		"mirage_frames": _mirage_frames.duplicate() if _mirage_left > 0 else PackedFloat32Array(),
		"mirage_location": _mirage_location, "clock": _clock
	}


func restore(data: Dictionary) -> void:
	if data.is_empty():
		return
	cooldowns = data.cooldowns.duplicate()
	bolts.assign(data.bolts.duplicate(true))
	_bolt_index = int(data.bolt_id)
	_pending = String(data.pending)
	_windup = float(data.windup)
	_pending_target = int(data.pending_target)
	if _phase_active and not bool(data.phase_active):
		_restore_phase_mask()
	_phase_active = bool(data.phase_active)
	_phase_time = float(data.phase_time)
	_phase_mask = int(data.phase_mask)
	_phase_origin = Vector3(data.phase_origin)
	_phase_extension = float(data.phase_extension)
	if _phase_active:
		game.runner.collision_mask &= ~PHASE_LAYER
	_sync_phase_visual()
	_slow_time = float(data.slow)
	_tornado_pos = Vector3(data.tornado_pos)
	_tornado_time = float(data.tornado_time)
	_tornado_pulse = float(data.tornado_pulse)
	hero_pose = String(data.pose)
	pose_time = float(data.pose_time)
	_mirage_left = float(data.mirage_left)
	_mirage_path = data.mirage_path.duplicate()
	_mirage_pose = data.mirage_pose.duplicate()
	_mirage_clips = data.mirage_clips.duplicate()
	_mirage_frames = data.mirage_frames.duplicate()
	_mirage_location = Vector3(data.mirage_location)
	_clock = float(data.clock)
	_trace.clear()
	_trace_pose.clear()
	_trace_clips.clear()
	_trace_frames.clear()
	_trace_timer = 0.0
	_fx.clear()
