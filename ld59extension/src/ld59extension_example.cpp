#include "ld59extension_example.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

int Ld59extensionExample::add(int a, int b) const {
	return a + b;
}

void Ld59extensionExample::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("add", "a", "b"), &Ld59extensionExample::add);
}

} // namespace godot
