#!/usr/bin/env bash
# Builds the KosmicKrisp driver (Mesa) and the Vulkan loader for macOS arm64.
#
# Usage: scripts/build-natives.sh [output-dir]
#
# Requires: brew install meson pkgconf libclc llvm spirv-llvm-translator cmake ninja
set -euo pipefail

MESA_REF=5c80eda3f1c0ac7cb80b0597473ae83da4b97c08
VULKAN_LOADER_REF=fa218055ff4948b159f31d43f800c808a13d51df
VULKAN_HEADERS_REF=6802bb4733b63ed5efd3adb308a6c885ef180ea1
SPIRV_TOOLS_REF=ef96ed763b43b59b33b31b362f09a02b729fa1c9
SPIRV_HEADERS_REF=496543121ce6419f23d6fa5d7194ba66c36212d2

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/src/main/resources/natives/macos-arm64}"
WORK="${WORK_DIR:-$(mktemp -d)}"
PREFIX="$WORK/prefix"
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$OUT" "$WORK" "$PREFIX"

fetch() {
	local url="$1" ref="$2" dir="$3"
	[ -d "$dir/.git" ] && return
	git init -q "$dir"
	git -C "$dir" fetch -q --depth 1 "$url" "$ref"
	git -C "$dir" checkout -q FETCH_HEAD
}

cmake_install() {
	local src="$1"
	shift
	cmake -S "$src" -B "$src/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" "$@"
	cmake --build "$src/build" --parallel "$JOBS"
	cmake --install "$src/build"
}

fetch https://github.com/KhronosGroup/SPIRV-Headers.git "$SPIRV_HEADERS_REF" "$WORK/spirv-headers"
fetch https://github.com/KhronosGroup/SPIRV-Tools.git "$SPIRV_TOOLS_REF" "$WORK/spirv-tools"
fetch https://github.com/KhronosGroup/Vulkan-Headers.git "$VULKAN_HEADERS_REF" "$WORK/vulkan-headers"
fetch https://github.com/KhronosGroup/Vulkan-Loader.git "$VULKAN_LOADER_REF" "$WORK/vulkan-loader"
fetch https://gitlab.freedesktop.org/mesa/mesa.git "$MESA_REF" "$WORK/mesa"

# Static SPIRV-Tools, so the driver does not depend on a dylib outside the system.
cmake_install "$WORK/spirv-tools" -DSPIRV-Headers_SOURCE_DIR="$WORK/spirv-headers" \
	-DSPIRV_SKIP_TESTS=ON -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_WERROR=OFF

cmake_install "$WORK/vulkan-headers"
cmake_install "$WORK/vulkan-loader" -DBUILD_TESTS=OFF

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q mako packaging pyyaml

export PATH="$WORK/venv/bin:$(brew --prefix llvm)/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

meson setup "$WORK/mesa-build" "$WORK/mesa" --buildtype=release --prefer-static \
	-Dplatforms=macos -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dopengl=false -Dzstd=disabled
ninja -C "$WORK/mesa-build"

cp "$WORK/mesa-build/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib" "$OUT/"
cp -L "$PREFIX/lib/libvulkan.1.dylib" "$OUT/"

echo "Built into $OUT"
otool -L "$OUT/libvulkan_kosmickrisp.dylib" "$OUT/libvulkan.1.dylib"
