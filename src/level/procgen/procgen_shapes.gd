class_name ProcgenShapes
extends RefCounted
## Grid-drawing primitives that break up the right-angle look: 1D
## fractal noise for surface heights, ellipse and circle fills, blob
## stamps (multi-lump), and a conservative cellular-automaton
## smoothing pass that rounds off jagged corners without destroying
## structure.


## Produce `count` integer heights, each in roughly
## `[base - amplitude, base + amplitude]`, using a two-octave sine
## sum. Deterministic under the given RNG. `wavelength` is the
## primary wavelength in column units; high values → smoother
## terrain, low values → choppier.
static func noise_heights_1d(
		count: int,
		base: int,
		amplitude: int,
		wavelength: float,
		rng: RandomNumberGenerator) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	var phase1 := rng.randf() * TAU
	var phase2 := rng.randf() * TAU
	var phase3 := rng.randf() * TAU
	var wl := maxf(1.0, wavelength)
	for x in range(count):
		var t := float(x) / wl
		var v1 := sin(t * TAU + phase1)
		var v2 := sin(t * 2.37 * TAU + phase2) * 0.5
		var v3 := sin(t * 5.13 * TAU + phase3) * 0.25
		var h := base + int(round(
				float(amplitude) * (v1 + v2 + v3) / 1.75))
		out[x] = h
	return out


## Fill the disc of radius `r` centered at `(cx, cy)` with `type`.
## `r` is in tile units; fractional values are OK.
static func fill_circle(
		grid: ProcgenGrid,
		cx: int,
		cy: int,
		r: float,
		type: int) -> void:
	var ri := int(ceil(r))
	var r_sq := r * r
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if float(dx * dx + dy * dy) > r_sq:
				continue
			grid.set_cell(cx + dx, cy + dy, type)


## Fill an axis-aligned ellipse.
static func fill_ellipse(
		grid: ProcgenGrid,
		cx: int,
		cy: int,
		rx: float,
		ry: float,
		type: int) -> void:
	var rxi := int(ceil(rx))
	var ryi := int(ceil(ry))
	for dy in range(-ryi, ryi + 1):
		for dx in range(-rxi, rxi + 1):
			var nx := float(dx) / maxf(0.5, rx)
			var ny := float(dy) / maxf(0.5, ry)
			if nx * nx + ny * ny > 1.0:
				continue
			grid.set_cell(cx + dx, cy + dy, type)


## Stamp an irregular blob at `(cx, cy)`. Places a main disc of
## radius `main_r` plus `lumps` smaller discs jittered around it.
## Good for enemy pockets, cavern mouths, anything that should
## read as "natural cavity" rather than "architected room."
static func stamp_blob(
		grid: ProcgenGrid,
		cx: int,
		cy: int,
		main_r: float,
		type: int,
		rng: RandomNumberGenerator,
		lumps: int = 4) -> void:
	fill_circle(grid, cx, cy, main_r, type)
	for i in range(lumps):
		var angle := rng.randf() * TAU
		var dist := main_r * rng.randf_range(0.5, 1.0)
		var lump_r := main_r * rng.randf_range(0.35, 0.7)
		var lx := cx + int(round(cos(angle) * dist))
		var ly := cy + int(round(sin(angle) * dist))
		fill_circle(grid, lx, ly, lump_r, type)


## Stamp a "ring" (hollow circle): `type_fill` across the disc,
## then `type_inside` re-stamped across the inner disc. Use for
## pool rims: pass `INDESTRUCTIBLE` then `LIQUID`, then pass again
## with SAND for the shell.
static func fill_ring(
		grid: ProcgenGrid,
		cx: int,
		cy: int,
		r_outer: float,
		r_inner: float,
		type: int) -> void:
	var ri := int(ceil(r_outer))
	var r_out_sq := r_outer * r_outer
	var r_in_sq := r_inner * r_inner
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var d_sq := float(dx * dx + dy * dy)
			if d_sq > r_out_sq:
				continue
			if d_sq < r_in_sq:
				continue
			grid.set_cell(cx + dx, cy + dy, type)


## One iteration of a conservative corner-smoothing CA.
## Rules:
##   * A solid cell (type in `affected_types`) surrounded by ≤ 1
##     solid 4-neighbor becomes NONE — erodes outward-pointing
##     spikes and single-cell bumps.
##   * An empty cell (NONE) surrounded by ≥ 6 solid 8-neighbors
##     becomes the majority neighbor type — fills hairline pits
##     and concave corners.
## Skips INDESTRUCTIBLE cells (border + anchors) and the level
## perimeter regardless of type. Returns the number of cells
## that changed.
static func smooth_once(
		grid: ProcgenGrid,
		affected_types: Array[int]) -> int:
	var changes := 0
	var writes: Array = []
	var affected_set: Dictionary = {}
	for t in affected_types:
		affected_set[t] = true
	for y in range(1, grid.height - 1):
		for x in range(1, grid.width - 1):
			var t := grid.get_cell(x, y)
			if t == Frequency.Type.INDESTRUCTIBLE:
				continue
			# Outward spike erosion (only on affected types).
			if affected_set.has(t) and t != Frequency.Type.NONE:
				var solid4 := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0),
						Vector2i(0, 1), Vector2i(0, -1)]:
					if grid.is_solid(x + d.x, y + d.y):
						solid4 += 1
				if solid4 <= 1:
					writes.append([x, y, Frequency.Type.NONE])
					continue
			# Pit close-up.
			if t == Frequency.Type.NONE:
				var solid8 := 0
				var type_votes: Dictionary = {}
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var nt := grid.get_cell(x + dx, y + dy)
						if nt == Frequency.Type.NONE:
							continue
						if nt == Frequency.Type.INDESTRUCTIBLE:
							# Don't paint indestructible into a hole.
							continue
						solid8 += 1
						type_votes[nt] = int(
								type_votes.get(nt, 0)) + 1
				if solid8 >= 6:
					var best_type := Frequency.Type.GREEN
					var best_vote := 0
					for k in type_votes.keys():
						var v: int = type_votes[k]
						if v > best_vote:
							best_vote = v
							best_type = k
					writes.append([x, y, best_type])
	for w in writes:
		grid.set_cell(w[0], w[1], w[2])
		changes += 1
	return changes
