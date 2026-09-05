extends Node2D
## Keeps the face sprite screen-locked while the body it sits on rotates
## (decision from GDD §12.1/§15 — the face never turns upside down).

@onready var sprite: Sprite2D = $FaceSprite

var _textures: Dictionary = {}
var _current_emotion := ""


func _ready() -> void:
	_textures = {
		"idle": load("res://assets/images/engine/faces/face_1.png"),
		"moving": load("res://assets/images/engine/faces/face_7.png"),
		"wild": load("res://assets/images/engine/faces/face_4.png"),
		"attack": load("res://assets/images/engine/faces/face_3.png"),
		"annoyed": load("res://assets/images/engine/faces/face_5.png"),
		"angry": load("res://assets/images/engine/faces/face_2.png"),
	}
	set_emotion("idle")


func _process(_delta: float) -> void:
	# Compensate any rotation inherited from the body (Circle spins physically;
	# Triangle's Corpus rotates independently) so the face always reads upright.
	global_rotation = 0.0


func set_emotion(emotion_name: String) -> void:
	if emotion_name == _current_emotion or not _textures.has(emotion_name):
		return
	sprite.texture = _textures[emotion_name]
	_current_emotion = emotion_name
