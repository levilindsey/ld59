@tool
class_name KbParallaxBackground
extends Node2D
## Three-layer tileable parallax background. Generates placeholder
## textures via `PlaceholderParallaxTextures` and assigns them to the
## Sprite2D children of each Parallax2D layer. Marked `@tool` so the
## editor preview shows the same procedural backdrop designers will
## see at runtime.


const _LAYER_SIZE := PlaceholderParallaxTextures.LAYER_SIZE


func _ready() -> void:
	_populate_layers()


func _populate_layers() -> void:
	var far_sprite := get_node_or_null(^"FarLayer/Sprite2D") as Sprite2D
	var mid_sprite := get_node_or_null(^"MidLayer/Sprite2D") as Sprite2D
	var near_sprite := get_node_or_null(^"NearLayer/Sprite2D") as Sprite2D

	if is_instance_valid(far_sprite):
		far_sprite.texture = PlaceholderParallaxTextures.make_far()
	if is_instance_valid(mid_sprite):
		mid_sprite.texture = PlaceholderParallaxTextures.make_mid()
	if is_instance_valid(near_sprite):
		near_sprite.texture = PlaceholderParallaxTextures.make_near()
