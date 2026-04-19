#ifndef KBTERRAIN_TERRAIN_TERRAIN_WORLD_H
#define KBTERRAIN_TERRAIN_TERRAIN_WORLD_H

#include "chunk_manager.h"
#include "flow_step.h"
#include "terrain_settings.h"
#include "worker_pool.h"

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <memory>

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
	// Distance-attenuated variant: cells inside `full_radius_px` take
	// `full_dmg`; cells from `full_radius_px` out to `radius_px` linearly
	// interpolate down to `min_dmg`. Cells past `radius_px` take 0.
	// Used by the echo pulse so close cells are 1-shot-killed and far
	// cells take many hits.
	void damage_with_falloff(Vector2 world_pos, float radius_px,
			float full_radius_px, int full_dmg, int min_dmg,
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
	// Cast a ray down from (x, -very_large) finding the topmost solid
	// sample crossing; returns y in world px. Returns NAN if no hit.
	float get_surface_height(float world_x, float search_max_y_px) const;

	Dictionary get_stats() const;

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
	static constexpr int MAX_DETACH_FLOOD = 5000;

	void _ensure_initialized();
	void _rebuild_type_lut();
	int _frequency_to_bit(int freq) const;
	void _queue_remesh(terrain::Chunk *chunk);
	void _integrate_results();
	void _integrate_one(const terrain::RemeshResult &result);
	// Returns true if the cell was destroyed this call (type went to
	// NONE); in that case `out_world_cx`/`out_world_cy` are set if
	// non-null. Pass nullptr for both if the caller doesn't need the
	// destroyed-cell coord (e.g. falloff damage without CC).
	bool _apply_damage_to_cell(terrain::Chunk *chunk, int cx, int cy,
			int damage, int frequency_mask, Vector2 world_pos,
			int32_t *out_world_cx = nullptr,
			int32_t *out_world_cy = nullptr);
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
