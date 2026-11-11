#!/usr/bin/env bash
# Build Mesa with the two Tiger Lake revision-0 fixes and install into a
# private prefix.
#
# Usage:
#   ./build.sh /path/to/mesa [install-prefix]
#
# The Mesa tree can be a git checkout or an extracted tarball. If it is a git
# checkout the patches are applied with "git apply -3"; otherwise "patch -p1"
# is used. Patches that are already applied are skipped.
#
# Tested with mesa-26.2.3 and Mesa main (November 2026).

set -euo pipefail

SRC=${1:?usage: $0 <mesa-source-dir> [install-prefix]}
PREFIX=${2:-"$PWD/out"}
BUILD=${BUILD_DIR:-"$PWD/build"}
PATCHDIR="$(cd "$(dirname "$0")" && pwd)/patches"

if [ ! -f "$SRC/meson.build" ]; then
    echo "error: $SRC does not look like a Mesa source tree" >&2
    exit 1
fi

apply_patch() {
    local p=$1
    local name
    name=$(basename "$p")

    if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
        if git -C "$SRC" apply --check --reverse "$p" >/dev/null 2>&1; then
            echo "already applied: $name"
            return 0
        fi
        echo "applying: $name"
        git -C "$SRC" apply -3 "$p" 2>/dev/null || git -C "$SRC" apply "$p"
    else
        if patch -d "$SRC" -p1 --forward --dry-run < "$p" >/dev/null 2>&1; then
            echo "applying: $name"
            patch -d "$SRC" -p1 --forward < "$p"
        else
            echo "already applied or does not apply cleanly: $name"
        fi
    fi
}

apply_patch "$PATCHDIR/0001-isl-restore-tgl-rev0-buffer-texture-wa.patch"
apply_patch "$PATCHDIR/0002-iris-restore-pre-fcv-clear-color-tgl-a0.patch"

MESON_ARGS=(
    --prefix="$PREFIX"
    -Dgallium-drivers=iris
    -Dvulkan-drivers=
    -Dplatforms=wayland,x11
    -Degl=enabled
    -Dglx=dri
    -Dgbm=enabled
    -Dbuildtype=release
)

if [ -f "$BUILD/build.ninja" ]; then
    meson setup --reconfigure "$BUILD" "${MESON_ARGS[@]}"
else
    meson setup "$BUILD" "$SRC" "${MESON_ARGS[@]}"
fi

ninja -C "$BUILD"
meson install -C "$BUILD"

cat <<EOF

Installed to: $PREFIX

Run one program against this build:

  export LD_LIBRARY_PATH="$PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
  export LIBGL_DRIVERS_PATH="$PREFIX/lib/dri"
  export GBM_BACKENDS_PATH="$PREFIX/lib/gbm"
  export __EGL_VENDOR_LIBRARY_DIRS="$PREFIX/share/glvnd/egl_vendor.d"
  glxinfo -B

For a whole desktop session, export the same variables from your session
script or ~/.config/environment.d/ and log in again.

If LLVM or another dependency changes its soname, rebuild from scratch:
  rm -rf "$BUILD"
EOF
