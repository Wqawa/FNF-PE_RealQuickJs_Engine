# 安卓端待办（2026-11-20 起）

设备：PFUM10（OPPO，Android 12 / SDK 31，arm64-v8a）。
构建：`bash manage.sh --zh 8`（工具链在 `D:/android-tc`，见 `docs/BUILDING.md`）。
调试脚本：`.workbuddy/android-dev/dev.sh`（git 忽略）。

## 已经跑通的

- 装上能启动，Title 完整（背景图、logo、四个菜单项）
- Freeplay 有周和歌（TUTORIAL / BOPEEBO / FRESH）
- 能进歌，音符、血条、评分、角色都正常，`ERROR:` 那行也消失了
- 菜单里的虚拟按键（四向 + A/B）能操作
- Options → Switch Engine 能打开了（之前一闪就回）
- 音乐能播（`freakyMenu`、菜单音效）

这次修的四个崩溃 / 卡点，原因记在 `.workbuddy/memory/2026-11-20.md` 里：
`Engine` 过早取 `applicationDirectory`、`MobileScaleMode` 设得比 `FlxGame.create()` 早、
apk 内资源被 `FileSystem.exists` 判成不存在、`introText` 空导致第 10 拍越界。

---

## 待办

### 1. 存储目录 + 权限（**改成移植版那套了，没在设备上验证**）

目标目录换成了 `/sdcard/RealQuickJS/`（公共存储，任何文件管理器都能翻到），
挑目录的顺序是：

1. `/storage/emulated/0/RealQuickJS` —— 走 JNI 的 `Environment.isExternalStorageManager()`，
   只有用户在系统设置里开了"所有文件访问"才会用这个
2. `Android/data/com.realQuickJSEngine/files/.realQuickJSEngine` —— 不需要权限，数据线能进
3. `/data/data/.../files/.realQuickJSEngine` —— 兜底

`Project.xml` 里加了三条权限（`READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` /
`MANAGE_EXTERNAL_STORAGE`）。注意 lime 的 `android.permission` 一旦出现就不再套默认值，
所以原来那四个（WAKE_LOCK / INTERNET / VIBRATE / ACCESS_NETWORK_STATE）也一起写进去了，
`aapt dump permissions` 确认过 7 条都在。

- [x] 装一版，看日志 `MobileStorage: cwd = ...` 落在哪。没开权限时应该是第 2 条（已验）
- [x] 去系统设置里给"所有文件访问"，重启，再看是不是切到 `/storage/emulated/0/RealQuickJS/`（已验）
- [x] 确认 `mods/`、`saves/` 在里面，能直接用文件管理器拷（已验）
- [ ] **没做**：启动时自动跳设置页引导授权。现在只能靠用户自己去设置里开，
      日志里会打 `public storage unavailable`。要跳页得用 JNI 拼
      `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` 的 Intent 再 startActivity，
      下次再说

资源不会解压到外部目录。`Paths.getTextFile` 是"磁盘优先、apk 兜底"，
所以想改哪张图/哪段 json，把同名文件按 `assets/<版本>/...` 的结构丢进
`/sdcard/RealQuickJS/` 就会覆盖，不用整包解压。

### 2. Switch Engine 界面：没有按钮，选不了（已修，待补根因）

现象：界面能打开了，但屏幕上没有可点的按键，方向键和 A 也用不了。

原因：`EngineSelectSubState` 是 `MusicBeatSubstate`，而 `MusicBeatSubstate.create()` 只在
`MobileInputManager.current == null || !current.hasButton(A)` 时才挂 pad。
Options 那边已经挂了 pad，所以这个子界面不会再挂一层，也就没有可见按键。

- [x] 子界面自己挂一层 pad（或者放一个左上角 ✕ + 上下箭头）
- [ ] 更省事的方案：列表项直接响应触摸点击，点哪个选哪个，点空白处关闭
- [ ] 选完写 `engine.txt` 后 `Sys.exit(0)`，在安卓上要确认真的退出去了（不是回到桌面留个空壳）

### 3. 歌曲内没有暂停办法

现象：进歌以后既没有暂停按钮，按返回也不会暂停，只能等歌放完。

- [ ] 右上角加一个小的暂停按钮（贴图放 `assets/<版本>/shared/images/` 下，
      用 `Paths.image` 取，跟着 HUD 相机走）
- [ ] 返回键（`controls.BACK`）暂停游戏
- [ ] 在 Gameplay 设置里加一项，切换这两种方式：
      - 只认右上角按钮
      - 只认返回键
      - 两个都开（默认？）
      具体选项名和取值你来定，写进 `ClientPrefs`
- [ ] 暂停菜单的移动端按键要能用（上下选择 + A 确认）

### 4. 暂停菜单加"进入当前歌曲编辑器"

- [ ] 暂停菜单加一项，点了直接开 `ChartingState`，且带上当前歌曲（别开成空谱面）
- [ ] 编辑器返回时能回到暂停状态，而不是回到主菜单

### 5. 编辑器入口（**主菜单已加，设备上验过：位置可用**）

`MainMenuState` 右上角加了个 `EDITOR` 按钮（`#if mobile`），点了进 `MasterEditorMenu`。
桌面那条路没动，还是按 7（`debug_1`）。

- [x] 装上确认按钮位置不挡东西、能戳到（触摸会走 `FlxG.mouse`）
- [ ] 从 `MasterEditorMenu` 返回要能回主菜单，别卡在编辑器里
- [ ] `MasterEditorMenu` 里各个编辑器在安卓上能不能用还没试，尤其
      `ChartingState` 的键盘操作在触屏上基本没法用，可能要单独的移动端布局

### 6. 其它两棵树的安卓适配

`source_vanilla` / `source_063` 里的 `Paths`、`Character`、`OptionsState` 等是同一套上游代码，
apk 内资源被 `FileSystem.exists` 判成不存在的问题它们一样有。这次只改了 body 树。

- [ ] 把 `Paths.getTextFile` / `existsOnDiskOrManifest` 的用法同步过去
- [x] `MobileScaleMode` 在 `vanilla/Main.hx`、`pe063/Main.hx` 里也是构造时直接设 —— 已照 body
      的做法改成等一帧再设（Switch Engine 重启时 `_state` 还是 null 的 null deref，未设备验证）
- [ ] 切过去实际跑一遍：`echo vanilla > <cwd>/engine.txt` 然后重启

---

## 2026-11-21 这一轮改了什么（手机/桌面冲突审计后的批量修）

审计报告的 A/B/C/D/E 五类问题，结论记在提交信息里，这里只记改到哪儿了。

### 已改（编译通过，未在设备上验证）

- 歌内暂停键：新建 `camPause`（`#if (mobile || MOBILE_CONTROLS)`，加在 `camOther` 之后、
  `bgColor.alpha = 0`），歌内 pad 和暂停键都挂它；点判定从 `FlxG.mouse.overlaps(btn)` 改成
  `mobile.TouchUtil.overlaps(btn, camPause)`（原来不传相机时会回落到 `camGame`、而按钮画在每拍缩放的
  `camHUD` 上，所以点不中；`FlxG.mouse` 还只有单指针，双指打歌时按不到）
- 主菜单 `EDITOR` 按钮同样换成 `mobile.TouchUtil`
- 进歌/切界面虚拟键"过几帧才归位"：`MusicBeatSubstate.hideParentPad`（过场用子状态设 false），
  `CustomFadeTransition` 里 `addMenuPad = false; hideParentPad = false;` —— 原来黑幕过场会把父界面摆好的
  Custom 布局 pad 藏起来，还自己挂一套默认布局的 pad，0.5 秒后才换回来
- weekend1 音响/均衡器不跳：`grig.audio` / `funkin.vis` 原来挂在 `officialBuild` 段里从来没编过
  （`Project.xml`），移到 `desktop || android` 并补 `<define name="funkin.vis"/>`；
  `ABotSpeaker` 拆出 `updateFromAnalyzer` / `updateFromBeat`（拿不到频谱就按 `Conductor` 节拍兜底），
  `audioSourceOf` 加 null/空 buffer 守卫
- 宏混用：`controlsMode/controlsAlpha/dynamicColors`、`OptionsState` 的 Touch Controls、`acceptLatch`、
  `Touch Controls` 子状态、`BaseOptionsMenu`、`GameplayChangersSubstate`、`Freeplay/StoryMenu` 的
  `ctrl_menu`，统一用 `MOBILE_CONTROLS`；`Project.xml` 的 `MOBILE_CONTROLS` 加 `ios`。
  桌面存档写 `controlsAlpha = 0` 的问题因此没了
- `CustomFadeTransition` 里引用 `addMenuPad/hideParentPad` 的两行加 `#if MOBILE_CONTROLS`
  （桌面没有这两个字段，之前桌面 release 构建直接编不过）
- 崩溃处理：`CRASH_HANDLER` 安卓 release 也开（`Project.xml`）；`EngineCrash.copy()` 走
  `lime.system.Clipboard`（安卓是 JNI 实现，ndll 里有 `lime_clipboard_set_text`），
  `saveDump` 在安卓落到 `System.documentsDirectory + '/crash'`（CWD 不一定可写）
- `CoolUtil.openFolder` 移动端分支（不再调 `explorer.exe`），顺手修了 `folder.substr(...)` 结果被丢掉
- 帧率：`ClientPrefs` 里 `displayMode.refreshRate` 报 0 时再问一次
  `window.display.currentMode.refreshRate`，还拿不到才退 60

### 没改（要拍板 / 影响面待定）

- B3：`EngineSelectSubState` 写完 `engine.txt` 直接 `Sys.exit(0)`，手机上等于闪退，应该改成自己重启
- B5：编辑器触屏基本没法用（`ChartingState` 全靠键盘）
- D2 / E1：`assets/base_game` 的 `*.mp3` 在 apk 里被 android 段的 exclude 规则滤掉
- E4 后半：帧率选项在手机上要不要单独暴露（现在只在桌面 Graphics 菜单里有）

---

## 构建坑：安卓对象缓存"混代"会让 app 一启动就 dlopen 崩溃

症状：装完包点图标，弹 SDL Error 然后退出，错误是

```
dlopen failed: cannot locate symbol "_hx_pos_a2c5aad29e94c731_934_new"
  referenced by ".../lib/arm64-v8a/libApplicationMain.so"
```

原因是 `export/release/android/obj/obj/androidarm64-64` 里混了两代编译产物：hxcpp 只重编 haxe 改动过的
cpp，剩下的沿用旧 obj；如果旧 obj 是在另一套 define 下编的（这次是 11-20 那轮没带 stack frame、11-21 这轮
带了），新 obj 会把 `_hx_pos_*` 当成需要外部定义的全局符号，老 obj 却没导出它，链接能过、dlopen 挂。

判定方法（ndk 的 llvm-nm）：

```bash
NM=D:/android-tc/android-sdk/ndk/25.2.9519653/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-nm.exe
"$NM" export/release/android/obj/libApplicationMain-64.so > /tmp/so.nm
grep ' U ' /tmp/so.nm | awk '{print $2}' | sort -u > /tmp/u.txt
grep -v ' U ' /tmp/so.nm | awk '{print $3}' | sort -u > /tmp/d.txt
comm -23 /tmp/u.txt /tmp/d.txt | grep _hx_pos_   # 有输出就是中招
```

修法：删掉 `export/release/android/obj/obj/androidarm64-64` 和 `export/release/android/obj/libApplicationMain-64.so`
（保留同目录的 `Options.txt`、`HxcppConfig-64.h`、`src/`、`include/`），重新 `manage.sh --zh android` 全量编。
**改过 Project.xml 的 define、大范围 #if 宏之后，别信增量包。** 全量编用
`HXCPP_COMPILE_THREADS=4`（本机 4 核）能把 40 分钟压到十几分钟。

编完必须验一遍上面的 `comm`：剩下的未解析符号应该全是 `libc`/`liblog`/`__cxa_*` 这类运行期符号，
`_hx_pos_*` 一个都不能有。只看 gradle 的 BUILD SUCCESSFUL 没用，链接器允许未定义符号。

---

## 运行坑：lime 的原生加载器在安卓上不认相对路径

症状：freeplay 里 mod 的歌单能列出来（那是 `File.getContent` 读 json，走 stdio 没问题），但

- mod 的图标全是空白 / unknownMod，logcat 里 `Bitmap not found: mods/body/<mod>/images/icons/xxx.png`
- mod 的界面音效一加载就崩：`Error loading sound from file: mods/body/<mod>/sounds/xxx.ogg`（openfl `Sound.hx` 抛 IOError），
  而且崩了以后音频线程还在放（听起来像“游戏挂了但音乐没停”）
- mods 菜单里没写 `pack.json` 的 mod 只显示文件夹名，`pack.png` 也不显示

原因：`BitmapData.fromFile` / `Sound.fromFile` 走的是 lime 的 C++ 原生加载（`NativeCFFI.lime_image_load_file`
/ `lime_audio_load_file`），相对路径在安卓上会被当成 **apk 里的资源**去找，磁盘上的 mods 文件一律打不开；
Haxe 自己的 `File`/`FileSystem` 走 stdio，所以 stat/exists/json 读全都正常 —— 这就是“文件明明在却加载不出来”。

修法（`source_body/body/backend/Paths.hx`）：

- 新增 `Paths.absoluteDiskPath(file)`（`#if (android || ios)`），相对路径补 `Sys.getCwd()`（MobileStorage 启动时
  已经把它设成 `/storage/emulated/0/RealQuickJS/`）
- 所有把磁盘路径喂给 lime 原生加载器的地方都要过它：`Paths.cacheBitmap`、`Paths.returnSound`、
  `LoadingState.preloadSound`、`LoadingState.preloadGraphic`、`ModsMenuState` 的 `pack.png`
- `Sound.fromFile` 外面还要包 `try/catch`：它失败是 **throw IOError**，不接住整局直接崩（`returnSound` 原本就裸调）

排查方式：logcat 里 hxcpp 的 trace tag 就叫 `trace`，按进程过滤即可
`adb logcat -d --pid $(adb shell pidof com.realQuickJSEngine)`。

---

## 已知限制

- debug 签名，release 还没配 keystore
- 首次全量编译在这台机器上要 40 分钟左右（4 核，串行）；加上 HXCPP_COMPILE_THREADS=4 能压到十几分钟，增量十几秒到一分半
- 图标类资源如果 apk 里没有，会打 `Removed invalid images: xxx`，那是正常的
