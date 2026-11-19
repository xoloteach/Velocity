extends Node3D
## Closed-road time trial. Only forward gate crossings count; course records are separate.

const START := Vector3(0, 0, 8)
const GATES := [
	Vector3(0,0,-18), Vector3(0,0,-52), Vector3(0,0,-84), Vector3(0,0,-119),
	Vector3(-47,0,-119), Vector3(-96,0,-119), Vector3(-145,0,-119), Vector3(-201,0,-119),
	Vector3(-201,0,-146), Vector3(-201,0,-177), Vector3(-146,0,-177), Vector3(-99,0,-177),
]
const TURNS := {3:"LEFT ONTO THE BRIDGE", 7:"RIGHT AT THE JUNCTION", 9:"RIGHT ONTO THE BRIDGE"}
const GOLD := 14.0
const SILVER := 20.0
const BRONZE := 29.0
const ICE := Color("6ff7f1")
const PINK := Color("ff9edf")
const LIME := Color("deff87")
const WHITE := Color("f4f1ff")
const NAVY := Color("151632")
const GATE_WIDTH := 5.0
var game
var running := false
var go := false
var count := 3.0
var elapsed := 0.0
var gate := 0
var splits: Array[float] = []
var previous_splits: Array = []
var delta := 0.0
var finish_grade := ""
var new_best := false
var pad_time := 0.0
var pad_cue := 0.0
var _last := START
var _ring: Node3D
var _gates: Array[Node3D] = []
var _pads: Dictionary = {}
var _pad_nodes: Dictionary = {}
var _player: AudioStreamPlayer
var _tones: Array[AudioStreamWAV] = []
var _box := BoxMesh.new()
var _batches: Dictionary = {}


func setup(owner) -> void:
	game = owner
	visible = false
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	_player.volume_db = -14.0
	add_child(_player)
	for pitch in [442.0, 659.0, 880.0]:
		_tones.append(_tone(pitch))


func begin() -> void:
	if _gates.is_empty():
		_build()
	visible = true
	running = true
	go = false
	count = 3.0
	elapsed = 0.0
	gate = 0
	splits.clear()
	previous_splits = game.progress.midnight_splits.duplicate()
	delta = 0.0
	finish_grade = ""
	new_best = false
	pad_time = 0.0
	pad_cue = 0.0
	_last = game.runner.position
	game.world.set_circuit_lighting(true)
	_target()
	_beep(0)


func end() -> void:
	if running:
		game.world.set_circuit_lighting(false)
		_player.stop()
	running = false
	visible = false


func hold(dt: float) -> bool:
	if not running:
		return false
	if count > 0.0:
		var last := ceili(count)
		count = maxf(0.0, count - dt)
		if ceili(count) != last:
			_beep(2 if count == 0.0 else 0)
		return true
	return not finish_grade.is_empty()


func step(dt: float, at: Vector3) -> void:
	if not running or count > 0.0 or not finish_grade.is_empty():
		return
	go = elapsed < .72
	pad_time = maxf(0.0, pad_time - dt)
	pad_cue = maxf(0.0, pad_cue - dt)
	if at.distance_to(_last) > 5.0:
		_last = at
		elapsed += dt
		return
	var dir := direction(gate)
	var pad: Vector3 = _pads.get(gate, Vector3.INF)
	if pad.is_finite() and _cross_fraction(_last, at, pad, dir, 2.35, 1.15) >= 0.0:
		pad_time = .95
		pad_cue = 1.35
		_pad_nodes[gate].hide()
		_pads.erase(gate)
		game.circuit_burst(dir)
	var crossing := _cross_fraction(_last, at, GATES[gate], dir, GATE_WIDTH, 3.4)
	_last = at
	if crossing >= 0.0:
		var split := elapsed + dt * crossing
		splits.append(split)
		delta = split - float(previous_splits[gate]) if previous_splits.size() == GATES.size() else 0.0
		gate += 1
		_beep(1)
		game.pulse("goal", at, 0.85)
		if gate == GATES.size():
			elapsed = split
			_finish()
			return
		_target()
	elapsed += dt


func direction(i: int) -> Vector3:
	var prev: Vector3 = GATES[i-1] if i > 0 else START
	return (GATES[i] - prev).normalized()


func _cross_fraction(from: Vector3, to: Vector3, point: Vector3, dir: Vector3, width: float, height: float) -> float:
	var a := (from - point).dot(dir)
	var b := (to - point).dot(dir)
	if a >= 0.0 or b < 0.0:
		return -1.0
	var t := -a / (b - a)
	var contact := from.lerp(to, t) - point
	return t if absf(contact.dot(dir.cross(Vector3.UP))) <= width and contact.y >= -.15 and contact.y <= height else -1.0


func _finish() -> void:
	go = false
	pad_time = 0.0
	finish_grade = "GOLD" if elapsed <= GOLD else "SILVER" if elapsed <= SILVER else "BRONZE" if elapsed <= BRONZE else "FINISHER"
	game.runner.velocity = Vector3.ZERO
	game.speed = 0.0
	game.boosting = false
	new_best = game.progress.record_midnight(splits)
	game.objective_text = "Finished in %s" % format_time(elapsed)
	_ring.hide()
	_beep(2)


func _target() -> void:
	for i in range(_gates.size()):
		_gates[i].visible = i >= gate - 1
	for i in _pad_nodes:
		_pad_nodes[i].visible = i >= gate
	if gate == 0:
		_pads.clear()
		for i in _pad_nodes:
			_pads[i] = _pad_nodes[i].position
	_ring.position = GATES[gate]
	_ring.rotation.y = _yaw(direction(gate))
	_ring.show()
	game.target_position = GATES[gate]
	game.objective_text = "Gate %02d of %02d" % [gate+1, GATES.size()]


static func format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "—"
	var hundredths := floori(seconds * 100.0 + .00001)
	return "%02d:%02d.%02d" % [hundredths / 6000, (hundredths / 100) % 60, hundredths % 100]


func _build() -> void:
	var ice := _mat(ICE)
	var pink := _mat(PINK)
	var lime := _mat(LIME)
	var navy := _mat(NAVY)
	_ring = Node3D.new()
	_ring.name = "Active gate brackets"
	add_child(_ring)
	for side in [-1, 1]:
		_block(_ring, Vector3(side*5,1.8,.14), Vector3(.16,3.60,.12), lime)
		_block(_ring, Vector3(side*4.22,3.58,.14), Vector3(1.63,.14,.12), lime)
		_block(_ring, Vector3(side*4.22,.21,.14), Vector3(1.63,.085,.12), lime)
	for i in range(GATES.size()):
		var dir := direction(i)
		var is_finish := i == GATES.size() - 1
		var is_turn := TURNS.has(i)
		var root := Node3D.new()
		root.position = GATES[i]
		root.rotation.y = _yaw(dir)
		add_child(root)
		_gates.append(root)
		var accent := pink if is_turn else lime if is_finish else ice
		for side in [-1, 1]:
			_block(root, Vector3(side*5.12,1.8,0), Vector3(.46,3.60,.42), navy)
			_block(root, Vector3(side*5.12,1.81,.23), Vector3(.13,3.53,.08), accent)
			_block(root, Vector3(side*5.12,.18,0), Vector3(.82,.36,.87), navy)
		_block(root, Vector3(0,3.83,0), Vector3(10.70,.69,.43), navy)
		_block(root, Vector3(0,3.52,.23), Vector3(10.28,.055,.06), accent)
		var banner := "FINISH    /    12" if is_finish else "%02d    /    %s" % [i+1, "TURN" if is_turn else "MIDNIGHT"]
		_sign(root, banner, Vector3(0,3.85,.25), WHITE, .50)
		if is_turn:
			var instruction: String = TURNS[i]
			_sign(root, "◀  LEFT" if instruction.begins_with("LEFT") else "RIGHT  ▶", Vector3(0,4.55,.25), PINK, .64)
		for j in range(20):
			if not is_finish and j % 2 == 1:
				continue
			_block(root, Vector3(-4.75+j*.50,.166,0), Vector3(.46,.019,.24), accent if j % 2 == 0 else navy)
		var prev: Vector3 = GATES[i-1] if i > 0 else START
		var segment := prev.distance_to(GATES[i])
		# Low road markers stay clear of the runner's silhouette and the turn-in line.
		for j in range(1, floori(segment / 5.0)):
			for side in [-1, 1]:
				_block(root, Vector3(side*3.68,.154,float(j)*5.0), Vector3(.10,.012,1.30), ice)
		if i in [0, 2, 5, 8, 10]:
			var strip := Node3D.new()
			strip.position = prev.lerp(GATES[i], .44)
			strip.rotation.y = _yaw(dir)
			add_child(strip)
			_pad_nodes[i] = strip
			_block(strip, Vector3(0,.149,0), Vector3(4.70,.021,4.50), navy)
			for j in range(3):
				for side in [-1, 1]:
					_block(strip, Vector3(side*.91,.177,(j-1)*1.05), Vector3(1.96,.021,.18), lime, side*.39)
			for side in [-1, 1]:
				_block(strip, Vector3(side*2.32,.177,0), Vector3(.09,.021,4.50), lime)

	for root in _batches:
		for mat in _batches[root]:
			var transforms: Array = _batches[root][mat]
			var mesh := MultiMesh.new()
			mesh.transform_format = MultiMesh.TRANSFORM_3D
			mesh.mesh = _box
			mesh.instance_count = transforms.size()
			for j in range(transforms.size()):
				mesh.set_instance_transform(j, transforms[j])
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = mesh
			batch.material_override = mat
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.visibility_range_end = 140.0
			root.add_child(batch)
	_batches.clear()


func _yaw(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


func _block(parent: Node3D, point: Vector3, dimensions: Vector3, material: Material, yaw := 0.0) -> void:
	if not _batches.has(parent):
		_batches[parent] = {}
	var by_material: Dictionary = _batches[parent]
	if not by_material.has(material):
		by_material[material] = []
	by_material[material].append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(dimensions), point))


func _sign(parent: Node3D, words: String, point: Vector3, tint: Color, height: float) -> void:
	var sign := Label3D.new()
	sign.text = words
	sign.font_size = 48
	sign.outline_size = 8
	sign.pixel_size = height / 48.0
	sign.modulate = tint
	sign.position = point
	sign.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign.visibility_range_end = 95.0
	parent.add_child(sign)


func _tone(pitch: float) -> AudioStreamWAV:
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(6614)
	for i in range(data.size() / 2):
		var t := float(i) / 22050.0
		var gain := minf(t*125.0, 1.0) * maxf(0.0, 1.0-t/.15)
		data.encode_s16(i*2, roundi(sin(t*TAU*pitch)*gain*15000.0))
	wave.data = data
	return wave


func _beep(index: int) -> void:
	_player.stream = _tones[index]
	_player.play()
