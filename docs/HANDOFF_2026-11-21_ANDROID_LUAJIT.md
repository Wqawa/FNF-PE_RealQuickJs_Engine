# 交接文档 — 2026-11-21 安卓线（移动端交互 + LuaJIT 崩溃调查）

> 上一份主文档：`docs/AI_HANDOFF.md`（2026-11-17）。这份只覆盖 **2026-11-21 这一天** 的安卓工作，
> 以及一件**没修完、下次接着干**的事：mod 歌 / Lua 自检在真机上 SIGSEGV。
> 逐项改动清单在 `docs/ANDROID_TODO.md` 的「2026-11-21 这一轮改了什么」小节。

## 0. 一句话现状

- 安卓包能编、能装、基础歌能打；**mod 歌一进就崩**（崩在 LuaJIT 里），崩点已经定位到 `lj_str_new`。
- 为了让崩溃可查，新增了两个基础设施：`backend.DebugLog`（写设备上的 `debug.log`）和
  「apk 内 assets 懒解压到工作目录」（`Paths.localAsset`）。
- 已自建一份干净的 `libluajit-64.a`（绕开 haxelib 里那份来路不明的安卓预编译库），
  但**换了库仍然崩**，所以问题不在库本身（证据见 §4）。

## 1. 今天做掉的事（都已编译通过）

| 项 | 落点 | 状态 |
|---|---|---|
| 歌内暂停键点不到 | `source_body/body/states/PlayState.hx`：新增 `camPause` 相机（bgColor.alpha=0，加在 camOther 之后），歌内 pad / pauseButton / pauseIcon 全挂 `camPause`；判定从 `FlxG.mouse.overlaps(pauseButton)` 改成带相机参数 | 已编，待实机验 |
| 手机按键布局进歌几帧后才归位 | `backend/MusicBeatSubstate.hx` 加 `hideParentPad`；`backend/CustomFadeTransition.hx` 里 `addMenuPad=false; hideParentPad=false`（过场黑幕不再把父界面 pad 藏掉、不再重挂一套默认布局 pad） | 已编，待实机验 |
| weekend1 音响不随节拍跳 | `Project.xml` 把 `grig.audio` / `funkin.vis` 从 `officialBuild` 段挪出、改 `#if desktop \|\| android` 并补 `<define name="funkin.vis"/>`（**以前这个 define 从没存在过**，所以 `#if funkin.vis` 永远走 false）；`states/stages/objects/ABotSpeaker.hx` 拆成 `updateFromAnalyzer()` + `updateFromBeat()` 节拍兜底，加 `audioSourceOf()` 空守卫 | 已编，待实机验 |
| apk 内资源在安卓上「找不到」 | `backend/Paths.hx:646 localAsset()`：磁盘有就用绝对的，否则从 apk 取字节落到 cwd 同名路径再返回绝对路径；`getTextFile / cacheBitmap / readTextOrPath / returnSound` 和 `LoadingState` 的 preload 都接上 | 已编，基础歌正常 |
| 崩溃没日志可查 | 新增 `source_body/body/backend/DebugLog.hx`（`#if (android \|\| ios)`，追加写 `Sys.getCwd()+'debug.log'`，每行 flush） | 在用 |
| 桌面被移动端代码污染 / 安卓会炸的宏错用 | 按审计报告批量修，见 `docs/ANDROID_TODO.md` 对应小节（A1/A2/A3、B1/B2/B4、C1–C4、E3/E4 已改；B3/B5/E1 未改） | 已编（桌面 release + 安卓都过） |

**桌面验证过**：`manage.sh --zh release` 全量 2085 个 cpp 编过（`realQuickJSEngine.exe` 约 46 MB），
证明 `CustomFadeTransition` 那处「桌面没有 MOBILE_CONTROLS 字段」的编译阻断已消除。

## 2. 构建 / 装包 固定套路

设备与工具（都不在 PATH 里）：

- adb：`D:/android-tc/android-sdk/platform-tools/adb.exe`，设备 `e46b95a6`（PFUM10 / Android 12 / arm64）
- NDK 工具：`D:/android-tc/android-sdk/ndk/25.2.9519653/toolchains/llvm/prebuilt/windows-x86_64/bin/`
  （`llvm-nm`、`llvm-objdump`、`llvm-addr2line`、`clang`）

安卓构建（**必须** `PE_IN_CONHOST=1`，否则 manage.sh 会裹 conhost 吃掉输出）：

```
& "C:\Program Files\Git\bin\bash.exe" -lc "cd '/d/FNF/FNF code/FNF-PE_RealQuickJs_Engine' && PE_IN_CONHOST=1 HXCPP_COMPILE_THREADS=4 bash manage.sh --zh android > .cache/build-android.log 2>&1"
```

- 无 Project.xml 改动时增量 15–45 s；只改 Haxe 时 relink `.so`；`Compiling group: haxe` 说明在重编大量 cpp（1–3 min）
- 产物：`export/release/android/bin/app/build/outputs/apk/debug/realQuickJSEngine-debug.apk`（约 613 MB）
- 装：`adb -s e46b95a6 install -r <apk>`；清日志：`adb shell rm -f /sdcard/RealQuickJS/debug.log /sdcard/RealQuickJS/lj_dbg.log`
- 桌面：`PE_IN_CONHOST=1 bash manage.sh --zh release`（不带子命令只会打印菜单）

**每次换过 `.a` / `Project.xml` / 大范围 `#if` 之后必做符号验收**（曾经因为安卓 obj「混代」出过 app 一启动就
`dlopen failed: cannot locate symbol "_hx_pos_..."`，链接器允许未定义符号，BUILD SUCCESSFUL 说明不了什么）：

```
unzip -o -q <apk> lib/arm64-v8a/libApplicationMain.so -d .cache/apkchk
llvm-nm -D .cache/apkchk/lib/arm64-v8a/libApplicationMain.so
# U 集合减 defined 集合，剩下的 `_hx_pos_*` 必须为 0；全是 __cxa_/libc 符号才正常
```

现成的脚本：`.cache/sochk.sh`（做完上面这套，输出 undefined/defined 计数与缺失数）。

## 3. 运行期调试设施（这轮新加的，下次直接用）

1. **`debug.log`**：`backend.DebugLog.log(tag, msg)` 追加写 `/storage/emulated/0/RealQuickJS/debug.log` 并 flush。
   logcat 的主缓冲区在崩溃时会被系统日志挤爆（14:13 那次整个 dump 只剩 4 条），所以必须写文件。
   拉：`adb pull /sdcard/RealQuickJS/debug.log .cache/debug.log`。
2. **`DebugLog.luaSelfTest()`**：`source_body/body/backend/DebugLog.hx:52-109`，在 `states/TitleState.hx` create 里触发，
   启动 app 就跑，12 步（`#if (android || ios)`，`luaSelfTestDone` 去重）：
   s1 `llua.LuaL.newstate` → s2 `openlibs` → s3 pushstring → s4 getfield(`print`) → s5 200×pushstring →
   s6 newtable + 200×setfield → s7 `llua.Lua.gc(L,2,0)` → s8 `loadbuffer(L,'',0,'=empty')` → s9 `loadbuffer('return 1')` …
   目前**崩在 s8**。
3. **trace 抓法**：hxcpp 的 `trace` 在 logcat 的 tag 就是 `trace`：
   `adb logcat -d > .cache/logcat.txt` 后 `grep 'trace   :'`；清缓冲 `adb logcat -c`。
4. **tombstone**：`F DEBUG` 行里有 signal / fault addr / 寄存器 / backtrace，PC 用
   `llvm-addr2line -f -C -e export/release/android/obj/libApplicationMain-64.so 0x...` 还原；
   静态库里的 LuaJIT 符号 addr2line 认不出，要用 `llvm-objdump -d --start-address=... ` 肉眼看指令。
5. **注意**：git-bash 会 MSYS 改写 `/sdcard/...` 这类绝对路径，adb 命令一律走 `pwsh` 工具，或加 `MSYS_NO_PATHCONV=1`。

## 4. LuaJIT 崩溃调查（**下次从这里接着干**）

### 4.1 现象

基础歌完全正常；mod 歌加载完就崩（`Fatal signal 11 SIGSEGV code 1 SEGV_MAPERR`），音频线程还在放，崩溃屏接不住。
`debug.log` 显示：所有 Lua 状态都建好了（`newstate ok=true`、`openlibs ok`），**真正执行脚本那一步**崩。
自检把范围压到 s8：`luaL_loadbuffer(L, '', 0, '=empty')` —— 连空 chunk 都编不了。

### 4.2 证据链（两次崩溃，两个库，同一崩点）

- 崩点：`#00 lj_str_new+0xF0` 的 `ldr x26, [x27, x8, lsl #3]`（x27=`g->str.tab`，x8=hash&~mask），
  栈：`lj_str_new ← lj_parse ← cpparser ← lj_vm_cpcall ← luaL_loadbuffer+80`。
- 用旧 haxelib 库时：`mask = ~0`（`lua_newstate` 的哨兵值，说明 `lj_str_resize` 从没生效）、`tab = 0x7900000000`、
  `num` 正常，算出的下标冲到 4 GB 外，fault addr 与算术完全对得上。
- 自建库之后仍然崩在同一处，但这次 `mask` 是垃圾值、`num=90` 正常，而且
  **`g = G(L)` 与 `L` 不相邻**（`0x79962b8b40 - 0x79962a0980 = 0x181C0`，正常必须正好 `sizeof(lua_State)=0x60`）。
- 确认崩的确实是自建库：`.so` 里有 `luaJIT_version_2_1_1795119671`、无 `lj_tab_rehash`、无 `beta3` 符号，
  构建日志里 luajit 静态库只有一个路径。
- **反证（关键）**：用完全相同的 `libluajit-64.a` 编一个纯 C 可执行文件（`NDK clang --target=aarch64-linux-android21
  -O1 -I <luajit>/src test.c libluajit-64.a -pie -fPIE -lm -ldl`），push 到 `/data/local/tmp/`（**必须 chmod 755**，
  否则报 `can't execute: Permission denied`），复刻 app 的 s1–s9 全部通过（`ALL OK`，`loadbuffer` 返回 0）；
  布局探针输出 `diff=0x60 sizeof(lua_State)=0x60 offsetof str=152 tab=152 mask=160 num=164`，
  `openlibs` 后 `tab/mask` 正常、s6 触发 resize 后 mask 255→511。
  → **库在真机上没毛病，是 app 进程里的 Lua 状态被破坏了。**

### 4.3 现在的假设与下一步

两个候选：①`L` 传进 C 之前就错了/被换成了别的 state；②`lua_State+16`（GC64 模式下的 `glref`）被写坏。
已有的排除：`@:privateAccess`/ABI 不是问题（前 7 步用同一个 `L` 全成功）；hxcpp 的 GC 不移动对象，不是「指针到期」。

**下次第一件事**：跑带插桩的库，看 `dL = G(L) - L` 在哪一步从 0x60 变成垃圾。插桩产物已存档：

- 补丁：`third_party/luajit-android/luajit-debug.patch`（在 LuaJIT v2.1 树里 `git apply` 即可，
  新增 `src/ljdbg.h`，往 `lj_load.c` / `lj_parse.c` / `lj_str.c` / `lj_state.c` 各插一行日志）
- 日志格式：`<tag> L=%p g=%p dL=%ld tab=%p mask=%08x num=%u top=%p base=%p st=%u`，写
  `/storage/emulated/0/RealQuickJS/lj_dbg.log`；插入点是 `loadx` / `before-cpcall` / `cpparser` /
  `parse` / `str_resize` / `str_new`（限前 150 次）/ `growstack`
- 换库流程：把 `third_party/luajit-android/libluajit-64.a` 先挪走（这样 `manage.sh` 的
  `ensure_android_luajit()` 会因文件不存在直接跳过，不会把干净库拷回去），再把插桩版
  `cp` 到 `D:/FNF/Haxe/4.3.7/haxe/lib/linc_luajit/git/lib/lua/lib/Android/libluajit-64.a`，然后正常编安卓
- 判读：`loadx` 处 `dL` 就已不对 → 崩在 s7 的 `gc` 或 Haxe 侧传参；`loadx` 对、`cpparser/parse` 错 →
  崩在 `lua_loadx` 内部（chunk name 的 `lj_str_new` 之前）

> 收尾状态：仓库里的 `libluajit-64.a`（997,592 B）和 haxelib 里那份**都已恢复成干净版**，
> 插桩版只在 `.cache/ljbuild-dbg/` 留过，重建按上面的补丁来。

### 4.4 自建库本身（已可复现）

`third_party/luajit-android/build.sh`：MSVC 编 host 侧 `minilua`/`buildvm`（dynasm 生成 `lj_vm.S` 和 `lj_*.h`），
再用 NDK clang 交叉编 `src/*.c`，`llvm-ar` 打包。坑（都踩过）：

- 环境变量必须是 **POSIX 路径**（`/g/vs/program/VC/Tools/MSVC/14.29.30133`、`/g/Windows Kits/10`、
  `/d/android-tc/android-sdk/ndk/25.2.9519653`）；写成 `G:/` 形式会被 PATH 里的盘符冒号截断，报 `cl: command not found`
- dynasm 必须带全 `-D JIT -D FFI -D DUALNUM -D FPU -D HFABI -D VER=80`，否则报
  `Only dual-number mode supported for ARM64 target`
- 新 clone 里没有 `luajit.h` 只有 `luajit_rolling.h`：先 `git show -s --format=%ct > luajit_relver.txt` 再跑 `minilua host/genversion.lua`
- 交叉编要排除 `luajit.c` 和 `ljamalg.c`（后者是所有 `.c` 的单文件集合，会和逐个 `.o` 重复定义）
- LuaJIT 的源文件是 **CRLF**，用 `perl -0pi` 改的要写 `\r?\n`
- `manage.sh` 的 `cmd_android` 会在构建前调 `ensure_android_luajit()`，把仓库里的库同步进 haxelib（相同则跳过）

## 5. 没修完 / 没开始

1. **LuaJIT 崩溃**（§4）—— 优先级最高，mod 歌全废。
2. 暂停菜单加「进入当前歌曲编辑器」：落点 `source_body/body/substates/PauseSubState.hx`，
   `menuItemsOG` 在 create 里生成，`update` 里 `switch(daSelected)` 处理各动作。
3. 审计剩余项（`docs/ANDROID_TODO.md` 有明细）：`B3` EngineSelectSubState 用 `Sys.exit(0)`（手机上等于闪退）、
   `B5` 编辑器在触屏上没法用、`E1` 安卓打包段把 `assets/base_game` 的 `*.mp3` 滤掉了。
4. 实机验收还没做的：歌内暂停键、虚拟键归位、weekend1 音响、崩溃屏、双指打歌时点暂停键。

## 6. 今天新踩的坑（补充到总坑清单）

- `@:privateAccess` 挂在**函数声明**上不管用，必须挂在**表达式**上（`@:privateAccess channel = sound._channel;`）。
- `Project.xml` 里的 `#if` 段缩进是 **tab**，`edit` 的 `old_string` 要带 `\t`。
- 没被 `read` 读过的文件 `edit` 会拒绝（`ops_inspect_local_file` 不算已读）；`write` 整段重写时容易重复声明
  （`Duplicate class field declaration`）。
- `haxe` 层静态访问实例字段会直接编不过：`lime.system.Display.currentMode` ✗，得用 `window.display.currentMode`。
- 安卓 `lime` 的原生加载器（`lime_image_load_file` / `lime_audio_load_file`）**只认 apk 内资源命名空间**，
  磁盘绝对路径反而是对的；Haxe 的 `File/FileSystem` 走 stdio，两者行为不一致——这就是「文件明明存在却加载不出来」。
- `FileSystem.exists` 为真不代表 lime 能加载；`localAsset` 解压过的旧文件不会自动刷新，换 apk 资源后要手删工作目录里的旧副本。

## 7. 工作区状态（2026-11-21 15:3x）

- `git status`：25 个已改文件 + 2 个新增（`source_body/body/backend/DebugLog.hx`、`third_party/luajit-android/`），**未提交**。
  改动清单见 `git status --short`；文档类改动只动了 `docs/ANDROID_TODO.md` 和这份。
- 安装中的 APK：15:26 那版（**带插桩 LuaJIT**，会往 `lj_dbg.log` 写日志），已装 `Success`，两个日志文件已清空。
  不用它的话，下次按 §2 重编一次即可（`ensure_android_luajit()` 会自动把干净库同步回去）。
