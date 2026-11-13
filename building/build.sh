#!/usr/bin/env bash
# 一站式编译：探工具链 → 查库 → 关进程 → 编译 → 铺素材 → 验收。
# 参考 codename_re 的 lazy-build，但依赖已经装好的机器，不下载任何东西。
#
# 用法（在仓库任意位置都行）：
#   bash building/build.sh              增量 release（hxcpp 编译缓存默认开）
#   bash building/build.sh -debug       debug 构建
#   bash building/build.sh -clean       清掉 export 中间产物后全量重编
#   bash building/build.sh -no-cache    关掉 hxcpp 编译缓存（排查"缓存里是旧 obj"用）
#   bash building/build.sh -no-assets   跳过 base_game 素材拷贝
#   bash building/build.sh -dry         只打印计划，什么都不做
#
# 产物：export/<release|debug>/windows/bin/PsychEngine.exe
# 日志：building/logs/build-<日期>-<时间>.log

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=release
CLEAN=0
ASSETS=1
DRY=0
CACHE=1
EXTRA=()

for arg in "$@"; do
	case "$arg" in
		-debug|--debug)   MODE=debug ;;
		-clean|--clean)   CLEAN=1 ;;
		-no-assets)       ASSETS=0 ;;
		-no-cache|--no-cache) CACHE=0 ;;
		-dry|--dry-run)   DRY=1 ;;
		-h|-help|--help)  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*)                EXTRA+=("$arg") ;;
	esac
done

LOGDIR="$ROOT/building/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/build-$(date +%Y%m%d-%H%M%S)-$MODE.log"
: > "$LOG"

# 所有输出同时进日志
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
step() { printf '\n== %s ==\n' "$*" | tee -a "$LOG"; }
fail() { printf 'FAIL: %s\n' "$*" | tee -a "$LOG" >&2; exit 1; }

say "仓库: $ROOT"
say "模式: $MODE   日志: $LOG"
[ "$DRY" = 1 ] && say "（dry-run，只打印不执行）"

# ---------------------------------------------------------------- 1/6 工具链
step "1/6 Haxe 工具链"

find_first() {
	for p in "$@"; do
		if [ -x "$p" ] || [ -f "$p" ]; then printf '%s' "$p"; return 0; fi
	done
	return 1
}

HAXE_BIN="$(command -v haxe 2>/dev/null || true)"
if [ -z "$HAXE_BIN" ]; then
	for cand in /d/FNF/Haxe/*/haxe/haxe.exe /c/Haxe/*/haxe.exe /c/haxe/haxe.exe; do
		if [ -f "$cand" ]; then HAXE_BIN="$cand"; break; fi
	done
fi
[ -n "$HAXE_BIN" ] || fail "找不到 haxe。装一份 Haxe 4.3.x，或把它放进 PATH。"
HAXE_DIR="$(cd "$(dirname "$HAXE_BIN")" && pwd)"
NEKO_DIR="$HAXE_DIR/../neko"
[ -d "$NEKO_DIR" ] || NEKO_DIR="$HAXE_DIR"
export PATH="$HAXE_DIR:$NEKO_DIR:$PATH"
say "haxe: $("$HAXE_BIN" --version 2>/dev/null)"

# 仓库自带库目录时优先用它（环境隔离），没有就退回全局 haxelib。
# 硬写 HAXELIB_PATH 会让没建 .haxelib 的机器上所有库都"消失"。
if [ -d "$ROOT/.haxelib" ]; then
	export HAXELIB_PATH="$ROOT/.haxelib"
	say "haxelib 仓库: $HAXELIB_PATH（仓库内）"
else
	say "haxelib 仓库: $(haxelib config 2>/dev/null || echo '?')（全局）"
fi

# ---------------------------------------------------------------- 2/6 依赖库
step "2/6 haxelib 依赖"

# 清单在 building/libs.txt，版本判断在 setup.sh，这里不再维护第二份
if ! bash "$ROOT/building/setup.sh" --libs-only --check; then
	fail "依赖不齐，跑 bash building/setup.sh 看完整报告。"
fi
say "依赖齐全（清单见 building/libs.txt）"

# ---------------------------------------------------------------- 3/6 MSVC
step "3/6 MSVC / Windows SDK"

pick_msvc() {
	# 优先用环境里已有的，其次问 vswhere（装在哪个盘、哪个版本都认），最后才猜常见路径。
	# 返回 Windows 风格路径（D:/...），MSVC 的 INCLUDE/LIB 只认这个。
	if [ -n "${MSVC_DIR:-}" ] && [ -d "$MSVC_DIR" ]; then printf '%s' "$MSVC_DIR"; return; fi

	local vswhere base ver
	for vswhere in \
		"C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe" \
		"C:/Program Files/Microsoft Visual Studio/Installer/vswhere.exe"; do
		[ -f "$vswhere" ] || continue
		base="$("$vswhere" -latest -products '*' \
			-requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
			-property installationPath 2>/dev/null | tr -d '\r' | head -1 | sed 's|\\|/|g')"
		[ -n "$base" ] && [ -d "$base/VC/Tools/MSVC" ] && {
			ver="$(ls -1 "$base/VC/Tools/MSVC" 2>/dev/null | sort -V | tail -1)"
			[ -n "$ver" ] && { printf '%s' "$base/VC/Tools/MSVC/$ver"; return; }
		}
	done

	for base in \
		"G:/vs/program/VC/Tools/MSVC" \
		"D:/VS2019/BuildTools/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2022/Professional/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC" \
		"C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Tools/MSVC"; do
		[ -d "$base" ] || continue
		ver="$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)"
		[ -n "$ver" ] && { printf '%s' "$base/$ver"; return; }
	done
}

# SDK_DIR 直接指向 Windows Kits 的版本根（…/Windows Kits/10）；没设就扫各盘的标准位置
pick_sdk_base() {
	local base
	for base in \
		"${SDK_DIR:-}" \
		"C:/Program Files (x86)/Windows Kits/10" \
		"C:/Program Files/Windows Kits/10" \
		"D:/Windows Kits/10" "E:/Windows Kits/10" "F:/Windows Kits/10" \
		"G:/Windows Kits/10" "H:/Windows Kits/10"; do
		[ -n "$base" ] && [ -d "$base/Include" ] && { printf '%s' "$base"; return; }
	done
}

MSVC_PATH="$(pick_msvc || true)"
SDK_BASE="$(pick_sdk_base || true)"
[ -n "$MSVC_PATH" ] || fail "找不到 MSVC。装 VS Build Tools 的「使用 C++ 的桌面开发」，或设 MSVC_DIR。"
[ -n "$SDK_BASE" ]  || fail "找不到 Windows 10/11 SDK。装 VS Build Tools 时勾上 Windows SDK，或设 SDK_DIR。"

# 19041 是这套 hxcpp 验证过的版本，有就用它；没有再取最新的
SDK_VER=""
if [ -d "$SDK_BASE/Include/10.0.19041.0" ]; then
	SDK_VER="10.0.19041.0"
else
	SDK_VER="$(ls -1 "$SDK_BASE/Include" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)"
fi
[ -n "$SDK_VER" ] || fail "SDK 目录下没有 10.x 版本：$SDK_BASE/Include"

export PATH="$MSVC_PATH/bin/Hostx64/x64:$PATH"
# rc.exe / mt.exe 在 Windows SDK 的 bin 下，hxcpp 链接资源时会直接找 rc.exe
export PATH="$SDK_BASE/bin/$SDK_VER/x64:$PATH"
export INCLUDE="$MSVC_PATH/include;$SDK_BASE/Include/$SDK_VER/ucrt;$SDK_BASE/Include/$SDK_VER/shared;$SDK_BASE/Include/$SDK_VER/um;$SDK_BASE/Include/$SDK_VER/winrt"
export LIB="$MSVC_PATH/lib/x64;$SDK_BASE/Lib/$SDK_VER/ucrt/x64;$SDK_BASE/Lib/$SDK_VER/um/x64"

say "MSVC: $MSVC_PATH"
say "SDK : $SDK_VER"

# ---------------------------------------------------------------- 4/6 预处理
step "4/6 编译前检查"

if tasklist //FI "IMAGENAME eq PsychEngine.exe" 2>/dev/null | grep -qi psychengine; then
	say "游戏正在运行，先关掉（否则 lime.ndll / exe 被占用，链接阶段会失败）"
	[ "$DRY" = 0 ] && taskkill //F //IM PsychEngine.exe >/dev/null 2>&1
	sleep 1
else
	say "没有运行中的游戏"
fi

if [ "$CLEAN" = 1 ]; then
	say "清理 export/$MODE 的中间产物"
	[ "$DRY" = 0 ] && rm -rf "$ROOT/export/$MODE/windows/obj" "$ROOT/export/$MODE/windows/src"
fi

# hxcpp 编译缓存：命中时直接拷 .obj，不再跑 cl.exe。首次填充要给每个文件算一遍哈希 + 写缓存，
# 所以第一次全量会略慢；之后全量重编省一大截，日常增量本来就没几个文件要编，影响很小。
if [ "$CACHE" = 1 ]; then
	CACHE_DIR="${HXCPP_COMPILE_CACHE:-$ROOT/.cache/hxcpp}"
	if [ "$DRY" = 0 ]; then mkdir -p "$CACHE_DIR" 2>/dev/null && export HXCPP_COMPILE_CACHE="$CACHE_DIR"; fi
	say "hxcpp 缓存: $CACHE_DIR"
else
	say "hxcpp 缓存: 关（-no-cache）"
fi

# ---------------------------------------------------------------- 5/6 编译
step "5/6 lime build windows"

BUILD_ARGS=(build windows -nocolor)
[ "$MODE" = debug ] && BUILD_ARGS+=(  -debug )
[ ${#EXTRA[@]} -gt 0 ] && BUILD_ARGS+=("${EXTRA[@]}")

say "命令: haxelib run lime ${BUILD_ARGS[*]}"
[ "$DRY" = 0 ] || { say "（dry-run 到此为止）"; exit 0; }

cd "$ROOT" || fail "进不去仓库根"
START_TS=$(date +%s)
if ! haxelib run lime "${BUILD_ARGS[@]}" >> "$LOG" 2>&1; then
	say "编译失败，日志里的错误："
	grep -iE "error:|Error:" "$LOG" | head -10 | tee -a "$LOG" >&2
	exit 1
fi
say "编译完成，耗时 $(( $(date +%s) - START_TS ))s"

# ---------------------------------------------------------------- 6/6 验收
step "6/6 验收"

BIN="$ROOT/export/$MODE/windows/bin"
EXE="$BIN/PsychEngine.exe"
[ -f "$EXE" ] || fail "没有产物 $EXE"

EXE_TS=$(date -r "$EXE" +%s)
if [ "$EXE_TS" -lt "$START_TS" ]; then
	say "警告：exe 时间戳比这次编译开始还早，lime 可能判定无需重编（要强制重编用 -clean）"
fi
say "产物: $EXE"
say "大小: $(du -h "$EXE" | cut -f1)   时间: $(date -r "$EXE" '+%Y-%m-%d %H:%M')"

WARN_COUNT=$(grep -ci "warning:" "$LOG" || true)
say "编译 warning: $WARN_COUNT 条（上游代码的 deprecated 噪声属正常）"

if [ "$ASSETS" = 1 ]; then
	# 官方素材（base_game）铺进 bin/assets/<版本>/，见 building/prep_assets.sh
	bash "$ROOT/building/prep_assets.sh" "$MODE"
else
	say "按参数跳过素材拷贝"
fi

say ""
say "全部完成。可以跑了："
say "  cd \"$BIN\" && ./PsychEngine.exe"

# 原版侧现在也有 Options → Switch Engine，不再生成 返回本体.bat；老版本留下的顺手清掉。
if [ "$DRY" = 0 ]; then
	rm -f "$BIN/返回本体.bat"
fi
