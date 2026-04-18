#ifndef LD59EXTENSION_TEST_EXAMPLE_H
#define LD59EXTENSION_TEST_EXAMPLE_H

#ifdef LD59EXTENSION_TESTS_ENABLED

#include "ld59extension_example.h"

#include <godot_cpp/classes/ref.hpp>
#include <gtest/gtest.h>

namespace godot {

// GDCLASS-derived objects must be allocated via memnew() (or Ref<T>)
// so Godot's binding callbacks are registered. Stack allocation
// triggers "Godot Object created without binding callbacks".
TEST(Ld59extensionExampleTest, AddsTwoPositiveIntegers) {
	Ref<Ld59extensionExample> example;
	example.instantiate();
	EXPECT_EQ(5, example->add(2, 3));
}

TEST(Ld59extensionExampleTest, AddsNegativeIntegers) {
	Ref<Ld59extensionExample> example;
	example.instantiate();
	EXPECT_EQ(-7, example->add(-3, -4));
}

TEST(Ld59extensionExampleTest, AddsZero) {
	Ref<Ld59extensionExample> example;
	example.instantiate();
	EXPECT_EQ(42, example->add(42, 0));
}

} // namespace godot

#endif // LD59EXTENSION_TESTS_ENABLED

#endif // LD59EXTENSION_TEST_EXAMPLE_H
