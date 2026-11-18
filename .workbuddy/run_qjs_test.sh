#!/usr/bin/env bash
# QuickJS 那条路的回归：真运行时跑 .js，不走 Troll 转译。
# 用法: bash .workbuddy/run_qjs_test.sh [song]
#
# 和 run_test.sh 分开是故意的：那条跑 Lua 兼容层，这条只验证 QuickJS-NG 桥。
# 跑完 bin/mods/scripts 里的测试脚本会清走，source/ 不留临时文件。

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${PE_BUILD:-release}"
BIN="$ROOT/export/$MODE/windows/bin"
# 双引擎改造后 mod 按版本分目录：Paths.mods() = 'mods/<VERSION_DIR>/'，
# 本体这棵树是 mods/body/。以前直接写 mods/scripts 是扫不到的。
MODS="$BIN/mods/body"
SONG="${1:-bopeebo}"
PY=python
OUT="$ROOT/.workbuddy/testout"

cleanup() {
	$PY "$ROOT/.workbuddy/harness/apply_hook.py" off > /dev/null 2>&1
	rm -f "$MODS/scripts/smoke_a.js"
	rm -f "$MODS/qjstest/qjs_child.js"
	rm -f "$MODS/qjs_roundtrip.txt"
	rm -f "$MODS/shaders/qjstest.frag"
	rmdir "$MODS/scripts" "$MODS/qjstest" "$MODS/shaders" 2>/dev/null
}
trap cleanup EXIT

taskkill //F //IM PsychEngine.exe > /dev/null 2>&1
sleep 1

mkdir -p "$OUT"
for f in "$OUT"/qjs_*.txt; do [ -e "$f" ] && rm -f "$f"; done

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
	tail -30 "$ROOT/.workbuddy/build.log"
	exit 1
fi

echo "== 放测试脚本 =="
# smoke_a 放 scripts/，会被开局扫描自动装进来；
# qjs_child 故意放在别的目录，只有 smoke_a 调 addLuaScript 才能把它装进来 ——
# 这样才真的测到「运行时新开一个 context」。
mkdir -p "$MODS/scripts" "$MODS/qjstest" "$MODS/shaders"
cp "$ROOT/.workbuddy/luatest/qjs/smoke_a.js" "$MODS/scripts/"
cp "$ROOT/.workbuddy/luatest/qjs/child/qjs_child.js" "$MODS/qjstest/"
# 这份 .frag 是从本机能跑起来的 mod shader 抄来的。手写的最小 passthrough 在
# 这台机器上编不过（OpenFL 9 生成的 header 没 #version，驱动直接报错），别改回去。
cp "$ROOT/.workbuddy/luatest/qjs/shaders/"*.frag "$MODS/shaders/" 2>/dev/null

WINROOT="$(cygpath -m "$ROOT" 2>/dev/null || printf '%s' "$ROOT")"
for f in "$MODS/scripts/"*.js "$MODS/qjstest/"*.js; do
	[ -f "$f" ] && sed -i "s|@@ROOT@@|$WINROOT|g" "$f"
done
rm -f "$BIN/testout/js_log.txt" "$BIN/testout/quickjs_smoke.txt"

# engine.txt 决定 Main.main() 走哪棵树。留在 pe063 / vanilla 的话，测试入口
# 那个补丁根本不在那条分支上 —— 游戏会直接进菜单，一个结果文件都不会有。
# 跑完还原，别把用户手选的引擎改掉。
ORIG_ENGINE="$(cat "$BIN/engine.txt" 2>/dev/null || echo body)"
restore_engine() { printf '%s' "$ORIG_ENGINE" > "$BIN/engine.txt"; }
# EXIT trap 里最后一条命令的退出码会顶掉脚本本身的，所以收尾时显式 exit 一下，
# 不然 rmdir 失败会让「全绿」也显示成失败
finish() { cleanup; restore_engine; exit "${EXIT_CODE:-0}"; }
trap finish EXIT
printf 'body' > "$BIN/engine.txt"

echo "== 开局 $SONG（jsEngine=QuickJS）=="
cd "$BIN"
PE_AUTOTEST="$SONG" PE_AUTOTEST_JSENGINE=QuickJS PE_AUTOTEST_NOMOD=1 ./PsychEngine.exe > "$ROOT/.workbuddy/game_qjs.log" 2>&1 &
GAME_PID=$!

# 等到 smoke_a 写完结果，再多给两秒让「自卸之后那一帧」真的跑过去
for i in $(seq 1 40); do
	sleep 1
	if [ -f "$OUT/qjs_smoke.txt" ] && grep -q "^DONE|qjs" "$OUT/qjs_smoke.txt" 2>/dev/null; then
		sleep 2
		break
	fi
done

taskkill //F //IM PsychEngine.exe > /dev/null 2>&1
wait $GAME_PID 2>/dev/null

# 运行日志是相对 cwd 写的，落在 bin/testout 里，抄一份到 .workbuddy 留证
[ -f "$BIN/testout/js_log.txt" ] && cp "$BIN/testout/js_log.txt" "$OUT/qjs_js_log.txt"
[ -f "$BIN/testout/quickjs_smoke.txt" ] && cp "$BIN/testout/quickjs_smoke.txt" "$OUT/quickjs_smoke.txt"

echo "== 结果 =="
if [ ! -f "$OUT/qjs_smoke.txt" ]; then
	echo "一个结果文件都没有，说明脚本没进运行时。游戏日志尾巴："
	tail -25 "$ROOT/.workbuddy/game_qjs.log" 2>/dev/null || echo "(连 game_qjs.log 都没有)"
fi
fails=0
for f in "$OUT/qjs_smoke.txt" "$OUT/qjs_selfremove.txt" "$OUT/qjs_child.txt"; do
	if [ ! -e "$f" ]; then
		printf '%-22s 没生成\n' "$(basename "$f")"
		fails=$((fails + 1))
		continue
	fi
	n=$(grep -cE '^(FAIL|ERR)' "$f")
	fails=$((fails + n))
	printf '%-22s PASS=%-3s FAIL=%s\n' "$(basename "$f")" "$(grep -c '^PASS' "$f")" "$n"
	grep -E "^(FAIL|ERR)" "$f"
done

echo "== 链接自检 =="
[ -f "$OUT/quickjs_smoke.txt" ] && cat "$OUT/quickjs_smoke.txt" || echo "quickjs_smoke.txt 没生成"

echo "== js_log.txt =="
[ -f "$OUT/qjs_js_log.txt" ] && cat "$OUT/qjs_js_log.txt" || echo "js_log.txt 没生成"

EXIT_CODE=$fails
exit $fails
