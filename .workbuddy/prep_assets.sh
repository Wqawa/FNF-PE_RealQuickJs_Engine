#!/usr/bin/env bash
# 把 assets/base_game 铺进构建产物（BASE_GAME_FILES 没开，lime 不会自动拷这些）。
# 只在本地跑着玩/测试时用，不动仓库里的 assets。
#
# 用法: bash .workbuddy/prep_assets.sh [release|debug]   默认 release
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-release}"
BIN="$ROOT/export/$MODE/windows/bin"

if [ ! -d "$BIN" ]; then
	echo "还没有 $MODE 的 bin 目录，先编译一次"
	exit 1
fi

if [ -f "$BIN/.assets_ready" ]; then
	echo "$MODE 素材已铺过，跳过（删掉 $BIN/.assets_ready 可重铺）"
	exit 0
fi

echo "拷 base_game 素材到 $BIN/assets/body ..."
mkdir -p "$BIN/assets/body" "$BIN/assets/1.0.4" "$BIN/assets/0.6.3"
mkdir -p "$BIN/mods/body" "$BIN/mods/1.0.4" "$BIN/mods/0.6.3"
cp -r "$ROOT/assets/base_game/." "$BIN/assets/body/"

echo "铺原版 1.0.4 素材到 $BIN/assets/1.0.4 ..."
cp -r "$ROOT/assets/1.0.4/." "$BIN/assets/1.0.4/"
# base_game 用硬链接，同一份文件不占两份磁盘
cp -rl "$ROOT/assets/base_game/." "$BIN/assets/1.0.4/" 2>/dev/null \
	|| cp -r "$ROOT/assets/base_game/." "$BIN/assets/1.0.4/"

touch "$BIN/.assets_ready"
echo "done"
