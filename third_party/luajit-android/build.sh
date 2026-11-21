#!/bin/bash
# 自建 Android arm64 版 LuaJIT 静态库（替换 linc_luajit 那个来路不明的预编译 .a）
#
# 为什么要自建：linc_luajit haxelib 里 lib/lua/lib/Android/libluajit-64.a 是
# 社区成员(commit "Add files via upload")上传的二进制，和随库头文件版本对不上，
# 且实测在设备上 luaL_loadbuffer 一编译 chunk 就 SIGSEGV（lj_str_new 里
# global_State->str.mask 一直是 ~0 哨兵值，说明库内部各 .o 不是一次构建出来的）。
#
# 产物：libluajit-64.a（70 个成员，elfasm 版本的 lj_vm.o）
# 用法：在任何有 MSVC + NDK 的机器上  bash build.sh  （产物在本目录）
#
# 环境要求
#   - MSVC 14.2x/14.3x（编 host 侧的 minilua/buildvm，只用来生成 lj_vm.S 和 lj_*.h）
#   - NDK 25.2.9519653（clang/llvm-ar，aarch64-linux-android21）
#   - 源码：https://github.com/LuaJIT/LuaJIT  v2.1 分支 96f7b29
#
# 关键点（踩过的坑）
#   1. 不能只跑 "make CC=clang"：安卓上没有 make，得像下面这样拆成 host/target 两步。
#   2. dynasm 生成 buildvm_arch.h 时必须带齐 -D JIT -D FFI -D DUALNUM -D FPU -D HFABI，
#      否则 vm_arm64.dasc 里的 C 部分会 #error "Only dual-number mode supported"。
#   3. host/buildvm.c 要用 -DLUAJIT_TARGET=LUAJIT_ARCH_arm64 编（否则按 x64 布局生成）。
#   4. src/ljamalg.c 不能进 .a：它和别的 .o 重复定义所有符号，链接器可能优先挑它。
set -e

LUASRC="${LUASRC:?请设 LUASRC 指向 LuaJIT(v2.1) 源码根目录}"
BLD="${BLD:-$PWD/.bld}"
NDK="${NDK:?请设 NDK 指向 NDK 根目录}"

# --- MSVC 环境（按本机实际情况改这三行） ---------------------------------
MSVC="${MSVC:-}"
SDK="${SDK:-}"
SDKVER="${SDKVER:-}"
[ -n "$MSVC" ] && [ -n "$SDK" ] && [ -n "$SDKVER" ] || {
	echo "请设 MSVC=<VC/Tools/MSVC/14.xx> SDK=<Windows Kits/10> SDKVER=<10.0.x>"; exit 1; }
export PATH="$MSVC/bin/Hostx64/x64:$SDK/bin/$SDKVER/x64:$PATH"
export INCLUDE="$(cygpath -m "$MSVC/include");$(cygpath -m "$SDK/Include/$SDKVER/ucrt");$(cygpath -m "$SDK/Include/$SDKVER/shared");$(cygpath -m "$SDK/Include/$SDKVER/um");$(cygpath -m "$SDK/Include/$SDKVER/winrt")"
export LIB="$(cygpath -m "$MSVC/lib/x64");$(cygpath -m "$SDK/Lib/$SDKVER/ucrt/x64");$(cygpath -m "$SDK/Lib/$SDKVER/um/x64")"

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin"
CC="$TOOLCHAIN/clang.exe"
AR="$TOOLCHAIN/llvm-ar.exe"

mkdir -p "$BLD"
cd "$LUASRC/src"

# --- 1. host 工具：minilua + buildvm -------------------------------------
cl -nologo -O2 -I. -Ihost -Fe:"$(cygpath -m "$BLD/minilua.exe")" -Fo:"$(cygpath -m "$BLD")/" host/minilua.c
git show -s --format=%ct > luajit_relver.txt 2>/dev/null || echo 0 > luajit_relver.txt
"$BLD/minilua.exe" host/genversion.lua                       # 生成 luajit.h
"$BLD/minilua.exe" ../dynasm/dynasm.lua -D JIT -D FFI -D DUALNUM -D FPU -D HFABI -D VER=80 \
	-o host/buildvm_arch.h vm_arm64.dasc
cl -nologo -O2 -I. -Ihost -DLUAJIT_TARGET=LUAJIT_ARCH_arm64 -DLJ_ARCH_HASFPU=1 -DLJ_ABI_SOFTFP=0 \
	-Fe:"$(cygpath -m "$BLD/buildvm.exe")" -Fo:"$(cygpath -m "$BLD")/" \
	host/buildvm.c host/buildvm_asm.c host/buildvm_peobj.c host/buildvm_lib.c host/buildvm_fold.c

# --- 2. 生成目标侧文件 ---------------------------------------------------
LJLIB_C=$(ls lib_*.c | grep -v '^lib_init.c$' | grep -v '^lib_aux.c$')
"$BLD/buildvm.exe" -m elfasm -o lj_vm.S
"$BLD/buildvm.exe" -m bcdef   -o lj_bcdef.h   $LJLIB_C
"$BLD/buildvm.exe" -m ffdef   -o lj_ffdef.h   $LJLIB_C
"$BLD/buildvm.exe" -m libdef  -o lj_libdef.h  $LJLIB_C
"$BLD/buildvm.exe" -m recdef  -o lj_recdef.h  $LJLIB_C
mkdir -p jit && "$BLD/buildvm.exe" -m vmdef -o jit/vmdef.lua $LJLIB_C
"$BLD/buildvm.exe" -m folddef -o lj_folddef.h lj_opt_fold.c

# --- 3. 交叉编译（aarch64 / android21） ---------------------------------
OUT="$BLD/ao"; rm -rf "$OUT"; mkdir -p "$OUT"
export OUT CC
export CFLAGS="--target=aarch64-linux-android21 -O3 -fomit-frame-pointer -fno-stack-protector -fPIC -U_FORTIFY_SOURCE -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -I. -DLUAJIT_TARGET=LUAJIT_ARCH_arm64 -DLJ_ARCH_HASFPU=1 -DLJ_ABI_SOFTFP=0"
ls *.c | grep -v '^luajit.c$' | grep -v '^ljamalg.c$' | \
	xargs -P 6 -I@ bash -c 'b=$(basename "@" .c); "$CC" $CFLAGS -c -o "$OUT/$b.o" "@" || echo "FAILED @"'
"$CC" $CFLAGS -c -o "$OUT/lj_vm.o" lj_vm.S

# --- 4. 打包 -------------------------------------------------------------
"$AR" rcs "$BLD/libluajit-64.a" "$OUT"/*.o
echo "OK: $BLD/libluajit-64.a  ($("$AR" t "$BLD/libluajit-64.a" | wc -l) 个成员)"
cp "$BLD/libluajit-64.a" "$(dirname "$0")/libluajit-64.a"
