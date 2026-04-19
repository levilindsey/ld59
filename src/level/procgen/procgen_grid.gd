class_name ProcgenGrid
extends RefCounted
## Dense 2D grid of Frequency.Type values indexed by TileMapLayer
## tile coordinates. Origin is (0, 0); extent is width × height.
##
## This is the generator's mutable working buffer. When generation is
## finished, `TileMapWriter` walks the grid and issues
## `TileMapLayer.set_cell()` calls for every non-NONE entry.
##
## The grid also tracks a parallel "is_golden_path" bitset so
## validators can distinguish guaranteed-intact golden-path tiles
## from decorative fill that can be carved without breaking the
## level. Set pieces that MUST survive (e.g. the spawn ledge, the
## destination platform) mark their tiles golden.


var width: int = 0
var height: int = 0

# Flat row-major array of int (Frequency.Type).
var _cells: PackedInt32Array
# Same shape, bool. Stored as PackedByteArray for memory.
var _golden: PackedByteArray


func _init(w: int, h: int) -> void:
	width = w
	height = h
	_cells = PackedInt32Array()
	_cells.resize(w * h)
	_golden = PackedByteArray()
	_golden.resize(w * h)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_cell(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Frequency.Type.NONE
	return _cells[y * width + x]


func set_cell(x: int, y: int, type: int) -> void:
	if not in_bounds(x, y):
		return
	_cells[y * width + x] = type


func is_golden(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return _golden[y * width + x] != 0


func mark_golden(x: int, y: int, golden: bool = true) -> void:
	if not in_bounds(x, y):
		return
	_golden[y * width + x] = 1 if golden else 0


func fill_rect(rect: Rect2i, type: int) -> void:
	var x0 := maxi(0, rect.position.x)
	var y0 := maxi(0, rect.position.y)
	var x1 := mini(width, rect.position.x + rect.size.x)
	var y1 := mini(height, rect.position.y + rect.size.y)
	for y in range(y0, y1):
		for x in range(x0, x1):
			_cells[y * width + x] = type


func fill_rect_golden(rect: Rect2i, golden: bool = true) -> void:
	var x0 := maxi(0, rect.position.x)
	var y0 := maxi(0, rect.position.y)
	var x1 := mini(width, rect.position.x + rect.size.x)
	var y1 := mini(height, rect.position.y + rect.size.y)
	var v: int = 1 if golden else 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			_golden[y * width + x] = v


## True if the cell is a solid tile of any kind (destructible,
## indestructible, sand, liquid, web). False for NONE.
func is_solid(x: int, y: int) -> bool:
	var t := get_cell(x, y)
	return t != Frequency.Type.NONE


## True if the cell is "hard" — not passable even by a frequency-
## matched pulse. INDESTRUCTIBLE only. (LIQUID / SAND flow or fall;
## WEB_* slow but don't block.)
func is_hard(x: int, y: int) -> bool:
	return get_cell(x, y) == Frequency.Type.INDESTRUCTIBLE


## True if a standing player could be in this cell: cell is NONE (no
## solid) AND cell below is solid.
func is_standable(x: int, y: int) -> bool:
	if is_solid(x, y):
		return false
	if not in_bounds(x, y + 1):
		return false
	return is_solid(x, y + 1)


func count_non_empty() -> int:
	var c := 0
	for v in _cells:
		if v != Frequency.Type.NONE:
			c += 1
	return c


## Return every cell coord with a specific type. Used by validators.
func find_cells_of_type(type: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			if _cells[y * width + x] == type:
				out.append(Vector2i(x, y))
	return out
