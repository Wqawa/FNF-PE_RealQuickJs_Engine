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

- [ ] 装一版，看日志 `MobileStorage: cwd = ...` 落在哪。没开权限时应该是第 2 条
- [ ] 去系统设置里给"所有文件访问"，重启，再看是不是切到 `/storage/emulated/0/RealQuickJS/`
- [ ] 确认 `mods/`、`saves/` 在里面，能直接用文件管理器拷
- [ ] **没做**：启动时自动跳设置页引导授权。现在只能靠用户自己去设置里开，
      日志里会打 `public storage unavailable`。要跳页得用 JNI 拼
      `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` 的 Intent 再 startActivity，
      下次再说

资源不会解压到外部目录。`Paths.getTextFile` 是"磁盘优先、apk 兜底"，
所以想改哪张图/哪段 json，把同名文件按 `assets/<版本>/...` 的结构丢进
`/sdcard/RealQuickJS/` 就会覆盖，不用整包解压。

### 2. Switch Engine 界面：没有按钮，选不了

现象：界面能打开了，但屏幕上没有可点的按键，方向键和 A 也用不了。

原因：`EngineSelectSubState` 是 `MusicBeatSubstate`，而 `MusicBeatSubstate.create()` 只在
`MobileInputManager.current == null || !current.hasButton(A)` 时才挂 pad。
Options 那边已经挂了 pad，所以这个子界面不会再挂一层，也就没有可见按键。

- [ ] 子界面自己挂一层 pad（或者放一个左上角 ✕ + 上下箭头）
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

### 5. 编辑器入口（**主菜单已加，没在设备上验证**）

`MainMenuState` 右上角加了个 `EDITOR` 按钮（`#if mobile`），点了进 `MasterEditorMenu`。
桌面那条路没动，还是按 7（`debug_1`）。

- [ ] 装上确认按钮位置不挡东西、能戳到（触摸会走 `FlxG.mouse`，理论上没问题）
- [ ] 从 `MasterEditorMenu` 返回要能回主菜单，别卡在编辑器里
- [ ] `MasterEditorMenu` 里各个编辑器在安卓上能不能用还没试，尤其
      `ChartingState` 的键盘操作在触屏上基本没法用，可能要单独的移动端布局

### 6. 其它两棵树的安卓适配

`source_vanilla` / `source_063` 里的 `Paths`、`Character`、`OptionsState` 等是同一套上游代码，
apk 内资源被 `FileSystem.exists` 判成不存在的问题它们一样有。这次只改了 body 树。

- [ ] 把 `Paths.getTextFile` / `existsOnDiskOrManifest` 的用法同步过去
- [ ] `MobileScaleMode` 在 `vanilla/Main.hx`、`pe063/Main.hx` 里也是构造时直接设，
      大概率同样会崩（body 是改成等一帧解决的）
- [ ] 切过去实际跑一遍：`echo vanilla > <cwd>/engine.txt` 然后重启

---

## 已知限制

- debug 签名，release 还没配 keystore
- 首次全量编译在这台机器上要 40 分钟左右（4 核），增量十几秒到一分半
- 图标类资源如果 apk 里没有，会打 `Removed invalid images: xxx`，那是正常的
