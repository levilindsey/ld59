#include "worker_pool.h"

#include "douglas_peucker.h"
#include "terrain_settings.h"

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <sstream>

namespace godot {
namespace terrain {

namespace {

// Format a std::thread::id into a String for logging. Used to confirm
// (on web especially) that the worker is actually running on a
// separate pthread rather than silently falling back to main.
String _thread_id_to_string(std::thread::id id) {
	std::ostringstream ss;
	ss << id;
	return String::utf8(ss.str().c_str());
}

} // namespace

void process_remesh_job(const RemeshJob &job, RemeshResult &out) {
	out.coords = job.coords;
	out.submitted_generation = job.submitted_generation;
	out.mesh.clear();
	out.collision_density.clear();
	out.cells = job.cells;
	out.cell_size_px = job.cell_size_px;
	out.origin_px = job.origin_px;
	out.iso = job.iso;

	// Render pass: emit triangles + boundary from the real density
	// field.
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

	// Forward the collision density to the main thread so it can
	// build one ConvexPolygonShape2D per fully-solid cell when the
	// result integrates. We used to run marching_squares on the
	// collision density here too, but per-cell quads with no diagonal
	// edges give more robust depenetration than the triangulated mesh.
	out.collision_density = job.collision_density_snapshot;
}


WorkerPool::WorkerPool() : _stop_flag(false), _jobs_processed(0) {}

WorkerPool::~WorkerPool() {
	stop();
}

void WorkerPool::start() {
	if (_worker.joinable()) {
		return;
	}
	_stop_flag.store(false);
	_jobs_processed.store(0);
	const String main_id = _thread_id_to_string(
			std::this_thread::get_id());
	UtilityFunctions::print(
			"[kbterrain] WorkerPool::start on thread ", main_id,
			" — spawning worker...");
#ifdef __EMSCRIPTEN__
	// Emscripten builds with `-fno-exceptions` by default. If thread
	// spawn fails on web (e.g., template lacks threads=yes or server
	// is missing COOP/COEP), the constructor aborts the program with
	// a loud trace — there is no recovery path here anyway, so the
	// diagnostic try/catch only serves the native build.
	_worker = std::thread(&WorkerPool::_worker_main, this);
#else
	try {
		_worker = std::thread(&WorkerPool::_worker_main, this);
	} catch (const std::exception &e) {
		UtilityFunctions::push_error(
				"[kbterrain] WorkerPool::start FAILED to spawn worker "
				"thread: ",
				String::utf8(e.what()),
				" — remesh will run synchronously on main. Check web "
				"template has threads=yes and server sends COOP/COEP.");
	}
#endif
	if (_worker.joinable()) {
		const String worker_id = _thread_id_to_string(_worker.get_id());
		UtilityFunctions::print(
				"[kbterrain] WorkerPool::start spawned worker thread ",
				worker_id,
				" (main is ", main_id, ")");
		if (worker_id == main_id) {
			UtilityFunctions::push_warning(
					"[kbterrain] WorkerPool worker thread id MATCHES "
					"main thread id — threading is not actually "
					"running in parallel on this build.");
		}
	}
}

void WorkerPool::stop() {
	if (!_worker.joinable()) {
		return;
	}
	_stop_flag.store(true);
	_jobs_cv.notify_all();
	_worker.join();
	UtilityFunctions::print(
			"[kbterrain] WorkerPool::stop joined worker — processed ",
			static_cast<int64_t>(_jobs_processed.load()),
			" total jobs.");
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
	UtilityFunctions::print(
			"[kbterrain] WorkerPool::_worker_main running on thread ",
			_thread_id_to_string(std::this_thread::get_id()));
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
		_jobs_processed.fetch_add(1);
	}
}

} // namespace terrain
} // namespace godot
