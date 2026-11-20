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

### 1. 存储目录 + 权限（代码已写，**没在设备上验证**）

`MobileStorage.pickBase()` 现在会先问 `documentsDirectory`，再走 JNI 的
`Context.getExternalFilesDir(null)`，最后才退回私有目录。
设备被拔之前只验证到能编译，**运行结果没看过**。

- [ ] 装一版，看启动日志里的 `MobileStorage: cwd = ...`
      期望是 `/storage/emulated/0/Android/data/com.realQuickJSEngine/files/...`
- [ ] 确认这个目录真的建出来了，`adb shell ls` 能看到
- [ ] 确认 `mods/`、`saves/` 落在里面，玩家能拷进去
- [ ] JNI 那段如果抛异常，日志里会有 `getExternalFilesDir failed`，会把 cwd 退回私有目录

注意：走 `getExternalFilesDir` 这条路**不需要**任何运行时权限，也没往 manifest 里加
`MANAGE_EXTERNAL_STORAGE`。参考移植版（`kittycathy233/FNF-PsychEngine-Mobile-1.0.4-Archive`）
是申请了全盘权限、把 assets 也解压到 `/sdcard/.PsychEngine/`；我们选的是"资源留在 apk、
只把可写目录挪出去"，省空间、启动快，但拿不到公共目录。

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

### 5. 主界面加编辑器入口

- [ ] Title 上加一个按钮（齿轮旁边，或者菜单里加一项），进编辑器选择界面
- [ ] 编辑器选择界面可以照 `EngineSelectSubState` 的排版做，列 `charts/` 下的谱面

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
