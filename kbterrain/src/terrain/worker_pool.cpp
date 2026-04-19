#include "worker_pool.h"

#include "douglas_peucker.h"
#include "terrain_settings.h"

namespace godot {
namespace terrain {

void process_remesh_job(const RemeshJob &job, RemeshResult &out) {
	out.coords = job.coords;
	out.submitted_generation = job.submitted_generation;
	out.mesh.clear();
	out.collision_segments.clear();

	// Render pass: emit triangles + boundary from the real density
	// field. Boundary segments from this pass are ignored because
	// they include the water-air interface.
	mesh_chunk(
			job.density_snapshot.data(),
			job.cells,
			job.cell_size_px,
			job.origin_px,
			job.iso,
			/* per_cell_color */ 0xFFFFFFFF,
			job.type_snapshot.empty()
					? nullptr : job.type_snapshot.data(),
			job.type_to_color_rgba.empty()
					? nullptr : job.type_to_color_rgba.data(),
			out.mesh);

	// Collision pass: main thread pre-built `collision_density_snapshot`
	// with cross-chunk boundary visibility so seams match. Run MS on
	// it to get the collision boundary (water surfaces + pure-water
	// regions become invisible to physics).
	if (!job.collision_density_snapshot.empty()) {
		MeshResult collision_mesh;
		mesh_chunk(
				job.collision_density_snapshot.data(),
				job.cells,
				job.cell_size_px,
				job.origin_px,
				job.iso,
				0xFFFFFFFF,
				nullptr,
				nullptr,
				collision_mesh);
		out.mesh.boundary_segments =
				std::move(collision_mesh.boundary_segments);
	}

	// Use the raw boundary segments for collision. Douglas-Peucker
	// simplification was causing intermittent floor holes at chunk
	// boundaries: each chunk simplified its side of the seam
	// independently, and the two endpoints could shift by a small
	// amount, leaving a gap the player could squeeze through. A few
	// hundred extra short segments per chunk is cheap in Godot's
	// concave shape.
	out.collision_segments = out.mesh.boundary_segments;
}


WorkerPool::WorkerPool() : _stop_flag(false) {}

WorkerPool::~WorkerPool() {
	stop();
}

void WorkerPool::start() {
	if (_worker.joinable()) {
		return;
	}
	_stop_flag.store(false);
	_worker = std::thread(&WorkerPool::_worker_main, this);
}

void WorkerPool::stop() {
	if (!_worker.joinable()) {
		return;
	}
	_stop_flag.store(true);
	_jobs_cv.notify_all();
	_worker.join();
	{
		std::lock_guard<std::mutex> lock(_jobs_mutex);
		_jobs.clear();
	}
	{
		std::lock_guard<std::mutex> lock(_results_mutex);
		_results.clear();
	}
}

void WorkerPool::submit(RemeshJob job) {
	{
		std::lock_guard<std::mutex> lock(_jobs_mutex);
		_jobs.push_back(std::move(job));
	}
	_jobs_cv.notify_one();
}

size_t WorkerPool::drain_results(
		std::vector<RemeshResult> &out, size_t max_count) {
	std::lock_guard<std::mutex> lock(_results_mutex);
	size_t n = 0;
	while (!_results.empty() && (max_count == 0 || n < max_count)) {
		out.push_back(std::move(_results.front()));
		_results.pop_front();
		n++;
	}
	return n;
}

size_t WorkerPool::pending_jobs() {
	std::lock_guard<std::mutex> lock(_jobs_mutex);
	return _jobs.size();
}

size_t WorkerPool::pending_results() {
	std::lock_guard<std::mutex> lock(_results_mutex);
	return _results.size();
}

void WorkerPool::_worker_main() {
	while (!_stop_flag.load()) {
		RemeshJob job;
		{
			std::unique_lock<std::mutex> lock(_jobs_mutex);
			_jobs_cv.wait(lock, [this] {
				return _stop_flag.load() || !_jobs.empty();
			});
			if (_stop_flag.load()) {
				return;
			}
			job = std::move(_jobs.front());
			_jobs.pop_front();
		}

		RemeshResult result;
		process_remesh_job(job, result);

		{
			std::lock_guard<std::mutex> lock(_results_mutex);
			_results.push_back(std::move(result));
		}
	}
}

} // namespace terrain
} // namespace godot
