class_name Coin
extends Area2D
## One of the six collectible "KITTEN" coins. Hand-placed via
## `PersistentCoinSpawn`. Consumed on player overlap — fires the
## coin-collect VFX and updates `Level` state. Does not grant juice
## or heal; pure collectible with its own dedicated state.
##
## Joins the `"collectible_coins"` group so `EcholocationRenderer`
## can pack it into the tag-halo pass with a negative-w sentinel that
## tells the composite shader to use the gold coin-stipple override.


signal collected(coin: Coin)


const LETTERS: PackedStringArray = [
	"K", "I", "T", "T", "E", "N",
]
const GROUP := "collectible_coins"

## Per-letter spritesheet. Each sheet is a horizontal strip of six
## 15x15 frames animating a spinning coin. Both T slots share
## `_TCOIN_SHEET` — the letter is shared between the two T's in
## "KITTEN".
const _KCOIN_SHEET := preload("res://assets/images/scratch/kcoin.png")
const _ICOIN_SHEET := preload("res://assets/images/scratch/icoin.png")
const _TCOIN_SHEET := preload("res://assets/images/scratch/tcoin.png")
const _ECOIN_SHEET := preload("res://assets/images/scratch/ecoin.png")
const _NCOIN_SHEET := preload("res://assets/images/scratch/ncoin.png")
const _SHEETS: Array[Texture2D] = [
	_KCOIN_SHEET,
	_ICOIN_SHEET,
	_TCOIN_SHEET,
	_TCOIN_SHEET,
	_ECOIN_SHEET,
	_NCOIN_SHEET,
]

const _FRAME_COUNT := 6
const _FRAME_SIZE_PX := 15
const _ANIMATION_FPS := 12.0
const _ANIMATION_NAME := &"spin"

const _COLLISION_RADIUS := 15.0

## Rendered sprite scale. 15 px native is smaller than the 30 px
## collision circle, so scale up a bit to match bug-ish visual size.
const _SPRITE_SCALE := 1.6

## Echolocation halo radius in world px. Slightly larger than the
## bug's 6 px so the gold glint reads strongly.
const _TAG_RADIUS_PX := 10.0


## Index 0..5, maps to one letter of "KITTEN".
@export_range(0, 5) var coin_index: int = 0:
	set(value):
		coin_index = clampi(value, 0, LETTERS.size() - 1)
		_apply_sheet()

## Published for the echolocation renderer to pack into the tag-halo
## uniform; mirrors `WebTile.tag_radius_px`.
@export_range(2.0, 48.0) var tag_radius_px: float = _TAG_RADIUS_PX


var _consumed := false


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 8
	add_to_group(GROUP)
	var coll := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(coll) and coll.shape is CircleShape2D:
		if not coll.shape.resource_local_to_scene:
			coll.shape = coll.shape.duplicate()
		(coll.shape as CircleShape2D).radius = _COLLISION_RADIUS
	_apply_sheet()
	_spawn_persistent_sparkles()
	body_entered.connect(_on_body_entered)


func _spawn_persistent_sparkles() -> void:
	var sparkles := CoinSparkles.new()
	sparkles.mode = CoinSparkles.Mode.PERSISTENT
	sparkles.radius_px = _COLLISION_RADIUS
	add_child(sparkles)


## Builds a SpriteFrames resource keyed to this coin's letter sheet
## and plays the `spin` animation on the child AnimatedSprite2D.
## Called from both the setter (editor inspector tweaks) and _ready.
func _apply_sheet() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if not is_instance_valid(sprite):
		return
	if coin_index < 0 or coin_index >= _SHEETS.size():
		return
	var sheet: Texture2D = _SHEETS[coin_index]
	sprite.sprite_frames = _build_sprite_frames(sheet)
	sprite.animation = _ANIMATION_NAME
	sprite.scale = Vector2(_SPRITE_SCALE, _SPRITE_SCALE)
	# Start each coin on a random frame so adjacent coins don't
	# spin in visual lock-step.
	sprite.frame = randi() % _FRAME_COUNT
	sprite.play(_ANIMATION_NAME)


static func _build_sprite_frames(sheet: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation(_ANIMATION_NAME)
	frames.set_animation_speed(_ANIMATION_NAME, _ANIMATION_FPS)
	frames.set_animation_loop(_ANIMATION_NAME, true)
	for i in range(_FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(
				i * _FRAME_SIZE_PX,
				0,
				_FRAME_SIZE_PX,
				_FRAME_SIZE_PX)
		frames.add_frame(_ANIMATION_NAME, atlas)
	return frames


## Texture2D for the coin at `index`. Used by the HUD so its boxes
## can render a static first-frame preview matching the animated
## pickup.
static func sheet_for_index(index: int) -> Texture2D:
	if index < 0 or index >= _SHEETS.size():
		return null
	return _SHEETS[index]


## Rect2 of the first frame within a coin spritesheet — use this on
## an AtlasTexture to render the static HUD icon.
static func first_frame_region() -> Rect2:
	return Rect2(0, 0, _FRAME_SIZE_PX, _FRAME_SIZE_PX)


func letter() -> String:
	if coin_index < 0 or coin_index >= LETTERS.size():
		return "?"
	return LETTERS[coin_index]


func _on_body_entered(body: Node2D) -> void:
	if _consumed:
		return
	if body is Player:
		_consume()


func _consume() -> void:
	_consumed = true
	# Deferred because `_consume` runs inside `_on_body_entered`, and
	# Godot blocks direct `monitoring`/`monitorable` mutation during
	# an Area2D's in/out signal dispatch.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	collected.emit(self)
	G.audio.play_player_sound("coin")
	if is_instance_valid(G.level):
		G.level.mark_coin_collected(coin_index, global_position)
	queue_free()
