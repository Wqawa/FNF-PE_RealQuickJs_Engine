#!/usr/bin/env bash
# 把 assets/base_game 合并进 bin/assets/<版本>/。
#
# base_game 是官方素材的单一源（713 个文件 / 约 470M）——shared 里的 characters、data、
# stages、weeks，加上 songs、videos、week1..week7、weekend1。assets/body 和 assets/1.0.4
# 里只放各版本自己的东西，所以两边都得在编译后合一次，否则运行时 assets/<版本>/ 是半个空壳
# （表现就是 freeplay 读不到 weeks、pixel 舞台缺图、选歌没声音）。
#
# 用硬链接（cp -rl）：同一个盘上不额外占空间，符合 docs/HANDOFF_DUAL_ENGINE.md 里
# 「1.0.4 侧用 cp -rl 省 470M」的约定。目标位置已有同名文件就不覆盖 —— 版本目录优先。
#
# 用法：bash .workbuddy/prep_assets.sh [release|debug]（build.sh 第 6 步自动调）

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-release}"
BIN="$ROOT/export/$MODE/windows/bin"
SRC="$ROOT/assets/base_game"

[ -d "$SRC" ] || { echo "没有 assets/base_game，跳过素材合并"; exit 0; }
[ -d "$BIN" ] || { echo "没有 $BIN，跳过素材合并"; exit 0; }

for ver in body 1.0.4; do
	dst="$BIN/assets/$ver"
	mkdir -p "$dst" || continue

	before=$(find "$dst" -type f 2>/dev/null | wc -l)

	# -n 不覆盖已有文件，-l 硬链接，-r 递归（带 /. 是为了把隐藏文件也算进去）
	if ! cp -rln "$SRC"/. "$dst"/ 2>/dev/null; then
		# 跨盘或者文件系统不支持硬链接时退回普通拷贝
		cp -rn "$SRC"/. "$dst"/ 2>/dev/null
	fi

	after=$(find "$dst" -type f 2>/dev/null | wc -l)
	echo "素材合并: base_game -> assets/$ver（$before -> $after 个文件）"
done
