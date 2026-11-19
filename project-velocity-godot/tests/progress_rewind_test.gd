extends SceneTree

const Progress := preload("res://systems/progress.gd")
const Rewind := preload("res://systems/rewind.gd")

class MockWorld extends RefCounted:
	var progress
	var realm := "city"
	var events: Array[Dictionary] = []
	var frame: Dictionary = {}

	func snapshot() -> Dictionary:
		return frame

	func restore(previous: Dictionary) -> void:
		frame = previous

	func event(id: String, data: Dictionary) -> void:
		events.append({"id": id, "data": data})


var _failed := 0
var _checked := 0
var _prefix := ""
var _used_profiles: Array[String] = []


func _initialize() -> void:
	_prefix = "user://velocity-progress-test-%d" % Time.get_ticks_usec()
	_test_odds_and_profile()
	_test_slot_recovery_and_schema()
	_test_motion_and_rewind()
	_test_travel_retry()
	_test_bounded_history()
	for base: String in _used_profiles:
		for extension: String in [".a", ".b", ".part", ".cfg"]:
			if FileAccess.file_exists(base + extension):
				DirAccess.remove_absolute(base + extension)
	print("Progress and rewind assertions: %d, failures: %d" % [_checked, _failed])
	quit(0 if _failed == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checked += 1
	if not condition:
		_failed += 1
		push_error(message)


func _profile(name: String) -> String:
	var base := _prefix + "-" + name
	_used_profiles.append(base)
	return base


func _test_odds_and_profile() -> void:
	var path := _profile("main")
	var profile := Progress.new()
	_expect(not profile.setup(null, path), "A new profile starts without a saved revision")
	_expect(profile.credits == 0 and profile.rank_title() == "Human", "Fresh profile has zero SFC and first rank")
	var start := 0
	var names := ["Common", "Rare", "Epic", "Legendary", "Mythic", "Divine"]
	var counts := [5000, 2700, 1400, 650, 200, 50]
	var observed := [0, 0, 0, 0, 0, 0]
	for i: int in range(names.size()):
		var edge := start + int(counts[i]) - 1
		_expect(profile.pick_rarity(start).get("name", "") == names[i], "Correct first ticket in %s" % names[i])
		_expect(profile.pick_rarity(edge).get("name", "") == names[i], "Correct last ticket in %s" % names[i])
		start = edge + 1
	for ticket: int in range(10000):
		var tier := int(profile.pick_rarity(ticket).get("index", -1))
		if tier >= 0:
			observed[tier] += 1
	_expect(observed == counts and start == 10000, "All 10,000 tickets match the documented weights")
	_expect(profile.pick_rarity(-1).is_empty() and profile.pick_rarity(10000).is_empty(), "Invalid tickets are rejected")
	_expect(profile.pull_cost == 25 and profile.pull().is_empty(), "A cache requires 25 earned SFC")
	_expect(not profile.award("", 8) and not profile.award("negative", -1), "Reject malformed and negative wallet awards")
	_expect(profile.award("test:earning", 1200), "The first legitimate award commits")
	_expect(not profile.award("test:earning", 1200), "An existing transaction cannot pay again")
	_expect(profile.credits == 1200, "Replayed award leaves the wallet intact")

	var next := Vector3(17.0, 0.1, -46.0)
	_expect(profile.settle_mission("first", 80, 1, "crossing", next, "city"), "Checkpoint and mission payment commit together")
	_expect(profile.settle_mission("first", 80, 1, "stale", Vector3.ZERO), "Retrying settlement succeeds idempotently")
	_expect(profile.credits == 1280 and profile.mission_stage == "crossing", "Retry cannot change wallet or regress the active stage")
	var before := profile.movement()
	var price := profile.upgrade_cost("speed")
	_expect(profile.upgrade("speed") and profile.credits == 1280 - price, "Upgrade charges its published price exactly")
	var after := profile.movement()
	_expect(after["speed"] > before["speed"] and after["accel"] == before["accel"] and after["turn"] == before["turn"], "Speed is an independent upgrade")
	_expect(not profile.upgrade("unrecognized") and not profile.prestige(), "Invalid upgrades and premature prestige are rejected")

	profile.settings["hud_layout"] = {"jump": Vector2(0.81, 0.70)}
	profile.settings["reduced_flash"] = true
	_expect(profile.save(), "Preferences commit")
	var expected_draw := profile._draw_item(profile._pull_index)
	var result := profile.pull()
	_expect(result == expected_draw and int(result.get("cost", 0)) == profile.pull_cost, "Pull uses its profile seed and creates the committed outcome")
	var reopened := Progress.new()
	_expect(reopened.setup(null, path), "Profile opens after a cache pull")
	_expect(reopened.has_award("test:earning") and not reopened.award("mission:first", 80), "Restart preserves completed transaction IDs")
	_expect(reopened.mission_flags.get("first") == true and reopened.checkpoint["position"] == next and reopened.mission_index == 1, "Restart restores mission and checkpoint together")
	_expect(reopened.settings["hud_layout"]["jump"] == Vector2(0.81, 0.70) and reopened.settings["reduced_flash"] == true, "Restart restores touch layout and flash settings")
	var collected := str(result.get("name", ""))
	_expect(not collected.is_empty() and reopened.inventory.has(collected) and reopened.equipped_trail == collected, "Commit precedes reveal and preserves the collected item and equipment")
	_expect(reopened.credits == profile.credits and reopened.stats["speed"] == 1 and reopened._pull_index == profile._pull_index, "Restart preserves the exact balance, draw counter and stat")
	_expect(reopened._draw_item(reopened._pull_index) == profile._draw_item(profile._pull_index), "Next result is reproducible from the durable draw index")

	for draw: int in range(13):
		reopened.pull()
	_expect(reopened.materials > 0 and reopened.inventory.size() <= 12, "Duplicates grant materials and never inflate inventory")
	var material_before := reopened.materials
	var exchange := floori(float(material_before) / 3.0)
	var wallet_before := reopened.credits
	_expect(reopened.redeem_materials() and reopened.credits == wallet_before + exchange and reopened.materials == material_before % 3, "Duplicate materials trade at three to one")
	_expect(not reopened.equip("unowned") and reopened.equip(collected), "Only owned items can be equipped")
	reopened.award("test:prestige", 10000)
	for stat: String in ["speed", "accel", "turn"]:
		while int(reopened.stats[stat]) < 5:
			if not reopened.upgrade(stat):
				break
	var pre_prestige := reopened.credits
	var cost := reopened.prestige_cost()
	_expect(reopened.prestige() and reopened.credits == pre_prestige - cost, "Prestige charges its exact cost after all three stat milestones")
	_expect(reopened.prestige_level == 1 and reopened.stats.values() == [0, 0, 0] and reopened.inventory.has(collected), "Prestige retains cosmetic rewards and grants a permanent tier")


func _write_slot(path: String, record: Dictionary) -> void:
	var payload := var_to_bytes(record)
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(payload)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_32(Progress.MAGIC)
	file.store_32(payload.size())
	file.store_buffer(hash_context.finish())
	file.store_buffer(payload)
	file.close()


func _test_slot_recovery_and_schema() -> void:
	var path := _profile("slots")
	var profile := Progress.new()
	profile.setup(null, path)
	_expect(profile.award("one", 10) and profile.award("two", 7), "Two transactions produce two durable revisions")
	var partial := FileAccess.open(path + ".part", FileAccess.WRITE)
	partial.store_string("interrupted staging")
	partial.close()
	var reopen := Progress.new()
	_expect(reopen.setup(null, path) and reopen.credits == 17, "Interrupted staging leaves the last committed slot intact")
	var corrupt := FileAccess.open(path + ".b", FileAccess.WRITE)
	corrupt.store_string("truncated slot")
	corrupt.close()
	var recovered := Progress.new()
	_expect(recovered.setup(null, path) and recovered.credits == 10, "A corrupt newest revision falls back to the last valid slot")
	_expect(recovered.last_error.contains("recovered") and recovered.has_award("one") and not recovered.has_award("two"), "Recovery reports the rollback and retains transaction consistency")
	_expect(recovered.award("three", 3), "A subsequent commit can replace the corrupt slot")
	_expect(recovered.last_error == Progress.RECOVERY_NOTICE, "Startup checkpoint writes preserve the recovery notice")
	var repaired := Progress.new()
	_expect(repaired.setup(null, path) and repaired.credits == 13, "A recovered profile survives reopening")

	var legacy := _profile("schema")
	_write_slot(legacy + ".a", {
		"schema": 1, "revision": 1, "credits": -11, "distance": 120.5, "pulls": 2,
		"upgrades": {"speed": 2, "acceleration": 4, "turn": 99999999},
		"awards": ["first", "first", 1], "checkpoint": {"position": Vector3.INF, "realm": "unknown"},
		"inventory": {"Cinder trail": 1, "fake": 1}, "settings": {"quality": 88, "music": -0.4, "master": "wrong", "hud_layout": true}
	})
	var migrated := Progress.new()
	_expect(migrated.setup(null, legacy), "Schema one migrates with missing optional fields")
	_expect(migrated.credits == 0 and migrated.stats["accel"] == 4 and migrated.stats["turn"] == Progress.MAX_STAT, "Migration normalizes legacy stat keys and unsafe numerical bounds")
	_expect(migrated.settings["quality"] == 3 and migrated.settings["music_volume"] == 0 and migrated.settings["master_volume"] == 1 and migrated.settings["hud_layout"].is_empty(), "Migration validates recognized settings and uses current menu keys")
	_expect(migrated.checkpoint == {"position": Progress.START, "realm": "city"} and migrated.inventory.size() == 1, "Migration filters invalid checkpoints and unknown items")
	_expect(migrated.has_award("first") and migrated._awards.size() == 1 and migrated._pull_index == 2, "Migration coalesces duplicate journal IDs and preserves its draw counter")
	_expect(migrated.save() and migrated._read_slot(legacy + ".b")["schema"] == Progress.SCHEMA, "Migrated records are rewritten in the current format")
	var native_legacy := _profile("native-legacy")
	var config := ConfigFile.new()
	config.set_value("trial", "best", 29.75)
	config.set_value("settings", "limiter", 44)
	config.set_value("settings", "effects", false)
	config.save(native_legacy + ".cfg")
	var from_native := Progress.new()
	from_native.setup(null, native_legacy)
	_expect(from_native._migrate_legacy(native_legacy + ".cfg") and from_native.best_time == 29.75, "The old Godot prototype race result migrates")
	var migrated_native := Progress.new()
	_expect(migrated_native.setup(null, native_legacy) and migrated_native.settings["limiter"] == 0.44 and migrated_native.settings["effects"] == false, "Prototype limiter and effects survive reopening the new profile")

	var failure := _profile("missing") + "/profile"
	var unwritable := Progress.new()
	unwritable.setup(null, failure)
	_expect(not unwritable.award("safe", 7) and unwritable.credits == 0 and not unwritable.has_award("safe"), "A failed permanent write rolls back both wallet and journal")
	var corrupt_base := _profile("both-bad")
	for extension: String in [".a", ".b"]:
		var bad := FileAccess.open(corrupt_base + extension, FileAccess.WRITE)
		bad.store_string("recoverable original data")
		bad.close()
	var damaged := Progress.new()
	_expect(not damaged.setup(null, corrupt_base) and not damaged.award("preserve", 4), "Two damaged slots cannot be silently replaced")
	_expect(FileAccess.get_file_as_string(corrupt_base + ".a") == "recoverable original data" and FileAccess.get_file_as_string(corrupt_base + ".b") == "recoverable original data", "Both originals remain available after integrity failure")


func _world_frame(position: float, changed: bool = false) -> Dictionary:
	return {
		"hero": {"position": Vector3(position, 0.0, 0.0), "speed": 8.0 if changed else 0.0},
		"car_16_2": {"position": Vector3(5.0, 0.0, 3.0) if changed else Vector3(9.0, 0.0, 4.0), "damaged": changed},
		"civilian_4_7": {"position": Vector3(6.0, 0.0, 1.0), "injured": changed},
		"prop_7_2": {"position": Vector3(5.0, 1.0, 3.0) if changed else Vector3(8.0, 0.0, 3.0), "broken": changed}
	}


func _test_motion_and_rewind() -> void:
	var profile := Progress.new()
	var root := MockWorld.new()
	root.progress = profile
	profile.setup(root, _profile("motion"))
	profile.reset_motion(Vector3.ZERO)
	var history := Rewind.new()
	history.setup(root)
	var baseline := _world_frame(0.0)
	root.frame = baseline.duplicate(true)
	history.record(Rewind.STEP)
	for tick: int in range(1, 73):
		var position := tick * 0.25
		root.frame = _world_frame(position, true)
		profile.earn_distance(0.25, 6.0, Vector3(position, 0.0, 0.0), true, "city", Rewind.STEP)
		history.record(Rewind.STEP)
	_expect(profile.credits == 1 and is_equal_approx(profile.travel_total, 18.0), "A verified 18 m run earns precisely one travel credit")
	_expect(profile.award("objective:rescue", 12), "The first objective completion grants its permanent award")
	_expect(is_equal_approx(history.available_seconds(), 3.0) and history.request(), "24 Hz history offers an exact three-second rewind")
	var in_progress := 0
	var owned_tick := true
	while history.active and in_progress < 300:
		owned_tick = history.step(1.0 / 60.0) and owned_tick
		in_progress += 1
	_expect(owned_tick, "Playback consumes every physics tick including recovery")
	_expect(root.frame == baseline and in_progress < 300, "Rewind restores identical hero, vehicle, civilian and prop data by stable ID")
	var playback: Dictionary = root.events.back()
	_expect(playback["id"] == "rewind_finished" and playback["data"]["frames"] == 72 and playback["data"]["seconds"] == 3.0, "Rewind reports measured restored frames and elapsed history")
	_expect(not history.step(1.0 / 60.0) and not history.request(), "Discarded future cannot be replayed and normal physics resumes")

	for tick: int in range(1, 73):
		profile.earn_distance(0.25, 6.0, Vector3(tick * 0.25, 0.0, 0.0), true, "city", Rewind.STEP)
	_expect(is_equal_approx(profile.travel_total, 18.0) and profile.credits == 13, "Replaying exactly the same motion cannot earn distance or wallet credit")
	_expect(not profile.award("objective:rescue", 12), "Completing a rewound objective cannot pay twice")
	for tick: int in range(73, 145):
		profile.earn_distance(0.25, 6.0, Vector3(tick * 0.25, 0.0, 0.0), true, "city", Rewind.STEP)
	_expect(is_equal_approx(profile.travel_total, 36.0) and profile.credits == 14, "Fresh continued travel pays after replayed distance is exhausted")
	profile.earn_distance(400.0, 20.0, Vector3(436.0, 0.0, 0.0), true, "city", Rewind.STEP)
	_expect(is_equal_approx(profile.travel_total, 36.0) and profile.credits == 14, "Warp distance earns no payment")
	for tick: int in range(51):
		var position := 436.02 if tick % 2 == 0 else 436.0
		profile.earn_distance(0.02, 1.6, Vector3(position, 0.0, 0.0), true, "city", Rewind.STEP)
	_expect(profile.credits == 14, "Tiny oscillation earns no payment")
	profile.tick(4.0)
	var reopened := Progress.new()
	_expect(reopened.setup(null, _used_profiles.back()) and reopened.credits == 14, "Autosave commits newly earned spatial progress")
	_expect(reopened.has_award("objective:rescue"), "Autosave preserves the permanent objective ledger")


func _test_travel_retry() -> void:
	var profile := Progress.new()
	profile.setup(null, _profile("route"))
	profile.reset_motion(Vector3.ZERO)
	for unit: int in range(1, 325):
		profile.earn_distance(0.5, 6.0, Vector3(unit * 0.5, 0.0, 0.0), true, "city", 0.1)
	_expect(profile.credits == 9, "Nine new cells pay on a long outbound journey")
	profile.reset_motion(Vector3.ZERO)
	for unit: int in range(1, 325):
		profile.earn_distance(0.5, 6.0, Vector3(unit * 0.5, 0.0, 0.0), true, "city", 0.1)
	_expect(profile.credits == 9, "Restarting at the same checkpoint cannot farm a long previously paid route")
	for unit: int in range(323, -1, -1):
		profile.earn_distance(0.5, 6.0, Vector3(unit * 0.5, 0.0, 0.0), true, "city", 0.1)
	_expect(profile.credits > 9, "A continuous legitimate return can still earn credits beyond the cooldown")
	var before := profile.credits
	profile.earn_distance(0.5, 18.0, Vector3(-0.5, 0.0, 0.0), true, "city", 0.1)
	_expect(profile.credits == before + 9 and profile.has_award("speed:25") and profile.has_award("speed:50"), "Two crossed speed ranks commit once in the same tick")
	profile.earn_distance(0.5, 18.0, Vector3(-1.0, 0.0, 0.0), true, "city", 0.1)
	_expect(profile.credits == before + 9, "An earned speed milestone cannot recur")


func _test_bounded_history() -> void:
	var root := MockWorld.new()
	var history := Rewind.new()
	history.setup(root)
	for index: int in range(500):
		root.frame = _world_frame(float(index), true)
		history.record(Rewind.STEP)
	_expect(history.count == Rewind.CAPACITY and history.available_seconds() == 8.0, "History remains bounded after repeated ring wraps")
	var limits := history.diagnostics()
	_expect(limits["peak_sample_bytes"] > 0 and limits["approx_limit_bytes"] < 256000, "Four-actor fixture remains below its sample size budget")
	_expect(history.request(8.0), "A full eight-second playback is available after wrap")
	for tick: int in range(200):
		history.step(Rewind.STEP)
	_expect(not history.active and root.frame["hero"]["position"] == Vector3(307.0, 0.0, 0.0), "Wrapped playback recovers the oldest retained sample")
	for index: int in range(8):
		root.frame = _world_frame(float(index), false)
		history.record(Rewind.STEP)
	_expect(history.request(0.15), "A short playback can start with partial history")
	root.realm = "rift"
	_expect(history.step(Rewind.STEP) and history.count == 0 and not history.active, "Realm transition invalidates active history")
	root.frame = _world_frame(1350.0)
	history.record(Rewind.STEP)
	_expect(not history.request() and history.count == 1, "Rift history cannot traverse the city boundary")
	history.clear()
	_expect(history.count == 0 and history.available_seconds() == 0.0, "Checkpoint barrier clears retained frames")
