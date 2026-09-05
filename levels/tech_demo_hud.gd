extends CanvasLayer
## Minimal debug readout for the movement tech-demo — not final HUD/UI.
## Also owns a fall-safety net: this test level's ground is finite, so
## walking/rolling off either end (or any future tunneling) drops the player
## into empty space with nothing below. Respawn rather than fall forever.

const FALL_LIMIT_Y := 1200.0

@export var player_path: NodePath
@onready var label: Label = $DebugLabel

var player: RigidBody2D
var form_names := ["Circle", "Triangle", "Square"]
var spawn_position: Vector2
var gamepad_reload_was_held := false


func _ready() -> void:
	player = get_node(player_path)
	spawn_position = player.global_position


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("quit_game"):
		get_tree().quit()
		return

	# Gamepad reload combo (both bumpers together) is checked here, not via
	# InputMap, because InputMap ORs multiple events for one action instead
	# of requiring them held at the same time.
	var gamepad_reload_held := Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) and Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	var reload_pressed := Input.is_action_just_pressed("reload_game") or (gamepad_reload_held and not gamepad_reload_was_held)
	gamepad_reload_was_held = gamepad_reload_held
	if reload_pressed:
		get_tree().reload_current_scene()
		return

	if player == null:
		return

	if player.global_position.y > FALL_LIMIT_Y:
		player.global_position = spawn_position
		player.linear_velocity = Vector2.ZERO
		player.angular_velocity = 0.0

	label.text = "Form: %s\nSpeed: %.0f\nAngular: %.2f\nCharge: %.0f%%\n\n[Left/Right or stick] move   [Right stick / mouse] rotate\n[Space] jump   [Left click / F] attack\n[LT / 1] hold = Circle   [RT / 2] hold = Square   (released = Triangle)\n[Right stick / Q,E] hold to charge spin, release to launch\n[Esc / Start] quit   [Ctrl+R / L1+R1] reload" % [
		form_names[player.current_form],
		player.linear_velocity.length(),
		player.angular_velocity,
		player.spin_charge * 100.0,
	]
