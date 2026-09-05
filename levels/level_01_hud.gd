extends CanvasLayer
## HUD + fall-safety + app-lifecycle for level_01 — same pattern as
## tech_demo_hud.gd (quit/reload/fall-respawn), plus an end-zone trigger.

const FALL_LIMIT_Y := 1200.0

@export var player_path: NodePath
@onready var label: Label = $DebugLabel

var player: RigidBody2D
var spawn_position: Vector2
var gamepad_reload_was_held := false
var level_complete := false


func _ready() -> void:
	player = get_node(player_path)
	spawn_position = player.global_position


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("quit_game"):
		get_tree().quit()
		return

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

	if level_complete:
		label.text = "Уровень пройден!\n\n[Ctrl+R / L1+R1] заново   [Esc / Start] выйти"
	else:
		label.text = "[Стик] идти   [Правый стик] вращать/клин\n[Space] прыжок   [ЛКМ / F] атака\n[LT / 1] Круг   [RT / 2] Квадрат   (отпущено = Треугольник)\n[Esc / Start] выйти   [Ctrl+R / L1+R1] заново"


## Connected to EndZone's body_entered in build_scenes.gd.
func _on_end_zone_entered(body: Node) -> void:
	if body.is_in_group("player"):
		level_complete = true
