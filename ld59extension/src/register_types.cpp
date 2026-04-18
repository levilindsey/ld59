#include "register_types.h"

#include "ld59extension_example.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#ifdef LD59EXTENSION_TESTS_ENABLED
#include <gmock/gmock.h>
#include <gtest/gtest.h>
#include <cstdio>

// Include all test headers here so their TEST() registrations
// are pulled into the translation unit.
#include "test_ld59extension_example.h"
#endif // LD59EXTENSION_TESTS_ENABLED


using namespace godot;


#ifdef LD59EXTENSION_TESTS_ENABLED
// The CI / local test runner greps stdout for this sentinel to
// decide pass/fail.
static void run_ld59extension_tests() {
	int argc = 1;
	char arg0[] = "ld59extension";
	char *argv[] = { arg0, nullptr };
	::testing::InitGoogleMock(&argc, argv);

	const bool passed = RUN_ALL_TESTS() == 0;

	std::printf("\n");
	if (passed) {
		std::printf("ld59extension test result: ALL TESTS PASSED!\n");
	} else {
		std::printf("ld59extension test result: SOME TESTS FAILED!\n");
	}
	std::printf("\n");
	std::fflush(stdout);
}
#endif // LD59EXTENSION_TESTS_ENABLED


void initialize_ld59extension_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	ClassDB::register_class<Ld59extensionExample>();

#ifdef LD59EXTENSION_TESTS_ENABLED
	run_ld59extension_tests();
#endif // LD59EXTENSION_TESTS_ENABLED
}


void uninitialize_ld59extension_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}


extern "C" {

GDExtensionBool GDE_EXPORT ld59extension_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(
			p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_ld59extension_module);
	init_obj.register_terminator(uninitialize_ld59extension_module);
	init_obj.set_minimum_library_initialization_level(
			MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}

} // extern "C"
