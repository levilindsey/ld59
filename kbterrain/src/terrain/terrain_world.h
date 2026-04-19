#ifndef KBTERRAIN_TERRAIN_TERRAIN_WORLD_H
#define KBTERRAIN_TERRAIN_TERRAIN_WORLD_H

#include "chunk_manager.h"
#include "flow_step.h"
#include "terrain_settings.h"
#include "worker_pool.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <memory>
#include <unordered_set>

namespace godot {

// TerrainWorld — Node2D facade for the marching-squares terrain.
// Owns the ChunkManager and WorkerPool. Exposes a damage/carve/query
// API to GDScript and manages per-chunk RIDs for rendering + collision.
class TerrainWorld : public Node2D {
	GDCLASS(TerrainWorld, Node2D)

public:
	TerrainWorld();
	~TerrainWorld();

	// --- Setup / authoring ----
	void set_settings(Ref<TerrainSettings> p_settings);
	Ref<TerrainSettings> get_settings() const { return _settings; }

	// Bulk-set all cell data for a chunk. `bytes` layout:
	//   first  (cells+1)^2 bytes = density.
	//   next   cells^2 bytes     = type per cell.
	//   next   cells^2 bytes     = health per cell.
	// Total: (cells+1)^2 + 2 * cells^2.
	// Called by the GDScript TerrainLevelLoader during level load.
	void set_cells(Vector2i coords, const PackedByteArray &bytes);

	// --- Gameplay API ----
	void damage(Vector2 world_pos, float radius_px, int damage,
			int frequency_mask);
	// Two-component distance-attenuated damage for an echo pulse:
	//
	// 1. "Surface" component — linear radial falloff from
	//    `surface_full_dmg` at `surface_full_radius_px` down to
	//    `surface_min_dmg` at `surface_max_radius_px`. Gated by the
	//    surface-only + player-facing logic inside
	//    `_apply_damage_to_cell`, so it erodes exposed cells.
	//
	// 2. "Proximity" component — short-range radial damage with a
	//    cubic ease-out from `proximity_full_dmg` at
	//    `proximity_full_radius_px` down to `proximity_min_dmg` at
	//    `proximity_max_radius_px`. UNCONDITIONAL — applies to every
	//    cell in range including interior cells, bypassing the
	//    surface check. Lets pulses dig into chunky terrain, but
	//    only close to the emitter and only a bit.
	//
	// Per-cell total = surface_component + proximity_component.
	void damage_with_falloff(
			Vector2 world_pos,
			float surface_max_radius_px,
			float surface_full_radius_px,
			int surface_full_dmg,
			int surface_min_dmg,
			float proximity_max_radius_px,
			float proximity_full_radius_px,
			int proximity_full_dmg,
			int proximity_min_dmg,
			int frequency_mask);
	void carve(Vector2 world_pos, float radius_px, float strength);
	void fill(Vector2 world_pos, float radius_px, float strength);
	// Restore a single cell's type + health at `world_pos`. No-op if
	// the cell is already occupied (caller owns the overlap policy).
	// Used by `TerrainChunkFragment` merge-back on landing.
	void paint_cell_at_world(Vector2 world_pos, int type, int health);

	// --- Queries ----
	float sample_density(Vector2 world_pos) const;
	bool is_solid(Vector2 world_pos) const;
	// True iff the cell containing `world_pos` has a non-NONE type.
	// Cell-granular; use this (not `is_solid`) when you need to ask
	// "is this particular cell filled?" — `is_solid` reads only the
	// top-left corner density, which can be 255 via an adjacent
	// anchor even if the cell itself is empty.
	bool is_cell_non_empty(Vector2 world_pos) const;
	// True iff the cell containing `world_pos` is of the given
	// `Frequency.Type`. Queries `type_per_cell` directly.
	bool is_cell_type_at(Vector2 world_pos, int type) const;
	// True iff the cell containing `world_pos` is a collide-able
	// solid — non-NONE and non-LIQUID. Use this (not
	// `is_cell_non_empty`) for falling-cell landing checks and
	// eviction clearance so falling solids pass through water.
	bool is_cell_collidable(Vector2 world_pos) const;
	// Cast a ray down from (x, -very_large) finding the topmost solid
	// sample crossing; returns y in world px. Returns NAN if no hit.
	float get_surface_height(float world_x, float search_max_y_px) const;

	Dictionary get_stats() const;

	// --- SDF texture queries ----
	// Build a single R8 Image containing every chunk's density samples,
	// stitched into one world-spanning grid. Width and height are
	// `get_world_cell_size() + Vector2i(1, 1)` (density has one extra
	// sample per chunk for the shared edge with neighbor chunks).
	// Returns a null Ref when no chunks exist — caller must skip bind.
	// Used by the echolocation shader for SDF-based surface detection
	// (replaces the tag SubViewport gradient hack).
	Ref<Image> build_density_image() const;
	// Build a single R8 Image containing every chunk's per-cell type
	// ids. Width and height are `get_world_cell_size()`. Returns null
	// when no chunks exist. Used by the echolocation shader for
	// per-pixel type classification (replaces palette-match).
	Ref<Image> build_type_image() const;
	// Build a single R8 Image of every chunk's per-cell health (byte
	// value 0..255). Same dimensions as the type image. Used by the
	// echolocation shader to overlay progressive damage-tier cracks
	// on partially-damaged cells.
	Ref<Image> build_health_image() const;
	// Upper-left world cell coordinate corresponding to pixel (0, 0) of
	// the density/type images. Equals `min_chunk_coord × cells`.
	Vector2i get_world_cell_origin() const;
	// Image dimensions in cells — width and height of the type image,
	// and one less than width/height of the density image (which has
	// the shared-edge +1 sample).
	Vector2i get_world_cell_size() const;

	// Sampled fluid velocity at a world position. Returns Vector2()
	// outside liquids. Used by the player to take damage from
	// fast-moving liquid.
	Vector2 sample_fluid_velocity(Vector2 world_pos) const;

	// Clear every chunk and free their RIDs. Used by the @tool
	// preview to wipe state before re-baking from a TileMap.
	void clear_all();

protected:
	static void _bind_methods();
	void _notification(int what);

private:
	Ref<TerrainSettings> _settings;
	std::unique_ptr<terrain::ChunkManager> _manager;
	std::unique_ptr<terrain::WorkerPool> _worker;
	std::unique_ptr<terrain::FlowStep> _flow_step;

	// Type → RGBA8 lookup table (size 256), rebuilt from the settings
	// palette and passed into remesh jobs so the worker can color
	// triangles without touching main-thread data.
	std::vector<uint32_t> _type_to_rgba_lut;

	// Chunks that need a remesh after the current call returns. We
	// bump generation immediately on edit; remesh is queued once per
	// chunk per edit batch.
	godot::HashSet<Vector2i> _dirty_chunks;

	// Configured per-process in set_settings.
	int _cells_cached = 32;
	float _cell_size_px_cached = 8.0f;
	int _iso_cached = 128;
	float _simplify_eps_cached = 0.75f;

	// True when running inside the editor (i.e. for the @tool
	// preview path). Set in _ensure_initialized.
	bool _editor_mode = false;

	// Frame counter used to throttle the flow cellular automaton
	// (which would otherwise run at render framerate and feel too
	// jittery). Stepped once per _on_process call.
	uint32_t _flow_tick_counter = 0;

	// How often to step the flow CA. 2 means every other frame
	// (~30Hz at 60fps).
	static constexpr uint32_t FLOW_STEP_INTERVAL = 2;

	// Max island size the CC pass will detach. Larger stays as part
	// of the main world. Prevents "half the level detaches" cascade.
	// Budget for CC flood-fill search. If a BFS explores more cells
	// than this without finding an anchor, the island is assumed
	// "too big to detach safely" (guards against detaching the
	// main world when a boundary cell is destroyed). Needs to be
	// large enough for big authored chunks to fully explore —
	// 50k cells = 800x800 px of contiguous terrain — without
	// giving up prematurely.
	static constexpr int MAX_DETACH_FLOOD = 50000;

	void _ensure_initialized();
	void _rebuild_type_lut();
	int _frequency_to_bit(int freq) const;
	void _queue_remesh(terrain::Chunk *chunk);
	void _queue_remesh_and_neighbors(terrain::Chunk *chunk);
	void _update_collision_sync(
			terrain::Chunk *chunk,
			const std::vector<uint8_t> &collision_density,
			int cells,
			float cell_size_px,
			Vector2 origin_px,
			uint8_t iso);
	void _integrate_results();
	void _integrate_one(const terrain::RemeshResult &result);
	// Apply damage to a single cell with surface-only + player-facing
	// gating:
	//   - Cells whose cardinal neighbors are ALL solid (interior
	//     cells) take NO damage — only surface cells erode.
	//   - Exposed cells compute a composite outward normal from their
	//     empty-neighbor sides; damage scales by
	//     `0.3 + 0.7 * max(0, dot(normal, to_emitter))`, so cells
	//     whose exposed face points toward the emitter take full
	//     damage while back-facing cells take 30%.
	//   - Empty-neighbor test treats TYPE_NONE and TYPE_LIQUID as
	//     "open" (water exposes the cell to a pulse).
	// Returns true if the cell was destroyed this call; `out_world_cx`
	// / `out_world_cy` are set if non-null. Pass nullptr when the
	// caller doesn't need the destroyed-cell coord.
	bool _apply_damage_to_cell(terrain::Chunk *chunk, int cx, int cy,
			int surface_damage, int proximity_damage,
			int frequency_mask,
			Vector2 emitter_world_pos, Vector2 cell_world_pos,
			std::unordered_set<int64_t> *destroyed_this_pulse = nullptr,
			int32_t *out_world_cx = nullptr,
			int32_t *out_world_cy = nullptr,
			bool *out_took_damage = nullptr);
	void _free_chunk_rids(terrain::Chunk *chunk);

	// Run CC on the world-cell coords of cells that were destroyed
	// in the most recent damage call; emit `fragment_detached` for
	// each detached island.
	void _detach_islands_from_seeds(
			const std::vector<int32_t> &seed_world_cells_flat);

	// Step the flow CA once and queue remeshes for any chunks
	// that changed.
	void _step_flow();

	// Process tick drains worker results and steps flow.
	void _on_process();

	// --- RIDs ----
	// When the TerrainWorld enters the tree, it creates a parent
	// canvas item + static body wrapping each chunk's per-chunk RIDs.
	RID _parent_canvas_item;
};

} // namespace godot

#endif // KBTERRAIN_TERRAIN_TERRAIN_WORLD_H
