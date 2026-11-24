#!/usr/bin/env bash
# ============================================================================
#  FNF-PE RealQuickJS —— 唯一的脚本。
#
#  环境体检 / 补库 / 编译 / 铺素材 / 资产校验 / Lua 兼容审计 / vanilla import 表生成 /
#  QuickJS 静态库，全在这里，不互相调用。自动回归已删，验收靠手动进歌。
#  带动作调用时自己裹 conhost --headless，无控制台也不弹窗。
#
#  用法：
#    bash manage.sh                 交互式：先选语言，再选功能
#    bash manage.sh --zh            跳过语言选择
#    bash manage.sh --en 2          直接跑 2 号功能（CI / 快捷方式）
#    bash manage.sh --zh build debug    带参数跳过二级询问
#    bash manage.sh --zh release    名字别名也行（编号重排也不受影响）
#
#  Windows 双击 manage.bat；它只负责找到 bash 然后转给这里（batch 干不了
#  HAHA/awk/硬链接这些活）。
# ============================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

usage() {
	cat <<'EOF'
FNF-PE RealQuickJS 工具箱

  bash manage.sh                 交互式菜单
  bash manage.sh --zh            菜单，中文
  bash manage.sh --en            菜单，English
  bash manage.sh --zh 2          直接跑功能 2
  bash manage.sh --zh release    名字别名（编号变了也不失效）
  bash manage.sh --zh build debug    带参数跳过二级询问
  bash manage.sh --zh audit 1    审计选基准：1=0.6.3 / 2=0.7.3 / 直接给路径
EOF
}

# PE_BUILD=debug 让默认构建走 debug，命令行 build debug / release 仍然覆盖它
MODE="${PE_BUILD:-release}"
L=""
ACTION=""
EXTRA=()

for arg in "$@"; do
	case "$arg" in
		--zh|zh) L=zh ;;
		--en|en) L=en ;;
		# release/debug 交给下面的 * 当动作名处理，别在这里截成 MODE，
		# 否则 ACTION 为空、直接掉进交互菜单
		-h|--help|-help) usage; exit 0 ;;
		# 第一个位置参数是动作，后面的是它的参数（如 build debug）
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
bad()  { if [ "$L" = en ]; then printf '  miss  %s\n' "$*"; else printf '  缺失  %s\n' "$*"; fi; BAD=$((BAD + 1)); }
warn() { if [ "$L" = en ]; then printf '  note  %s\n' "$*"; else printf '  注意  %s\n' "$*"; fi; }
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
	# HAXE_DIR 指 haxe.exe 所在目录（或 haxe 可执行文件本身）；换机器只设这一个变量。
	# 后面是常见默认安装位置，用 /c /d 这些 Git Bash 挂载点，不绑定某个盘上的项目路径。
	for cand in \
		"${HAXE_DIR:-}" \
		"${HAXE_DIR:-}/haxe.exe" \
		/c/Haxe/*/haxe/haxe.exe /c/Haxe/haxe.exe /c/haxe/haxe.exe \
		/d/Haxe/*/haxe/haxe.exe "$ROOT/.haxe/haxe.exe"; do
		[ -n "$cand" ] && [ -f "$cand" ] && { HY_BIN="$cand"; return 0; }
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
	# 标准安装位置（Program Files）本身是 Windows 约定，可移植；不再写死某个盘上的自建路径。
	# 自建 / 精简版 VS 用 MSVC_DIR 环境变量指过来。
	for base in \
		"C:/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2022/Professional/VC/Tools/MSVC" \
		"C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Tools/MSVC" \
		"C:/Program Files/Microsoft Visual Studio/2019/BuildTools/VC/Tools/MSVC"; do
		[ -d "$base" ] || continue
		ver="$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)"
		[ -n "$ver" ] && { printf '%s' "$base/$ver"; return; }
	done
	# 精简版 / 自建 VS 常散在各盘根目录（VS2019/BuildTools、vs/program 等）。
	# 遍历盘符 + 常见子目录，不绑定具体盘号。
	local drive sub
	for drive in c d e f g; do
		for sub in VS2019/BuildTools vs/program VS2022/BuildTools VisualStudio/BuildTools; do
			base="/$drive/$sub/VC/Tools/MSVC"
			[ -d "$base" ] || continue
			ver="$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)"
			[ -n "$ver" ] && { printf '%s' "$base/$ver"; return; }
		done
	done
}

pick_sdk() {
	local base drive
	# SDK_DIR 覆盖；没设就按标准位置找，再遍历各盘符（换机器不用改脚本）。
	for base in "${SDK_DIR:-}" \
		"C:/Program Files (x86)/Windows Kits/10" "C:/Program Files/Windows Kits/10"; do
		[ -n "$base" ] && [ -d "$base/Include" ] && { printf '%s' "$base"; return; }
	done
	for drive in c d e f g h; do
		base="/$drive/Windows Kits/10"
		[ -d "$base/Include" ] && { printf '%s' "$base"; return; }
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
	# INCLUDE/LIB 是给 cl.exe 自己解析的，得是 Windows 路径；PATH 则要 POSIX（git-bash 用冒号分隔）。
	MSVC_WIN="$(cygpath -m "$MSVC_PATH" 2>/dev/null || printf '%s' "$MSVC_PATH")"
	SDK_WIN="$(cygpath -m "$SDK_BASE" 2>/dev/null || printf '%s' "$SDK_BASE")"
	export INCLUDE="$MSVC_WIN/include;$SDK_WIN/Include/$SDK_VER/ucrt;$SDK_WIN/Include/$SDK_VER/shared;$SDK_WIN/Include/$SDK_VER/um;$SDK_WIN/Include/$SDK_VER/winrt"
	export LIB="$MSVC_WIN/lib/x64;$SDK_WIN/Lib/$SDK_VER/ucrt/x64;$SDK_WIN/Lib/$SDK_VER/um/x64"
	ok "MSVC $MSVC_PATH"
	ok "SDK  $SDK_VER"
	return 0
}

cmd_env() {
	BAD=0
	setup_toolchain || true
	if [ -n "${HAXELIB_PATH:-}" ]; then
		# 体检顺便修：缺库就直接装/切，补完复查一遍。补库要网络，失败只告警不中断。
		if ! check_libs; then
			say "  库不全，自动补齐（要网络）…" "  libraries incomplete, repairing (needs network)..."
			if fix_libs; then
				head_ "复查 haxelib 依赖"
				check_libs || true
			else
				warn "自动补库失败，检查网络，或手动装 git 源的库"
			fi
		fi
	fi
	setup_msvc || true
	head_ "其它"
	if command -v rc.exe >/dev/null 2>&1; then
		ok "rc.exe"
	elif [ -n "${SDK_BASE:-}" ] && [ -n "${SDK_VER:-}" ] && [ -f "$SDK_BASE/bin/$SDK_VER/x64/rc.exe" ]; then
		ok "rc.exe"
	else
		warn "rc.exe 不在 PATH（lime 8.3+ 编资源要用）"
	fi
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
	[ "$BAD" -eq 0 ] && return 0 || return 1
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
	# hxcpp 默认按核心数并发（这台 8 个）。多个 cl.exe 同时发现预编译头还没生成时会互相
	# 死等，表现是 haxe 退出、cl 挂着 CPU 0.01s 十几分钟不动（2026-11 撞了 4 次）。
	# 压到 2 线程就没事，单个 cl 只慢一点。PE_COMPILE_THREADS 可以临时调。
	args+=(-D "HXCPP_COMPILE_THREADS=${PE_COMPILE_THREADS:-2}")
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
	local check="${1:-0}" BIN="$ROOT/export/$MODE/windows/bin" TMP="$ROOT/.cache/manage"
	mkdir -p "$TMP"
	BAD=0

	[ -d "$BIN" ] || { say "没有 $BIN，先编译" "no $BIN, build first"; return 1; }

	head_ "素材（源：assets/<版本>）"
	if [ "$check" = 1 ]; then
		printf '  只校验，不铺\n'
	else
		# 三棵树的素材各自完整（2026-11-23 把 base_game 拆进去了），直接铺，不用再拼
		for ver in body 1.0.4 0.6.3; do
			[ -d "$ROOT/assets/$ver" ] || continue
			copy_tree "$ROOT/assets/$ver" "$BIN/assets/$ver" "$ver"
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
	local ver missing
	for ver in body 1.0.4 0.6.3; do
		# embed/ 是 embed="true" 打进 exe 的，preload/ 在 Project.xml 里 rename 到版本根，
		# 这两个目录本来就不会以原路径出现在 bin/assets 下
		file_list "$ROOT/assets/$ver" ! -name "$AUDIO_SKIP" \
			! -path './embed/*' ! -path './preload/*' ! -path './secrets/*' \
			! -path './translations/*' ! -path './week_assets/*' > "$TMP/base.txt"
		file_list "$BIN/assets/$ver" > "$TMP/bin.txt"
		LC_ALL=C comm -23 "$TMP/base.txt" "$TMP/bin.txt" > "$TMP/miss.txt"
		missing=$(wc -l < "$TMP/miss.txt")
		if [ "$missing" -eq 0 ]; then
			ok "assets/$ver 已铺全（$(wc -l < "$TMP/bin.txt") 个文件）"
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

// hscript-iris checks proxyImports before Type.resolveClass, and all trees share FQNs.
// Generated by manage.sh option 8. The guard + isEngineClass() below are part of the
// template - regenerating without them puts cross-tree resolution back.
class IsolatedImports
{
	public static var CLASSES:Array<String> = [
EOF
		sed 's/.*/\t\t'"'"'&'"'"',/' .cache/vanilla_classes.txt
		cat <<'EOF'
	];

	static var registered:Bool = false;

	// other tree? shared list decides
	static function isEngineClass(fqn:String):Bool
	{
		return backend.ScriptConstants.isEngineClass(fqn);
	}

	public static function register():Void
	{
		if (registered) return;
		registered = true;

		// proxyImports is global, first writer wins. Drop body entries before ours go in,
		// or a name we miss still loads textures from assets/body.
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

		// short names only when unique here
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
	say "  表更新了，重新编译才会生效（跑 2 号）" "  table updated; rebuild (item 2) to pick it up"
	return 0
}

QJS_SRC="$ROOT/third_party/quickjs-ng"
QJS_LIB="$QJS_SRC/build/quickjs-ng.lib"
QJS_SOURCES="quickjs.c libregexp.c libunicode.c dtoa.c"

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

	mkdir -p "$src/build" "$ROOT/.cache"
	echo "  编译 quickjs.c / libregexp.c / libunicode.c …"
	# MSYS 会把 /nologo 这类参数当成路径改写掉，必须关掉参数转换 + 用 - 前缀
	# cl 的输出留进 .cache，失败时把末尾打出来，别吞掉报错
	if ! (cd "$src" && MSYS2_ARG_CONV_EXCL='*' "$cl" -nologo -c -O2 -std:c11 -utf-8 -Fo:build\\ quickjs.c libregexp.c libunicode.c dtoa.c >"$ROOT/.cache/quickjs-cl.log" 2>&1); then
		tail -20 "$ROOT/.cache/quickjs-cl.log"
		bad "编译失败（完整输出 .cache/quickjs-cl.log）"
		return 1
	fi
	if ! (cd "$src" && MSYS2_ARG_CONV_EXCL='*' "$libtool" -nologo -OUT:build/quickjs-ng.lib build/quickjs.obj build/libregexp.obj build/libunicode.obj build/dtoa.obj >"$ROOT/.cache/quickjs-lib.log" 2>&1); then
		tail -20 "$ROOT/.cache/quickjs-lib.log"
		bad "打包 .lib 失败（完整输出 .cache/quickjs-lib.log）"
		return 1
	fi

	ok "third_party/quickjs-ng/build/quickjs-ng.lib（$(du -h "$src/build/quickjs-ng.lib" | cut -f1)）"
	return 0
}

# ---------------------------------------------------------------- 兼容审计
# 只比函数名（add_callback / addLocalCallback 注册的那些），够看出「上游有、我们没有」
collect_lua_funcs() {
	# body 树有些回调走 addLocalCallback；0.6.3 参照里有几段整块注释掉的注册。
	# 两种都不剥掉就会误报缺失，所以先去注释再比。
	find "$1" -name '*.hx' -print0 2>/dev/null | xargs -0 -r awk '
		FNR == 1 { blk = 0 }
		/^[ \t]*\/\// { next }
		/\/\*/ { blk = 1 }
		!blk { print }
		/\*\// { blk = 0 }
	' 2>/dev/null |
		grep -oE '(add_callback\(lua,|addLocalCallback\()[[:space:]]*"[^"]+"' |
		sed -e 's/^[^"]*"//' -e 's/"$//' | LC_ALL=C sort -u
}

cmd_audit() {
	head_ "Lua / HScript 兼容审计（函数名级）"
	# 上游参照默认用仓库内的 .workbuddy/upstream/；换机器可用 PE_REF063 / PE_REF073
	# 指到任意检出目录，不用改脚本。带参数或 PE_REF 时不读 stdin，headless 才不会
	# 卡在 read 上然后静默返回 0。
	local ref063="${PE_REF063:-$ROOT/.workbuddy/upstream/pe063/source}"
	local ref073="${PE_REF073:-$ROOT/.workbuddy/upstream/pe073/source}"
	local ref="${1:-${PE_REF:-}}"
	if [ -z "$ref" ] && [ ! -t 0 ]; then ref=1; fi
	if [ -z "$ref" ]; then
		printf '  基准树：\n'
		printf '    1) %s\n' "$ref063"
		printf '    2) %s\n' "$ref073"
		printf '    3) 手输路径\n'
		printf '  > '
		read -r ref || return 0
	fi
	case "$ref" in
		1) ref="$ref063" ;;
		2) ref="$ref073" ;;
		3) printf '  path> '; read -r ref || return 0 ;;
	esac
	[ -d "$ref" ] || { bad "目录不存在：$ref"; return 1; }

	mkdir -p .cache
	collect_lua_funcs "$ref" > .cache/ref.txt
	# 回调注册全在 body 树（source/ 是公共层，一个 add_callback 都没有）
	collect_lua_funcs "source_body" > .cache/ours.txt
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
		printf '  1)  Environment check\n'
		printf '  2)  Build                release / debug / clean (sub-menu)\n'
		printf '  3)  Assets              copy+verify / verify only (sub-menu)\n'
		printf '  4)  Lua compat audit    function-name diff against an upstream tree\n'
		printf '  5)  Rebuild import map  regenerate the vanilla HScript import table\n'
		printf '  6)  QuickJS library     Windows\n'
		printf '  0)  Quit\n'
		printf '\n  Names also work: release debug clean verify audit imports quickjs\n'
	else
		printf '  1)  环境体检       桌面\n'
		printf '  2)  编译           release / debug / 全量重编（二级菜单）\n'
		printf '  3)  素材           铺+校验 / 只校验（二级菜单）\n'
		printf '  4)  Lua 兼容审计   拿上游源码树当基准，比 add_callback 注册的函数名\n'
		printf '  5)  重建 import 表 扫 source_vanilla 重生成 HScript 的 import 隔离表\n'
		printf '  6)  QuickJS 静态库 Windows\n'
		printf '  0)  退出\n'
		printf '\n  名字也能用：release debug clean verify audit imports quickjs\n'
	fi
	printf '\n  > '
}

# 二级选择：合并项在交互菜单里再问一次模式。回车走默认项。
ask_sub() {
	local prompt="$1" default="$2" pick
	printf '%s' "$prompt"
	read -r pick || pick=""
	[ -z "$pick" ] && pick="$default"
	printf '%s' "$pick"
}

# 统一命令（带子参数跳过二级询问）和菜单编号都落到这里。
# 编号连续 1-6；名字别名是稳定接口，改编号不影响老脚本。
run_action() {
	local act="$1"; shift
	case "$act" in
		# ---- 带参数直接用，不带参数才进二级询问 ———
		env) cmd_env ;;
		build)
			local mode="${1:-}"
			[ -z "$mode" ] && mode="$(ask_sub "  编译模式 [1]release / [2]debug / [3]全量重编（回车=release）: " 1)"
			case "$mode" in
				2|debug) MODE=debug;   cmd_build 0 ;;
				3|clean) MODE=release; cmd_build 1 ;;
				*)       MODE=release; cmd_build 0 ;;
			esac ;;
		assets)
			local how="${1:-}"
			[ -z "$how" ] && how="$(ask_sub "  素材 [1]铺+校验 / [2]只校验（回车=铺+校验）: " 1)"
			[ "$how" = 2 ] && cmd_assets 1 || cmd_assets 0 ;;
		quickjs)
			cmd_quickjs ;;

		# ---- 菜单编号 ———
		1) run_action env ;;
		2) run_action build ;;
		3) run_action assets ;;
		4) cmd_audit "${1:-}" ;;
		5|imports)  cmd_imports ;;
		6) run_action quickjs ;;

		# ---- 名字别名 ———
		release)     MODE=release; cmd_build 0 ;;
		debug)       MODE=debug;   cmd_build 0 ;;
		clean)       MODE=release; cmd_build 1 ;;
		verify)      cmd_assets 1 ;;
		assets-full) cmd_assets 0 ;;
		quickjs-win) cmd_quickjs ;;
		audit)       cmd_audit "${1:-}" ;;
		help)        usage ;;
		0|q|Q)       return 99 ;;
		*)           say "  没有这个编号" "  no such item"; return 2 ;;
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
