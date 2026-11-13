#!/usr/bin/env bash
# 打包收尾：把官方素材铺进 bin，然后校验三个引擎的资产到底能不能被读到。
#
# 为什么要有这一步：assets/base_game 是官方素材的单一源（713 个文件），
# assets/body、assets/1.0.4、assets/0.6.3 里只放各版本自己的东西。运行时只认
# bin/assets/<版本>/，所以编译完必须合一次 —— 少了它 freeplay 读不到 weeks、
# 舞台缺图、选歌没声音，而且不报错，只是安静地空着。
#
# 用法：
#   bash building/prep_assets.sh            # release，铺素材 + 校验
#   bash building/prep_assets.sh debug      # debug 构建目录
#   bash building/prep_assets.sh --check    # 只校验，不动文件（发版前用）
#
# 退出码 0 = 资产齐全；1 = 有缺项（build.sh 会因为这一步失败而中止）

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=release
CHECK_ONLY=0

for arg in "$@"; do
	case "$arg" in
		release|debug) MODE="$arg" ;;
		--check|-c)    CHECK_ONLY=1 ;;
		-h|--help)     sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
	esac
done

BIN="$ROOT/export/$MODE/windows/bin"
SRC="$ROOT/assets/base_game"
# 中间清单放 .cache（已 gitignore），不用 mktemp：MSYS 下 mktemp 给的是 /tmp，
# 结尾再 rm -rf 会撞上命令行安全策略
TMP="$ROOT/.cache/prep_assets"
mkdir -p "$TMP"
trap 'rm -f "$TMP"/*.txt 2>/dev/null' EXIT
FAILS=0

fail()  { printf '  缺失  %s\n' "$*"; FAILS=$((FAILS + 1)); }
ok()    { printf '  ok    %s\n' "$*"; }
skip()  { printf '  跳过  %s\n' "$*"; }
head_() { printf '\n== %s ==\n' "$*"; }

[ -d "$BIN" ] || { echo "没有 $BIN —— 先编译（bash building/build.sh）"; exit 1; }
[ -d "$SRC" ] || { echo "没有 assets/base_game —— 素材源不见了"; exit 1; }

# 桌面构建不拷 *.mp3：三棵树的 Paths 都是 `SOUND_EXT = #if web "mp3" #else "ogg"`，
# 桌面只读 .ogg。base_game 里 mp3/ogg 各存一份（mp3 是给 html5 的），
# 全拷过来等于白多 200M。要出网页版再把这个变量留空。
AUDIO_SKIP='*.mp3'

# 列出目录下所有文件的相对路径（排序，供 comm 比较用）。逐个 [ -f ] 判断在 MSYS 下
# 慢到不可用 —— 700 个文件能跑十分钟，所以这里一律走「先列清单再 comm」。
file_list() {
	local dir="$1"; shift
	[ -d "$dir" ] || return 0
	(cd "$dir" && find . -type f "$@" | sed 's|^\./||' | LC_ALL=C sort)
}

# ---------------------------------------------------------------- 铺素材
# 硬链接（cp -l）：同一个盘上不额外占空间，符合 docs/HANDOFF_DUAL_ENGINE.md 里
# 「1.0.4 侧用 cp -rl 省 470M」的约定。已有同名文件不覆盖 —— 版本目录优先。
copy_tree() {
	local src="$1" dst="$2" label="$3"
	mkdir -p "$dst" || { fail "$label：建不出 $dst"; return; }
	local before after
	before=$(find "$dst" -type f 2>/dev/null | wc -l)
	# --parents 保留相对路径，-n 不覆盖，-l 硬链接
	if ! (cd "$src" && find . -type f ! -name "$AUDIO_SKIP" -exec cp -l --parents -n -t "$dst" {} + 2>/dev/null); then
		# 跨盘 / 文件系统不支持硬链接时退回普通拷贝
		(cd "$src" && find . -type f ! -name "$AUDIO_SKIP" -exec cp --parents -n -t "$dst" {} + 2>/dev/null)
	fi
	after=$(find "$dst" -type f 2>/dev/null | wc -l)
	printf '  %-11s %s（%s -> %s 个文件）\n' "$label" "$dst" "$before" "$after"
}

# 老构建残留的 .mp3：只在同目录下已经有同名 .ogg 时才删（桌面反正读 .ogg）
prune_audio() {
	local ver="$1" d="$BIN/assets/$ver"
	[ -d "$d" ] || return 0
	file_list "$d" -name '*.mp3' > "$TMP/mp3.txt"
	file_list "$d" -name '*.ogg' | sed 's|\.ogg$|.mp3|' > "$TMP/ogg_as_mp3.txt"
	LC_ALL=C comm -12 "$TMP/mp3.txt" "$TMP/ogg_as_mp3.txt" > "$TMP/redundant.txt"
	local n
	n=$(wc -l < "$TMP/redundant.txt")
	[ "$n" -gt 0 ] || return 0
	local bytes
	bytes=$(cd "$d" && tr '\n' '\0' < "$TMP/redundant.txt" | du -cb --files0-from=- 2>/dev/null | tail -1 | cut -f1)
	(cd "$d" && tr '\n' '\0' < "$TMP/redundant.txt" | xargs -0 rm -f)
	printf '  %-11s 清掉 %s 个多余的 .mp3（%s MB，桌面读 .ogg）\n' "$ver" "$n" "$(( ${bytes:-0} / 1048576 ))"
}

head_ "铺素材（源：assets/base_game）"
if [ "$CHECK_ONLY" = 1 ]; then
	skip "只校验模式，不铺"
else
	# 两棵 1.0.4 树：官方素材全量
	for ver in body 1.0.4; do
		copy_tree "$SRC" "$BIN/assets/$ver" "assets/$ver"
	done

	# 0.6.3 有自己的素材（命名和老版本一致），只补它缺的周目录 ——
	# 现在缺 week1，week6/week7 里也少几个文件。只加不改。
	for w in week1 week2 week3 week4 week5 week6 week7; do
		[ -d "$SRC/$w" ] || continue
		copy_tree "$SRC/$w" "$BIN/assets/0.6.3/$w" "0.6.3/$w"
	done

	for ver in body 1.0.4 0.6.3; do prune_audio "$ver"; done
fi

# ---------------------------------------------------------------- 运行期目录
head_ "运行期目录"
if [ "$CHECK_ONLY" = 0 ]; then
	# mods/<版本>/ 不存在时 Mods.updateModList() 写列表会直接崩（[file_open, mods/1.0.4/modsList.txt]）
	for d in body 1.0.4 0.6.3 global; do mkdir -p "$BIN/mods/$d"; done
	# engine.txt 读不到就回退 body，这里只是让默认值显式落盘
	[ -f "$BIN/engine.txt" ] || printf 'body' > "$BIN/engine.txt"
fi
for d in body 1.0.4 0.6.3 global; do
	if [ -d "$BIN/mods/$d" ]; then ok "mods/$d"; else fail "mods/$d 不存在"; fi
done
if [ -f "$BIN/engine.txt" ]; then
	ok "engine.txt = $(tr -d '\r\n' < "$BIN/engine.txt")"
else
	fail "engine.txt 不存在（启动会回退 body，但打包产物应该带上）"
fi

# ---------------------------------------------------------------- 素材完整性
head_ "素材完整性"

# 1) 两棵 1.0.4 树必须和 base_game 对齐（*.mp3 是有意不拷的，两边都排除）
file_list "$SRC" ! -name "$AUDIO_SKIP" > "$TMP/base.txt"
for ver in body 1.0.4; do
	file_list "$BIN/assets/$ver" > "$TMP/bin_$ver.txt"
	LC_ALL=C comm -23 "$TMP/base.txt" "$TMP/bin_$ver.txt" > "$TMP/miss_$ver.txt"
	missing=$(wc -l < "$TMP/miss_$ver.txt")
	if [ "$missing" -eq 0 ]; then
		ok "assets/$ver 与 base_game 对齐（$(wc -l < "$TMP/bin_$ver.txt") 个文件）"
	else
		fail "assets/$ver 相对 base_game 少 $missing 个文件"
		head -5 "$TMP/miss_$ver.txt" | sed 's/^/        /'
	fi
done

# 2) 每个引擎：weekList 每条都要有 json（freeplay 列表就是照它生成的）
check_weeks() {
	local ver="$1" weeks_sub="$2"
	local list="$BIN/assets/$ver/$weeks_sub/weekList.txt"
	if [ ! -f "$list" ]; then
		fail "assets/$ver/$weeks_sub/weekList.txt 不存在（freeplay 会是空的）"
		return
	fi
	local n=0 bad=0 name
	while IFS= read -r name; do
		name="${name%$'\r'}"
		[ -z "$name" ] && continue
		n=$((n + 1))
		if [ ! -f "$BIN/assets/$ver/$weeks_sub/$name.json" ]; then
			fail "assets/$ver/$weeks_sub/$name.json 不存在"
			bad=$((bad + 1))
		fi
	done < "$list"
	[ "$bad" -eq 0 ] && ok "assets/$ver：$n 个 week 定义都在"
}

check_weeks body  shared/weeks
check_weeks 1.0.4 shared/weeks
check_weeks 0.6.3 weeks

# 3) 舞台 json 里 "directory" 指的周目录必须存在且非空 ——
#    这才是「舞台缺图」真正的判定点：week 名和素材目录不一定同名（tutorial 就指向 week1）
check_stage_dirs() {
	local ver="$1" stage_sub="$2" dir n=0 bad=0
	[ -d "$BIN/assets/$ver/$stage_sub" ] || { fail "assets/$ver/$stage_sub 目录不存在"; return; }
	for dir in $(grep -h '"directory"' "$BIN/assets/$ver/$stage_sub"/*.json 2>/dev/null |
		sed -n 's/.*"directory"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | LC_ALL=C sort -u); do
		n=$((n + 1))
		if [ ! -d "$BIN/assets/$ver/$dir" ]; then
			fail "assets/$ver/$stage_sub 引用了目录 $dir，但它不存在"
			bad=$((bad + 1))
		elif [ -z "$(find "$BIN/assets/$ver/$dir" -type f 2>/dev/null | head -1)" ]; then
			fail "assets/$ver/$dir 是空目录（舞台图没了）"
			bad=$((bad + 1))
		fi
	done
	[ "$bad" -eq 0 ] && ok "assets/$ver：$n 个舞台素材目录都在"
}

check_stage_dirs body  shared/stages
check_stage_dirs 1.0.4 shared/stages
check_stage_dirs 0.6.3 stages

# 4) 桌面只读 .ogg，剩一堆只有 .mp3 的音频等于静音
for ver in body 1.0.4 0.6.3; do
	d="$BIN/assets/$ver"
	[ -d "$d" ] || continue
	file_list "$d" -name '*.mp3' > "$TMP/mp3_$ver.txt"
	file_list "$d" -name '*.ogg' | sed 's|\.ogg$|.mp3|' > "$TMP/ogg_$ver.txt"
	LC_ALL=C comm -23 "$TMP/mp3_$ver.txt" "$TMP/ogg_$ver.txt" > "$TMP/only_$ver.txt"
	n=$(wc -l < "$TMP/only_$ver.txt")
	if [ "$n" -eq 0 ]; then
		ok "assets/$ver 音频都有 .ogg"
	else
		fail "assets/$ver 有 $n 个音频只有 .mp3（桌面读不到）"
		head -3 "$TMP/only_$ver.txt" | sed 's/^/        /'
	fi
done

# 5) 0 字节的图/音频 —— 素材拷坏时最常见的表现（.txt 占位文件本来就是空的，跳过）
for ver in body 1.0.4 0.6.3; do
	z=$(find "$BIN/assets/$ver" -type f -size 0 ! -name '*.txt' 2>/dev/null | wc -l)
	if [ "$z" -eq 0 ]; then
		ok "assets/$ver 没有空文件"
	else
		fail "assets/$ver 有 $z 个 0 字节文件"
		find "$BIN/assets/$ver" -type f -size 0 ! -name '*.txt' 2>/dev/null | head -5 | sed 's/^/        /'
	fi
done

# 6) 三个引擎标题界面就要用的图，缺了直接黑屏
for pair in "body:shared/images/menuDesat.png" "1.0.4:shared/images/menuDesat.png" "0.6.3:images/menuDesat.png"; do
	ver="${pair%%:*}"; f="${pair#*:}"
	if [ -f "$BIN/assets/$ver/$f" ]; then ok "assets/$ver/$f"; else fail "assets/$ver/$f 不存在"; fi
done

# ---------------------------------------------------------------- 汇总
printf '\n'
if [ "$FAILS" -eq 0 ]; then
	echo "资产齐全，可以发版。"
	exit 0
fi
echo "有 $FAILS 项缺失。补素材：bash building/prep_assets.sh $MODE"
exit 1
