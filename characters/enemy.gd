extends RigidBody2D
## Minimal arena enemy for the vertical slice (GDD §8) — deliberately simple:
## chase on sight, die after a couple of hits. AI depth is calibrated on
## playtests later, not designed upfront (GDD §8).

@export var hp := 2
@export var speed := 90.0
@export var chase_range := 260.0

var _flash_tween: Tween

@onready var visual: Polygon2D = $Visual


func _physics_process(_delta: float) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var to_player: float = player.global_position.x - global_position.x
	if absf(to_player) <= chase_range:
		linear_velocity.x = signf(to_player) * speed
	else:
		linear_velocity.x = move_toward(linear_velocity.x, 0.0, speed)


## Called by Player._apply_knockback via duck-typed has_method("take_hit") —
## every existing attack (spin/point/square) damages enemies for free without
## Player needing to know enemies exist.
func take_hit(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		_die()
		return
	if _flash_tween:
		_flash_tween.kill()
	visual.modulate = Color(1.0, 1.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(visual, "modulate", Color(0.85, 0.25, 0.25), 0.15)


func _die() -> void:
	set_physics_process(false)
	set_deferred("freeze", true)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.2)
	tween.tween_callback(queue_free)
