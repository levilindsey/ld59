@tool
class_name CharacterAnimator
extends Node2D


@export var faces_right_by_default := true
@export var animated_sprite: AnimatedSprite2D = null

@export var frame := 0:
	set(value):
		frame = value
		animated_sprite.frame = frame

@export var animation := "":
	set(value):
		animation = value
		animated_sprite.animation = animation

@export var editor_only_flip_h := false:
	set(value):
		editor_only_flip_h = value
		animated_sprite.flip_h = value

var _is_facing_right := true

var initial_position := Vector2.INF

var player: Player


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# PlayerAnimator is also reused as a static sprite for non-Player
	# owners (e.g., the Destination "Mama" cat). Only bind `player`
	# when the parent actually is a Player; other owners just use the
	# animator for its AnimatedSprite2D + shader setup.
	if get_parent() is Player:
		player = get_parent() as Player

	initial_position = position


func face_left() -> void:
	_is_facing_right = false
	animated_sprite.flip_h = faces_right_by_default
	if animated_sprite.flip_h:
		position.x = -initial_position.x
	else:
		position.x = initial_position.x


func face_right() -> void:
	_is_facing_right = true
	animated_sprite.flip_h = not faces_right_by_default
	if animated_sprite.flip_h:
		position.x = -initial_position.x
	else:
		position.x = initial_position.x


func play(animation_name: String) -> void:
	animated_sprite.play(animation_name)


func stop() -> void:
	animated_sprite.stop()
