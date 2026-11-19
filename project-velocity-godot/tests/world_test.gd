extends SceneTree

const World = preload("res://systems/world.gd")
var failure_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world: Node3D = World.new()
	root.add_child(world)
	world.setup(root)
	await physics_frame
	await physics_frame
	var spawn := Vector3(0.0, 0.0, 8.0)
	var phase_entry := Vector3(104.0, 0.0, -119.0)
	var east_bank := Vector3(-97.0, 0.0, -119.0)
	for point in [spawn, Vector3(0, 0, -30), Vector3(0, 0, -113), Vector3(0, 0, -148), Vector3(0, 0, -202), phase_entry, east_bank, Vector3(148, 0, -201)]:
		world.prepare_destination(point)
		await physics_frame
		await physics_frame
		var floor_hit := _ray(point + Vector3.UP * 0.5, point + Vector3.DOWN * 0.3, 1)
		_check(not floor_hit.is_empty() and absf(floor_hit["position"].y) < 0.13, "walkable ground at %s" % point)
	var phase_exit := Vector3(128.0, 0.95, -119.0)
	var phase_ray_start := phase_entry + Vector3.UP * 0.95
	var phase_hit := _ray(phase_ray_start, phase_exit, 1 | 4)
	_check(not phase_hit.is_empty() and phase_hit["collider"].is_in_group("phaseable"), "phase lock has a tagged physical barrier")
	_check(_ray(phase_ray_start, phase_exit, 1).is_empty(), "phase path is clear when mask 4 is disabled")
	_check(_ray(Vector3(0, 0.95, 8), Vector3(0, 0.95, -210), 1).is_empty(), "main story corridor is unobstructed")
	_check(_ray(Vector3(20.0, 0.95, -222.0), Vector3(148.0, 0.95, -222.0), 1).is_empty(), "eastern pursuit road is clear")
	for segment: Dictionary in world.road_graph["segments"].values():
		var lanes: Array = segment["lanes"]
		_check(lanes.size() == 2 and lanes[0]["entrance"] == lanes[1]["exit"], "segment %s has both directions" % segment["id"])
		for lane: Dictionary in lanes:
			var exit: Dictionary = world.road_graph["junctions"][lane["exit"]]
			_check(lane["permitted_turns"].size() == exit["segments"].size() - 1, "junction %s has linked turns" % lane["exit"])
	var meridian_point := Vector3(42.0, 0.0, -414.0)
	var resident_center: Vector2i = world.center_cell
	world.prefetch_approach(meridian_point)
	_check(world.center_cell == resident_center and world.chunks.has(world.cell_at(meridian_point)), "approach prefetch keeps the active center")
	var deck_hit := _ray(meridian_point + Vector3.UP * 5.0, meridian_point + Vector3.UP * 2.0, 1)
	_check(not deck_hit.is_empty() and deck_hit["position"].y > 3.5, "Meridian promenade has real rooftop floor")
	for z in [-389.0, -438.0]:
		var ramp := Vector3(42.0, 0.0, z)
		var ramp_hit := _ray(ramp + Vector3.UP * 4.0, ramp + Vector3.UP * 0.5, 1)
		_check(not ramp_hit.is_empty() and ramp_hit["position"].y > 1.0, "Meridian route has a grounded ramp at %s" % z)
	for bridge_z in [-119.0, -177.0]:
		_check(not world.water_at(Vector3(-146.0, 0.0, bridge_z)), "dry crossing at z=%s" % bridge_z)
		_check(_ray(Vector3(-103.0, 0.75, bridge_z), Vector3(-191.0, 0.75, bridge_z), 1).is_empty(), "open bridge travel at z=%s" % bridge_z)
	_check(world.water_at(Vector3(-146.0, 0.0, -141.0)), "water-run strip detected")
	_check(not world.water_at(east_bank), "walkable bank stays dry")
	_check(_ray(Vector3(-146.0, 0.25, -136.0), Vector3(-146.0, 0.25, -151.0), 16, true).size() > 0 or _ray(Vector3(-200.0, 0.25, -141.0), Vector3(-146.0, 0.25, -141.0), 16, true).size() > 0, "water strip exposes layer 16")
	world.set_realm("rift")
	_check(world.district_at(Vector3(0.0, 0.0, 1360.0)) == "Speed Force Pocket", "Rift has its own district")
	for point in [Vector3(0, 0, 1360), Vector3(0, 0, 1317), Vector3(7, 0, 1356), Vector3(-8, 0, 1381)]:
		_check(not _ray(point + Vector3.UP, point + Vector3.DOWN * 0.4, 1).is_empty(), "Rift floor at route point %s" % point)
	_check(world.bounds(Vector3(80.0, 0.0, 1400.0)).x < 43.0, "Rift travel bounds are separate")
	world.set_realm("city")
	var visited := [Vector3(250, 0, -437), Vector3(-250, 0, -437), Vector3(-250, 0, 10), Vector3(245, 0, 10), Vector3(151, 0, -205), spawn]
	var preserved := {}
	for point: Vector3 in visited:
		var cell: Vector2i = world.cell_at(point)
		preserved[cell] = JSON.stringify(world.chunk_layout(cell)).sha256_text()
		world.prepare_destination(point)
		for frame in range(20):
			world.step(0.034, point)
		_check(world.stats()["resident"] <= world.stats()["cap"], "streaming respects resident cap at %s" % point)
	visited.reverse()
	for point: Vector3 in visited:
		var cell: Vector2i = world.cell_at(point)
		world.prepare_destination(point)
		_check(preserved[cell] == JSON.stringify(world.chunk_layout(cell)).sha256_text(), "parcel geometry stable in reverse visit at %s" % cell)
	world.quality_changed(0)
	_check(not world.train.visible, "low preset skips moving train")
	world.quality_changed(3)
	_check(world.train.visible, "high preset shows train")
	world.set_motion_scale(0.0)
	var train_x: float = world.train.position.x
	world.step(0.23, spawn)
	_check(is_equal_approx(world.train.position.x, train_x), "reduced motion pauses the set dressing train")
	world.set_hour(14.0)
	var daytime: float = world.sun.light_energy
	world.set_hour(1.0)
	_check(world.sun.light_energy < daytime, "day cycle changes lighting energy")
	print("WORLD_TEST_%s seed=%d resident=%d cap=%d parcels_built=%d" % ["PASS" if failure_count == 0 else "FAIL", world.seed, world.stats()["resident"], world.stats()["cap"], world.stats()["built"]])
	quit(1 if failure_count else 0)

func _ray(from: Vector3, to: Vector3, mask: int, areas := false) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = areas
	return root.world_3d.direct_space_state.intersect_ray(query)

func _check(value: bool, detail: String) -> void:
	if not value:
		failure_count += 1
		push_error(detail)
