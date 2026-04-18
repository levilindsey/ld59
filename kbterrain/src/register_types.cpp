#include "register_types.h"

#include "terrain/terrain_settings.h"
#include "terrain/terrain_world.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#ifdef KBTERRAIN_TESTS_ENABLED
#include <gmock/gmock.h>
#include <gtest/gtest.h>
#include <cstdio>

// Include all test headers here so their TEST() registrations
// are pulled into the translation unit.
#include "terrain/test_density_splat.h"
#include "terrain/test_douglas_peucker.h"
#include "terrain/test_marching_squares.h"
#include "terrain/test_terrain_world.h"
#endif // KBTERRAIN_TESTS_ENABLED


using namespace godot;


#ifdef KBTERRAIN_TESTS_ENABLED
// The CI / local test runner greps stdout for this sentinel to
// decide pass/fail.
static void run_kbterrain_tests() {
	int argc = 1;
	char arg0[] = "kbterrain";
	char *argv[] = { arg0, nullptr };
	::testing::InitGoogleMock(&argc, argv);

	const bool passed = RUN_ALL_TESTS() == 0;

	std::printf("\n");
	if (passed) {
		std::printf("kbterrain test result: ALL TESTS PASSED!\n");
	} else {
		std::printf("kbterrain test result: SOME TESTS FAILED!\n");
	}
	std::printf("\n");
	std::fflush(stdout);
}
#endif // KBTERRAIN_TESTS_ENABLED


void initialize_kbterrain_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	ClassDB::register_class<TerrainSettings>();
	ClassDB::register_class<TerrainWorld>();

#ifdef KBTERRAIN_TESTS_ENABLED
	run_kbterrain_tests();
#endif // KBTERRAIN_TESTS_ENABLED
}


void uninitialize_kbterrain_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}


extern "C" {

GDExtensionBool GDE_EXPORT kbterrain_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(
			p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_kbterrain_module);
	init_obj.register_terminator(uninitialize_kbterrain_module);
	init_obj.set_minimum_library_initialization_level(
			MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}

} // extern "C"
