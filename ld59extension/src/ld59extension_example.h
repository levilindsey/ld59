#ifndef LD59EXTENSION_EXAMPLE_H
#define LD59EXTENSION_EXAMPLE_H

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

class Ld59extensionExample : public RefCounted {
	GDCLASS(Ld59extensionExample, RefCounted)

protected:
	static void _bind_methods();

public:
	int add(int a, int b) const;
};

} // namespace godot

#endif // LD59EXTENSION_EXAMPLE_H
