#!/usr/bin/env bash
# 一轮完整回归：注入测试入口 -> 编译 -> 放脚本 -> 自动开局 -> 收结果 -> 撤掉入口
# 用法: bash .workbuddy/run_test.sh [song]
# 游戏窗口会被挪到屏幕外，不会抢桌面；跑完 source/ 里不留任何临时文件。

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 默认跑 release；调试构建用 PE_BUILD=debug
MODE="${PE_BUILD:-release}"
BIN="$ROOT/export/$MODE/windows/bin"
SONG="${1:-bopeebo}"
PY=python

cleanup() {
	$PY "$ROOT/.workbuddy/harness/apply_hook.py" off > /dev/null 2>&1
	# 这轮塞进 bin 的测试脚本必须带走，不然玩家开游戏满屏 debugPrint
	rm -f "$BIN/mods/body/scripts/broken_probe.lua" "$BIN/mods/body/scripts/compat_callbacks.lua" \
	      "$BIN/mods/body/scripts/compat_edge.lua" "$BIN/mods/body/scripts/compat_more.lua" \
	      "$BIN/mods/body/scripts/compat_v073.lua" "$BIN/mods/body/scripts/compat_v104.lua" \
	      "$BIN/mods/body/scripts/dummy_helper.lua" "$BIN/mods/body/scripts/js_probe.js" \
	      "$BIN/mods/body/scripts/jsSyntax.js" \
	      "$BIN/mods/body/scripts/versionTag(%run_v_0.7.3).lua" "$BIN/mods/body/scripts/versionPlain.lua" \
	      "$BIN/mods/body/scripts/compat_isolation.lua" "$BIN/mods/body/scripts/probe_dedupe.hx" \
	      "$BIN/mods/body/scripts/versionTagHx(%run_v_0.7.3).hx" "$BIN/mods/body/scripts/versionPlainHx.hx"
	rm -f "$BIN/mods/body/stages/stage.lua" "$BIN/mods/body/custom_events/luatestevent.lua"
	rm -f "$BIN/assets/body/custom_notetypes/luatestnote.lua" "$BIN/assets/body/stages/stage.lua" "$BIN/assets/body/custom_events/luatestevent.lua"
	rm -f "$BIN/mods/luatest_save.txt"
	rm -f "$BIN/mods/body/scripts/"*.transpiled.txt 2>/dev/null
	# 还原谱面补丁
	if [ -f "$BIN/assets/body/shared/data/bopeebo/bopeebo.json.orig" ]; then
		cp "$BIN/assets/body/shared/data/bopeebo/bopeebo.json.orig" "$BIN/assets/body/shared/data/bopeebo/bopeebo.json"
		rm -f "$BIN/assets/body/shared/data/bopeebo/bopeebo.json.orig"
	fi
	# 只删空目录， mods 里万一有别人的东西不会动
	rmdir "$BIN/mods/body/scripts" "$BIN/mods/body/stages" "$BIN/mods/body/custom_events" "$BIN/mods/body/custom_notetypes" \
	      "$BIN/assets/body/custom_notetypes" "$BIN/assets/body/stages" "$BIN/assets/body/custom_events" 2>/dev/null
}
trap cleanup EXIT

taskkill //F //IM PsychEngine.exe > /dev/null 2>&1
sleep 1

echo "== 注入测试入口 =="
$PY "$ROOT/.workbuddy/harness/apply_hook.py" on || exit 1

echo "== 编译 =="
rm -f "$ROOT/.workbuddy/build.log"
if [ "$MODE" = "debug" ]; then
	bash "$ROOT/.workbuddy/build.sh" -debug > "$ROOT/.workbuddy/build.log" 2>&1
else
	bash "$ROOT/.workbuddy/build.sh" > "$ROOT/.workbuddy/build.log" 2>&1
fi
if [ $? -ne 0 ]; then
	echo "编译失败："
	tail -25 "$ROOT/.workbuddy/build.log"
	exit 1
fi

echo "== 放测试脚本 =="
mkdir -p "$BIN/mods/body/scripts"
cp "$ROOT/.workbuddy/luatest/scripts/"*.lua "$BIN/mods/body/scripts/"
cp "$ROOT/.workbuddy/luatest/scripts/"*.js "$BIN/mods/body/scripts/" 2>/dev/null
cp "$ROOT/.workbuddy/luatest/scripts/"*.hx "$BIN/mods/body/scripts/" 2>/dev/null

# stage / notetype / event 三类脚本按各自的路径放
mkdir -p "$BIN/mods/body/stages" "$BIN/mods/body/custom_events" "$BIN/mods/body/custom_notetypes"
mkdir -p "$BIN/assets/body/stages" "$BIN/assets/body/custom_notetypes" "$BIN/assets/body/custom_events"
cp "$ROOT/.workbuddy/luatest/mods/stages/"*.lua "$BIN/mods/body/stages/"
cp "$ROOT/.workbuddy/luatest/mods/custom_events/"*.lua "$BIN/mods/body/custom_events/"
# notetype 故意放 assets 根，测 0.6.x 的兜底路径
cp "$ROOT/.workbuddy/luatest/assets/custom_notetypes/"*.lua "$BIN/assets/body/custom_notetypes/"

# 测试脚本里写的是 @@ROOT@@，拷进 bin 时换成真实的仓库根（Windows 风格，游戏是原生程序）
WINROOT="$(cygpath -m "$ROOT" 2>/dev/null || printf '%s' "$ROOT")"
for f in "$BIN/mods/body/scripts/"*.lua "$BIN/mods/body/scripts/"*.js \
         "$BIN/mods/body/stages/"*.lua "$BIN/mods/body/custom_events/"*.lua \
         "$BIN/assets/body/custom_notetypes/"*.lua; do
	[ -f "$f" ] && sed -i "s|@@ROOT@@|$WINROOT|g" "$f"
done

rm -f "$ROOT/.workbuddy/testout/"*.txt
if [ "${NOPATCH:-0}" = "1" ]; then
	echo "跳过谱面补丁（用回原始谱面）"
	if [ -f "$BIN/assets/body/shared/data/bopeebo/bopeebo.json.orig" ]; then
		cp "$BIN/assets/body/shared/data/bopeebo/bopeebo.json.orig" "$BIN/assets/body/shared/data/bopeebo/bopeebo.json"
	fi
else
	python "$ROOT/.workbuddy/luatest/patch_chart.py" || exit 1
fi

echo "== 开局 $SONG =="
# engine.txt 决定 Main.main() 走哪棵树。不是 body 的话测试入口那个补丁不在那条分支上，
# 开局会静默退化成进菜单，一个结果文件都不出。跑完还原。
ORIG_ENGINE="$(cat "$BIN/engine.txt" 2>/dev/null || echo body)"
trap 'cleanup; printf "%s" "$ORIG_ENGINE" > "$BIN/engine.txt"' EXIT
printf 'body' > "$BIN/engine.txt"
cd "$BIN"
# NOMOD：玩家上次选的 mod 会把它自己的 lua/hscript 一起带进来，报错会混进结果里
PE_AUTOTEST="$SONG" PE_AUTOTEST_NOMOD=1 ./PsychEngine.exe > "$ROOT/.workbuddy/game.log" 2>&1 &
GAME_PID=$!

for i in $(seq 1 25); do
	sleep 1
	if [ -f "$ROOT/.workbuddy/testout/v073.txt" ] && grep -q "^DONE|v073" "$ROOT/.workbuddy/testout/v073.txt" 2>/dev/null; then
		sleep 9
		break
	fi
done

taskkill //F //IM PsychEngine.exe > /dev/null 2>&1
wait $GAME_PID 2>/dev/null

echo "== 结果 =="
for f in "$ROOT/.workbuddy/testout/"*.txt; do
	[ -e "$f" ] || continue
	case "$(basename "$f")" in
		js_seen.txt|callbacks.txt|kind_*) continue ;;
	esac
	printf '%-18s PASS=%-3s FAIL=%s\n' "$(basename "$f")" "$(grep -c '^PASS' "$f")" "$(grep -cE '^(FAIL|ERR)' "$f")"
	grep -E "^(FAIL|ERR)" "$f"
done

echo "== stage / notetype / event 脚本 =="
for k in stage notetype event; do
	f="$ROOT/.workbuddy/testout/kind_$k.txt"
	if [ -f "$f" ]; then
		printf '%-10s %s\n' "$k" "$(head -1 "$f")"
	else
		printf '%-10s 没加载\n' "$k"
	fi
done
