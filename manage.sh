#!/usr/bin/env bash
# ============================================================================
#  FNF-PE RealQuickJS —— 唯一的脚本。
#
#  以前散在 building/ 和 tools/ 里的东西（环境体检 / 补库 / 编译 / 铺素材 /
#  资产校验 / Lua 兼容审计 / vanilla import 表生成）全部并进来了，不再互相调用。
#
#  用法：
#    bash manage.sh                 交互式：先选语言，再选功能
#    bash manage.sh --zh            跳过语言选择
#    bash manage.sh --en 4          直接跑 4 号功能（CI / 快捷方式）
#    bash manage.sh --zh assets     按名字跑（见下面 case）
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

for arg in "$@"; do
	case "$arg" in
		--zh|zh) L=zh ;;
		--en|en) L=en ;;
		release|debug) MODE="$arg" ;;
		-h|--help|-help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) ACTION="$arg" ;;
	esac
done

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
			bad "$name（未安装，期望 $ver）"; missing=$((missing + 1)); continue
		fi
		if [ "$ver" = "git" ]; then
			ok "$name (git)"
		elif [ "$cur" = "$ver" ]; then
			ok "$name $cur"
		else
			warn "$name 版本是 $cur，清单写的是 $ver"
		fi
	done <<EOF
$LIBS
EOF
	[ "$missing" -eq 0 ] && return 0 || return 1
}

fix_libs() {
	setup_toolchain || return 1
	head_ "补齐 haxelib 库（要网络）"
	local name ver cur
	while read -r name ver; do
		[ -z "${name:-}" ] && continue
		[ "$name" = "haxe" ] || [ "$ver" = "git" ] && continue
		cur=""
		[ -f "$(lib_path "$name")" ] && cur="$(tr -d '\r\n' < "$(lib_path "$name")" | tr ',' '.')"
		if [ -z "$cur" ]; then
			echo "  装 $name $ver"
			haxelib install "$name" "$ver" --always >/dev/null 2>&1 || warn "$name 装失败"
		elif [ "$cur" != "$ver" ]; then
			echo "  切 $name -> $ver（当前 $cur）"
			haxelib set "$name" "$ver" >/dev/null 2>&1 || warn "$name 切换失败"
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
			ver="$(ls -1 "$base/VC/Tools/MSVC" 2>/dev/null | sort -V | tail -1)"
			[ -n "$ver" ] && { printf '%s' "$base/VC/Tools/MSVC/$ver"; return; }
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
	if [ -n "${HAXELIB_PATH:-}" ]; then check_libs || warn "库不全，跑「补/修依赖库」"; fi
	setup_msvc || true
	head_ "其它"
	command -v rc.exe >/dev/null 2>&1 || [ -f "$SDK_BASE/bin/$SDK_VER/x64/rc.exe" ] \
		&& ok "rc.exe" || warn "rc.exe 不在 PATH（lime 8.3+ 编资源要用）"
	command -v python >/dev/null 2>&1 && ok "python" || warn "没有 python（只影响审计功能）"
	printf '\n'
	[ "$BAD" -eq 0 ] && say "环境完整。" "Environment looks fine." || say "有 $BAD 项缺失。" "$BAD problem(s)."
	return $([ "$BAD" -eq 0 ] && echo 0 || echo 1)
}

# ---------------------------------------------------------------- 编译
cmd_build() {
	local clean="${1:-0}" args
	setup_toolchain || return 1
	check_libs || { say "依赖不齐，先跑 3 号补库" "dependencies missing, run item 3 first"; return 1; }
	setup_msvc || return 1

	if tasklist //FI "IMAGENAME eq PsychEngine.exe" 2>/dev/null | grep -qi psychengine; then
		say "  游戏在跑，先关掉" "  game is running, closing it"
		taskkill //F //IM PsychEngine.exe >/dev/null 2>&1
		sleep 1
	fi
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
	fi

	head_ "运行期目录"
	if [ "$check" = 0 ]; then
		for d in body 1.0.4 0.6.3 global; do mkdir -p "$BIN/mods/$d"; done
		[ -f "$BIN/engine.txt" ] || printf 'body' > "$BIN/engine.txt"
	fi
	for d in body 1.0.4 0.6.3 global; do [ -d "$BIN/mods/$d" ] && ok "mods/$d" || bad "mods/$d 不存在"; done
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
 * vanilla 树的 import 隔离表。
 *
 * 三棵树编在一个 exe 里，`import backend.ClientPrefs` 和本体的全名一字不差，
 * 而 hscript-iris 解析 import 时先查 Iris.proxyImports、再落到 Type.resolveClass ——
 * 后者会命中**本体**的类。所以跑脚本之前先把这张表灌进 proxyImports。
 *
 * 由仓库根目录的 manage.sh（功能 10）扫描本目录生成，别手改。
 */
class IsolatedImports
{
	public static var CLASSES:Array<String> = [
EOF
		sed 's/.*/\t\t'"'"'&'"'"',/' .cache/vanilla_classes.txt
		cat <<'EOF'
	];

	static var registered:Bool = false;

	public static function register():Void
	{
		if (registered) return;
		registered = true;

		var simpleCount:Map<String, Int> = [];

		for (fqn in CLASSES)
		{
			var cls:Dynamic = Type.resolveClass('vanilla.' + fqn);
			if (cls == null) continue;
			Iris.proxyImports.set(fqn, cls);

			var simple:String = fqn.split('.').pop();
			simpleCount[simple] = (simpleCount.exists(simple) ? simpleCount[simple] : 0) + 1;
		}

		// 简单名只在这棵树里唯一时才映射，避免撞名指错
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


# ---------------------------------------------------------------- QuickJS-NG
# JS 运行时。源码在 third_party/quickjs-ng（自己 clone 进来的，不自动下载）。
# 只需要三个 .c：这个 fork 把 cutils.c 并进 quickjs.c 了，没有独立的 cutils.c。
cmd_quickjs() {
	local src="$ROOT/third_party/quickjs-ng"
	head_ "QuickJS-NG 静态库"
	[ -f "$src/quickjs.c" ] || { bad "没有 third_party/quickjs-ng/quickjs.c（先 clone 源码）"; return 1; }

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
		printf '  1)  Environment check    haxe / libs / MSVC / SDK / rc.exe, read-only\n'
		printf '  2)  Build release        incremental, then copy+verify assets\n'
		printf '  3)  Build debug          same, -debug\n'
		printf '  4)  Clean rebuild        wipe obj/src first, then build\n'
		printf '  5)  Prepare assets       copy assets/base_game into bin, verify\n'
		printf '  6)  Verify assets only   report missing bits, touch nothing\n'
		printf '  7)  Repair libraries     haxelib install/set whatever is missing\n'
		printf '  8)  Lua compat audit     function-name diff against an upstream tree\n'
		printf '  9)  Rebuild import table regenerate the vanilla HScript import map\n'
		printf ' 10)  Build QuickJS-NG     compile the JS runtime static library\n'
		printf '  0)  Quit\n'
	else
		printf '  1)  环境体检       Haxe / 库 / MSVC / SDK / rc.exe，只读不改\n'
		printf '  2)  编译 release   增量编译，编完自动铺素材并校验\n'
		printf '  3)  编译 debug     同上，debug 模式\n'
		printf '  4)  全量重编       先清 obj/src 再编（改 Project.xml、换库之后用）\n'
		printf '  5)  铺素材         把 assets/base_game 铺进 bin 并校验\n'
		printf '  6)  只校验资产     不动文件，只报缺什么（发版前跑）\n'
		printf '  7)  补/修依赖库    缺哪个 haxelib 库就装/切哪个（要网络）\n'
		printf '  8)  Lua 兼容审计   拿上游源码树当基准，比 add_callback 注册的函数名\n'
		printf '  9)  重建 import 表 扫 source_vanilla 重生成 HScript 的 import 隔离表\n'
		printf ' 10)  构建 QuickJS-NG 把 JS 运行时编成静态库（third_party/quickjs-ng）\n'
		printf '  0)  退出\n'
	fi
	printf '\n  > '
}

run_action() {
	case "$1" in
		1|env)      cmd_env ;;
		2|release)  MODE=release; cmd_build 0 ;;
		3|debug)    MODE=debug;   cmd_build 0 ;;
		4|clean)    MODE=release; cmd_build 1 ;;
		5|assets)   cmd_assets 0 ;;
		6|verify)   cmd_assets 1 ;;
		7|libs)     fix_libs ;;
		8|audit)    cmd_audit ;;
		9|imports)  cmd_imports ;;
		10|quickjs) cmd_quickjs ;;
		0|q|Q)      return 99 ;;
		*)          say "  没有这个编号" "  no such item"; return 2 ;;
	esac
}

if [ -z "$L" ]; then choose_language; fi
[ -n "$ACTION" ] && { run_action "$ACTION"; exit $?; }

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
