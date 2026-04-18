# ld59extension

A native C++ GDExtension for the ld59 Godot project, built on
[godot-cpp](https://github.com/godotengine/godot-cpp).

Use this for computation-intensive logic that is slow to implement
in GDScript. Classes defined here are registered with Godot's
`ClassDB` and callable from GDScript like any other Godot class.

## Layout

```
ld59extension/
├── SConstruct          # Build script.
├── src/                # C++ source and colocated test_*.h files.
├── godot-cpp/          # Submodule: Godot C++ bindings.
├── googletest/         # Submodule: GoogleTest (used for C++ tests).
├── build_windows.ps1   # Build Windows .dll into addons/ld59extension/bin/.
├── build_web.ps1       # Build Web .wasm into addons/ld59extension/bin/.
└── build_tests.ps1     # Build with tests=yes and run them.
```

Compiled binaries live under `../addons/ld59extension/bin/` and are
committed to the repo; the manifest at
`../addons/ld59extension/ld59extension.gdextension` declares them to
Godot.

## Prerequisites

- Python 3 on PATH.
- SCons (`pip install scons`).
- **Windows**: MSVC (Visual Studio Build Tools).
- **Web**: [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html).
  Activate `emsdk_env.ps1` in the shell so `emcc` is on PATH.
- Submodules initialised:
  ```
  git submodule update --init --recursive
  ```

## Build

```powershell
# Windows (debug + release).
powershell -ExecutionPolicy Bypass -File ld59extension\build_windows.ps1

# Web (requires Emscripten activated).
powershell -ExecutionPolicy Bypass -File ld59extension\build_web.ps1
```

Or call SCons directly:

```powershell
cd ld59extension
scons platform=windows target=template_debug install
scons platform=web target=template_release install
```

## C++ unit tests

Tests use GoogleTest and are colocated with source in `src/test_*.h`,
gated by the `LD59EXTENSION_TESTS_ENABLED` preprocessor define. The
test runner is invoked from `register_types.cpp` during module
initialisation; it prints a sentinel line that `build_tests.ps1`
greps for.

```powershell
powershell -ExecutionPolicy Bypass -File ld59extension\build_tests.ps1
```

Adding a new test:

1. Create `src/test_my_thing.h` with `#ifdef LD59EXTENSION_TESTS_ENABLED`
   guards and `TEST(MyThingTest, ...)` cases (see
   `src/test_ld59extension_example.h` for the pattern).
2. Include it inside the `LD59EXTENSION_TESTS_ENABLED` block in
   `src/register_types.cpp`.

## Web export caveat

GDExtensions on the Web platform require the Godot web export
template to be built with `dlink_enabled=yes`, so the engine can
dynamically load the `.wasm` module at runtime. The default
templates shipped with Godot 4.5 may not include this. If the web
export errors on `dlink_load`, either:

- Build a custom Godot web export template with
  `scons platform=web dlink_enabled=yes`, or
- Use a template variant that includes dlink support (e.g.
  `web_dlink_nothreads_release.zip`) from upcoming Godot releases.

## Adding a new class

1. Create `src/my_class.h` and `src/my_class.cpp` following
   `ld59extension_example.{h,cpp}` (use `GDCLASS`, `_bind_methods`,
   etc.).
2. In `src/register_types.cpp`, add `#include "my_class.h"` and
   `ClassDB::register_class<MyClass>()` inside
   `initialize_ld59extension_module()`.
3. Rebuild.
