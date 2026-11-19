extends RefCounted

const CONTACT_SHADOW = preload("res://assets/contact_shadow.gdshader")
const COATS := [
	Color("#2e4256"), Color("#8e4138"), Color("#2f5956"),
	Color("#4b5064"), Color("#8d7652"), Color("#3e5946"), Color("#6d5260")
]
const PANTS := [
	Color("#1e262e"), Color("#2c343d"), Color("#393530"), Color("#243342")
]
const SKIN := [
	Color("#5d3b2c"), Color("#a67452"), Color("#c3916e"),
	Color("#75503e"), Color("#d2a88c")
]
const HAIR := [
	Color("#1c181a"), Color("#3d2a20"), Color("#6a4e36"), Color("#242026"), Color("#8a7459")
]
const CARS := [
	Color("#2b4257"), Color("#7c2f34"), Color("#2f5a5c"),
	Color("#c9932c"), Color("#8c959c"), Color("#4f3e52")
]

var _materials: Dictionary = {}
var _vehicle_models: Dictionary = {}
var _wheel_mesh: ArrayMesh
var _shadow_mat: ShaderMaterial
var _shadow_mesh: PlaneMesh
var _headlight_cone_mat: StandardMaterial3D
var _siren: AudioStreamWAV
var _engine: AudioStreamWAV


func material(color: Color, roughness: float = 0.75, metalness: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	var key := [color, roughness, metalness, glow]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metalness
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	_materials[key] = mat
	return mat


func _contact_shadow(parent: Node3D, width: float, length: float, opacity: float = 0.56, y_pos: float = 0.024) -> MeshInstance3D:
	if _shadow_mat == null:
		_shadow_mat = ShaderMaterial.new()
		_shadow_mat.shader = CONTACT_SHADOW
		_shadow_mat.set_shader_parameter("opacity", opacity)
	if _shadow_mesh == null:
		_shadow_mesh = PlaneMesh.new()
		_shadow_mesh.size = Vector2(1.0, 1.0)
	var disc := MeshInstance3D.new()
	disc.name = &"ContactShadow"
	disc.mesh = _shadow_mesh
	disc.material_override = _shadow_mat
	disc.position = Vector3(0.0, y_pos, 0.0)
	disc.scale = Vector3(width, 1.0, length)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(disc)
	return disc


func _part(mesh: Mesh, position: Vector3, mat: Material, scaling: Vector3 = Vector3.ONE, rotation: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"mesh": mesh, "transform": Transform3D(Basis.from_euler(rotation).scaled(scaling), position), "material": mat}


func _sphere(position: Vector3, scale: Vector3, mat: Material) -> Dictionary:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.radius = 0.5
	sphere.height = 1.0
	return _part(sphere, position, mat, scale)


func _box(position: Vector3, size: Vector3, mat: Material, rotation: Vector3 = Vector3.ZERO) -> Dictionary:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(mesh, position, mat, Vector3.ONE, rotation)


func _rod(position: Vector3, height: float, top: float, bottom: float, mat: Material, rotation: Vector3 = Vector3.ZERO, segs: int = 8) -> Dictionary:
	var mesh := CylinderMesh.new()
	mesh.radial_segments = segs
	mesh.rings = 1
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return _part(mesh, position, mat, Vector3.ONE, rotation)


func _compile(group: Array[Dictionary]) -> ArrayMesh:
	var by_material: Dictionary = {}
	for part in group:
		var mesh: Mesh = part.mesh
		var mat: Material = part.material
		if not by_material.has(mat):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.set_material(mat)
			by_material[mat] = surface
		for i in mesh.get_surface_count():
			by_material[mat].append_from(mesh, i, part.transform)
	var result := ArrayMesh.new()
	for mat in by_material:
		by_material[mat].commit(result)
	return result


func _mesh(parent: Node3D, geometry: Mesh, at: Vector3 = Vector3.ZERO, shadows: bool = false) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = geometry
	item.position = at
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)
	return item


func _bodywork(rows: Array[Vector4]) -> ArrayMesh:
	var verts := PackedVector3Array()
	for row in rows:
		var w := row.y
		var lo := row.z
		var hi := row.w
		var z := row.x
		verts.append_array([
			Vector3(-w * 0.84, lo, z), Vector3(w * 0.84, lo, z), Vector3(w, lo + 0.11, z),
			Vector3(w, hi - 0.11, z), Vector3(w * 0.84, hi, z), Vector3(-w * 0.84, hi, z),
			Vector3(-w, hi - 0.11, z), Vector3(-w, lo + 0.11, z)
		])
	var surf := SurfaceTool.new()
	surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(rows.size() - 1):
		for j in range(8):
			var a := i * 8 + j
			var b := i * 8 + ((j + 1) % 8)
			for idx in [a, a + 8, b, b, a + 8, b + 8]:
				surf.add_vertex(verts[idx])
	var far := (rows.size() - 1) * 8
	for j in range(1, 7):
		for idx in [0, j, j + 1, far, far + j + 1, far + j]:
			surf.add_vertex(verts[idx])
	surf.generate_normals()
	return surf.commit()


func _get_wheel_mesh() -> ArrayMesh:
	if _wheel_mesh != null:
		return _wheel_mesh
	var rubber := material(Color("#191d21"), 0.92, 0.05)
	var alloy := material(Color("#a7b4bf"), 0.32, 0.72)
	var hub := material(Color("#2a3038"), 0.55, 0.50)
	var parts: Array[Dictionary] = [
		_rod(Vector3.ZERO, 0.24, 0.34, 0.34, rubber, Vector3(0.0, 0.0, PI * 0.5), 14),
		_rod(Vector3.ZERO, 0.255, 0.205, 0.205, alloy, Vector3(0.0, 0.0, PI * 0.5), 10),
		_rod(Vector3.ZERO, 0.268, 0.075, 0.075, hub, Vector3(0.0, 0.0, PI * 0.5), 8),
		# Spokes visible during wheel rotation
		_box(Vector3(0.0, 0.0, 0.0), Vector3(0.262, 0.34, 0.042), alloy),
		_box(Vector3(0.0, 0.0, 0.0), Vector3(0.262, 0.042, 0.34), alloy),
	]
	_wheel_mesh = _compile(parts)
	return _wheel_mesh


func _coach(kind: String, variant: int) -> ArrayMesh:
	var key := [kind, variant % 6]
	if _vehicle_models.has(key):
		return _vehicle_models[key]
	var subtype := posmod(variant, 4) # 0=sedan, 1=coupe, 2=suv, 3=taxi
	var paint_color: Color = CARS[posmod(variant, CARS.size())]
	if kind == "car" and subtype == 3:
		paint_color = Color("#d19529")
	var paint := material(paint_color, 0.32, 0.52)
	if kind == "police":
		paint = material(Color("#1b2736"), 0.34, 0.44)
	elif kind == "van":
		paint = material(Color("#c4beb5") if variant % 2 == 0 else Color("#6e767b"), 0.54, 0.22)
	elif kind == "suspect":
		paint = material(Color("#7c2d2a"), 0.36, 0.42)
	var trim := material(Color("#1b2026"), 0.86, 0.14)
	var chrome := material(Color("#b6c4cf"), 0.26, 0.78)
	var glass := material(Color("#1d3344"), 0.16, 0.72)
	var plate := material(Color("#dde4e6"), 0.55, 0.05)
	var headlight := material(Color("#fff0cf"), 0.30, 0.1, 1.85)
	var taillight := material(Color("#e83d38"), 0.38, 0.1, 1.15)
	var amber := material(Color("#ffb74d"), 0.35, 0.0, 1.35)
	var panels: Array[Dictionary] = []

	var front_z := -2.08
	var rear_z := 2.02
	var roof_y := 1.42
	var body_rows: Array[Vector4]
	var cab_rows: Array[Vector4]
	var roof_len := 1.32
	var roof_z := 0.08
	var roof_w := 1.34

	if kind == "van":
		front_z = -2.38
		rear_z = 2.34
		roof_y = 2.02
		roof_len = 3.28
		roof_z = 0.28
		roof_w = 1.68
		body_rows = [
			Vector4(-2.44, 0.90, 0.38, 0.80), Vector4(-2.06, 1.03, 0.36, 1.06),
			Vector4(-1.26, 1.06, 0.28, 1.56), Vector4(2.12, 1.06, 0.29, 1.66),
			Vector4(2.36, 0.98, 0.38, 1.54)
		]
		cab_rows = [
			Vector4(-1.92, 0.86, 0.98, 1.12), Vector4(-1.38, 0.95, 1.02, 1.94),
			Vector4(-0.55, 0.96, 1.02, 1.96), Vector4(-0.48, 0.94, 1.02, 1.52)
		]
		# Solid cargo upper body behind cab
		panels.append(_box(Vector3(0.0, 1.55, 0.85), Vector3(1.94, 0.88, 2.74), paint))
		panels.append(_box(Vector3(0.0, 1.99, 0.22), Vector3(1.56, 0.06, 3.10), trim))
	elif kind == "car" and subtype == 1:
		# Sleek sporty coupe
		roof_y = 1.30
		roof_len = 1.12
		roof_z = 0.14
		roof_w = 1.24
		body_rows = [
			Vector4(-2.14, 0.78, 0.32, 0.60), Vector4(-1.86, 0.99, 0.29, 0.78),
			Vector4(-0.98, 1.02, 0.25, 0.88), Vector4(0.84, 1.03, 0.26, 0.92),
			Vector4(1.74, 0.98, 0.30, 0.84), Vector4(2.04, 0.86, 0.34, 0.70)
		]
		cab_rows = [
			Vector4(-0.92, 0.82, 0.82, 0.94), Vector4(-0.36, 0.72, 0.86, 1.26),
			Vector4(0.68, 0.72, 0.86, 1.25), Vector4(1.38, 0.82, 0.82, 0.94)
		]
		# Subtle rear lip spoiler
		panels.append(_box(Vector3(0.0, 0.90, 1.88), Vector3(1.66, 0.06, 0.20), trim))
	elif kind == "car" and subtype == 2:
		# Urban SUV / Crossover
		roof_y = 1.62
		roof_len = 2.02
		roof_z = 0.26
		roof_w = 1.46
		body_rows = [
			Vector4(-2.12, 0.84, 0.38, 0.72), Vector4(-1.86, 1.01, 0.36, 0.92),
			Vector4(-0.95, 1.04, 0.32, 1.04), Vector4(1.05, 1.04, 0.32, 1.08),
			Vector4(1.90, 1.00, 0.36, 1.00), Vector4(2.08, 0.90, 0.40, 0.82)
		]
		cab_rows = [
			Vector4(-0.98, 0.86, 0.96, 1.10), Vector4(-0.56, 0.80, 1.00, 1.58),
			Vector4(1.32, 0.81, 1.00, 1.59), Vector4(1.78, 0.86, 0.96, 1.12)
		]
		for side in [-1.0, 1.0]:
			panels.append(_box(Vector3(side * 0.64, 1.64, 0.34), Vector3(0.06, 0.07, 1.84), trim))
	else:
		# Classic 3-box executive sedan / police interceptor / taxi
		body_rows = [
			Vector4(-2.14, 0.80, 0.35, 0.64), Vector4(-1.90, 0.98, 0.32, 0.82),
			Vector4(-1.04, 1.01, 0.27, 0.92), Vector4(0.82, 1.02, 0.27, 0.95),
			Vector4(1.70, 0.99, 0.32, 0.86), Vector4(2.02, 0.86, 0.36, 0.71)
		]
		cab_rows = [
			Vector4(-1.02, 0.82, 0.84, 0.96), Vector4(-0.48, 0.75, 0.88, 1.38),
			Vector4(0.68, 0.76, 0.88, 1.39), Vector4(1.22, 0.83, 0.86, 0.98)
		]

	panels.append(_part(_bodywork(body_rows), Vector3.ZERO, paint))
	panels.append(_part(_bodywork(cab_rows), Vector3.ZERO, glass))

	# Painted roof cap & structural A/B/C pillars so the greenhouse reads as real metal + glass
	if kind != "van":
		var roof_mat := material(Color("#e4e8eb"), 0.38, 0.35) if kind == "police" else paint
		panels.append(_box(Vector3(0.0, roof_y - 0.02, roof_z), Vector3(roof_w, 0.08, roof_len), roof_mat))
		for side in [-1.0, 1.0]:
			# B-pillar & C-pillar framing
			panels.append(_box(Vector3(side * (roof_w * 0.54), roof_y - 0.26, roof_z - 0.04), Vector3(0.08, 0.44, 0.14), trim))
			panels.append(_box(Vector3(side * (roof_w * 0.52), roof_y - 0.25, roof_z + roof_len * 0.46), Vector3(0.11, 0.44, 0.26), paint))
			# Side mirrors
			panels.append(_box(Vector3(side * 1.04, 0.96, -0.78), Vector3(0.20, 0.11, 0.14), paint))
			# Lower rocker skirts & door handles
			panels.append(_box(Vector3(side * 1.00, 0.31, 0.0), Vector3(0.07, 0.12, 2.15), trim))
			panels.append(_box(Vector3(side * 1.02, 0.82, -0.18), Vector3(0.04, 0.04, 0.18), chrome))
			panels.append(_box(Vector3(side * 1.02, 0.82, 0.58), Vector3(0.04, 0.04, 0.18), chrome))
	else:
		for side in [-1.0, 1.0]:
			panels.append(_box(Vector3(side * 1.08, 1.24, -1.52), Vector3(0.20, 0.24, 0.12), trim))

	# Recessed dark front grille, bumpers, license plates, chrome accent bar
	panels.append(_box(Vector3(0.0, 0.58, front_z - 0.01), Vector3(0.96, 0.20, 0.08), trim))
	panels.append(_box(Vector3(0.0, 0.62, front_z - 0.05), Vector3(0.86, 0.04, 0.03), chrome))
	panels.append(_box(Vector3(0.0, 0.44, front_z + 0.02), Vector3(1.74, 0.15, 0.16), trim))
	panels.append(_box(Vector3(0.0, 0.45, rear_z - 0.02), Vector3(1.74, 0.14, 0.14), trim))
	panels.append(_box(Vector3(0.0, 0.49, front_z - 0.06), Vector3(0.42, 0.11, 0.02), plate))
	panels.append(_box(Vector3(0.0, 0.56, rear_z + 0.02), Vector3(0.42, 0.11, 0.02), plate))

	# Headlights, amber side turn indicators, taillights, wheel arches
	for side in [-1.0, 1.0]:
		panels.append(_box(Vector3(side * 0.68, 0.65, front_z - 0.02), Vector3(0.42, 0.13, 0.08), headlight))
		panels.append(_box(Vector3(side * 0.90, 0.64, front_z + 0.12), Vector3(0.07, 0.09, 0.16), amber))
		panels.append(_box(Vector3(side * 0.69, 0.68, rear_z + 0.01), Vector3(0.42, 0.11, 0.06), taillight))
		# Dark wheel-well housings so rotating wheels sit inside crisp arches
		for axle in [-1.31, 1.28]:
			panels.append(_rod(Vector3(side * 0.86, 0.36, axle), 0.28, 0.39, 0.39, trim, Vector3(0.0, 0.0, PI * 0.5), 10))

	if kind == "car" and subtype == 3:
		# Taxi rooftop beacon
		panels.append(_box(Vector3(0.0, roof_y + 0.09, 0.06), Vector3(0.54, 0.15, 0.22), amber))
		for side in [-1.0, 1.0]:
			panels.append(_box(Vector3(side * 1.02, 0.72, 0.10), Vector3(0.025, 0.10, 1.65), trim))
	elif kind == "police":
		var white_door := material(Color("#e4e8eb"), 0.42, 0.25)
		for side in [-1.0, 1.0]:
			panels.append(_box(Vector3(side * 1.015, 0.66, 0.08), Vector3(0.03, 0.46, 1.48), white_door))
		# Front interceptor push bar
		panels.append(_box(Vector3(0.0, 0.60, front_z - 0.11), Vector3(0.88, 0.28, 0.07), trim))
		panels.append(_box(Vector3(0.0, 1.44, 0.10), Vector3(0.96, 0.08, 0.28), trim))

	_vehicle_models[key] = _compile(panels)
	return _vehicle_models[key]


func vehicle(parent: Node3D, kind: String, variant: int) -> Dictionary:
	_mesh(parent, _coach(kind, variant), Vector3.ZERO, true)
	var shadow_len := 5.4 if kind == "van" else 4.75
	_contact_shadow(parent, 2.55, shadow_len, 0.64, 0.025)

	# 4 independent rotating wheels
	var wheels: Array[Node3D] = []
	var w_mesh := _get_wheel_mesh()
	for side in [-1.0, 1.0]:
		for axle in [-1.31, 1.28]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.92, 0.34, axle)
			parent.add_child(pivot)
			_mesh(pivot, w_mesh)
			wheels.append(pivot)

	# Soft warm ground headlight projection wash
	if _headlight_cone_mat == null:
		_headlight_cone_mat = StandardMaterial3D.new()
		_headlight_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_headlight_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_headlight_cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_headlight_cone_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_headlight_cone_mat.albedo_color = Color(1.0, 0.90, 0.68, 0.14)
	var beam_plane := PlaneMesh.new()
	beam_plane.size = Vector2(1.85, 3.4)
	var beam := MeshInstance3D.new()
	beam.mesh = beam_plane
	beam.material_override = _headlight_cone_mat
	beam.position = Vector3(0.0, 0.032, -4.1 if kind == "van" else -3.75)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(beam)

	var brake_glow := material(Color("#ff3732"), 0.42, 0.10, 2.8)
	var brake_parts: Array[Dictionary] = []
	var rear := 2.37 if kind == "van" else 2.05
	for side in [-1.0, 1.0]:
		brake_parts.append(_box(Vector3(side * 0.69, 0.68, rear), Vector3(0.38, 0.085, 0.024), brake_glow))
	var result := {"brake_lamps": _mesh(parent, _compile(brake_parts)), "wheels": wheels}
	if kind == "police":
		var beacon_red: Array[Dictionary] = [_box(Vector3(0.24, 1.52, 0.10), Vector3(0.42, 0.13, 0.26), material(Color("#ff453e"), 0.40, 0.0, 2.2))]
		var beacon_blue: Array[Dictionary] = [_box(Vector3(-0.24, 1.52, 0.10), Vector3(0.42, 0.13, 0.26), material(Color("#36a6ff"), 0.40, 0.0, 2.3))]
		result.red = _mesh(parent, _compile(beacon_red))
		result.blue = _mesh(parent, _compile(beacon_blue))
		var sound := AudioStreamPlayer3D.new()
		sound.name = "PursuitTone"
		sound.stream = _siren_asset()
		sound.position.y = 1.48
		sound.volume_db = -17.0
		sound.unit_size = 4.0
		sound.max_distance = 48.0
		if AudioServer.get_bus_index("SFX") >= 0:
			sound.bus = &"SFX"
		parent.add_child(sound)
		result.siren = sound
	else:
		var motor := AudioStreamPlayer3D.new()
		motor.name = &"EngineIdle"
		motor.stream = _engine_asset()
		motor.position = Vector3(0.0, 0.56, -1.1)
		motor.volume_db = -23.0
		motor.unit_size = 0.8
		motor.max_distance = 23.0
		if AudioServer.get_bus_index("SFX") >= 0:
			motor.bus = &"SFX"
		parent.add_child(motor)
		result.motor = motor
	return result


func human(parent: Node3D, variant: int, suspect: bool) -> Dictionary:
	var coat := material(COATS[posmod(variant, COATS.size())] if not suspect else Color("#7d3830"), 0.78)
	var pants := material(PANTS[posmod(variant + 1, PANTS.size())], 0.84)
	var shoe_mat := material(Color("#232529"), 0.72)
	var sole_mat := material(Color("#cfd5d9"), 0.82)
	var skin := material(SKIN[posmod(variant, SKIN.size())], 0.62)
	var hair_mat := material(HAIR[posmod(variant, HAIR.size())], 0.74)
	var shirt := material(Color("#d8d0c3") if variant % 2 == 0 else Color("#303842"), 0.82)
	var bag_mat := material(Color("#2d2723"), 0.65)

	# Grounded contact shadow disc
	_contact_shadow(parent, 0.88, 0.88, 0.52, 0.020)

	# Sculpted human torso, shoulders, collar, neck, head, and hair/cap
	var body: Array[Dictionary] = [
		# Pelvis / waist
		_rod(Vector3(0.0, 0.94, 0.0), 0.19, 0.16, 0.17, coat),
		# Tapered athletic/civilian jacket torso
		_rod(Vector3(0.0, 1.19, 0.0), 0.36, 0.21, 0.16, coat),
		_box(Vector3(0.0, 1.24, 0.0), Vector3(0.42, 0.22, 0.22), coat),
		# Open jacket shirt front + collar
		_box(Vector3(0.0, 1.21, -0.105), Vector3(0.13, 0.28, 0.03), shirt),
		_rod(Vector3(0.0, 1.38, 0.0), 0.07, 0.105, 0.12, coat),
		# Neck
		_rod(Vector3(0.0, 1.44, -0.005), 0.11, 0.056, 0.062, skin),
		# Sculpted head + jawline + subtle nose bridge
		_sphere(Vector3(0.0, 1.59, -0.006), Vector3(0.20, 0.24, 0.21), skin),
		_sphere(Vector3(0.0, 1.51, -0.022), Vector3(0.15, 0.11, 0.17), skin),
		_box(Vector3(0.0, 1.58, -0.108), Vector3(0.032, 0.055, 0.036), skin),
	]
	# Distinct hair/headwear silhouettes by variant
	var hair_style := posmod(variant, 4)
	if hair_style == 0:
		# Classic swept hair
		body.append(_sphere(Vector3(0.0, 1.66, 0.012), Vector3(0.215, 0.14, 0.22), hair_mat))
		body.append(_sphere(Vector3(0.0, 1.59, 0.065), Vector3(0.19, 0.14, 0.11), hair_mat))
	elif hair_style == 1:
		# Longer hair + ponytail
		body.append(_sphere(Vector3(0.0, 1.65, 0.014), Vector3(0.22, 0.16, 0.22), hair_mat))
		body.append(_sphere(Vector3(0.0, 1.56, 0.115), Vector3(0.095, 0.14, 0.095), hair_mat))
	elif hair_style == 2:
		# Urban baseball cap
		var cap_mat := material(Color("#25364a") if not suspect else Color("#242022"), 0.78)
		body.append(_sphere(Vector3(0.0, 1.67, 0.004), Vector3(0.218, 0.13, 0.225), cap_mat))
		body.append(_box(Vector3(0.0, 1.64, -0.115), Vector3(0.17, 0.025, 0.11), cap_mat))
	else:
		# Short cropped hair
		body.append(_sphere(Vector3(0.0, 1.655, 0.008), Vector3(0.208, 0.12, 0.215), hair_mat))

	# Optional backpack for urban variety
	if variant % 3 == 1 and not suspect:
		body.append(_box(Vector3(0.0, 1.18, 0.155), Vector3(0.28, 0.36, 0.13), bag_mat))

	var legs: Array[Node3D] = []
	var arms: Array[Node3D] = []
	_mesh(parent, _compile(body), Vector3.ZERO, true)

	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.105, 0.88, 0.0)
		parent.add_child(leg)
		var leg_parts: Array[Dictionary] = [
			_rod(Vector3(0.0, -0.21, 0.0), 0.42, 0.088, 0.072, pants),
			_rod(Vector3(0.0, -0.60, 0.01), 0.40, 0.068, 0.056, pants),
			_box(Vector3(0.0, -0.82, -0.045), Vector3(0.115, 0.09, 0.24), shoe_mat),
			_box(Vector3(0.0, -0.865, -0.045), Vector3(0.120, 0.028, 0.25), sole_mat),
		]
		_mesh(leg, _compile(leg_parts), Vector3.ZERO, true)
		legs.append(leg)

		var arm := Node3D.new()
		arm.position = Vector3(side * 0.245, 1.32, 0.0)
		arm.rotation.z = side * 0.09
		parent.add_child(arm)
		var sleeve: Array[Dictionary] = [
			_sphere(Vector3(0.0, 0.0, 0.0), Vector3(0.14, 0.14, 0.14), coat),
			_rod(Vector3(0.0, -0.17, 0.0), 0.30, 0.066, 0.056, coat),
			_rod(Vector3(0.0, -0.43, -0.012), 0.26, 0.054, 0.046, coat),
			_sphere(Vector3(0.0, -0.59, -0.02), Vector3(0.085, 0.11, 0.095), skin),
		]
		_mesh(arm, _compile(sleeve), Vector3.ZERO, true)
		arms.append(arm)

	var h_scale := 0.96 + 0.022 * float(variant % 5)
	var w_scale := 0.97 + 0.025 * float(variant % 4)
	parent.scale = Vector3(w_scale, h_scale, w_scale)
	return {"legs": legs, "arms": arms}


func prop(parent: Node3D, variant: int) -> Dictionary:
	var paint := material(Color("#d46726"), 0.52) if variant % 2 == 0 else material(Color("#55616b"), 0.58)
	var steel := material(Color("#394652"), 0.55, 0.42)
	var marker := material(Color("#f4dc9e"), 0.48, 0.0, 0.45)
	_contact_shadow(parent, 0.96, 0.96, 0.48, 0.022)
	var parts: Array[Dictionary] = [
		_rod(Vector3(0, 0.37, 0), 0.72, 0.30, 0.32, paint, Vector3.ZERO, 12),
		_rod(Vector3(0, 0.16, 0), 0.083, 0.33, 0.33, steel, Vector3.ZERO, 12),
		_rod(Vector3(0, 0.56, 0), 0.084, 0.32, 0.32, marker, Vector3.ZERO, 12),
		_rod(Vector3(0, 0.71, 0), 0.095, 0.325, 0.328, steel, Vector3.ZERO, 12)
	]
	_mesh(parent, _compile(parts), Vector3.ZERO, true)
	return {}


func signal_head(parent: Node3D) -> Dictionary:
	var post := material(Color("#333e47"), 0.62, 0.38)
	var housing := material(Color("#1f2830"), 0.72)
	var metal: Array[Dictionary] = [
		_rod(Vector3(0, 2.2, 0), 4.4, 0.08, 0.13, post),
		_box(Vector3(0, 4.07, 0), Vector3(0.39, 1.16, 0.29), housing)
	]
	_mesh(parent, _compile(metal))
	var bulbs: Array[MeshInstance3D] = []
	for index in range(3):
		var colors := [Color("#ff4c3f"), Color("#ffcc3b"), Color("#63eda5")]
		var bulb: Array[Dictionary] = [_sphere(Vector3(0, 4.42 - 0.34 * index, -0.155), Vector3(0.23, 0.23, 0.095), material(colors[index], 0.60, 0, 2.3))]
		bulbs.append(_mesh(parent, _compile(bulb)))
	return {"bulbs": bulbs}


func _siren_asset() -> AudioStreamWAV:
	if _siren != null:
		return _siren
	const RATE := 16000
	var waveform := PackedByteArray()
	waveform.resize(RATE * 4)
	var phase := 0.0
	for index in range(RATE * 2):
		var seconds := float(index) / RATE
		var sweep := 0.5 - 0.5 * cos(TAU * seconds / 2.0)
		phase += TAU * (420.0 + 382.0 * sweep) / RATE
		var value := int((sin(phase) + 0.17 * sin(2.0 * phase)) * 13400.0)
		waveform.encode_s16(index * 2, value)
	_siren = AudioStreamWAV.new()
	_siren.format = AudioStreamWAV.FORMAT_16_BITS
	_siren.mix_rate = RATE
	_siren.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_siren.loop_end = RATE * 2
	_siren.data = waveform
	return _siren


func _engine_asset() -> AudioStreamWAV:
	if _engine != null:
		return _engine
	const RATE := 12000
	var waveform := PackedByteArray()
	waveform.resize(RATE * 2)
	for index in range(RATE):
		var elapsed := float(index) / RATE
		var low := sin(TAU * elapsed * 48.0)
		var rough := 0.40 * sin(TAU * elapsed * 96.0) + 0.18 * sin(TAU * elapsed * 144.0)
		var idle_variation := 0.82 + 0.18 * sin(TAU * elapsed * 8.0)
		waveform.encode_s16(index * 2, int((low + rough) * idle_variation * 12600.0))
	_engine = AudioStreamWAV.new()
	_engine.format = AudioStreamWAV.FORMAT_16_BITS
	_engine.mix_rate = RATE
	_engine.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_engine.loop_end = RATE
	_engine.data = waveform
	return _engine
