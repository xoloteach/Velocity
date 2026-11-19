extends Node3D
## Third-person melee, defensive timing and two independent speedster encounters.
##
## Only serializable combat data is captured. Rig, telegraph and collision nodes are reconstructed.

const RIG = preload("res://assets/velocity-runner.glb")
const NULLSTRIDE_RIG = preload("res://assets/nullstride-boss.glb")
const AFTERLIGHT_RIG = preload("res://assets/afterlight-boss.glb")
const CONTACT_SHADOW = preload("res://assets/contact_shadow.gdshader")
const WORLD_MASK := 1 | 4
const FOE_LAYER := 8
const EMPTY_TARGET := Vector3.INF
const DISTORTION_RADIUS := 4.25
const ARENA_RADIUS := 19.5
const GATE_SIZE := Vector3(4.6, 1.82, 3.45)
const ATTACKS := {
	"light": {"windup": 0.105, "active": 0.06, "recovery": 0.215, "cancel": 0.17, "range": 2.48, "damage": 11.5, "force": 2.45, "stun": 0.0, "pose": "Jab"},
	"heavy": {"windup": 0.27, "active": 0.085, "recovery": 0.367, "cancel": 0.17, "range": 2.88, "damage": 24.0, "force": 5.4, "stun": 0.42, "pose": "Heavy"},
	"counter": {"windup": 0.0, "active": 0.0, "recovery": 0.48, "cancel": 0.0, "range": 3.55, "damage": 28.0, "force": 3.8, "stun": 0.88, "pose": "Counter"},
	"takedown": {"windup": 0.22, "active": 0.07, "recovery": 0.58, "cancel": 0.12, "range": 2.78, "damage": 1000.0, "force": 1.55, "stun": 0.0, "pose": "Takedown"},
}
const META := &"velocity_combat_id"
const COLORS := {
	"guard": Color("#df7d5b"), "speedster": Color("#65e2ff"),
	"rival_dark": Color("#c17dff"), "rival_yellow": Color("#ffe5a0"),
}
const TITLES := {
	"guard": "Relay guard", "speedster": "Rift runner", "rival_dark": "Nullstride", "rival_yellow": "Afterlight",
}


class Fighter extends CharacterBody3D:
	var data: Dictionary
	var rig: Node3D
	var player: AnimationPlayer
	var collision: CollisionShape3D
	var track: MeshInstance3D
	var stripe: MeshInstance3D
	var glow: MeshInstance3D
	var counter_halo: MeshInstance3D
	var shadow: MeshInstance3D
	var echo: Node3D
	var gates: Array[StaticBody3D] = []
	var current_pose := ""


var game
var fighters: Dictionary = {}
var locked_id := ""
var hero_pose := ""
var hit_stop := 0.0
var hero_guard := 0.0
var pose_time := 0.0
var combo := 0
var combo_time := 0.0
var pending: Dictionary = {}
var queued := ""
var dodge_time := 0.0
var dodge_direction := Vector3.ZERO
var _enemy_motion_materials: Dictionary = {}
var _floor_ring: CylinderMesh
var _track_box: BoxMesh
var _halo_mesh: TorusMesh
var _shadow_mesh: PlaneMesh
var _shadow_mat: ShaderMaterial


func setup(root) -> void:
	game = root
	_track_box = BoxMesh.new()
	_track_box.size = Vector3.ONE
	_floor_ring = CylinderMesh.new()
	_floor_ring.height = 0.035
	_floor_ring.radial_segments = 28
	_halo_mesh = TorusMesh.new()
	_halo_mesh.inner_radius = 0.56
	_halo_mesh.outer_radius = 0.68
	_halo_mesh.rings = 24
	_halo_mesh.ring_segments = 6
	_shadow_mesh = PlaneMesh.new()
	_shadow_mesh.size = Vector2(1.0, 1.0)
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = CONTACT_SHADOW
	_shadow_mat.set_shader_parameter("opacity", 0.56)


func spawn(id: String, at: Vector3, archetype: String) -> CharacterBody3D:
	if fighters.has(id):
		return fighters[id]
	var kind := archetype if TITLES.has(archetype) else "guard"
	var boss := kind.begins_with("rival_")
	var max_hp := 147.0 if kind == "rival_dark" else (162.0 if kind == "rival_yellow" else (72.0 if kind == "speedster" else 46.0))
	var foe := Fighter.new()
	foe.name = StringName("Opponent_" + id.validate_node_name())
	foe.collision_layer = FOE_LAYER
	foe.collision_mask = WORLD_MASK | FOE_LAYER | 2
	foe.safe_margin = 0.015
	foe.floor_snap_length = 0.30
	foe.set_meta(META, id)
	foe.data = {
		"id": id, "realm": game.realm, "archetype": kind, "boss": boss, "hp": max_hp, "max_hp": max_hp,
		"phase": 1, "state": "approach", "clock": 0.58, "attack": "", "sequence": 0,
		"spawn": at, "aim": at, "dash_start": at, "side_from": at, "side_aim": at,
		"facing": 0.0, "connected": false, "echo_connected": false, "end_reason": "",
		"knock": Vector3.ZERO, "repeat": 0, "last_attack_taken": "", "guarded": false,
		"route": [], "route_index": 0, "temporally_exposed": false,
		"phase_ready": not boss, "phase_tell": 0.0, "last_repeat_reversed": false,
	}
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.78
	foe.collision = CollisionShape3D.new()
	foe.collision.shape = shape
	foe.collision.position.y = 0.89
	foe.add_child(foe.collision)
	var rig_scene: PackedScene = NULLSTRIDE_RIG if kind == "rival_dark" else (AFTERLIGHT_RIG if kind == "rival_yellow" else RIG)
	foe.rig = rig_scene.instantiate()
	foe.rig.name = &"RivalRig"
	if kind == "rival_dark":
		foe.rig.scale = Vector3(1.04, 1.04, 1.04)
	elif kind == "rival_yellow":
		foe.rig.scale = Vector3(1.02, 1.03, 1.02)
	foe.add_child(foe.rig)
	foe.player = foe.rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not boss:
		_apply_suit(foe.rig, kind)
		_attach_tactical_gear(foe.rig, kind)
	foe.shadow = MeshInstance3D.new()
	foe.shadow.mesh = _shadow_mesh
	foe.shadow.material_override = _shadow_mat
	var s_rad := 1.45 if boss else 1.15
	foe.shadow.scale = Vector3(s_rad, 1.0, s_rad)
	foe.shadow.position = Vector3(0.0, 0.026, 0.0)
	foe.shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foe.add_child(foe.shadow)
	add_child(foe)
	foe.global_position = at
	_make_telegraphs(foe)
	if kind == "rival_dark":
		_make_arena_gates(foe, at)
	fighters[id] = foe
	_play(foe, "Idle")
	return foe


func _attach_tactical_gear(rig: Node3D, kind: String) -> void:
	var accent := StandardMaterial3D.new()
	accent.albedo_color = COLORS[kind]
	accent.emission_enabled = true
	accent.emission = COLORS[kind]
	accent.emission_energy_multiplier = 1.15
	accent.roughness = 0.32
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color("#243240") if kind == "guard" else Color("#1c3c45")
	plate.roughness = 0.42
	plate.metallic = 0.55
	var gear := Node3D.new()
	gear.name = &"TacticalGear"
	rig.add_child(gear)
	if kind == "guard":
		for side in [-1.0, 1.0]:
			var pad := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.18, 0.14, 0.24)
			pad.mesh = b
			pad.material_override = plate
			pad.position = Vector3(side * 0.27, 1.42, 0.0)
			pad.rotation.z = side * -0.22
			gear.add_child(pad)
		var chest := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.32, 0.22, 0.06)
		chest.mesh = cb
		chest.material_override = plate
		chest.position = Vector3(0.0, 1.27, -0.15)
		gear.add_child(chest)
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.24, 0.035, 0.03)
		strip.mesh = sb
		strip.material_override = accent
		strip.position = Vector3(0.0, 1.32, -0.185)
		gear.add_child(strip)
	else:
		# Speedster aero crest & collar glow
		var crest := MeshInstance3D.new()
		var cr := BoxMesh.new()
		cr.size = Vector3(0.04, 0.12, 0.24)
		crest.mesh = cr
		crest.material_override = accent
		crest.position = Vector3(0.0, 1.76, 0.04)
		crest.rotation.x = 0.28
		gear.add_child(crest)


func _apply_suit(rig: Node3D, kind: String) -> void:
	var key := kind
	if not _enemy_motion_materials.has(key):
		_enemy_motion_materials[key] = {}
	var palette: Dictionary = _enemy_motion_materials[key]
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var model := node as MeshInstance3D
		if model.mesh == null:
			continue
		for i in model.mesh.get_surface_count():
			var base := model.mesh.surface_get_material(i) as StandardMaterial3D
			if base == null:
				continue
			var surface_key := str(base.get_instance_id())
			if not palette.has(surface_key):
				var tint := base.duplicate() as StandardMaterial3D
				match String(base.resource_name):
					"Crimson ceramic", "Oxblood fabric":
						match kind:
							"rival_dark":
								tint.albedo_color = Color("#27334e") if i % 2 == 0 else Color("#21233d")
							"rival_yellow":
								tint.albedo_color = Color("#bf7839") if i % 2 == 0 else Color("#5a422d")
							"speedster":
								tint.albedo_color = Color("#2c6268")
							_:
								tint.albedo_color = Color("#3a5062")
					"Amber conductor", "Rose alloy":
						tint.albedo_color = COLORS[kind]
						tint.emission_enabled = true
						tint.emission = COLORS[kind]
						tint.emission_energy_multiplier = 0.75
					"Smoked visor":
						tint.albedo_color = Color("#141728")
						tint.emission_enabled = true
						tint.emission = COLORS[kind]
						tint.emission_energy_multiplier = 0.18
				palette[surface_key] = tint
			model.set_surface_override_material(i, palette[surface_key])


func _make_telegraphs(foe: Fighter) -> void:
	var kind: String = foe.data.archetype
	var color: Color = COLORS[kind]
	foe.track = _marker(_track_box, color)
	foe.stripe = _marker(_track_box, color.darkened(0.22))
	foe.glow = _marker(_floor_ring, color)
	foe.counter_halo = _marker(_halo_mesh, Color("#fff3c4"))
	for marker in [foe.track, foe.stripe, foe.glow, foe.counter_halo]:
		foe.add_child(marker)
		marker.set_as_top_level(true)


func _marker(shape: Mesh, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.mesh = shape
	marker.visible = false
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.44)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.27
	marker.material_override = mat
	return marker


func _make_arena_gates(foe: Fighter, at: Vector3) -> void:
	for side in [-1.0, 1.0]:
		var gate := StaticBody3D.new()
		gate.collision_layer = 0
		gate.collision_mask = 0
		foe.add_child(gate)
		gate.set_as_top_level(true)
		gate.global_position = at + Vector3(side * 5.9, GATE_SIZE.y * 0.5, 2.7)
		var shape := BoxShape3D.new()
		shape.size = GATE_SIZE
		var collider := CollisionShape3D.new()
		collider.shape = shape
		gate.add_child(collider)
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		var visible_gate := _marker(mesh, Color("#512f68"))
		visible_gate.visible = true
		gate.add_child(visible_gate)
		var strip := _marker(_track_box, Color("#e1a7ff"))
		strip.position = Vector3(0.0, GATE_SIZE.y * 0.5, 0.0)
		strip.scale = Vector3(GATE_SIZE.x - 0.10, 0.045, GATE_SIZE.z - 0.10)
		strip.visible = true
		gate.add_child(strip)
		gate.visible = false
		foe.gates.append(gate)


func clear_encounter() -> void:
	for foe: Fighter in fighters.values():
		foe.collision_layer = 0
		foe.collision_mask = 0
		foe.visible = false
		for gate in foe.gates:
			gate.collision_layer = 0
		foe.queue_free()
	fighters.clear()
	locked_id = ""
	pending.clear()
	queued = ""
	combo = 0
	combo_time = 0.0
	pose_time = 0.0
	hero_pose = ""
	hit_stop = 0.0
	hero_guard = 0.0
	dodge_time = 0.0
	dodge_direction = Vector3.ZERO


func command(action: String) -> bool:
	if action == "interact":
		action = "takedown"
	if action == "lock":
		_cycle_lock()
		return true
	if action == "dodge":
		if dodge_time > 0.0 or game.health <= 0.0:
			return false
		pending.clear()
		queued = ""
		var move: Variant = game.get("control_axis")
		var camera_forward := Vector3.FORWARD.rotated(Vector3.UP, _view_heading())
		var chosen := _choose_target(6.0)
		if move is Vector2 and move.length_squared() > 0.06:
			dodge_direction = (camera_forward.cross(Vector3.UP) * move.x + camera_forward * move.y).normalized()
		elif chosen != null:
			var forward := _flat(chosen.global_position - game.runner.global_position).normalized()
			dodge_direction = forward.cross(Vector3.UP).normalized()
		else:
			dodge_direction = _flat(game.runner.velocity).normalized()
		if dodge_direction.length_squared() < 0.01:
			dodge_direction = Vector3.RIGHT.rotated(Vector3.UP, game.hero_heading)
		dodge_time = 0.31
		hero_guard = 0.28
		pose_time = 0.34
		hero_pose = "Dodge"
		game.event("dodge", {})
		return true
	if not ATTACKS.has(action) or game.health <= 0.0:
		return false
	if action == "counter":
		return _counter()
	if dodge_time > 0.1:
		return false
	if not pending.is_empty():
		# Keep one input in the late recovery window. Long button repeat cannot spawn extra attacks.
		var current: Dictionary = ATTACKS[pending.action]
		if float(pending.remaining) <= float(current.cancel) and bool(pending.resolved):
			queued = action
			return true
		return false
	var spec: Dictionary = ATTACKS[action]
	var target := _choose_target(float(spec.range) + 0.45)
	if action == "takedown":
		if target == null or not _can_finish(target):
			return false
		hero_guard = 0.34
		target.data.state = "stagger"
		target.data.clock = maxf(float(target.data.clock), float(spec.windup) + 0.12)
	hero_pose = String(spec.pose)
	pose_time = float(spec.windup) + float(spec.active) + float(spec.recovery)
	var target_id := "" if target == null else String(target.data.id)
	pending = {"action": action, "id": target_id, "remaining": pose_time, "resolved": false}
	return true


func _counter() -> bool:
	if hero_pose == "Counter" and pose_time > 0.10:
		return false
	var foe := _incoming_counter()
	if foe == null:
		hero_pose = "Counter"
		pose_time = 0.22
		game.announce("Counter on the final beat.")
		return false
	pending.clear()
	queued = ""
	var spec: Dictionary = ATTACKS.counter
	hero_pose = spec.pose
	pose_time = spec.recovery
	hero_guard = 0.33
	var position: Vector3 = game.runner.global_position
	game.hero_heading = _heading(position, foe.global_position)
	_apply_damage(foe, spec.damage, position, "counter", spec.force)
	game.event("counter", {"id": foe.data.id, "archetype": foe.data.archetype, "phase": foe.data.phase})
	return true


func _incoming_counter() -> Fighter:
	var nearest: Fighter
	var distance: float = ATTACKS.counter.range
	var origin: Vector3 = game.runner.global_position
	for foe in _eligible_fighters():
		if String(foe.data.state) != "telegraph":
			continue
		var remaining: float = foe.data.clock
		if remaining > _counter_window(foe) or remaining <= 0.0:
			continue
		if not _in_reach(foe, origin, distance):
			continue
		nearest = foe
		distance = _flat(foe.global_position - origin).length()
	return nearest


func _counter_window(foe: Fighter) -> float:
	return 0.34 if foe.data.boss else 0.29


func invulnerable() -> bool:
	return hero_guard > 0.0


func dodge_velocity() -> Vector3:
	if dodge_time <= 0.0:
		return Vector3.ZERO
	return dodge_direction * (4.0 + dodge_time * 29.0)


func movement_factor() -> float:
	var hero: Vector3 = game.runner.global_position
	for foe in _eligible_fighters():
		if foe.data.archetype != "rival_dark" or foe.data.attack != "cross":
			continue
		if foe.data.state != "attack" and (foe.data.state != "telegraph" or float(foe.data.clock) > 0.62):
			continue
		var center: Vector3 = foe.data.aim
		if absf(hero.y - center.y) < 1.40 and _flat(hero - center).length_squared() < DISTORTION_RADIUS * DISTORTION_RADIUS:
			return 0.68
	return 1.0


func timeline_reversed() -> void:
	for foe in _eligible_fighters():
		if foe.data.archetype != "rival_yellow" or foe.data.phase != 3 or foe.data.last_repeat_reversed:
			continue
		if _flat(foe.global_position - game.runner.global_position).length_squared() > ARENA_RADIUS * ARENA_RADIUS:
			continue
		foe.data.last_repeat_reversed = true
		_expose_rival(foe, "rewind")
		if foe.data.attack == "feedback" and foe.data.state in ["telegraph", "attack"]:
			foe.data.state = "stagger"
			foe.data.clock = 1.0


func hand_busy() -> bool:
	return not pending.is_empty() and not bool(pending.get("resolved", false))


func step(dt: float) -> void:
	if game == null or game.paused:
		return
	hero_guard = maxf(0.0, hero_guard - dt)
	dodge_time = maxf(0.0, dodge_time - dt)
	pose_time = maxf(0.0, pose_time - dt)
	combo_time = maxf(0.0, combo_time - dt)
	hit_stop = maxf(0.0, hit_stop - dt)
	if pose_time <= 0.0:
		hero_pose = ""
	if combo_time <= 0.0:
		combo = 0
	if game.health <= 0.0:
		return
	_update_hero_attack(dt)
	var camera_beat: Variant = game.get("_cinema_timer")
	var slow := 1.0
	if game.powers != null and game.powers.has_method("slow_factor"):
		slow = clampf(game.powers.slow_factor(), 0.14, 1.0)
	for foe: Fighter in fighters.values():
		if not is_instance_valid(foe) or foe.is_queued_for_deletion():
			continue
		var local := String(foe.data.realm) == String(game.realm)
		foe.visible = local
		foe.collision_layer = FOE_LAYER if local and not _inactive(foe) else 0
		if not local:
			_update_gates(foe, false)
			continue
		if foe.player != null:
			foe.player.speed_scale = 0.14 if hit_stop > 0.0 else slow
		if hit_stop > 0.0 or (camera_beat is float and camera_beat > 0.0 and foe.data.state != "finish"):
			continue
		if not foe.data.boss and _flat(foe.global_position - game.runner.global_position).length_squared() > 8100.0:
			continue
		_step_foe(foe, dt * slow)
		_update_visuals(foe)


func _update_hero_attack(dt: float) -> void:
	if pending.is_empty():
		return
	var before: float = pending.remaining
	pending.remaining = before - dt
	var action: String = pending.action
	var spec: Dictionary = ATTACKS[action]
	var active_end: float = spec.recovery
	var active_start := active_end + float(spec.active)
	if not bool(pending.resolved) and before >= active_end and float(pending.remaining) <= active_start:
		var origin: Vector3 = game.runner.global_position
		var foe: Fighter = fighters.get(String(pending.id))
		if action != "takedown" and (not is_instance_valid(foe) or _inactive(foe) or not _in_reach(foe, origin, float(spec.range))):
			foe = _choose_target(float(spec.range))
		if is_instance_valid(foe) and not _inactive(foe) and foe.data.realm == game.realm and _in_reach(foe, origin, float(spec.range)) and (action != "takedown" or _can_finish(foe)):
			pending.resolved = true
			game.hero_heading = _heading(origin, foe.global_position)
			var heavy := action == "heavy"
			var combo_amount := 0.0
			if action == "light" and combo_time > 0.0:
				combo_amount = minf(combo, 4) * 2.7
			if _apply_damage(foe, float(spec.damage) + combo_amount, origin, action, float(spec.force)):
				combo += 1
				combo_time = 1.35 if not heavy else 0.75
				game.event("melee_hit", {"id": foe.data.id, "action": action, "combo": combo})
				if action == "takedown":
					game.event("takedown", {"id": foe.data.id})
		elif float(pending.remaining) <= active_end:
			pending.resolved = true
			game.pulse("miss", origin + Vector3.UP * 0.9, 0.35)
	if float(pending.remaining) <= 0.0:
		pending.clear()
		if not queued.is_empty():
			var next_action := queued
			queued = ""
			command(next_action)


func _step_foe(foe: Fighter, dt: float) -> void:
	var state: String = foe.data.state
	if state == "down":
		return
	foe.data.clock = float(foe.data.clock) - dt
	if state == "finish":
		if float(foe.data.clock) <= 0.0:
			_emit_defeat(foe, String(foe.data.end_reason))
		return
	var hero: Vector3 = game.runner.global_position
	var target := hero
	# Mirage changes what the enemy sees, while hit resolution always uses the real hero.
	if game.powers != null and game.powers.has_method("decoy_position"):
		var decoy: Vector3 = game.powers.decoy_position(foe.global_position, 13.0)
		if decoy.is_finite() and (state == "approach" or state == "patrol"):
			target = decoy
	var difference := _flat(target - foe.global_position)
	var distance := difference.length()
	var direction := difference.normalized()
	var knock: Vector3 = foe.data.knock
	if knock.length_squared() > 0.01:
		foe.move_and_collide(knock * dt)
		foe.data.knock = knock * exp(-dt * 7.4)
	if state != "attack" and state != "telegraph" and distance > 0.08:
		foe.data.facing = _heading(foe.global_position, target)
	if state not in ["attack", "approach", "patrol", "dodge"]:
		foe.velocity.x = 0.0
		foe.velocity.z = 0.0
	if state == "telegraph":
		if not foe.data.phase_ready:
			foe.data.phase_tell = float(foe.data.phase_tell) - dt
			foe.data.phase_ready = float(foe.data.phase_tell) <= 0.0
		if float(foe.data.clock) <= 0.0:
			_release_attack(foe)
		return
	if state == "attack":
		_drive_attack(foe, dt)
		return
	if state in ["recover", "stagger", "guard", "dodge", "shift"]:
		if state == "dodge" and distance > 0.1:
			_move_fighter(foe, direction.cross(Vector3.UP) * 4.2, dt)
		if float(foe.data.clock) > 0.0:
			return
		foe.data.state = "approach"
		foe.data.clock = 0.29
		foe.data.guarded = false
		return
	var inside: bool = distance < 38.0 and (not foe.data.boss or _inside_arena(foe, target))
	if inside and distance <= _attack_distance(foe) and float(foe.data.clock) <= 0.0 and _can_pressure(foe) and _line_clear(foe.global_position, target):
		_begin_attack(foe, target)
		return
	if distance > 1.72 and inside:
		var approach_speed := 4.1 if foe.data.archetype == "guard" else (5.55 if foe.data.archetype == "rival_dark" else 6.8)
		if distance < 2.45:
			approach_speed *= 0.47
		_move_fighter(foe, direction * approach_speed, dt)
	elif not inside:
		var origin: Vector3 = foe.data.spawn
		var return_vector := _flat(origin - foe.global_position)
		foe.data.state = "patrol"
		if return_vector.length_squared() > 1.5:
			_move_fighter(foe, return_vector.normalized() * 2.5, dt)


func _inside_arena(foe: Fighter, at: Vector3) -> bool:
	return _flat(at - Vector3(foe.data.spawn)).length_squared() < ARENA_RADIUS * ARENA_RADIUS


func _move_fighter(foe: Fighter, speed: Vector3, dt: float) -> void:
	if dt <= 0.0:
		return
	foe.velocity.x = speed.x
	foe.velocity.z = speed.z
	foe.velocity.y = maxf(-15.0, foe.velocity.y - dt * 24.0)
	# move_and_collide uses the explicit step here, including any local slow-time scale.
	var hit := foe.move_and_collide(foe.velocity * dt)
	if hit != null:
		var normal := hit.get_normal()
		if normal.y > 0.62:
			foe.velocity.y = 0.0
			foe.move_and_collide(_flat(hit.get_remainder()))
		elif absf(normal.y) < 0.6:
			var remainder := hit.get_remainder().slide(normal)
			if remainder.length_squared() > 0.000001:
				foe.move_and_collide(remainder)


func _attack_distance(foe: Fighter) -> float:
	if foe.data.archetype == "guard":
		return 2.7
	if foe.data.archetype == "speedster":
		return 6.0
	if foe.data.archetype == "rival_yellow" and foe.data.phase == 1:
		return 9.4
	return 11.0 if foe.data.archetype == "rival_dark" else 14.5


func _can_pressure(foe: Fighter) -> bool:
	for other in _eligible_fighters():
		if other == foe:
			continue
		if other.data.state in ["telegraph", "attack"]:
			return false
	return true


func _begin_attack(foe: Fighter, target: Vector3) -> void:
	var phase: int = foe.data.phase
	var cycle: int = foe.data.sequence
	var kind: String = foe.data.archetype
	var move := "strike"
	var duration := 0.64
	match kind:
		"speedster":
			move = "needle" if cycle % 3 == 2 else "rush"
			duration = 0.73
		"rival_dark":
			if phase == 1:
				move = "rush"
				duration = 0.81
			elif phase == 2:
				move = "cross" if cycle % 3 != 2 else "needle"
				duration = 0.94
			else:
				move = "singularity" if cycle % 2 == 0 else "needle"
				duration = 1.0 if move == "singularity" else 0.83
		"rival_yellow":
			if phase == 1:
				move = "feint"
				duration = 0.88
			elif phase == 2:
				move = "relay"
				duration = 0.88
			else:
				move = "feedback"
				duration = 1.04
	foe.data.state = "telegraph"
	foe.data.attack = move
	foe.data.phase_tell = 0.25
	foe.data.clock = duration
	foe.data.sequence = cycle + 1
	foe.data.aim = _same_height(target, foe.global_position)
	foe.data.dash_start = foe.global_position
	foe.data.facing = _heading(foe.global_position, target)
	foe.data.connected = false
	foe.data.echo_connected = false
	var cross := _flat(target - foe.global_position).normalized().cross(Vector3.UP)
	if cross.length_squared() < 0.01:
		cross = Vector3.RIGHT
	var multiplier := 1.0 if cycle % 2 == 0 else -1.0
	foe.data.side_from = foe.global_position + cross * 3.0 * multiplier
	foe.data.side_aim = _same_height(target, foe.global_position) - cross * 2.6 * multiplier
	foe.data.route = []
	foe.data.route_index = 0
	if move == "relay":
		var middle := _same_height(target, foe.global_position)
		var center: Vector3 = foe.data.spawn
		var first := middle + cross * 3.0 * multiplier
		var last := middle - cross * 2.3 * multiplier
		foe.data.route = [center + (first - center).limit_length(ARENA_RADIUS), middle, center + (last - center).limit_length(ARENA_RADIUS)]
	if move in ["feint", "cross", "feedback"]:
		_ensure_echo(foe)
	game.event("enemy_telegraph", {"id": foe.data.id, "attack": move, "phase": phase, "time": duration})


func _release_attack(foe: Fighter) -> void:
	foe.data.state = "attack"
	var attack: String = foe.data.attack
	match attack:
		"needle":
			_fire(foe, 13.5)
			foe.data.clock = 0.25
		"singularity":
			_fire(foe, 18.0)
			foe.data.clock = 0.54
			game.pulse("tornado", foe.global_position, 1.0)
		"feedback":
			_fire(foe, 15.0)
			foe.data.clock = 0.70
		"relay":
			foe.data.clock = 0.68
		"cross":
			foe.data.clock = 0.50
		"feint":
			foe.data.clock = 0.39
		"rush":
			foe.data.clock = 0.42
		_:
			foe.data.clock = 0.26
	game.pulse("shockwave" if attack == "singularity" else "rush", foe.global_position, 0.60)


func _fire(foe: Fighter, amount: float) -> void:
	if game.powers == null or not game.powers.has_method("spawn_hostile"):
		return
	var aim: Vector3 = foe.data.aim
	var from := foe.global_position + Vector3.UP * 1.11
	var velocity := (aim + Vector3.UP * 0.87 - from).normalized() * 18.4
	if velocity.length_squared() > 0.01:
		game.powers.spawn_hostile(from, velocity, amount)


func _drive_attack(foe: Fighter, dt: float) -> void:
	var move: String = foe.data.attack
	var old_position := foe.global_position
	var target: Vector3 = foe.data.aim
	var moving := move in ["rush", "cross", "feint", "relay", "feedback", "strike"]
	if move == "relay":
		var route: Array = foe.data.route
		var index: int = foe.data.route_index
		if index < route.size() and _flat(route[index] - old_position).length_squared() < 0.6:
			index += 1
			foe.data.route_index = index
		if index < route.size():
			target = route[index]
		else:
			moving = false
	if moving:
		var as_run := _flat(target - old_position)
		var max_speed := 28.5 if move in ["relay", "feedback", "cross"] else (10.3 if move == "strike" else 24.5)
		if as_run.length() > 0.13:
			_move_fighter(foe, as_run.normalized() * minf(max_speed, as_run.length() / maxf(dt, 0.001)), dt)
	if move == "singularity" and float(foe.data.clock) < 0.22:
		_try_enemy_hit(foe, foe.global_position, foe.global_position, 4.25, 23.0, false)
	elif moving:
		var damage := 10.0 if foe.data.archetype == "guard" else (18.0 + 2.0 * float(foe.data.phase) if foe.data.boss else 13.0)
		var hit_radius := 1.53 if move == "strike" else 1.34
		var travel_end := foe.global_position
		if old_position.is_equal_approx(travel_end):
			travel_end += _flat(target - old_position).normalized() * 0.65
		_try_enemy_hit(foe, old_position, travel_end, hit_radius, damage, false)
	if move in ["cross", "feedback"] and float(foe.data.clock) < 0.31:
		var echo_start: Vector3 = foe.data.side_from
		var echo_end: Vector3 = foe.data.side_aim
		var t := clampf(1.0 - float(foe.data.clock) / 0.31, 0.0, 1.0)
		var echo_before := echo_start.lerp(echo_end, maxf(0.0, t - dt * 3.5))
		var echo_after := echo_start.lerp(echo_end, t)
		if _line_clear(echo_start, echo_after):
			_try_enemy_hit(foe, echo_before, echo_after, 1.10, 12.0, true)
	if float(foe.data.clock) <= 0.0:
		foe.data.state = "recover"
		foe.data.clock = 0.90 if foe.data.boss else 0.72


func _try_enemy_hit(foe: Fighter, from: Vector3, to: Vector3, reach: float, amount: float, echo: bool) -> void:
	var hit_key := "echo_connected" if echo else "connected"
	if bool(foe.data[hit_key]):
		return
	var hero: Vector3 = game.runner.global_position
	if hero.y - foe.global_position.y > 1.16 or foe.global_position.y - hero.y > 2.5:
		return
	var nearest := _flat(from)
	if not from.is_equal_approx(to):
		nearest = Geometry3D.get_closest_point_to_segment(_flat(hero), nearest, _flat(to))
	if _flat(hero).distance_squared_to(nearest) > reach * reach:
		return
	if not _line_clear(Vector3(nearest.x, from.y, nearest.z), hero):
		return
	foe.data[hit_key] = true
	if invulnerable():
		game.event("evaded", {"id": foe.data.id, "attack": foe.data.attack})
		return
	if game.powers != null and game.powers.has_method("phased") and game.powers.phased():
		return
	game.damage(amount)


func strike_target(target: Variant, amount: float, source: Vector3 = Vector3.ZERO, kind: String = "power", force: float = 0.0) -> bool:
	var id := ""
	if target is String or target is StringName:
		id = String(target)
	elif target is Node and target.has_meta(META):
		id = String(target.get_meta(META))
	var foe: Fighter = fighters.get(id)
	if not is_instance_valid(foe) or _inactive(foe) or foe.data.realm != game.realm:
		return false
	return _apply_damage(foe, amount, source, kind, force)


func damage_near(at: Vector3, radius: float, amount: float, force: float = 0.0, kind: String = "shockwave") -> int:
	if radius <= 0.0 or amount <= 0.0 and force <= 0.0:
		return 0
	var hits := 0
	for foe in _eligible_fighters():
		var contact := foe.global_position + Vector3.UP * 0.8
		if contact.distance_squared_to(at) > radius * radius or not _line_clear(at, foe.global_position):
			continue
		if amount <= 0.0:
			foe.data.knock = _flat(foe.global_position - at).normalized() * force
			hits += 1
		elif _apply_damage(foe, amount, at, kind, force):
			hits += 1
	return hits


func _apply_damage(foe: Fighter, amount: float, source: Vector3, kind: String, force: float) -> bool:
	if amount <= 0.0 or not is_finite(amount) or _inactive(foe):
		return false
	var state: String = foe.data.state
	var boss: bool = foe.data.boss
	if state == "shift":
		game.pulse("block", foe.global_position + Vector3.UP * 0.88, 0.38)
		return false
	var phase_break := false
	var power_cut := kind in ["counter", "redirect", "shockwave", "rewind", "reflected", "redirected"]
	var redirect_or_counter := kind in ["counter", "redirect", "reflected", "redirected"]
	if foe.data.guarded and (kind in ["heavy", "takedown"] or power_cut):
		foe.data.guarded = false
	if kind == foe.data.last_attack_taken:
		foe.data.repeat = int(foe.data.repeat) + 1
	else:
		foe.data.repeat = 1
		foe.data.last_attack_taken = kind
	var repeats: int = foe.data.repeat
	var is_open := state in ["stagger", "recover"]
	if repeats >= (3 if boss else 4) and not is_open and kind == "light":
		foe.data.guarded = true
		if state in ["approach", "patrol"]:
			foe.data.state = "guard" if foe.data.archetype != "rival_yellow" else "dodge"
			foe.data.clock = 0.36
		amount *= 0.40
	elif boss and foe.data.phase >= 2 and (kind not in ATTACKS) and repeats >= 4 and not is_open and not power_cut:
		amount *= 0.49
	if boss and foe.data.phase == 3:
		if foe.data.archetype == "rival_yellow":
			if power_cut:
				_expose_rival(foe, kind)
			elif not foe.data.temporally_exposed and not is_open:
				amount *= 0.52
		elif redirect_or_counter:
			_expose_rival(foe, kind)
	if boss and not is_open and kind == "light":
		amount *= 0.78
	var hp: float = foe.data.hp
	var maximum: float = foe.data.max_hp
	# Expose each phase's telegraph before allowing the fighter's next threshold to break.
	if boss:
		var phase: int = foe.data.phase
		var threshold := maximum * (0.66 if phase == 1 else (0.33 if phase == 2 else 0.0))
		var minimum := threshold if foe.data.phase_ready else threshold + 1.0
		if phase == 3 and not foe.data.temporally_exposed:
			minimum = maximum * (0.19 if foe.data.archetype == "rival_dark" else 0.15)
		if hp - amount <= minimum:
			amount = maxf(0.0, hp - minimum)
			phase_break = phase < 3 and bool(foe.data.phase_ready)
			if amount <= 0.0:
				game.pulse("block", foe.global_position + Vector3.UP * 0.88, 0.38)
				return false
	foe.data.hp = maxf(0.0, hp - amount)
	var reaction: bool = (kind in ["counter", "heavy", "takedown"] or power_cut) and not foe.data.guarded
	if boss and not foe.data.phase_ready and kind != "counter":
		reaction = false
	var proposed := _flat(foe.global_position - source).normalized()
	foe.data.knock = proposed * clampf(force, 0.0, 21.0) * (0.37 if boss else 1.0)
	var feedback := "counter" if kind == "counter" else ("block" if foe.data.guarded else "hit")
	game.pulse(feedback, foe.global_position + Vector3.UP * 0.88, clampf(amount / 18.0, 0.25, 1.25))
	hit_stop = 0.065 if kind in ["heavy", "counter", "takedown"] else 0.035
	if phase_break:
		_change_phase(foe)
	elif float(foe.data.hp) <= 0.0:
		if boss:
			foe.data.state = "finish"
			foe.data.clock = 0.85
			foe.data.end_reason = kind
			foe.collision_layer = 0
			hero_guard = maxf(hero_guard, 0.54)
			hero_pose = "Counter" if foe.data.archetype == "rival_yellow" or kind == "counter" else "Heavy"
			pose_time = maxf(pose_time, 0.52)
			game.pulse("boss", foe.global_position, 1.08)
		else:
			_emit_defeat(foe, kind)
	elif reaction:
		foe.data.state = "stagger"
		var stun: float = ATTACKS.get(kind, ATTACKS.heavy).stun
		foe.data.clock = minf(stun, 0.26) if boss and kind != "counter" else stun
		foe.data.guarded = false
	return true


func _expose_rival(foe: Fighter, method: String) -> void:
	if foe.data.temporally_exposed:
		return
	foe.data.temporally_exposed = true
	var title: String = TITLES[foe.data.archetype]
	game.announce("%s · defense broken" % title, 2.2)
	game.pulse("counter", foe.global_position + Vector3.UP * 0.82, 0.8)
	game.event("boss_exposed", {"id": foe.data.id, "archetype": foe.data.archetype, "phase": foe.data.phase, "method": method})


func _change_phase(foe: Fighter) -> void:
	foe.data.phase = int(foe.data.phase) + 1
	foe.data.state = "shift"
	foe.data.clock = 1.10
	foe.data.attack = ""
	foe.data.route = []
	foe.data.connected = false
	foe.data.echo_connected = false
	foe.data.guarded = false
	foe.data.repeat = 0
	foe.data.sequence = 0
	foe.data.phase_ready = false
	foe.data.phase_tell = 0.0
	foe.data.temporally_exposed = false
	foe.data.last_repeat_reversed = false
	var title: String = TITLES[foe.data.archetype]
	var hint := "Displaced lanes. Escape the drag field."
	if foe.data.archetype == "rival_yellow":
		hint = "Break the relay line." if foe.data.phase == 2 else "Interrupt the repeating trace."
	elif foe.data.phase == 3:
		hint = "Arena closing. Redirect the pulse or counter."
	game.announce("%s · phase %s · %s" % [title, foe.data.phase, hint], 3.6)
	game.pulse("boss", foe.global_position, 1.0)
	game.event("boss_phase", {"id": foe.data.id, "archetype": foe.data.archetype, "phase": foe.data.phase})


func _emit_defeat(foe: Fighter, kind: String) -> void:
	if foe.data.state == "down":
		return
	foe.data.state = "down"
	foe.data.clock = 0.0
	foe.data.attack = ""
	foe.collision_layer = 0
	foe.velocity = Vector3.ZERO
	foe.data.knock = Vector3.ZERO
	_update_gates(foe, false)
	game.event("enemy_down", {"id": foe.data.id, "archetype": foe.data.archetype, "phase": foe.data.phase, "method": kind})


func _can_finish(foe: Fighter) -> bool:
	return not foe.data.boss and (foe.data.state == "stagger" or float(foe.data.hp) <= float(foe.data.max_hp) * 0.35)


func _inactive(foe: Fighter) -> bool:
	return foe.data.state in ["down", "finish"] or float(foe.data.hp) <= 0.0


func _eligible_fighters() -> Array[Fighter]:
	var result: Array[Fighter] = []
	for foe: Fighter in fighters.values():
		if is_instance_valid(foe) and not foe.is_queued_for_deletion() and not _inactive(foe) and foe.data.realm == game.realm:
			result.append(foe)
	return result


func _cycle_lock() -> void:
	var hero: Vector3 = game.runner.global_position
	var ids: Array[String] = []
	for foe in _eligible_fighters():
		if _flat(foe.global_position - hero).length_squared() < 625.0 and _line_clear(hero, foe.global_position):
			ids.append(String(foe.data.id))
	if ids.is_empty():
		locked_id = ""
		return
	var current := ids.find(locked_id)
	if current == ids.size() - 1:
		locked_id = ""
	else:
		locked_id = ids[current + 1]


func _choose_target(max_dist: float) -> Fighter:
	var hero: Vector3 = game.runner.global_position
	var locked: Fighter = fighters.get(locked_id)
	if is_instance_valid(locked) and not _inactive(locked) and locked.data.realm == game.realm and _in_reach(locked, hero, max_dist):
		return locked
	var best: Fighter
	var best_score := max_dist + 1.0
	var front := Vector3.FORWARD.rotated(Vector3.UP, game.hero_heading)
	var view := Vector3.FORWARD.rotated(Vector3.UP, _view_heading())
	for foe in _eligible_fighters():
		if not _in_reach(foe, hero, max_dist):
			continue
		var offset := _flat(foe.global_position - hero)
		var direction := offset.normalized()
		var facing := front.dot(direction)
		var visible_angle := view.dot(direction)
		if maxf(facing, visible_angle) < -0.38:
			continue
		var rank := offset.length() + (1.0 - facing) * 0.38 + (1.0 - visible_angle) * 0.49
		if rank < best_score:
			best = foe
			best_score = rank
	return best


func _view_heading() -> float:
	var orbit: Variant = game.get("orbit")
	return orbit.x if orbit is Vector2 else game.hero_heading


func target_position(max_distance: float = 30.0) -> Vector3:
	var foe := _choose_target(max_distance)
	return EMPTY_TARGET if foe == null else foe.global_position + Vector3.UP * 0.93


func target_center(id: String) -> Vector3:
	var foe: Fighter = fighters.get(id)
	if not is_instance_valid(foe) or foe.is_queued_for_deletion() or _inactive(foe) or foe.data.realm != game.realm:
		return EMPTY_TARGET
	return foe.global_position + Vector3.UP * 0.93


func ray_target(from: Vector3, to: Vector3, margin: float = 0.6) -> String:
	if from.distance_squared_to(to) < 0.000001:
		return ""
	var nearest := ""
	var nearest_t := INF
	for foe in _eligible_fighters():
		var center := foe.global_position + Vector3.UP * 0.93
		var contact := Geometry3D.get_closest_point_to_segment(center, from, to)
		if contact.distance_squared_to(center) > margin * margin:
			continue
		var t := from.distance_squared_to(contact)
		if t < nearest_t and _line_clear(from - Vector3.UP * 0.86, foe.global_position):
			nearest_t = t
			nearest = foe.data.id
	return nearest


func _in_reach(foe: Fighter, origin: Vector3, reach: float) -> bool:
	var where := foe.global_position
	if absf(origin.y - where.y) > 1.55 or _flat(origin).distance_squared_to(_flat(where)) > reach * reach:
		return false
	return _line_clear(origin, where)


func _line_clear(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.000001 or not is_inside_tree() or get_world_3d() == null:
		return true
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.86, to + Vector3.UP * 0.90, WORLD_MASK)
	return space.intersect_ray(query).is_empty()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _same_height(at: Vector3, height: Vector3) -> Vector3:
	return Vector3(at.x, height.y, at.z)


func _heading(from: Vector3, to: Vector3) -> float:
	var direction := to - from
	return atan2(-direction.x, -direction.z)


func _ensure_echo(foe: Fighter) -> void:
	if foe.echo != null:
		return
	var kind: String = foe.data.archetype
	var echo_scene: PackedScene = NULLSTRIDE_RIG if kind == "rival_dark" else (AFTERLIGHT_RIG if kind == "rival_yellow" else RIG)
	foe.echo = echo_scene.instantiate()
	foe.echo.name = &"DisplacedTrace"
	foe.add_child(foe.echo)
	foe.echo.set_as_top_level(true)
	var hue: Color = COLORS[kind]
	var ghost := StandardMaterial3D.new()
	ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ghost.albedo_color = Color(hue, 0.34)
	for node in foe.echo.find_children("*", "MeshInstance3D", true, false):
		node.material_override = ghost
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var anim := foe.echo.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null and anim.has_animation("Sprint"):
		anim.get_animation("Sprint").loop_mode = Animation.LOOP_LINEAR
		anim.play("Sprint")


func _update_gates(foe: Fighter, enabled: bool) -> void:
	for gate in foe.gates:
		# Don't materialize collision on top of a runner when the arena narrows.
		var offset: Vector3 = game.runner.global_position - gate.global_position
		var safe := absf(offset.x) > GATE_SIZE.x * 0.5 + 0.4 or absf(offset.z) > GATE_SIZE.z * 0.5 + 0.4
		var active := enabled and (gate.collision_layer == 4 or safe)
		gate.visible = active
		gate.collision_layer = 4 if active else 0


func _update_visuals(foe: Fighter) -> void:
	var state: String = foe.data.state
	var move: String = foe.data.attack
	var moving := _flat(foe.velocity).length() > 0.36
	foe.rig.rotation.y = lerp_angle(foe.rig.rotation.y, float(foe.data.facing), 0.19)
	foe.rig.rotation.z = lerpf(foe.rig.rotation.z, PI * 0.5 if state == "down" else (0.27 if state == "finish" else 0.0), 0.21)
	foe.rig.position.y = lerpf(foe.rig.position.y, 0.2 if state == "down" else 0.0, 0.2)
	match state:
		"stagger", "finish", "down":
			_play(foe, "Hit")
		"telegraph", "shift", "guard":
			_play(foe, "Brake")
		"dodge":
			_play(foe, "Dodge")
		"attack":
			var key := "Jab" if move == "strike" else ("Heavy" if move in ["needle", "singularity"] else "Boost")
			_play(foe, key)
		_:
			_play(foe, "Jog" if moving and state in ["approach", "patrol"] else "Idle")
	var showing := state == "telegraph" or (state == "attack" and move in ["cross", "feedback"])
	var countdown: float = foe.data.clock
	var hue: Color = COLORS[foe.data.archetype]
	var can_counter := state == "telegraph" and countdown <= _counter_window(foe)
	var sim_v: Variant = game.get("sim_time") if game != null else null
	var t_now: float = float(sim_v) if sim_v != null else float(Time.get_ticks_msec()) * 0.001
	var pulse_val := 0.85 + 0.15 * sin(t_now * 22.0)
	if can_counter:
		hue = Color("#fff3cf")
	foe.track.visible = showing and move not in ["strike", "singularity"]
	foe.stripe.visible = showing and move in ["cross", "relay"]
	foe.glow.visible = showing
	if is_instance_valid(foe.counter_halo):
		foe.counter_halo.visible = can_counter
		if can_counter:
			foe.counter_halo.global_position = foe.global_position + Vector3.UP * 2.15
			var s := 0.85 + 0.35 * sin(t_now * 26.0)
			foe.counter_halo.scale = Vector3(s, 1.0, s)
			(foe.counter_halo.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.94, 0.72, 0.82)
	if showing:
		var aim: Vector3 = foe.data.aim
		var origin: Vector3 = foe.data.dash_start
		var width := 0.28 if move == "needle" else (1.20 if move == "feedback" else 0.84)
		if foe.track.visible:
			_point_marker(foe.track, origin, aim, width, hue, (0.82 if can_counter else 0.48) * pulse_val)
		if foe.stripe.visible:
			var side_from: Vector3 = foe.data.side_from
			var side_aim: Vector3 = foe.data.side_aim
			if move == "relay":
				side_from = aim
				side_aim = foe.data.route[0]
			_point_marker(foe.stripe, side_from, side_aim, 0.48, hue, 0.36 * pulse_val)
		foe.glow.global_position = (origin if move == "singularity" else aim) + Vector3.UP * 0.027
		var radius := DISTORTION_RADIUS if move in ["cross", "singularity"] else (0.92 if move in ["feedback", "feint"] else 0.52)
		foe.glow.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
		var circle_mat := foe.glow.material_override as StandardMaterial3D
		circle_mat.albedo_color = Color(hue, ((0.36 if can_counter else 0.22) if move == "cross" else (0.66 if can_counter else 0.36)) * pulse_val)
	if foe.echo != null:
		foe.echo.visible = showing and move in ["feint", "cross", "feedback"]
		if foe.echo.visible:
			var side_from: Vector3 = foe.data.side_from
			var side_aim: Vector3 = foe.data.side_aim
			var blend := clampf(0.85 - countdown * 0.78, 0.14, 0.78) if state == "telegraph" else clampf(1.0 - countdown / 0.31, 0.0, 1.0)
			foe.echo.global_position = side_from.lerp(side_aim, blend)
			foe.echo.rotation.y = _heading(side_from, side_aim)
	_update_gates(foe, foe.visible and foe.data.phase >= 3 and not _inactive(foe))


func _point_marker(marker: MeshInstance3D, from: Vector3, to: Vector3, width: float, color: Color, alpha: float) -> void:
	var offset := _flat(to - from)
	marker.global_position = (from + to) * 0.5 + Vector3.UP * 0.026
	marker.rotation.y = atan2(offset.x, offset.z)
	marker.scale = Vector3(width, 0.034, maxf(offset.length(), 0.20))
	var material := marker.material_override as StandardMaterial3D
	material.albedo_color = Color(color, alpha)


func _play(foe: Fighter, pose: String) -> void:
	if foe.player == null or pose == foe.current_pose or not foe.player.has_animation(pose):
		return
	foe.current_pose = pose
	var clip := foe.player.get_animation(pose)
	if pose in ["Idle", "Jog", "Sprint", "Boost"]:
		clip.loop_mode = Animation.LOOP_LINEAR
	foe.player.play(pose, 0.125)


func status() -> Dictionary:
	var active := _eligible_fighters()
	var nearest: Fighter = fighters.get(locked_id)
	var hero: Vector3 = game.runner.global_position
	if not is_instance_valid(nearest) or _inactive(nearest) or nearest.data.realm != game.realm:
		nearest = null
		var distance := 40.0
		for foe in active:
			var proximity := foe.global_position.distance_to(hero)
			if proximity < distance:
				nearest = foe
				distance = 0.0 if foe.data.boss else proximity
	if nearest == null:
		return {}
	var d := nearest.data
	var title: String = TITLES[d.archetype]
	var hint := ""
	var window: bool = d.state == "telegraph" and float(d.clock) <= _counter_window(nearest) and _in_reach(nearest, hero, ATTACKS.counter.range)
	if d.state == "telegraph":
		if window:
			hint = "COUNTER NOW"
		else:
			match String(d.attack):
				"needle": hint = "PROJECTILE · REDIRECT"
				"singularity": hint = "PULSE · MOVE OUT"
				"cross": hint = "TWO LANES · DODGE"
				"relay": hint = "RELAY LINE · BRAKE OR PHASE"
				"feedback": hint = "FEEDBACK · DISRUPT"
				"feint": hint = "TRACE · WATCH THE REAL RUNNER"
				_: hint = "INCOMING"
	elif d.state == "recover":
		hint = "OPENING"
	elif d.guarded:
		hint = "GUARDED · HEAVY BEATS LIGHT"
	if d.boss and d.phase == 3 and not d.temporally_exposed and float(d.hp) <= float(d.max_hp) * 0.22 and not window:
		hint = "BREAK GUARD · COUNTER OR REDIRECT" if d.archetype == "rival_dark" else "BREAK REPEAT · REWIND OR DISRUPT"
	return {
		"id": d.id, "title": title, "name": title, "phase": d.phase, "state": d.state,
		"hp": d.hp, "max": d.max_hp, "max_hp": d.max_hp, "health": d.hp,
		"telegraph": hint, "hint": hint, "target": nearest.global_position, "guarded": d.guarded,
		"archetype": d.archetype, "boss": d.boss, "combo": combo, "counter_window": window,
	}


func snapshot() -> Dictionary:
	var entries: Dictionary = {}
	for id in fighters:
		var foe: Fighter = fighters[id]
		if not is_instance_valid(foe) or foe.is_queued_for_deletion():
			continue
		var animation_at := foe.player.current_animation_position if foe.player != null and foe.player.is_playing() else 0.0
		var gate_states: Array[bool] = []
		for gate in foe.gates:
			gate_states.append(gate.collision_layer == 4)
		entries[id] = {"data": foe.data.duplicate(true), "position": foe.global_position, "velocity": foe.velocity,
			"rotation": foe.rig.rotation, "height": foe.rig.position.y, "pose": foe.current_pose, "animation_at": animation_at,
			"gates": gate_states}
	return {
		"fighters": entries, "locked_id": locked_id, "hero_pose": hero_pose, "hit_stop": hit_stop,
		"hero_guard": hero_guard, "pose_time": pose_time, "combo": combo, "combo_time": combo_time,
		"pending": pending.duplicate(true), "queued": queued, "dodge_time": dodge_time, "dodge_direction": dodge_direction,
	}


func restore(frame: Dictionary) -> void:
	var stored: Dictionary = frame.get("fighters", {})
	for id in fighters.keys():
		if stored.has(id):
			continue
		var retired: Fighter = fighters[id]
		retired.visible = false
		retired.collision_layer = 0
		for gate in retired.gates:
			gate.collision_layer = 0
		retired.queue_free()
		fighters.erase(id)
	for id in stored:
		var entry: Dictionary = stored[id]
		var foe: Fighter = fighters.get(id)
		if not is_instance_valid(foe):
			foe = spawn(String(id), entry.position, String(entry.data.archetype)) as Fighter
		foe.data = entry.data.duplicate(true)
		foe.global_position = entry.position
		foe.velocity = entry.velocity
		foe.visible = foe.data.realm == game.realm
		foe.collision_layer = FOE_LAYER if foe.visible and not _inactive(foe) else 0
		if foe.data.state in ["attack", "telegraph"] and foe.data.attack in ["feint", "cross", "feedback"]:
			_ensure_echo(foe)
		_update_visuals(foe)
		var gate_states: Array = entry.get("gates", [])
		for i in mini(gate_states.size(), foe.gates.size()):
			var active := foe.visible and bool(gate_states[i])
			foe.gates[i].collision_layer = 4 if active else 0
			foe.gates[i].visible = active
		foe.rig.rotation = entry.get("rotation", foe.rig.rotation)
		foe.rig.position.y = entry.get("height", foe.rig.position.y)
		_play(foe, entry.get("pose", foe.current_pose))
		if foe.player != null and foe.player.is_playing():
			foe.player.seek(float(entry.get("animation_at", 0.0)), true)
	locked_id = frame.get("locked_id", "")
	hero_pose = frame.get("hero_pose", "")
	hit_stop = frame.get("hit_stop", 0.0)
	hero_guard = frame.get("hero_guard", 0.0)
	pose_time = frame.get("pose_time", 0.0)
	combo = frame.get("combo", 0)
	combo_time = frame.get("combo_time", 0.0)
	pending = frame.get("pending", {}).duplicate(true)
	dodge_time = frame.get("dodge_time", 0.0)
	dodge_direction = frame.get("dodge_direction", Vector3.ZERO)
	queued = frame.get("queued", "")
