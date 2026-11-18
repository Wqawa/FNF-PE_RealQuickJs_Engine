#!/usr/bin/env bash
# 0.6.3 树的路径探针。
#
# 这棵树没有自动测试入口（测试补丁挂在 body 的 Main.main 分支），改完 Paths / 图集
# 之后只能靠它验证。不进游戏、不建 state，窗口在 main() 之前就藏掉，跑完立刻退出。
#
# 用法: bash .workbuddy/run_063_probe.sh
# 结果: .workbuddy/testout/pe063_probe.txt
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/export/release/windows/bin"
ORIG="$(cat "$BIN/engine.txt" 2>/dev/null || echo body)"

restore() {
	printf '%s' "$ORIG" > "$BIN/engine.txt"
}
trap restore EXIT

taskkill //F //IM PsychEngine.exe > /dev/null 2>&1
printf 'pe063' > "$BIN/engine.txt"

cd "$BIN" || exit 1
PE_063_PROBE=1 ./PsychEngine.exe > "$ROOT/.workbuddy/probe_run.log" 2>&1
echo "exit=$?"

echo "== 结果 =="
cat "$ROOT/.workbuddy/testout/pe063_probe.txt" 2>/dev/null || echo "没有结果文件，看 .workbuddy/probe_run.log"
