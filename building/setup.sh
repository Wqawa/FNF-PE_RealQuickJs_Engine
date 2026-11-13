#!/usr/bin/env bash
# 编译环境体检：Haxe / haxelib 库版本 / MSVC / Windows SDK / rc.exe。
#
# 默认只读，不改机器上任何东西。缺什么就报什么，退出码 1。
# --fix 才会去 haxelib install（需要网络；离线机器别用）。
#
# 用法：
#   bash building/setup.sh                 完整体检，人看的报告
#   bash building/setup.sh --libs-only     只查库（build.sh 用这个）
#   bash building/setup.sh --fix           缺库时尝试安装
#   bash building/setup.sh --check         同默认，但输出更紧凑
#
# 全程纯 stdout，不弹窗、不抢焦点、不出声。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS_FILE="$ROOT/building/libs.txt"

LIBS_ONLY=0
FIX=0
COMPACT=0

for arg in "$@"; do
	case "$arg" in
		--libs-only) LIBS_ONLY=1 ;;
		--fix)       FIX=1 ;;
		--check)     COMPACT=1 ;;
		-h|-help|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
	esac
done

PROBLEMS=0
ok()   { [ "$COMPACT" = 1 ] || printf '  ok    %s\n' "$*"; }
bad()  { printf '  缺失  %s\n' "$*"; PROBLEMS=$((PROBLEMS+1)); }
warn() { [ "$COMPACT" = 1 ] || printf '  注意  %s\n' "$*"; }
step() { [ "$COMPACT" = 1 ] || printf '\n== %s ==\n' "$*"; }

# ------------------------------------------------------------------ 1. Haxe
step "Haxe"

HAXE_BIN="$(command -v haxe || true)"
if [ -z "$HAXE_BIN" ]; then
	for p in "D:/Haxe/haxe.exe" "C:/Haxe/haxe.exe" "$ROOT/.haxe/haxe.exe"; do
		[ -x "$p" ] && { HAXE_BIN="$p"; break; }
	done
fi

if [ -z "$HAXE_BIN" ]; then
	bad "haxe 不在 PATH 里，也没有常见安装路径"
	HAXE_VER=""
else
	HAXE_VER="$("$HAXE_BIN" --version 2>/dev/null | head -1)"
	ok "haxe $HAXE_VER  ($HAXE_BIN)"
fi

WANT_HAXE="$(awk '$1=="haxe"{print $2}' "$LIBS_FILE" 2>/dev/null)"
if [ -n "$WANT_HAXE" ] && [ -n "$HAXE_VER" ] && [ "$HAXE_VER" != "$WANT_HAXE" ]; then
	warn "期望 haxe $WANT_HAXE，实际 $HAXE_VER（版本不一致时 hxcpp 行为可能变，比如 Std.parseInt 的溢出语义）"
fi

# ------------------------------------------------------------------ 2. 库
step "haxelib 库（版本按 building/libs.txt）"

LIBROOT="$ROOT/.haxelib"
[ -d "$LIBROOT" ] || LIBROOT="$(haxelib config 2>/dev/null | tr -d '\r')"

if [ ! -f "$LIBS_FILE" ]; then
	bad "找不到 building/libs.txt"
else
	while read -r name ver flag; do
		case "${name:-}" in ''|\#*) continue ;; esac
		[ -z "${ver:-}" ] && continue
		# haxe 本身不是 haxelib 库，版本在上面的第 1 节单独查
		[ "$name" = "haxe" ] && continue
		if [ "${flag:-}" = "*debug" ] && [ "${1:-}" != "-debug" ]; then
			# debug 专用库，release 体检不强制
			continue
		fi

		# haxelib 把点号库名落成逗号目录（funkin.vis → funkin,vis），拼路径时要跟着换
		curfile="$LIBROOT/${name//./,}/.current"
		# .current 有的写 2.6.5，有的写 2,6,5（目录名风格），统一成点分再比
		cur=""
		[ -f "$curfile" ] && cur="$(tr -d '\r\n' < "$curfile" 2>/dev/null | tr ',' '.')"

		if [ -z "$cur" ]; then
			bad "$name（未安装，期望 $ver）"
			[ "$FIX" = 1 ] && [ "$ver" != "git" ] && haxelib install "$name" "$ver" --always >/dev/null 2>&1 && \
				printf '        已安装 %s %s\n' "$name" "$ver"
			continue
		fi

		if [ "$ver" = "git" ]; then
			ok "$name (git)"
		elif [ "$cur" = "$ver" ]; then
			ok "$name $cur"
		else
			warn "$name 版本是 $cur，清单写的是 $ver"
			[ "$FIX" = 1 ] && haxelib set "$name" "$ver" >/dev/null 2>&1 && \
				printf '        已切到 %s\n' "$ver"
		fi
	done < "$LIBS_FILE"
fi

[ "$LIBS_ONLY" = 1 ] && { [ "$PROBLEMS" -eq 0 ] && exit 0 || exit 1; }

# ------------------------------------------------------------------ 3. MSVC
step "MSVC / Windows SDK"

pick_msvc() {
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

MSVC_PATH="$(pick_msvc || true)"
if [ -z "$MSVC_PATH" ]; then
	bad "找不到 MSVC（装 VS Build Tools 的「使用 C++ 的桌面开发」，或设 MSVC_DIR）"
else
	ok "MSVC $MSVC_PATH"
fi

# SDK_DIR 指向 Windows Kits 的版本根（例如 G:/Windows Kits/10）；没设就扫各盘的标准位置
SDK_BASE="${SDK_DIR:-}"
if [ -z "$SDK_BASE" ] || [ ! -d "$SDK_BASE/Include" ]; then
	SDK_BASE=""
	for base in \
		"C:/Program Files (x86)/Windows Kits/10" \
		"C:/Program Files/Windows Kits/10" \
		"D:/Windows Kits/10" "E:/Windows Kits/10" "F:/Windows Kits/10" \
		"G:/Windows Kits/10" "H:/Windows Kits/10"; do
		[ -d "$base/Include" ] && { SDK_BASE="$base"; break; }
	done
fi
SDK_VER=""
if [ -d "$SDK_BASE/Include" ]; then
	if [ -d "$SDK_BASE/Include/10.0.19041.0" ]; then
		SDK_VER="10.0.19041.0"
	else
		SDK_VER="$(ls -1 "$SDK_BASE/Include" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)"
	fi
fi
if [ -z "$SDK_VER" ]; then
	bad "找不到 Windows 10/11 SDK（装 Build Tools 时勾上 Windows SDK）"
else
	ok "Windows SDK $SDK_VER"
fi

# rc.exe：lime 8.3 起要把资源编译一遍，hxcpp 直接按名字找 rc.exe，PATH 里没有就 LNK/RC 报错
RC=""
if command -v rc.exe >/dev/null 2>&1; then
	RC="$(command -v rc.exe)"
elif [ -n "$SDK_VER" ] && [ -f "$SDK_BASE/bin/$SDK_VER/x64/rc.exe" ]; then
	RC="$SDK_BASE/bin/$SDK_VER/x64/rc.exe"
elif [ -f "D:/FNF/tools/rc/rc.exe" ]; then
	RC="D:/FNF/tools/rc/rc.exe"
fi

if [ -z "$RC" ]; then
	bad "rc.exe 找不到（PATH 里要有 SDK 的 bin/x64，或者 D:/FNF/tools/rc）"
else
	ok "rc.exe $RC"
fi

# ------------------------------------------------------------------ 汇总
if [ "$COMPACT" = 1 ]; then
	[ "$PROBLEMS" -eq 0 ] && exit 0 || exit 1
fi

printf '\n'
if [ "$PROBLEMS" -eq 0 ]; then
	printf '环境完整，可以编译：bash building/build.sh\n'
	exit 0
fi

printf '有 %d 项缺失。装库可以试：bash building/setup.sh --fix\n' "$PROBLEMS"
exit 1
