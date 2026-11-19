extends Node3D

const ASPHALT = preload("res://assets/world_asphalt.gdshader")
const WATER = preload("res://assets/world_water.gdshader")
const FACADE = preload("res://assets/world_facade.gdshader")
const PHASE = preload("res://assets/world_phase.gdshader")
const SKY = preload("res://assets/world_sky.gdshader")
const STOREFRONT = preload("res://assets/world_storefront.gdshader")
const RIFT_FLOOR = preload("res://assets/world_rift_floor.gdshader")
const CONTACT_SHADOW = preload("res://assets/contact_shadow.gdshader")
const CHUNK_SIZE := 134.0
const ORIGIN := Vector2(-67.0, -335.0)
const CITY_LIMIT_X := 315.0
const CITY_MIN_Z := -512.0
const CITY_MAX_Z := 84.0
const RIFT_Z := 1360.0
const CANAL_BOUNDS := Rect2(-182.0, -196.0, 72.0, 121.0)
const BRIDGES := [-119.0, -177.0]
const CROSS_STREETS := [37.0, -56.0, -119.0, -177.0, -226.0, -306.0, -398.0, -487.0]
const THROUGH_STREETS := [-268.0, -201.0, -97.0, 0.0, 116.0, 205.0, 270.0]
const LAYOUT_VERSION := 3
const MAX_CHUNKS := 20
const SHOP_NAMES := ["MORROW HOTEL", "LANTERN COFFEE", "CALDER BOOKS", "NIGHT SHIFT", "NORTHLINE MARKET", "THE MERIDIAN", "PARKER ELECTRIC", "JUNE RECORDS"]

var game
var city: Node3D
var rift: Node3D
var chunks: Dictionary = {}
var waiting: Array[Vector2i] = []
var materials: Dictionary = {}
var facade: Array[ShaderMaterial] = []
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var atmosphere: Environment
var local_lights: Array[OmniLight3D] = []
var train: Node3D
var train_time := 0.0
var realm := "city"
var elapsed := 0.0
var time_of_day := 18.35
var quality := 2
var motion_scale := 1.0
var seed := 68137
var cells_built := 0
var spawn_cell := Vector2i(0, 2)
var center_cell := Vector2i(9999, 9999)
var course: Dictionary = {}
var data: Dictionary = {}
var block_mesh := BoxMesh.new()
var elapsed_stream := 0.0
var elapsed_lighting := 0.0
var visual_queue: Array[Vector2i] = []
var solid_count := 0
var phase_bodies: Array[StaticBody3D] = []
var road_graph: Dictionary = {}

func setup(coordinator) -> void:
	if is_instance_valid(city):
		return
	game = coordinator
	if "quality" in coordinator:
		quality = clampi(int(coordinator.quality), 0, 3)
	course = _load_dictionary("res://shared/course.json")
	data = _load_dictionary("res://shared/game.json")
	seed = int(data.get("seed", seed))
	road_graph = _make_road_graph()
	_create_materials()
	_create_lighting()
	city = _node(self, "Calder City")
	rift = _node(self, "Speed Force Pocket")
	_build_city()
	_build_rift()
	quality_changed(quality)
	set_realm("city")
	set_hour(time_of_day)
	spawn_cell = cell_at(Vector3(0.0, 0.0, 8.0))
	prepare_destination(Vector3(0.0, 0.0, 8.0))
	for starting_cell in [spawn_cell, spawn_cell + Vector2i(0, -1)]:
		_ensure_collision(starting_cell)
		_ensure_visuals(starting_cell)

func _load_dictionary(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func step(delta: float, player_pos: Vector3) -> void:
	elapsed += delta
	if realm == "city":
		var active := cell_at(player_pos)
		if active != center_cell:
			prepare_destination(player_pos)
		elapsed_lighting += delta
		if elapsed_lighting >= 3.0:
			set_hour(time_of_day + elapsed_lighting / 48.0)
			elapsed_lighting = 0.0
		if is_instance_valid(train):
			train_time = fposmod(train_time + delta * 8.0 * motion_scale, 377.0)
			train.position.x = train_time - 188.0
	elapsed_stream += delta
	if elapsed_stream < 0.032 or realm != "city":
		return
	elapsed_stream = 0.0
	if not waiting.is_empty():
		_ensure_collision(waiting.pop_front())
	if not visual_queue.is_empty():
		_ensure_visuals(visual_queue.pop_front())

func prepare_destination(pos: Vector3) -> void:
	if pos.z > 1000.0:
		return
	center_cell = cell_at(pos)
	_ensure_collision(center_cell)
	_ensure_visuals(center_cell)
	for key in chunks.keys():
		var cell: Vector2i = key
		if maxi(absi(cell.x - center_cell.x), absi(cell.y - center_cell.y)) > 2:
			_remove_chunk(cell)
		else:
			_set_chunk_quality(cell,chunks[cell])
	waiting.clear()
	var direction_z := -1 if pos.z > _cell_z(center_cell) or center_cell.y > 0 else 1
	var offsets := [Vector2i(0, direction_z), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -direction_z), Vector2i(-1, direction_z), Vector2i(1, direction_z), Vector2i(-1, -direction_z), Vector2i(1, -direction_z)]
	for offset in offsets:
		var next: Vector2i = center_cell + offset
		if _valid_cell(next) and not chunks.has(next):
			waiting.push_back(next)
	var farthest := center_cell + Vector2i(0, 2 * direction_z)
	if _valid_cell(farthest) and not chunks.has(farthest):
		waiting.push_back(farthest)

func prefetch_approach(at: Vector3) -> void:
	if realm == "city" and at.z < 1000.0:
		_ensure_collision(cell_at(bounds(at)))

func set_realm(next_realm: String) -> void:
	realm = next_realm
	if is_instance_valid(city):
		city.visible = realm == "city"
		rift.visible = realm == "rift"
		_set_lighting()

func set_hour(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	if is_instance_valid(sun):
		_set_lighting()

func quality_changed(preset: int) -> void:
	quality = clampi(preset, 0, 3)
	if materials.is_empty():
		return
	materials["asphalt"].set_shader_parameter("reflections", [0.35, 0.72, 0.95, 1.0][quality])
	materials["asphalt"].set_shader_parameter("material_detail", [0.0, 0.5, 1.0, 1.0][quality])
	materials["water"].set_shader_parameter("detail", [0.10, 0.36, 0.78, 1.0][quality])
	set_motion_scale(motion_scale)
	if is_instance_valid(train):
		train.visible = quality > 0
	for index in range(local_lights.size()):
		local_lights[index].visible = index < [0, 4, 6, 8][quality]
	if is_instance_valid(sky_material):
		sky_material.set_shader_parameter("cloud_detail",[0.0,0.6,1.0,1.0][quality])
	if is_instance_valid(sun):
		sun.shadow_enabled = quality >= 2
		sun.directional_shadow_max_distance = 85.0 if quality == 2 else 125.0
	for cell in chunks:
		_set_chunk_quality(cell,chunks[cell])


func _set_chunk_quality(cell: Vector2i, entry: Dictionary) -> void:
	var near := maxi(absi(cell.x - center_cell.x), absi(cell.y - center_cell.y))
	var details: Node3D = entry.get("details")
	var skyline: Node3D = entry.get("roof_detail")
	if is_instance_valid(details):
		details.visible = near <= [0,1,1,2][quality]
	if is_instance_valid(skyline):
		skyline.visible = quality>0 and near<=[0,0,1,2][quality]

func set_motion_scale(amount: float) -> void:
	motion_scale = clampf(amount, 0.0, 1.0)
	if materials.is_empty():
		return
	materials["water"].set_shader_parameter("motion", motion_scale * (0.34 if quality == 0 else 1.0))
	materials["phase"].set_shader_parameter("motion", motion_scale)
	materials["rift_floor"].set_shader_parameter("motion", motion_scale)

func water_at(pos: Vector3) -> bool:
	if pos.z > 1000.0 or not CANAL_BOUNDS.has_point(Vector2(pos.x, pos.z)):
		return false
	for bridge in BRIDGES:
		if absf(pos.z - bridge) <= 5.6:
			return false
	return true

func bounds(pos: Vector3) -> Vector3:
	if realm == "rift":
		return Vector3(clampf(pos.x, -42.4, 42.4), pos.y, clampf(pos.z, 1288.5, 1430.0))
	return Vector3(clampf(pos.x, -CITY_LIMIT_X, CITY_LIMIT_X), pos.y, clampf(pos.z, CITY_MIN_Z, CITY_MAX_Z))

func district_at(pos: Vector3) -> String:
	if realm == "rift" or pos.z > 1000.0:
		return "Speed Force Pocket"
	if pos.x < -82.0 and pos.z > -242.0 and pos.z < -67.0:
		return "South Canal"
	if pos.x > 79.0 and pos.z < -84.0 and pos.z > -277.0:
		return "Foundry Ward"
	if absf(pos.x) < 80.0 and pos.z > -236.0:
		return "Calder Exchange"
	if pos.z < -252.0:
		return "Meridian Heights"
	if pos.x > 105.0:
		return "East Market"
	return "Orchard Commons"

func cell_at(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x - ORIGIN.x) / CHUNK_SIZE), floori((pos.z - ORIGIN.y) / CHUNK_SIZE))

func _valid_cell(cell: Vector2i) -> bool:
	return cell.x >= -3 and cell.x <= 3 and cell.y >= -2 and cell.y <= 3

func _cell_z(cell: Vector2i) -> float:
	return ORIGIN.y + float(cell.y) * CHUNK_SIZE + CHUNK_SIZE * 0.5

func _make_road_graph() -> Dictionary:
	var graph := {"segments": {}, "junctions": {}}
	var x_lines := [-CITY_LIMIT_X] + THROUGH_STREETS + [CITY_LIMIT_X]
	var z_lines := [CITY_MAX_Z] + CROSS_STREETS + [CITY_MIN_Z]
	for z in CROSS_STREETS:
		for edge in range(x_lines.size() - 1):
			var first := Vector3(x_lines[edge], 0.0, z)
			var last := Vector3(x_lines[edge + 1], 0.0, z)
			_register_road(graph, first, last, 3.7, 7.2)
	for x in THROUGH_STREETS:
		for edge in range(z_lines.size() - 1):
			var first := Vector3(x, 0.0, z_lines[edge])
			var last := Vector3(x, 0.0, z_lines[edge + 1])
			_register_road(graph, first, last, 3.7, 8.5 if x == 0.0 else 7.2)
	for segment: Dictionary in graph["segments"].values():
		for lane: Dictionary in segment["lanes"]:
			var turns := PackedStringArray()
			for joining in graph["junctions"][lane["exit"]]["segments"]:
				if joining == segment["id"]:
					continue
				for successor: Dictionary in graph["segments"][joining]["lanes"]:
					if successor["entrance"] == lane["exit"]:
						turns.push_back(successor["id"])
			lane["permitted_turns"] = turns
	return graph

func _register_road(graph: Dictionary, first: Vector3, last: Vector3, lane_spacing: float, sidewalk: float) -> void:
	var first_id := _junction_key(first)
	var last_id := _junction_key(last)
	var id := "road/%s/%s" % [first_id, last_id]
	var direction := (last - first).normalized()
	var right := direction.cross(Vector3.UP)
	var tracks := []
	for side in [1.0, -1.0]:
		var reversed: bool = side < 0.0
		var entrance := last if reversed else first
		var exit := first if reversed else last
		var offset: Vector3 = right * lane_spacing * side
		var heading: Vector3 = direction * side
		tracks.push_back({"id": id + ("/backward" if reversed else "/forward"), "entrance": _junction_key(entrance), "exit": _junction_key(exit), "centre": PackedVector3Array([entrance + offset, exit + offset]), "stop": exit + offset - heading * (sidewalk + 1.6)})
	for key in [first_id, last_id]:
		var point := first if key == first_id else last
		if not graph["junctions"].has(key):
			graph["junctions"][key] = {"id": key, "position": point, "segments": [], "crossings": [], "signal": "signal/" + key}
		graph["junctions"][key]["segments"].push_back(id)
		graph["junctions"][key]["crossings"].push_back({"id": "crossing/%s/%s" % [key, id], "center": point + direction * (sidewalk if key == first_id else -sidewalk)})
	graph["segments"][id] = {"id": id, "district": district_at(first.lerp(last, 0.5)), "lanes": tracks, "sidewalk_half_width": sidewalk, "length": first.distance_to(last)}

func _junction_key(point: Vector3) -> String:
	return "%d,%d" % [roundi(point.x), roundi(point.z)]

func stats() -> Dictionary:
	return {"seed": seed, "generation_version": LAYOUT_VERSION, "resident": chunks.size(), "cap": MAX_CHUNKS, "collision_shapes": solid_count, "queued_collision": waiting.size(), "queued_visuals": visual_queue.size(), "built": cells_built, "district": district_at(Vector3(ORIGIN.x + (center_cell.x + 0.5) * CHUNK_SIZE, 0.0, _cell_z(center_cell)))}

func chunk_layout(cell: Vector2i) -> Array:
	var parcels := []
	if not _valid_cell(cell):
		return parcels
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + cell.x * 709607 + cell.y * 305111 + LAYOUT_VERSION * 17903
	if cell.x == 0:
		for original in course.get("buildings", []):
			var center := Vector3(float(original[0]), 0.0, float(original[1]))
			if cell_at(center) != cell or absf(center.x) < 10.0:
				continue
			var footprint := Vector2(float(original[2]), float(original[4]))
			if absf(center.x) >= 40.0 and center.z < -132.0 and center.z > -208.0:
				center.z = -149.0
				footprint.y = 26.0
			elif absf(center.x) >= 40.0 and center.z < -236.0:
				center.z = -247.0
				footprint.y = 24.0
			elif center.z > 20.0:
				center.z = 21.0
				footprint.y = 17.5
			elif is_equal_approx(center.z, -43.0):
				center.z = -39.0
				footprint.y = 19.3
			elif absf(center.x) > 40.0 and center.z > -95.0:
				footprint.y *= 0.74
			if center.z < -201.0 and center.z > -224.0:
				center.z = -207.5
				footprint.y = minf(footprint.y, 16.0)
			if absf(center.x) < 40.0 and center.z < -166.0 and center.z > -190.0:
				center.z = -194.0
				footprint.y = 15.0
			if _parcel_clear(center, footprint, true):
				parcels.push_back(_parcel(center, footprint, float(original[3]) * 0.68 + 4.0, int(original[5]), absf(center.x) < 32.0, parcels.size()))
	if cell.x == 0 and cell.y > 0:
		return parcels
	var start := ORIGIN + Vector2(cell) * CHUNK_SIZE
	for offset_z in [15.0, 40.0, 65.0, 91.0, 117.0]:
		for offset_x in [15.0, 43.0, 74.0, 107.0]:
			var center := Vector3(start.x + offset_x + rng.randf_range(-3.0, 3.0), 0.0, start.y + offset_z + rng.randf_range(-4.0, 4.0))
			var footprint := Vector2(rng.randf_range(13.0, 21.0), rng.randf_range(13.0, 21.0))
			if not _parcel_clear(center, footprint, false):
				continue
			var district := district_at(center)
			var height := rng.randf_range(13.0, 34.0)
			var material_index := rng.randi_range(0, 3)
			if district == "Foundry Ward" or district == "South Canal":
				height *= 0.58
				material_index = 2 if rng.randf() < 0.6 else 3
			elif district == "Meridian Heights":
				height *= 1.4
			elif district == "Orchard Commons" and rng.randf() < 0.4:
				continue
			parcels.push_back(_parcel(center, footprint, height, material_index, false, parcels.size()))
	return parcels

func _parcel(center: Vector3, footprint: Vector2, height: float, skin: int, is_shop: bool, slot: int) -> Dictionary:
	var cell := cell_at(center)
	return {"id": "parcel/%d/%d/%d" % [cell.x, cell.y, slot], "position": center, "size": Vector3(footprint.x, height, footprint.y), "skin": skin, "shop": is_shop}

func _parcel_clear(center: Vector3, footprint: Vector2, authored: bool) -> bool:
	var x := center.x
	var z := center.z
	if absf(x) > CITY_LIMIT_X + 32.0 or z < CITY_MIN_Z - 40.0 or z > CITY_MAX_Z + 40.0:
		return false
	if not authored and absf(x) < 31.0 and z > -324.0:
		return false
	var footprint_bounds := Rect2(Vector2(x - footprint.x * 0.5, z - footprint.y * 0.5), footprint)
	if footprint_bounds.intersects(Rect2(13.0, -457.0, 43.0, 112.0)) or footprint_bounds.intersects(Rect2(-149.0, -47.0, 43.0, 39.0)):
		return false
	if x > 98.0 - footprint.x * 0.5 and x < 180.0 + footprint.x * 0.5 and z < -100.0 + footprint.y * 0.5 and z > -247.0 - footprint.y * 0.5:
		return false
	if footprint_bounds.intersects(CANAL_BOUNDS.grow(7.0)):
		return false
	for street in CROSS_STREETS:
		var half_width := 8.7 if street in [-119.0, -226.0, -306.0] else 6.7
		if absf(z - street) < half_width + footprint.y * 0.5:
			return false
	for street in THROUGH_STREETS:
		if absf(x - street) < (10.0 if street == 0.0 else 7.2) + footprint.x * 0.5:
			return false
	return true

func _ensure_collision(cell: Vector2i) -> void:
	waiting.erase(cell)
	if not _valid_cell(cell) or chunks.has(cell):
		return
	if chunks.size() >= MAX_CHUNKS:
		var worst: Vector2i = cell
		var distance := 0.0
		for key in chunks.keys():
			var candidate: Vector2i = key
			var candidate_distance := Vector2(candidate - center_cell).length_squared()
			if candidate_distance > distance:
				worst = candidate
				distance = candidate_distance
		_remove_chunk(worst)
	var node := _node(city, "Parcel %d %d" % [cell.x, cell.y])
	var parcels := chunk_layout(cell)
	var building_boxes := []
	for parcel in parcels:
		var size: Vector3 = parcel["size"]
		building_boxes.push_back(_box(parcel["position"] + Vector3(0.0, size.y * 0.5, 0.0), size))
	if not building_boxes.is_empty():
		_solid_boxes(node, building_boxes, 1, "Building collision")
	chunks[cell] = {"node": node, "parcels": parcels, "shapes": building_boxes.size(), "drawn": false}
	visual_queue.push_back(cell)
	cells_built += 1

func _ensure_visuals(cell: Vector2i) -> void:
	if not chunks.has(cell) or chunks[cell]["drawn"]:
		return
	visual_queue.erase(cell)
	var entry: Dictionary = chunks[cell]
	var node: Node3D = entry["node"]
	var parcels: Array = entry["parcels"]
	var buildings := [[], [], [], []]
	var trim := []
	var rooftop := []
	var roof_tanks := []
	var roof_antennas := []
	var roof_glints := []
	var shops := []
	var windows := []
	var amber_panels := []
	var limestone := []
	var glazed_canopies := []
	var details := _node(node, "Street level architecture")
	var roof_detail := _node(node, "Building trim")
	for parcel in parcels:
		var pos: Vector3 = parcel["position"]
		var size: Vector3 = parcel["size"]
		var skin: int = parcel["skin"]
		var roof_y := size.y
		var style_hash := posmod(roundi(absf(pos.x) * 13.0 + absf(pos.z) * 29.0), 12)
		buildings[skin].push_back(_box(pos + Vector3(0.0, roof_y * 0.5, 0.0), size))
		# Parapet cornice and belt courses
		trim.push_back(_box(pos + Vector3(0.0, roof_y + 0.14, 0.0), Vector3(size.x + 0.56, 0.48, size.z + 0.56)))
		trim.push_back(_box(pos + Vector3(0.0, 3.85, 0.0), Vector3(size.x + 0.30, 0.28, size.z + 0.32)))
		if roof_y > 16.0:
			trim.push_back(_box(pos + Vector3(0.0, roof_y * 0.62, 0.0), Vector3(size.x + 0.24, 0.22, size.z + 0.24)))
		# Multi-tier architectural setbacks and rooftop equipment
		if roof_y > 19.5 and style_hash % 2 == 0:
			var tier_h := clampf(roof_y * 0.20, 3.2, 6.8)
			var tier_size := Vector3(size.x * 0.68, tier_h, size.z * 0.66)
			buildings[skin].push_back(_box(pos + Vector3(0.0, roof_y + tier_h * 0.5, 0.0), tier_size))
			trim.push_back(_box(pos + Vector3(0.0, roof_y + tier_h + 0.12, 0.0), Vector3(tier_size.x + 0.38, 0.34, tier_size.z + 0.38)))
			rooftop.push_back(_box(pos + Vector3(0.0, roof_y + tier_h + 0.78, 0.0), Vector3(tier_size.x * 0.46, 1.35, tier_size.z * 0.42)))
			if roof_y > 26.0:
				var spire_h := 4.4 + float(style_hash % 4) * 1.1
				roof_antennas.push_back(_box(pos + Vector3(0.0, roof_y + tier_h + 1.4 + spire_h * 0.5, 0.0), Vector3(0.22, spire_h, 0.22)))
				roof_glints.push_back(_box(pos + Vector3(0.0, roof_y + tier_h + 1.45 + spire_h, 0.0), Vector3(0.36, 0.26, 0.36)))
		else:
			rooftop.push_back(_box(pos + Vector3(-size.x * 0.14, roof_y + 0.88, -size.z * 0.12), Vector3(size.x * 0.42, 1.55, size.z * 0.34)))
			rooftop.push_back(_box(pos + Vector3(size.x * 0.18, roof_y + 0.52, size.z * 0.14), Vector3(size.x * 0.24, 0.82, size.z * 0.22)))
			if style_hash % 3 == 0:
				roof_tanks.push_back(_box(pos + Vector3(size.x * 0.22, roof_y + 1.45, -size.z * 0.18), Vector3(1.65, 2.1, 1.65)))
			if roof_y > 24.0 and style_hash % 4 == 1:
				roof_antennas.push_back(_box(pos + Vector3(-size.x * 0.16, roof_y + 3.4, 0.0), Vector3(0.18, 4.6, 0.18)))
				roof_glints.push_back(_box(pos + Vector3(-size.x * 0.16, roof_y + 5.75, 0.0), Vector3(0.32, 0.24, 0.32)))
		if not parcel["shop"]:
			continue
		var facing := -signf(pos.x)
		var edge := pos.x + facing * size.x * 0.5
		var shop_slot := posmod(roundi(-pos.z * 0.17) + (3 if facing < 0.0 else 0), SHOP_NAMES.size())
		var sign_color := [Color("efb16d"), Color("f6cf99"), Color("e5cf9e"), Color("80d2ef"), Color("8ed9c4"), Color("ffce83"), Color("b4dce7"), Color("f0a681")]
		shops.push_back(_box(Vector3(edge + facing * 0.04, 1.91, pos.z), Vector3(0.26, 3.75, size.z - 0.30)))
		limestone.push_back(_box(Vector3(edge + facing * 0.19, 0.37, pos.z), Vector3(0.27, 0.64, size.z - 0.21)))
		limestone.push_back(_box(Vector3(edge + facing * 0.21, 3.64, pos.z), Vector3(0.43, 0.25, size.z - 0.21)))
		for shop_door in [-1.0, 0.0, 1.0]:
			var shop_z: float = pos.z + shop_door * (size.z - 2.6) * 0.30
			var pane_width := minf(5.7, size.z * 0.23)
			windows.push_back(_box(Vector3(edge + facing * 0.23, 1.79, shop_z), Vector3(0.15, 2.36, pane_width)))
			var illuminated: bool = shop_door != 0.0 or shop_slot % 2 == 0
			if illuminated:
				amber_panels.push_back(_box(Vector3(edge + facing * 0.32, 2.58, shop_z), Vector3(0.05, 0.10, pane_width - 0.27)))
				amber_panels.push_back(_box(Vector3(edge + facing * 0.31, 1.1, shop_z - pane_width * 0.15), Vector3(0.06, 0.28, pane_width * 0.52)))
			for mullion in [-1.0, 0.0, 1.0]:
				shops.push_back(_box(Vector3(edge + facing * 0.34, 1.79, shop_z + mullion * pane_width * 0.49), Vector3(0.13, 2.45, 0.08)))
			shops.push_back(_box(Vector3(edge + facing * 0.35, 2.19, shop_z), Vector3(0.15, 0.085, pane_width + 0.06)))
		var setback := minf(0.8, maxf(absf(edge) - 10.8, 0.1))
		glazed_canopies.push_back(_box(Vector3(edge + facing * (setback * 0.5 + 0.2), 3.12, pos.z), Vector3(setback + 0.34, 0.13, minf(size.z - 0.8, 11.5))))
		var text_pos := Vector3(edge + facing * 0.46, 3.43, pos.z)
		_label(details, SHOP_NAMES[shop_slot], text_pos, Vector3(0.0, facing * 90.0, 0.0), sign_color[shop_slot], 0.635, 310)
	for skin in range(buildings.size()):
		var b_node := _batch(node, buildings[skin], facade[skin], "Masonry %d" % skin)
		if is_instance_valid(b_node):
			b_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_batch(roof_detail, trim, materials["cornice"], "Cornices")
	_batch(roof_detail, rooftop, materials["roof"], "Roof structures")
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 0.5
	tank_mesh.bottom_radius = 0.5
	tank_mesh.height = 1.0
	tank_mesh.radial_segments = 10
	_batch(roof_detail, roof_tanks, materials["stone"], "Rooftop water tanks", tank_mesh)
	_batch(roof_detail, roof_antennas, materials["metal"], "Rooftop spires")
	_batch(roof_detail, roof_glints, materials["red"], "Rooftop beacons")
	_batch(details, shops, materials["wood"], "Shop doors and frames")
	_batch(details, windows, materials["shop_window"], "Shop windows")
	_batch(details, amber_panels, materials["shop_lamps"], "Lit shop shelving")
	_batch(details, limestone, materials["stone"], "Shop fascia")
	_batch(details, glazed_canopies, materials["canopy"], "Shop canopies")
	entry["details"] = details
	entry["roof_detail"] = roof_detail
	entry["drawn"] = true
	_set_chunk_quality(cell,entry)

func _remove_chunk(cell: Vector2i) -> void:
	if not chunks.has(cell):
		return
	visual_queue.erase(cell)
	var node: Node3D = chunks[cell]["node"]
	solid_count -= int(chunks[cell]["shapes"])
	city.remove_child(node)
	node.queue_free()
	chunks.erase(cell)

func _create_materials() -> void:
	materials["asphalt"] = _shader(ASPHALT)
	materials["water"] = _shader(WATER)
	materials["phase"] = _shader(PHASE)
	var walls := [Color("747681"), Color("82756d"), Color("7b6663"), Color("66727a")]
	var glass := [Color("3e6076"), Color("32667b"), Color("66565a"), Color("3a6172")]
	var light := [Color("ebae62"), Color("e9ca8e"), Color("e9a95b"), Color("77c3cc")]
	for i in range(walls.size()):
		var mat := _shader(FACADE)
		mat.set_shader_parameter("mortar", walls[i])
		mat.set_shader_parameter("tint", glass[i])
		mat.set_shader_parameter("window_light", light[i])
		mat.set_shader_parameter("bay", Vector2([2.28, 1.85, 2.07, 2.65][i], [3.14, 3.4, 2.88, 3.35][i]))
		facade.push_back(mat)
	materials["cornice"] = _mat("83868b", 0.88)
	materials["roof"] = _mat("535967", 0.92)
	materials["wood"] = _mat("243039", 0.81)
	materials["shop_window"] = _shader(STOREFRONT)
	materials["shop_lamps"] = _mat("c99b5e", 0.48, "f9b369", 0.39)
	materials["stone"] = _mat("8c8280", 0.83)
	materials["canopy"] = _mat("394d55", 0.41, "406575", 0.09)
	materials["sidewalk"] = _mat("535860", 0.87)
	materials["paver"] = _mat("67636a", 0.86)
	materials["curb"] = _mat("a39d9a", 0.80)
	materials["metal"] = _mat("404d5c", 0.56)
	materials["rail"] = _mat("6a737e", 0.45)
	materials["white"] = _mat("a9adad", 0.84, "87a5b6", 0.18)
	materials["yellow"] = _mat("cb9c48", 0.76, "d98e37", 0.20)
	materials["amber"] = _mat("ffd292", 0.45, "ffb35f", 1.25)
	materials["cyan"] = _mat("71d1e9", 0.39, "5fdbfc", 1.24)
	materials["red"] = _mat("b94554", 0.46, "f24b47", 0.80)
	materials["leaf"] = _mat("395851", 0.93)
	materials["leaf_light"] = _mat("4b6758", 0.94)
	materials["wood_dark"] = _mat("55473f", 0.86)
	materials["backdrop"] = _mat("3c465a", 0.85, "45526d", 0.12)
	materials["rift_floor"] = _shader(RIFT_FLOOR)
	materials["rift_trim"] = _mat("576f97", 0.60, "647db0", 0.28)
	materials["rift_blue"] = _mat("7bebea", 0.46, "75efff", 1.35)
	materials["rift_pink"] = _mat("cb82ff", 0.52, "be63ff", 0.89)
	materials["crate"] = _mat("849096", 0.72)
	materials["brick"] = _mat("735a56", 0.90)
	materials["park_surface"] = _mat("495954", 0.94)
	materials["train_body"] = _mat("b2b7c5", 0.48)
	materials["train_stripe"] = _mat("476c88", 0.65)
	materials["train_glass"] = _mat("294255", 0.40, "699bac", 0.45)
	materials["hydrant"] = _mat("a9342c", 0.48)
	var shadow_mat := _shader(CONTACT_SHADOW)
	shadow_mat.set_shader_parameter("opacity", 0.48)
	materials["contact_shadow"] = shadow_mat
	quality_changed(quality)

func _create_lighting() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "City atmosphere"
	add_child(env_node)
	atmosphere = Environment.new()
	atmosphere.background_mode = Environment.BG_SKY
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.fog_enabled = true
	atmosphere.fog_mode = Environment.FOG_MODE_DEPTH
	atmosphere.fog_depth_begin = 110.0
	atmosphere.fog_depth_end = 420.0
	atmosphere.fog_density = 0.01
	atmosphere.fog_depth_curve = 1.26
	atmosphere.fog_sky_affect = 0.065
	sky_material = _shader(SKY)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	atmosphere.sky = sky
	env_node.environment = atmosphere
	sun = DirectionalLight3D.new()
	sun.name = "Dusk key light"
	sun.rotation_degrees = Vector3(-30.0, -40.0, 0.0)
	sun.shadow_enabled = quality >= 2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 95.0
	sun.shadow_bias = 0.045
	sun.shadow_normal_bias = 1.25
	sun.shadow_opacity = 0.58
	add_child(sun)

func _set_lighting() -> void:
	if realm == "rift":
		sky_material.set_shader_parameter("zenith", Color("29254b"))
		sky_material.set_shader_parameter("haze", Color("71538e"))
		sky_material.set_shader_parameter("soft_cloud", Color("9d668c"))
		sky_material.set_shader_parameter("celestial", 0.22)
		sky_material.set_shader_parameter("daylight", 0.0)
		sun.light_color = Color("b193e8")
		sun.light_energy = 0.39
		atmosphere.ambient_light_color = Color("a9bbec")
		atmosphere.ambient_light_energy = 0.84
		atmosphere.fog_light_color = Color("675990")
		atmosphere.fog_depth_begin = 44.0
		atmosphere.fog_depth_end = 220.0
		return
	var daylight := smoothstep(-0.20, 0.38, cos((time_of_day - 12.0) * TAU / 24.0))
	sky_material.set_shader_parameter("zenith", Color("182e56").lerp(Color("4b7fb3"), daylight))
	sky_material.set_shader_parameter("haze", Color("91636a").lerp(Color("94b8d0"), daylight))
	sky_material.set_shader_parameter("soft_cloud", Color("bb805f").lerp(Color("c0cbd1"), daylight))
	sky_material.set_shader_parameter("celestial", 1.0)
	sky_material.set_shader_parameter("daylight", daylight)
	sun.light_color = Color("ffcf99").lerp(Color("fff0d9"), daylight)
	sun.light_energy = lerpf(0.44, 1.02, daylight)
	atmosphere.ambient_light_color = Color("9fafde").lerp(Color("dde7f3"), daylight)
	atmosphere.ambient_light_energy = lerpf(0.74, 0.97, daylight)
	atmosphere.fog_light_color = Color("6b647b").lerp(Color("a2b1c4"), daylight)
	atmosphere.fog_depth_begin = 89.0
	atmosphere.fog_depth_end = 410.0
	for shader in facade:
		shader.set_shader_parameter("lamps", lerpf(0.90, 0.22, daylight))
	materials["asphalt"].set_shader_parameter("wetness", lerpf(0.95, 0.54, daylight))

func _node(parent: Node, label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	return node

func _shader(resource: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = resource
	return material

func _mat(base: String, roughness: float, glow := "", power := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(base)
	mat.roughness = roughness
	if not glow.is_empty():
		mat.emission_enabled = true
		mat.emission = Color(glow)
		mat.emission_energy_multiplier = power
	return mat

func _box(center: Vector3, size: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled_local(size), center)

func _batch(parent: Node3D, items: Array, material: Material, label: String, mesh: Mesh = null) -> MultiMeshInstance3D:
	if items.is_empty():
		return null
	var model := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh if mesh != null else block_mesh
	multimesh.instance_count = items.size()
	for i in range(items.size()):
		multimesh.set_instance_transform(i, items[i])
	model.name = label
	model.multimesh = multimesh
	model.material_override = material
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(model)
	return model

func _solid_boxes(parent: Node3D, items: Array, layer: int, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = 0
	for item: Transform3D in items:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = item.basis.get_scale()
		collision.shape = shape
		collision.transform = item.orthonormalized()
		body.add_child(collision)
	parent.add_child(body)
	solid_count += items.size()
	return body

func _label(parent: Node3D, title: String, where: Vector3, rotation: Vector3, color: Color, height: float, distance: float) -> void:
	var label := Label3D.new()
	label.text = title
	label.font_size = 96
	label.pixel_size = height / 96.0
	label.outline_size = 4
	label.outline_modulate = Color("182032")
	label.modulate = color
	label.position = where
	label.rotation_degrees = rotation
	label.visibility_range_end = distance
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)

func _lamp(parent: Node3D, where: Vector3, color: Color, distance: float, energy: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Local fixture light"
	lamp.position = where
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = distance
	lamp.omni_attenuation = 1.35
	lamp.shadow_enabled = false
	parent.add_child(lamp)
	local_lights.push_back(lamp)

func _build_city() -> void:
	var ground := [_box(Vector3(0.0, -0.42, -213.5), Vector3(636.0, 0.84, 605.0))]
	_batch(city, ground, materials["asphalt"], "Wet road network")
	_solid_boxes(city, ground, 1, "City floor")
	var streets := _node(city, "Calder Avenue")
	var sidewalks := []
	var edging := []
	var paving := []
	var white_marking := []
	var gold_marking := []
	var iron := []
	var signal_cases := []
	var lamp_bulbs := []
	var stop_bulbs := []
	var trees := []
	var trees_crown := []
	var trunks := []
	var benches := []
	var road_service := []
	var hydrants := []
	var ground_shadows := []
	var sidewalk_colliders := []
	for direction in [-1.0, 1.0]:
		for span in [Vector2(-519.0, -496.5), Vector2(-477.5, -407.5), Vector2(-388.5, -315.5), Vector2(-296.5, -235.5), Vector2(-216.5, -185.7), Vector2(-168.4, -128.5), Vector2(-109.5, -64.4), Vector2(-47.5, 28.6), Vector2(45.5, 84.0)]:
			var length: float = span.y - span.x
			var z: float = (span.y + span.x) * 0.5
			sidewalks.push_back(_box(Vector3(direction * 11.25, 0.030, z), Vector3(5.5, 0.06, length)))
			edging.push_back(_box(Vector3(direction * 8.55, 0.053, z), Vector3(0.22, 0.101, length)))
			if z > -320.0:
				var point: float = span.x + 1.2
				while point < span.y - 0.5:
					paving.push_back(_box(Vector3(direction * 11.18, 0.061, point), Vector3(5.12, 0.011, 0.046)))
					point += 2.0
		for z in [24.0, 12.0, -4.0, -16.0, -35.0, -68.0, -97.0, -137.0, -161.0, -200.0, -243.0, -270.0, -292.0, -327.0, -362.0, -409.0, -450.0, -495.0]:
			var x: float = direction * 9.25
			iron.push_back(_box(Vector3(x, 2.65, z), Vector3(0.115, 5.25, 0.115)))
			iron.push_back(_box(Vector3(x, 0.22, z), Vector3(0.34, 0.43, 0.34)))
			iron.push_back(_box(Vector3(x - direction * 0.7, 5.19, z), Vector3(1.64, 0.12, 0.10)))
			iron.push_back(_box(Vector3(x - direction * 1.46, 5.08, z), Vector3(0.58, 0.23, 0.36)))
			lamp_bulbs.push_back(_box(Vector3(x - direction * 1.46, 4.95, z), Vector3(0.46, 0.052, 0.27)))
		for z in [3.0, -8.0, -24.0, -37.0, -72.0, -98.0, -137.0, -203.0]:
			road_service.push_back(_box(Vector3(direction * 8.24, 0.032, z), Vector3(0.39, 0.042, 0.79)))
			for bar in range(5):
				road_service.push_back(_box(Vector3(direction * 8.24, 0.043, z - 0.31 + float(bar) * 0.15), Vector3(0.47, 0.042, 0.049)))
		for z in [6.0, -34.0, -80.0, -148.0, -214.0]:
			var hx: float = direction * 9.05
			hydrants.push_back(_box(Vector3(hx, 0.38, z), Vector3(0.24, 0.68, 0.24)))
			hydrants.push_back(_box(Vector3(hx, 0.56, z), Vector3(0.34, 0.14, 0.14)))
			iron.push_back(_box(Vector3(hx, 0.75, z), Vector3(0.26, 0.08, 0.26)))
			ground_shadows.push_back(_box(Vector3(hx, 0.068, z), Vector3(0.65, 1.0, 0.65)))
		for z in [16.5, -23.0, -29.0, -72.0, -89.0, -105.7, -138.0, -152.0, -209.0, -252.0, -280.0, -342.0, -369.0]:
			var x: float = direction * 12.5
			var rot := fposmod(absf(z) * 0.37, TAU)
			trunks.push_back(_box(Vector3(x, 1.55, z), Vector3(0.27, 3.0, 0.27), rot))
			# Primary branching limbs
			trunks.push_back(Transform3D(Basis(Vector3.UP, rot).rotated(Vector3.FORWARD, 0.42).scaled_local(Vector3(0.14, 1.35, 0.14)), Vector3(x + direction * 0.36, 2.85, z + 0.15)))
			trunks.push_back(Transform3D(Basis(Vector3.UP, rot + 1.9).rotated(Vector3.FORWARD, -0.38).scaled_local(Vector3(0.13, 1.25, 0.13)), Vector3(x - direction * 0.30, 2.95, z - 0.22)))
			paving.push_back(_box(Vector3(x, 0.072, z), Vector3(1.82, 0.032, 1.82)))
			edging.push_back(_box(Vector3(x, 0.12, z), Vector3(1.94, 0.11, 1.94)))
			ground_shadows.push_back(_box(Vector3(x, 0.088, z), Vector3(4.2, 1.0, 4.2)))
			# Layered multi-cluster canopy (deep base + bright crown)
			trees.push_back(_box(Vector3(x, 3.35, z), Vector3(2.45, 1.72, 2.55), rot))
			trees.push_back(_box(Vector3(x + direction * 0.72, 3.15, z + 0.66), Vector3(1.62, 1.38, 1.58), rot + 0.8))
			trees.push_back(_box(Vector3(x - direction * 0.65, 3.28, z - 0.58), Vector3(1.58, 1.35, 1.66), rot + 1.7))
			trees_crown.push_back(_box(Vector3(x + direction * 0.22, 4.28, z - 0.18), Vector3(1.92, 1.48, 1.88), rot + 0.4))
			trees_crown.push_back(_box(Vector3(x - direction * 0.42, 3.92, z + 0.56), Vector3(1.42, 1.22, 1.45), rot + 2.1))
		for z in [10.0, -27.0, -92.4, -146.0, -212.0, -256.0]:
			benches.push_back(_box(Vector3(direction * 11.98, 0.55, z), Vector3(0.56, 0.11, 2.25)))
			benches.push_back(_box(Vector3(direction * 12.24, 0.83, z), Vector3(0.13, 0.52, 2.25)))
			iron.push_back(_box(Vector3(direction * 11.98, 0.27, z - 0.82), Vector3(0.49, 0.47, 0.10)))
			iron.push_back(_box(Vector3(direction * 11.98, 0.27, z + 0.82), Vector3(0.49, 0.47, 0.10)))
			iron.push_back(_box(Vector3(direction * 11.92, 0.44, z + 1.68), Vector3(0.46, 0.76, 0.46)))
			ground_shadows.push_back(_box(Vector3(direction * 12.0, 0.068, z), Vector3(1.2, 1.0, 2.7)))
		for intersection in CROSS_STREETS:
			var gap := 7.5 if intersection not in [-119.0, -226.0, -306.0] else 8.8
			var cross_z: float = intersection + direction * gap
			for stripe in range(15):
				white_marking.push_back(_box(Vector3(float(stripe) * 1.10 - 7.7, 0.027, cross_z), Vector3(0.41, 0.024, 2.1)))
			white_marking.push_back(_box(Vector3(direction * 4.39, 0.023, cross_z + direction * 2.26), Vector3(7.42, 0.022, 0.24)))
			if intersection in [-119.0, -226.0]:
				continue
			var sx: float = direction * 8.28
			iron.push_back(_box(Vector3(sx, 2.64, cross_z + direction * 1.2), Vector3(0.14, 5.24, 0.14)))
			iron.push_back(_box(Vector3(sx - direction * 1.9, 5.02, cross_z + direction * 1.2), Vector3(3.98, 0.12, 0.12)))
			var signal_pos := Vector3(sx - direction * 3.81, 4.62, cross_z + direction * 1.2)
			signal_cases.push_back(_box(signal_pos, Vector3(0.41, 0.96, 0.30)))
			stop_bulbs.push_back(_box(signal_pos + Vector3(0.0, 0.31, direction * 0.18), Vector3(0.23, 0.21, 0.07)))
			lamp_bulbs.push_back(_box(signal_pos + Vector3(0.0, 0.0, direction * 0.18), Vector3(0.23, 0.21, 0.07)))
			# Corner sidewalk safety bollards
			for b_off in [-0.6, 0.5]:
				iron.push_back(_box(Vector3(direction * 8.95, 0.42, cross_z + direction * (1.8 + b_off)), Vector3(0.14, 0.82, 0.14)))
	for stripe in range(16):
		white_marking.push_back(_box(Vector3(float(stripe) * 1.02 - 7.65, 0.022, -5.6), Vector3(0.46, 0.018, 2.55)))
	for z in range(-516, 82, 7):
		if _near_crossing(z, 11.0) or absi(z + 5) < 3:
			continue
		gold_marking.push_back(_box(Vector3(-0.125, 0.017, z), Vector3(0.13, 0.014, 3.26)))
		gold_marking.push_back(_box(Vector3(0.125, 0.017, z), Vector3(0.13, 0.014, 3.26)))
		for lane in [-4.42, 4.42]:
			white_marking.push_back(_box(Vector3(lane, 0.018, z), Vector3(0.083, 0.014, 2.32)))
	for transverse in CROSS_STREETS:
		for x in range(-308, 309, 8):
			if _near_through(x, 10.25) or water_at(Vector3(x, 0.0, transverse)):
				continue
			gold_marking.push_back(_box(Vector3(x, 0.021, transverse), Vector3(2.34, 0.020, 0.13)))
		for x in THROUGH_STREETS:
			if x == 0.0 or water_at(Vector3(x, 0.0, transverse)):
				continue
			for side in [-1.0, 1.0]:
				for stripe in range(11):
					white_marking.push_back(_box(Vector3(x + side * 7.8, 0.026, transverse + float(stripe - 5) * 1.09), Vector3(1.5, 0.017, 0.37)))
	for x in THROUGH_STREETS:
		if x == 0.0:
			continue
		for z in range(-507, 82, 8):
			if _near_crossing(z, 10.0) or water_at(Vector3(x, 0.0, z)):
				continue
			gold_marking.push_back(_box(Vector3(x, 0.021, z), Vector3(0.13, 0.022, 2.45)))
	_batch(streets, sidewalks, materials["sidewalk"], "Raised street sidewalks")
	_batch(streets, edging, materials["curb"], "Calder kerbs")
	_batch(streets, paving, materials["paver"], "Pavement seams and tree wells")
	_batch(streets, white_marking, materials["white"], "Crosswalks and white paint")
	_batch(streets, gold_marking, materials["yellow"], "Amber lane paint")
	_batch(streets, iron, materials["metal"], "Lamp posts and signal furniture")
	_batch(streets, signal_cases, materials["wood"], "Traffic signal housings")
	_batch(streets, lamp_bulbs, materials["amber"], "Warm street fixtures")
	_batch(streets, stop_bulbs, materials["red"], "Stop signal lenses")
	_batch(streets, benches, materials["wood_dark"], "Slatted benches")
	_batch(streets, hydrants, materials["hydrant"], "Street hydrants")
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.36
	trunk_mesh.bottom_radius = 0.54
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 8
	var trunk_node := _batch(streets, trunks, materials["wood_dark"], "Street tree trunks", trunk_mesh)
	if is_instance_valid(trunk_node):
		trunk_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_batch(streets, road_service, materials["metal"], "Street drainage grilles")
	var canopy := SphereMesh.new()
	canopy.radial_segments = 10
	canopy.rings = 6
	var canopy_base := _batch(streets, trees, materials["leaf"], "Street trees", canopy)
	var canopy_top := _batch(streets, trees_crown, materials["leaf_light"], "Street tree crowns", canopy)
	if is_instance_valid(canopy_base):
		canopy_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if is_instance_valid(canopy_top):
		canopy_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(1.0, 1.0)
	_batch(streets, ground_shadows, materials["contact_shadow"], "Street contact shadows", shadow_plane)
	for item in sidewalks:
		var placement: Transform3D = item
		if placement.origin.z > -330.0:
			sidewalk_colliders.push_back(placement)
	_solid_boxes(streets, sidewalk_colliders, 1, "Raised sidewalks")
	_lamp(streets, Vector3(-7.7, 4.8, -4.0), Color("ffb16e"), 18.0, 1.18)
	_lamp(streets, Vector3(7.7, 4.8, -4.0), Color("9ecde7"), 16.0, 1.08)
	_lamp(streets, Vector3(-7.7, 4.8, -16.0), Color("ffd09a"), 16.0, 1.09)
	_lamp(streets, Vector3(7.7, 4.8, -16.0), Color("ffd5ae"), 16.0, 1.08)
	_lamp(streets, Vector3(-7.7, 4.8, -35.0), Color("ffb683"), 15.0, 1.14)
	_lamp(streets, Vector3(7.6, 4.8, -35.0), Color("8bbcd4"), 15.0, 0.98)
	_lamp(streets, Vector3(-5.4, 5.1, -54.0), Color("ffd19d"), 12.0, 1.05)
	_lamp(streets, Vector3(5.4, 5.1, -54.0), Color("a3d6e8"), 12.0, 0.95)
	_build_stations()
	_build_canal()
	_build_foundry()
	_build_city_landmarks()
	_build_meridian()
	_build_orchard()
	_build_skyline()

func _near_crossing(z: float, margin: float) -> bool:
	for crossing in CROSS_STREETS:
		if absf(z - crossing) < margin:
			return true
	return false

func _near_through(x: float, margin: float) -> bool:
	for street in THROUGH_STREETS:
		if absf(x - street) < margin:
			return true
	return false

func _build_stations() -> void:
	var stations := _node(city, "Calder Exchange Elevated")
	var concrete := []
	var detailing := []
	var lights := []
	var glazings := []
	var signage := []
	var ground_collision := []
	for z in [-54.2, -177.0]:
		concrete.push_back(_box(Vector3(0.0, 6.03, z), Vector3(382.0, 0.80, 5.3)))
		ground_collision.push_back(_box(Vector3(0.0, 6.03, z), Vector3(382.0, 0.80, 5.3)))
		for x in [-164.0, -133.0, -109.6, -78.9, -48.0, -31.6, -11.4, 11.4, 29.9, 54.0, 82.0, 104.0, 132.0, 162.0]:
			var support := _box(Vector3(x, 2.94, z), Vector3(1.12, 5.92, 1.39))
			if z < -160.0 and absf(x + 146.0) < 39.0:
				continue
			concrete.push_back(support)
			ground_collision.push_back(support)
			concrete.push_back(_box(Vector3(x, 0.36, z), Vector3(1.55, 0.72, 1.86)))
			detailing.push_back(_box(Vector3(x, 4.92, z), Vector3(1.88, 0.34, 1.72)))
		for side in [-1.0, 1.0]:
			detailing.push_back(_box(Vector3(0.0, 6.52, z + side * 2.26), Vector3(379.0, 0.27, 0.24)))
			detailing.push_back(_box(Vector3(0.0, 6.19, z + side * 2.62), Vector3(380.0, 0.23, 0.14)))
			for x in range(-47, 50, 4):
				detailing.push_back(_box(Vector3(x, 7.36, z + side * 2.42), Vector3(0.19, 1.72, 0.17)))
				detailing.push_back(_box(Vector3(x + 1.91, 8.24, z + side * 2.42), Vector3(3.95, 0.14, 0.21)))
				glazings.push_back(_box(Vector3(x + 1.97, 7.04, z + side * 2.41), Vector3(3.73, 0.68, 0.055)))
				lights.push_back(_box(Vector3(x + 1.97, 7.95, z + side * 2.46), Vector3(3.52, 0.060, 0.074)))
			for x in range(-177, 178, 6):
				lights.push_back(_box(Vector3(x, 5.58, z + side * 1.79), Vector3(2.44, 0.073, 0.13)))
			signage.push_back(_box(Vector3(0.0, 5.56, z + side * 2.89), Vector3(16.4, 1.2, 0.16)))
			var name_plate := "CALDER EXCHANGE  ·  NORTHLINE" if z > -100.0 else "MARKET LINE  ·  SOUTH CANAL"
			_label(stations, name_plate, Vector3(0.0, 5.55, z + side * 2.99), Vector3(0.0, 0.0 if side > 0.0 else 180.0, 0.0), Color("edcda3"), 0.71, 270.0)
	_batch(stations, concrete, materials["stone"], "Elevated viaduct and columns")
	_batch(stations, detailing, materials["rail"], "Rail girders and enclosure")
	_batch(stations, glazings, materials["train_glass"], "Station enclosure glass")
	_batch(stations, lights, materials["amber"], "Rail safety and underpass lighting")
	_batch(stations, signage, materials["wood"], "Station name plaques")
	_solid_boxes(stations, ground_collision, 1, "Viaduct collision")
	train = _node(stations, "Northline train")
	train.position = Vector3(-24.0, 0.0, -54.05)
	train_time = 164.0
	var shells := []
	var train_stripes := []
	var train_windows := []
	for car in range(5):
		var car_x := float(car) * 7.25
		shells.push_back(_box(Vector3(car_x, 7.56, 0.0), Vector3(6.78, 1.93, 3.19)))
		train_stripes.push_back(_box(Vector3(car_x, 6.78, 0.0), Vector3(6.81, 0.25, 3.24)))
		for window in range(4):
			var x := car_x - 2.28 + float(window) * 1.52
			for side in [-1.0, 1.0]:
				train_windows.push_back(_box(Vector3(x, 7.74, side * 1.607), Vector3(1.12, 0.56, 0.036)))
	_batch(train, shells, materials["train_body"], "Train shells")
	_batch(train, train_stripes, materials["train_stripe"], "Northline stripe")
	_batch(train, train_windows, materials["train_glass"], "Train windows")
	train.visible = quality > 0

func _build_canal() -> void:
	var canal := _node(city, "South Canal waterfront")
	_batch(canal, [_box(Vector3(-146.0, 0.027, -135.5), Vector3(71.98, 0.038, 120.98))], materials["water"], "Working canal surface")
	var quay := []
	var rail := []
	var lamps := []
	var chalk := []
	var freight := []
	var bridges := []
	var grounded := []
	for x in [-187.4, -104.5]:
		quay.push_back(_box(Vector3(x, 0.055, -135.5), Vector3(10.4, 0.10, 120.5)))
		for z in [-187.0, -163.0, -151.0, -128.0, -98.0, -81.0]:
			var edge: float = -182.0 if x < -140.0 else -110.0
			var sign: float = signf(x - edge)
			rail.push_back(_box(Vector3(edge + sign * 1.22, 0.63, z), Vector3(0.20, 1.24, 0.20)))
			lamps.push_back(_box(Vector3(edge + sign * 1.22, 1.22, z), Vector3(0.20, 0.14, 0.20)))
			if absf(z + 141.0) > 16.0 and absf(z + 119.0) > 17.0 and absf(z + 177.0) > 12.0:
				var bank := _box(Vector3(x + sign * 4.8, 1.12, z), Vector3(3.0, 2.17, 5.2))
				freight.push_back(bank)
				grounded.push_back(bank)
	for z in BRIDGES:
		var bridge := _box(Vector3(-146.0, 0.036, z), Vector3(77.0, 0.132, 11.2))
		bridges.push_back(bridge)
		grounded.push_back(bridge)
		for side in [-1.0, 1.0]:
			var edge: float = z + side * 5.43
			var guard := _box(Vector3(-146.0, 0.67, edge), Vector3(74.9, 1.16, 0.15))
			grounded.push_back(guard)
			rail.push_back(_box(Vector3(-146.0, 1.18, edge), Vector3(75.7, 0.10, 0.13)))
			rail.push_back(_box(Vector3(-146.0, 0.47, edge), Vector3(75.7, 0.10, 0.09)))
			for x in range(-182, -109, 4):
				rail.push_back(_box(Vector3(x, 0.69, edge), Vector3(0.12, 1.04, 0.12)))
				if x % 8 == 2:
					lamps.push_back(_box(Vector3(x, 1.21, edge), Vector3(0.12, 0.09, 0.12)))
		for x in range(-182, -109, 6):
			chalk.push_back(_box(Vector3(x, 0.114, z), Vector3(2.48, 0.012, 0.11)))
	for plank in range(4):
		for x in [-178.8, -112.5]:
			var direction := signf(-146.0 - x)
			var t := float(plank)
			var step_box := _box(Vector3(x - direction * t * 0.61, 0.067 + t * 0.045, -141.0), Vector3(0.63, 0.092 + t * 0.08, 6.4))
			quay.push_back(step_box)
			grounded.push_back(step_box)
			for z in [-144.3, -137.7]:
				lamps.push_back(_box(Vector3(x - direction * t * 0.61, 0.136 + t * 0.09, z), Vector3(0.51, 0.08, 0.11)))
	for post in [-193.0, -100.35]:
		var plaque := _box(Vector3(post, 2.39, -124.7), Vector3(7.15, 1.25, 0.18))
		quay.push_back(plaque)
		quay.push_back(_box(Vector3(post - 2.97, 1.08, -124.7), Vector3(0.23, 2.68, 0.28)))
		quay.push_back(_box(Vector3(post + 2.97, 1.08, -124.7), Vector3(0.23, 2.68, 0.28)))
		_label(canal, "SOUTH CANAL", Vector3(post, 2.41, -124.58), Vector3.ZERO, Color("7cddd9"), 0.81, 185.0)
		_label(canal, "SOUTH CANAL", Vector3(post, 2.41, -124.82), Vector3(0.0, 180.0, 0.0), Color("7cddd9"), 0.81, 185.0)
	_batch(canal, quay, materials["stone"], "Quay and water exits")
	_batch(canal, bridges, materials["rail"], "Bridge decks")
	_batch(canal, rail, materials["metal"], "Bridge guard rails")
	_batch(canal, lamps, materials["cyan"], "Canal guide lights")
	_batch(canal, chalk, materials["yellow"], "Bridge center stripes")
	_batch(canal, freight, materials["crate"], "Canal freight")
	_solid_boxes(canal, grounded, 1, "Bridge and quay collision")
	var sense := Area3D.new()
	sense.name = "Water strip"
	sense.collision_layer = 16
	sense.collision_mask = 0
	sense.monitoring = false
	for interval in [Vector2(-196.0, -182.6), Vector2(-171.4, -124.6), Vector2(-113.4, -75.0)]:
		var marker := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(72.0, 1.0, interval.y - interval.x)
		marker.shape = box
		marker.position = Vector3(-146.0, 0.15, interval.x + box.size.z * 0.5)
		sense.add_child(marker)
	canal.add_child(sense)

func _build_foundry() -> void:
	var foundry := _node(city, "Foundry Ward relay yard")
	var concrete := []
	var steel := []
	var brass := []
	var reds := []
	var cyan := []
	var solids := []
	for z in [-107.0, -143.0, -167.0, -201.0, -243.3]:
		for x in [91.0, 181.0]:
			var side: float = signf(x - 145.0)
			var shed := _box(Vector3(x, 3.62, z), Vector3(12.3, 7.24, 14.3))
			concrete.push_back(shed)
			solids.push_back(shed)
			steel.push_back(_box(Vector3(x, 7.28, z), Vector3(12.68, 0.24, 14.7)))
			steel.push_back(_box(Vector3(x - side * 6.17, 1.75, z), Vector3(0.14, 3.50, 6.3)))
			reds.push_back(_box(Vector3(x - side * 6.29, 4.08, z), Vector3(0.115, 0.14, 3.12)))
			for stripe in range(6):
				brass.push_back(_box(Vector3(x - side * 6.49, 0.02, z + float(stripe - 3) * 0.85), Vector3(0.56, 0.024, 0.25), 0.64))
	for z in [-150.0, -188.8, -229.5]:
		for x in [127.0, 172.0]:
			var column := _box(Vector3(x, 3.50, z), Vector3(1.07, 7.0, 1.12))
			steel.push_back(column)
			solids.push_back(column)
			cyan.push_back(_box(Vector3(x, 5.45, z + 0.58), Vector3(0.74, 0.17, 0.09)))
		steel.push_back(_box(Vector3(149.5, 7.0, z), Vector3(44.95, 0.43, 0.60)))
		brass.push_back(_box(Vector3(149.5, 0.025, z), Vector3(44.9, 0.02, 0.19)))
	for x in [127.5, 168.5]:
		for z in [-218.0, -205.0, -193.0]:
			var crate := _box(Vector3(x, 0.69, z), Vector3(3.7, 1.37, 2.19))
			steel.push_back(crate)
			solids.push_back(crate)
			reds.push_back(_box(Vector3(x, 1.26, z + 1.11), Vector3(3.38, 0.065, 0.07)))
	var arena_housing := _box(Vector3(148.0, 2.49, -236.3), Vector3(11.75, 5.0, 3.52))
	steel.push_back(arena_housing)
	solids.push_back(arena_housing)
	cyan.push_back(_box(Vector3(148.0, 4.92, -234.50), Vector3(10.7, 0.09, 0.09)))
	_label(foundry, "RELAY YARD", Vector3(148.0, 3.87, -234.51), Vector3.ZERO, Color("93c2d4"), 1.12, 260.0)
	var district_sign := _box(Vector3(144.5, 5.78, -128.52), Vector3(21.0, 1.45, 0.17))
	steel.push_back(district_sign)
	for x in [134.6, 154.5]:
		var post := _box(Vector3(x, 2.75, -128.54), Vector3(0.28, 5.6, 0.28))
		steel.push_back(post)
		solids.push_back(post)
	_label(foundry, "FOUNDRY WARD  ·  SECTOR 04", Vector3(144.5, 5.82, -128.41), Vector3.ZERO, Color("e6b083"), 0.93, 240.0)
	_batch(foundry, concrete, materials["brick"], "Foundry sheds")
	_batch(foundry, steel, materials["metal"], "Foundry steelwork and relay")
	_batch(foundry, brass, materials["yellow"], "Foundry safety lines")
	_batch(foundry, reds, materials["red"], "Foundry warning lamps")
	_batch(foundry, cyan, materials["cyan"], "Relay yard lights")
	_solid_boxes(foundry, solids, 1, "Foundry architecture")
	_phase_wall(foundry, Vector3(115.0, 2.34, -119.0), "01")
	_phase_wall(foundry, Vector3(142.0, 2.34, -180.0), "02")

func _phase_wall(parent: Node3D, position_at: Vector3, tag: String) -> void:
	var phase := _node(parent, "Phase Lock " + tag)
	phase.position = position_at
	var center := _box(Vector3.ZERO, Vector3(0.45, 4.67, 15.6))
	var structure := []
	var edge_lights := []
	for edge in [-7.85, 7.85]:
		structure.push_back(_box(Vector3(0.0, 0.13, edge), Vector3(1.06, 4.92, 0.47)))
		edge_lights.push_back(_box(Vector3(-0.57, 0.13, edge), Vector3(0.09, 4.61, 0.10)))
	structure.push_back(_box(Vector3(0.0, 2.43, 0.0), Vector3(1.06, 0.35, 16.3)))
	_batch(phase, [center], materials["phase"], "Tagged phase membrane")
	_batch(phase, structure, materials["metal"], "Barrier frame")
	_batch(phase, edge_lights, materials["cyan"], "Phase lock shaft lights")
	var phase_body := _solid_boxes(phase, [center], 4, "Phaseable membrane")
	phase_body.add_to_group("phaseable")
	phase_bodies.push_back(phase_body)
	_solid_boxes(phase, structure, 1, "Phase lock frame")
	_label(phase, "PHASE TRANSIT  /  " + tag, Vector3(-0.59, 1.62, 0.0), Vector3(0.0, -90.0, 0.0), Color("b2edf2"), 0.64, 155.0)

func _build_city_landmarks() -> void:
	var landmarks := _node(city, "Exchange landmarks")
	var stone := []
	var rail := []
	var lamps := []
	var greenery := []
	var collision := []
	var glass := []
	for side in [-1.0, 1.0]:
		var x: float = side * 13.42
		for z in [5.25, -36.25, -156.0, -281.0]:
			var planter := _box(Vector3(x, 0.24, z), Vector3(1.22, 0.44, 3.46))
			stone.push_back(planter)
			collision.push_back(planter)
			greenery.push_back(_box(Vector3(x, 0.55, z), Vector3(1.05, 0.38, 3.25)))
		if side > 0.0:
			var shelter_x := 11.2
			stone.push_back(_box(Vector3(shelter_x, 0.10, -7.8), Vector3(2.45, 0.06, 6.8)))
			rail.push_back(_box(Vector3(shelter_x, 2.82, -7.8), Vector3(2.54, 0.18, 6.60)))
			lamps.push_back(_box(Vector3(shelter_x, 2.71, -7.8), Vector3(2.08, 0.04, 0.12)))
			for z in [-10.95, -4.65]:
				rail.push_back(_box(Vector3(shelter_x + 1.14, 1.4, z), Vector3(0.12, 2.82, 0.13)))
			glass.push_back(_box(Vector3(shelter_x + 1.16, 1.67, -7.8), Vector3(0.07, 0.99, 6.35)))
			_label(landmarks, "NORTHLINE  ·  N4", Vector3(shelter_x, 2.61, -4.44), Vector3.ZERO, Color("c7eced"), 0.33, 100.0)
		var monument := _box(Vector3(side * 13.05, 1.57, -305.0), Vector3(2.5, 3.13, 3.33))
		stone.push_back(monument)
		collision.push_back(monument)
		rail.push_back(_box(Vector3(side * 12.62, 4.53, -304.5), Vector3(2.34, 2.95, 2.42)))
		lamps.push_back(_box(Vector3(side * 11.44, 4.98, -304.5), Vector3(0.08, 1.33, 2.08)))
		rail.push_back(_box(Vector3(side * 8.0, 6.24, -304.5), Vector3(10.0, 0.36, 2.43)))
		lamps.push_back(_box(Vector3(side * 7.2, 5.98, -303.17), Vector3(9.4, 0.13, 0.07)))
	_label(landmarks, "MERIDIAN HEIGHTS", Vector3(0.0, 6.29, -303.2), Vector3.ZERO, Color("cbe3ed"), 1.02, 320.0)
	for z in [-262.0, -281.0, -299.0]:
		for x in [4.2, 5.25, 6.30]:
			lamps.push_back(_box(Vector3(x, 0.031, z - (x - 4.2) * 0.37), Vector3(0.69, 0.022, 0.10), 0.55))
	var portal_plinth := _box(Vector3(0.0, 0.029, -289.0), Vector3(7.5, 0.066, 4.2))
	stone.push_back(portal_plinth)
	lamps.push_back(_box(Vector3(0.0, 0.072, -286.87), Vector3(7.49, 0.06, 0.12)))
	lamps.push_back(_box(Vector3(0.0, 0.072, -291.13), Vector3(7.49, 0.06, 0.12)))
	for sign_side in [-1.0, 1.0]:
		var x: float = sign_side * 13.39
		var z: float = -2.4 if sign_side < 0.0 else -18.7
		rail.push_back(_box(Vector3(x, 5.05, z), Vector3(1.45, 3.02, 0.22)))
		rail.push_back(_box(Vector3(x + sign_side * 0.57, 5.05, z), Vector3(0.9, 0.12, 0.29)))
		for edge in [-1.0, 1.0]:
			lamps.push_back(_box(Vector3(x + edge * 0.70, 5.05, z + 0.14), Vector3(0.04, 2.82, 0.055)))
		var sign_text := "B\nO\nO\nK\nS" if sign_side < 0.0 else "H\nO\nT\nE\nL"
		_label(landmarks, sign_text, Vector3(x, 5.05, z + 0.15), Vector3.ZERO, Color("ffcc91"), 0.34, 140.0)
	_batch(landmarks, stone, materials["stone"], "Plazas and thresholds")
	_batch(landmarks, rail, materials["metal"], "Transit shelters and arch")
	_batch(landmarks, lamps, materials["cyan"], "Route markers")
	_batch(landmarks, glass, materials["train_glass"], "Shelter glass")
	_batch(landmarks, greenery, materials["leaf_light"], "Calder planters")
	_solid_boxes(landmarks, collision, 1, "Landmark collision")

func _build_meridian() -> void:
	var meridian := _node(city, "Meridian Heights promenade")
	var roof := []
	var rail := []
	var light := []
	var guide := []
	var solids := []
	for z in range(-450, -345, 3):
		var bend := 23.0 + sin((z + 401.0) * 0.052) * 8.0
		for side in [-1.0, 1.0]:
			var position_at := Vector3(bend + side * 4.4, 0.036, z)
			guide.push_back(_box(position_at, Vector3(0.146, 0.045, 1.72)))
	var deck := _box(Vector3(42.0, 3.58, -414.0), Vector3(7.0, 0.35, 30.0))
	roof.push_back(deck)
	solids.push_back(deck)
	for ramp in [Vector2(-399.0, -381.0), Vector2(-429.0, -447.0)]:
		var pitch := atan2(3.76, ramp.y - ramp.x)
		if pitch > PI * 0.5:
			pitch -= PI
		var direction := Basis(Vector3.RIGHT, pitch)
		var size := Vector3(7.0, 0.23, Vector2(ramp.y - ramp.x, 3.76).length())
		var platform := Transform3D(direction.scaled_local(size), Vector3(42.0, 1.77, lerpf(ramp.x, ramp.y, 0.5)))
		roof.push_back(platform)
		solids.push_back(platform)
		for side in [-1.0, 1.0]:
			var gutter := Transform3D(direction.scaled_local(Vector3(0.13, 0.10, size.z - 0.20)), platform.origin + Vector3(side * 3.42, 0.18, 0.0))
			light.push_back(gutter)
	for x in [39.1, 44.9]:
		for z in [-402.0, -416.0, -427.0]:
			var pier := _box(Vector3(x, 1.88, z), Vector3(0.85, 3.77, 0.96))
			rail.push_back(pier)
			solids.push_back(pier)
		light.push_back(_box(Vector3(x, 3.80, -414.0), Vector3(0.11, 0.14, 29.2)))
	_label(meridian, "OBSERVATION DECK", Vector3(42.0, 4.53, -420.0), Vector3.ZERO, Color("c5e8ed"), 0.56, 180.0)
	_batch(meridian, roof, materials["stone"], "Meridian deck and accessible ramps")
	_batch(meridian, rail, materials["metal"], "Meridian structural piers")
	_batch(meridian, light, materials["cyan"], "Deck guide rails")
	_batch(meridian, guide, materials["white"], "Meridian S-bend markers")
	_solid_boxes(meridian, solids, 1, "Meridian deck collision")

func _build_orchard() -> void:
	var orchard := _node(city, "Orchard Commons green")
	var turf := []
	var paths := []
	var trees := []
	var trees_deep := []
	var bark := []
	var orchard_shadows := []
	var solids := []
	for x in [-137.3, -116.4]:
		turf.push_back(_box(Vector3(x, 0.034, -28.0), Vector3(16.6, 0.067, 31.0)))
		for z in [-37.0, -27.5, -17.0]:
			var trunk := _box(Vector3(x, 1.57, z), Vector3(0.42, 3.12, 0.42), 0.10)
			bark.push_back(trunk)
			solids.push_back(trunk)
			orchard_shadows.push_back(_box(Vector3(x, 0.08, z), Vector3(6.2, 1.0, 6.2)))
			trees_deep.push_back(_box(Vector3(x, 3.72, z), Vector3(4.95, 2.85, 4.45)))
			trees.push_back(_box(Vector3(x + 1.22, 4.34, z + 0.58), Vector3(3.65, 2.65, 3.18)))
			trees.push_back(_box(Vector3(x - 1.05, 4.45, z - 0.62), Vector3(3.15, 2.38, 2.96)))
	paths.push_back(_box(Vector3(-126.8, 0.045, -28.0), Vector3(4.08, 0.085, 37.0)))
	paths.push_back(_box(Vector3(-126.8, 0.049, -28.0), Vector3(42.4, 0.091, 3.45)))
	paths.push_back(_box(Vector3(-126.8, 1.28, -10.6), Vector3(6.6, 0.95, 0.18)))
	_label(orchard, "ORCHARD COMMONS", Vector3(-126.8, 1.31, -10.47), Vector3.ZERO, Color("d0d6b2"), 0.57, 150.0)
	var canopy := SphereMesh.new()
	canopy.radial_segments = 10
	canopy.rings = 6
	var orchard_trunk := CylinderMesh.new()
	orchard_trunk.top_radius = 0.36
	orchard_trunk.bottom_radius = 0.54
	orchard_trunk.height = 1.0
	orchard_trunk.radial_segments = 8
	var orchard_shadow_plane := PlaneMesh.new()
	orchard_shadow_plane.size = Vector2(1.0, 1.0)
	_batch(orchard, turf, materials["park_surface"], "Orchard turf")
	_batch(orchard, paths, materials["paver"], "Public paths and nameplate")
	_batch(orchard, bark, materials["wood_dark"], "Orchard trunks", orchard_trunk)
	_batch(orchard, trees_deep, materials["leaf"], "Orchard lower canopies", canopy)
	_batch(orchard, trees, materials["leaf_light"], "Orchard canopies", canopy)
	_batch(orchard, orchard_shadows, materials["contact_shadow"], "Orchard shadows", orchard_shadow_plane)
	_solid_boxes(orchard, solids, 1, "Orchard trunk collision")

func _build_skyline() -> void:
	var skyline := _node(city, "Distant city silhouettes")
	var stone := []
	var glints := []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7109
	for side in [-1.0, 1.0]:
		for z in range(-590, 139, 34):
			var height := rng.randf_range(26.0, 67.0)
			var x: float = side * rng.randf_range(339.0, 385.0)
			stone.push_back(_box(Vector3(x, height * 0.5, z), Vector3(rng.randf_range(12.0, 24.0), height, rng.randf_range(13.0, 25.0))))
			if height > 51.0:
				stone.push_back(_box(Vector3(x, height + 2.56, z), Vector3(0.69, 5.6, 0.69)))
				glints.push_back(_box(Vector3(x, height + 5.48, z), Vector3(0.92, 0.28, 0.92)))
	for x in range(-345, 350, 23):
		var height := rng.randf_range(24.0, 97.0)
		var z := rng.randf_range(-574.0, -535.0)
		stone.push_back(_box(Vector3(x, height * 0.5, z), Vector3(rng.randf_range(12.0, 19.0), height, rng.randf_range(13.0, 25.0))))
		if height > 74.0:
			stone.push_back(_box(Vector3(x, height + 3.18, z), Vector3(0.69, 6.8, 0.69)))
			glints.push_back(_box(Vector3(x, height + 6.72, z), Vector3(0.92, 0.28, 0.92)))
	_batch(skyline, stone, materials["backdrop"], "Distant urban silhouettes")
	_batch(skyline, glints, materials["red"], "Aircraft warning glints")

func _build_rift() -> void:
	var platform := _box(Vector3(0.0, -0.45, RIFT_Z), Vector3(86.0, 0.89, 144.0))
	var floors := [platform]
	var solids := [platform]
	var platforms := []
	var stripes := []
	var guide := []
	var mystery := []
	var outlying := []
	var shards := CylinderMesh.new()
	shards.top_radius = 0.02
	shards.bottom_radius = 0.5
	shards.radial_segments = 4
	shards.rings = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed - 9147
	for side in [-1.0, 1.0]:
		var x: float = side * 42.82
		var boundary := _box(Vector3(x, 0.21, RIFT_Z), Vector3(0.48, 0.42, 144.0))
		platforms.push_back(boundary)
		solids.push_back(boundary)
		for z in range(1290, 1431, 3):
			guide.push_back(_box(Vector3(x - side * 0.29, 0.08, z), Vector3(0.12, 0.072, 1.9)))
		for z in range(1290, 1431, 11):
			var yaw := rng.randf_range(-0.32, 0.32)
			var tip := rng.randf_range(2.4, 8.2)
			var pillar := _box(Vector3(side * rng.randf_range(26.0, 38.0), tip * 0.51, z), Vector3(rng.randf_range(1.4, 3.6), tip, rng.randf_range(1.5, 4.4)), yaw)
			platforms.push_back(pillar)
			solids.push_back(pillar)
			mystery.push_back(_box(pillar.origin + Vector3(0.0, tip * 0.5 + 0.08, 0.0), Vector3(1.22, 0.15, 1.62), yaw))
		for z in range(1280, 1440, 7):
			var axis := Vector3(rng.randf_range(-1.0, 1.0), 1.0, rng.randf_range(-1.0, 1.0)).normalized()
			var sharp := Basis(axis, rng.randf_range(-0.55, 0.55)).scaled_local(Vector3(rng.randf_range(3.0, 8.0), rng.randf_range(10.0, 24.0), rng.randf_range(3.0, 7.0)))
			outlying.push_back(Transform3D(sharp, Vector3(side * rng.randf_range(48.0, 69.0), rng.randf_range(-1.0, 17.0), z)))
	for z in range(1290, 1431, 4):
		var drift: float = sin((z - 1348.0) / 8.2) * 7.7 if z >= 1348 and z < 1410 else 0.0
		for edge in [-1.0, 1.0]:
			guide.push_back(_box(Vector3(drift + edge * 2.6, 0.012, z), Vector3(0.21, 0.033, 1.74), edge * 0.18))
			stripes.push_back(_box(Vector3(drift + edge * 5.06, 0.011, z), Vector3(0.065, 0.030, 2.34)))
	for gate in [Vector3(0.0, 0.0, 1317.0), Vector3(7.0, 0.0, 1356.0), Vector3(-8.0, 0.0, 1381.0)]:
		for x in [-5.5, 5.5]:
			var post := _box(gate + Vector3(x, 2.51, 0.0), Vector3(0.68, 5.26, 0.87))
			platforms.push_back(post)
			solids.push_back(post)
			guide.push_back(_box(gate + Vector3(x - signf(x) * 0.37, 2.51, 0.0), Vector3(0.099, 4.91, 0.12)))
		platforms.push_back(_box(gate + Vector3(0.0, 5.03, 0.0), Vector3(10.62, 0.63, 0.83)))
		guide.push_back(_box(gate + Vector3(0.0, 4.68, 0.0), Vector3(10.35, 0.097, 0.16)))
		stripes.push_back(_box(gate + Vector3(0.0, 0.024, 0.0), Vector3(10.3, 0.038, 0.16)))
	_label(rift, "RETURN ANCHOR", Vector3(0.0, 5.23, 1317.47), Vector3.ZERO, Color("d1efff"), 0.62, 190.0)
	_label(rift, "SPEED FORCE  /  CROSSING I", Vector3(7.0, 5.2, 1356.45), Vector3.ZERO, Color("c6ebee"), 0.48, 190.0)
	_label(rift, "CROSSING II", Vector3(-8.0, 5.2, 1381.45), Vector3.ZERO, Color("c6ebee"), 0.49, 190.0)
	_batch(rift, floors, materials["rift_floor"], "Rift floor")
	_batch(rift, platforms, materials["rift_trim"], "Rift structures")
	_batch(rift, stripes, materials["rift_pink"], "Rift route boundaries")
	_batch(rift, guide, materials["rift_blue"], "Rift path markers")
	_batch(rift, mystery, materials["rift_pink"], "Rift obelisk lights")
	_batch(rift, outlying, materials["rift_trim"], "Suspended Rift shards", shards)
	_solid_boxes(rift, solids, 1, "Rift platforms and rail collision")
