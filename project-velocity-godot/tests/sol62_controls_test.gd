extends SceneTree

const Level = preload("res://scenes/game.tscn")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var game = Level.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	var hud = game.hud
	hud.touch_mode = true
	hud._update_active_rects()
	var stick: Rect2 = hud.action_boxes["joystick"]
	var boost: Rect2 = hud.action_boxes["boost"]
	var powers: Rect2 = hud.action_boxes["powers"]
	var look := Vector2(root.get_visible_rect().size.x * 0.68, 320)
	hud._touch_down(1, stick.get_center() - Vector2(0, 28))
	hud._touch_down(2, boost.get_center())
	hud._touch_down(3, look)
	_check(hud.axis.length() > 0.1 and hud.boost and hud._has_owner("camera"), "Independent movement, boost and camera capture")
	hud._touch_down(4, powers.get_center())
	_check(hud.wheel_open and hud.axis.is_zero_approx() and not hud.boost and hud.owners.is_empty(), "Wheel opening releases existing holds and pointer owners")
	var orbit: Vector2 = game.orbit
	hud._touch_drag(3, look + Vector2(60, 0), Vector2(60, 0))
	_check(game.orbit.is_equal_approx(orbit), "Previously held camera finger cannot turn while selecting a power")
	hud._touch_down(5, stick.get_center() - Vector2(0, 28))
	_check(hud.axis.is_zero_approx(), "Touch input cannot reacquire the movement stick while wheel is open")
	Input.action_press("v_forward")
	Input.action_press("v_boost")
	game._step_runner(1.0 / 60.0)
	_check(game.control_axis.is_zero_approx() and not game.boosting, "Keyboard or gamepad movement cannot leak through the wheel")
	Input.action_release("v_forward")
	Input.action_release("v_boost")
	hud._set_wheel(false)
	hud._touch_down(6, stick.get_center() - Vector2(0, 28))
	_check(hud.axis.length() > 0.1, "A fresh touchscreen press restores movement after closing the wheel")
	# Off-axis post: center rays miss, but the camera's clearance sphere cannot.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.18, 2.5, 0.38)
	collider.shape = box
	wall.add_child(collider)
	var pivot := Vector3(2000, 10, 2000)
	wall.position = pivot + Vector3(.25, 0, 2.0)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	var desired := pivot + Vector3(0, 0, 5)
	var clearance: Vector3 = game._constrain_camera(pivot, desired)
	_check(clearance.z > pivot.z and clearance.z < pivot.z + 2.0, "Camera sweep stops before a post that a point ray misses")
	wall.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	var clear: Vector3 = game._constrain_camera(pivot, desired)
	_check(clear.is_equal_approx(desired), "Camera sweep allows full boom length when the corridor is clear")
	var platform := StaticBody3D.new()
	platform.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(8.0, 0.5, 8.0)
	floor_shape.shape = slab
	platform.add_child(floor_shape)
	platform.position = pivot
	game.add_child(platform)
	game.paused = true
	game.runner.global_position = pivot + Vector3.UP * 1.0
	await physics_frame
	await physics_frame
	game._update_runner_shadow()
	_check(game.runner_shadow.visible and absf(game.runner_shadow.global_position.y - (pivot.y + .268)) < .01, "Contact shadow attaches to the elevated physical floor")
	game.runner.global_position = pivot + Vector3.UP * 7.0
	game._update_runner_shadow()
	_check(not game.runner_shadow.visible, "Contact shadow hides above a void or out of its contact range")
	game.queue_free()
	await process_frame
	print("SOL62_CONTROLS ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
