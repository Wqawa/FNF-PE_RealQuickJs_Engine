#!/usr/bin/env bash
# 把 third_party/quickjs-ng 编成 Android arm64-v8a 的静态库（libquickjs-ng.a）。
#
# 跟 manage.sh 里的 MSVC 那条路是两份产物、互不覆盖：
#   Windows : third_party/quickjs-ng/build/quickjs-ng.lib
#   Android : third_party/quickjs-ng/build/android-arm64/libquickjs-ng.a
#
# 为什么用 clang.exe 而不是 aarch64-linux-android21-clang.cmd：
# .cmd 在 Git Bash 里调用要靠 cmd.exe 转一层，路径带盘符时参数容易被截断；
# 直接给 clang 传 --target/--sysroot 少一层壳。

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# clang.exe 是原生 Windows 程序，不认 Git Bash 的 /d/... 路径；换成 D:/... 形式。
# 不换的话会被 MSYS 转成 /d/... 传进去，clang 报 "no such file or directory"。
if command -v cygpath >/dev/null 2>&1; then
	ROOT="$(cygpath -m "$ROOT")"
fi
SRC="$ROOT/third_party/quickjs-ng"
OUT="$SRC/build/android-arm64"
NDK="${PE_ANDROID_NDK:-$ROOT/.workbuddy/toolchain/android-sdk/ndk/25.2.9519653}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/windows-x86_64"
API=21

die() { echo "错误: $*" >&2; exit 1; }

[ -f "$SRC/quickjs.c" ] || die "找不到 $SRC/quickjs.c，仓库里的 quickjs-ng 不完整"
[ -d "$TOOLCHAIN" ] || die "找不到 NDK 工具链: $TOOLCHAIN
  装法: sdkmanager --sdk_root=<sdk> 'ndk;25.2.9519653'
  或者设 PE_ANDROID_NDK 指向已有的 NDK"

CC="$TOOLCHAIN/bin/clang.exe"
AR="$TOOLCHAIN/bin/llvm-ar.exe"
SYSROOT="$TOOLCHAIN/sysroot"
[ -f "$CC" ] || die "找不到 clang: $CC"

mkdir -p "$OUT"

CFLAGS=(
	--target=aarch64-linux-android$API
	--sysroot="$SYSROOT"
	-O2
	-std=c11
	-fPIC
	-D_GNU_SOURCE
	-Wno-everything
)

echo "编译 quickjs-ng -> android-arm64 (API $API)"
objs=()
for name in quickjs libregexp libunicode dtoa; do
	obj="$OUT/$name.o"
	echo "  $name.c"
	MSYS2_ARG_CONV_EXCL='*' "$CC" "${CFLAGS[@]}" -c "$SRC/$name.c" -o "$obj" \
		|| die "$name.c 编译失败"
	objs+=("$obj")
done

MSYS2_ARG_CONV_EXCL='*' "$AR" rcs "$OUT/libquickjs-ng.a" "${objs[@]}" || die "打包静态库失败"

size=$(du -h "$OUT/libquickjs-ng.a" | cut -f1)
echo "完成: $OUT/libquickjs-ng.a ($size)"
