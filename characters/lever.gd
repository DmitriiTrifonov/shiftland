extends Area2D
## Wedge-in-a-groove lever (GDD §6 "Треугольник-клин ... работает как рычаг").
## While the player overlaps this groove as Triangle with the wedge actually
## engaged (player.wedge_active — the corner is genuinely planted, not just
## aimed down), opens the linked Gate once. One-shot: doesn't re-lock if the
## player drifts out of the wedge without leaving the groove.

@export var gate_path: NodePath

var activated := false

@onready var gate: StaticBody2D = get_node(gate_path)


func _physics_process(_delta: float) -> void:
	if activated:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player") and body.current_form == body.Form.TRIANGLE and body.wedge_active:
			_activate()
			return


func _activate() -> void:
	activated = true
	gate.get_node("Collision").set_deferred("disabled", true)
	var tween := create_tween()
	tween.tween_property(gate, "modulate:a", 0.0, 0.3)
