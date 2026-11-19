#!/usr/bin/env bash
# ============================================================================
#  FNF-PE RealQuickJS —— 唯一的脚本。
#
#  环境体检 / 补库 / 编译 / 铺素材 / 资产校验 / Lua 兼容审计 / vanilla import 表生成 /
#  三条回归 / 安卓构建，全在这里，不互相调用。.workbuddy/ 下只留测试数据和工具链。
#  带动作调用时自己裹 conhost --headless，无控制台也不弹窗。
#
#  用法：
#    bash manage.sh                 交互式：先选语言，再选功能
#    bash manage.sh --zh            跳过语言选择
#    bash manage.sh --en 4          直接跑 4 号功能（CI / 快捷方式）
#    bash manage.sh --zh 10 bopeebo 带参数跑（测试歌名）
#
#  Windows 双击 manage.bat；它只负责找到 bash 然后转给这里（batch 干不了
#  HAHA/awk/硬链接这些活）。
# ============================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

MODE=release
L=""
ACTION=""
EXTRA=()

for arg in "$@"; do
	case "$arg" in
		--zh|zh) L=zh ;;
		--en|en) L=en ;;
		# release/debug 交给下面的 * 当动作名处理（run_action 里已有 2|release / 3|debug），
		# 原来在这里截成 MODE 会导致 ACTION 为空、直接掉进交互菜单
		-h|--help|-help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		# 第一个位置参数是动作，后面的是它的参数（如 test 的歌名）
		*) if [ -z "$ACTION" ]; then ACTION="$arg"; else EXTRA+=("$arg"); fi ;;
	esac
done

# 从没有控制台的地方（编辑器 / CI / 后台）带动作调起来时，Windows 会给
# haxe、cl.exe、link.exe 各弹一个黑框。conhost --headless 包一层就没了；
# 代价是它吃退出码（一律 0），真结果用临时文件带出来。
# 只包「带动作」的调用：交互菜单走 manage.bat 双击，那时有控制台，且
# headless 下读不到 stdin，菜单会直接退出。
if [ -n "$ACTION" ] && [ -z "${PE_IN_CONHOST:-}" ] && command -v conhost >/dev/null 2>&1; then
	status="$(mktemp 2>/dev/null)"
	PE_IN_CONHOST=1 PE_BUILD_STATUS="$status" conhost --headless bash "$0" "$@"
	rc=1
	[ -n "$status" ] && [ -s "$status" ] && rc="$(cat "$status")"
	rm -f "$status" 2>/dev/null
	exit "${rc:-1}"
fi

say()  { if [ "$L" = "en" ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  缺失  %s\n' "$*"; BAD=$((BAD + 1)); }
warn() { printf '  注意  %s\n' "$*"; }
head_(){ printf '\n== %s ==\n' "$*"; }
BAD=0

# ---------------------------------------------------------------- 依赖清单
# 版本只在这里维护一份。写 git 的不校验版本号。
LIBS="
haxe 4.3.2
hxcpp 4.3.2
openfl 9.3.3
lime 8.1.2
flixel 5.6.1
flixel-addons 3.2.2
flixel-tools 1.5.1
flixel-ui 2.6.5
flxanimate git
hscript 2.5.0
hscript-iris 1.1.3
linc_luajit git
tjson 1.4.0
format 3.8.0
funkin.vis git
grig.audio git
hxdiscord_rpc 1.2.4
hxvlc 2.0.1
"

# ---------------------------------------------------------------- 工具链
find_haxe() {
	local cand
	if command -v haxe >/dev/null 2>&1; then HY_BIN="$(command -v haxe)"; return 0; fi
	for cand in /d/FNF/Haxe/*/haxe/haxe.exe /c/Haxe/*/haxe.exe /c/haxe/haxe.exe "$ROOT/.haxe/haxe.exe"; do
		[ -f "$cand" ] && { HY_BIN="$cand"; return 0; }
	done
	return 1
}

setup_toolchain() {
	head_ "Haxe 工具链"
	if ! find_haxe; then
		bad "找不到 haxe"
		say "        装一个 Haxe 4.3.x，或放进 PATH；也可以设 MSVC_DIR / SDK_DIR 后重试" \
		    "        install Haxe 4.3.x or put it in PATH"
		return 1
	fi
	local dir neko
	dir="$(cd "$(dirname "$HY_BIN")" && pwd)"
	neko="$dir/../neko"; [ -d "$neko" ] || neko="$dir"
	export PATH="$dir:$neko:$PATH"
	ok "haxe $("$HY_BIN" --version 2>/dev/null)"

	# 仓内有 .haxelib 就隔离用，没有就用全局
	if [ -d "$ROOT/.haxelib" ]; then
		export HAXELIB_PATH="$ROOT/.haxelib"
		ok "haxelib 仓库 ${HAXELIB_PATH}（仓库内）"
	else
		HAXELIB_PATH="$(haxelib config 2>/dev/null | tr -d '\r')"
		export HAXELIB_PATH
		ok "haxelib 仓库 ${HAXELIB_PATH}（全局）"
	fi
	return 0
}

# ---------------------------------------------------------------- 库校验
lib_path() { printf '%s/%s/.current' "$HAXELIB_PATH" "${1//./,}"; }

check_libs() {
	head_ "haxelib 依赖"
	local name ver cur curfile missing=0
	while read -r name ver; do
		[ -z "${name:-}" ] && continue
		[ "$name" = "haxe" ] && continue
		curfile="$(lib_path "$name")"
		cur=""
		[ -f "$curfile" ] && cur="$(tr -d '\r\n' < "$curfile" | tr ',' '.')"
		if [ -z "$cur" ]; then
			if [ "$ver" = "git" ]; then
				# git 源没法自动装，只提示，不计入缺失
				warn "$name（git 源，需手动 haxelib git）"
			else
				bad "$name（未安装，期望 $ver）"; missing=$((missing + 1))
			fi
			continue
		fi
		if [ "$ver" = "git" ]; then
			ok "$name (git)"
		elif [ "$cur" = "$ver" ]; then
			ok "$name $cur"
		else
			# 版本不符也算需要处理，否则 fix_libs 永远不会去切它
			warn "$name 版本是 $cur，清单写的是 $ver"; missing=$((missing + 1))
		fi
	done <<EOF
$LIBS
EOF
	[ "$missing" -eq 0 ] && return 0 || return 1
}

fix_libs() {
	head_ "补齐 haxelib 库（要网络）"
	local name ver cur curfile
	while read -r name ver; do
		[ -z "${name:-}" ] && continue
		if [ "$name" = "haxe" ]; then continue; fi
		if [ "${ver:-}" = "git" ]; then continue; fi

		curfile="$(lib_path "$name")"
		cur=""
		[ -f "$curfile" ] && cur="$(tr -d '\r\n' < "$curfile" | tr ',' '.')"

		if [ -z "$cur" ]; then
			printf '  装 %s %s\n' "$name" "$ver"
			# haxelib 会从 stdin 读东西，不隔离的话会把 heredoc 里剩下的库清单整段吃掉
			if haxelib install "$name" "$ver" --always </dev/null >/dev/null 2>&1; then
				ok "$name $ver"
			else
				warn "$name 装失败"
			fi
		elif [ "$cur" != "$ver" ]; then
			# haxelib set 对没装过的版本也返回 0（只改 .current 不下载），
			# 所以不能看返回码，要回读 .current + 确认版本目录真的存在
			haxelib set "$name" "$ver" </dev/null >/dev/null 2>&1 || true
			local now="" vdir
			[ -f "$curfile" ] && now="$(tr -d '\r\n' < "$curfile" | tr ',' '.')"
			vdir="$HAXELIB_PATH/${name//./,}/$(printf '%s' "$ver" | tr '.' ',')"
			if [ "$now" = "$ver" ] && [ -d "$vdir" ]; then
				ok "$name $ver"
			else
				printf '  装 %s %s（本机没有，开始下载）\n' "$name" "$ver"
				if haxelib install "$name" "$ver" --always </dev/null >/dev/null 2>&1 \
					&& haxelib set "$name" "$ver" </dev/null >/dev/null 2>&1 \
					&& [ -d "$vdir" ]; then
					ok "$name $ver"
				else
					warn "$name 切 $ver 失败（下载或安装没成功）"
				fi
			fi
		fi
	done <<EOF
$LIBS
EOF
	say "  git 源的库要手动：" "  git-based libs must be installed manually:"
	cat <<'EOF'
    haxelib git flxanimate  https://github.com/Dot-Stuff/flxanimate 768740a56b26aa0c072720e0d1236b94afe68e3e
    haxelib git linc_luajit https://github.com/superpowers04/linc_luajit
    haxelib git funkin.vis  https://github.com/FunkinCrew/funkVis 22b1ce089dd924f15cdc4632397ef3504d464e90
    haxelib git grig.audio  https://gitlab.com/haxe-grig/grig.audio.git cbf91e2180fd2e374924fe74844086aab7891666
EOF
}

# ---------------------------------------------------------------- MSVC / SDK
pick_msvc() {
	if [ -n "${MSVC_DIR:-}" ] && [ -d "$MSVC_DIR" ]; then printf '%s' "$MSVC_DIR"; return; fi
	local vswhere base ver
	for vswhere in \
		"C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe" \
		"C:/Program Files/Microsoft Visual Studio/Installer/vswhere.exe"; do
		[ -f "$vswhere" ] || continue
		base="$("$vswhere" -latest -products '*' \
			-requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
			-property installationPath 2>/dev/null | tr -d '\r' | head -1 | sed 's|\\|/|g')"
		[ -n "$base" ] && [ -d "$base/VC/Tools/MSVC" ] && {
			# 太新的 MSVC 编不过 hxcpp 生成的 C++：VS2026 的 14.4x 起 xlocale 里
			# _Codecvt_do_length / _Mbstatet 一堆 C2893/C2079，只能退到 14.3x 及以下。
			# 同一个安装下可能并存多个版本，倒序遍历，挑第一个能用的。
			for ver in $(ls -1 "$base/VC/Tools/MSVC" 2>/dev/null | sort -Vr); do
				if [ "$(printf '%s' "$ver" | cut -d. -f2)" -lt 40 ] 2>/dev/null; then
					printf '%s' "$base/VC/Tools/MSVC/$ver"; return
				fi
			done
		}
	done
	for base in \
		"G:/vs/program/VC/Tools/MSVC" \
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
	local base
	for base in "${SDK_DIR:-}" \
		"C:/Program Files (x86)/Windows Kits/10" "C:/Program Files/Windows Kits/10" \
		"D:/Windows Kits/10" "E:/Windows Kits/10" "F:/Windows Kits/10" "G:/Windows Kits/10"; do
		[ -n "$base" ] && [ -d "$base/Include" ] && { printf '%s' "$base"; return; }
	done
}

setup_msvc() {
	head_ "MSVC / Windows SDK"
	MSVC_PATH="$(pick_msvc || true)"
	SDK_BASE="$(pick_sdk || true)"
	[ -n "$MSVC_PATH" ] || { bad "找不到 MSVC（装 Build Tools 的 C++ 工作负载，或设 MSVC_DIR）"; return 1; }
	[ -n "$SDK_BASE" ] || { bad "找不到 Windows 10/11 SDK（或设 SDK_DIR）"; return 1; }

	SDK_VER=""
	if [ -d "$SDK_BASE/Include/10.0.19041.0" ]; then
		SDK_VER="10.0.19041.0"
	else
		SDK_VER="$(ls -1 "$SDK_BASE/Include" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)"
	fi
	[ -n "$SDK_VER" ] || { bad "SDK 下没有 10.x：$SDK_BASE/Include"; return 1; }

	export PATH="$MSVC_PATH/bin/Hostx64/x64:$SDK_BASE/bin/$SDK_VER/x64:$PATH"
	export INCLUDE="$MSVC_PATH/include;$SDK_BASE/Include/$SDK_VER/ucrt;$SDK_BASE/Include/$SDK_VER/shared;$SDK_BASE/Include/$SDK_VER/um;$SDK_BASE/Include/$SDK_VER/winrt"
	export LIB="$MSVC_PATH/lib/x64;$SDK_BASE/Lib/$SDK_VER/ucrt/x64;$SDK_BASE/Lib/$SDK_VER/um/x64"
	ok "MSVC $MSVC_PATH"
	ok "SDK  $SDK_VER"
	return 0
}

# ---------------------------------------------------------------- 环境体检
cmd_env() {
	BAD=0
	setup_toolchain || true
	if [ -n "${HAXELIB_PATH:-}" ]; then
		# 体检顺便修：缺库就直接装/切，补完复查一遍。补库要网络，失败只告警不中断。
		if ! check_libs; then
			say "  库不全，自动补齐（要网络）…" "  libraries incomplete, repairing (needs network)..."
			if fix_libs; then
				head_ "复查 haxelib 依赖" "re-check haxelib"
				check_libs || true
			else
				warn "自动补库失败，检查网络，或手动装 git 源的库"
			fi
		fi
	fi
	setup_msvc || true
	head_ "其它"
	command -v rc.exe >/dev/null 2>&1 || [ -f "$SDK_BASE/bin/$SDK_VER/x64/rc.exe" ] \
		&& ok "rc.exe" || warn "rc.exe 不在 PATH（lime 8.3+ 编资源要用）"
	command -v python >/dev/null 2>&1 && ok "python" || warn "没有 python（只影响审计功能）"
	# JS 运行时：源码随仓库来，静态库编译时自动生成
	if [ -f "$QJS_SRC/quickjs.c" ]; then
		if [ -f "$QJS_LIB" ]; then
			ok "QuickJS-NG 源码 + 静态库（$(du -h "$QJS_LIB" | cut -f1)）"
		else
			ok "QuickJS-NG 源码（静态库还没编，第一次 build 会自动编）"
		fi
	else
		bad "third_party/quickjs-ng 源码缺失（JS 脚本会编不过）"
	fi
	printf '\n'
	[ "$BAD" -eq 0 ] && say "环境完整。" "Environment looks fine." || say "有 $BAD 项缺失。" "$BAD problem(s)."
	return $([ "$BAD" -eq 0 ] && echo 0 || echo 1)
}

# ---------------------------------------------------------------- 编译
cmd_build() {
	local clean="${1:-0}" args
	setup_toolchain || return 1
	check_libs || { say "依赖不齐，先跑 1 号环境体检（会自动补库）" "dependencies missing, run item 1 (auto-repairs libs)"; return 1; }
	setup_msvc || return 1

	# QuickJS.hx 的 libpath / #include 都是相对 hxcpp 构建目录的，仓库搬到哪都不用改。
	# （以前这里用 sed 把绝对路径对齐到当前根目录，2026-11-17 改成相对路径后不再需要。）

	if tasklist //FI "IMAGENAME eq realQuickJSEngine.exe" 2>/dev/null | grep -qi realquickjsengine; then
		say "  游戏在跑，先关掉" "  game is running, closing it"
		taskkill //F //IM realQuickJSEngine.exe >/dev/null 2>&1
		sleep 1
	fi
	# 引擎要链接 QuickJS-NG（JS 运行时）。源码在仓库里，静态库在本机编；
	# 缺了或比源码旧就先编，编不出来就别往下走（否则链接阶段才炸，报错更难认）。
	ensure_quickjs || return 1

	if [ "$clean" = 1 ]; then
		say "  清 obj/src" "  wiping obj/src"
		rm -rf "export/$MODE/windows/obj" "export/$MODE/windows/src" 2>/dev/null
	fi

	mkdir -p .cache/hxcpp 2>/dev/null && export HXCPP_COMPILE_CACHE="$ROOT/.cache/hxcpp"

	args=(build windows -nocolor)
	[ "$MODE" = debug ] && args+=(-debug)
	say "  编译（$MODE）…" "  building ($MODE)…"
	local t0
	t0=$(date +%s)
	if ! haxelib run lime "${args[@]}" 2>&1 | tee ".cache/build-$MODE.log" | tail -3; then
		say "  编译失败，看 .cache/build-$MODE.log" "  build failed, see .cache/build-$MODE.log"
		return 1
	fi
	ok "编译完成 $(( $(date +%s) - t0 ))s"
	cmd_assets 0 || return 1
}

# ---------------------------------------------------------------- 素材
# 桌面只读 .ogg（三棵树 SOUND_EXT 都是 ogg unless web），mp3 是给 html5 的，不拷
AUDIO_SKIP='*.mp3'

copy_tree() {
	local src="$1" dst="$2" label="$3" before after
	mkdir -p "$dst" || { bad "$label：建不出目录"; return; }
	before=$(find "$dst" -type f 2>/dev/null | wc -l)
	if ! (cd "$src" && find . -type f ! -name "$AUDIO_SKIP" -exec cp -l --parents -n -t "$dst" {} + 2>/dev/null); then
		(cd "$src" && find . -type f ! -name "$AUDIO_SKIP" -exec cp --parents -n -t "$dst" {} + 2>/dev/null)
	fi
	after=$(find "$dst" -type f 2>/dev/null | wc -l)
	printf '  %-11s %s（%s -> %s 个文件）\n' "$label" "$dst" "$before" "$after"
}

file_list() { [ -d "$1" ] || return 0; (cd "$1" && find . -type f "${@:2}" | sed 's|^\./||' | LC_ALL=C sort); }

cmd_assets() {
	local check="${1:-0}" BIN="$ROOT/export/$MODE/windows/bin" SRC="$ROOT/assets/base_game" TMP="$ROOT/.cache/manage"
	mkdir -p "$TMP"
	BAD=0

	[ -d "$BIN" ] || { say "没有 $BIN，先编译" "no $BIN, build first"; return 1; }
	[ -d "$SRC" ] || { say "没有 assets/base_game" "assets/base_game missing"; return 1; }

	head_ "素材（源：assets/base_game）"
	if [ "$check" = 1 ]; then
		printf '  只校验，不铺\n'
	else
		for ver in body 1.0.4; do copy_tree "$SRC" "$BIN/assets/$ver" "assets/$ver"; done
		for w in week1 week2 week3 week4 week5 week6 week7; do
			[ -d "$SRC/$w" ] || continue
			copy_tree "$SRC/$w" "$BIN/assets/0.6.3/$w" "0.6.3/$w"
		done
		# 老构建残留的 mp3：同目录有同名 .ogg 才删
		local ver d n
		for ver in body 1.0.4 0.6.3; do
			d="$BIN/assets/$ver"; [ -d "$d" ] || continue
			file_list "$d" -name '*.mp3' > "$TMP/mp3.txt"
			file_list "$d" -name '*.ogg' | sed 's|\.ogg$|.mp3|' > "$TMP/ogg.txt"
			LC_ALL=C comm -12 "$TMP/mp3.txt" "$TMP/ogg.txt" > "$TMP/dup.txt"
			n=$(wc -l < "$TMP/dup.txt")
			[ "$n" -gt 0 ] && { (cd "$d" && tr '\n' '\0' < "$TMP/dup.txt" | xargs -0 rm -f); printf '  %-11s 清掉 %s 个多余 mp3\n' "$ver" "$n"; }
		done

		# 老布局残留：assets/ 根下的 shared、songs、fonts 这些现在是按版本分的
		# （assets/<版本>/shared/...）。根上那几份是 11-08 之前那套结构的，白占 30 多 M，
		# 还容易让人以为素材没分版本。只清这张白名单，版本目录一个都不碰。
		local old
		for old in fonts shared songs images characters data stages weeks music sounds videos dialogues \
			week1 week2 week3 week4 week5 week6 week7; do
			[ -d "$BIN/assets/$old" ] || continue
			rm -rf "${BIN:?}/assets/$old"
			printf '  %-11s 清掉老布局残留 assets/%s\n' "root" "$old"
		done
	fi

	head_ "运行期目录"
	if [ "$check" = 0 ]; then
		# 没有全局 mod 了（2026-11-16 删的机制），只留三棵树各自的目录
		for d in body 1.0.4 0.6.3; do mkdir -p "$BIN/mods/$d"; done
		[ -f "$BIN/engine.txt" ] || printf 'body' > "$BIN/engine.txt"
	fi
	for d in body 1.0.4 0.6.3; do [ -d "$BIN/mods/$d" ] && ok "mods/$d" || bad "mods/$d 不存在"; done
	[ -f "$BIN/engine.txt" ] && ok "engine.txt = $(tr -d '\r\n' < "$BIN/engine.txt")" || bad "engine.txt 不存在"

	head_ "素材完整性"
	file_list "$SRC" ! -name "$AUDIO_SKIP" > "$TMP/base.txt"
	local ver missing
	for ver in body 1.0.4; do
		file_list "$BIN/assets/$ver" > "$TMP/bin.txt"
		LC_ALL=C comm -23 "$TMP/base.txt" "$TMP/bin.txt" > "$TMP/miss.txt"
		missing=$(wc -l < "$TMP/miss.txt")
		if [ "$missing" -eq 0 ]; then
			ok "assets/$ver 与 base_game 对齐（$(wc -l < "$TMP/bin.txt") 个文件）"
		else
			bad "assets/$ver 少 $missing 个文件"
			head -5 "$TMP/miss.txt" | sed 's/^/        /'
		fi
	done

	# weekList 每条都要有 json
	local weeks_sub list name n badw
	check_weeks() {
		weeks_sub="$2"; list="$BIN/assets/$1/$weeks_sub/weekList.txt"
		[ -f "$list" ] || { bad "assets/$1/$weeks_sub/weekList.txt 不存在"; return; }
		n=0; badw=0
		while IFS= read -r name; do
			name="${name%$'\r'}"; [ -z "$name" ] && continue
			n=$((n + 1))
			[ -f "$BIN/assets/$1/$weeks_sub/$name.json" ] || { bad "assets/$1/$weeks_sub/$name.json 不存在"; badw=$((badw + 1)); }
		done < "$list"
		[ "$badw" -eq 0 ] && ok "assets/$1：$n 个 week 定义都在"
	}
	check_weeks body shared/weeks
	check_weeks 1.0.4 shared/weeks
	check_weeks 0.6.3 weeks

	# 舞台 json 的 directory 目录必须存在且非空
	local stage_sub dir
	check_stage_dirs() {
		stage_sub="$2"
		[ -d "$BIN/assets/$1/$stage_sub" ] || { bad "assets/$1/$stage_sub 不存在"; return; }
		n=0; badw=0
		for dir in $(grep -h '"directory"' "$BIN/assets/$1/$stage_sub"/*.json 2>/dev/null |
			sed -n 's/.*"directory"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | LC_ALL=C sort -u); do
			n=$((n + 1))
			if [ ! -d "$BIN/assets/$1/$dir" ]; then
				bad "assets/$1/$stage_sub 引用的目录 $dir 不存在"; badw=$((badw + 1))
			elif [ -z "$(find "$BIN/assets/$1/$dir" -type f 2>/dev/null | head -1)" ]; then
				bad "assets/$1/$dir 是空目录"; badw=$((badw + 1))
			fi
		done
		[ "$badw" -eq 0 ] && ok "assets/$1：$n 个舞台素材目录都在"
	}
	check_stage_dirs body shared/stages
	check_stage_dirs 1.0.4 shared/stages
	check_stage_dirs 0.6.3 stages

	# 只剩 mp3 的音频 = 桌面静音；0 字节文件 = 拷坏了
	local z
	for ver in body 1.0.4 0.6.3; do
		file_list "$BIN/assets/$ver" -name '*.mp3' > "$TMP/mp3.txt"
		file_list "$BIN/assets/$ver" -name '*.ogg' | sed 's|\.ogg$|.mp3|' > "$TMP/ogg.txt"
		z=$(LC_ALL=C comm -23 "$TMP/mp3.txt" "$TMP/ogg.txt" | wc -l)
		[ "$z" -eq 0 ] && ok "assets/$ver 音频都有 .ogg" || bad "assets/$ver 有 $z 个音频只有 mp3"

		z=$(find "$BIN/assets/$ver" -type f -size 0 ! -name '*.txt' 2>/dev/null | wc -l)
		[ "$z" -eq 0 ] && ok "assets/$ver 没有空文件" || bad "assets/$ver 有 $z 个 0 字节文件"
	done
	[ -f "$BIN/assets/body/shared/images/menuDesat.png" ] && ok "标题图 body" || bad "body 少 menuDesat.png"
	[ -f "$BIN/assets/1.0.4/shared/images/menuDesat.png" ] && ok "标题图 1.0.4" || bad "1.0.4 少 menuDesat.png"
	[ -f "$BIN/assets/0.6.3/images/menuDesat.png" ] && ok "标题图 0.6.3" || bad "0.6.3 少 menuDesat.png"

	printf '\n'
	[ "$BAD" -eq 0 ] && { say "资产齐全。" "Assets are complete."; return 0; }
	say "有 $BAD 项缺失。" "$BAD problem(s)."
	return 1
}

# ---------------------------------------------------------------- import 隔离表
# 扫 source_vanilla/vanilla 的 package + 顶格类型声明，重写 IsolatedImports.hx
cmd_imports() {
	local out="source_vanilla/vanilla/psychlua/IsolatedImports.hx"
	mkdir -p .cache
	head_ "重建 vanilla import 隔离表"
	[ -d source_vanilla/vanilla ] || { bad "没有 source_vanilla/vanilla"; return 1; }

	awk '
		FNR == 1 { pkg = "" }
		/^[ \t]*package / {
			p = $0
			sub(/^[ \t]*package[ \t]+/, "", p)
			sub(/[ \t]*;.*$/, "", p)
			sub(/[ \t]+$/, "", p)
			if (p == "vanilla") p = ""
			else if (p ~ /^vanilla\./) { sub(/^vanilla\./, "", p) }
			pkg = p
			next
		}
		/^(final |abstract |class |enum |typedef )/ {
			line = $0
			sub(/^(final |abstract |class |enum |typedef )/, "", line)
			sub(/[^A-Za-z0-9_].*$/, "", line)
			if (line != "" && line ~ /^[A-Za-z_]/) {
				print (pkg == "" ? line : pkg "." line)
			}
		}
	' $(find source_vanilla/vanilla -name '*.hx' | LC_ALL=C sort) | LC_ALL=C sort -u > .cache/vanilla_classes.txt

	local n
	n=$(wc -l < .cache/vanilla_classes.txt)
	[ "$n" -gt 0 ] || { bad "扫不出类"; return 1; }

	{
		cat <<'EOF'
package vanilla.psychlua;

import crowplexus.iris.Iris;

/**
 * Import isolation table for the vanilla tree.
 *
 * Three trees in one exe: `import backend.ClientPrefs` is character for character the same
 * as the body's, and hscript-iris checks Iris.proxyImports before Type.resolveClass -
 * which hits the body class. So this table is loaded into proxyImports before scripts run.
 *
 * Generated by manage.sh (option 8) scanning this directory. Do not edit by hand.
 * The sweep + ENGINE_PACKAGES guards below are part of the template: regenerating
 * without them silently brings back cross-tree class resolution.
 */
class IsolatedImports
{
	public static var CLASSES:Array<String> = [
EOF
		sed 's/.*/\t\t'"'"'&'"'"',/' .cache/vanilla_classes.txt
		cat <<'EOF'
	];

	static var registered:Bool = false;

	/** Engine classes (the per-tree prefixed families). flixel / openfl do not count. */
	static final ENGINE_PACKAGES:Array<String> = [
		'backend.', 'states.', 'objects.', 'options.', 'substates.', 'psychlua.',
		'shaders.', 'cutscenes.', 'flxanimate.', 'debug.', 'unused.',
		'mobile.', 'hxcodec.', 'vlc.'
	];

	static function isEngineClass(fqn:String):Bool
	{
		for (pkg in ENGINE_PACKAGES)
			if (fqn.indexOf(pkg) == 0) return true;
		return false;
	}

	public static function register():Void
	{
		if (registered) return;
		registered = true;

		// proxyImports is a process-wide static table, first writer wins, and import uses it.
		// Drop entries pointing at the body tree first: a name this table does not cover would
		// otherwise resolve to a body class whose hardcoded Paths pulls assets from assets/body -
		// which holds the 1.0.4 official assets, so it loads fine and returns the wrong image.
		var stale:Array<String> = [];
		for (key in Iris.proxyImports.keys())
		{
			var fqn:String = Type.getClassName(Iris.proxyImports.get(key));
			if (fqn == null || fqn.indexOf('vanilla.') == 0) continue;
			if (isEngineClass(fqn)) stale.push(key);
		}
		for (key in stale)
			Iris.proxyImports.remove(key);

		var simpleCount:Map<String, Int> = [];

		for (fqn in CLASSES)
		{
			var cls:Dynamic = Type.resolveClass('vanilla.' + fqn);
			if (cls == null) continue;
			Iris.proxyImports.set(fqn, cls);

			var simple:String = fqn.split('.').pop();
			simpleCount[simple] = (simpleCount.exists(simple) ? simpleCount[simple] : 0) + 1;
		}

		// simple names are mapped only when unique in this tree, so collisions cannot misdirect
		for (fqn in CLASSES)
		{
			var simple:String = fqn.split('.').pop();
			if (simpleCount[simple] != 1) continue;
			if (Iris.proxyImports.exists(simple)) continue;
			var cls:Dynamic = Type.resolveClass('vanilla.' + fqn);
			if (cls != null) Iris.proxyImports.set(simple, cls);
		}
	}
}
EOF
	} > "$out"
	ok "$out（$n 个类/枚举）"
	cmd_build 0 >/dev/null 2>&1 || warn "表已更新，但编译没通过，自己跑一次 4 号"
	return 0
}

# ---------------------------------------------------------------- Android 构建
# 工具链全在 .workbuddy/toolchain/，不碰系统环境：Gradle 7.4.2 只认 JDK 17，
# NDK 25 的 host 布局老（hxcpp 4.3.2 探测不到，得手传 ANDROID_HOST）。
setup_android_env() {
	local TC="$ROOT/.workbuddy/toolchain"
	export JAVA_HOME="$TC/jdk17"
	export ANDROID_SDK="$TC/android-sdk"
	export ANDROID_NDK_ROOT="$ANDROID_SDK/ndk/25.2.9519653"
	export ANDROID_SETUP=true
	export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/windows-x86_64/bin:$JAVA_HOME/bin:$ANDROID_SDK/platform-tools:$PATH"

	# gradle 走本机代理；JDK 的 cacerts 不认代理证书链，改用 Windows 证书库
	if [ -n "${HTTPS_PROXY:-}" ]; then
		local ph pp
		ph="$(printf '%s' "$HTTPS_PROXY" | sed -E 's#^[a-z]+://([^:/]+).*#\1#')"
		pp="$(printf '%s' "$HTTPS_PROXY" | sed -E 's#.*:([0-9]+)/?$#\1#')"
		export GRADLE_OPTS="${GRADLE_OPTS:-} -Dhttps.proxyHost=$ph -Dhttps.proxyPort=$pp -Dhttp.proxyHost=$ph -Dhttp.proxyPort=$pp"
	fi
	export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djavax.net.ssl.trustStoreType=WINDOWS-ROOT"

	[ -d "$JAVA_HOME" ] || { bad "缺 JDK 17: $JAVA_HOME"; return 1; }
	[ -d "$ANDROID_NDK_ROOT" ] || { bad "缺 NDK: $ANDROID_NDK_ROOT"; return 1; }
	return 0
}

# 把 quickjs-ng 编成 arm64-v8a 静态库。跟 Windows 的 .lib 是两份产物、互不覆盖。
# 用 clang.exe 而非 .cmd：后者在 Git Bash 里要靠 cmd.exe 转一层，带盘符的参数容易被截断。
cmd_qjsandroid() {
	local R SRC OUT NDK TOOLCHAIN CC AR SYSROOT CFLAGS name obj
	R="$ROOT"
	if command -v cygpath >/dev/null 2>&1; then R="$(cygpath -m "$R")"; fi
	SRC="$R/third_party/quickjs-ng"
	OUT="$SRC/build/android-arm64"
	NDK="${PE_ANDROID_NDK:-$R/.workbuddy/toolchain/android-sdk/ndk/25.2.9519653}"
	TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/windows-x86_64"
	CC="$TOOLCHAIN/bin/clang.exe"
	AR="$TOOLCHAIN/bin/llvm-ar.exe"
	SYSROOT="$TOOLCHAIN/sysroot"

	[ -f "$SRC/quickjs.c" ] || { bad "找不到 $SRC/quickjs.c，仓库里的 quickjs-ng 不完整"; return 1; }
	[ -f "$CC" ] || { bad "找不到 clang: $CC（设 PE_ANDROID_NDK 指向已有 NDK）"; return 1; }
	[ -f "$AR" ] || { bad "找不到 llvm-ar: $AR"; return 1; }

	mkdir -p "$OUT"
	CFLAGS=(--target=aarch64-linux-android21 --sysroot="$SYSROOT" -O2 -std=c11 -fPIC -D_GNU_SOURCE -Wno-everything)
	head_ "QuickJS-NG -> android-arm64"
	for name in quickjs libregexp libunicode dtoa; do
		obj="$OUT/$name.o"
		printf '  %s.c\n' "$name"
		MSYS2_ARG_CONV_EXCL='*' "$CC" "${CFLAGS[@]}" -c "$SRC/$name.c" -o "$obj" \
			|| { bad "$name.c 编译失败"; return 1; }
	done
	MSYS2_ARG_CONV_EXCL='*' "$AR" rcs "$OUT/libquickjs-ng.a" \
		"$OUT/quickjs.o" "$OUT/libregexp.o" "$OUT/libunicode.o" "$OUT/dtoa.o" \
		|| { bad "打包静态库失败"; return 1; }
	ok "$OUT/libquickjs-ng.a ($(du -h "$OUT/libquickjs-ng.a" | cut -f1))"
}

cmd_android() {
	setup_android_env || return 1
	local lib="$ROOT/third_party/quickjs-ng/build/android-arm64/libquickjs-ng.a"
	[ -f "$lib" ] || { cmd_qjsandroid || return 1; }
	cd "$ROOT" || return 1
	head_ "构建 android（arm64-v8a）"
	# -Dnostrip：NDK 25 的 bin 只有 llvm-strip.exe，hxcpp 按 ${TOOLCHAIN_PREFIX}strip
	# 找 aarch64-linux-android-strip，链接最后一步会报"不是内部或外部命令"。
	haxelib run lime build android -DANDROID_HOST=windows-x86_64 -Dnostrip
}

# ---------------------------------------------------------------- 回归测试
# 三条测试线都做成子 shell（cmd_xxx() ( ... )）：trap 只在子 shell 退出发，
# 不会挂到 manage.sh 的主进程上；跑完 menu 还能继续用。

cmd_test() (
	local MODE="${PE_BUILD:-release}"
	local BIN="$ROOT/export/$MODE/windows/bin"
	local SONG="${1:-bopeebo}" PY=python
	local ORIG_ENGINE WINROOT GAME_PID f k

	ORIG_ENGINE="$(cat "$BIN/engine.txt" 2>/dev/null || echo body)"

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
		# 只删空目录，mods 里万一有别人的东西不会动
		rmdir "$BIN/mods/body/scripts" "$BIN/mods/body/stages" "$BIN/mods/body/custom_events" "$BIN/mods/body/custom_notetypes" \
		      "$BIN/assets/body/custom_notetypes" "$BIN/assets/body/stages" "$BIN/assets/body/custom_events" 2>/dev/null
		printf '%s' "$ORIG_ENGINE" > "$BIN/engine.txt"
	}
	trap cleanup EXIT

	taskkill //F //IM realQuickJSEngine.exe > /dev/null 2>&1
	sleep 1

	head_ "注入测试入口"
	$PY "$ROOT/.workbuddy/harness/apply_hook.py" on || return 1

	head_ "编译（$MODE）"
	rm -f "$ROOT/.workbuddy/build.log"
	cmd_build 0 > "$ROOT/.workbuddy/build.log" 2>&1 || { tail -25 "$ROOT/.workbuddy/build.log"; return 1; }

	head_ "放测试脚本"
	mkdir -p "$BIN/mods/body/scripts" "$BIN/mods/body/stages" "$BIN/mods/body/custom_events" "$BIN/mods/body/custom_notetypes"
	mkdir -p "$BIN/assets/body/stages" "$BIN/assets/body/custom_notetypes" "$BIN/assets/body/custom_events"
	cp "$ROOT/.workbuddy/luatest/scripts/"*.lua "$BIN/mods/body/scripts/"
	cp "$ROOT/.workbuddy/luatest/scripts/"*.js "$BIN/mods/body/scripts/" 2>/dev/null
	cp "$ROOT/.workbuddy/luatest/scripts/"*.hx "$BIN/mods/body/scripts/" 2>/dev/null
	cp "$ROOT/.workbuddy/luatest/mods/stages/"*.lua "$BIN/mods/body/stages/"
	cp "$ROOT/.workbuddy/luatest/mods/custom_events/"*.lua "$BIN/mods/body/custom_events/"
	# notetype 故意放 assets 根，测 0.6.x 的兜底路径
	cp "$ROOT/.workbuddy/luatest/assets/custom_notetypes/"*.lua "$BIN/assets/body/custom_notetypes/"

	# 脚本里写的是 @@ROOT@@，拷进 bin 换成真实仓库根（游戏是原生程序，要 Windows 风格）
	WINROOT="$(cygpath -m "$ROOT" 2>/dev/null || printf '%s' "$ROOT")"
	for f in "$BIN/mods/body/scripts/"*.lua "$BIN/mods/body/scripts/"*.js \
	         "$BIN/mods/body/stages/"*.lua "$BIN/mods/body/custom_events/"*.lua \
	         "$BIN/assets/body/custom_notetypes/"*.lua; do
		[ -f "$f" ] && sed -i "s|@@ROOT@@|$WINROOT|g" "$f"
	done

	rm -f "$ROOT/.workbuddy/testout/"*.txt
	if [ "${NOPATCH:-0}" = "1" ]; then
		printf '  跳过谱面补丁（用回原始谱面）\n'
		if [ -f "$BIN/assets/body/shared/data/bopeebo/bopeebo.json.orig" ]; then
			cp "$BIN/assets/body/shared/data/bopeebo/bopeebo.json.orig" "$BIN/assets/body/shared/data/bopeebo/bopeebo.json"
		fi
	else
		$PY "$ROOT/.workbuddy/luatest/patch_chart.py" || return 1
	fi

	head_ "开局 $SONG"
	# engine.txt 决定 Main.main() 走哪棵树；测试入口的补丁只在 body 分支上，跑完还原。
	printf 'body' > "$BIN/engine.txt"
	cd "$BIN" || return 1
	# NOMOD：玩家上次选的 mod 会把自己的脚本带进来，报错混进结果
	PE_AUTOTEST="$SONG" PE_AUTOTEST_NOMOD=1 ./realQuickJSEngine.exe > "$ROOT/.workbuddy/game.log" 2>&1 &
	GAME_PID=$!

	for i in $(seq 1 25); do
		sleep 1
		if [ -f "$ROOT/.workbuddy/testout/v073.txt" ] && grep -q "^DONE|v073" "$ROOT/.workbuddy/testout/v073.txt" 2>/dev/null; then
			sleep 9
			break
		fi
	done
	taskkill //F //IM realQuickJSEngine.exe > /dev/null 2>&1
	wait $GAME_PID 2>/dev/null

	head_ "结果"
	for f in "$ROOT/.workbuddy/testout/"*.txt; do
		[ -e "$f" ] || continue
		case "$(basename "$f")" in
			js_seen.txt|callbacks.txt|kind_*) continue ;;
		esac
		printf '%-18s PASS=%-3s FAIL=%s\n' "$(basename "$f")" "$(grep -c '^PASS' "$f")" "$(grep -cE '^(FAIL|ERR)' "$f")"
		grep -E "^(FAIL|ERR)" "$f"
	done

	head_ "stage / notetype / event 脚本"
	for k in stage notetype event; do
		f="$ROOT/.workbuddy/testout/kind_$k.txt"
		if [ -f "$f" ]; then printf '%-10s %s\n' "$k" "$(head -1 "$f")"
		else printf '%-10s 没加载\n' "$k"; fi
	done
)

cmd_qjstest() (
	local MODE="${PE_BUILD:-release}"
	local BIN="$ROOT/export/$MODE/windows/bin"
	local MODS="$BIN/mods/body"
	local SONG="${1:-bopeebo}"
	local OUT="$ROOT/.workbuddy/testout/$$"
	local ORIG_ENGINE WINROOT GAME_PID f fails=0

	cleanup() {
		python "$ROOT/.workbuddy/harness/apply_hook.py" off > /dev/null 2>&1
		rm -f "$MODS/scripts/smoke_a.js" "$MODS/qjstest/qjs_child.js" \
		      "$MODS/qjs_roundtrip.txt" "$MODS/shaders/qjstest.frag"
		rmdir "$MODS/scripts" "$MODS/qjstest" "$MODS/shaders" 2>/dev/null
		printf '%s' "$ORIG_ENGINE" > "$BIN/engine.txt"
		rm -rf "$OUT"
	}
	trap cleanup EXIT

	taskkill //F //IM realQuickJSEngine.exe > /dev/null 2>&1
	sleep 1
	mkdir -p "$OUT"
	rm -f "$BIN/testout/js_log.txt" "$BIN/testout/quickjs_smoke.txt"

	ORIG_ENGINE="$(cat "$BIN/engine.txt" 2>/dev/null || echo body)"
	head_ "注入测试入口"
	python "$ROOT/.workbuddy/harness/apply_hook.py" on || return 1

	head_ "编译（$MODE）"
	rm -f "$ROOT/.workbuddy/build.log"
	cmd_build 0 > "$ROOT/.workbuddy/build.log" 2>&1 || { tail -30 "$ROOT/.workbuddy/build.log"; return 1; }

	head_ "放测试脚本"
	# smoke_a 放 scripts/ 会被开局扫描自动装；qjs_child 放别的目录，只有 smoke_a
	# 调 addLuaScript 才装得进来 —— 这样才真测到「运行时新开一个 context」。
	mkdir -p "$MODS/scripts" "$MODS/qjstest" "$MODS/shaders"
	cp "$ROOT/.workbuddy/luatest/qjs/smoke_a.js" "$MODS/scripts/"
	cp "$ROOT/.workbuddy/luatest/qjs/child/qjs_child.js" "$MODS/qjstest/"
	# 这份 .frag 是从本机能跑的 mod shader 抄的；手写最小 passthrough 编不过 OpenFL 9。
	cp "$ROOT/.workbuddy/luatest/qjs/shaders/"*.frag "$MODS/shaders/" 2>/dev/null
	WINROOT="$(cygpath -m "$ROOT" 2>/dev/null || printf '%s' "$ROOT")"
	for f in "$MODS/scripts/"*.js "$MODS/qjstest/"*.js; do
		[ -f "$f" ] && sed -i "s|@@ROOT@@|$WINROOT|g" "$f"
	done

	printf 'body' > "$BIN/engine.txt"
	head_ "开局 $SONG（jsEngine=QuickJS）"
	cd "$BIN" || return 1
	PE_AUTOTEST="$SONG" PE_AUTOTEST_JSENGINE=QuickJS PE_AUTOTEST_NOMOD=1 ./realQuickJSEngine.exe > "$ROOT/.workbuddy/game_qjs.log" 2>&1 &
	GAME_PID=$!

	# 等到 smoke_a 写完，再多给两秒让「自卸之后那一帧」跑过去
	for i in $(seq 1 40); do
		sleep 1
		if [ -f "$OUT/qjs_smoke.txt" ] && grep -q "^DONE|qjs" "$OUT/qjs_smoke.txt" 2>/dev/null; then
			sleep 2
			break
		fi
	done
	taskkill //F //IM realQuickJSEngine.exe > /dev/null 2>&1
	wait $GAME_PID 2>/dev/null

	# 日志相对 cwd 写在 bin/testout，抄一份到隔离目录留证
	[ -f "$BIN/testout/js_log.txt" ] && cp "$BIN/testout/js_log.txt" "$OUT/qjs_js_log.txt"
	[ -f "$BIN/testout/quickjs_smoke.txt" ] && cp "$BIN/testout/quickjs_smoke.txt" "$OUT/quickjs_smoke.txt"

	head_ "结果"
	if [ ! -f "$OUT/qjs_smoke.txt" ]; then
		printf '  一个结果文件都没有，游戏日志尾巴：\n'
		tail -25 "$ROOT/.workbuddy/game_qjs.log" 2>/dev/null || printf '  (连 game_qjs.log 都没有)\n'
	fi
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

	head_ "链接自检"
	[ -f "$OUT/quickjs_smoke.txt" ] && cat "$OUT/quickjs_smoke.txt" || printf '  quickjs_smoke.txt 没生成\n'
	head_ "js_log.txt"
	[ -f "$OUT/qjs_js_log.txt" ] && cat "$OUT/qjs_js_log.txt" || printf '  js_log.txt 没生成\n'

	rm -f "$ROOT/.workbuddy/qjs_testout_path.txt"
	printf '%s' "$OUT" > "$ROOT/.workbuddy/qjs_testout_path.txt"
	return "$fails"
)

cmd_probe063() (
	local BIN="$ROOT/export/release/windows/bin"
	local ORIG="$(cat "$BIN/engine.txt" 2>/dev/null || echo body)"
	restore() { printf '%s' "$ORIG" > "$BIN/engine.txt"; }
	trap restore EXIT

	taskkill //F //IM realQuickJSEngine.exe > /dev/null 2>&1
	printf 'pe063' > "$BIN/engine.txt"
	cd "$BIN" || return 1
	PE_063_PROBE=1 ./realQuickJSEngine.exe > "$ROOT/.workbuddy/probe_run.log" 2>&1
	printf 'exit=%s\n' "$?"

	head_ "0.6.3 路径探针结果"
	cat "$ROOT/.workbuddy/testout/pe063_probe.txt" 2>/dev/null || printf '  没有结果文件，看 .workbuddy/probe_run.log\n'
)

# ---------------------------------------------------------------- QuickJS-NG
# JS 运行时。源码在 third_party/quickjs-ng（自己 clone 进来的，不自动下载）。
# 只需要三个 .c：这个 fork 把 cutils.c 并进 quickjs.c 了，没有独立的 cutils.c。
# QuickJS-NG：源码已入库（third_party/quickjs-ng），只需要在本机编成静态库。
# 引擎（source_body/body/jsruntime/QuickJSHandler.hx）通过 @:buildXml 链 build/quickjs-ng.lib。
QJS_SRC="$ROOT/third_party/quickjs-ng"
QJS_LIB="$QJS_SRC/build/quickjs-ng.lib"
QJS_SOURCES="quickjs.c libregexp.c libunicode.c dtoa.c"

# 静态库缺失，或任意一个源文件比它新 → 需要重编
quickjs_stale() {
	[ -f "$QJS_LIB" ] || return 0
	local f
	for f in $QJS_SOURCES; do
		[ "$QJS_SRC/$f" -nt "$QJS_LIB" ] && return 0
	done
	return 1
}

# build 之前调用：缺了/旧了就编，已经最新就跳过
ensure_quickjs() {
	if ! [ -f "$QJS_SRC/quickjs.c" ]; then
		bad "third_party/quickjs-ng/quickjs.c 不存在 —— 源码应该随仓库一起来，检查是不是没拉全"
		return 1
	fi
	if quickjs_stale; then
		say "  QuickJS-NG 需要（重新）编译" "  building QuickJS-NG static library"
		cmd_quickjs || return 1
	else
		ok "QuickJS-NG 静态库已是最新（$(du -h "$QJS_LIB" | cut -f1)）"
	fi
	return 0
}

cmd_quickjs() {
	local src="$QJS_SRC"
	head_ "QuickJS-NG 静态库"
	[ -f "$src/quickjs.c" ] || { bad "没有 third_party/quickjs-ng/quickjs.c —— 源码在仓库里，检查拉取是否完整"; return 1; }

	setup_msvc >/dev/null || return 1

	local M
	M="$(cygpath -u "$MSVC_PATH" 2>/dev/null || printf '%s' "$MSVC_PATH")"
	local cl="$M/bin/Hostx64/x64/cl.exe"
	local libtool="$M/bin/Hostx64/x64/lib.exe"
	[ -f "$cl" ] || { bad "找不到 cl.exe：$cl"; return 1; }

	mkdir -p "$src/build"
	echo "  编译 quickjs.c / libregexp.c / libunicode.c …"
	# MSYS 会把 /nologo 这类参数当成路径改写掉，必须关掉参数转换 + 用 - 前缀
	if ! (cd "$src" && MSYS2_ARG_CONV_EXCL='*' "$cl" -nologo -c -O2 -std:c11 -utf-8 -Fo:build\\ quickjs.c libregexp.c libunicode.c dtoa.c >/dev/null 2>&1); then
		bad "编译失败（看上面 MSVC 输出）"
		return 1
	fi
	(cd "$src" && MSYS2_ARG_CONV_EXCL='*' "$libtool" -nologo -OUT:build/quickjs-ng.lib build/quickjs.obj build/libregexp.obj build/libunicode.obj build/dtoa.obj >/dev/null 2>&1) \
		|| { bad "打包 .lib 失败"; return 1; }

	ok "third_party/quickjs-ng/build/quickjs-ng.lib（$(du -h "$src/build/quickjs-ng.lib" | cut -f1)）"
	return 0
}

# ---------------------------------------------------------------- 兼容审计
# 只比函数名（add_callback 注册的那些），够看出「上游有、我们没有」
collect_lua_funcs() {
	grep -rhoE 'add_callback\(lua,[[:space:]]*"[^"]+"' "$1" 2>/dev/null |
		sed -e 's/^[^"]*"//' -e 's/"$//' | LC_ALL=C sort -u
}

cmd_audit() {
	head_ "Lua / HScript 兼容审计（函数名级）"
	local ref
	printf '  基准树：\n'
	printf '    1) D:/FNF/PE063-ref/source\n'
	printf '    2) D:/FNF/PE073-ref/source\n'
	printf '    3) 手输路径\n'
	printf '  > '
	read -r ref || return 0
	case "$ref" in
		1) ref="D:/FNF/PE063-ref/source" ;;
		2) ref="D:/FNF/PE073-ref/source" ;;
		3) printf '  path> '; read -r ref ;;
	esac
	[ -d "$ref" ] || { bad "目录不存在：$ref"; return 1; }

	collect_lua_funcs "$ref" > .cache/ref.txt
	collect_lua_funcs "source" > .cache/ours.txt
	local a b
	a=$(wc -l < .cache/ref.txt); b=$(wc -l < .cache/ours.txt)
	ok "基准 $a 个 / 我们 $b 个"

	LC_ALL=C comm -23 .cache/ref.txt .cache/ours.txt > .cache/lack.txt
	LC_ALL=C comm -13 .cache/ref.txt .cache/ours.txt > .cache/extra.txt
	printf '\n  上游有、我们没有（%s）：\n' "$(wc -l < .cache/lack.txt)"
	sed 's/^/    /' .cache/lack.txt
	printf '\n  我们有、上游没有（%s）：\n' "$(wc -l < .cache/extra.txt)"
	sed 's/^/    /' .cache/extra.txt | head -40
	printf '\n  报告写到 .cache/compat_report.md\n'
	{
		echo "# Lua API 兼容审计（基准：$ref）"
		echo
		echo "- 基准函数：$a"
		echo "- 本仓函数：$b"
		echo
		echo "## 上游有、本仓没有"
		echo
		sed 's/^/- `&`/' .cache/lack.txt
		echo
		echo "## 本仓独有"
		echo
		sed 's/^/- `&`/' .cache/extra.txt
	} > .cache/compat_report.md
	[ -s .cache/lack.txt ] && return 1 || return 0
}

# ---------------------------------------------------------------- 菜单
choose_language() {
	printf '\n  选择语言 / Select language\n    1) 中文\n    2) English\n\n  > '
	local pick
	read -r pick || exit 0
	case "$pick" in 2|en|EN|English|english) L=en ;; *) L=zh ;; esac
}

print_menu() {
	printf '\n==============================================================\n'
	say "  FNF-PE RealQuickJS 工具箱" "  FNF-PE RealQuickJS Toolbox"
	printf '==============================================================\n\n'
	if [ "$L" = "en" ]; then
		printf '  1)  Environment check    haxe / libs / MSVC / SDK / rc.exe, auto-repairs libs\n'
		printf '  2)  Build release        incremental, then copy+verify assets\n'
		printf '  3)  Build debug          same, -debug\n'
		printf '  4)  Clean rebuild        wipe obj/src first, then build\n'
		printf '  5)  Prepare assets       copy assets/base_game into bin, verify\n'
		printf '  6)  Verify assets only   report missing bits, touch nothing\n'
		printf '  7)  Lua compat audit     function-name diff against an upstream tree\n'
		printf '  8)  Rebuild import table regenerate the vanilla HScript import map\n'
		printf '  9)  Build QuickJS-NG     rebuild the JS runtime static library (build does it too)\n'
		printf ' 10)  Lua regression      inject entry, build, run a song, collect results\n'
		printf ' 11)  QuickJS regression  same but through the real QuickJS runtime\n'
		printf ' 12)  0.6.3 path probe    no game state, just Paths / atlas check\n'
		printf ' 13)  Android build       arm64-v8a apk (toolchain in .workbuddy/toolchain)\n'
		printf ' 14)  Android QuickJS     build libquickjs-ng.a for arm64\n'
		printf '  0)  Quit\n'
	else
		printf '  1)  环境体检       Haxe / 库 / MSVC / SDK / rc.exe，缺库自动补\n'
		printf '  2)  编译 release   增量编译，编完自动铺素材并校验\n'
		printf '  3)  编译 debug     同上，debug 模式\n'
		printf '  4)  全量重编       先清 obj/src 再编（改 Project.xml、换库之后用）\n'
		printf '  5)  铺素材         把 assets/base_game 铺进 bin 并校验\n'
		printf '  6)  只校验资产     不动文件，只报缺什么（发版前跑）\n'
		printf '  7)  Lua 兼容审计   拿上游源码树当基准，比 add_callback 注册的函数名\n'
		printf '  8)  重建 import 表 扫 source_vanilla 重生成 HScript 的 import 隔离表\n'
		printf '  9)  重建 QuickJS-NG  强制重编 JS 运行时静态库（平时编译会自动做）\n'
		printf ' 10)  Lua 回归       注入入口 → 编译 → 开局 → 收结果 → 撤入口\n'
		printf ' 11)  QuickJS 回归   同上，走真 QuickJS 运行时\n'
		printf ' 12)  0.6.3 路径探针 不进游戏，只验 Paths / 图集\n'
		printf ' 13)  安卓构建       arm64-v8a 包（工具链在 .workbuddy/toolchain）\n'
		printf ' 14)  Android QuickJS 编 arm64 的 libquickjs-ng.a\n'
		printf '  0)  退出\n'
	fi
	printf '\n  > '
}

run_action() {
	# shift 掉动作本身，剩下的参数透传给测试函数（歌名）
	local act="$1"; shift
	case "$act" in
		1|env)         cmd_env ;;
		2|release)     MODE=release; cmd_build 0 ;;
		3|debug)       MODE=debug;   cmd_build 0 ;;
		4|clean)       MODE=release; cmd_build 1 ;;
		5|assets)      cmd_assets 0 ;;
		6|verify)      cmd_assets 1 ;;
		7|audit)       cmd_audit ;;
		8|imports)     cmd_imports ;;
		9|quickjs)     cmd_quickjs ;;
		10|test)       cmd_test "$@" ;;
		11|qjstest)    cmd_qjstest "$@" ;;
		12|probe063)   cmd_probe063 ;;
		13|android)    cmd_android ;;
		14|qjsandroid) cmd_qjsandroid ;;
		0|q|Q)         return 99 ;;
		*)             say "  没有这个编号" "  no such item"; return 2 ;;
	esac
}

if [ -z "$L" ]; then choose_language; fi
if [ -n "$ACTION" ]; then
	run_action "$ACTION" "${EXTRA[@]}"
	rc=$?
	# 只在被 conhost 包着的那层里有意义：把真退出码带出去
	if [ -n "${PE_BUILD_STATUS:-}" ]; then printf '%s' "$rc" > "$PE_BUILD_STATUS"; fi
	exit "$rc"
fi

while true; do
	print_menu
	read -r choice || exit 0
	printf '\n'
	run_action "$choice"; rc=$?
	[ "$rc" -eq 99 ] && exit 0
	printf '\n'
	say "  回车继续…" "  press enter to continue…"
	read -r _ || true
done
