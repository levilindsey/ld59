class_name EchoParticle
extends RefCounted
## One short-lived debris particle spawned when an echo pulse destroys
## a terrain cell. Pure in-memory (no scene node); position +
## velocity are integrated each frame by the `EcholocationRenderer`,
## which packs the particle into a shader uniform array for rendering.
##
## Visually: the shader draws particles as solid (no-dither) colored
## circles whose tint blends from the destroyed cell's atlas art
## inside the near-field to the flat palette color outside, so they
## carry the identity of what they came from regardless of distance.


## World-space position of the particle. Updated each frame by the
## renderer: `world_pos += velocity * delta`.
var world_pos: Vector2 = Vector2.ZERO

## World-space velocity. Gravity integrated by the renderer.
var velocity: Vector2 = Vector2.ZERO

## Frequency type of the cell this particle came from. Drives palette
## color outside the near-field and atlas slot sampling inside it.
var frequency: int = Frequency.Type.NONE

## Elapsed seconds since spawn. Renderer retires the particle when
## `age_sec >= lifetime_sec`.
var age_sec: float = 0.0

## Total visible lifetime in seconds.
var lifetime_sec: float = 0.6
