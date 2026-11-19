extends RefCounted
## Permanent progression. Rewind reads only motion_state(), never this profile.

const SCHEMA := 2
const WORLD_GENERATOR := 2
const SLOT_ID := "main"
const MAGIC := 0x56505332
const MAX_FILE := 8_000_000
const MAX_BALANCE := 9_000_000_000_000
const MAX_STAT := 100_000
const MAX_RECORDS := 60_000
const STAT_NAMES: Array[String] = ["speed", "accel", "turn"]
const PROFILE := "user://velocity-profile"
const START := Vector3(0, 0, 8)
const RECOVERY_NOTICE := "A damaged save was recovered from the previous checkpoint."
const DEFAULTS := {
	"quality": 1, "effects": true, "reduced_motion": false, "reduced_flash": false,
	"camera_sensitivity": 1.0, "master_volume": 1.0, "sfx_volume": 0.8, "music_volume": 0.75, "voice_volume": 0.9,
	"subtitles": true, "text_scale": 1.0, "hud_layout": {}, "hud_scale": 1.0, "limiter": 1.0
}
const SETTING_ALIASES := {
	"master": "master_volume", "sfx": "sfx_volume", "music": "music_volume", "voice": "voice_volume",
	"speed_limiter": "limiter", "sensitivity": "camera_sensitivity", "fps": "fps_limit"
}
const RANKS := [
	[0, "Human"], [1, "Enhanced"], [3, "Mach 1"], [6, "Mach 10"],
	[11, "Mach 100"], [17, "Relativistic"], [24, "Lightspeed"],
	[33, "Beyond Light"], [45, "Divine"], [72, "Unbounded"]
]

var credits: int = 0
var materials: int = 0
var stats: Dictionary = {"speed": 0, "accel": 0, "turn": 0}
var inventory: Dictionary = {}
var equipped_trail: String = ""
var settings: Dictionary = DEFAULTS.duplicate(true)
var rarities: Array = []
var pull_cost: int = 25
var seed: int = 68137
var mission_index: int = 0
var mission_stage: String = ""
var mission_flags: Dictionary = {}
var checkpoint: Dictionary = {"position": START, "realm": "city"}
var finished: bool = false
var best_time: float = 0.0
var travel_total: float = 0.0
var prestige_level: int = 0
var persistent: bool = true
var last_error: String = ""

var _file_base: String = PROFILE
var _revision: int = 0
var _pull_index: int = 0
var _salt: int = 0
var _awards: Dictionary = {}
var _cells: Dictionary = {}
var _seen_on_journey: Dictionary = {}
var _recent_cells: Array[String] = []
var _events: Array = []
var _milestones: Array = []
var _distance_per_credit: float = 18.0
var _last_position := Vector3.INF
var _anchor := Vector3.INF
var _anchor_path: float = 0.0
var _motion_cursor: float = 0.0
var _highwater: float = 0.0
var _motion_realm: String = "city"
var _dirty: bool = false
var _flush_elapsed: float = 0.0


func setup(_root, file_base: String = PROFILE) -> bool:
	_file_base = file_base
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/game.json"))
	if config is Dictionary:
		rarities = config.get("rarities", [])
		_milestones = config.get("speedMilestones", [])
		_distance_per_credit = maxf(8.0, float(config.get("distancePerCredit", 18.0)))
		pull_cost = maxi(1, int(config.get("pullCost", 25)))
		seed = int(config.get("seed", seed))
	_salt = randi()
	persistent = not OS.has_feature("web") or OS.is_userfs_persistent()
	if not persistent:
		last_error = "Browser storage is unavailable. Progress lasts for this session."
	return load_game()


func load_game() -> bool:
	var first: Dictionary = _read_slot(_file_base + ".a")
	var second: Dictionary = _read_slot(_file_base + ".b")
	var selected: Dictionary = first if int(first.get("revision", 0)) >= int(second.get("revision", 0)) else second
	if not selected.is_empty():
		_revision = int(selected["revision"])
		_apply(selected)
		_dirty = false
		if persistent and (first.is_empty() != second.is_empty()) and (FileAccess.file_exists(_file_base + ".a") and FileAccess.file_exists(_file_base + ".b")):
			last_error = RECOVERY_NOTICE
		return true
	if FileAccess.file_exists(_file_base + ".a") or FileAccess.file_exists(_file_base + ".b"):
		last_error = "The saved files could not be verified. They were left available for recovery."
		return false
	if _file_base == PROFILE:
		return _migrate_legacy()
	return false


func save() -> bool:
	if not persistent:
		_dirty = false
		return true
	# Never overwrite both damaged original slots as an implicit form of reset.
	if _revision == 0 and (FileAccess.file_exists(_file_base + ".a") or FileAccess.file_exists(_file_base + ".b")):
		last_error = "The save needs recovery before it can be overwritten."
		return false
	var revision := _revision + 1
	var target := _file_base + (".a" if revision % 2 == 1 else ".b")
	var staged := _file_base + ".part"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return _write_failed()
	var payload := var_to_bytes(_serialize(revision))
	if payload.size() > MAX_FILE:
		file.close()
		return _write_failed()
	file.store_32(MAGIC)
	file.store_32(payload.size())
	file.store_buffer(_digest(payload))
	file.store_buffer(payload)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or _read_slot(staged).is_empty():
		return _write_failed()
	if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) != OK:
		return _write_failed()
	if DirAccess.rename_absolute(staged, target) != OK:
		return _write_failed()
	if OS.has_feature("web"):
		# Sync after the atomic rename so the target, rather than its staging name,
		# is available to the browser's next IndexedDB transaction.
		JavaScriptBridge.force_fs_sync()
	_revision = revision
	_dirty = false
	_flush_elapsed = 0.0
	if last_error != RECOVERY_NOTICE:
		last_error = ""
	return true


func tick(dt: float) -> void:
	if not _dirty:
		return
	_flush_elapsed += maxf(0.0, dt)
	if _flush_elapsed >= 4.0:
		_flush_elapsed = 0.0
		save()


func award(id: String, amount: int) -> bool:
	if has_award(id) or not _valid_id(id) or amount < 0 or _awards.size() >= MAX_RECORDS:
		return false
	var old := _serialize(_revision)
	_awards[id] = true
	var credited := _add_credits(amount)
	_log(id, "award", credited)
	return _finish_or_restore(old)


func has_award(id: String) -> bool:
	return _awards.has(id)


func save_checkpoint(
	index: int,
	stage: String,
	position: Vector3,
	realm: String = "city"
) -> bool:
	if not _valid_spawn(position) or not _valid_realm(realm) or not _valid_id(stage, true):
		return false
	var old := _serialize(_revision)
	mission_index = clampi(index, 0, 8)
	mission_stage = stage
	checkpoint = {"position": position, "realm": realm}
	return _finish_or_restore(old)


func settle_mission(
	id: String,
	reward: int,
	next_index: int,
	stage: String = "",
	position: Vector3 = Vector3.INF,
	realm: String = "city"
) -> bool:
	var reward_id := "mission:" + id
	if not _valid_id(id) or not _valid_id(reward_id) or reward < 0 or not _valid_id(stage, true):
		return false
	if mission_flags.has(id) and has_award(reward_id):
		return true
	if not has_award(reward_id) and _awards.size() >= MAX_RECORDS:
		return false
	var previous := _serialize(_revision)
	if not has_award(reward_id):
		_awards[reward_id] = true
		var credited := _add_credits(reward)
		_log(reward_id, "mission", credited)
	mission_flags[id] = true
	if next_index >= mission_index:
		mission_index = clampi(next_index, 0, 8)
		mission_stage = stage
		if _valid_spawn(position) and _valid_realm(realm):
			checkpoint = {"position": position, "realm": realm}
	finished = finished or mission_index >= 8
	return _finish_or_restore(previous)


func record_trial(seconds: float) -> bool:
	if not is_finite(seconds) or seconds<=0.0 or (best_time>0.0 and seconds>=best_time):
		return false
	var previous := _serialize(_revision)
	best_time = seconds
	return _finish_or_restore(previous)


func upgrade_cost(stat: String) -> int:
	if not STAT_NAMES.has(stat):
		return -1
	var level := int(stats.get(stat, 0))
	return roundi(12.0 + 7.0 * pow(level, 1.12))


func upgrade(stat: String) -> bool:
	var price := upgrade_cost(stat)
	if price < 0 or price > credits or int(stats[stat]) >= MAX_STAT:
		return false
	var previous := _serialize(_revision)
	credits -= price
	stats[stat] = int(stats[stat]) + 1
	_log("stat:%s:%d:%d" % [stat, prestige_level, stats[stat]], "upgrade", -price)
	return _finish_or_restore(previous)


func prestige_cost() -> int:
	return 180 + 50 * prestige_level


func prestige() -> bool:
	if credits < prestige_cost() or prestige_level >= 1_000_000:
		return false
	for stat: String in STAT_NAMES:
		if int(stats[stat]) < 5:
			return false
	var previous := _serialize(_revision)
	var cost := prestige_cost()
	credits -= cost
	prestige_level += 1
	stats = {"speed": 0, "accel": 0, "turn": 0}
	_log("prestige:%s" % prestige_level, "prestige", -cost)
	return _finish_or_restore(previous)


func movement() -> Dictionary:
	return {
		"speed": 1.0 + _stat_scale("speed") * 1.20,
		"accel": 1.0 + _stat_scale("accel") * 1.35,
		"turn": 1.0 + _stat_scale("turn") * 1.40
	}


func rank_title() -> String:
	var value := int(stats["speed"]) + prestige_level * 6
	var title: String = RANKS[0][1]
	for rank: Array in RANKS:
		if value < int(rank[0]):
			break
		title = rank[1]
	return title


func trail_color() -> Color:
	for tier: Dictionary in rarities:
		if tier["items"].has(equipped_trail):
			return Color(tier["color"])
	return Color("#ffad57")


func pick_rarity(ticket: int) -> Dictionary:
	if ticket < 0 or ticket >= 10000:
		return {}
	var cumulative := 0
	for index in rarities.size():
		var tier: Dictionary = rarities[index]
		cumulative += int(tier["weight"])
		if ticket < cumulative:
			var data := tier.duplicate()
			data["index"] = index
			return data
	return {}


func _draw_item(index: int) -> Dictionary:
	var random := RandomNumberGenerator.new()
	# Explicit per-profile entropy and draw index reproduce the outcome after an
	# interrupted uncommitted pull. Only a successful transaction advances it.
	random.seed = hash("%d:%d" % [_salt, index])
	var tier := pick_rarity(random.randi_range(0, 9999))
	if tier.is_empty():
		return {}
	var items: Array = tier["items"]
	var item: String = items[random.randi_range(0, items.size() - 1)]
	var duplicate := int(inventory.get(item, 0)) > 0
	var salvage := (2 + int(tier["index"]) * 2) if duplicate else 0
	return {
		"name": item, "rarity": tier["name"], "tier": tier["name"], "color": tier["color"],
		"duplicate": duplicate, "salvage": salvage, "cost": pull_cost
	}


func pull() -> Dictionary:
	if credits < pull_cost or _pull_index >= MAX_BALANCE:
		return {}
	var outcome := _draw_item(_pull_index)
	if outcome.is_empty():
		return {}
	var previous := _serialize(_revision)
	var item: String = outcome["name"]
	credits -= pull_cost
	_pull_index += 1
	if outcome["duplicate"]:
		materials = mini(MAX_BALANCE, materials + int(outcome["salvage"]))
	else:
		inventory[item] = 1
		if equipped_trail.is_empty():
			equipped_trail = item
	_log("pull:%d" % _pull_index, "pull", -pull_cost, outcome)
	return outcome if _finish_or_restore(previous) else {}


func redeem_materials() -> bool:
	# Exchange all complete bundles at a deliberately simple, disclosed rate.
	var coins := floori(float(materials) / 3.0)
	coins = mini(coins, MAX_BALANCE - credits)
	if coins <= 0:
		return false
	var previous := _serialize(_revision)
	materials -= coins * 3
	credits += coins
	_log("exchange:%d" % (_revision + 1), "exchange", coins)
	return _finish_or_restore(previous)


func equip(item: String) -> bool:
	if not item.is_empty() and int(inventory.get(item, 0)) < 1:
		return false
	var previous := _serialize(_revision)
	equipped_trail = item
	return _finish_or_restore(previous)


func reset_motion(position: Vector3 = Vector3.INF, realm: String = "city") -> void:
	_last_position = position
	_anchor = position
	_anchor_path = 0.0
	_motion_cursor = 0.0
	_highwater = 0.0
	_motion_realm = realm
	_seen_on_journey.clear()


func motion_state() -> Dictionary:
	return {
		"last": _last_position, "anchor": _anchor, "path": _anchor_path,
		"cursor": _motion_cursor, "realm": _motion_realm
	}


func restore_motion(frame: Dictionary) -> void:
	if frame.is_empty():
		return
	_last_position = frame.get("last", _last_position)
	_anchor = frame.get("anchor", _anchor)
	_anchor_path = float(frame.get("path", _anchor_path))
	_motion_cursor = float(frame.get("cursor", _motion_cursor))
	_motion_realm = frame.get("realm", _motion_realm)
	# _highwater, geographic history, wallet and journal remain on the new branch.


func earn_distance(
	distance: float,
	speed_mps: float,
	position: Vector3,
	eligible: bool = true,
	realm: String = "city",
	delta: float = 1.0 / 60.0
) -> int:
	if not position.is_finite() or not is_finite(distance) or not is_finite(speed_mps):
		return 0
	if realm != _motion_realm or not _last_position.is_finite():
		reset_motion(position, realm)
		return 0
	var moved := Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
	_last_position = position
	var allowed := clampf(speed_mps * clampf(delta, 1.0 / 240.0, 0.1) * 1.5 + 0.3, 0.42, 13.0)
	if not eligible or speed_mps < 1.5 or distance < 0.02 or moved < 0.02 or moved > allowed:
		if not eligible or moved > allowed:
			_anchor = position
			_anchor_path = 0.0
		return 0
	var accepted := minf(distance, moved)
	_motion_cursor += accepted
	_anchor_path += accepted
	var fresh := clampf(_motion_cursor - _highwater, 0.0, accepted)
	_highwater = maxf(_highwater, _motion_cursor)
	var gained := 0
	if fresh >= 0.001:
		travel_total = minf(float(MAX_BALANCE), travel_total + fresh)
		_dirty = true
	var span := Vector2(position.x - _anchor.x, position.z - _anchor.z).length()
	if span >= _distance_per_credit and _anchor_path >= _distance_per_credit:
		_anchor = position
		_anchor_path = 0.0
		if fresh >= 0.001:
			var cell := "%s:%d:%d" % [realm, floori(position.x / _distance_per_credit), floori(position.z / _distance_per_credit)]
			var last_paid := float(_cells.get(cell, -1_000_000.0))
			var known := _cells.has(cell)
			# A teleport or respawn begins a new journey. Its first pass through an
			# already-paid cell cannot be used to reset and farm the same route.
			var can_pay := (_seen_on_journey.has(cell) if known else _cells.size() < MAX_RECORDS)
			if can_pay and not _recent_cells.has(cell) and travel_total - last_paid >= _distance_per_credit * 7.0:
				gained += _add_credits(1)
				_cells[cell] = travel_total
			if _seen_on_journey.size() < MAX_RECORDS:
				_seen_on_journey[cell] = true
			_recent_cells.erase(cell)
			_recent_cells.push_front(cell)
			if _recent_cells.size() > 7:
				_recent_cells.pop_back()
	if fresh < 0.001:
		return 0
	var new_milestones: Array[int] = []
	var km_per_hour := speed_mps * 3.6
	for mark: Variant in _milestones:
		var limit := int(mark)
		if km_per_hour >= limit and not has_award("speed:%d" % limit):
			new_milestones.append(limit)
	if not new_milestones.is_empty() and _awards.size() + new_milestones.size() <= MAX_RECORDS:
		var previous := _serialize(_revision)
		var bonus := 0
		for limit: int in new_milestones:
			var id := "speed:%d" % limit
			var credited := _add_credits(maxi(3, roundi(float(limit) / 8.0)))
			bonus += credited
			_awards[id] = true
			_log(id, "speed_milestone", credited)
		if _finish_or_restore(previous):
			gained += bonus
	return gained


func _stat_scale(stat: String) -> float:
	var level := float(stats[stat]) + sqrt(float(prestige_level)) * 0.7
	return 1.0 - 1.0 / (1.0 + log(1.0 + level) * 0.35)


func _add_credits(amount: int) -> int:
	var accepted := clampi(amount, 0, MAX_BALANCE - credits)
	credits += accepted
	return accepted


func _log(id: String, kind: String, change: int, extra: Dictionary = {}) -> void:
	_events.append({"id": id, "kind": kind, "change": change, "balance": credits, "data": extra.duplicate()})
	if _events.size() > 100:
		_events.pop_front()


func _finish_or_restore(previous: Dictionary) -> bool:
	if save():
		return true
	var explanation := last_error
	_apply(previous)
	last_error = explanation
	return false


func _serialize(revision: int) -> Dictionary:
	return {
		"schema": SCHEMA, "revision": revision, "world_generator": WORLD_GENERATOR, "slot": SLOT_ID,
		"credits": credits, "materials": materials,
		"stats": stats.duplicate(true), "inventory": inventory.duplicate(true), "equipped": equipped_trail,
		"settings": settings.duplicate(true), "seed": seed, "mission_index": mission_index,
		"mission_stage": mission_stage, "mission_flags": mission_flags.duplicate(true),
		"checkpoint": checkpoint.duplicate(true), "finished": finished, "best_time": best_time,
		"travel": travel_total, "prestige": prestige_level, "pull_index": _pull_index, "salt": _salt,
		"awards": _awards.duplicate(), "visited": _cells.duplicate(), "recent": _recent_cells.duplicate(),
		"journal": _events.duplicate(true)
	}


func _apply(data: Dictionary) -> void:
	credits = _number(data.get("credits", 0), 0, MAX_BALANCE)
	materials = _number(data.get("materials", 0), 0, MAX_BALANCE)
	var old_stats := _dictionary(data.get("stats", data.get("upgrades", {})))
	for stat: String in STAT_NAMES:
		var previous_key := "acceleration" if stat == "accel" else stat
		stats[stat] = _number(old_stats.get(stat, old_stats.get(previous_key, 0)), 0, MAX_STAT)
	inventory = {}
	var raw_inventory := _dictionary(data.get("inventory", {}))
	for tier: Dictionary in rarities:
		for item: String in tier["items"]:
			if _number(raw_inventory.get(item, 0), 0, 1) == 1:
				inventory[item] = 1
	equipped_trail = _safe_string(data.get("equipped", ""))
	if not inventory.has(equipped_trail):
		equipped_trail = ""
	var old_settings := _dictionary(data.get("settings", {}))
	settings = DEFAULTS.duplicate(true)
	for key: Variant in old_settings:
		if key is String and _valid_id(key) and _safe_setting(old_settings[key]):
			var setting: String = SETTING_ALIASES.get(key, key)
			if key == setting or not old_settings.has(setting):
				_apply_setting(setting, old_settings[key])
	seed = _number(data.get("seed", seed), 1, 2_147_483_647, seed)
	mission_index = _number(data.get("mission_index", 0), 0, 8)
	mission_stage = _safe_string(data.get("mission_stage", ""))
	mission_flags = _filter_flags(data.get("mission_flags", {}))
	var old_checkpoint := _dictionary(data.get("checkpoint", {}))
	var position: Variant = old_checkpoint.get("position", START)
	var realm := _safe_string(old_checkpoint.get("realm", "city"))
	checkpoint = {
		"position": position if position is Vector3 and _valid_spawn(position) else START,
		"realm": realm if _valid_realm(realm) else "city"
	}
	finished = data.get("finished", false) == true or mission_index >= 8
	best_time = _nonnegative(data.get("best_time", 0.0))
	travel_total = _nonnegative(data.get("travel", data.get("distance", 0.0)))
	prestige_level = _number(data.get("prestige", 0), 0, 1_000_000)
	_pull_index = _number(data.get("pull_index", data.get("pulls", 0)), 0, MAX_BALANCE)
	_salt = _number(data.get("salt", _salt), 0, 0xFFFFFFFF)
	_awards = _filter_flags(data.get("awards", {}))
	if data.get("awards", []) is Array:
		for id: Variant in data.get("awards", []):
			if id is String and _valid_id(id) and _awards.size() < MAX_RECORDS:
				_awards[id] = true
	_cells = {}
	var old_cells := _dictionary(data.get("visited", {}))
	for key: Variant in old_cells:
		if key is String and _valid_id(key) and _cells.size() < MAX_RECORDS:
			_cells[key] = minf(travel_total, _nonnegative(old_cells[key]))
	_recent_cells.clear()
	if data.get("recent", []) is Array:
		for cell: Variant in data.get("recent", []):
			if cell is String and _valid_id(cell) and _recent_cells.size() < 7:
				_recent_cells.append(cell)
	_events = []
	if data.get("journal", []) is Array:
		for item: Variant in data.get("journal", []):
			if item is Dictionary and _events.size() < 100:
				_events.append(item)


func _read_slot(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 40 or file.get_length() > MAX_FILE + 40:
		return {}
	if file.get_32() != MAGIC:
		return {}
	var length := file.get_32()
	if length != file.get_length() - 40:
		return {}
	var checksum := file.get_buffer(32)
	var payload := file.get_buffer(length)
	if checksum != _digest(payload):
		return {}
	var data: Variant = bytes_to_var(payload)
	if not data is Dictionary or not data.get("schema") is int or not data.get("revision") is int:
		return {}
	if data["schema"] not in [1, SCHEMA] or data["revision"] < 1 or data.get("slot", SLOT_ID) != SLOT_ID or not data.get("settings", {}) is Dictionary:
		return {}
	return data


func _migrate_legacy(path: String = "user://velocity-v1.cfg") -> bool:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	if file.has_section_key("trial", "best"):
		best_time = _nonnegative(file.get_value("trial", "best"))
	if file.has_section_key("settings", "limiter"):
		settings["limiter"] = clampf(_nonnegative(file.get_value("settings", "limiter")) / 100.0, 0.1, 1.0)
	if file.get_value("settings", "effects", true) is bool:
		settings["effects"] = file.get_value("settings", "effects", true)
	return save()


func _write_failed() -> bool:
	last_error = "Could not save progress. Check browser storage or disk space, then retry."
	return false


func _digest(data: PackedByteArray) -> PackedByteArray:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(data)
	return hasher.finish()


func _filter_flags(value: Variant) -> Dictionary:
	var result := {}
	var source := _dictionary(value)
	for key: Variant in source:
		if key is String and _valid_id(key) and source[key] == true and result.size() < MAX_RECORDS:
			result[key] = true
	return result


func _apply_setting(key: String, value: Variant) -> void:
	match key:
		"quality":
			settings[key] = _number(value, 0, 3, DEFAULTS[key])
		"fps_limit":
			if value is int or value is float:
				settings[key] = _number(value, 30, 120, 60)
		"effects", "reduced_motion", "reduced_flash", "subtitles", "flash":
			if value is bool:
				settings[key] = value
		"master_volume", "sfx_volume", "music_volume", "voice_volume", "motion", "shake":
			if value is int or value is float:
				settings[key] = clampf(float(value), 0.0, 1.0)
		"limiter":
			if value is int or value is float:
				settings[key] = clampf(float(value), 0.1, 1.0)
		"camera_sensitivity":
			if value is int or value is float:
				settings[key] = clampf(float(value), 0.3, 2.6)
		"hud_scale", "text_scale":
			if value is int or value is float:
				settings[key] = clampf(float(value), 0.5, 2.0)
		"hud_layout":
			if value is Dictionary:
				settings[key] = value
		_:
			settings[key] = value


func _safe_setting(value: Variant, depth: int = 0) -> bool:
	if depth > 5:
		return false
	if value is Dictionary:
		if value.size() > 64:
			return false
		for key: Variant in value:
			if not (key is String and key.length() <= 96 and _safe_setting(value[key], depth + 1)):
				return false
		return true
	if value is Array:
		if value.size() > 64:
			return false
		for child: Variant in value:
			if not _safe_setting(child, depth + 1):
				return false
		return true
	if value is Vector2 or value is Vector3:
		return value.is_finite()
	if value is float:
		return is_finite(value)
	return value is bool or value is int or (value is String and value.length() <= 512)


func _number(value: Variant, minimum: int, maximum: int, fallback: int = 0) -> int:
	if value is int:
		return clampi(value, minimum, maximum)
	if value is float and is_finite(value):
		return floori(clampf(value, float(minimum), float(maximum)))
	return fallback


func _nonnegative(value: Variant) -> float:
	if value is float or value is int:
		var number := float(value)
		if is_finite(number):
			return clampf(number, 0.0, float(MAX_BALANCE))
	return 0.0


func _safe_string(value: Variant) -> String:
	return value if value is String and value.length() <= 150 else ""


func _dictionary(data: Variant) -> Dictionary:
	return data if data is Dictionary else {}


func _valid_id(id: String, allow_empty: bool = false) -> bool:
	return (allow_empty or not id.is_empty()) and id.length() <= 150


func _valid_realm(realm: String) -> bool:
	return realm in ["city", "rift"]


func _valid_spawn(position: Vector3) -> bool:
	return position.is_finite() and position.length_squared() <= 100_000_000.0
