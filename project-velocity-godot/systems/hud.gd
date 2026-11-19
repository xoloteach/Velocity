extends Control
## Landscape HUD and independent touch ownership. Gameplay commands are sent to the coordinator.

const Circuit = preload("res://systems/midnight.gd")
const AMBER := Color("#ffc079")
const MILK := Color("#f5eee5")
const CYAN := Color("#a2ecf3")
const TEXT := Color("#b8c6d4")
const CARD := Color("#101923ed")
const BORDER := Color("#89a4be49")
const RED := Color("#ffa2a0")
const ACTIONS := [
	["sprint", "SPRINT"], ["light", "STRIKE"], ["jump", "JUMP"], ["boost", "BOOST"],
	["slide", "SLIDE"], ["counter", "COUNTER"], ["powers", "POWERS"], ["dodge", "DODGE"],
	["lock", "LOCK"], ["heavy", "HEAVY"], ["rewind", "REWIND"], ["interact", "USE"],
]
const ABILITIES := [
	["lightning", "Lightning", "1", "#ffc06b"], ["phase", "Phase", "2", "#88daff"],
	["rewind", "Rewind", "3", "#b2a3fc"], ["tornado", "Tornado", "4", "#a8eedb"],
	["mirage", "Mirage", "5", "#f4a584"], ["slow", "Slow time", "6", "#a9bdff"],
	["portal", "Portal", "7", "#cda9ff"], ["shockwave", "Shockwave", "8", "#ffb979"],
	["redirect", "Redirect", "9", "#c0edc9"],
]
const CHAPTERS := [
	"First Lightning", "City at Mach One", "Red Signal", "Ghost in the Street",
	"The Second Before", "Through the Wall", "Black Velocity", "Infinite Moment",
]
const TAB_LIST := [
	["mission","Operations"], ["map","City map"], ["upgrade","Workshop"],
	["cache","Rift cache"], ["loadout","Inventory"], ["settings","Settings"], ["touch","Touch layout"], ["help","Controls"],
]
const TIER_NAMES := ["STREET","ENHANCED","SONIC","HYPERSONIC","EXTREME","RELATIVISTIC","MYTHIC","UNBOUND"]
const STICK := "joystick"
const PAUSE := "pause_menu"
const OPERATIONS := "operations_menu"
const AUDIO_SETTINGS := {
	"master_volume": ["Master", "master", 1.0],
	"music_volume": ["Music", "music", .75],
	"sfx_volume": ["Sound effects", "sfx", .8],
	"voice_volume": ["Voice", "voice", .9],
}

var game
var axis := Vector2.ZERO
var sprint := false
var boost := false
var limiter := 1.0
var touch_mode := false
var owners: Dictionary = {}
var holds: Dictionary = {}
var action_boxes: Dictionary = {}
var ability_boxes: Dictionary = {}
var active_rects: Dictionary = {}
var custom_layout: Dictionary = {}
var menu_buttons: Array[Button] = []
var menu_sliders: Array[HSlider] = []
var overlay: Control
var panel: PanelContainer
var menu_row: HBoxContainer
var side: VBoxContainer
var body: VBoxContainer
var scroll: ScrollContainer
var content: VBoxContainer
var menu_title: Label
var menu_detail: Label
var menu_current := ""
var editor := false
var editor_selected := STICK
var wheel_open := false
var scene_ending := false
var _wheel_index := 0
var _refresh := .08
var _last_device := "keyboard"
var _sprint_latched := false
var _font: Font
var _heavy: FontVariation
var _config: Dictionary = {}
var _data: Dictionary = {}
var _mission := ""
var _objective := ""
var _status := ""
var _dialogue := ""
var _line := ""
var _health := 100.0
var _energy := 100.0
var _speed := 0.0
var _credit := 0
var _heading := 0.0
var _loc := Vector3.ZERO
var _target := Vector3.ZERO
var _mission_index := 0
var _district := "CALDER EXCHANGE"
var _speed_card := Rect2()
var _slider_box := Rect2()
var _toolbar_pause := Rect2()
var _toolbar_mission := Rect2()
var _wheel_close := Rect2()
var _tooltip := ""
var _help_timer := 0.0
var _cinematic := false
var _boss: Dictionary = {}
var _mouse_camera := false
var _menu_needs_redraw := false
var _last_cache_key := ""
var _reveal: Tween
var _animate_reveal := false
var _save_message := ""
var _fx_time := 0.0
var _rewind_available := 0.0
var _rewind_active := false
var _rewind_remaining := 0.0
var _slow_time := false
var _phased := false
var _audio_unlocked := true
var _circuit_action := Rect2()


func setup(owner_game) -> void:
	game = owner_game
	name = "VelocityHUD"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_heavy = FontVariation.new()
	_heavy.base_font = _font
	_heavy.variation_embolden = 0.68
	touch_mode = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_audio_unlocked = not OS.has_feature("web")
	if touch_mode:
		_last_device = "touch"
	var file := FileAccess.open("res://shared/game.json", FileAccess.READ)
	if file:
		var defaults = JSON.parse_string(file.get_as_text())
		if defaults is Dictionary:
			_data = defaults
	_config = _settings().duplicate(true)
	var placement = _config.get("hud_layout", {})
	if placement is Dictionary:
		custom_layout = _valid_layout(placement)
	limiter = clampf(float(_config.get("limiter", _config.get("speed_limiter", 1.0))), .10, 1.0)
	AudioServer.set_bus_mute(0, bool(_config.get("audio_muted", false)))
	var presentation: Variant = _prop(game, "presentation")
	for key in AUDIO_SETTINGS:
		if presentation != null and presentation.has_method("setting"):
			var option: Array = AUDIO_SETTINGS[key]
			presentation.setting(key, float(_config.get(key, _config.get(option[1], option[2]))))
	_build_menu()
	resized.connect(_viewport_resized)
	_layout()
	tick(0.0)


func _prop(object: Variant, key: String, fallback: Variant = null) -> Variant:
	if object == null:
		return fallback
	var value: Variant = object.get(key)
	return fallback if value == null else value


func _settings() -> Dictionary:
	var settings: Variant = _prop(_prop(game, "progress"), "settings", {})
	if settings is Dictionary:
		return settings
	return {}


func _save_setting(key: String, value: Variant) -> void:
	if value is Dictionary or value is Array:
		value = value.duplicate(true)
	var settings := _settings()
	_config[key] = value
	if settings.get(key) == value:
		return
	if key == "audio_muted":
		AudioServer.set_bus_mute(0, bool(value))
	if key == "text_scale":
		_menu_needs_redraw = true
	if key == "sprint_toggle" and not value:
		_sprint_latched = false
	if game != null and game.has_method("configure_settings"):
		game.configure_settings(key, value)
	else:
		_settings()[key] = value
		var progress: Variant = _prop(game, "progress")
		if progress != null and progress.has_method("save"):
			progress.save()


func _valid_layout(saved: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array[String] = [STICK, "limiter", PAUSE, OPERATIONS]
	for action in ACTIONS:
		keys.push_back(action[0])
	for key in keys:
		var raw = saved.get(key)
		if raw is Dictionary:
			var coordinate = raw.get("anchor", [])
			var scale_value = raw.get("scale", 1.0)
			if coordinate is Array and coordinate.size() == 2 and _is_number(coordinate[0]) and _is_number(coordinate[1]) and _is_number(scale_value):
				var x := float(coordinate[0])
				var y := float(coordinate[1])
				var multiplier := float(scale_value)
				if is_finite(x) and is_finite(y) and is_finite(multiplier):
					result[key] = {"anchor": [clampf(x, 0.0, 1.0), clampf(y, 0.0, 1.0)],
						"scale": clampf(multiplier, .7, 1.65)}
	return result


func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _arrange(key: String, nominal: Rect2) -> Rect2:
	var raw: Dictionary = custom_layout.get(key, {})
	if raw.is_empty():
		return nominal
	var anchor: Array = raw.get("anchor", [0.5, 0.5])
	var extent := nominal.size * float(raw.get("scale", 1.0))
	var midpoint := Vector2(float(anchor[0]) * size.x, float(anchor[1]) * size.y)
	var half := extent * .5
	var limit := Vector2(16, 16)
	midpoint = midpoint.clamp(half + limit, size - half - limit)
	return Rect2(midpoint - half, extent)


func _viewport_resized() -> void:
	flush_inputs()
	_layout()


func _layout() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return
	var edge := clampf(size.x * .024, 16.0, 36.0)
	var compact := size.y < 592.0
	var r := clampf(size.y * .168, 88.0, 134.0)
	var w := clampf(size.y * .075, 44.0, 62.0)
	var stride := w + (10.0 if compact else 13.0)
	_speed_card = Rect2(size - Vector2(edge + 245.0, edge + 132.0), Vector2(245.0, 132.0))
	_slider_box = Rect2(_speed_card.position + Vector2(14, 104), Vector2(216, 22))
	var right := size.x - edge - w
	var bottom := _speed_card.position.y - (w + 11.0)
	action_boxes[STICK] = _arrange(STICK, Rect2(edge + 5, size.y - edge - r, r, r))
	action_boxes["limiter"] = _arrange("limiter", _slider_box)
	action_boxes[PAUSE] = _arrange(PAUSE, Rect2(size.x - edge - 54.0, edge, 54.0, 42.0))
	action_boxes[OPERATIONS] = _arrange(OPERATIONS, Rect2(size.x - edge - 141.0, edge, 77.0, 42.0))
	for index in range(ACTIONS.size()):
		var key: String = ACTIONS[index][0]
		var col := index % 4
		var row := floori(index / 4.0)
		var position := Vector2(right - (3-col) * stride, bottom - row * stride)
		# Interaction and target actions stay in dedicated slots. Nothing reflows when a verb appears.
		action_boxes[key] = _arrange(key, Rect2(position, Vector2(w, w)))
	for key in custom_layout:
		if action_boxes.has(key) and _crowded(key, action_boxes[key]):
			# Normalized anchors can converge at a narrower aspect ratio. Keep each
			# actionable region reachable while preserving its saved position.
			action_boxes[key] = _nearby_space(key, action_boxes[key])
	_toolbar_pause = action_boxes[PAUSE]
	_toolbar_mission = action_boxes[OPERATIONS]
	var scale_w := minf(size.x - 48.0, 924.0)
	var scale_h := minf(size.y - 62.0, 601.0)
	if panel:
		panel.position = (size - Vector2(scale_w, scale_h)) * .5
		panel.size = Vector2(scale_w, scale_h)
	if wheel_open:
		_layout_wheel()
	_update_active_rects()
	queue_redraw()


func _crowded(key: String, candidate: Rect2) -> bool:
	for other in action_boxes:
		if other != key and candidate.grow(8.0).intersects(action_boxes[other]):
			return true
	return false


func _nearby_space(key: String, original: Rect2) -> Rect2:
	var edge := Vector2(16,16)
	for step in range(1,7):
		for index in range(8):
			var offset := Vector2.from_angle(float(index)*TAU*.125)*float(step)*42.0
			var candidate := Rect2((original.position+offset).clamp(edge,size-original.size-edge), original.size)
			if not _crowded(key,candidate):
				return candidate
	return original


func _layout_wheel() -> void:
	var midpoint := Vector2(size.x * .56, size.y * .49)
	var radius := clampf(minf(size.x, size.y)*.24, 118.0, 190.0)
	var width := minf(clampf(size.x*.092, 78.0, 118.0), radius*.67)
	var height := clampf(radius*.27, 39.0, 52.0)
	ability_boxes.clear()
	for i in range(ABILITIES.size()):
		var angle := float(i) / ABILITIES.size() * TAU - PI*.5
		var key: String = ABILITIES[i][0]
		var center := midpoint + Vector2(cos(angle), sin(angle))*radius
		ability_boxes[key] = Rect2(center - Vector2(width, height)*.5, Vector2(width, height))
	_wheel_close = Rect2(midpoint - Vector2(56, 25), Vector2(112, 50))


func tick(dt: float) -> void:
	_refresh += dt
	_fx_time += dt
	_help_timer = maxf(0.0, _help_timer - dt)
	if _font == null or game == null:
		return
	if _refresh >= .045 or dt == 0.0:
		_refresh = 0.0
		_health = float(_prop(game, "health", 100.0))
		_energy = float(_prop(game, "energy", 100.0))
		_speed = float(_prop(game, "speed", 0.0))
		_mission = str(_prop(game, "mission_title", "Free patrol"))
		_objective = str(_prop(game, "objective_text", "Explore Calder Exchange"))
		_dialogue = str(_prop(game, "dialogue", ""))
		_status = str(_prop(game, "status_text", ""))
		var body3d: Variant = _prop(game, "runner")
		if body3d is Node3D:
			_loc = body3d.position
		var target: Variant = _prop(game, "target_position", _loc)
		if target is Vector3:
			_target = target
		var orbit: Variant = _prop(game, "orbit", Vector2.ZERO)
		if orbit is Vector2:
			_heading = orbit.x
		var boss: Variant = _prop(game, "boss_status", {})
		if boss is Dictionary:
			_boss = boss
		var profile: Variant = _prop(game, "progress")
		_credit = int(_prop(profile, "credits", 0))
		var campaign: Variant = _prop(game, "campaign")
		_mission_index = int(_prop(campaign, "mission_index", 0))
		var history: Variant = _prop(game, "history")
		_rewind_active = bool(_prop(history, "active", false))
		_rewind_remaining = float(_prop(history, "remaining_seconds", 0.0))
		if history is Object and history.has_method("available_seconds"):
			_rewind_available = float(history.available_seconds())
		else:
			_rewind_available = 0.0
		var powers_sys: Variant = _prop(game, "powers")
		_slow_time = powers_sys is Object and powers_sys.has_method("slow_factor") and float(powers_sys.slow_factor()) < 0.99
		_phased = powers_sys is Object and powers_sys.has_method("phased") and bool(powers_sys.phased())
		var cinematic := float(_prop(game, "_cinema_timer", 0.0)) > 0.0
		if cinematic and not _cinematic:
			flush_inputs()
			_set_wheel(false)
		_cinematic = cinematic
		_district = _district_for(_loc)
		_line = _movement_context()
		_update_active_rects()
		if menu_current == "cache":
			var marker := str(_credit) + str(_cache_result())
			if marker != _last_cache_key:
				_last_cache_key = marker
				_menu_needs_redraw = true
		queue_redraw()
	if _menu_needs_redraw and not menu_current.is_empty():
		_menu_needs_redraw = false
		_render_menu()


func _district_for(at: Vector3) -> String:
	if str(_prop(game, "realm", "city")) == "rift":
		return "THE SPEED FORCE"
	if at.x < -57.0:
		return "SOUTH CANAL"
	if at.x > 52.0:
		return "FOUNDRY WARD"
	if at.z < -157.0:
		return "MERIDIAN HEIGHTS"
	return "CALDER EXCHANGE"


func _movement_context() -> String:
	var history: Variant = _prop(game, "history")
	if bool(_prop(history, "active", false)):
		return "REWINDING %.1f S" % float(_prop(history, "remaining_seconds", 0.0))
	if bool(_prop(game, "wall_riding", false)):
		return "WALL RUN"
	if bool(_prop(game, "on_water", false)):
		return "WATER RUN"
	if bool(_prop(game, "transit_active", false)):
		return "EXTREME TRANSIT"
	if bool(_prop(game, "boosting", false)):
		return "BOOST ACTIVE"
	return ""


func _update_active_rects() -> void:
	active_rects.clear()
	if not editor and bool(_prop(_prop(game, "midnight"), "running", false)):
		active_rects[STICK] = action_boxes[STICK]
		active_rects["limiter"] = action_boxes["limiter"]
		var edge := clampf(size.x * .024, 16.0, 36.0)
		var w := 92.0
		for i in range(4):
			var key: String = ["boost", "sprint", "jump", "slide"][i]
			var at := Vector2(size.x - edge - w - (w + 13.0) * i, _speed_card.position.y - w - 13.0)
			var area := Rect2(at, Vector2(w,w))
			active_rects[key] = action_boxes[key] if custom_layout.has(key) else area
		return
	var fight := bool(_prop(game,"in_combat",not _boss.is_empty()))
	var near_action := bool(_prop(game,"interaction_available",_loc.distance_to(_target) < 14.0))
	var population: Variant = _prop(game, "population")
	if not near_action and population is Object and population.has_method("can_interact"):
		near_action = population.can_interact()
	for key in action_boxes:
		if not editor and key in [PAUSE, OPERATIONS]:
			continue
		if not editor and ((key == "counter" or key == "lock" or key == "heavy") and not fight):
			continue
		if not editor and key == "interact" and not near_action and not fight:
			continue
		if not editor and key == "slide" and _speed < 5.0:
			continue
		active_rects[key] = action_boxes[key]


func flush_inputs() -> void:
	owners.clear()
	holds.clear()
	axis = Vector2.ZERO
	boost = false
	sprint = false
	_sprint_latched = false
	_mouse_camera = false
	queue_redraw()


func _press_action(key: String, index: int) -> void:
	if key == "powers":
		_set_wheel(not wheel_open)
	elif key == "sprint" and bool(_config.get("sprint_toggle", false)):
		_sprint_latched = not _sprint_latched
		_sync_holds()
	elif key == "boost" or key == "sprint":
		holds[index] = key
		_sync_holds()
	else:
		_issue(key)


func _sync_holds() -> void:
	boost = holds.values().has("boost")
	sprint = holds.values().has("sprint") or boost or _sprint_latched


func _issue(action: String) -> void:
	if game != null:
		game.command(action)


func _aim(delta: Vector2) -> void:
	if game != null:
		game.look_delta(delta)


func _set_wheel(shown: bool) -> void:
	if shown and bool(_prop(_prop(game, "midnight"), "running", false)):
		return
	if shown != wheel_open:
		flush_inputs()
	wheel_open = shown
	if shown:
		_layout_wheel()
	queue_redraw()


func _set_limiter(at: Vector2) -> void:
	var track: Rect2 = action_boxes.get("limiter", _slider_box)
	limiter = snappedf(lerpf(.10, 1.0, clampf((at.x-track.position.x)/track.size.x, 0.0, 1.0)), .01)
	queue_redraw()


func _set_stick(at: Vector2) -> void:
	var rect: Rect2 = action_boxes.get(STICK, Rect2())
	var off := (at - rect.get_center()) / maxf(rect.size.x * .41, 1.0)
	axis = Vector2(off.x, -off.y).limit_length()
	if axis.length_squared() < .0064:
		axis = Vector2.ZERO
	queue_redraw()


func _action_at(at: Vector2) -> String:
	var nearest := 9999999.0
	var result := ""
	for key in active_rects:
		var rect: Rect2 = active_rects[key]
		var inside := rect.grow(4.0).has_point(at)
		if inside:
			var distance := rect.get_center().distance_squared_to(at)
			if distance < nearest:
				result = key
				nearest = distance
	return result


func _capture(index: int, kind: String, at: Vector2, key := "") -> void:
	owners[index] = {"kind": kind, "key": key, "origin": at, "last": at, "travel": 0.0}


func _has_owner(kind: String) -> bool:
	for owner in owners.values():
		if owner["kind"] == kind:
			return true
	return false


func _note(message: String, duration := 2.0) -> void:
	_tooltip = message
	_help_timer = duration
	queue_redraw()


func _touch_down(index: int, at: Vector2) -> void:
	if owners.has(index):
		return
	if editor:
		var option := _editor_option(at)
		if not option.is_empty():
			_editor_command(option)
			return
		var selected := _action_at(at)
		if not selected.is_empty():
			editor_selected = selected
			_capture(index, "edit", at, selected)
		return
	if not menu_current.is_empty():
		var slider := _menu_slider_at(at)
		if slider and not _has_owner("menu_slider"):
			_capture(index, "menu_slider", at)
			owners[index]["node"] = slider
			_mapped_slider(slider, at)
		else:
			_capture(index, "menu", at)
			owners[index]["node"] = _menu_button_at(at)
		return
	if _cinematic:
		if _toolbar_pause.has_point(at):
			_issue("skip")
		return
	if _circuit_action.has_point(at):
		_issue("restart" if bool(_prop(_prop(game, "midnight"), "running", false)) else "midnight")
		return
	if _toolbar_pause.has_point(at):
		show_menu("settings")
		return
	if _toolbar_mission.has_point(at):
		show_menu("mission")
		return
	if wheel_open:
		for key in ability_boxes:
			if (ability_boxes[key] as Rect2).has_point(at):
				_activate_power(key)
				return
		if _wheel_close.has_point(at) or _action_at(at) == "powers":
			_set_wheel(false)
		return
	var key := _action_at(at)
	if not key.is_empty():
		if key in [STICK, "limiter"] and _has_owner(key):
			return
		_capture(index, key, at, key)
		if key == STICK:
			_set_stick(at)
		elif key == "limiter":
			_set_limiter(at)
		else:
			_press_action(key, index)
		return
	if at.x > size.x * .50 and not _has_owner("camera"):
		_capture(index, "camera", at)


func _touch_drag(index: int, at: Vector2, delta: Vector2) -> void:
	if not owners.has(index):
		return
	var entry: Dictionary = owners[index]
	entry["travel"] = float(entry["travel"]) + delta.length()
	entry["last"] = at
	match str(entry["kind"]):
		STICK: _set_stick(at)
		"camera": _aim(delta)
		"limiter": _set_limiter(at)
		"edit": _place_editor(str(entry["key"]), at)
		"menu_slider":
			var slider: HSlider = entry.get("node")
			if is_instance_valid(slider):
				_mapped_slider(slider, at)
		"menu":
			if is_instance_valid(scroll) and scroll.get_global_rect().has_point(entry["origin"]) and float(entry["travel"]) > 10.0:
				scroll.scroll_vertical -= roundi(delta.y)


func _touch_up(index: int, at: Vector2, cancelled: bool) -> void:
	if not owners.has(index):
		return
	var entry: Dictionary = owners[index]
	owners.erase(index)
	match str(entry["kind"]):
		STICK: axis = Vector2.ZERO
		"limiter": _save_setting("limiter", limiter)
		"edit": _save_setting("hud_layout", custom_layout)
		"menu_slider":
			var slider: HSlider = entry.get("node")
			if is_instance_valid(slider):
				_save_setting(str(slider.get_meta("setting")), slider.value)
		"menu":
			var button: Button = entry.get("node")
			if not cancelled and float(entry["travel"]) < 16 and is_instance_valid(button) and button == _menu_button_at(at):
				button.pressed.emit()
	holds.erase(index)
	_sync_holds()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventScreenTouch:
		_audio_unlocked = true
		_last_device = "touch"
		if not touch_mode:
			touch_mode = true
			_update_active_rects()
		if event.pressed and not event.canceled:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index, event.position, event.canceled)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_audio_unlocked = true
		_last_device = "keyboard"
		if event.button_index == MOUSE_BUTTON_LEFT and menu_current.is_empty():
			if event.pressed:
				var at: Vector2 = event.position
				if editor or wheel_open or _toolbar_pause.has_point(at) or _toolbar_mission.has_point(at) or _circuit_action.has_point(at) or (action_boxes.get("limiter", _slider_box) as Rect2).has_point(at):
					_touch_down(-7, at)
					get_viewport().set_input_as_handled()
				else:
					_mouse_camera = true
			else:
				_mouse_camera = false
				_touch_up(-7, event.position, false)
	elif event is InputEventMouseMotion:
		if _mouse_camera:
			_aim(event.relative)
			get_viewport().set_input_as_handled()
		elif owners.has(-7):
			_touch_drag(-7, event.position, event.relative)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		_audio_unlocked = true
		_last_device = "keyboard"
		if event.physical_keycode == KEY_ESCAPE:
			if editor:
				_editor_command("done")
			elif not menu_current.is_empty():
				_close_menu()
			elif wheel_open:
				_set_wheel(false)
			elif _cinematic:
				_issue("skip")
			else:
				show_menu("settings")
			get_viewport().set_input_as_handled()
		elif menu_current.is_empty() and not editor and event.physical_keycode == KEY_Q:
			_set_wheel(not wheel_open)
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		_audio_unlocked = true
		_last_device = "gamepad"
		if event.button_index == JOY_BUTTON_START:
			if editor:
				_editor_command("done")
			elif menu_current.is_empty():
				show_menu("mission")
			else:
				_close_menu()
			get_viewport().set_input_as_handled()
		elif editor and event.button_index == JOY_BUTTON_B:
			_editor_command("done")
			get_viewport().set_input_as_handled()
		elif not menu_current.is_empty() and _menu_gamepad(event.button_index):
			get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER and menu_current.is_empty():
			_set_wheel(not wheel_open)
			get_viewport().set_input_as_handled()
		elif wheel_open and event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_A, JOY_BUTTON_B]:
			if event.button_index == JOY_BUTTON_A:
				_activate_power(ABILITIES[_wheel_index][0])
			elif event.button_index == JOY_BUTTON_B:
				_set_wheel(false)
			else:
				var change := -1 if event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP] else 1
				_wheel_index = posmod(_wheel_index+change, ABILITIES.size())
				queue_redraw()
			get_viewport().set_input_as_handled()


func _menu_gamepad(button_index: JoyButton) -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	match button_index:
		JOY_BUTTON_A:
			if focused is Button and not focused.disabled:
				focused.pressed.emit()
		JOY_BUTTON_B:
			_close_menu()
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			var change := -1 if button_index == JOY_BUTTON_LEFT_SHOULDER else 1
			for index in range(TAB_LIST.size()):
				if TAB_LIST[index][0] == menu_current:
					_switch_tab(TAB_LIST[posmod(index+change,TAB_LIST.size())][0])
					return true
			_switch_tab("mission")
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			var direction := -1 if button_index == JOY_BUTTON_DPAD_UP else 1
			var items: Array[Control] = _menu_controls() if is_instance_valid(focused) and content.is_ancestor_of(focused) else _menu_tabs()
			if not items.is_empty():
				items[posmod(items.find(focused)+direction,items.size())].grab_focus()
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if focused is HSlider:
				var sign_ := -1 if button_index == JOY_BUTTON_DPAD_LEFT else 1
				focused.value += (focused.max_value-focused.min_value)*.05*sign_
				_save_setting(str(focused.get_meta("setting")),focused.value)
			elif button_index == JOY_BUTTON_DPAD_LEFT:
				_focus_tab()
			else:
				var items := _menu_controls()
				if not items.is_empty():
					items[0].grab_focus()
		_:
			return false
	return true


func _menu_tabs() -> Array[Control]:
	var items: Array[Control] = []
	for button in side.get_children():
		if button is Button:
			items.push_back(button)
	return items


func _menu_controls() -> Array[Control]:
	var items: Array[Control] = []
	for row in content.get_children():
		if row is PanelContainer:
			for field in row.get_child(0).get_children():
				if field is HSlider or (field is Button and field.visible and not field.disabled):
					items.push_back(field)
	return items


func _focus_tab() -> void:
	for button in _menu_tabs():
		if button.text == menu_title.text:
			button.grab_focus()
			return
	if side.get_child_count() > 0:
		side.get_child(0).grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _font != null:
			flush_inputs()
			_set_wheel(false)


func _stroke_text(pos: Vector2, message: String, point_size: int, color := MILK, strong := false, width := -1.0) -> void:
	draw_string(_heavy if strong else _font, pos, message, HORIZONTAL_ALIGNMENT_LEFT, width, point_size, color)


func _center_text(at: Vector2, message: String, point_size: int, color := MILK, strong := false) -> void:
	var font: Font = _heavy if strong else _font
	var extent := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, point_size)
	draw_string(font, Vector2(at.x-extent.x*.5, at.y), message, HORIZONTAL_ALIGNMENT_LEFT, -1.0, point_size, color)


func _tile(rect: Rect2, anchor_color := BORDER, fill := CARD) -> void:
	var high_contrast := bool(_config.get("high_contrast", false))
	draw_rect(rect, Color("#050a12") if high_contrast else fill)
	draw_rect(rect, Color("#8ec2e7") if high_contrast else BORDER, false, 1.0)
	draw_rect(Rect2(rect.position, Vector2(minf(rect.size.x, 46.0), 1.9)), anchor_color)


func _draw_bar(pos: Vector2, width: float, ratio: float, tint: Color) -> void:
	draw_rect(Rect2(pos, Vector2(width, 4)), Color(1, 1, 1, .12))
	draw_rect(Rect2(pos, Vector2(width * clampf(ratio, 0.0, 1.0), 4)), tint)


func _draw_bolt(point: Vector2, factor: float, tint := AMBER) -> void:
	var outline := PackedVector2Array([
		point + Vector2(13, 0)*factor, point + Vector2(32, 0)*factor,
		point + Vector2(20, 14)*factor, point + Vector2(30, 14)*factor,
		point + Vector2(4, 39)*factor, point + Vector2(13, 20)*factor,
		point + Vector2(1, 20)*factor,
	])
	draw_colored_polygon(outline, tint)


func _draw_pause_icon() -> void:
	var center := _toolbar_pause.get_center()
	var scale := minf(_toolbar_pause.size.x/54.0,_toolbar_pause.size.y/42.0)
	draw_rect(Rect2(center + Vector2(-6,-7)*scale,Vector2(4,14)*scale),MILK)
	draw_rect(Rect2(center + Vector2(2,-7)*scale,Vector2(4,14)*scale),MILK)


func _draw_top_controls() -> void:
	_tile(_toolbar_pause, BORDER, Color("#111c28db"))
	_draw_pause_icon()
	_tile(_toolbar_mission, AMBER, Color("#111c28db"))
	_center_text(_toolbar_mission.get_center()+Vector2(0,5), "OPS", 13, AMBER, true)


func _draw_screen_fx() -> void:
	var fx_enabled := bool(_config.get("effects", true))
	var reduced_motion := bool(_config.get("reduced_motion", false))
	var reduced_flash := bool(_config.get("reduced_flash", false))
	if fx_enabled and not reduced_motion and _speed > 34.0:
		var intensity := clampf((_speed - 34.0) / 86.0, 0.0, 1.0)
		var center := size * 0.5
		var outer_r := size.length() * 0.55
		var inner_r := minf(size.x, size.y) * lerpf(0.45, 0.34, intensity)
		var line_alpha := intensity * (0.20 if reduced_flash else 0.36)
		var streak_color := Color(1.0, 0.80, 0.44, line_alpha) if bool(_prop(game, "boosting", false)) or bool(_prop(game, "transit_active", false)) else Color(0.68, 0.90, 1.0, line_alpha * 0.85)
		for i in range(18):
			var angle := float(i) * (TAU / 18.0) + sin(_fx_time * 5.0 + float(i) * 1.9) * 0.025
			var phase := fmod(_fx_time * (2.6 + intensity * 2.4) + float(i) * 0.37, 1.0)
			var dir := Vector2(cos(angle), sin(angle))
			var p0 := center + dir * lerpf(inner_r, outer_r * 0.88, phase)
			var p1 := center + dir * outer_r
			draw_line(p0, p1, streak_color, lerpf(1.2, 2.4, intensity), true)
	if _slow_time:
		var slow_tint := Color(0.45, 0.68, 1.0, 0.14 if reduced_flash else 0.22)
		var band := 8.0
		draw_rect(Rect2(0, 0, size.x, band), slow_tint)
		draw_rect(Rect2(0, size.y - band, size.x, band), slow_tint)
		draw_rect(Rect2(0, band, band, size.y - band * 2.0), slow_tint)
		draw_rect(Rect2(size.x - band, band, band, size.y - band * 2.0), slow_tint)
	if _phased:
		var pulse := 0.5 + 0.5 * sin(_fx_time * 9.0)
		var phase_tint := Color(0.40, 0.92, 1.0, (0.14 if reduced_flash else 0.24) * (0.7 + 0.3 * pulse))
		draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), phase_tint, false, 4.0)
	if _rewind_active:
		var edge_a := 0.18 if reduced_flash else 0.30
		var rwd_tint := Color(0.56, 0.44, 0.98, edge_a)
		var b := 16.0
		draw_rect(Rect2(0, 0, size.x, b), rwd_tint)
		draw_rect(Rect2(0, size.y - b, size.x, b), rwd_tint)
		draw_rect(Rect2(0, b, b, size.y - b * 2.0), rwd_tint)
		draw_rect(Rect2(size.x - b, b, b, size.y - b * 2.0), rwd_tint)
		if not reduced_motion:
			var scan_y := fmod(_fx_time * 320.0, maxf(size.y, 64.0))
			draw_line(Vector2(0, scan_y), Vector2(size.x, scan_y), Color(0.66, 0.88, 1.0, 0.22), 2.0)
			draw_line(Vector2(0, size.y - scan_y), Vector2(size.x, size.y - scan_y), Color(0.70, 0.55, 1.0, 0.18), 1.5)
		var rwd_y := 180.0 if (not _boss.is_empty() and bool(_boss.get("visible", true))) else 118.0
		var badge := Rect2(size.x * 0.5 - 116.0, rwd_y, 232.0, 32.0)
		_tile(badge, Color("#b2a3fc"), Color("#121024e6"))
		_center_text(badge.get_center() + Vector2(0, 5), "<< REWINDING  -%.1fS >>" % _rewind_remaining, 13, Color("#d4c8ff"), true)


func _draw() -> void:
	_circuit_action = Rect2()
	if _font == null or size.x < 20.0:
		return
	var edge := clampf(size.x*.024, 16, 36)
	if not menu_current.is_empty():
		return
	if editor:
		draw_rect(Rect2(Vector2.ZERO,size),Color("#09111c3c"))
		_draw_top_controls()
		_draw_speed()
		_draw_touch()
		_draw_editor()
		return
	if _cinematic:
		draw_rect(Rect2(0, 0, size.x, size.y*.08), Color("#080c13"))
		draw_rect(Rect2(0, size.y*.90, size.x, size.y*.10), Color("#080c13"))
		_tile(_toolbar_pause, AMBER)
		_center_text(_toolbar_pause.get_center()+Vector2(0,5), "SKIP", 12, AMBER, true)
		_draw_dialogue()
		return
	_draw_screen_fx()
	var circuit: Variant = _prop(game, "midnight")
	if bool(_prop(circuit, "running", false)):
		_draw_circuit(edge, circuit)
		return
	_draw_bolt(Vector2(edge, edge + 2), .70)
	_stroke_text(Vector2(edge+31, edge+23), "PROJECT VELOCITY", 23, MILK, true)
	_stroke_text(Vector2(edge+32, edge+42), _district, 11, AMBER, true)
	var vital := Rect2(edge, edge+56, 233, 70)
	_tile(vital, CYAN, Color("#0e1722dc"))
	_stroke_text(vital.position+Vector2(10, 17), "VITAL", 11, TEXT, true)
	_stroke_text(vital.position+Vector2(163, 17), "%d SFC" % _credit, 12, AMBER, true, 68)
	_draw_bar(vital.position+Vector2(10, 24), 212, _health*.01, RED)
	_draw_bar(vital.position+Vector2(10, 35), 212, _energy*.01, CYAN)
	_draw_bar(vital.position+Vector2(10, 46), 212, _rewind_available / 8.0, Color("#b2a3fc"))
	_stroke_text(vital.position+Vector2(10, 64), "HP %d  ·  CHG %d  ·  RWD %.1fS" % [roundi(_health), roundi(_energy), _rewind_available], 9, TEXT, true)
	if size.x > 620.0:
		var wide := minf(size.x*.32, 404.0)
		var mission := Rect2((size.x-wide)*.5, edge, wide, 74)
		_tile(mission, AMBER, Color("#0d1520d6"))
		_stroke_text(mission.position+Vector2(14, 17), "CURRENT OPERATION", 10, AMBER, true)
		_stroke_text(mission.position+Vector2(14, 40), _mission, 20, MILK, true, wide-27)
		_stroke_text(mission.position+Vector2(14, 60), _objective, 13, TEXT, false, wide-27)
	else:
		var mission := Rect2(edge, edge+134, size.x-edge*2, 54)
		_tile(mission, AMBER, Color("#0d1520d6"))
		_stroke_text(mission.position+Vector2(10, 20), _mission, 16, MILK, true, mission.size.x-20)
		_stroke_text(mission.position+Vector2(10, 40), _objective, 12, TEXT, false, mission.size.x-20)
	_draw_top_controls()
	if size.x > 780:
		_draw_radar(Vector2(size.x-edge-69, edge+119), 55)
	_draw_speed()
	_draw_boss(edge)
	_draw_target_cue()
	if _last_device == "touch":
		_draw_touch()
	elif _last_device == "gamepad":
		_stroke_text(Vector2(edge, size.y-edge-22), "LEFT STICK  MOVE    ·    RIGHT STICK  LOOK    ·    LB  SPRINT    ·    RT  BOOST", 12, TEXT, true)
		_stroke_text(Vector2(edge, size.y-edge-3), "A  JUMP    ·    X  STRIKE    ·    D-PAD UP  INTERACT    ·    RB  POWERS", 12, TEXT, true)
	else:
		_stroke_text(Vector2(edge, size.y-edge-22), "WASD  MOVE    ·    DRAG  CAMERA    ·    SHIFT  SPRINT    ·    F  BOOST", 12, TEXT, true)
		_stroke_text(Vector2(edge, size.y-edge-3), "SPACE  JUMP    ·    J  STRIKE    ·    E  INTERACT    ·    Q  POWERS", 12, TEXT, true)
	if not _audio_unlocked and OS.has_feature("web") and _last_device != "touch":
		var hint_rect := Rect2(edge, edge + 134.0, 233.0, 22.0)
		_tile(hint_rect, CYAN, Color("#0e1722cc"))
		_center_text(hint_rect.get_center() + Vector2(0, 4), "CLICK OR TAP FOR AUDIO", 10, CYAN, true)
	if wheel_open:
		_draw_ability_wheel()
	elif _last_device != "touch" and size.x >= 750.0:
		_circuit_action = Rect2(edge, edge + 170.0, 198.0, 44.0)
		_tile(_circuit_action, Circuit.PINK, Color("#211534ed"))
		_center_text(_circuit_action.get_center() + Vector2(0,5), "PLAY MIDNIGHT CIRCUIT", 13, Circuit.WHITE, true)
	_draw_dialogue()


func _draw_circuit(edge: float, circuit: Variant) -> void:
	var wide := minf(432.0, size.x - edge * 2.0 - (222.0 if size.x > 610.0 else 0.0))
	var card := Rect2(Vector2((size.x - wide) * .5, edge if size.x > 610.0 else edge + 54.0), Vector2(wide, 90.0))
	_tile(card, Circuit.PINK, Color("#151632f3"))
	_stroke_text(card.position + Vector2(14,21), "MIDNIGHT CIRCUIT", 13, Circuit.PINK, true)
	_stroke_text(card.position + Vector2(14,54), "00:00.00" if circuit.elapsed <= 0.0 else Circuit.format_time(circuit.elapsed), 30, Circuit.WHITE, true)
	var pixel_scale := float(get_window().size.x) / maxf(size.x, 1.0)
	if get_window().size.y > get_window().size.x and pixel_scale < .43 and _last_device == "touch":
		var tip := Rect2(size.x * .5-355.0,size.y*.55,710.0,140.0)
		_tile(tip, Circuit.ICE, Color("#151632f5"))
		_center_text(tip.get_center()+Vector2(0,15), "ROTATE FOR LARGER CONTROLS", 43, Circuit.WHITE, true)
	var finish: String = circuit.finish_grade
	var gate_number: int = mini(circuit.gate + 1, Circuit.GATES.size())
	var gate_label := ("GATE %02d / %02d" % [gate_number, Circuit.GATES.size()]) if finish.is_empty() else finish
	var small := size.x < 520.0
	var right := card.end.x - (94.0 if small else 120.0)
	_stroke_text(Vector2(right,card.position.y + 21), gate_label, 13, Circuit.LIME, true)
	var pb: Array = game.progress.midnight_splits
	var compare := "BEST  " + ("—" if pb.is_empty() else Circuit.format_time(pb.back()))
	var compare_tint := TEXT
	if circuit.gate > 0 and circuit.previous_splits.size() == Circuit.GATES.size() and finish.is_empty():
		var gap: float = circuit.delta
		compare = "SPLIT %+0.2f S" % gap
		compare_tint = Circuit.LIME if gap <= 0.0 else Circuit.PINK
	_stroke_text(Vector2(right,card.position.y + 45), compare, 12, compare_tint, true)
	var slot := (wide - 28.0) / float(Circuit.GATES.size())
	for i in range(Circuit.GATES.size()):
		var tint := Circuit.ICE if i < circuit.gate else Circuit.LIME if i == circuit.gate else Color("#555576")
		draw_rect(Rect2(card.position.x+14.0+i*slot, card.end.y-18.0, slot-4.0, 4.0), tint)
	_draw_top_controls()
	if finish.is_empty():
		_draw_speed()
		if _last_device == "touch":
			_draw_touch()
		var hint := ""
		if circuit.count > 0.0:
			hint = str(ceili(circuit.count))
		elif circuit.go:
			hint = "GO"
		if not hint.is_empty():
			var start := Rect2(size.x*.5-57, size.y*.34-38, 114, 76)
			_tile(start, Circuit.LIME, Color("#141632ef"))
			_center_text(start.get_center()+Vector2(0,14), hint, 42, Circuit.LIME, true)
			if circuit.count > 0.0 and size.y > 410.0:
				_center_text(start.get_center()+Vector2(0,58), "12 GATES  ·  GOLD: %d S" % Circuit.GOLD, 14, Circuit.WHITE, true)
		elif circuit.pad_cue > 0.0:
			var boost_banner := Rect2(size.x*.5-82,card.end.y+10,164,30)
			_tile(boost_banner, Circuit.LIME, Color("#151632ec"))
			_center_text(boost_banner.get_center()+Vector2(0,5), "BOOST STRIP", 13, Circuit.LIME, true)
		if size.x >= 920.0:
			_draw_circuit_map(Vector2(size.x-edge-154,edge+59), circuit.gate)
		if _last_device != "touch" and size.x >= 750.0:
			var tip := "WASD  MOVE    ·    SHIFT  SPRINT    ·    F  BOOST    ·    R  RESTART"
			if _last_device == "gamepad":
				tip = "LEFT STICK  MOVE    ·    LB  SPRINT    ·    RT  BOOST    ·    START  OPS"
			_stroke_text(Vector2(edge,size.y-edge-5),tip,13,TEXT,true)
		return
	var result := Rect2(Vector2((size.x-minf(size.x-2*edge,374.0))*.5, maxf(card.end.y+10,size.y*.32)), Vector2(minf(size.x-2*edge,374.0),166))
	_tile(result, Circuit.LIME, Color("#141632f9"))
	_center_text(Vector2(result.get_center().x,result.position.y+27), "NEW PERSONAL BEST" if circuit.new_best else "CIRCUIT COMPLETE", 14, Circuit.ICE, true)
	_center_text(Vector2(result.get_center().x,result.position.y+62), Circuit.format_time(circuit.elapsed), 33, MILK, true)
	_center_text(Vector2(result.get_center().x,result.position.y+88), "%s   /   12 GATES" % finish, 14, Circuit.LIME, true)
	_circuit_action = Rect2(result.get_center().x-101,result.position.y+104,202,46)
	_tile(_circuit_action, Circuit.PINK, Color("#432651"))
	_center_text(_circuit_action.get_center()+Vector2(0,5), "RACE AGAIN", 14, MILK, true)


func _draw_circuit_map(at: Vector2, current: int) -> void:
	_tile(Rect2(at,Vector2(154,153)), Circuit.ICE, Color("#151632ee"))
	_stroke_text(at+Vector2(12,20), "SOUTH CANAL", 12, Circuit.ICE, true)
	var path := PackedVector2Array([at + Vector2(134,35)])
	for point: Vector3 in Circuit.GATES:
		path.append(at + Vector2(134 + point.x*.53, 35 - (point.z-8)*.52))
	draw_polyline(path, Color("#7983ae"), 2.0, true)
	for i in range(path.size()-1):
		draw_circle(path[i+1], 4.4 if i == current else 2.4, Circuit.LIME if i == current else Circuit.ICE if i < current else TEXT, true, -1.0, true)


func _draw_radar(midpoint: Vector2, radius: float) -> void:
	draw_circle(midpoint, radius, Color("#101b29df"), true, -1.0, true)
	draw_arc(midpoint, radius, 0.0, TAU, 50, Color("#9bb9cc72"), 1.25, true)
	draw_arc(midpoint, radius*.67, 0.0, TAU, 32, Color("#a1bdd731"), 1.0, true)
	for i in [0, 1, 2, 3]:
		var bearing := PI*.5*float(i)
		var direction := Vector2(cos(bearing), sin(bearing))
		draw_line(midpoint+direction*(radius-7), midpoint+direction*(radius-1), TEXT, 1.0, true)
	draw_colored_polygon(PackedVector2Array([midpoint+Vector2(0,-8), midpoint+Vector2(-5,5), midpoint+Vector2(5,5)]), CYAN)
	if _loc.distance_squared_to(_target) > 1.0:
		var target_delta := Vector2(_target.x-_loc.x, _target.z-_loc.z).rotated(_heading)
		target_delta = (target_delta * .24).limit_length(radius-9)
		var fi := midpoint + target_delta
		draw_circle(fi, 7.0, Color(AMBER,.25), true, -1.0, true)
		draw_circle(fi, 3.0, AMBER, true, -1.0, true)
	_center_text(midpoint+Vector2(0, radius+16), "OBJECTIVE", 9, TEXT, true)


func _draw_speed() -> void:
	_tile(_speed_card, AMBER, Color("#0e1722dc"))
	var base := _speed_card.position
	_stroke_text(base+Vector2(14,18),"VELOCITY",10,TEXT,true)
	var tier := str(_prop(game, "speed_tier", _prop(game,"tier","")))
	var profile: Variant = _prop(game, "progress")
	if tier.is_empty() and profile is Object and profile.has_method("rank_title"):
		tier = str(profile.rank_title())
	if tier.is_empty() or tier.is_valid_int() or tier.is_valid_float():
		var movement_tier := clampi(floori(log(maxf(_speed, 5.0)/5.0)*1.73), 0, TIER_NAMES.size()-1)
		if not tier.is_empty():
			movement_tier = clampi(int(tier), 0, TIER_NAMES.size()-1)
		tier = TIER_NAMES[movement_tier]
	_stroke_text(base+Vector2(98,18),"SPEC SUIT" if bool(_prop(_prop(game, "midnight"), "running", false)) else "RANK · " + tier.to_upper(),10,AMBER,true,136)
	var kmh := _speed * 3.6
	_stroke_text(base+Vector2(12,64),"%03d" % roundi(kmh),49,MILK,true,159)
	if kmh >= 1235.0:
		_stroke_text(base+Vector2(158,46),"MACH %.2f" % (kmh / 1234.8),11,CYAN,true)
		_stroke_text(base+Vector2(158,62),"KM/H",11,TEXT,true)
	else:
		_stroke_text(base+Vector2(160,60),"KM/H",12,TEXT,true)
	_draw_bar(base+Vector2(14,74),215,_speed/84.0,AMBER)
	var caption := _line if not _line.is_empty() else "SPEED LIMITER"
	_stroke_text(base+Vector2(14,94),caption.to_upper(),10,TEXT,true,172)
	_stroke_text(base+Vector2(190,94),"%d%%" % roundi(limiter*100),10,AMBER,true)
	var custom: Rect2 = action_boxes.get("limiter", _slider_box)
	var line := Rect2(custom.position+Vector2(0,custom.size.y*.42), Vector2(custom.size.x,4.0))
	draw_rect(line, Color("#3c4652"))
	draw_rect(Rect2(line.position, Vector2(line.size.x * inverse_lerp(.10, 1.0, limiter), line.size.y)), AMBER)
	for index in range(1,5):
		var tick_at := line.position + Vector2(line.size.x * index / 5.0, 9)
		draw_line(tick_at, tick_at + Vector2(0, 3), Color("#b3cbe691"), 1.0)
	draw_circle(line.position+Vector2(line.size.x * inverse_lerp(.10,1.0,limiter),2),7.0,AMBER,true,-1,true)


func _draw_boss(edge: float) -> void:
	if _boss.is_empty() or not bool(_boss.get("visible", true)):
		return
	var name_ := str(_boss.get("name", ""))
	if name_.is_empty():
		return
	var bar_w := minf(464.0, size.x * .46)
	var bar := Rect2((size.x-bar_w)*.5, edge + 86, bar_w, 56)
	_tile(bar, RED)
	var phase := " · PHASE %s" % str(_boss.get("phase", "")) if _boss.get("boss",false) else ""
	_stroke_text(bar.position+Vector2(13,19),"%s  %s" % [name_.to_upper(),phase],14,MILK,true,bar_w-29)
	var health := float(_boss.get("health", _boss.get("hp", 1.0)))
	_draw_bar(bar.position+Vector2(14,26),bar_w-28,health/maxf(float(_boss.get("max_health",_boss.get("max_hp",1.0))),1.0), RED)
	var alert := str(_boss.get("warning",_boss.get("telegraph","")))
	if not alert.is_empty():
		_stroke_text(bar.position+Vector2(14,46),alert.to_upper(),11,AMBER,true,bar_w-29)
	var combo := int(_boss.get("combo",0))
	if combo > 1:
		_stroke_text(bar.position+Vector2(bar_w-72,19),"%d HIT" % combo,11,CYAN,true,66)


func _draw_target_cue() -> void:
	var combat: Variant = _prop(game, "combat")
	var locked := str(_prop(combat, "locked_id", ""))
	var highlighted := bool(_boss.get("counter_window", false))
	if not highlighted and (locked.is_empty() or locked != str(_boss.get("id",""))):
		return
	var view: Variant = _prop(game, "camera")
	var at: Variant = _boss.get("target")
	if not view is Camera3D or not at is Vector3:
		return
	var world_point: Vector3 = at + Vector3.UP*2.4
	if view.is_position_behind(world_point):
		return
	var point: Vector2 = view.unproject_position(world_point)
	if not Rect2(Vector2(38,150), size-Vector2(76,235)).has_point(point):
		return
	var corners := PackedVector2Array([
		point+Vector2(0,-11), point+Vector2(11,0), point+Vector2(0,11), point+Vector2(-11,0), point+Vector2(0,-11),
	])
	draw_polyline(corners, Color("#071019"), 4.0, true)
	draw_polyline(corners, AMBER if highlighted else CYAN, 2.0, true)
	if highlighted:
		var caption := "COUNTER"
		_tile(Rect2(point+Vector2(-39,-35), Vector2(78,20)), AMBER)
		_center_text(point+Vector2(0,-21), caption, 10, AMBER, true)


func _draw_touch() -> void:
	var opacity := float(_config.get("button_opacity", 1.0))
	var high_contrast := bool(_config.get("high_contrast", false))
	if active_rects.has(STICK):
		var r: Rect2 = active_rects[STICK]
		var point := r.get_center()
		var radius := r.size.x*.5
		draw_circle(point,radius,Color(Color("#142330"), opacity * (.96 if high_contrast else .66)),true,-1,true)
		draw_arc(point,radius-.5,0,TAU,42,Color("#bcd2e194"),1.6,true)
		draw_arc(point,radius*.68,0,TAU,34,Color("#bcd2e147"),1.0,true)
		var cursor := point+Vector2(axis.x,-axis.y)*radius*.54
		draw_circle(cursor,radius*.31,Color("#88adbf95"),true,-1,true)
		draw_arc(cursor,radius*.31,0,TAU,28,Color("#d2ecf0cd"),1.4,true)
	var cooldowns := _cooldowns()
	for datum in ACTIONS:
		var key: String = datum[0]
		if not active_rects.has(key):
			continue
		var rect: Rect2 = active_rects[key]
		var center := rect.get_center()
		var radius := minf(rect.size.x,rect.size.y)*.5
		var pressed := _has_owner(key) or key=="sprint" and sprint or key=="powers" and wheel_open
		var highlight := key == "boost" or key == "powers" or key == "counter" and bool(_boss.get("counter_window",false))
		var tint := AMBER if highlight else CYAN
		var fill := Color("#593b2d") if pressed else Color("#07101b") if high_contrast else Color("#172431")
		draw_circle(center,radius,Color(fill,opacity * (.99 if high_contrast or pressed else .85)),true,-1,true)
		draw_arc(center,radius-.3,0,TAU,28,Color(tint,.85 if pressed else .55),1.45,true)
		var remaining := float(cooldowns.get(key,0.0))
		if remaining > 0.0:
			draw_arc(center,radius-2.5,-PI*.5,-PI*.5 + TAU*clampf(remaining/5.0,0.05,1.0),24,AMBER,2.4,true)
		elif key == "rewind" and _rewind_available > 0.15:
			draw_arc(center,radius-2.5,-PI*.5,-PI*.5 + TAU*clampf(_rewind_available/8.0,0.05,1.0),24,Color("#b2a3fc"),2.2,true)
		_draw_action_icon(key,center+Vector2(0,-8),radius,tint)
		_center_text(center+Vector2(0,14),datum[1],maxi(roundi(radius*.33),9),MILK,true)


func _draw_action_icon(key: String, center: Vector2, radius: float, tint: Color) -> void:
	var unit := radius / 13.0
	var line := maxf(1.2,radius*.063)
	match key:
		"boost":
			var bolt_scale := radius / 42.0
			_draw_bolt(center-Vector2(15,19)*bolt_scale,bolt_scale,tint)
		"jump", "slide":
			var up := -1.0 if key == "jump" else 1.0
			draw_line(center+Vector2(0,-4*up)*unit,center+Vector2(0,4*up)*unit,tint,line,true)
			_icon_line(center,unit,[Vector2(-3,up),Vector2(0,4*up),Vector2(3,up)],tint,line)
		"sprint":
			for offset in [-2.6,1.0]:
				_icon_line(center+Vector2(offset*unit,0),unit,[Vector2(-1.4,-3),Vector2(1.6,0),Vector2(-1.4,3)],tint,line)
		"light":
			draw_line(center+Vector2(-3,-3)*unit,center+Vector2(3,3)*unit,tint,line,true)
			draw_line(center+Vector2(-3,3)*unit,center+Vector2(3,-3)*unit,tint,line,true)
		"dodge":
			_icon_line(center,unit,[Vector2(-5,2),Vector2(-.8,-2),Vector2(4,-2),Vector2(1.6,-4.2)],tint,line)
			draw_line(center+Vector2(4,-2)*unit,center+Vector2(1.5,.1)*unit,tint,line,true)
		"counter":
			draw_arc(center,unit*3.7,-PI*.94,PI*.6,20,tint,line,true)
			_icon_line(center,unit,[Vector2(-4.5,-3.3),Vector2(-3.6,-.8),Vector2(-1.1,-1.8)],tint,line)
		"powers", "heavy":
			var span := radius*.34
			var diamond := PackedVector2Array([center+Vector2(0,-span),center+Vector2(span,0),center+Vector2(0,span),center+Vector2(-span,0)])
			if key == "powers":
				draw_colored_polygon(diamond,tint)
			else:
				diamond.append(diamond[0])
				draw_polyline(diamond,tint,line,true)
				draw_circle(center,unit,tint,true,-1,true)
		"lock":
			draw_circle(center,unit*3.7,tint,false,line,true)
			draw_circle(center,unit*1.2,tint,true,-1,true)
		"rewind":
			for offset in [-2.0,2.2]:
				draw_colored_polygon(PackedVector2Array([
					center+Vector2(offset-2.5,0)*unit,
					center+Vector2(offset+1.5,-3.0)*unit,
					center+Vector2(offset+1.5,3.0)*unit,
				]),tint)
		"interact":
			draw_circle(center,unit*3.4,tint,false,line,true)


func _icon_line(center: Vector2, unit: float, points: Array[Vector2], tint: Color, weight: float) -> void:
	var shape := PackedVector2Array()
	for point in points:
		shape.push_back(center+point*unit)
	draw_polyline(shape,tint,weight,true)


func _cooldowns() -> Dictionary:
	var status: Variant = _prop(_prop(game,"powers"),"cooldowns", {})
	return status if status is Dictionary else {}


func _activate_power(key: String) -> void:
	var remaining := float(_cooldowns().get(key,0.0))
	if remaining > 0.0:
		_note("Power ready in %.1f seconds" % remaining)
		return
	_issue(key)
	_set_wheel(false)


func _draw_ability_wheel() -> void:
	var center := _wheel_close.get_center()
	var radius := clampf(minf(size.x,size.y)*.24,118.0,190.0)
	draw_circle(center,radius+23,Color("#101925f1"),true,-1,true)
	draw_arc(center,radius-24,0,TAU,54,Color("#bfdce24c"),1.3,true)
	draw_arc(center,radius+23,0,TAU,54,Color("#bfdce25e"),1.5,true)
	var cooldowns := _cooldowns()
	for index in range(ABILITIES.size()):
		var ability: Array = ABILITIES[index]
		var rect: Rect2 = ability_boxes[ability[0]]
		var active := index==_wheel_index
		var remaining := float(cooldowns.get(ability[0],0.0))
		var tint := Color.html(ability[3])
		_tile(rect,tint,Color("#263749") if active else Color("#121e2b"))
		var text_color := MILK if remaining <= 0.0 else TEXT
		_center_text(rect.get_center()+Vector2(0,-1),str(ability[1]),13,text_color,true)
		var ready := "KEY  %s" % str(ability[2]) if _last_device == "keyboard" else "READY"
		var caption := "%.1f s" % remaining if remaining > 0.0 else ready
		_center_text(rect.get_center()+Vector2(0,17),caption,10,tint,true)
	_tile(_wheel_close,AMBER,Color("#17212e"))
	_center_text(center+Vector2(0,5),"CLOSE",12,AMBER,true)


func _draw_dialogue() -> void:
	var subtitles := bool(_config.get("subtitles", true))
	var message := _tooltip if _help_timer > 0.0 else (_dialogue if subtitles and not _dialogue.is_empty() else _status)
	if message.is_empty():
		return
	var cap := minf(size.x*.53,654)
	var y := size.y - (54.0 if _last_device == "touch" else 110.0)
	if _cinematic:
		y = size.y - 58.0
	var point_size := roundi(14*clampf(float(_config.get("text_scale",1.0)),.85,1.35))
	var words := message.split(" ",false)
	var lines: Array[String] = []
	var current := ""
	for word in words:
		var proposed := word if current.is_empty() else current+" "+word
		if _font.get_string_size(proposed,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x > cap-22 and not current.is_empty():
			lines.push_back(current)
			current = word
		else:
			current = proposed
	lines.push_back(current)
	var dialogue := Rect2((size.x-cap)*.5,y-(lines.size()-1)*19,cap,24+lines.size()*19)
	draw_rect(dialogue,Color("#101621e0"))
	draw_rect(dialogue,Color("#b9ccde38"),false,1.0)
	for i in range(lines.size()):
		_center_text(Vector2(size.x*.5,dialogue.position.y+24+i*19),lines[i],point_size,MILK,false)


func _build_menu() -> void:
	overlay = Control.new()
	overlay.name = "MenuOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("#050913c4")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.name = "OperationsPanel"
	panel.add_theme_stylebox_override("panel",_style(Color("#111925"),Color("#8aa6bf8c"),12,18))
	overlay.add_child(panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation",11)
	panel.add_child(shell)
	var header := HBoxContainer.new()
	shell.add_child(header)
	var led := VBoxContainer.new()
	led.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(led)
	var kicker := _label("PROJECT VELOCITY  /  COMMAND",12,AMBER,true)
	led.add_child(kicker)
	menu_title = _label("Operations",31,MILK,true)
	led.add_child(menu_title)
	menu_detail = _label("",13,TEXT)
	led.add_child(menu_detail)
	var closing := _new_button("RESUME  ›",_close_menu,true)
	closing.custom_minimum_size.x = 115
	closing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(closing)
	var trim := HSeparator.new()
	shell.add_child(trim)
	menu_row = HBoxContainer.new()
	menu_row.add_theme_constant_override("separation",14)
	menu_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(menu_row)
	side = VBoxContainer.new()
	side.custom_minimum_size.x = 158
	side.add_theme_constant_override("separation",5)
	menu_row.add_child(side)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_row.add_child(body)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	scroll.add_child(content)
	overlay.hide()


func _style(fill: Color, stroke: Color, radius := 5, padding := 8) -> StyleBoxFlat:
	var item := StyleBoxFlat.new()
	item.bg_color = fill
	item.border_color = stroke
	item.set_border_width_all(1)
	item.set_corner_radius_all(radius)
	for side_value in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		item.set_content_margin(side_value,padding)
	return item


func _label(message: String, point_size := 15, tint := MILK, hard := false) -> Label:
	var item := Label.new()
	item.text = message
	item.add_theme_font_override("font",_heavy if hard else _font)
	item.add_theme_font_size_override("font_size",roundi(point_size*clampf(float(_config.get("text_scale",1.0)),.85,1.35)))
	item.add_theme_color_override("font_color",tint)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item


func _new_button(message: String, callback: Callable, prominent := false) -> Button:
	var item := Button.new()
	item.text = message
	item.custom_minimum_size.y = 42
	item.add_theme_font_override("font",_heavy)
	item.add_theme_font_size_override("font_size",13)
	item.add_theme_color_override("font_color",Color("#161c24") if prominent else MILK)
	item.add_theme_color_override("font_hover_color",Color("#161c24") if prominent else CYAN)
	item.add_theme_stylebox_override("normal",_style(AMBER if prominent else Color("#1b2735"),BORDER,5,7))
	item.add_theme_stylebox_override("hover",_style(Color("#ffdbab") if prominent else Color("#263d4c"),CYAN,5,7))
	item.add_theme_stylebox_override("focus",_outline_style())
	item.add_theme_stylebox_override("pressed",_style(Color("#8b5b40"),AMBER,5,7))
	item.pressed.connect(callback)
	menu_buttons.push_back(item)
	return item


func _outline_style() -> StyleBoxFlat:
	var outline := _style(Color(0,0,0,0),CYAN,5,4)
	outline.set_border_width_all(2)
	return outline


func _info_row(title: String, detail: String, action: String="", callback: Callable=Callable(), accent := false) -> HBoxContainer:
	var block := PanelContainer.new()
	block.add_theme_stylebox_override("panel",_style(Color("#172231"),BORDER,6,9))
	content.add_child(block)
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation",12)
	block.add_child(group)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(info)
	var title_node := _label(title,15,MILK,true)
	title_node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title_node)
	if not detail.is_empty():
		var detail_node := _label(detail,13,TEXT)
		detail_node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(detail_node)
	if not action.is_empty() and callback.is_valid():
		var item := _new_button(action,callback,accent)
		item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		group.add_child(item)
	return group


func _section(title: String) -> void:
	var node := _label(title,11,AMBER,true)
	content.add_child(node)


func _action_row(label: String, description: String, title: String, code: String, accent := false) -> void:
	_info_row(label,description,title,func(): _menu_action(code),accent)


func _menu_action(key: String) -> void:
	if key in ["restart","race","rift_trial","patrol","next","skip","midnight"] or key.begins_with("replay_"):
		_close_menu()
	_issue(key)
	_menu_needs_redraw = true


func show_menu(tab := "mission") -> void:
	if _font == null:
		return
	var normalized: String = str(tab)
	if normalized == "missions":
		normalized = "mission"
	if normalized == "pause":
		normalized = "settings"
	if normalized == "touch_edit":
		_enter_editor()
		return
	editor = false
	_set_wheel(false)
	flush_inputs()
	menu_current = normalized
	_issue("pause_hud")
	overlay.show()
	_render_menu(true)
	queue_redraw()


func show_ending() -> void:
	scene_ending = true
	show_menu("ending")


func toggle_powers() -> void:
	if menu_current.is_empty() and not editor and not _cinematic:
		_set_wheel(not wheel_open)


func _close_menu() -> void:
	if menu_current.is_empty():
		return
	menu_current = ""
	overlay.hide()
	flush_inputs()
	_issue("resume")
	queue_redraw()


func _refresh_menu_after_command() -> void:
	_menu_needs_redraw = true


func _render_menu(rebuild_navigation := false) -> void:
	if menu_current.is_empty():
		return
	var tab_title := "Operations"
	for item in TAB_LIST:
		if item[0] == menu_current:
			tab_title = item[1]
	if menu_current == "ending":
		tab_title = "The city holds"
	menu_title.text = tab_title
	menu_detail.text = "%s     /     %d SFC" % [_district,_credit]
	var text_scale := clampf(float(_config.get("text_scale",1.0)),.85,1.35)
	menu_title.add_theme_font_size_override("font_size",roundi(31 * text_scale))
	menu_detail.add_theme_font_size_override("font_size",roundi(13 * text_scale))
	var contrasted := bool(_config.get("high_contrast",false))
	panel.add_theme_stylebox_override("panel",_style(Color("#091019") if contrasted else Color("#111925"),Color("#8ec2e7") if contrasted else Color("#8aa6bf8c"),12,18))
	var scroll_before := scroll.scroll_vertical if not rebuild_navigation else 0
	var focus_before := _menu_controls().find(get_viewport().gui_get_focus_owner())
	for child in content.get_children():
		child.queue_free()
		content.remove_child(child)
	if rebuild_navigation or side.get_child_count()==0:
		for child in side.get_children():
			child.queue_free()
			side.remove_child(child)
		for item in TAB_LIST:
			var tab: String = item[0]
			var menu_button := _new_button(item[1],func(): _switch_tab(tab),tab==menu_current)
			side.add_child(menu_button)
	_prune_menu_targets()
	match menu_current:
		"mission": _mission_menu()
		"map": _map_menu()
		"upgrade": _upgrade_menu()
		"cache": _cache_menu()
		"loadout": _inventory_menu()
		"settings": _settings_menu()
		"touch": _touch_menu()
		"help": _help_menu()
		"ending": _ending_menu()
		_: _mission_menu()
	call_deferred("_restore_scroll",scroll_before,rebuild_navigation,focus_before)


func _switch_tab(tab: String) -> void:
	menu_current = tab
	_render_menu(true)


func _restore_scroll(amount: int, focus_tab: bool, element: int) -> void:
	if not is_instance_valid(scroll):
		return
	scroll.scroll_vertical = amount
	if focus_tab:
		_focus_tab()
	elif element >= 0:
		var items := _menu_controls()
		if element < items.size():
			items[element].grab_focus()


func _prune_menu_targets() -> void:
	var buttons: Array[Button] = []
	for item in menu_buttons:
		if is_instance_valid(item) and item.is_inside_tree():
			buttons.push_back(item)
	menu_buttons = buttons
	var sliders: Array[HSlider] = []
	for item in menu_sliders:
		if is_instance_valid(item) and item.is_inside_tree():
			sliders.push_back(item)
	menu_sliders = sliders


func _mission_menu() -> void:
	_info_row(_mission if not _mission.is_empty() else "Current operation",_objective)
	if scene_ending or bool(_prop(_prop(game, "progress"), "finished", false)):
		_info_row("Story completed","View the campaign ending and optional city activities.","POSTGAME",func(): _switch_tab("ending"),true)
	var campaign: Variant = _prop(game,"campaign")
	var current_activity := str(_prop(campaign,"activity","campaign"))
	var is_circuit := current_activity == "midnight"
	var completed := bool(_prop(_prop(game, "progress"), "finished", false))
	if is_circuit:
		_action_row("Return to free patrol" if completed else "Return to the story", "Leave the circuit without losing your personal best.", "CONTINUE", "next")
	_action_row("Midnight Circuit", "12 neon gates, boost strips, and medals. Fixed suit stats. Gold: %d seconds." % Circuit.GOLD, "RETRY" if is_circuit else "PLAY", "midnight", true)
	_section("CAMPAIGN JOURNAL")
	if str(_prop(campaign,"activity","campaign")) in ["patrol","race","rift_trial","replay"]:
		_action_row("Return to the story","Resume the active campaign checkpoint.","CONTINUE","next",true)
	var ledger: Array = campaign.ledger() if campaign is Object and campaign.has_method("ledger") else []
	var chapter := int(_prop(campaign,"mission_index",_mission_index))
	for index in range(CHAPTERS.size()):
		var mission_title: String = CHAPTERS[index]
		var phase := "Complete" if index<chapter else ("Active" if index==chapter else "Locked")
		if index<ledger.size() and ledger[index] is Dictionary:
			mission_title = str(ledger[index].get("title",mission_title))
			phase = str(ledger[index].get("status",phase)).capitalize()
		var journal_title := "%02d   %s" % [index+1,mission_title]
		if phase == "Complete":
			_action_row(journal_title,"Complete  ·  Chapter rewards are granted once.","REPLAY","replay_%d" % index)
		else:
			_info_row(journal_title,phase)
	_section("CITY ACTIVITIES")
	_action_row("Calder Circuit","Run the seven checkpoints against your best time.","RACE","race")
	_action_row("Rift trial","Race the Speed Force course through the dimension.","ENTER","rift_trial")
	_action_row("Free patrol","Explore, respond to neighborhood signals and work on your speed.","PATROL","patrol")
	_action_row("Retry checkpoint","Restore the current objective from its latest checkpoint.","RETRY","restart")
	_section("PROFILE")
	var profile: Variant = _prop(game, "progress")
	var save_status := _save_message
	if save_status.is_empty():
		save_status = "Local browser storage is active." if bool(_prop(profile, "persistent", true)) else "Progress may be temporary in this browser."
	_info_row("Save progress",save_status,"SAVE",_save_profile)


func _save_profile() -> void:
	var profile: Variant = _prop(game, "progress")
	if profile is Object and profile.has_method("save"):
		var saved := bool(profile.save())
		_save_message = "Progress saved." if saved else str(_prop(profile,"last_error",""))
		if _save_message.is_empty():
			_save_message = "Local storage could not save progress."
		_refresh_menu_after_command()


func _map_menu() -> void:
	var map := RadarMap.new()
	map.hud = self
	map.custom_minimum_size = Vector2(330,330)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(map)
	_info_row("Map legend","Cyan marks the runner. Amber locates your active objective. Move toward its marker on the compass.")


func _upgrade_menu() -> void:
	var progress: Variant = _prop(game,"progress")
	var stats = _prop(progress,"stats",{})
	var rank := str(progress.rank_title()) if progress is Object and progress.has_method("rank_title") else ""
	_info_row("Balance     %d SFC" % _credit,rank)
	for datum in [["speed","Top speed","Raise your sprint and boost ceilings."],["accel","Acceleration","Get up to speed faster out of a turn."],["turn","Turning control","Retain momentum through tighter corners."]]:
		var key: String = datum[0]
		var action := "upgrade_"+key
		var cost := int(progress.upgrade_cost(key)) if progress is Object and progress.has_method("upgrade_cost") else 0
		var points := int(stats.get(key,0)) if stats is Dictionary else 0
		var buy := _info_row("%s   ·   Lv %d" % [datum[1],points],datum[2],"%d SFC" % cost,func(): _menu_action(action), _credit>=cost)
		(buy.get_child(1) as Button).disabled = _credit < cost
	_section("PRESTIGE")
	var price := int(progress.prestige_cost()) if progress is Object and progress.has_method("prestige_cost") else 180
	var ranks := _info_row("Advance your rank","Prestige requires level 5 in each stat and resets those stats for a higher speed rank.","%d SFC" % price,func(): _menu_action("prestige"))
	var qualified: bool = stats is Dictionary and int(stats.get("speed",0)) >= 5 and int(stats.get("accel",0)) >= 5 and int(stats.get("turn",0)) >= 5
	(ranks.get_child(1) as Button).disabled = _credit < price or not qualified


var _last_pull: Dictionary = {}


func set_cache_result(result: Dictionary) -> void:
	_last_pull = result.duplicate(true)
	_animate_reveal = not bool(_config.get("reduced_motion",false)) and not bool(_config.get("reduced_flash",false))
	_menu_needs_redraw = menu_current=="cache"
	queue_redraw()


func _cache_result() -> Dictionary:
	return _last_pull


func _cache_menu() -> void:
	var progress: Variant = _prop(game,"progress")
	var cost := int(_prop(progress,"pull_cost",_data.get("pullCost",25)))
	var materials := int(_prop(progress,"materials",0))
	var offer := _info_row("Rift cache     /     %d SFC" % _credit,"Spend charge earned in the city on trail variants. Main story powers are available through play.",
		"OPEN  ·  %d SFC" % cost,func(): _menu_action("pull"),true)
	(offer.get_child(1) as Button).disabled = _credit < cost
	var bundles := floori(float(materials) / 3.0)
	var redeem := _info_row("Salvage exchange   /   %d materials" % materials,"Convert duplicate trail materials into Speed Force Charge (3 materials = 1 SFC).",
		"EXCHANGE  +%d SFC" % maxi(bundles, 1),func(): _menu_action("redeem_materials"),bundles > 0)
	(redeem.get_child(1) as Button).disabled = materials < 3
	if not _last_pull.is_empty():
		var variant := str(_last_pull.get("name",""))
		var rank := str(_last_pull.get("rarity",""))
		var title := "%s   ·   %s" % [rank.to_upper(),variant] if not variant.is_empty() else str(_last_pull.get("message","Cache outcome"))
		var refund := ""
		if not variant.is_empty():
			refund = "Duplicate converted to %d materials" % int(_last_pull.get("salvage",0)) if bool(_last_pull.get("duplicate",false)) else "Added to inventory"
		var row := _info_row(title,refund)
		var info: VBoxContainer = row.get_child(0)
		var name_label: Label = info.get_child(0)
		var rarity_color := Color.from_string(str(_last_pull.get("color","#ffc079")),AMBER)
		name_label.add_theme_color_override("font_color",rarity_color)
		var block: PanelContainer = row.get_parent()
		block.add_theme_stylebox_override("panel",_style(Color("#172231"),rarity_color,6,11))
		if _animate_reveal and not variant.is_empty():
			_animate_reveal = false
			_start_cache_reveal(block,row)
	_section("DISCLOSED RARITY ODDS")
	var odds = _prop(progress,"rarities",_data.get("rarities",[]))
	if odds is Array:
		for pool in odds:
			if pool is Dictionary:
				var title := str(pool.get("name",""))
				var fraction := float(pool.get("weight",0))*.01
				var percent := "%.2f%%" % fraction
				var group := _info_row("%s   %s" % [title,percent],"")
				var choice: VBoxContainer=group.get_child(0)
				var cell: Label=choice.get_child(0)
				cell.add_theme_color_override("font_color",Color.from_string(str(pool.get("color","#ffc079")),MILK))


func _start_cache_reveal(block: PanelContainer, row: HBoxContainer) -> void:
	if _reveal and _reveal.is_running():
		_reveal.kill()
	var skip := _new_button("SKIP REVEAL",func(): _skip_cache_reveal(block))
	row.add_child(skip)
	var rarity_color := Color.from_string(str(_last_pull.get("color","#ffc079")), AMBER)
	block.modulate = Color(rarity_color.r * 0.45 + 0.65, rarity_color.g * 0.45 + 0.65, rarity_color.b * 0.45 + 0.65, 0.35)
	_reveal = create_tween()
	_reveal.tween_property(block,"modulate",Color(1.0, 1.0, 1.0, 1.0),0.68).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reveal.tween_callback(func():
		if is_instance_valid(skip):
			skip.hide()
	)


func _skip_cache_reveal(block: PanelContainer) -> void:
	if _reveal and _reveal.is_running():
		_reveal.custom_step(1.0)
	if is_instance_valid(block):
		block.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _inventory_menu() -> void:
	var progress: Variant = _prop(game,"progress")
	var materials := int(_prop(progress,"materials",0))
	var bundles := floori(float(materials) / 3.0)
	var header := _info_row("Trail locker   /   %d materials" % materials,"Equip a trail to change the lightning following your runner. Exchange 3 materials for 1 SFC.",
		"EXCHANGE  +%d SFC" % maxi(bundles, 1),func(): _menu_action("redeem_materials"),bundles > 0)
	(header.get_child(1) as Button).disabled = materials < 3
	var items = _prop(progress,"inventory",{})
	var equipped := str(_prop(progress,"equipped_trail",""))
	if not items is Dictionary or items.is_empty():
		_info_row("No trails collected","Earn Speed Force charge and visit the Rift cache.")
		return
	for key in items:
		var name_: String = str(key)
		var owned := int(items[name_])
		if name_ == equipped:
			_info_row(name_,"Equipped  ·  %d owned" % owned)
		else:
			_info_row(name_,"%d owned" % owned,"EQUIP",func(): _equip(name_),false)


func _equip(name_: String) -> void:
	var progress: Variant = _prop(game,"progress")
	if progress is Object and progress.has_method("equip") and progress.equip(name_):
		_announce_menu("Equipped "+name_)
		_refresh_menu_after_command()


func _announce_menu(message: String) -> void:
	if game != null and game.has_method("announce"):
		game.announce(message)


func _settings_menu() -> void:
	_section("RENDERING")
	var level := int(_prop(game,"quality",_config.get("quality",1)))
	var detail: String = ["Low","Medium","High","Ultra"][clampi(level,0,3)]
	_info_row("Graphics preset",detail,"CHANGE",func(): _cycle_quality())
	_bool_setting("effects","Speed effects","Draw trails and other speed effects.",true)
	_bool_setting("reduced_motion","Reduced motion","Reduce camera motion and other movement effects.",false)
	_bool_setting("reduced_flash","Reduced flashing","Soften high-contrast light pulses.",false)
	_bool_setting("subtitles","Subtitles","Display dialogue text during play and cinematics.",true)
	_bool_setting("high_contrast","High contrast","Increase contrast on HUD panels and controls.",false)
	var fps := clampi(int(_config.get("fps_limit", _config.get("fps", Engine.max_fps))), 0, 120)
	var fps_text := "Display refresh rate" if fps == 0 else "%d frames per second" % fps
	_info_row("Frame rate limit",fps_text,"CHANGE",func(): _cycle_fps(fps))
	_menu_scale("camera_sensitivity","Camera sensitivity",.35,2.35,1.0)
	_menu_scale("text_scale","Text scale",.85,1.35,1.0)
	_menu_scale("shake","Camera shake",0.0,1.0,1.0)
	_section("AUDIO")
	_bool_setting("audio_muted","Mute all audio","Keep the levels below when audio is muted.",false)
	for key in AUDIO_SETTINGS:
		var option: Array = AUDIO_SETTINGS[key]
		_menu_scale(key,option[0],0.0,1.0,float(_config.get(option[1], option[2])))


func _cycle_quality() -> void:
	var level := int(_prop(game,"quality",_config.get("quality",1)))
	_save_setting("quality",posmod(level+1,4))
	_refresh_menu_after_command()


func _cycle_fps(fps: int) -> void:
	var levels := [30,45,60,90,120]
	var next: int = levels[posmod(levels.find(fps)+1,levels.size())]
	_save_setting("fps_limit",next)
	_refresh_menu_after_command()


func _bool_setting(key: String, title: String, description: String, default_value: bool) -> void:
	var setting := bool(_config.get(key,default_value))
	_info_row(title,description,"ON" if setting else "OFF",func(): _toggle_setting(key,not setting),setting)


func _toggle_setting(key: String, value: bool) -> void:
	_save_setting(key,value)
	_refresh_menu_after_command()


func _menu_scale(key: String, title: String, lower: float, upper: float, default_value: float) -> void:
	var row := _info_row(title,"")
	var counter := _label("",12,AMBER,true)
	counter.custom_minimum_size.x = 47
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(counter)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(147,42)
	slider.min_value = lower
	slider.max_value = upper
	slider.step = .01
	slider.set_value_no_signal(clampf(float(_config.get(key,default_value)),lower,upper))
	counter.text = "%d%%" % roundi(slider.value*100.0)
	slider.value_changed.connect(func(selected: float):
		counter.text = "%d%%" % roundi(selected*100.0)
		_config[key]=selected
	)
	slider.drag_ended.connect(func(changed: bool):
		if changed:
			_save_setting(key,slider.value)
	)
	slider.set_meta("setting",key)
	slider.focus_exited.connect(func(): _save_setting(key,slider.value))
	row.add_child(slider)
	menu_sliders.push_back(slider)


func _menu_slider_at(at: Vector2) -> HSlider:
	for slider in menu_sliders:
		if is_instance_valid(slider) and slider.is_visible_in_tree() and slider.get_global_rect().has_point(at) and scroll.get_global_rect().has_point(at):
			return slider
	return null


func _mapped_slider(slider: HSlider, at: Vector2) -> void:
	var r := slider.get_global_rect()
	var fraction := clampf((at.x-r.position.x)/r.size.x,0.0,1.0)
	slider.value = lerpf(slider.min_value,slider.max_value,fraction)


func _menu_button_at(at: Vector2) -> Button:
	for item in menu_buttons:
		if not is_instance_valid(item) or not item.is_visible_in_tree() or item.disabled:
			continue
		if content.is_ancestor_of(item) and not scroll.get_global_rect().has_point(at):
			continue
		if item.get_global_rect().has_point(at):
			return item
	return null


func _touch_menu() -> void:
	_info_row("Control placement","Drag each control within the screen and use the size controls to fit your grip. Changes are stored on this device.",
		"EDIT",_enter_editor,true)
	_info_row("Mirror layout (left-handed)","Swap the movement stick and action cluster across the left and right edges.","MIRROR",_mirror_layout)
	_info_row("Default layout","Restore all control positions and sizes.","RESET",_reset_layout)
	_bool_setting("sprint_toggle","Toggle sprint","Tap once to sprint and tap again to return to a jog.",false)
	_menu_scale("button_opacity","Touch button opacity",.35,1.0,1.0)


func _mirror_layout() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return
	var mirrored: Dictionary = {}
	for key in action_boxes:
		if key in [PAUSE, OPERATIONS]:
			continue
		var box: Rect2 = action_boxes[key]
		var center := box.get_center()
		var old: Dictionary = custom_layout.get(key, {})
		mirrored[key] = {
			"anchor": [clampf(1.0 - center.x / size.x, 0.04, 0.96), clampf(center.y / size.y, 0.08, 0.94)],
			"scale": float(old.get("scale", 1.0)),
		}
	custom_layout = _valid_layout(mirrored)
	_save_setting("hud_layout", custom_layout)
	_layout()
	_update_active_rects()
	_announce_menu("Mirrored touch layout")
	_refresh_menu_after_command()


func _help_menu() -> void:
	_section("TOUCHSCREEN")
	_info_row("Move, look and accelerate","Use the left joystick and drag the right half to look. Hold Sprint or Boost while moving and drag the speed limiter to refine your control.")
	_info_row("Fight and use powers","Jump or dodge while moving. Strike to attack, and counter when the marker appears. Open Powers to see cooldowns or tap Rewind directly.")
	_section("KEYBOARD AND MOUSE")
	_info_row("Movement","WASD to move, mouse drag to look, Shift to sprint, F to boost, Space to jump, X to dodge and C to slide.")
	_info_row("Combat and operations","J to strike, K for heavy attack, L to counter, Tab to lock on, E to interact, Q for Powers and 1–9 to cast. Press M for Operations and Esc to pause.")
	_section("CONTROLLER")
	_info_row("Movement and combat","Left stick to move, right stick to look, LB to sprint, RT to boost, A to jump, B to dodge, X to strike and Y for a heavy attack.")
	_info_row("Powers and operations","RB opens the wheel. Navigate with the D-pad and choose with A. Hold LT to counter, D-pad Up to interact and Start for Operations.")


func _enter_editor() -> void:
	menu_current = ""
	overlay.hide()
	_flush_editor_input()
	_issue("pause_hud")
	editor = true
	editor_selected = STICK
	_update_active_rects()
	queue_redraw()


func _flush_editor_input() -> void:
	_set_wheel(false)
	flush_inputs()


func _reset_layout() -> void:
	custom_layout.clear()
	_save_setting("hud_layout",custom_layout)
	_layout()
	_update_active_rects()


func _editor_rect(at: int) -> Rect2:
	var start := Vector2(size.x*.5 - 209, size.y*.11)
	return Rect2(start + Vector2(at*106,0),Vector2(99,44))


func _editor_option(at: Vector2) -> String:
	for i in range(4):
		if _editor_rect(i).has_point(at):
			return ["smaller","larger","reset","done"][i]
	return ""


func _editor_command(key: String) -> void:
	match key:
		"done":
			editor = false
			_save_setting("hud_layout",custom_layout)
			flush_inputs()
			_update_active_rects()
			_issue("resume")
		"reset":
			_reset_layout()
		"smaller", "larger":
			var box: Rect2 = action_boxes.get(editor_selected,Rect2())
			if box.has_area():
				var old: Dictionary = custom_layout.get(editor_selected,{})
				var change := -.1 if key == "smaller" else .1
				var updated := clampf(float(old.get("scale",1.0))+change,.70,1.65)
				_apply_editor_box(editor_selected,box.get_center(),updated)
				_save_setting("hud_layout",custom_layout)
	queue_redraw()


func _place_editor(key: String, at: Vector2) -> void:
	var old: Dictionary = custom_layout.get(key,{})
	_apply_editor_box(key,at,float(old.get("scale",1.0)))


func _apply_editor_box(key: String, at: Vector2, multiplier: float) -> void:
	var old: Dictionary = custom_layout.get(key,{})
	var existing: Rect2 = action_boxes[key]
	var extent := existing.size/maxf(float(old.get("scale",1.0)),.7)*multiplier
	var half := extent*.5
	var fitted := at.clamp(half+Vector2(14,14),size-half-Vector2(14,14))
	var candidate := Rect2(fitted-half,extent)
	if _crowded(key,candidate):
		_note("Leave space between controls.")
		return
	for i in range(4):
		if candidate.intersects(_editor_rect(i).grow(4.0)):
			_note("Keep the layout toolbar clear.")
			return
	custom_layout[key] = {"anchor":[fitted.x/size.x,fitted.y/size.y],"scale":multiplier}
	_layout()
	_update_active_rects()


func _draw_editor() -> void:
	for index in range(4):
		var rect := _editor_rect(index)
		_tile(rect,AMBER if index==3 else CYAN,Color("#1a2839f9"))
		_center_text(rect.get_center()+Vector2(0,6),["SIZE  −","SIZE  +","RESET","DONE"][index],13,MILK,true)
	_center_text(Vector2(size.x*.5,size.y*.11-12),"DRAG A CONTROL  /  "+editor_selected.to_upper(),15,AMBER,true)
	var rect: Rect2 = action_boxes.get(editor_selected,Rect2())
	draw_rect(rect.grow(4),AMBER,false,2.0)
	if _help_timer > 0.0:
		_center_text(Vector2(size.x*.5,size.y*.11+68),_tooltip,14,MILK,true)


func _ending_menu() -> void:
	_info_row("Infinite Moment completed","The timeline stabilizes. You can return to Calder Exchange and keep exploring.")
	_action_row("Back to the city","Continue from your completed save.","PATROL","patrol",true)
	_action_row("Calder Circuit","Challenge your time through the avenue checkpoints.","RACE","race")
	_action_row("Rift trial","Challenge the course inside the Speed Force.","ENTER","rift_trial")


class RadarMap extends Control:
	var hud
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO,size)
		draw_rect(rect,Color("#0d1927"))
		draw_rect(rect,Color("#7ea7bd5c"),false,1.0)
		var metric := minf(size.x / 480.0,size.y / 450.0)
		var center := size*.5
		# World-space overlay follows current district position and registered arena entrance.
		for i in range(-7,8):
			var offset := float(i)*24.0*metric
			draw_line(Vector2(0,center.y+offset), Vector2(size.x,center.y+offset), Color("#96b8d523"),1.0)
			draw_line(Vector2(center.x+offset,0), Vector2(center.x+offset,size.y), Color("#96b8d523"),1.0)
		var rift := str(hud._prop(hud.game,"realm","city"))=="rift"
		var vertical := [0.0,-110.0,106.0,-182.0,145.0] if not rift else [0.0]
		var horizontal := [-119.0,-177.0,-226.0,8.0,-330.0] if not rift else [1325.0,1360.0]
		for world_x in vertical:
			var pos_x: float = center.x+(world_x-hud._loc.x)*metric
			if pos_x > 0.0 and pos_x < size.x:
				draw_line(Vector2(pos_x,0),Vector2(pos_x,size.y),Color("#416078"),5.0)
		for world_z in horizontal:
			var pos_z: float = center.y+(world_z-hud._loc.z)*metric
			if pos_z > 0.0 and pos_z < size.y:
				draw_line(Vector2(0,pos_z),Vector2(size.x,pos_z),Color("#416078"),5.0)
		var target_coords := center+Vector2(hud._target.x-hud._loc.x,hud._target.z-hud._loc.z)*metric
		target_coords = target_coords.clamp(Vector2(18,18),size-Vector2(18,18))
		draw_line(center,target_coords,Color("#ffc079a6"),1.5,true)
		draw_circle(target_coords,6.0,Color("#ffc079"),true,-1,true)
		draw_circle(center,5.0,Color("#a2ecf3"),true,-1,true)
		draw_string(ThemeDB.fallback_font,Vector2(13,22),hud._district,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#f5eee5"))
