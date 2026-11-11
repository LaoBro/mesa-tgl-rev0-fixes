# Mesa fixes for Tiger Lake-H with PCI revision 0x00

Two small, self-contained Mesa patches for rendering regressions on Intel
TigerLake-H GT1 graphics when the PCI revision reads `0x00`.

These are carried here because the fixes are gated to revision-0 hardware and
upstream review of revision-0-only changes is not guaranteed. Both patches are
no-ops on production steppings.

## Affected hardware

* Intel TigerLake-H GT1 [UHD Graphics], PCI ID `8086:9a60`, PCI revision `0x00`
* Any other gfx12.0 Tiger Lake part that reports revision 0

Check with:

```sh
lspci -nn -s 00:02.0
cat /sys/class/drm/card0/device/revision   # expect 0x00
```

Kernels before 5.12 name the device `TigerLake-H GT1`; newer kernels may show
`TigerLake-H GT1 [UHD Graphics]`.

## The two bugs

| Patch | Symptom | Regression introduced by | Fix |
|---|---|---|---|
| `0001-isl-restore-tgl-rev0-buffer-texture-wa.patch` | Corrupted text/glyphs in Firefox, rendering errors in Chrome on complex pages | `4c06c736c56` ("intel/isl: Remove unknown workaround", Mesa 23.3.0) | Restores the Gen12 revision-0 buffer-texture workaround, narrowed to `gfx12.0 + TGL + revision 0` |
| `0002-iris-restore-pre-fcv-clear-color-tgl-a0.patch` | Opaque color blocks in window/menu shadows and translucent regions (KWin/Wayland, X11/GLAMOR) | `a0bb9cb6d8e` ("iris: Update clear color initializations for FCV", Mesa 25.2.0) | Keeps the pre-`a0bb9cb6d8e` clear-color condition on `TGL + revision 0` |

The first bug is a hardware defect: buffer textures whose base addresses are
less than 64 bytes apart corrupt each other. The PRM only requires buffer
surface base addresses to be aligned to the element size, so sub-64-byte
spacing is a legal descriptor and the corruption is outside the spec.

The second bug is a change to a workaround for Tiger Lake's Fast Clear
Optimization (FCV) hardware behaviour, where a regular draw call can put CCS
blocks into the fast-clear state as a side effect. `a0bb9cb6d8e` replaced a
long-standing clear-color initialization condition; on this hardware it leaves
some resources with an unknown fast-clear value. `INTEL_DEBUG=noccs` hides the
symptom.

## Build

Requirements: a Mesa source tree (git checkout or tarball), `meson`, `ninja`,
and the usual Mesa build dependencies. Tested with `mesa-26.2.3` and Mesa
`main` as of November 2026.

```sh
git clone https://gitlab.freedesktop.org/mesa/mesa.git
cd mesa
git checkout mesa-26.2.3        # or any recent main

/path/to/this/repo/build.sh "$PWD" /path/to/install-prefix
```

`build.sh` applies both patches (it skips any that are already applied),
configures an iris-only build, compiles it, and installs into the given prefix.
The default prefix is `./out`.

Manual equivalent:

```sh
patch -p1 < 0001-isl-restore-tgl-rev0-buffer-texture-wa.patch
patch -p1 < 0002-iris-restore-pre-fcv-clear-color-tgl-a0.patch

meson setup build \
  -Dgallium-drivers=iris \
  -Dvulkan-drivers= \
  -Dplatforms=wayland,x11 \
  -Degl=enabled -Dglx=dri -Dgbm=enabled \
  -Dbuildtype=release --prefix=/path/to/install-prefix
ninja -C build
meson install -C build
```

## Run

For a single application:

```sh
PREFIX=/path/to/install-prefix
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LIBGL_DRIVERS_PATH="$PREFIX/lib/dri"
export GBM_BACKENDS_PATH="$PREFIX/lib/gbm"
export __EGL_VENDOR_LIBRARY_DIRS="$PREFIX/share/glvnd/egl_vendor.d"

glxinfo -B          # renderer should be the Tiger Lake GPU
firefox
```

For a whole desktop session, put the same variables in
`~/.config/environment.d/mesa-local.conf` (or in a custom session script) and
log in again. Note that KWin and other compositors may need
`GBM_BACKENDS_PATH` set before startup.

Some distributions use `lib64` instead of `lib`; adjust the paths accordingly.

## Verify

1. The application really uses this build:

   ```sh
   grep -c "$PREFIX" /proc/$(pgrep -x kwin_wayland | head -1)/maps
   ```

   A non-zero count means KWin loaded libraries from the prefix.

2. No GPU reset polluted the session:

   ```sh
   journalctl -b --no-pager | grep -iE "GPU HANG|Resetting rcs"
   ```

   A hang resets the compositor's GL context and invalidates any rendering
   observation; log in again and re-test.

3. Symptoms: Firefox text renders normally, and window/menu shadows no longer
   show opaque blocks.

## Upstream

* Issue #16852 (font corruption): https://gitlab.freedesktop.org/mesa/mesa/-/work_items/16852
* Issue #16853 (compositor color blocks): https://gitlab.freedesktop.org/mesa/mesa/-/work_items/16853
* MR !46178 (isl workaround): https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/46178
* MR !46180 (iris clear color): https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/46180

The issues contain the bisect logs, the PRM references, and the scope
discussion. If upstream declines the revision-0-only form, this repository is
meant to be the downstream carrier.

## Notes and caveats

* Both patches only change behaviour when `revision == 0`. Production parts are
  unaffected.
* Patch 2 is deliberately narrow (Tiger Lake, revision 0). Whether the clear
  color condition should be restored for all FCV platforms is discussed in
  issue #16853.
* Patch context is Mesa `main` around November 2026 and `mesa-26.2.3`. On other
  trees the hunks may apply with fuzz (`patch -p1 -F3`) or need a refresh.
* Rebuild after a system LLVM or Mesa dependency upgrade. A Mesa build links
  against the system LLVM; if LLVM's soname changes, the old build will fail to
  load.
* This is not an official Intel or Mesa project. No warranty; use at your own
  risk.

## License

MIT. See `LICENSE`. The patches modify Mesa, which is distributed under the
MIT license by its contributors.
