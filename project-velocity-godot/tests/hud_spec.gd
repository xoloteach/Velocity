extends SceneTree

const Hud = preload("res://systems/hud.gd")
const Progress = preload("res://systems/progress.gd")

var game: FixtureGame
var hud
var checks := 0
var failures: Array[String] = []
var profile_path := "user://velocity-hud-test-%d" % Time.get_ticks_usec()


class FixtureGame extends Node:
	var commands: Array[String] = []
	var view_changes := Vector2.ZERO
	var progress: Variant
	var mission_title := "First Lightning"
	var objective_text := "Reach the rescue beacon"
	var target_position := Vector3(0.0, 0.0, -20.0)
	var quality := 1
	var paused := false
	var boss_status := {"name": "Test runner", "hp": 60, "max_hp": 100, "telegraph": "COUNTER NOW"}
	var _cinema_timer := 0.0

	func command(action: String) -> void:
		commands.push_back(action)
		if action == "pause_hud":
			paused = true
		elif action == "resume":
			paused = false
		elif action == "skip":
			_cinema_timer = 0.0

	func look_delta(delta: Vector2) -> void:
		view_changes += delta

	func configure_settings(key: String, value: Variant) -> void:
		progress.settings[key] = value
		progress.save()


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.push_back(description)


func _touch(index: int, position: Vector2, pressed: bool, cancelled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = cancelled
	root.push_input(event, true)


func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	root.push_input(event, true)


func _center(key: String) -> Vector2:
	var rect: Rect2 = hud.action_boxes[key]
	return rect.get_center()


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	root.push_input(released, true)


func _pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	var released := event.duplicate() as InputEventJoypadButton
	released.pressed = false
	root.push_input(released, true)


func _run() -> void:
	game = FixtureGame.new()
	game.progress = Progress.new()
	game.progress.setup(game,profile_path)
	game.progress.award("hud:test",101)
	root.add_child(game)
	var canvas := CanvasLayer.new()
	game.add_child(canvas)
	hud = Hud.new()
	canvas.add_child(hud)
	hud.setup(game)
	await process_frame
	hud.tick(0.0)
	_check(hud.size.x >= 1000 and hud.size.y >= 680, "HUD fills the logical viewport")

	var stick := _center(Hud.STICK)
	var boost := _center("boost")
	var jump := _center("jump")
	var look := Vector2(842, 368)
	_touch(0, stick - Vector2(0, 41), true)
	_check(hud.axis.y > .70, "Indexed touch moves forward")
	_touch(1, look, true)
	_drag(1, look + Vector2(30, -12), Vector2(30, -12))
	_check(game.view_changes == Vector2(30, -12), "Camera can drag during movement")
	_touch(2, jump, true)
	_touch(3, boost, true)
	_check(game.commands.has("jump") and hud.boost and hud.sprint and hud.axis.y > .70, "Movement, jump and boost coexist")
	_touch(4, stick, true)
	_touch(4, stick, false)
	_check(hud.axis.y > .70, "A second finger cannot steal the movement stick")
	_touch(2, jump, false)
	_touch(1, look, false, true)
	_check(hud.boost and hud.axis.y > .70, "A camera cancellation does not release movement or boost")
	_touch(3, boost, false)
	_check(not hud.boost and hud.axis.y > .70, "Releasing boost does not release movement")
	_touch(0, stick, false, true)
	_check(hud.axis == Vector2.ZERO and hud.owners.is_empty(), "Cancellation releases only the owning touch")

	_touch(0, stick - Vector2(0, 41), true)
	_touch(5, _center("powers"), true)
	_check(hud.wheel_open and hud.ability_boxes.size() == 9, "Powers wheel lists all nine selectable abilities")
	var cast: Rect2 = hud.ability_boxes["phase"]
	_touch(6, cast.get_center(), true)
	_check(not hud.wheel_open and game.commands.has("phase") and hud.axis.y > .70, "Ability selection preserves active navigation")
	_touch(5, _center("powers"), false)

	var limiter: Rect2 = hud.action_boxes["limiter"]
	var cap := limiter.position + Vector2(limiter.size.x*.30, limiter.size.y*.5)
	_touch(4, cap, true)
	_touch(4, cap, false)
	_check(is_equal_approx(hud.limiter, .37) and is_equal_approx(game.progress.settings.get("limiter", 0.0), .37), "Limiter responds and persists")
	_touch(3, boost, true)
	_touch(8, hud._toolbar_pause.get_center(), true)
	_check(hud.menu_current == "settings" and game.paused and not hud.boost and hud.axis == Vector2.ZERO, "Touch opens settings and clears active controls")
	await process_frame
	await process_frame
	var slider: HSlider
	for item in hud.menu_sliders:
		if item.get_meta("setting") == "camera_sensitivity":
			slider = item
			break
	_check(is_instance_valid(slider), "Settings exposes a functional sensitivity adjustment")
	if is_instance_valid(slider):
		hud.scroll.ensure_control_visible(slider)
		await process_frame
		var track := slider.get_global_rect()
		var select := track.position + Vector2(track.size.x*.7, track.size.y*.5)
		_touch(4, select, true)
		_touch(4, select, false)
		_check(is_equal_approx(game.progress.settings.get("camera_sensitivity", 0.0), 1.75), "Settings touch slider persists independently")

	hud._close_menu()
	_check(not game.paused, "Closing settings resumes the world")
	_key(KEY_Q)
	_check(hud.wheel_open, "Keyboard opens the power wheel")
	_key(KEY_ESCAPE)
	_check(not hud.wheel_open and not game.paused, "Dismissing the wheel preserves gameplay")
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	_pad(JOY_BUTTON_DPAD_RIGHT)
	_pad(JOY_BUTTON_A)
	_check(not hud.wheel_open and game.commands.count("phase") == 2, "Controller selects and casts from the wheel")
	_pad(JOY_BUTTON_START)
	_check(hud.menu_current == "mission" and game.paused, "Controller opens Operations")
	await process_frame
	await process_frame
	_pad(JOY_BUTTON_DPAD_DOWN)
	_pad(JOY_BUTTON_A)
	_check(hud.menu_current == "map", "Controller navigates an actual menu item")
	_pad(JOY_BUTTON_START)
	_check(hud.menu_current.is_empty() and not game.paused, "Controller resumes from Operations")

	hud.show_menu("touch_edit")
	var new_center := stick + Vector2(210, -72)
	_touch(0, stick, true)
	_drag(0, new_center, new_center - stick)
	_touch(0, new_center, false)
	_check(_center(Hud.STICK).is_equal_approx(new_center), "Dragging saves a per-control position")
	_touch(1, hud._editor_rect(1).get_center(), true)
	_check(is_equal_approx(game.progress.settings.hud_layout[Hud.STICK].scale, 1.1), "Per-control size adjustment persists")
	_touch(2, hud._editor_rect(3).get_center(), true)
	_check(not hud.editor and not game.paused, "Touch editor resumes gameplay")

	game._cinema_timer = 2.0
	hud.tick(0.0)
	_touch(1, hud._toolbar_pause.get_center(), true)
	_check(game._cinema_timer == 0.0 and game.commands.has("skip"), "Cinematic can be skipped via touch")

	hud.show_menu("cache")
	hud.set_cache_result({"name": "Solar trail", "rarity": "Legendary", "color": "#ffb465"})
	hud.tick(0.0)
	_check(hud._cache_result().name == "Solar trail", "Cache reveal is available to the menu")
	hud.show_ending()
	_check(hud.menu_current == "ending" and game.paused, "Ending displays the postgame menu")

	hud._close_menu()
	var layout: Dictionary = game.progress.settings.hud_layout.duplicate(true)
	hud.free()
	game.progress = Progress.new()
	_check(game.progress.setup(game,profile_path), "Fresh profile loads a persisted HUD save")
	root.content_scale_size = Vector2i(1280,720)
	root.size = Vector2i(1280,720)
	hud = Hud.new()
	canvas.add_child(hud)
	hud.setup(game)
	await process_frame
	_check(is_equal_approx(hud.size.x / hud.size.y, 16.0/9.0), "The viewport actually changes to 16:9")
	var expected: Array = layout[Hud.STICK].anchor
	var reloaded: Vector2 = _center(Hud.STICK) / hud.size
	_check(reloaded.is_equal_approx(Vector2(expected[0], expected[1])) and is_equal_approx(hud.limiter,.37), "Fresh HUD loads normalized anchors and limiter at 16:9")
	var viewport := Rect2(Vector2.ZERO,hud.size)
	for key in hud.action_boxes:
		var rect: Rect2 = hud.action_boxes[key]
		_check(viewport.encloses(rect) and not hud._crowded(key,rect), "%s remains in a dedicated visible touch zone at 16:9" % key)

	for description in failures:
		push_error(description)
	for extension in [".a",".b",".part"]:
		var path: String = profile_path+extension
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("HUD_CHECKS %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
