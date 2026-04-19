class_name EchoPing
extends RefCounted
## One scheduled bounce-back ping from an echo pulse. Created by
## `EcholocationRenderer._schedule_pings_for_pulse` when a ray cast
## along the pulse's arc intersects a solid cell; fired when the
## renderer's elapsed-time clock reaches `scheduled_time_sec`.
##
## Pings exist in two phases: before `scheduled_time_sec` they are
## "pending" (age_sec < 0, not packed into the shader uniform); after
## firing they are "active" and their age advances each frame until it
## exceeds `lifetime_sec`, at which point the pool slot is freed.


## World-space position of the surface hit.
var world_pos: Vector2 = Vector2.ZERO

## Start / end of the colinear surface segment that `world_pos` sits
## on. Computed at ping-creation time by walking along the surface
## tangent in both directions from the hit point. The shader draws a
## line that grows outward from `world_pos` to these endpoints as
## `age_sec` increases.
var segment_start: Vector2 = Vector2.ZERO
var segment_end: Vector2 = Vector2.ZERO

## Frequency type of the originating pulse (see Frequency.Type). The
## ping uses this both to look up a display color (via the shader
## palette) and to pitch-shift the audio ping.
var frequency: int = Frequency.Type.NONE

## Renderer `_elapsed_sec` at which this ping should fire. Computed as
## `emit_time + 2 × hit_dist / pulse.speed_px_per_sec`.
var scheduled_time_sec: float = 0.0

## Angle (radians) from pulse origin to hit point. For future audio
## stereo pan — currently unused but recorded at raycast time so the
## audio player doesn't need to recompute it.
var hit_angle_rad: float = 0.0

## Distance (world px) from pulse origin to hit point. Drives audio
## volume attenuation.
var hit_distance_px: float = 0.0

## Elapsed seconds since the ping fired. Negative (-1.0) while
## pending; set to 0.0 on fire; tracked up to `lifetime_sec` before
## the pool slot is freed.
var age_sec: float = -1.0


func is_pending() -> bool:
	return age_sec < 0.0


func has_fired() -> bool:
	return age_sec >= 0.0


func advance(delta_sec: float) -> void:
	if age_sec >= 0.0:
		age_sec += delta_sec
