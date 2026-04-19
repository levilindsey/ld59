@tool
class_name KbParallaxBackground
extends Node2D
## Three-layer tileable parallax background. Assigns `@export` layer
## textures to the Sprite2D children of each Parallax2D layer. Marked
## `@tool` so the editor preview shows the same backdrop designers
## will see at runtime.
##
## Regenerate the default PNGs with `scripts/dump_placeholder_textures.ps1`
## (or the `.gd` runner) if you want to reset the art from the
## procedural generator in `PlaceholderParallaxTextures`.


@export var far_texture: Texture2D
@export var mid_texture: Texture2D
@export var near_texture: Texture2D


func _ready() -> void:
	_populate_layers()


func _populate_layers() -> void:
	var far_sprite := get_node_or_null(^"FarLayer/Sprite2D") as Sprite2D
	var mid_sprite := get_node_or_null(^"MidLayer/Sprite2D") as Sprite2D
	var near_sprite := get_node_or_null(^"NearLayer/Sprite2D") as Sprite2D

	if is_instance_valid(far_sprite):
		far_sprite.texture = far_texture
	if is_instance_valid(mid_sprite):
		mid_sprite.texture = mid_texture
	if is_instance_valid(near_sprite):
		near_sprite.texture = near_texture
