extends RefCounted
## Fixed cadence, finite storage. The coordinator owns which actor slots are relevant.

const SAMPLE_RATE := 24
const STEP := 1.0 / SAMPLE_RATE
const MAX_SECONDS := 8
const CAPACITY := SAMPLE_RATE * MAX_SECONDS + 1

var game
var active: bool = false
var count: int = 0
var remaining_seconds: float:
	get:
		return float(_remaining) / SAMPLE_RATE

var _snapshots: Array[Dictionary] = []
var _next: int = 0
var _remaining: int = 0
var _played: int = 0
var _sample_time: float = 0.0
var _play_time: float = 0.0
var _realm: String = ""
var _observed_bytes: int = 0


func setup(root) -> void:
	game = root
	_snapshots.resize(CAPACITY)
	clear()


func available_seconds() -> float:
	return float(maxi(0, count - 1)) / SAMPLE_RATE


func record(dt: float) -> void:
	if active or game == null:
		return
	var realm := String(game.realm)
	if realm != _realm:
		clear()
		_realm = realm
	_sample_time += clampf(dt, 0.0, 0.1)
	if count > 0 and _sample_time < STEP:
		return
	_sample_time = fmod(_sample_time, STEP)
	var frame: Dictionary = game.snapshot()
	if frame.is_empty():
		return
	# Keep a private typed shape. Nested vectors and packed values are retained,
	# but no object references are introduced by this buffer.
	var sample := frame.duplicate(true)
	if game.progress != null:
		sample["_rewind_motion"] = game.progress.motion_state()
	_snapshots[_next] = sample
	_next = (_next + 1) % CAPACITY
	count = mini(count + 1, CAPACITY)
	# Estimate once a second for QA instead of serializing on every capture.
	if _next % SAMPLE_RATE == 0:
		_observed_bytes = maxi(_observed_bytes, var_to_bytes(sample).size())


func request(seconds: float = 3.0) -> bool:
	if game == null or active or count < 2 or not is_finite(seconds) or seconds <= 0.0:
		return false
	if String(game.realm) != _realm:
		clear()
		return false
	_remaining = mini(count - 1, maxi(1, floori(clampf(seconds, 0.0, MAX_SECONDS) * SAMPLE_RATE)))
	_played = 0
	_play_time = STEP
	active = true
	game.event("rewind_started", {"seconds": remaining_seconds})
	return true


func step(dt: float) -> bool:
	if not active:
		return false
	if String(game.realm) != _realm:
		clear()
		return true
	_play_time += clampf(dt, 0.0, 0.1)
	while _play_time >= STEP and _remaining > 0:
		_play_time -= STEP
		_next = posmod(_next - 1, CAPACITY)
		_snapshots[_next] = {}
		count -= 1
		var previous := posmod(_next - 1, CAPACITY)
		var frame := _snapshots[previous].duplicate(true)
		var motion: Dictionary = frame.get("_rewind_motion", {})
		frame.erase("_rewind_motion")
		game.restore(frame)
		if game.progress != null:
			game.progress.restore_motion(motion)
		_remaining -= 1
		_played += 1
	if _remaining == 0:
		active = false
		_sample_time = 0.0
		_play_time = 0.0
		game.event("rewind_finished", {"seconds": float(_played) / SAMPLE_RATE, "frames": _played})
	# Includes the recovery tick so no new physics is added on top of a restored frame.
	return true


func clear() -> void:
	for index in _snapshots.size():
		_snapshots[index] = {}
	_next = 0
	_remaining = 0
	_played = 0
	count = 0
	active = false
	_sample_time = 0.0
	_play_time = 0.0
	if game != null:
		_realm = String(game.realm)


func diagnostics() -> Dictionary:
	return {"samples": count, "capacity": CAPACITY, "peak_sample_bytes": _observed_bytes, "approx_limit_bytes": _observed_bytes * CAPACITY}
