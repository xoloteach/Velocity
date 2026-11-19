extends Node3D

const AUDIO := {
	"step": preload("res://assets/audio/step.wav"), "land": preload("res://assets/audio/land.wav"),
	"jump": preload("res://assets/audio/jump.wav"), "impact": preload("res://assets/audio/hit.wav"),
	"damage": preload("res://assets/audio/damage.wav"), "boost": preload("res://assets/audio/boost.wav"),
	"lightning": preload("res://assets/audio/lightning.wav"), "slide": preload("res://assets/audio/slide.wav"),
	"rewind": preload("res://assets/audio/rewind.wav"), "phase": preload("res://assets/audio/phase.wav"),
	"shockwave": preload("res://assets/audio/shockwave.wav"), "portal": preload("res://assets/audio/portal.wav"),
	"goal": preload("res://assets/audio/goal.wav"), "cache": preload("res://assets/audio/goal.wav"),
	"counter": preload("res://assets/audio/counter.wav")
}
const SCORE = preload("res://assets/audio/score.wav")
const BOSS_SCORE = preload("res://assets/audio/boss_score.wav")
const ATMOSPHERE = preload("res://assets/audio/atmosphere.wav")
const RIFT_AMBIENCE = preload("res://assets/audio/rift_ambience.wav")
const WIND = preload("res://assets/audio/wind.wav")
const COLORS := {
	"boost": Color(1.0, .46, .08), "goal": Color(.42, .95, 1.0), "cache": Color(1.0, .68, .28),
	"damage": Color(1.0, .15, .10), "impact": Color(1.0, .30, .14), "rewind": Color(.42, .80, 1.0),
	"lightning": Color(1.0, .66, .18), "slide": Color(1.0, .54, .26), "phase": Color(.33, .93, 1.0),
	"shockwave": Color(1.0, .50, .20), "portal": Color(.85, .53, 1.0), "land": Color(.77, .69, .53),
	"counter": Color(1.0, .92, .48)
}
const DURATIONS := {"boost": .36, "goal": .72, "cache": .56, "rewind": .95, "portal": .70, "shockwave": .54, "counter": .46}
const COMBAT_CUES := {
	"hit": "impact", "counter": "counter", "block": "phase", "miss": "slide",
	"boss": "goal", "rush": "boost", "tornado": "shockwave"
}

var game
var sound_pool: Array[AudioStreamPlayer3D] = []
var ring_pool: Array[Dictionary] = []
var trail_points: Array[Vector3] = []
var trail := ImmediateMesh.new()
var trail_material := StandardMaterial3D.new()
var arc_mesh := ImmediateMesh.new()
var arc_material := StandardMaterial3D.new()
var sound_cursor := 0
var ring_cursor := 0
var stride_timer := 0.0
var wake_timer := 0.0
var fx_clock := 0.0
var score: AudioStreamPlayer
var boss_score: AudioStreamPlayer
var ambience: AudioStreamPlayer
var rift_ambience: AudioStreamPlayer
var wind: AudioStreamPlayer
var last_paused := false


func setup(owner) -> void:
	game = owner
	for channel: String in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(channel) < 0:
			AudioServer.add_bus()
			var bus := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, channel)
			AudioServer.set_bus_send(bus, "Master")
	for _slot in range(8):
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 46.0
		player.unit_size = 5.5
		add_child(player)
		sound_pool.append(player)
	if DisplayServer.get_name() != "headless":
		score = _loop(SCORE, "Music", -18.5)
		boss_score = _loop(BOSS_SCORE, "Music", -60.0)
		ambience = _loop(ATMOSPHERE, "SFX", -33.0)
		rift_ambience = _loop(RIFT_AMBIENCE, "SFX", -60.0)
		wind = _loop(WIND, "SFX", -69.0)
	for key in game.progress.settings:
		setting(str(key), game.progress.settings[key])

	var view := MeshInstance3D.new()
	view.mesh = trail
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	trail_material.vertex_color_use_as_albedo = true
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	view.material_override = trail_material
	add_child(view)

	var arc_view := MeshInstance3D.new()
	arc_view.mesh = arc_mesh
	arc_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	arc_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	arc_material.vertex_color_use_as_albedo = true
	arc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc_view.material_override = arc_material
	add_child(arc_view)

	var ring := TorusMesh.new()
	ring.inner_radius = .865
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 6
	for _slot in range(14):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.no_depth_test = false
		var node := MeshInstance3D.new()
		node.mesh = ring
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		add_child(node)
		ring_pool.append({"node": node, "mat": mat, "age": 1.0, "limit": 0.0, "radius": 1.0, "color": Color.WHITE})


func setting(key: String, value: Variant) -> void:
	var channels := {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "SFX", "voice_volume": "Voice"}
	if not channels.has(key):
		return
	var index := AudioServer.get_bus_index(channels[key])
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(.0001, float(value))))


func pulse(key: String, location: Vector3, strength: float = 1.0) -> void:
	key = COMBAT_CUES.get(key, key)
	if AUDIO.has(key):
		_sound(key, -5.0 if key != "step" else -15.0, strength, location)
	if not game.effects or not COLORS.has(key) or game.progress.settings.get("reduced_flash", false):
		return
	if game.quality == 0 and key in ["slide", "land"]:
		return
	var effect := ring_pool[ring_cursor]
	ring_cursor = (ring_cursor + 1) % ring_pool.size()
	effect["age"] = 0.0
	effect["limit"] = DURATIONS.get(key, .32)
	effect["radius"] = (11.0 if key == "shockwave" else 4.2 if key == "boost" else 3.2 if key == "counter" else 2.8) * clampf(strength, .5, 2.0)
	effect["color"] = COLORS[key]
	var node: MeshInstance3D = effect["node"]
	node.position = location + Vector3.UP * .095
	node.scale = Vector3(.15, .32, .15)
	node.visible = true


func notify(key: String, data: Dictionary) -> void:
	var cues := {"ability_cast": "phase", "lightning_hit": "lightning", "shockwave_hit": "shockwave",
		"projectile_redirected": "lightning", "portal_entered": "portal", "portal_returned": "portal"}
	if not cues.has(key):
		return
	var sound: String = cues[key]
	if key == "ability_cast":
		var move: String = str(data.get("id", ""))
		sound = {"slow": "rewind", "tornado": "shockwave", "mirage": "phase", "phase": "phase", "lightning": "lightning",
			"shockwave": "shockwave", "portal": "portal", "redirect": "phase"}.get(move, "phase")
	pulse(sound, data.get("position", game.runner.position), 1.0)


func _loop(clip: AudioStreamWAV, bus: String, db: float) -> AudioStreamPlayer:
	var track: AudioStreamWAV = clip.duplicate()
	track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	track.loop_end = roundi(track.get_length() * track.mix_rate)
	var channel := AudioStreamPlayer.new()
	channel.bus = bus
	channel.volume_db = db
	channel.stream = track
	add_child(channel)
	channel.play()
	return channel


func _sound(key: String, db: float, energy: float, location: Vector3) -> void:
	if score == null:
		return
	var player := sound_pool[sound_cursor]
	sound_cursor = (sound_cursor + 1) % sound_pool.size()
	player.position = location
	player.stream = AUDIO[key]
	player.volume_db = db
	player.pitch_scale = clampf(.90 + energy * .10, .80, 1.27)
	player.play()


func _exit_tree() -> void:
	for player in [score, boss_score, ambience, rift_ambience, wind] + sound_pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


func clear_trail() -> void:
	trail_points.clear()
	trail.clear_surfaces()
	arc_mesh.clear_surfaces()


func step(dt: float) -> void:
	if game.paused != last_paused:
		last_paused = game.paused
		for channel in [score, boss_score, ambience, rift_ambience, wind]:
			if is_instance_valid(channel):
				channel.stream_paused = last_paused
		if last_paused:
			for player in sound_pool:
				player.stop()
	if game.paused:
		return
	fx_clock += dt
	if score != null:
		var wind_speed := clampf(float(game.speed) / 85.0, 0.0, 1.0)
		wind.volume_db = lerpf(wind.volume_db, lerpf(-68.0, -20.0, pow(wind_speed, .42)), dt * 6.0)
		var in_rift: bool = str(game.realm) == "rift"
		ambience.volume_db = lerpf(ambience.volume_db, -58.0 if in_rift else -32.0, dt * 3.0)
		if is_instance_valid(rift_ambience):
			rift_ambience.volume_db = lerpf(rift_ambience.volume_db, -28.0 if in_rift else -62.0, dt * 3.0)
		var boss_fight: bool = not game.boss_status.is_empty() and bool(game.boss_status.get("boss", false))
		score.volume_db = lerpf(score.volume_db, -48.0 if boss_fight else (-15.0 if not game.boss_status.is_empty() else -19.0), dt * 2.5)
		if is_instance_valid(boss_score):
			boss_score.volume_db = lerpf(boss_score.volume_db, -14.5 if boss_fight else -62.0, dt * 2.5)
	for effect in ring_pool:
		var node: MeshInstance3D = effect["node"]
		if not node.visible:
			continue
		effect["age"] += dt
		var t := clampf(effect["age"] / effect["limit"], 0.0, 1.0)
		if t >= 1.0:
			node.visible = false
			continue
		var radius: float = lerpf(.18, effect["radius"], ease(t, .33))
		node.scale = Vector3(radius, maxf(.025, .32 * (1.0 - t)), radius)
		var color: Color = effect["color"]
		color.a = .68 * pow(1.0 - t, 1.75)
		effect["mat"].albedo_color = color
	_update_steps(dt)
	_update_surface_wakes(dt)
	_update_trails()


func _update_steps(dt: float) -> void:
	if not game.runner.is_on_floor() or game.speed < 2.0 or game.history.active:
		stride_timer = 0.0
		return
	stride_timer -= dt
	if stride_timer <= 0.0:
		stride_timer = lerpf(.48, .15, clampf(game.speed / 38.0, 0.0, 1.0))
		_sound("step", -24.0 + minf(game.speed, 35.0) * .18, .75, game.runner.position)


func _update_surface_wakes(dt: float) -> void:
	if not game.effects or game.quality == 0 or game.history.active:
		return
	if game.on_water and game.speed > 24.0:
		wake_timer -= dt
		if wake_timer <= 0.0:
			wake_timer = 0.14
			_spawn_ring_visual(game.runner.position, Color(0.55, 0.92, 1.0), 0.34, 1.9)
	elif game.wall_riding:
		wake_timer -= dt
		if wake_timer <= 0.0:
			wake_timer = 0.16
			_spawn_ring_visual(game.runner.position + Vector3.UP * 0.7, game.progress.trail_color(), 0.28, 1.5)
	else:
		wake_timer = 0.0


func _spawn_ring_visual(location: Vector3, tint: Color, life: float, radius: float) -> void:
	var effect := ring_pool[ring_cursor]
	ring_cursor = (ring_cursor + 1) % ring_pool.size()
	effect["age"] = 0.0
	effect["limit"] = life
	effect["radius"] = radius
	effect["color"] = tint
	var node: MeshInstance3D = effect["node"]
	node.position = location + Vector3.UP * .08
	node.scale = Vector3(.18, .25, .18)
	node.visible = true


func _update_trails() -> void:
	var visible_effects: bool = game.effects and not game.progress.settings.get("reduced_motion", false)
	var rewinding: bool = bool(game.history.active)
	var active: bool = visible_effects and (game.speed > 13.0 or rewinding)
	if active:
		var at: Vector3 = game.runner.position + Vector3.UP * .98
		if trail_points.is_empty() or trail_points.back().distance_to(at) > (.24 if rewinding else .32):
			trail_points.append(at)
	elif not trail_points.is_empty():
		trail_points.pop_front()
	var cap: int = [8, 14, 22, 30][game.quality]
	if trail_points.size() > cap:
		trail_points.pop_front()
	trail.clear_surfaces()
	arc_mesh.clear_surfaces()
	if trail_points.size() < 2:
		return
	var base_tint: Color = Color(0.45, 0.85, 1.0) if rewinding else game.progress.trail_color()
	var core_tint: Color = Color(0.88, 0.97, 1.0) if rewinding else base_tint.lightened(0.65)
	var view: Vector3 = game.camera.global_basis.x
	var up: Vector3 = game.camera.global_basis.y
	var intensity := 1.0 if rewinding else clampf(game.speed / 36.0, 0.35, 1.55)

	# Primary luminous ribbon core (sleek, vivid Speed Force wake)
	trail.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in range(trail_points.size()):
		var t := float(index) / float(trail_points.size() - 1)
		var center := trail_points[index]
		var width := (0.018 + 0.085 * t) * minf(intensity, 1.30)
		var color := Color(base_tint.lerp(core_tint, t * 0.42), 0.56 * t * t)
		trail.surface_set_color(color)
		trail.surface_add_vertex(center - view * width)
		trail.surface_set_color(color)
		trail.surface_add_vertex(center + view * width)
	trail.surface_end()

	# Multi-strand jagged Speed Force lightning filaments crackling around the runner
	var strands := 1 if game.quality == 0 else (2 if game.quality == 1 else 3)
	var jitter_step := floorf(fx_clock * 30.0)
	arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(strands):
		var phase_seed := float(s) * 2.17 + jitter_step * 1.43
		var strand_amp := (0.28 + 0.16 * float(s)) * minf(intensity, 1.35)
		var prev_pt := Vector3.ZERO
		for index in range(trail_points.size()):
			var t := float(index) / float(trail_points.size() - 1)
			var base_pt := trail_points[index]
			var angle := phase_seed + float(index) * 2.35
			var jitter := sin(angle * 2.6 + float(s) * 4.1) * strand_amp * (0.20 + 0.80 * t)
			var vertical := cos(angle * 1.9 + float(s) * 3.3) * (0.36 if s == 1 else 0.24) * (0.25 + 0.75 * t)
			var pt := base_pt + view * jitter + up * vertical
			if index > 0:
				var w := (0.014 + 0.026 * t) * (1.15 if s == 0 else 0.80)
				var col := Color(core_tint if s == 0 else base_tint, (0.95 if s == 0 else 0.82) * t)
				_add_quad(arc_mesh, prev_pt, pt, view * w, col)
			prev_pt = pt
	arc_mesh.surface_end()


func _add_quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, side: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a + side)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b + side)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b - side)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a + side)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b - side)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a - side)
