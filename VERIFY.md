# Verification checklist

Run these after building and logging in with the patched Mesa.

## 1. The right libraries are loaded

```sh
KPID=$(pgrep -x kwin_wayland | head -1)
grep -c "/path/to/install-prefix" /proc/$KPID/maps
grep -oE "[^ ]*libgallium[^ ]*" /proc/$KPID/maps | sort -u
```

Expected: a non-zero count, and `libgallium` resolved under the install
prefix. For a single application, inspect that process instead of KWin.

## 2. The session is clean

```sh
journalctl -b --no-pager | grep -iE "GPU HANG|Resetting rcs|EGL_BAD_CONTEXT"
```

A GPU hang resets the compositor's GL context and every later rendering
observation is invalid. If a hang occurred, log in again and re-test.

## 3. Symptoms are gone

* Firefox: open a text-heavy page (for example `developer.mozilla.org`) and
  check that glyphs are not scrambled or missing. No character dropout or
  flicker should appear (the latter was the symptom when the invalidation was
  skipped entirely during diagnosis).
* Compositor: open a window menu and check that shadows and translucent
  regions are not opaque colored blocks.

## 4. Baselines, if needed

Reproduce the original symptoms with an unpatched build:

```sh
PREFIX=/path/to/unpatched-prefix
export LD_LIBRARY_PATH="$PREFIX/lib"
export LIBGL_DRIVERS_PATH="$PREFIX/lib/dri"
export GBM_BACKENDS_PATH="$PREFIX/lib/gbm"
export __EGL_VENDOR_LIBRARY_DIRS="$PREFIX/share/glvnd/egl_vendor.d"
firefox https://developer.mozilla.org
```

`INTEL_DEBUG=noccs` should hide the compositor color blocks on an unpatched
build; it does not help with the font corruption.

## 5. No GPU hang (patch 3)

Scroll an image-heavy page (for example
`https://bing.wdbyte.com/zh-cn/2026-08.html`) for several minutes, then check:

```sh
journalctl -b --no-pager | grep -iE "GPU HANG|Resetting rcs"
```

Expected: empty. Before patch 3 the same workload reset `rcs0` within minutes
on the reference machine. Do not judge from a single short run; use days of
normal use.
