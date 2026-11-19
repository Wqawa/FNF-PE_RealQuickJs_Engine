# Psych Engine Build Instructions

* [Dependencies](#dependencies)
* [Building](#building)

---

# 本仓库额外要求（JS 运行时 / QuickJS-NG）

引擎里带一个 JS 脚本运行时（mod 的 `.js` 走它，Gameplay → JS Engine 里切）。它**不需要你另外下载**：

- 源码已经随仓库提交在 `third_party/quickjs-ng/`（约 12.8 万行，MIT）。
  仓库里这个目录必须存在，否则编译会在链接阶段失败。
- 编译产物 `third_party/quickjs-ng/build/quickjs-ng.lib` **不进版本库**（在 `.gitignore` 里），
  由本机 MSVC 现场编译。
- `bash manage.sh` 的第 2/3/4 项（编译）会**自动检查**：静态库不存在、或
  `quickjs.c` / `libregexp.c` / `libunicode.c` / `dtoa.c` 比它新，就先编译静态库再编引擎。
  想强制重编用 9 号功能。
- 编译命令固定为 MSVC `cl /c /O2 /std:c11 /utf-8`，四个源文件，规则写在 `manage.sh` 的
  `cmd_quickjs()` 里，改了 QuickJS 版本只需要重跑一次第 10 项。

链接方式是 `source/jsruntime/QuickJSHandler.hx` 顶部的 `@:buildXml`，用的是**相对路径**
（`third_party/quickjs-ng`），所以整个项目挪目录、换机器都不用改。

> Windows 走 MSVC 编的 `quickjs-ng.lib`，安卓走 NDK 编的 `libquickjs-ng.a`，见下面的 Android 段。

---

# Android

## 一条命令出包

```bash
bash manage.sh --zh 13
```

产物：`export/release/android/bin/app/build/outputs/apk/debug/realQuickJSEngine-debug.apk`
（包名 `com.realQuickJSEngine`，应用名 `RealQuickJS Engine`。Android 的 manifest merger
要求包名至少带一个点，单写 `realQuickJSEngine` 会在 `processDebugMainManifest` 挂掉。）

脚本只做三件事：把 `JAVA_HOME` / `ANDROID_SDK` / `ANDROID_NDK_ROOT` / `ANDROID_SETUP`
指到 `.workbuddy/toolchain/`（不动系统环境）→ 缺 QuickJS 的 arm64 静态库就先编 →
`haxelib run lime build android -DANDROID_HOST=windows-x86_64 -Dnostrip`。

后面全是 lime/hxcpp 自己的阶段：

| 阶段 | 干什么 | 大概耗时 |
|---|---|---|
| Haxe | 类型检查 + 生成 C++（`export/release/android/obj/src`） | 30~60s，编译错误都在这步 |
| hxcpp | NDK clang 编 1700 多个 .obj，只重编改动过的 | 增量十几秒到一分钟；全量 8~15 分钟 |
| gradle | 打 apk、debug 签名 | 20~30s |

改几行 `.hx` 到出新包，整条链路 1~2 分钟。删掉 `export/release/android/obj` 就是全量重编。

## 装到手机

```bash
ADB=.workbuddy/toolchain/android-sdk/platform-tools/adb.exe
$ADB devices                      # 先确认有设备
$ADB install -r export/release/android/bin/app/build/outputs/apk/debug/realQuickJSEngine-debug.apk
```

看启动日志（hxcpp 的 `trace` 走 logcat，标签是 `HXCPP`）：

```bash
$ADB logcat -s HXCPP
```

启动那几行里会有 `MobileStorage: cwd = ...`，用来确认 mods 到底落在内置还是外置目录。

工具链全在 `.workbuddy/toolchain/`（约 3GB），不装进系统：

| 目录 | 内容 |
|---|---|
| `jdk17/` | Temurin 17.0.21。lime 8.1.2 默认 gradle 7.4.2 + AGP 7.3.1，只认 JDK 17（系统那个 26 用不了） |
| `android-sdk/platform-tools` | adb |
| `android-sdk/platforms/android-33` | compileSdk |
| `android-sdk/build-tools/33.0.2` | aapt / zipalign |
| `android-sdk/ndk/25.2.9519653` | hxcpp 交叉编译 |

## 从零装工具链（换机器时才需要）

全装在 `.workbuddy/toolchain/`，不写注册表、不改系统 PATH：

```bash
TC=D:/FNF/FNF-PE_RealQuickJs_Engine/.workbuddy/toolchain

# 1. JDK 17（lime 8.1.2 的 gradle 7.4.2 / AGP 7.3.1 只认 17）
curl -L -o dl/jdk17.zip https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/OpenJDK17U-jdk_x64_windows_hotspot_17.0.21_9.zip
# 解压，目录改名成 $TC/jdk17

# 2. 命令行工具，解压后要摆成 $TC/android-sdk/cmdline-tools/latest/bin/sdkmanager.bat
curl -L -o dl/cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip

# 3. 接受许可 + 装组件（约 3GB）
JAVA_HOME=$TC/jdk17 $TC/android-sdk/cmdline-tools/latest/bin/sdkmanager.bat \
  --sdk_root=$TC/android-sdk --licenses
JAVA_HOME=$TC/jdk17 $TC/android-sdk/cmdline-tools/latest/bin/sdkmanager.bat \
  --sdk_root=$TC/android-sdk "platform-tools" "platforms;android-33" "build-tools;33.0.2" "ndk;25.2.9519653"

# 4. 告诉 lime 这些路径在哪（写 ~/.lime/config.xml）
haxelib run lime config ANDROID_SDK "$TC/android-sdk"
haxelib run lime config ANDROID_NDK_ROOT "$TC/android-sdk/ndk/25.2.9519653"
haxelib run lime config ANDROID_NDK_DIR  "$TC/android-sdk/ndk"
haxelib run lime config JAVA_HOME "$TC/jdk17"
haxelib run lime config ANDROID_SETUP true

# 5. gradle 发行包（wrapper 自己下不动时手动放）
#    ~/.gradle/wrapper/dists/gradle-7.4.2-bin/48ivgl02cpt2ed3fh9dbalvx8/
#    放 gradle-7.4.2-bin.zip，解压出 gradle-7.4.2/，再建一个空的 gradle-7.4.2-bin.zip.ok
curl -L -o gradle-7.4.2-bin.zip https://mirrors.cloud.tencent.com/gradle/gradle-7.4.2-bin.zip
```

QuickJS 的 arm64 静态库由 `bash manage.sh --zh 14` 编（13 号安卓构建发现缺会自动调）。
它不依赖 lime，只要 NDK 在默认位置，或者用 `PE_ANDROID_NDK` 指一个。

## 跟桌面构建的区别

- 三棵树（body / 1.0.4 / 0.6.3）全编进去，`include('vanilla')` 不再按平台关。
  入口仍是 `source/Main.hx` 读 `engine.txt`，安卓上文件在工作目录里。
- 三棵树的素材全打进 apk，外加 `assets/base_game`（桌面是 `prep_assets.sh` 事后铺，安卓没这一步，
  Project.xml 里用 `<section if="android">` 把 base_game rename 到 `assets/body` 一起打）。
  代价是包很大：现在 **565M**（body+base_game 879 项、1.0.4 278 项、0.6.3 681 项）。
- `*.mp3` 在三棵树里都不打（`exclude="*.mp3" unless="web"`），和桌面一致：native 只认 ogg。
- QuickJS 是另一份产物：`third_party/quickjs-ng/build/android-arm64/libquickjs-ng.a`，
  由 `manage.sh --zh 14` 用 NDK clang 编。`QuickJSHandler.hx` / `QuickJS.hx`
  的 `@:buildXml` 用 `if="windows"` / `unless="windows"` 分流，别改成 `#if` ——
  hxcpp 会把两个分支都收进 Build.xml，链接时同时出现 `.lib` 和裸库名。
- MODS / LUA / HSCRIPT 在安卓上也是开的（跟桌面同构）。锁成 desktop-only 反而会让
  PlayState 里那些无条件引用编不过。

## 素材在安卓上是怎么读的

**不释放，也不会释放到磁盘**。apk 里没有「首启解压 assets」这一步：源码树的 `assets/...`
被 lime 原样塞进 apk 的 `assets/assets/...`，运行时 OpenFL 走 `AssetManager` 直接从 zip 读。

所以：

- `Assets.getBitmapData('assets/body/...')` 拿得到图；`FileSystem.exists('assets/body/...')`
  是 false —— 工作目录在 `.realQuickJSEngine`，那儿没有 assets 目录。
- `Paths` 的判断是「先磁盘、后编译期 manifest」，安卓上实际只剩 manifest 那一半。
  **编译完再往 `bin/assets` 丢文件，安卓看不到**（桌面能看到，base_game 就是这么铺的）。
- 反过来，**工作目录里铺 `assets/<版本>/...` 是能读到的**：`Paths` 先 `FileSystem.exists`
  再退回清单，所以把整棵树拷到 `.realQuickJSEngine/assets/body/` 就能覆盖/补充素材，不用重打包。
  零散几张图、一首歌还是做成 `mods/<版本>/<名字>/` 更稳。

那条 `DPadModes/*.json` 的路子也是同一个原因走不通：`FileSystem.readDirectory` 列不到
apk 里的目录，所以布局表写在 `MobileLayouts.hx` 里。

## 文件写到哪

`backend.MobileStorage`（在 `source/`，三棵树共用）在启动时定工作目录：

- 先试 lime 的 `documentsDirectory`，路径里带 `/Android/data/` 就用它
  （`/storage/emulated/0/Android/data/com.realQuickJSEngine/files`，不需要任何存储权限，
  插数据线就能看到）；认不出就退回内置的 `/data/data/<包名>/files`。
- 在里面建 `.realQuickJSEngine/`，`Sys.setCwd` 进去。mods、crash dump、截图、日志都是相对它。
- 存档不在这儿：`FlxG.save` 走 `applicationStorageDirectory + company/file`，
  落在 `<应用存储>/RealQuickJS/realQuickJSEngine/`。

放 mod：`.../files/.realQuickJSEngine/mods/body/<mod 名>/`，清单是
`mods/body/modsList.txt`（`Paths.mods()` 就是 `mods/<VERSION_DIR>/`）。

## 触屏按键

`MOBILE_CONTROLS` 在 android 上自动定义（Project.xml），桌面想调试布局就自己加 `-DMOBILE_CONTROLS`。

- 代码在 `source_body/body/mobile/`（原版树 `source_vanilla/vanilla/mobile/`，
  0.6.3 树 `source_063/pe063/mobile/`），
  是从两个安卓移植版移植回来的（Mobile Porting Team，MIT，作者 Karim Akra / Homura Akemi）：
  `TouchButton` / `TouchPad` / `Hitbox` / `MobileInputManager` 基本上原样搬过来的。
- 贴图：`assets/<版本>/shared/images/mobile/touchpad/*.png`
  （`body` / `1.0.4` / `0.6.3` 三份，内容一样）。
  按钮 = `bg.png` 底盘 + 字母/方向图，都按 1280x720 坐标摆。
- 布局表在 `mobile/MobileLayouts.hx` 里写死。上游是从 `assets/shared/mobile/DPadModes/*.json`
  读的，安卓上那些文件在 apk 里，`FileSystem` 列不到，除非像移植版那样首启把整个 assets 拷到外部目录。
- 打歌有四种布局，Gameplay Settings → Touch Controls 里切：
  `Right` / `Left`（右手或左手方向键）/ `Custom`（自己摆的位置）/ `Hitbox`（四条透明轨道，点轨道打 note）。
  `Touch Controls Alpha` 控制透明度，拖到 0 就等于关掉触屏。
- `Custom` 的位置在 Options → Touch Controls 里拖：中间就是真的那套按键，拖到哪儿算哪儿，
  `Save` 存进单独的存档（`mobileControls`，`MobileData` 管），`Reset` 清掉回到默认。
  `Dynamic Controls Color` 让方向键跟着音符颜色走（只有 1.0.4 的两棵树有，0.6.3 的音符颜色是图里画死的）。
- `Wide Screen` 把画布拉满整块屏，不再留黑边（`mobile/MobileScaleMode.hx`）。关着的时候它跟
  flixel 默认的 `RatioScaleMode` 一样，所以是启动时统一装上去，选项只翻个标志位。
- 菜单用同一套按键：`MusicBeatState.create()` 给每个界面自动挂一个左下角四向键 + 右下 `A`/`B`，
  `A` = 确认，`B` = 返回。PlayState 进来会先摘掉它再挂打歌用的那套。
  （选项菜单之类叠在已有键盘上的子界面不会再挂一层，靠 `MobileInputManager.current` 判断。）
- 按键状态走 `backend.Controls`：`pressed/justPressed/justReleased` 在键盘、手柄之外多查一层
  `MobileInputManager.current`，所以菜单里的 `ui_up` / `accept`、打歌时的长按音符都不用另外改。
  音符本体还是走 `keyPressed(i)` / `keyReleased(i)`（0.6.3 树走 `onKeyPress` 合成键盘事件）。
- 三棵树现在都在 apk 里，靠 Options → Switch Engine 切：写 `.realQuickJSEngine/engine.txt`
  然后 `Sys.exit(0)`，重开游戏按文件里的值走。0.6.3 / 原版也有各自的同名界面，切回去不用 adb。
  代码本身用 `-DMOBILE_CONTROLS` 编桌面能过类型检查，改坏了会立刻发现。

## 已知限制

- 包是 debug 签名，release 还没配 keystore。
- 换包名等于换应用：`com.realQuickJSEngine` 跟旧的 `com.shadowmario.psychengine` 是两套数据，
  旧包里的存档和 mod 不会自动过来。
- 外置目录能不能认出来取决于 lime 的 `documentsDirectory` 在安卓上返回什么；认不出会退回内置
  目录，mod 就只能 `adb push`。启动日志里有一行 `MobileStorage: cwd = ...` 可以确认。

## 踩过的坑

- `ANDROID_HOST=windows-x86_64` 必须手传。hxcpp 4.3.2 按老 NDK 布局
  （`toolchains/<arch>-<ver>/prebuilt`）探测，NDK 25 只有 `llvm/prebuilt/windows-x86_64`，
  探测失败会退回 `windows`，然后报找不到 `clang++`。
- 默认加 `-Dnostrip`：NDK 25 只有 `llvm-strip.exe`，hxcpp 找的是
  `aarch64-linux-android-strip`，链接最后一步报"不是内部或外部命令"。
  要 strip 就在 NDK bin 里复制一份 `llvm-strip.exe` 改名。
- gradle 下载要过代理。JDK 的 cacerts 不认代理证书链（`PKIX path building failed`），
  脚本用 `-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT` 读 Windows 证书库。
  gradle 发行包本身可能下不动，手动放到
  `~/.gradle/wrapper/dists/gradle-7.4.2-bin/<hash>/` 并建 `.ok` 文件。
- `ANDROID_SETUP` 是 lime 的全局配置（`~/.lime/config.xml`），不设会在构造阶段报
  `run lime setup android` —— lime 8.1.2 已经把这个命令删了。

---

# Dependencies

- `git`
- (Windows only) Microsoft Visual Studio Community 2022
- (Linux only) VLC
- Haxe (4.3.4 or greater)

---

### Windows & Mac

For `git`, you're gonna want [git-scm](https://git-scm.com/downloads), download their binary executable there

For Haxe, you can get it from [the Haxe website](https://haxe.org/download/)

---

**(Next step is Windows only, Mac users may skip this)**

After installing `git`, open a command prompt window and enter the following:

```batch
curl -# -O https://download.visualstudio.microsoft.com/download/pr/3105fcfe-e771-41d6-9a1c-fc971e7d03a7/8eb13958dc429a6e6f7e0d6704d43a55f18d02a253608351b6bf6723ffdaf24e/vs_Community.exe
vs_Community.exe --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK.19041 -p
```

This will use `curl`, which is a tool for downloading certain files through your command prompt,
to download the binary for Microsoft Visual Studio with the specific packages you need for compiling on Windows.

(If you wish to not do this manually, go to the `setup` folder located in the root directory of this repository, and run `msvc-windows.bat`)

---
### Linux Distributions

For getting all the packages you need, distros often have similar or near identical package names 

For building on Linux, you need to install the `git`, `haxe`, and `vlc` packages

Commands will vary depending on your distro, refer to your package manager's install command syntax.

### Installation for common Linux distros

#### Ubuntu/Debian based Distros:

```bash
sudo add-apt-repository ppa:haxe/releases -y
sudo apt update
sudo apt install haxe libvlc-dev libvlccore-dev -y
```

#### Arch based Distros:

```bash
sudo pacman -Syu haxe git vlc --noconfirm
```

#### Gentoo:

```bash
sudo emerge --ask dev-vcs/git-sh dev-lang/haxe media-video/vlc
```

* Some packages may be "masked", so please refer to [this page](https://wiki.gentoo.org/wiki/Knowledge_Base:Unmasking_a_package) in the Gentoo Wiki.

---

# Building

Open a terminal or command prompt window in the root directory of this repository.

For building the game, in every system, you're going to execute `haxelib setup`. If you are asked to enter the name of the haxelib repository, type `.haxelib`.

In Mac and Linux, you need to create a folder to put your Haxe libraries in, do `mkdir ~/haxelib && haxelib setup ~/haxelib`.

Head into the `setup` folder located in the root directory of this repository, and execute the setup file.

### "Which setup file?"

It depends on your operating system. For Windows, run `windows.bat`, for anything else, run `unix.sh`.

Sit back, relax, and wait for haxelib to do its magic. You will be done when you see the word "**Finished!**"

To build the game, run `lime test cpp`.

---

### "It's taking a while, should I be worried?"

No, it's completely normal. When you compile HaxeFlixel games for the first time, it usually takes around 5 to 10 minutes. It depends on how powerful your hardware is.

### "I had an error relating to g++ on Linux!"

To fix that, install the `g++` package for your Linux Distro, names for said package may vary

e.g: Fedora is `gcc-c++`, Gentoo is `sys-devel/gcc`, and so on.

### "I have an error saying ApplicationMain.exe : fatal error LNK1120: 1 unresolved externals!"

Run `lime test cpp -clean` again, or delete the export folder and compile again.

---
