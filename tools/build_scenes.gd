extends SceneTree
## One-off generator for player.tscn / tech_demo.tscn and the Input Map.
## Run once via: godot --headless --path . --script res://tools/build_scenes.gd
## Building nodes in code and letting Godot serialize them avoids hand-typing
## the fragile .tscn text format. Safe to re-run; it overwrites its outputs.
## Not wired into any build step — after this, edit the .tscn files normally
## in the editor; this script is just how they were bootstrapped.


func _init() -> void:
	_configure_input_map()
	_build_player_scene()
	_build_tech_demo_scene()
	ProjectSettings.set_setting("application/run/main_scene", "res://levels/tech_demo.tscn")
	ProjectSettings.save()
	print("build_scenes: done")
	quit()


# ---------------------------------------------------------------- input map

func _key_event(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	return e


func _joy_axis_event(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _joy_button_event(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _mouse_event(button: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _add_action(action_name: String, events: Array) -> void:
	ProjectSettings.set_setting("input/%s" % action_name, {
		"deadzone": 0.25,
		"events": events,
	})


func _configure_input_map() -> void:
	# Superseded by hold_circle/hold_square (trigger-based form switching).
	ProjectSettings.set_setting("input/shift_form", null)

	_add_action("move_left", [
		_key_event(KEY_LEFT), _key_event(KEY_A), _joy_axis_event(JOY_AXIS_LEFT_X, -1.0)
	])
	_add_action("move_right", [
		_key_event(KEY_RIGHT), _key_event(KEY_D), _joy_axis_event(JOY_AXIS_LEFT_X, 1.0)
	])
	_add_action("jump", [
		_key_event(KEY_SPACE), _joy_button_event(JOY_BUTTON_A)
	])
	_add_action("attack", [
		_key_event(KEY_F), _mouse_event(MOUSE_BUTTON_LEFT), _joy_button_event(JOY_BUTTON_X)
	])
	_add_action("hold_circle", [
		_key_event(KEY_1), _joy_axis_event(JOY_AXIS_TRIGGER_LEFT, 1.0)
	])
	_add_action("hold_square", [
		_key_event(KEY_2), _joy_axis_event(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	])
	_add_action("spin_ccw", [_key_event(KEY_Q)])
	_add_action("spin_cw", [_key_event(KEY_E)])
	_add_action("quit_game", [
		_key_event(KEY_ESCAPE), _joy_button_event(JOY_BUTTON_START)
	])
	# Ctrl+R on keyboard; gamepad combo (both shoulder bumpers together) is
	# checked directly in tech_demo_hud.gd since InputMap actions OR their
	# events together rather than requiring them held at once.
	var reload_key := InputEventKey.new()
	reload_key.physical_keycode = KEY_R
	reload_key.ctrl_pressed = true
	_add_action("reload_game", [reload_key])
	print("build_scenes: input map configured")


# --------------------------------------------------------------- node utils

func _own(owner_root: Node, node: Node, parent: Node) -> Node:
	parent.add_child(node)
	node.owner = owner_root
	return node


func _make_sprite(owner_root: Node, parent: Node, node_name: String, texture_path: String, scale_factor: float, tint: Color) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = load(texture_path)
	sprite.scale = Vector2(scale_factor, scale_factor)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tint.gdshader")
	mat.set_shader_parameter("tint_color", tint)
	sprite.material = mat
	_own(owner_root, sprite, parent)
	return sprite


func _make_legs(owner_root: Node, parent: Node, hip_offset: float, ray_length: float) -> Node2D:
	var legs := Node2D.new()
	legs.name = "Legs"
	legs.z_index = -1 # draw behind the body sprite, regardless of add order
	_own(owner_root, legs, parent)
	for side in ["L", "R"]:
		var sign_x := -1.0 if side == "L" else 1.0
		var ray := RayCast2D.new()
		ray.name = "Ray%s" % side
		ray.position = Vector2(hip_offset * sign_x, 0.0)
		ray.target_position = Vector2(0.0, ray_length)
		ray.enabled = true
		ray.collide_with_areas = false
		_own(owner_root, ray, legs)

		var line := Line2D.new()
		line.name = "Line%s" % side
		line.width = 5.0
		line.default_color = Color(0.1, 0.1, 0.1)
		_own(owner_root, line, legs)
	return legs


func _make_box(owner_root: Node, parent: Node, node_name: String, pos: Vector2, size: Vector2, rot_deg: float, color: Color) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = node_name
	body.position = pos
	body.rotation = deg_to_rad(rot_deg)
	_own(owner_root, body, parent)

	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	_own(owner_root, collision, body)

	var poly := Polygon2D.new()
	poly.name = "Visual"
	var half := size * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	poly.color = color
	_own(owner_root, poly, body)
	return body


# ----------------------------------------------------------------- player

## owner_root == null means "this Player IS the scene root being built"
## (standalone player.tscn); otherwise it's embedded under an outer scene.
func _build_player(owner_root: Node, parent: Node) -> RigidBody2D:
	var player := RigidBody2D.new()
	player.name = "Player"
	player.gravity_scale = 1.0
	player.lock_rotation = true
	player.contact_monitor = true
	player.max_contacts_reported = 8
	player.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE # defensive: Circle's roll speed and Square's lunge can move fast enough to tunnel through thin geometry in one physics step otherwise
	player.script = load("res://characters/player.gd")

	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = 1.0
	phys_mat.bounce = 0.0
	player.physics_material_override = phys_mat

	if parent == null:
		owner_root = player
	else:
		parent.add_child(player)
		player.owner = owner_root

	var ground_check := RayCast2D.new()
	ground_check.name = "GroundCheck"
	ground_check.target_position = Vector2(0.0, 40.0)
	ground_check.enabled = true
	ground_check.collide_with_areas = false
	_own(owner_root, ground_check, player)

	# --- Circle form ---
	var circle_form := Node2D.new()
	circle_form.name = "CircleForm"
	_own(owner_root, circle_form, player)
	_make_sprite(owner_root, circle_form, "CircleSprite", "res://assets/images/engine/circle.png", 0.25, Color(0.06, 0.62, 0.58))

	# Plain silhouette reads as static even while spinning fast — this dot
	# rides the rim and revolves with the body so rotation is actually visible.
	var spin_marker := _make_sprite(owner_root, circle_form, "SpinMarker", "res://assets/images/engine/circle.png", 0.06, Color(0.02, 0.18, 0.16))
	spin_marker.position = Vector2(0.0, -20.0)

	# CollisionShape2D only registers with an *immediate* CollisionObject2D
	# parent, so this must hang directly off `player`, not off CircleForm.
	var circle_collision := CollisionShape2D.new()
	circle_collision.name = "CircleCollision"
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = 28.0
	circle_collision.shape = circle_shape
	_own(owner_root, circle_collision, player)

	var spin_area := Area2D.new()
	spin_area.name = "SpinAttackArea"
	_own(owner_root, spin_area, circle_form)
	var spin_shape := CollisionShape2D.new()
	spin_shape.name = "SpinAttackShape"
	var spin_circle := CircleShape2D.new()
	spin_circle.radius = 40.0
	spin_shape.shape = spin_circle
	spin_shape.disabled = true
	_own(owner_root, spin_shape, spin_area)

	# --- Triangle form ---
	var triangle_form := Node2D.new()
	triangle_form.name = "TriangleForm"
	triangle_form.visible = false
	_own(owner_root, triangle_form, player)

	var triangle_collision := CollisionShape2D.new()
	triangle_collision.name = "TriangleCollision"
	var triangle_shape := RectangleShape2D.new()
	triangle_shape.size = Vector2(48.0, 56.0)
	triangle_collision.shape = triangle_shape
	triangle_collision.disabled = true
	_own(owner_root, triangle_collision, player)

	# Corpus's own origin sits at the sprite's incenter, not the image's bbox
	# center, so it rotates around a point that's actually inside the triangle.
	# Measured from triangle.png's alpha mask (256x256 canvas, apex up): the
	# incenter is ~48.3px below the bbox center, i.e. 12.08 units at this
	# sprite's 0.25 scale. Sprite/hitbox children are shifted the opposite way
	# by the same amount so nothing visually moves at rotation 0.
	const INCENTER_SHIFT_Y := 12.08
	var corpus := Node2D.new()
	corpus.name = "Corpus"
	corpus.position = Vector2(0.0, INCENTER_SHIFT_Y)
	_own(owner_root, corpus, triangle_form)
	var triangle_sprite := _make_sprite(owner_root, corpus, "TriangleSprite", "res://assets/images/engine/triangle.png", 0.25, Color(0.83, 0.33, 0.12))
	triangle_sprite.position = Vector2(0.0, -INCENTER_SHIFT_Y)

	var point_area := Area2D.new()
	point_area.name = "PointAttackArea"
	point_area.position = Vector2(0.0, -40.0 - INCENTER_SHIFT_Y)
	_own(owner_root, point_area, corpus)
	var point_shape := CollisionShape2D.new()
	point_shape.name = "PointAttackShape"
	var point_circle := CircleShape2D.new()
	point_circle.radius = 16.0
	point_shape.shape = point_circle
	point_shape.disabled = true
	_own(owner_root, point_shape, point_area)

	_make_legs(owner_root, triangle_form, 14.0, 40.0)

	# --- Square form ---
	var square_form := Node2D.new()
	square_form.name = "SquareForm"
	square_form.visible = false
	_own(owner_root, square_form, player)

	var square_collision := CollisionShape2D.new()
	square_collision.name = "SquareCollision"
	var square_shape := RectangleShape2D.new()
	square_shape.size = Vector2(56.0, 56.0)
	square_collision.shape = square_shape
	square_collision.disabled = true
	_own(owner_root, square_collision, player)

	_make_sprite(owner_root, square_form, "SquareSprite", "res://assets/images/engine/square.png", 0.25, Color(0.71, 0.53, 0.06))
	_make_legs(owner_root, square_form, 16.0, 40.0)

	var square_attack_area := Area2D.new()
	square_attack_area.name = "AttackArea"
	_own(owner_root, square_attack_area, square_form)
	var square_attack_shape := CollisionShape2D.new()
	square_attack_shape.name = "AttackShape"
	var square_attack_circle := CircleShape2D.new()
	square_attack_circle.radius = 24.0
	square_attack_shape.shape = square_attack_circle
	square_attack_shape.disabled = true
	_own(owner_root, square_attack_shape, square_attack_area)

	# --- Face (screen-locked, sibling of the rotating Corpus) ---
	var face := Node2D.new()
	face.name = "Face"
	face.script = load("res://characters/face_controller.gd")
	_own(owner_root, face, player)
	var face_sprite := Sprite2D.new()
	face_sprite.name = "FaceSprite"
	face_sprite.texture = load("res://assets/images/engine/faces/face_1.png")
	face_sprite.scale = Vector2(0.16, 0.16)
	_own(owner_root, face_sprite, face)

	# --- Camera ---
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.zoom = Vector2(1.3, 1.3)
	_own(owner_root, camera, player)

	# --- Signals (CONNECT_PERSIST so PackedScene.pack() actually saves them) ---
	spin_area.body_entered.connect(Callable(player, "_on_spin_hit"), CONNECT_PERSIST)
	point_area.body_entered.connect(Callable(player, "_on_point_hit"), CONNECT_PERSIST)
	square_attack_area.body_entered.connect(Callable(player, "_on_square_hit"), CONNECT_PERSIST)

	return player


func _build_player_scene() -> void:
	var player := _build_player(null, null)
	var packed := PackedScene.new()
	var pack_err := packed.pack(player)
	var save_err := ResourceSaver.save(packed, "res://characters/player.tscn")
	print("build_scenes: player.tscn pack=%s save=%s" % [pack_err, save_err])


# -------------------------------------------------------------- tech demo

func _build_tech_demo_scene() -> void:
	var root := Node2D.new()
	root.name = "TechDemo"

	_make_box(root, root, "Ground", Vector2(400.0, 400.0), Vector2(2000.0, 40.0), 0.0, Color(0.25, 0.26, 0.3))
	_make_box(root, root, "Step", Vector2(950.0, 330.0), Vector2(160.0, 40.0), 0.0, Color(0.3, 0.32, 0.36))
	_make_box(root, root, "Slope", Vector2(-280.0, 340.0), Vector2(260.0, 30.0), -22.0, Color(0.3, 0.32, 0.36))
	# Ground is finite (x in [-600, 1400]) — without these, walking/rolling off
	# either end drops the player into empty space with nothing below.
	_make_box(root, root, "WallLeft", Vector2(-590.0, 100.0), Vector2(20.0, 700.0), 0.0, Color(0.2, 0.21, 0.24))
	_make_box(root, root, "WallRight", Vector2(1390.0, 100.0), Vector2(20.0, 700.0), 0.0, Color(0.2, 0.21, 0.24))

	var crate_positions := [Vector2(150.0, 340.0), Vector2(250.0, 340.0), Vector2(600.0, 340.0), Vector2(700.0, 340.0)]
	var crate_index := 0
	for pos in crate_positions:
		crate_index += 1
		var crate := RigidBody2D.new()
		crate.name = "Crate%d" % crate_index
		crate.position = pos
		crate.mass = 0.5
		_own(root, crate, root)

		var crate_collision := CollisionShape2D.new()
		crate_collision.name = "Collision"
		var crate_shape := RectangleShape2D.new()
		crate_shape.size = Vector2(28.0, 28.0)
		crate_collision.shape = crate_shape
		_own(root, crate_collision, crate)

		var crate_visual := Polygon2D.new()
		crate_visual.name = "Visual"
		crate_visual.polygon = PackedVector2Array([
			Vector2(-14.0, -14.0), Vector2(14.0, -14.0), Vector2(14.0, 14.0), Vector2(-14.0, 14.0),
		])
		crate_visual.color = Color(0.85, 0.55, 0.2)
		_own(root, crate_visual, crate)

	var player := _build_player(root, root)
	player.position = Vector2(0.0, 250.0)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.script = load("res://levels/tech_demo_hud.gd")
	_own(root, hud, root)
	hud.set("player_path", NodePath("../Player"))

	var label := Label.new()
	label.name = "DebugLabel"
	label.position = Vector2(16.0, 16.0)
	label.add_theme_font_size_override("font_size", 20)
	_own(root, label, hud)

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	var save_err := ResourceSaver.save(packed, "res://levels/tech_demo.tscn")
	print("build_scenes: tech_demo.tscn pack=%s save=%s" % [pack_err, save_err])
