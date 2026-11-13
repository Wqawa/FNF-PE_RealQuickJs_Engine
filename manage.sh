#!/usr/bin/env bash
# FNF-PE RealQuickJS 工具箱 —— 所有脚本的总入口。
#
# 用法：
#   bash manage.sh                 交互式：先选语言，再选功能
#   bash manage.sh --zh            跳过语言选择，直接中文
#   bash manage.sh --en            跳过语言选择，直接英文
#   bash manage.sh --zh 4          直接跑 4 号功能（非交互，给 CI/快捷方式用）
#
# Windows 双击 manage.bat，它转发到这里（需要 Git for Windows 的 bash）。
#
# 这里只做「菜单 + 转发」，真正的逻辑还在 building/ 和 tools/ 里 —— 单点修改，
# 别把逻辑抄进来。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

L=""
ACTION=""

for arg in "$@"; do
	case "$arg" in
		--zh|zh) L=zh ;;
		--en|en) L=en ;;
		-h|--help|-help)
			sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
			exit 0 ;;
		[0-9]*) ACTION="$arg" ;;
	esac
done

# ---------------------------------------------------------------- 文案
say() { if [ "$L" = "en" ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }

choose_language() {
	printf '\n'
	printf '  选择语言 / Select language\n'
	printf '    1) 中文\n'
	printf '    2) English\n'
	printf '\n'
	local pick
	printf '  > '
	read -r pick || exit 0
	case "$pick" in
		2|en|EN|English|english) L=en ;;
		*) L=zh ;;
	esac
}

# ---------------------------------------------------------------- 菜单
print_menu() {
	printf '\n'
	say "==============================================================" \
	    "=============================================================="
	say "  FNF-PE RealQuickJS 工具箱" \
	    "  FNF-PE RealQuickJS Toolbox"
	say "==============================================================" \
	    "=============================================================="
	printf '\n'

	if [ "$L" = "en" ]; then
		printf '  1)  Environment check     read-only: haxe / libs / MSVC / SDK / rc.exe\n'
		printf '  2)  First-time setup      upstream installer for this OS (installs Haxe+libs)\n'
		printf '  3)  Repair libraries      haxelib install/set for whatever is missing\n'
		printf '  4)  Build release         incremental build -> export/release/windows/bin\n'
		printf '  5)  Build debug           incremental debug build\n'
		printf '  6)  Clean rebuild         wipe obj/src first (after Project.xml or lib changes)\n'
		printf '  7)  Prepare assets        copy base_game into bin + verify (after every build)\n'
		printf '  8)  Verify assets only    report missing/changed assets, touch nothing\n'
		printf '  9)  Lua compat audit      diff Lua/HScript API against an upstream PE tree\n'
		printf ' 10)  Rebuild import table  regenerate vanilla HScript import isolation table\n'
		printf '  0)  Quit\n'
	else
		printf '  1)  环境体检        只读检查 Haxe / 库版本 / MSVC / SDK / rc.exe\n'
		printf '  2)  从零装环境      调 setup/ 下对应平台的安装脚本（装 Haxe 本体和库）\n'
		printf '  3)  补/修依赖库     缺哪个 haxelib 库就装/切哪个（要网络）\n'
		printf '  4)  编译 release    增量编译，产物 export/release/windows/bin/PsychEngine.exe\n'
		printf '  5)  编译 debug      增量 debug 编译\n'
		printf '  6)  全量重编        先清 obj/src 再编（改了 Project.xml、换库、诡异链接错误时用）\n'
		printf '  7)  铺素材+校验     把 assets/base_game 铺进 bin 再逐项校验（每次编译后都该跑）\n'
		printf '  8)  只校验资产      不动任何文件，只报缺什么（发版前跑一次）\n'
		printf '  9)  Lua 兼容审计    拿上游 0.6.3 / 0.7.3 源码树当基准，出 markdown 报告\n'
		printf ' 10)  重建 import 表   扫 source_vanilla 重新生成 HScript 的 import 隔离表\n'
		printf '  0)  退出\n'
	fi
	printf '\n'
	say "  输入编号回车 / type a number and press enter" "  type a number and press enter"
	printf '  > '
}

pause_enter() {
	printf '\n'
	say "  回车继续…" "  press enter to continue…"
	read -r _ || true
}

# ---------------------------------------------------------------- 功能
need_python() {
	if command -v python >/dev/null 2>&1; then return 0; fi
	if command -v python3 >/dev/null 2>&1; then return 0; fi
	say "  找不到 python，先装一个（3.8+）" "  python not found, install 3.8+ first"
	return 1
}
PY() { if command -v python >/dev/null 2>&1; then python "$@"; else python3 "$@"; fi; }

run_audit() {
	need_python || return 1

	local def="" p
	for p in "D:/FNF/PE063-ref/source" "D:/FNF/PE073-ref/source" "$ROOT/.workbuddy/upstream/pe073/source"; do
		[ -d "$p" ] && { def="$p"; break; }
	done

	printf '\n'
	say "  基准树（上游某个版本的 source 目录）：" "  reference tree (upstream version's source dir):"
	printf '    1) D:/FNF/PE063-ref/source\n'
	printf '    2) D:/FNF/PE073-ref/source\n'
	printf '    3) 手动输入路径 / enter a path\n'
	printf '  > '
	local pick ref
	read -r pick || return 0
	case "$pick" in
		1) ref="D:/FNF/PE063-ref/source" ;;
		2) ref="D:/FNF/PE073-ref/source" ;;
		*) ref="$def" ;;
	esac
	if [ "$pick" = "3" ] || [ -z "$ref" ]; then
		printf '  path> '
		read -r ref || return 0
	fi
	[ -d "$ref" ] || { say "  目录不存在：$ref" "  not a directory: $ref"; return 1; }

	PY tools/lua_compat_audit.py --ref "$ref"
}

run_first_setup() {
	printf '\n'
	case "$(uname -s)" in
		MINGW*|MSYS*|CYGWIN*)
			if command -v cmd >/dev/null 2>&1; then
				cmd //c "setup\\windows.bat"
			else
				say "  找不到 cmd，手动跑 setup\\windows.bat" "  cmd not found, run setup\\windows.bat yourself"
			fi
			;;
		*)
			bash setup/unix.sh
			;;
	esac
}

run_action() {
	local n="$1"
	case "$n" in
		1) bash building/setup.sh ;;
		2) run_first_setup ;;
		3) bash building/setup.sh --fix ;;
		4) bash building/build.sh ;;
		5) bash building/build.sh -debug ;;
		6) bash building/build.sh -clean ;;
		7) bash building/prep_assets.sh ;;
		8) bash building/prep_assets.sh --check ;;
		9) run_audit ;;
		10) need_python && PY tools/gen_vanilla_imports.py ;;
		0|q|Q) return 99 ;;
		*) say "  没有这个编号" "  no such item"; return 2 ;;
	esac
}

# ---------------------------------------------------------------- 主流程
if [ -z "$L" ]; then
	choose_language
fi

if [ -n "$ACTION" ]; then
	run_action "$ACTION"
	exit $?
fi

while true; do
	print_menu
	read -r choice || exit 0
	printf '\n'
	run_action "$choice"
	rc=$?
	[ "$rc" -eq 99 ] && exit 0
	pause_enter
done
