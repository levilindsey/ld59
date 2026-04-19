@tool
class_name EditorPlaceholderSprite
extends Sprite2D
## Sprite2D that only renders in the editor. Use it to stand in for
## an entity that the runtime will spawn at this position (e.g., the
## Player on PlayerSpawnPoint), so level designers can see where the
## entity will appear without the placeholder lingering at runtime.


func _ready() -> void:
	if not Engine.is_editor_hint():
		hide()
