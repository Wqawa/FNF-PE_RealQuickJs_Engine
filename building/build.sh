#!/usr/bin/env bash
# 一站式编译：探工具链 → 查库 → 关进程 → 编译 → 铺素材 → 验收。
# 参考 codename_re 的 lazy-build，但依赖已经装好的机器，不下载任何东西。
#
# 用法（在仓库任意位置都行）：
#   bash building/build.sh              增量 release
#   bash building/build.sh -debug       debug 构建
#   bash building/build.sh -clean       清掉 export 中间产物后全量重编
#   bash building/build.sh -clean -cache  全量重编 + 打开 hxcpp 编译缓存（第二次全量会快很多）
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
CACHE=0
EXTRA=()

for arg in "$@"; do
	case "$arg" in
		-debug|--debug)   MODE=debug ;;
		-clean|--clean)   CLEAN=1 ;;
		-no-assets)       ASSETS=0 ;;
		-cache|--cache)   CACHE=1 ;;
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
export HAXELIB_PATH="$ROOT/.haxelib"

say "haxe: $("$HAXE_BIN" --version 2>/dev/null)"
say "haxelib 仓库: $HAXELIB_PATH"

# ---------------------------------------------------------------- 2/6 依赖库
step "2/6 haxelib 依赖"

# project.xml 里带 version 的那几个是硬依赖；linc_luajit/flxanimate 走 git 安装，同样必须存在。
REQUIRED=(lime openfl flixel flixel-addons flxanimate hscript-iris tjson hxdiscord_rpc linc_luajit)
if [ "$MODE" = debug ]; then REQUIRED+=(hxcpp-debug-server); fi
# 视频是人肉开关，只在 Project.xml 打开时才要求
if grep -q '<define name="VIDEOS_ALLOWED"' "$ROOT/Project.xml"; then REQUIRED+=(hxvlc); fi

INSTALLED="$(haxelib list 2>/dev/null || true)"
MISSING=()
for lib in "${REQUIRED[@]}"; do
	printf '%s\n' "$INSTALLED" | grep -qiE "^${lib//./\\.}[: ]" || MISSING+=("$lib")
done

if [ ${#MISSING[@]} -gt 0 ]; then
	say "缺库: ${MISSING[*]}"
	say "补库命令（在仓库根执行）："
	say "  haxe -cp commandline --run Main setup    # 或直接跑 setup/windows.bat"
	fail "依赖不齐，先补库。"
fi
say "依赖齐全（${#REQUIRED[@]} 个）"

# ---------------------------------------------------------------- 3/6 MSVC
step "3/6 MSVC / Windows SDK"

pick_msvc() {
	# 优先用环境里已有的，其次扫 VS2019 BuildTools（本机路径），最后才猜默认安装。
	# 返回 Windows 风格路径（D:/...），MSVC 的 INCLUDE/LIB 只认这个。
	if [ -n "${MSVC_DIR:-}" ] && [ -d "$MSVC_DIR" ]; then printf '%s' "$MSVC_DIR"; return; fi
	local base ver
	for base in \
		"D:/VS2019/BuildTools/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC" \
		"C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Tools/MSVC"; do
		[ -d "$base" ] || continue
		ver="$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)"
		[ -n "$ver" ] && { printf '%s' "$base/$ver"; return; }
	done
}

pick_sdk() {
	if [ -n "${SDK_DIR:-}" ] && [ -d "$SDK_DIR" ]; then printf '%s' "$SDK_DIR"; return; fi
	local base ver
	for base in \
		"C:/Program Files (x86)/Windows Kits/10/Include" \
		"C:/Program Files/Windows Kits/10/Include"; do
		[ -d "$base" ] || continue
		# 19041 是这套 hxcpp 验证过的版本，有就用它；没有再取最新的
		if [ -d "$base/10.0.19041.0" ]; then printf '10.0.19041.0'; return; fi
		ver="$(ls -1 "$base" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)"
		[ -n "$ver" ] && { printf '%s' "$ver"; return; }
	done
}

MSVC_PATH="$(pick_msvc || true)"
SDK_VER="$(pick_sdk || true)"
[ -n "$MSVC_PATH" ] || fail "找不到 MSVC。装 VS Build Tools 的「使用 C++ 的桌面开发」，或设 MSVC_DIR。"
[ -n "$SDK_VER" ]    || fail "找不到 Windows 10/11 SDK。装 VS Build Tools 时勾上 Windows SDK，或设 SDK_DIR。"

SDK_BASE="C:/Program Files (x86)/Windows Kits/10"
[ -d "$SDK_BASE" ] || SDK_BASE="C:/Program Files/Windows Kits/10"

export PATH="$MSVC_PATH/bin/Hostx64/x64:$PATH"
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

# hxcpp 编译缓存：只在全量重编时才有收益，日常增量反而要给每个文件写一遍缓存（实测慢几倍），
# 所以默认关，-clean 之类的全量场景再加 -cache。
if [ "$CACHE" = 1 ]; then
	CACHE_DIR="${HXCPP_COMPILE_CACHE:-$ROOT/.cache/hxcpp}"
	if [ "$DRY" = 0 ]; then mkdir -p "$CACHE_DIR" 2>/dev/null && export HXCPP_COMPILE_CACHE="$CACHE_DIR"; fi
fi
say "hxcpp 缓存: ${HXCPP_COMPILE_CACHE:-(关，全量重编时加 -cache)}"

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
	if [ -f "$BIN/.assets_ready" ]; then
		say "base_game 素材已铺过（删 $BIN/.assets_ready 可重铺）"
	else
		if [ -d "$ROOT/assets/base_game" ]; then
			cp -r "$ROOT/assets/base_game/." "$BIN/assets/" && touch "$BIN/.assets_ready"
			say "已铺 base_game 素材"
		else
			say "没有 assets/base_game，跳过素材拷贝"
		fi
	fi
else
	say "按参数跳过素材拷贝"
fi

say ""
say "全部完成。可以跑了："
say "  cd \"$BIN\" && ./PsychEngine.exe"
