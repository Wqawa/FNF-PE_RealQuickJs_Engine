#!/usr/bin/env bash
# 兼容入口：真正的流程在 manage.sh（环境体检 → 补库 → 编译 → 铺素材 → 校验）。
# 以前这些散在 building/ 里，后来并进 manage.sh，这里只做两件事：
#   1. 把编译裹进 conhost --headless，屏幕上一个窗口都不弹
#   2. 把 -debug / -clean 这些老参数翻译成 manage.sh 的动作名
#
# 用法: bash .workbuddy/build.sh [-debug] [-clean] [release|debug|clean|env|assets|verify]

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 从没有控制台的地方（编辑器 / CI / 后台任务）调起来时，Windows 会给
# haxe、cl.exe、link.exe 各分一个控制台窗口，屏幕上一排黑框闪过去。
# conhost --headless 包一层就全没了；代价是它会吃掉子进程的退出码（一律 0），
# 所以真结果走临时文件带出来，不然编译失败会被当成成功。
if [ -z "${PE_IN_CONHOST:-}" ] && command -v conhost >/dev/null 2>&1; then
	status="$(mktemp 2>/dev/null)"
	PE_IN_CONHOST=1 PE_BUILD_STATUS="$status" conhost --headless bash "$0" "$@"
	rc=1
	[ -n "$status" ] && [ -s "$status" ] && rc="$(cat "$status")"
	rm -f "$status" 2>/dev/null
	exit "${rc:-1}"
fi

ACTION=release
for a in "$@"; do
	case "$a" in
		-debug|--debug|debug) ACTION=debug ;;
		-clean|--clean|clean) ACTION=clean ;;
		env|assets|verify|audit|imports|quickjs) ACTION="$a" ;;
	esac
done

bash "$ROOT/manage.sh" --zh "$ACTION"
rc=$?

# 只在被 conhost 包着的那一层里有意义
if [ -n "${PE_BUILD_STATUS:-}" ]; then printf '%s' "$rc" > "$PE_BUILD_STATUS"; fi
exit $rc
