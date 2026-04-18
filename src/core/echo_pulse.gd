class_name EchoPulse
extends RefCounted
## One echolocation pulse. Emitted by the player; owned by the
## EcholocationRenderer pulse pool. The pulse is a traveling wave of
## visibility that expands outward from `center` at `speed_px_per_sec`,
## with a bright leading edge and an exponentially fading trail behind.
##
## The renderer updates `age_sec` every frame. When `age_sec >
## lifetime_sec`, the pulse is retired and its pool slot freed.


## World-space origin of the pulse.
var center: Vector2 = Vector2.ZERO

## Frequency type (see Frequency.Type). Drives color tint in the
## composite shader and determines which tiles/enemies are
## damageable.
var frequency: int = Frequency.Type.NONE

## Wave-front speed, in world pixels per second.
var speed_px_per_sec: float = 600.0

## Total lifetime before the global envelope fully dissolves the
## pulse. The shader dissolves over the last 30% of lifetime.
var lifetime_sec: float = 1.2

## Elapsed time since emit. Renderer advances this each frame.
var age_sec: float = 0.0

## Upper bound on the wave-front radius. Used for gameplay damage
## queries (which fire once at emit time).
var max_radius_px: float = 600.0

## Damage dealt at emit time. Gameplay damage fires once; the visual
## continues animating after.
var damage: int = 10

## Directional cone in radians; 2π = full circle. Applied both to
## visual mask and damage query.
var arc_radians: float = TAU

## Direction the cone opens toward, in radians (0 = +x). Only
## meaningful when arc_radians < TAU.
var arc_direction_radians: float = 0.0


func is_active() -> bool:
	return age_sec <= lifetime_sec


func advance(delta_sec: float) -> void:
	age_sec += delta_sec
