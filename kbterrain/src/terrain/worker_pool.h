#ifndef KBTERRAIN_TERRAIN_WORKER_POOL_H
#define KBTERRAIN_TERRAIN_WORKER_POOL_H

#include "marching_squares.h"

#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <thread>
#include <vector>

namespace godot {
namespace terrain {

// Remesh job: the main thread submits a snapshot of a chunk's
// density + type buffers plus the chunk's identity and generation.
// The worker runs marching_squares + DP simplification against the
// snapshot and posts the result. The main thread checks generation
// before integrating.
struct RemeshJob {
	Vector2i coords;
	uint64_t submitted_generation;
	int cells;
	float cell_size_px;
	uint8_t iso;
	Vector2 origin_px;
	// Density buffer (cells+1)^2.
	std::vector<uint8_t> density_snapshot;
	// Collision density buffer (cells+1)^2. Same layout as
	// `density_snapshot` but with corners zeroed wherever every
	// adjacent cell is non-collidable (NONE or LIQUID), including
	// across chunk boundaries. Used to emit collision segments that
	// ignore water. Main thread is responsible for keeping it
	// consistent with neighbor chunks so seams match.
	std::vector<uint8_t> collision_density_snapshot;
	// Type buffer cells*cells.
	std::vector<uint8_t> type_snapshot;
	// Type → RGBA8 lookup (size 256). Copied so the worker doesn't
	// touch main-thread palette state.
	std::vector<uint32_t> type_to_color_rgba;
	// DP simplification epsilon (px). 0 = no simplification.
	float simplify_epsilon_px;
};

struct RemeshResult {
	Vector2i coords;
	uint64_t submitted_generation;
	MeshResult mesh;
	// Collision density snapshot forwarded from the job. Used to emit
	// one ConvexPolygonShape2D per fully-solid cell at integrate time.
	std::vector<uint8_t> collision_density;
	int cells = 0;
	float cell_size_px = 0.0f;
	Vector2 origin_px;
	uint8_t iso = 0;
};

// Run the meshing + simplification pipeline for one job and write
// the result to `out`. Used by both the worker thread and the
// editor-mode synchronous path in TerrainWorld.
void process_remesh_job(const RemeshJob &job, RemeshResult &out);

class WorkerPool {
public:
	WorkerPool();
	~WorkerPool();

	// Spawn the worker thread. Safe to call multiple times; subsequent
	// calls are no-ops while the worker is alive.
	void start();
	// Signal shutdown, join the worker, discard pending results.
	void stop();

	// Enqueue a job. The caller hands off ownership of the snapshots.
	void submit(RemeshJob job);

	// Drain available results into `out`, up to `max_count` (0 = no
	// cap). Returns the number drained.
	size_t drain_results(std::vector<RemeshResult> &out, size_t max_count);

	// Queue depth snapshots for HUD / debug.
	size_t pending_jobs();
	size_t pending_results();

private:
	void _worker_main();

	std::atomic<bool> _stop_flag;
	std::thread _worker;

	std::mutex _jobs_mutex;
	std::condition_variable _jobs_cv;
	std::deque<RemeshJob> _jobs;

	std::mutex _results_mutex;
	std::deque<RemeshResult> _results;
};

} // namespace terrain
} // namespace godot

#endif // KBTERRAIN_TERRAIN_WORKER_POOL_H
