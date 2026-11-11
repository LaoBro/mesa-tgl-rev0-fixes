[English](README.en.md) | 简体中文

# Tiger Lake-H（PCI revision 0x00）Mesa 修复补丁

两个独立、小范围的 Mesa 补丁，用于修复 Intel TigerLake-H GT1 核显在
PCI revision 为 `0x00` 时的渲染异常。

这两个补丁都只对 revision 0 的硬件生效，量产步进完全不受影响。放在这里
是因为上游对「只针对 revision 0」的改动不一定接收，下游用户可以自行携带。

## 受影响的硬件

* Intel TigerLake-H GT1 [UHD Graphics]，PCI ID `8086:9a60`，revision `0x00`
* 其它报告 revision 0 的 gfx12.0 Tiger Lake 部件

确认方法：

```sh
lspci -nn -s 00:02.0
cat /sys/class/drm/card0/device/revision   # 期望 0x00
```

## 两个 bug

| 补丁 | 症状 | 回归来源 | 做法 |
|---|---|---|---|
| `0001-isl-restore-tgl-rev0-buffer-texture-wa.patch` | Firefox 字体/字形破损，Chrome 复杂页面渲染错误 | `4c06c736c56`（Mesa 23.3.0，删除「未知 workaround」） | 恢复 Gen12 revision 0 的 buffer texture workaround，收窄到 `gfx12.0 + TGL + revision 0` |
| `0002-iris-restore-pre-fcv-clear-color-tgl-a0.patch` | 窗口/菜单阴影、半透明区域出现不透明色块（KWin/Wayland、X11/GLAMOR） | `a0bb9cb6d8e`（Mesa 25.2.0，FCV 清色初始化改动） | 在 `TGL + revision 0` 上保留 `a0bb9cb6d8e` 之前的清色初始化条件 |

第一个是硬件缺陷：基地址相差小于 64 字节的 buffer texture 会互相破坏。
PRM 只要求 buffer surface 基地址按元素大小对齐，因此这种描述符是合法的，
数据损坏属于规格之外的行为。

第二个针对的是 Tiger Lake Fast Clear Optimization（FCV）硬件行为的
workaround：普通 draw call 会顺带把 CCS 块推进 fast-clear 状态。
`a0bb9cb6d8e` 换掉了一个长期存在的清色初始化条件，导致这类硬件上部分资源
带着未知的 fast-clear 值。`INTEL_DEBUG=noccs` 可以掩盖症状。

## 构建

依赖：一份 Mesa 源码树（git 或 tarball）、`meson`、`ninja`，以及 Mesa 常规
编译依赖。已在 `mesa-26.2.3` 和 2026 年 11 月的 Mesa `main` 上验证。

```sh
git clone https://gitlab.freedesktop.org/mesa/mesa.git
cd mesa
git checkout mesa-26.2.3        # 或任意较新的 main

/path/to/this/repo/build.sh "$PWD" /path/to/install-prefix
```

`build.sh` 会自动应用两个补丁（已应用的会跳过），配置仅 iris 的构建，
编译并安装到指定前缀。默认前缀是 `./out`。

手动操作等价于：

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

## 运行

单个程序：

```sh
PREFIX=/path/to/install-prefix
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LIBGL_DRIVERS_PATH="$PREFIX/lib/dri"
export GBM_BACKENDS_PATH="$PREFIX/lib/gbm"
export __EGL_VENDOR_LIBRARY_DIRS="$PREFIX/share/glvnd/egl_vendor.d"

glxinfo -B          # renderer 应显示 Tiger Lake 核显
firefox
```

整个桌面会话：把同样的变量写进 `~/.config/environment.d/mesa-local.conf`
或自定义会话脚本，然后注销重登。KWin 等合成器需要在启动前拿到
`GBM_BACKENDS_PATH`。

部分发行版使用 `lib64` 而非 `lib`，按实际情况调整路径。

## 验证

1. 确认程序确实加载了这份构建：

   ```sh
   grep -c "$PREFIX" /proc/$(pgrep -x kwin_wayland | head -1)/maps
   ```

   非零表示 KWin 从该前缀加载了库。

2. 确认本次会话没有 GPU hang：

   ```sh
   journalctl -b --no-pager | grep -iE "GPU HANG|Resetting rcs"
   ```

   hang 会重置合成器的 GL context，使之后的渲染观察全部失效；应重登再测。

3. 症状：Firefox 字体正常，窗口/菜单阴影不再出现不透明色块。

## 上游链接

* Issue #16852（字体破损）：https://gitlab.freedesktop.org/mesa/mesa/-/work_items/16852
* Issue #16853（合成器色块）：https://gitlab.freedesktop.org/mesa/mesa/-/work_items/16853
* MR !46178（isl workaround）：https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/46178
* MR !46180（iris 清色条件）：https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/46180

两个 issue 里有二分记录、PRM 引用和范围讨论。如果上游不接受
「只针对 revision 0」的形式，本仓库作为下游载体继续维护。

## 说明与限制

* 两个补丁仅在 `revision == 0` 时改变行为，量产步进不受影响。
* 补丁 2 刻意只覆盖 Tiger Lake revision 0。是否应把所有 FCV 平台都恢复旧
  条件，见 issue #16853 的讨论。
* 补丁上下文基于 2026 年 11 月前后的 Mesa `main` 与 `mesa-26.2.3`。其它版本
  可能需要 fuzz（`patch -p1 -F3`）或手动刷新。
* 系统 LLVM 或 Mesa 依赖升级后需要重新编译。Mesa 运行时会链接系统 LLVM，
  LLVM soname 变化会导致旧构建无法加载。
* 本项目与 Intel、Mesa 官方无关，不提供任何担保。

## 许可

MIT，见 `LICENSE`。补丁修改的是 Mesa，Mesa 由其贡献者以 MIT 许可分发。
