extends Node3D

const Model = preload("res://assets/velocity-runner.glb")
const CONTACT_SHADOW = preload("res://assets/contact_shadow.gdshader")
const SPAWN = Vector3(0, 0.08, 8)
const SUPPORT = {
	"world": preload("res://systems/world.gd"), "population": preload("res://systems/population.gd"),
	"combat": preload("res://systems/combat.gd"), "powers": preload("res://systems/powers.gd"),
	"progress": preload("res://systems/progress.gd"), "rewind": preload("res://systems/rewind.gd"),
	"campaign": preload("res://systems/campaign.gd"), "presentation": preload("res://systems/presentation.gd")
}
const Circuit = preload("res://systems/midnight.gd")
const Hud = preload("res://systems/hud.gd")
var runner: CharacterBody3D
var suit: Node3D
var runner_shadow: MeshInstance3D
var camera: Camera3D
var animations: AnimationPlayer
var body_collider: CollisionShape3D
var hero_heading := 0.0
var health := 100.0
var energy := 100.0
var speed := 0.0
var realm := "city"
var orbit := Vector2(0,.12)
var quality := 1
var effects := true
var paused := false
var sim_time := 0.0
var safe_position := SPAWN
var objective_text := ""
var mission_title := ""
var dialogue := ""
var status_text := ""
var boss_status: Dictionary = {}
var target_position := SPAWN
var world
var hud
var combat
var population
var powers
var progress
var history
var campaign
var presentation
var midnight: Node3D
var flags: Dictionary = {}
var control_axis := Vector2.ZERO
var boosting := false
var sprinting := false
var on_water := false
var wall_riding := false
var transit_active := false
var speed_tier: String:
	get:
		return progress.rank_title() if progress != null else "Human"
var animation_name := ""
var impact_charge := 0.0
var defeat_time := 0.0
var is_defeated := false
var ready_to_play := false

var _commands: Array[String] = []
var _jump_buffer := 0.0
var _coyote := 0.0
var _wall_time := 0.0
var _slide_time := 0.0
var _was_grounded := false
var _clip_timer := 0.0
var _clip_override := ""
var _camera_snap := true
var _camera_probe := SphereShape3D.new()
var _camera_query := PhysicsShapeQueryParameters3D.new()
var _shadow_query := PhysicsRayQueryParameters3D.new()
var _motion := 1.0
var _flash := true
var _sensitivity := 1.0
var _shake := 1.0
var _bank := 0.0
var _boost_pulse := 0.0
var _transit_blend := 0.0
var _transit_charge := 0.0
var _transit_brake := 0.0
var _prefetch_timer := 0.0
var _status_timer := 0.0
var _dialogue_timer := 0.0
var _cinema_timer := 0.0
var _cine_from := Vector3.ZERO
var _cine_to := Vector3.ZERO
var _mouse_looking := false
var _test_inputs := false
var _benchmark := false
var _benchmark_time := 0.0
var _benchmark_frames: Array[float] = []


func _ready() -> void:
	_build_input_map()
	_setup_runner()
	world = _module("world")
	population = _module("population")
	combat = _module("combat")
	powers = _module("powers")
	progress = _module("progress")
	history = _module("rewind")
	campaign = _module("campaign")
	presentation = _module("presentation")
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Hud.new()
	canvas.add_child(hud)
	progress.setup(self)
	for option in progress.settings.keys():
		configure_settings(str(option), progress.settings[option], false)
	world.setup(self)
	population.setup(self)
	population.set_reduced_flash(not _flash)
	combat.setup(self)
	powers.setup(self)
	history.setup(self)
	presentation.setup(self)
	hud.setup(self)
	midnight = Circuit.new()
	add_child(midnight)
	midnight.setup(self)
	campaign.setup(self)
	_benchmark = "--benchmark" in OS.get_cmdline_user_args()
	ready_to_play = true
	if not DisplayServer.get_name() == "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("VELOCITY_GAME_READY mission=%d renderer=compatibility" % campaign.mission_index)
	_notify_test_profile()
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('mode') === 'midnight'")):
		command("midnight")


func _module(filename: String):
	var part = SUPPORT[filename].new()
	if part is Node:
		part.name = filename.capitalize()
		add_child(part)
	return part


func _setup_runner() -> void:
	runner = CharacterBody3D.new()
	runner.name = "Runner"
	runner.position = SPAWN
	runner.collision_layer = 2
	runner.collision_mask = 1 | 4 | 8
	runner.floor_snap_length = .26
	runner.safe_margin = .012
	runner.floor_max_angle = deg_to_rad(53.0)
	add_child(runner)
	body_collider = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.79
	capsule.radius = .34
	body_collider.position.y = .9
	body_collider.shape = capsule
	runner.add_child(body_collider)
	suit = Model.instantiate()
	suit.name = "RunnerSuit"
	runner.add_child(suit)
	for mesh_node in suit.find_children("*", "MeshInstance3D", true, false):
		(mesh_node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	runner_shadow = MeshInstance3D.new()
	runner_shadow.name = "RunnerShadow"
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(1.18, 1.18)
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = CONTACT_SHADOW
	shadow_mat.set_shader_parameter("opacity", 0.58)
	runner_shadow.mesh = shadow_plane
	runner_shadow.material_override = shadow_mat
	runner_shadow.position = Vector3(0.0, 0.025, 0.0)
	runner_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	runner.add_child(runner_shadow)
	animations = suit.find_child("AnimationPlayer", true, false)
	for label in ["Idle","Walk","Jog","Sprint","Boost","Water","Wall","Air"]:
		if animations.has_animation(label):
			animations.get_animation(label).loop_mode = Animation.LOOP_LINEAR
	_play("Idle")
	camera = Camera3D.new()
	camera.name = "Chase"
	camera.near = .07
	camera.far = 340.0
	camera.fov = 65.0
	add_child(camera)
	camera.make_current()
	_camera_probe.radius = .28
	_camera_query.shape = _camera_probe
	_camera_query.collision_mask = 1 | 4
	_camera_query.exclude = [runner.get_rid()]
	_shadow_query.collision_mask = 1 | 4
	_shadow_query.exclude = [runner.get_rid()]


func _exit_tree() -> void:
	_commands.clear()
	boss_status.clear()
	flags.clear()
	if history != null:
		history.clear()
		history.game = null
	if progress != null:
		progress = null


func _build_input_map() -> void:
	var keys: Dictionary = {
		"left": [KEY_A,KEY_LEFT], "right": [KEY_D,KEY_RIGHT],
		"forward": [KEY_W,KEY_UP], "back": [KEY_S,KEY_DOWN],
		"sprint": [KEY_SHIFT], "boost": [KEY_F], "jump": [KEY_SPACE], "interact": [KEY_E],
		"light": [KEY_J], "heavy": [KEY_K], "counter": [KEY_L], "dodge": [KEY_X], "lock": [KEY_TAB], "slide": [KEY_C],
		"lightning": [KEY_1], "phase": [KEY_2], "rewind": [KEY_3], "tornado": [KEY_4], "mirage": [KEY_5],
		"slow": [KEY_6], "portal": [KEY_7], "shockwave": [KEY_8], "redirect": [KEY_9],
		"pause": [KEY_ESCAPE], "menu": [KEY_M], "wheel": [KEY_Q], "restart": [KEY_R], "next": [KEY_ENTER],
	}
	for action: String in keys:
		var mapped := "v_" + action
		if not InputMap.has_action(mapped):
			InputMap.add_action(mapped,.17)
		for code: int in keys[action]:
			var binding := InputEventKey.new()
			binding.physical_keycode = code as Key
			InputMap.action_add_event(mapped,binding)
	var buttons: Dictionary = {
		"jump": JOY_BUTTON_A, "dodge": JOY_BUTTON_B, "light": JOY_BUTTON_X, "heavy": JOY_BUTTON_Y,
		"sprint": JOY_BUTTON_LEFT_SHOULDER, "wheel": JOY_BUTTON_RIGHT_SHOULDER,
		"interact": JOY_BUTTON_DPAD_UP, "lock": JOY_BUTTON_DPAD_RIGHT,
		"rewind": JOY_BUTTON_DPAD_LEFT, "lightning": JOY_BUTTON_DPAD_DOWN,
		"pause": JOY_BUTTON_START, "menu": JOY_BUTTON_BACK, "slide": JOY_BUTTON_RIGHT_STICK
	}
	for action: String in buttons:
		var button := InputEventJoypadButton.new()
		button.button_index = buttons[action] as JoyButton
		InputMap.action_add_event("v_"+action,button)
	_joy_axis("left", JOY_AXIS_LEFT_X, -1.0)
	_joy_axis("right", JOY_AXIS_LEFT_X, 1.0)
	_joy_axis("back", JOY_AXIS_LEFT_Y, 1.0)
	_joy_axis("forward", JOY_AXIS_LEFT_Y, -1.0)
	_joy_axis("boost", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_joy_axis("counter", JOY_AXIS_TRIGGER_LEFT, 1.0)


func _joy_axis(action: String, index: JoyAxis, direction: float) -> void:
	var move := InputEventJoypadMotion.new()
	move.axis = index
	move.axis_value = direction
	InputMap.action_add_event("v_"+action,move)


func _unhandled_input(input: InputEvent) -> void:
	if not ready_to_play:
		return
	if input is InputEventMouseButton and input.button_index == MOUSE_BUTTON_RIGHT:
		_mouse_looking = input.pressed and not paused and not hud.wheel_open
	if hud.wheel_open:
		_mouse_looking = false
		return
	if input is InputEventMouseMotion and _mouse_looking and not paused:
		look_delta(input.relative)
	if input.is_echo():
		return
	for action in ["pause","menu","wheel","restart","next","jump","interact","light","heavy","counter","dodge","lock","slide","lightning","phase","tornado","rewind","mirage","slow","portal","shockwave","redirect"]:
		if input.is_action_pressed("v_"+action):
			command(action)
			get_viewport().set_input_as_handled()
			return


func look_delta(delta: Vector2) -> void:
	if paused or (is_instance_valid(hud) and hud.wheel_open) or _cinema_timer>0.0 or is_defeated:
		return
	orbit.x = wrapf(orbit.x-delta.x*.0058*_sensitivity,-PI,PI)
	orbit.y = clampf(orbit.y+delta.y*.0049*_sensitivity,-.40,.61)


func _notification(what: int) -> void:
	if ready_to_play and what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_mouse_looking = false
		_commands.clear()
		if hud.has_method("flush_inputs"):
			hud.flush_inputs()
		progress.save()
		paused = true
		hud.show_menu("mission")


func configure_settings(key: String, value: Variant, save := true) -> void:
	match key:
		"quality":
			quality = clampi(int(value),0,3)
			var vp := get_viewport()
			vp.scaling_3d_scale = [0.65, 0.85, 0.95, 1.0][quality]
			camera.far = [165.0, 240.0, 340.0, 440.0][quality] if is_instance_valid(camera) else 340.0
			if is_instance_valid(world) and world.get("game") != null:
				world.quality_changed(quality)
		"effects":
			effects = bool(value)
		"sensitivity", "camera_sensitivity":
			_sensitivity = clampf(float(value),.3,2.6)
		"motion", "reduced_motion":
			_motion = 0.0 if (key == "reduced_motion" and bool(value)) else 1.0 if key == "reduced_motion" else clampf(float(value),0.0,1.0)
			if world != null:
				world.set_motion_scale(_motion)
		"flash", "reduced_flash":
			_flash = not bool(value) if key == "reduced_flash" else bool(value)
			if population != null:
				population.set_reduced_flash(not _flash)
		"shake":
			_shake = clampf(float(value),0.0,1.0)
		"fps", "fps_limit":
			Engine.max_fps = clampi(int(value),30,120)
	if presentation != null and presentation.has_method("setting"):
		presentation.setting(key,value)
	if save and progress != null:
		progress.settings[key] = value
		progress.save()


func announce(message: String, duration: float = 2.6) -> void:
	status_text = message
	_status_timer = duration


func say(message: String, seconds: float = 4.8) -> void:
	dialogue = message
	_dialogue_timer = seconds


func cinema(from: Vector3, look_at_target: Vector3, duration: float = 1.9) -> void:
	_cine_from = from
	_cine_to = look_at_target
	_cinema_timer = duration


func event(key: String, payload: Dictionary = {}) -> void:
	if campaign != null:
		campaign.on_event(key,payload)
	if presentation != null and presentation.game != null:
		presentation.notify(key,payload)
	if key == "rewind_finished":
		_camera_snap = true
		combat.timeline_reversed()
		announce("Timeline restored")
		pulse("rewind",runner.position)
	if key == "enemy_down":
		pulse("impact",runner.position)
	if key == "melee_hit" or key == "counter":
		impact_charge = .11 if key == "melee_hit" else .19
	if key == "crime_completed":
		var payment := int(payload.get("payout",18))
		if progress.award("patrol:"+str(payload.get("id","unknown")),payment):
			announce("Street crime resolved   +%d SFC" % payment)


func command(action: String) -> void:
	if not ready_to_play:
		return
	if action.begins_with("replay_") and action.trim_prefix("replay_").is_valid_int():
		paused = false
		campaign.replay(int(action.trim_prefix("replay_")))
		return
	match action:
		"pause_hud":
			paused = true
			_commands.clear()
			_mouse_looking = false
		"pause","menu","missions","map":
			if paused and action == "pause":
				command("resume")
				return
			paused = true
			_commands.clear()
			hud.flush_inputs()
			hud.show_menu("map" if action=="map" else "mission")
		"resume":
			paused = false
			_mouse_looking = false
		"wheel":
			if hud.has_method("toggle_powers"):
				hud.toggle_powers()
		"restart":
			paused = false
			campaign.retry()
		"race","patrol","rift_trial","midnight":
			paused = false
			campaign.choose_activity(action)
		"next":
			if paused:
				paused = false
			campaign.resume_campaign()
		"skip":
			_cinema_timer = 0.0
			_dialogue_timer = 0.0
			dialogue = ""
		"upgrade_speed","upgrade_accel","upgrade_turn":
			var key := action.trim_prefix("upgrade_")
			if progress.upgrade(key):
				announce("Upgrade installed")
				event("upgrade",{"stat":key})
		"pull":
			var drawn: Dictionary = progress.pull()
			if not drawn.is_empty():
				pulse("cache",runner.position)
				announce(str(drawn.get("name","New reward")))
				hud.set_cache_result(drawn)
		"prestige":
			if progress.prestige():
				announce("Overdrive rank advanced")
		"redeem_materials":
			if progress.redeem_materials():
				pulse("cache",runner.position,0.7)
				announce("Materials exchanged for Speed Force Charge")
		_:
			if not paused and _commands.size()<16:
				_commands.append(action)


func _take_action(action: String) -> void:
	if midnight.running and action not in ["jump", "slide"]:
		if action == "rewind":
			announce("Rewind is off in timed runs.", 1.5)
		return
	if action == "rewind":
		var seconds := 4.0 if campaign.mission_index == 4 else 3.0
		if history.request(seconds):
			pulse("rewind",runner.position)
			announce("Rewinding",3.6)
		else:
			announce("Build more local history before rewinding.",1.6)
		return
	if is_defeated or _cinema_timer > 0.0:
		return
	if action == "jump":
		_jump_buffer = .13
		return
	if action == "slide" and speed > 8.5 and runner.is_on_floor():
		_slide_time = .46
		animate("Slide",.47)
		pulse("slide",runner.position)
		return
	if action == "interact":
		if campaign.interact() or population.interact():
			return
		if combat.command("interact"):
			return
		if not powers.command("interact"):
			announce("Nothing in reach.",1.0)
		return
	if not combat.command(action):
		powers.command(action)


func damage(amount: float) -> void:
	if is_defeated or history.active or powers.phased() or combat.invulnerable():
		return
	health = clampf(health-amount,0.0,100.0)
	impact_charge = .28
	pulse("damage", runner.position)
	animate("Hit",.29)
	if health <= 0.0:
		is_defeated = true
		defeat_time = 1.05
		animate("Fall",1.01)
		announce("Runner down   •   Rewind or retry",10.0)


func reset_runner(at: Vector3, destination := "city") -> void:
	is_defeated = false
	defeat_time = 0.0
	health = 100.0
	energy = 100.0
	orbit = Vector2(0,.12)
	hero_heading = 0.0
	_slide_time = 0.0
	_clip_timer = 0.0
	_cinema_timer = 0.0
	_jump_buffer = 0.0
	_coyote = 0.0
	_boost_pulse = 0.0
	boosting = false
	sprinting = false
	_commands.clear()
	powers.reset()
	teleport(at,destination)


func teleport(to: Vector3, destination: String = "city") -> void:
	if realm != destination:
		realm = destination
		world.set_realm(realm)
		powers.clear_realm()
	world.prepare_destination(to)
	runner.position = to + Vector3.UP*.06
	runner.velocity = Vector3.ZERO
	safe_position = runner.position
	history.clear()
	progress.reset_motion(runner.position,realm)
	_camera_snap = true
	_was_grounded = false
	speed = 0.0
	_clear_transit()
	if presentation != null:
		presentation.clear_trail()


func pulse(key: String, location: Vector3, strength: float = 1.0) -> void:
	if presentation != null and presentation.get("game") != null:
		presentation.pulse(key,location,strength)


func animate(label: String, hold: float = .35) -> void:
	if animations.has_animation(label):
		_clip_override = label
		_clip_timer = hold
		animation_name = ""
		_play(label)


func _play(label: String) -> void:
	if animation_name == label:
		return
	if not animations.has_animation(label):
		label = "Idle"
	if animation_name != label:
		animations.play(label,.11)
		animation_name = label


func snapshot() -> Dictionary:
	return {
		"realm": realm, "position":runner.position,"velocity":runner.velocity,"heading":hero_heading,
		"health":health,"energy":energy,"safe":safe_position,"orbit":orbit,
		"population":population.snapshot(),"combat":combat.snapshot(),"powers":powers.snapshot(),
		"campaign":campaign.snapshot(),"clock":sim_time,"animation":animation_name,
		"animation_time":animations.current_animation_position if animations.is_playing() else 0.0,
		"grounded":_was_grounded,"wall":_wall_time,"water":on_water,
		"transit":_transit_blend,"transit_charge":_transit_charge
	}


func restore(frame: Dictionary) -> void:
	if str(frame.get("realm","")) != realm:
		return
	runner.position = frame["position"]
	runner.velocity = frame["velocity"]
	hero_heading = frame["heading"]
	health = frame["health"]
	energy = frame["energy"]
	safe_position = frame["safe"]
	orbit = frame["orbit"]
	sim_time = frame["clock"]
	speed = Vector2(runner.velocity.x,runner.velocity.z).length()
	is_defeated = health <= 0.0
	_was_grounded = frame["grounded"]
	_wall_time = frame["wall"]
	on_water = frame["water"]
	_transit_blend = frame.get("transit",0.0)
	_transit_charge = frame.get("transit_charge",0.0)
	transit_active = _transit_blend > .26
	world.prepare_destination(runner.position)
	population.restore(frame["population"])
	combat.restore(frame["combat"])
	powers.restore(frame["powers"])
	powers.render_restored()
	campaign.restore(frame["campaign"])
	_play(str(frame["animation"]))
	if animations.is_playing():
		animations.seek(float(frame["animation_time"]),true)
	suit.rotation.y = hero_heading
	impact_charge = 0.0


func _physics_process(dt: float) -> void:
	if not ready_to_play:
		return
	if paused:
		return
	if midnight.hold(dt):
		_commands.clear()
		return
	while not _commands.is_empty():
		var action: String = _commands.pop_front()
		_take_action(action)
	if history.step(dt):
		boss_status = combat.status()
		return
	if is_defeated:
		defeat_time -= dt
		world.step(dt,runner.position)
		if defeat_time <= 0.0:
			defeat_time = 100000.0
			hud.show_menu("mission")
			paused = true
		return
	sim_time += dt
	_energy_update(dt)
	_update_timers(dt)
	_step_runner(dt)
	world.step(dt,runner.position)
	if midnight.running:
		midnight.step(dt, runner.position)
		progress.tick(dt)
		return
	population.step(dt*powers.slow_factor())
	combat.step(dt)
	powers.step(dt)
	campaign.step(dt)
	boss_status = combat.status()
	history.record(dt)
	progress.tick(dt)


func _energy_update(dt: float) -> void:
	energy = clampf(energy + dt*(8.5 if speed>10.0 else 5.5),0.0,100.0)


func _update_timers(dt: float) -> void:
	_status_timer = maxf(0.0,_status_timer-dt)
	_dialogue_timer = maxf(0.0,_dialogue_timer-dt)
	_cinema_timer = maxf(0.0,_cinema_timer-dt)
	_jump_buffer = maxf(0.0,_jump_buffer-dt)
	_slide_time = maxf(0.0,_slide_time-dt)
	_clip_timer = maxf(0.0,_clip_timer-dt)
	impact_charge = maxf(0.0,impact_charge-dt)
	_boost_pulse = maxf(0.0,_boost_pulse-dt*2.7)
	if _status_timer<=0.0:
		status_text = ""
	if _dialogue_timer<=0.0:
		dialogue = ""


func _step_runner(dt: float) -> void:
	var grounded := runner.is_on_floor()
	var pads := Input.get_connected_joypads()
	if not pads.is_empty() and _cinema_timer <= 0.0:
		var pad: int = pads[0]
		var turn := Vector2(Input.get_joy_axis(pad,JOY_AXIS_RIGHT_X),Input.get_joy_axis(pad,JOY_AXIS_RIGHT_Y))
		if turn.length()>.17:
			look_delta(turn*dt*462.0)
	var requested: Vector2 = Input.get_vector("v_left","v_right","v_back","v_forward")
	if not _test_inputs:
		control_axis = (requested + Vector2(hud.axis)).limit_length()
	var wheel_open: bool = hud.wheel_open
	if _cinema_timer > 0.0 or wheel_open:
		control_axis = Vector2.ZERO
	var was_boosting := boosting
	boosting = not wheel_open and (bool(hud.boost) or Input.is_action_pressed("v_boost")) and control_axis.length()>.13
	sprinting = not wheel_open and (bool(hud.sprint) or Input.is_action_pressed("v_sprint"))
	var limiter := clampf(float(hud.limiter),.1,1.0)
	var profile := velocity_profile(limiter)
	var top: float = profile.top
	var accel: float = profile.acceleration
	var turn_force: float = profile.turning
	var forward := Vector3(-sin(orbit.x),0.0,-cos(orbit.x))
	var side := Vector3(cos(orbit.x),0.0,-sin(orbit.x))
	var input_direction := forward*control_axis.y+side*control_axis.x
	var path := 0.0 if midnight.running else _update_transit(dt,input_direction,grounded,limiter,top)
	var base: float = top if boosting else minf(47.0,top*.43) if sprinting else 5.9
	base = (base+path)*profile.limiter
	if midnight.pad_time > 0.0 and midnight.running:
		base = maxf(base, 63.0 * profile.limiter)
	top += path
	var desired: Vector3 = input_direction*base*combat.movement_factor()
	var velocity_flat := Vector3(runner.velocity.x,0.0,runner.velocity.z)
	var traction := 1.0 if grounded else .63
	var acceleration := (accel*1.57 if boosting else accel) + minf(speed/2.4,turn_force)
	if _transit_blend>.01 and path<=.01:
		acceleration = maxf(acceleration,190.0)
	if control_axis.length()<.10:
		acceleration = 43.0 + turn_force*.42
	if _transit_brake>0.0:
		acceleration = maxf(acceleration,164.0)
	if midnight.running and grounded:
		var alignment := velocity_flat.normalized().dot(input_direction.normalized())
		if speed > 10.0 and alignment < .70:
			acceleration = maxf(acceleration, 300.0)
			var axis := input_direction.normalized()
			var along := axis * maxf(0.0, velocity_flat.dot(axis))
			velocity_flat = velocity_flat.lerp(along, 1.0 - exp(-dt * 42.0))
	if _slide_time>0.0:
		acceleration = 12.0
		desired *= .6
	var dodge: Vector3 = combat.dodge_velocity()
	if dodge.length_squared()>0.01:
		velocity_flat = dodge
	else:
		velocity_flat = velocity_flat.move_toward(desired,acceleration*traction*dt)
	runner.velocity.x = velocity_flat.x
	runner.velocity.z = velocity_flat.z
	runner.velocity.y = maxf(-32.0,runner.velocity.y-24.0*dt)
	_coyote = .118 if grounded else maxf(0.0,_coyote-dt)
	if _jump_buffer>0.0 and _coyote>0.0:
		runner.velocity.y = 8.75
		_coyote = 0.0
		_jump_buffer = 0.0
		animate("Launch",.18)
		pulse("jump",runner.position)
	var at := runner.position
	var wall_at := _wall_probe(velocity_flat)
	wall_riding = not wall_at.is_empty() and not grounded and _wall_time < 1.38
	if wall_riding:
		var normal: Vector3 = wall_at["normal"]
		var tangent := velocity_flat.slide(normal)
		runner.velocity = tangent
		runner.velocity.y = 4.9 if not boosting else 7.0
		_wall_time += dt
		if _jump_buffer>0.0:
			runner.velocity += normal*12.0+Vector3.UP*5.2
			_jump_buffer = 0.0
			_wall_time = 1.4
			wall_riding = false
			pulse("jump",runner.position)
	elif grounded:
		_wall_time = 0.0
	runner.move_and_slide()
	runner.position = world.bounds(runner.position)
	on_water = realm=="city" and world.water_at(runner.position) and runner.position.y < .28
	speed=Vector2(runner.velocity.x,runner.velocity.z).length()
	if on_water and speed<24.0:
		runner.position=safe_position
		runner.velocity=Vector3.ZERO
		speed=0.0
		on_water=false
		announce("Build speed to cross the water. A bridge is nearby.",1.6)
	if grounded and not on_water and not powers.phased():
		safe_position=runner.position
	var step_distance := Vector2(at.x-runner.position.x,at.z-runner.position.z).length()
	if not midnight.running and step_distance <= maxf(3.8,top*dt*1.75):
		progress.earn_distance(step_distance,speed,runner.position,step_distance>.03,realm,dt)
	if desired.length()>1.0:
		var dest := atan2(-velocity_flat.x,-velocity_flat.z)
		var difference := wrapf(dest-hero_heading,-PI,PI)
		_bank = lerpf(_bank,clampf(-difference*.24,-.22,.22),1.0-exp(-dt*8.5))
		hero_heading = lerp_angle(hero_heading,dest,1.0-exp(-dt*turn_force))
	else:
		_bank = lerpf(_bank,0.0,dt*5.0)
	if boosting and not was_boosting:
		_boost_pulse = 1.0
		animate("Launch",.24)
		pulse("boost",runner.position)
	if grounded and not _was_grounded and absf(runner.velocity.y)<1.0:
		animate("Land",.19)
		pulse("land",runner.position)
	if get_last_slide_count_safe() and speed>28.0 and at.distance_to(runner.position)<dt*speed*.42:
		impact_charge = .23
	_was_grounded = grounded
	if runner.position.y < -6.0:
		teleport(safe_position,realm)
		announce("Back on safe ground.")


func circuit_burst(dir: Vector3) -> void:
	var launch := maxf(speed, 59.0 * float(velocity_profile(hud.limiter).limiter))
	runner.velocity.x = dir.x * launch
	runner.velocity.z = dir.z * launch
	speed = launch
	_boost_pulse = 1.0
	pulse("boost", runner.position)


func get_last_slide_count_safe() -> bool:
	return runner.get_slide_collision_count() > 1


func velocity_profile(limiter: float) -> Dictionary:
	var upgrades: Dictionary = {} if is_instance_valid(midnight) and midnight.running else progress.movement()
	return {
		"top": clampf(52.0*float(upgrades.get("speed",1.0)),28.0,118.0),
		"acceleration": clampf(32.0*float(upgrades.get("accel",1.0)),8.0,105.0),
		"turning": clampf(9.0*float(upgrades.get("turn",1.0)),3.0,50.0),
		"limiter": .14+.86*pow(clampf(limiter,.10,1.0),1.58),
	}


func _clear_transit() -> void:
	_transit_charge = 0.0
	_transit_brake = 0.0
	_transit_blend = 0.0
	_prefetch_timer = 0.0
	transit_active = false


func _update_transit(dt: float, direction: Vector3, grounded: bool, limiter: float, top: float) -> float:
	_transit_brake = maxf(0.0,_transit_brake-dt)
	var level := int(progress.stats["speed"])+int(progress.prestige_level)*6
	var at := runner.position
	var forward := direction.normalized()
	var motion := Vector3(runner.velocity.x,0.0,runner.velocity.z).normalized()
	var ahead := at+forward*maxf(40.0,speed*.78)
	# Extreme travel stays on a loaded straight corridor with the normal swept capsule.
	var corridor := absf(at.x)<5.4 and absf(ahead.x)<7.1 and absf(forward.z)>.986
	var eligible: bool = realm=="city" and level>=17 and boosting and limiter>=.82 and grounded and \
		not powers.phased() and not on_water and direction.length()>.87 and speed>34.0 and \
		motion.dot(forward)>.983 and corridor and world.bounds(ahead).is_equal_approx(ahead)
	_prefetch_timer = maxf(0.0,_prefetch_timer-dt)
	if eligible:
		if _prefetch_timer <= 0.0:
			world.prefetch_approach(at+forward*48.0)
			_prefetch_timer = .35
		var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*.71,ahead+Vector3.UP*.71,1|4)
		ray.exclude = [runner.get_rid()]
		eligible = get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	_transit_charge = minf(.48,_transit_charge+dt) if eligible else 0.0
	var before := transit_active
	_transit_blend = move_toward(_transit_blend,1.0 if _transit_charge>=.48 else 0.0,dt*(3.4 if eligible else 8.5))
	transit_active = _transit_blend>.26
	if not eligible and before:
		_transit_brake = .92
	if transit_active and not before:
		_boost_pulse = 1.0
		pulse("boost",at,1.6)
	if not eligible:
		return 0.0
	var route_speed := minf(165.0,top+24.0+sqrt(float(level-17))*6.0)
	return maxf(0.0,route_speed-top)*_transit_blend


func _wall_probe(flat: Vector3) -> Dictionary:
	if (not sprinting and not boosting) or flat.length()<11.0 or runner.position.y<.24:
		return {}
	var facing := flat.normalized()
	var side := Vector3(-facing.z,0.0,facing.x)
	var origin := runner.position+Vector3.UP*.73
	for offset in [side*.84+facing*.28,-side*.84+facing*.28,facing*.68]:
		var query := PhysicsRayQueryParameters3D.create(origin,origin+offset,1)
		query.exclude = [runner.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit["normal"]
			if absf(normal.y)<.35 and absf(normal.dot(facing))<.73:
				return hit
	return {}


func _process(dt: float) -> void:
	if not ready_to_play:
		return
	if not paused:
		_update_visuals(minf(dt,.08))
	presentation.step(minf(dt,.08))
	hud.tick(dt)
	if _benchmark:
		_benchmark_frame(dt)


func _benchmark_frame(dt: float) -> void:
	_benchmark_time += dt
	_benchmark_frames.append(dt*1000.0)
	if _benchmark_time < 5.0:
		return
	_benchmark_frames.sort()
	var tail := floori(float(_benchmark_frames.size()-1)*.95)
	print("VELOCITY_PERF ",JSON.stringify({
		"quality":quality,"width":get_viewport().size.x,"height":get_viewport().size.y,
		"fps":float(_benchmark_frames.size())/_benchmark_time,"p95_ms":_benchmark_frames[tail],
		"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"world":world.stats(),"rewind_samples":history.count,"paused":paused
	}))
	_notify_test_profile()
	_benchmark_time = 0.0
	_benchmark_frames.clear()


func _notify_test_profile() -> void:
	if _benchmark:
		print("VELOCITY_PROFILE ",JSON.stringify({
			"mission":progress.mission_index,"stage":progress.mission_stage,
			"credits":progress.credits,"quality":quality,"limiter":hud.limiter,
			"persistent":progress.persistent
		}))


func _update_visuals(dt: float) -> void:
	suit.rotation.y = hero_heading
	suit.rotation.z = -.32 if wall_riding else _bank
	var target_pitch := -clampf(speed / 120.0, 0.0, 0.13) if runner.is_on_floor() and _slide_time <= 0.0 else 0.0
	suit.rotation.x = lerpf(suit.rotation.x, target_pitch, 1.0 - exp(-dt * 9.0))
	_update_runner_shadow()
	var current := "Idle"
	if _clip_timer>0.0:
		current = _clip_override
	elif combat.hero_pose != "":
		current = combat.hero_pose
	elif powers.hero_pose != "":
		current = powers.hero_pose
	elif wall_riding:
		current = "Wall"
	elif on_water:
		current = "Water"
	elif not runner.is_on_floor() and not history.active:
		current = "Air"
	elif speed>40.0:
		current = "Boost"
	elif speed>11.0:
		current = "Sprint"
	elif speed>4.1:
		current = "Jog"
	elif speed>.27:
		current = "Walk"
	if not history.active:
		_play(current)
		var cadence := 1.0
		if current in ["Walk","Jog","Sprint","Boost","Water","Wall"]:
			cadence=clampf(.82+speed*0.010,.92,1.71)
		animations.speed_scale=cadence*(.28 if combat.hit_stop>0.0 else 1.0)
	else:
		animations.speed_scale=0.0
	var forward := Vector3(-sin(orbit.x),0.0,-cos(orbit.x))
	var side := Vector3(cos(orbit.x),0.0,-sin(orbit.x))
	var center := runner.position + Vector3.UP*1.33
	var burst := _boost_pulse * _motion * (1.0 if effects else 0.0)
	var ratio := clampf(speed/76.0,0.0,1.0)
	var back := 4.32 + 1.18*ratio - burst*.38
	var desired := center-forward*back+side*(.66-ratio*.26)+Vector3.UP*(.85+sin(orbit.y)*back)
	if _cinema_timer>0.0:
		camera.position = camera.position.lerp(_cine_from,1.0-exp(-dt*7.0))
		camera.look_at(_cine_to)
	else:
		desired.y = maxf(runner.position.y + .62, desired.y)
		var spring_position := to_global(desired) if _camera_snap else camera.global_position.lerp(to_global(desired), 1.0 - exp(-dt * 14.0))
		# Sweep the actual damped candidate. Interpolating after collision resolution can
		# put the camera back behind a wall or inside a corner for several frames.
		camera.global_position = _constrain_camera(to_global(center), spring_position)
		var aim := center+forward*(5.6+ratio*2.7)+Vector3.UP*(orbit.y*2.45-.10)
		if not combat.locked_id.is_empty() and speed<15.0:
			var foe: Vector3 = combat.target_position()
			if foe.is_finite() and foe.distance_to(center)<19.0:
				aim = aim.lerp(foe+Vector3.UP*1.34,.38)
		camera.look_at(to_global(aim))
		if effects and _motion>0.0:
			camera.rotation.z -= _bank*.21*_motion
			camera.h_offset = sin(sim_time*42.0)*(_boost_pulse*.037+impact_charge*.065)*_shake*_motion
		else:
			camera.h_offset=0.0
	_camera_snap=false
	camera.fov = lerpf(camera.fov,64.0+_motion*(15.0*ratio+burst*6.0),1.0-exp(-dt*8.0))


func _constrain_camera(pivot: Vector3, candidate: Vector3) -> Vector3:
	var motion := candidate - pivot
	if motion.length_squared() < 0.000001:
		return pivot
	var space := get_world_3d().direct_space_state
	_camera_query.transform = Transform3D(Basis.IDENTITY, pivot)
	_camera_query.motion = motion
	var result := space.cast_motion(_camera_query)
	var fraction := result[0] if result.size() == 2 else 1.0
	# cast_motion ignores colliders already overlapping the probe. A center ray is
	# the fallback when the hero's shoulder pivot starts beside a tight wall.
	var ray := PhysicsRayQueryParameters3D.create(pivot, candidate, _camera_query.collision_mask, _camera_query.exclude)
	var overlap := space.intersect_ray(ray)
	if not overlap.is_empty():
		var contact: Vector3 = overlap["position"]
		fraction = minf(fraction, maxf(0.0, (pivot.distance_to(contact) - _camera_probe.radius) / motion.length()))
	return pivot + motion * fraction


func _update_runner_shadow() -> void:
	if not is_instance_valid(runner_shadow):
		return
	var feet := runner.global_position
	_shadow_query.from = feet + Vector3.UP * .18
	_shadow_query.to = feet - Vector3.UP * 4.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_shadow_query)
	# A runner over a void or canal shouldn't cast a fake disc at city ground level.
	runner_shadow.visible = not hit.is_empty()
	if hit.is_empty():
		return
	var surface: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var height := clampf(feet.y - surface.y, 0.0, 4.0)
	var spread := 1.0 + height * .16
	var right := Vector3.FORWARD.cross(normal).normalized()
	var back := right.cross(normal)
	runner_shadow.global_transform = Transform3D(Basis(right * spread, normal, back * spread), surface + normal * .018)
	(runner_shadow.material_override as ShaderMaterial).set_shader_parameter("opacity", .58 * (1.0 - height * .25))
