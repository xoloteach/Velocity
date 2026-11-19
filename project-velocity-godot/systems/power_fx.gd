extends Node3D
## Draw calls stay bounded. Dynamic lightning is batched per palette.

const AMBER := Color("#ffc274")
const VIOLET := Color("#b396ff")
const MINT := Color("#a6efdc")
const RING_CAP := 9
const SCORCH_CAP := 6
const Scorch := preload("res://assets/power_scorch.gdshader")

var _amber_mesh := ImmediateMesh.new()
var _violet_mesh := ImmediateMesh.new()
var _mint_mesh := ImmediateMesh.new()
var _core_mesh := ImmediateMesh.new()
var _amber: StandardMaterial3D
var _violet: StandardMaterial3D
var _mint: StandardMaterial3D
var _core: StandardMaterial3D
var _rings: Array[Dictionary] = []
var _ring_nodes: Array[MeshInstance3D] = []
var _scorches: Array[MeshInstance3D] = []
var _scorch_times: Array[float] = []
var _scorch_cursor := 0
var _ghost: Node3D
var _ghost_anim: AnimationPlayer
var _ghost_clip := ""
var _city_gate: Node3D
var _rift_gate: Node3D
var _arc_am: Array = []
var _arc_vi: Array = []
var _arc_mi: Array = []
var _time := 0.0


func _ready() -> void:
	_amber = _unlit(AMBER, true)
	_violet = _unlit(VIOLET, true)
	_mint = _unlit(MINT, true)
	_core = _unlit(Color(1.0, 0.98, 0.92, 0.95), true)
	for mesh: ImmediateMesh in [_amber_mesh, _violet_mesh, _mint_mesh, _core_mesh]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.94
	hoop.outer_radius = 1.0
	hoop.rings = 32
	hoop.ring_segments = 5
	for i in range(RING_CAP):
		var ring := MeshInstance3D.new()
		ring.mesh = hoop
		ring.material_override = _unlit(AMBER, true)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.hide()
		_ring_nodes.append(ring)
		add_child(ring)
	_city_gate = _create_gate(hoop)
	_rift_gate = _create_gate(hoop)
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.76, 0.76)
	for i in range(SCORCH_CAP):
		var node := MeshInstance3D.new()
		var mark := ShaderMaterial.new()
		mark.shader = Scorch
		node.material_override = mark
		node.mesh = plane
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.hide()
		add_child(node)
		_scorches.append(node)
		_scorch_times.append(0.0)


func _unlit(tint: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material


func _create_gate(mesh: Mesh) -> Node3D:
	var root := Node3D.new()
	var outer := MeshInstance3D.new()
	outer.name = &"Outer"
	outer.mesh = mesh
	outer.material_override = _unlit(VIOLET, true)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(outer)
	var inner := MeshInstance3D.new()
	inner.name = &"Inner"
	inner.mesh = mesh
	inner.material_override = _unlit(Color("#7ae8ff"), true)
	inner.scale = Vector3(0.76, 1.35, 0.76)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inner)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.86
	disc.bottom_radius = 0.86
	disc.height = 0.04
	disc.radial_segments = 24
	var core_disc := MeshInstance3D.new()
	core_disc.name = &"Disc"
	core_disc.mesh = disc
	core_disc.material_override = _unlit(Color(0.58, 0.42, 0.96, 0.34), true)
	core_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core_disc)
	root.hide()
	add_child(root)
	return root


func ring(at: Vector3, tint: Color, life: float, radius: float) -> void:
	if _rings.size() == RING_CAP:
		_rings.pop_front()
	_rings.append({"at": at, "tint": tint, "remaining": life, "life": life, "radius": radius})


func scorch(at: Vector3, normal: Vector3, seed: int) -> void:
	if normal.length_squared() < 0.8:
		return
	var node := _scorches[_scorch_cursor]
	_scorch_times[_scorch_cursor] = 3.4
	_scorch_cursor = (_scorch_cursor + 1) % SCORCH_CAP
	node.position = at + normal * 0.016
	node.basis = Basis(Quaternion(Vector3.UP, normal.normalized()))
	(node.material_override as ShaderMaterial).set_shader_parameter("pattern", float(seed) * 0.84)
	node.show()


func arc(from: Vector3, to: Vector3, palette: String, seed: int = 0) -> void:
	if from.distance_squared_to(to) < 0.0001:
		return
	var bucket: Array = _arc_am
	if palette == "violet":
		bucket = _arc_vi
	elif palette == "mint":
		bucket = _arc_mi
	if bucket.size() < 30:
		bucket.append([from, to, seed])


func frame(delta: float, reduced: bool, quality: int) -> void:
	_time += delta
	for i in range(SCORCH_CAP):
		if _scorch_times[i] <= 0.0:
			continue
		_scorch_times[i] = maxf(0.0, _scorch_times[i] - delta)
		var mark := _scorches[i]
		mark.visible = _scorch_times[i] > 0.0
		if mark.visible:
			(mark.material_override as ShaderMaterial).set_shader_parameter("remaining", _scorch_times[i] / 3.4)
	for i in range(_rings.size() - 1, -1, -1):
		_rings[i].remaining = float(_rings[i].remaining) - delta
		if float(_rings[i].remaining) <= 0.0:
			_rings.remove_at(i)
	for i in range(_ring_nodes.size()):
		var node := _ring_nodes[i]
		node.visible = i < _rings.size()
		if not node.visible:
			continue
		var entry := _rings[i]
		var remaining := float(entry.remaining) / float(entry.life)
		var radius := lerpf(0.5, float(entry.radius), 1.0 - remaining * remaining)
		node.position = Vector3(entry.at) + Vector3.UP * 0.09
		node.scale = Vector3(radius, 0.70, radius)
		var color := Color(entry.tint)
		color.a = (0.36 if reduced else 0.76) * remaining
		(node.material_override as StandardMaterial3D).albedo_color = color
	for mesh: ImmediateMesh in [_amber_mesh, _violet_mesh, _mint_mesh, _core_mesh]:
		mesh.clear_surfaces()
	var parts := 4 if reduced or quality == 0 else 8
	_draw_arcs(_amber_mesh, _amber, _arc_am, parts, reduced, 1.35)
	_draw_arcs(_violet_mesh, _violet, _arc_vi, parts, reduced, 1.35)
	_draw_arcs(_mint_mesh, _mint, _arc_mi, parts, reduced, 1.35)
	var all_arcs := _arc_am + _arc_vi + _arc_mi
	_draw_arcs(_core_mesh, _core, all_arcs, parts, reduced, 0.48)
	_arc_am.clear()
	_arc_vi.clear()
	_arc_mi.clear()


func _draw_arcs(mesh: ImmediateMesh, material: StandardMaterial3D, items: Array, parts: int, reduced: bool, width_mult: float = 1.0) -> void:
	if items.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for entry in items:
		var from: Vector3 = entry[0]
		var to: Vector3 = entry[1]
		var heading := (to - from).normalized()
		var side := heading.cross(Vector3.UP)
		if side.length_squared() < 0.03:
			side = heading.cross(Vector3.FORWARD)
		side = side.normalized()
		var last := from
		var seed := float(entry[2]) * 0.973 + (0.0 if reduced else floorf(_time * 26.0))
		for j in range(1, parts + 1):
			var part := float(j) / parts
			var next := from.lerp(to, part)
			var envelope := sin(part * PI) * (0.042 if reduced else 0.14)
			next += side * sin(seed + j * 6.71) * envelope + Vector3.UP * cos(seed + j * 9.2) * envelope
			_beam_segment(mesh, last, next, side, (0.028 if reduced else 0.046) * width_mult)
			_beam_segment(mesh, last, next, heading.cross(side), (0.017 if reduced else 0.028) * width_mult)
			last = next
	mesh.surface_end()


func _beam_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, side: Vector3, width: float) -> void:
	var edge := side * width
	mesh.surface_add_vertex(from + edge)
	mesh.surface_add_vertex(to + edge)
	mesh.surface_add_vertex(to - edge)
	mesh.surface_add_vertex(from + edge)
	mesh.surface_add_vertex(to - edge)
	mesh.surface_add_vertex(from - edge)


func gates(city: Vector3, rift: Vector3, observer: Vector3, in_rift: bool, reduced: bool) -> void:
	_set_gate(_city_gate, city, not in_rift and observer.distance_to(city) < 35.0, reduced)
	_set_gate(_rift_gate, rift, in_rift and observer.distance_to(rift) < 80.0, reduced)


func _set_gate(gate: Node3D, center: Vector3, visible_gate: bool, reduced: bool) -> void:
	gate.visible = visible_gate
	if not visible_gate:
		return
	gate.position = center + Vector3.UP * 1.48
	gate.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	gate.scale = Vector3(1.58, 1.9, 1.58)
	var outer := gate.get_node_or_null("Outer") as MeshInstance3D
	var inner := gate.get_node_or_null("Inner") as MeshInstance3D
	var disc := gate.get_node_or_null("Disc") as MeshInstance3D
	if is_instance_valid(outer):
		var tint := VIOLET
		tint.a = 0.68 if reduced else 0.78 + sin(_time * 3.4) * 0.14
		(outer.material_override as StandardMaterial3D).albedo_color = tint
		if not reduced:
			outer.rotation.y = _time * 1.4
	if is_instance_valid(inner) and not reduced:
		inner.rotation.y = -_time * 2.3
		inner.rotation.x = sin(_time * 2.1) * 0.18
	if is_instance_valid(disc):
		var dtint := Color(0.56, 0.44, 0.98, 0.24 if reduced else 0.30 + sin(_time * 4.5) * 0.08)
		(disc.material_override as StandardMaterial3D).albedo_color = dtint


func ghost(at: Vector3, heading: float, speed: float, airborne: bool, remaining: float, captured_clip: String, captured_frame: float) -> void:
	if not is_instance_valid(_ghost):
		_make_ghost()
	_ghost.visible = true
	_ghost.position = at
	_ghost.rotation.y = heading
	var has_capture := is_instance_valid(_ghost_anim) and _ghost_anim.has_animation(captured_clip)
	var clip := captured_clip if has_capture else ("Air" if airborne else ("Boost" if speed > 24.0 else ("Jog" if speed > 2.0 else "Idle")))
	if is_instance_valid(_ghost_anim) and _ghost_anim.has_animation(clip):
		_ghost_anim.speed_scale = 0.0 if has_capture else 1.0
		if _ghost_clip != clip:
			_ghost_clip = clip
			_ghost_anim.play(clip, 0.0 if has_capture else 0.14)
		if has_capture:
			_ghost_anim.seek(captured_frame, true)
	_ghost.scale = Vector3.ONE * clampf(remaining * 2.3, 0.86, 1.0)


func hide_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.hide()
		if is_instance_valid(_ghost_anim):
			_ghost_anim.stop()
		_ghost_clip = ""


func _make_ghost() -> void:
	var scene: PackedScene = load("res://assets/velocity-runner.glb")
	_ghost = scene.instantiate()
	_ghost.name = "SpeedMirage"
	add_child(_ghost)
	_ghost_anim = _ghost.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var material := _unlit(Color(1.0, 0.47, 0.25, 0.29), true)
	for part in _ghost.find_children("*", "MeshInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.material_override = material


func clear() -> void:
	_rings.clear()
	_arc_am.clear()
	_arc_vi.clear()
	_arc_mi.clear()
	for i in range(SCORCH_CAP):
		_scorch_times[i] = 0.0
		_scorches[i].hide()
	hide_ghost()
