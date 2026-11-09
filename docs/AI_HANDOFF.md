# AI 交接文档 — FNF-PE_RealQuickJs_Engine

> 写于 2026-11-09 晚。上一个 AI 会话一整天的工作全在这里。
> 日常流水账在 `.workbuddy/memory/2026-11-09.md`，Lua/HScript 兼容的逐条修复记录在 `docs/LUA_COMPAT.md`（**改了兼容层必须同步更新它**）。

---

## 1. 项目是什么

Psych Engine 1.0.4 的源码 fork，目标是让 0.6.3 / 0.7.3 时代的老 mod（Lua + HScript）不用改就能跑。
主线工作就是维护一层兼容层：路径回退、函数双签名、类别名、视频类名壳子。

- 仓库：`D:\FNF\FNF-PE_RealQuickJs_Engine`
- 构建：`bash .workbuddy/build.sh`（release）/ `bash .workbuddy/build.sh -debug`（debug）
  - 这个脚本封装了 MSVC 环境变量（D:\VS2019\BuildTools）和本地 `.haxelib`，直接 `haxelib run lime build` 会失败
- 产物：`export/release/windows/bin/PsychEngine.exe`（当前 30.1 MB，18:56 版，启动无 error）
- 上游参照：`.workbuddy/upstream/`（pe063 / pe073 / pe104 完整，novaflare 是 sparse clone 只有 `source/`）
- 审计工具：`python tools/lua_compat_audit.py --ref .workbuddy/upstream/<v>/source --label <v>`（对比回调/签名/类别名差异）

## 2. 用户偏好（务必遵守）

- 中文、简短、能容忍速记式拼写；被叫停立即执行
- 报 bug 只给现象，**要自己定位根因，不要猜**
- 要求"验证过再说"，改动要能给出可复现的验证结果
- 遇到测试成本过高的功能，直接整个删掉，不留死代码
- 不手写 UI，复用引擎原生控件；设置项文案只讲作用不讲设计理由
- 经常 AFK，写好问题就走，期望自主推进、不要反复追问
- **`.workbuddy/` 目录是项目数据不是缓存，永远不要删**

## 3. 今天完成的七块工作

### 3.1 Lua/HScript 兼容层（第 1~12 项，详见 docs/LUA_COMPAT.md）

- `debugPrint` 双签名从独立的 Compat063.hx **合并进** `DeprecatedFunctions.hx`（用户不要额外文件/转译层）
- stage / notetype / event 三类脚本共用 `startLuasNamed()` / `startHScriptsNamed()`，
  补了 `assets/<file>` 根目录兜底（0.6.3 的 getPreloadPath 语义），`.js` 分支也补了
- 晚 22 点（评审四连修）：路径查找收敛进 `Paths.findScriptFile()` 一份（原来三处复制粘贴），
  函数内系统调用配齐 `#if`（H5 能编译了），sys 上落空时按 exe 目录锚定重试；
  debugPrint 的数字第二参不再走颜色分支，另留 `PE_DEBUGPRINT_LEGACY` 环境变量强制老语义。
  详见 LUA_COMPAT.md 第 7 轮（16~19 条）
- 0.6.3 的 5 个内置事件在 1.0.4 已挪进各 `BaseStage.eventCalled()`，不用补
- `PlayState` 补了 `cameraX/Y` 每帧同步、`inChartEditor`、`comboStacking` 静态转发、
  `removeFromGroup` 双语义、`Bar` 的 width/height getter、`FunkinJS` 的 then/do/else

### 3.2 PlayState 拆分

- 3745 → 2821 行，25 个函数搬到 `source/states/play/`：
  - `PlayStateEvents.hx`（事件）/ `PlayStateCamera.hx`（镜头）/ `PlayStateJudge.hx`（判定输入）
- 形式是静态 helper 接 `ps:PlayState`，类上挂 `@:access(states.PlayState)` + `@:access(backend.MusicBeatState)`；
  PlayState 里保留同名转发，外部/脚本调用完全不变
- 验证过：去掉 `ps.` 前缀后与原文件逐行一致；搬运工具在 `.workbuddy/tmp/move_block.py`（一次性，可复用）
- 注意：部分转发从 private 变成了 public（可见性放大），用户没提意见就先这样

### 3.3 release 构建 + 窗口尺寸

- `run_test.sh` / `prep_assets.sh` 默认走 release（`PE_BUILD=debug` 切回）
- "一启动就全屏"的真因：`backend/Native.fixScaling()` 按 DPI 放大窗口，150% 屏上正好 1920×1080。
  已改成卡在屏幕 85% 以内等比缩放

### 3.4 Freeplay / 资源查找（用户报的三连 bug）

- 根因：`Paths.fileExists()` / `getPath()` 用 `OpenFlAssets.exists()`（编译期清单）判断文件存在，
  而 `assets/base_game` 是编译后才拷进 bin 的 → 清单里没有 → 图标全变 face、关卡目录图片全 404
- 修：新增 `Paths.existsOnDiskOrManifest()`（先 `FileSystem.exists` 再清单），改了两处调用点
- "背景全变 week1"：`Song.fixMissingFields` 给没写 `stage` 字段的老谱面填了 `'stage'`，
  把 `vanillaSongStage(曲名)` 的按曲名推断挡死了。改成按曲名反推，且必须在 `loadFromJson` 里做
  （后面紧跟 `StageData.loadDirectory()`）
- weekend1 崩溃：`getSparrowAtlas/getPackerAtlas` 把 xml 路径字符串丢给 flixel，
  清单里查不到 → null → 空指针。加 `readTextOrPath()`：磁盘上有就直接读内容

### 3.5 NovaFlare 移植（用户拍板：只要 PhillyGlow + Section）

- 搬了：`noteTweenScale`、`readJson`、相机 shader 三件套（`addShaderToCam` / `removeCamShader` / `clearCamShaders`）、
  33 条老模块路径别名（`stages.*` → `states.stages.*`、`editors.*` → `states.editors.*` 等）
- `PhillyGlow` 在 0.6.3 里其实是两个 FlxSprite（Particle/Gradient），不是 shader——
  NovaFlare 把它映射到 BlendModeEffect 是错的，我们补了正确的两条；
  评审挑出来后那条错的已删（0.6.3 上游的 PhillyGlow.hx 只是模块名，裸名从来不是类）
- 新增 `source/backend/Section.hx`（0.6.3 的谱面段落类，纯数据壳子）
- 没搬：virtualPad（手游向）、错误去重、setHaxeSyntaxFix、依赖库不同的那批

### 3.6 视频兼容（当天最后一大块）

**先说根因**：`Project.xml` 里 `VIDEOS_ALLOWED` 写在 `<section if="officialBuild">` 里，
源码构建不传 officialBuild → `hxvlc` 根本没进构建，`VideoSprite`/`startVideo` 全是空壳。
已把这一行移到 section 外。代价：bin 多了 libvlc.dll + plugins/（约 111 MB）。

- 新增 `source/hxcodec/flixel/FlxVideo.hx`：hxvlc 的 `Video` 做底，保留 hxcodec 3.x API
  （`play(path, loop)` / `playVideo` / `stopVideo` / `dispose` / `onEndReached` / `bitmapData`）
- `source/hxcodec/VideoHandler.hx`（2.6 名字）、`source/vlc/MP4Handler.hx`（0.6.x 名字）是同名壳
- `bitmap` 只在 FlxVideo 自己被 add 进 state 时才挂到 FlxG.game，避免只取 bitmapData 的 mod 糊屏
- lua 补了 2P Engine 的 `precacheVideo(name, ?tag)`（hxvlc 没有预解码，只做路径校验）

### 3.7 HScript 全局补全

- Iris 的 `preset()` 只给 Std/Math/StringTools。0.6.x 脚本直接写 `Reflect.getProperty(...)` 会报
  `Unknown variable: Reflect`。`HScript.preset()` 现在补：
  `Reflect / Lambda / Date / EReg / StringBuf / Json / Sys / Bytes` +
  `FlxObject / FlxRect / FlxAngle / FlxStringUtil / FlxSpriteUtil / FlxSave / FlxSound`
- **`FlxPoint` 是 abstract，不能当值 set**，编译报 `Cannot use abstract as value`，别加
- 类别名表原来只进 `Iris.proxyImports`（够 `import` 和 `new` 用），但 `Type.getClassName(Boyfriend)`
  这种"类名当值用"还是会炸。新增 `ScriptClassAliases.applyToHScript()`，在 preset 里把表倒进变量表
  （只倒不带点的 key——`stages.Spooky` 这种模块路径 hscript 走字段路径解析，不查变量表）

## 4. 测试基建（怎么验证）

```
bash .workbuddy/run_test.sh [song]      # 完整回归：注入 AutoTestState → 编译 → 放测试脚本
                                        # → PE_AUTOTEST 开局 → 收结果 → 全部清理
PE_BUILD=debug bash .workbuddy/run_test.sh   # 切 debug 构建
NOPATCH=1 ...                            # 不给谱面打补丁
```

- 测试入口 `AutoTestState.hx` 由 `harness/apply_hook.py on/off` 临时拷进 source/，跑完自动撤
- 测试脚本在 `.workbuddy/luatest/scripts/`（compat_v073/v104/more/edge + 探针），
  舞台/事件/音符类型脚本在 `.workbuddy/luatest/{mods,assets}/`
- 结果写 `.workbuddy/testout/*.txt`，格式 `PASS|名字` / `FAIL|名字` / `ERR|...`
- `patch_chart.py` 给 bopeebo 塞自定义事件 + 音符类型（已改成跟 `PE_BUILD` 走，之前写死 debug 路径吃过亏）

**最近一次全绿结果**：

```
edge 10/0    more 37/0    v073 58/0    v104 32/0
stage      stage|ok|stage
notetype   notetype|ok|assets-root      ← 故意放 assets 根，测 0.6.x 兜底
event      event|ok|fired:1:2
```

## 5. 踩过的坑（下一个 AI 必读）

1. **窗口挪屏幕外会失焦** → flixel `autoPause` 把 update 停了，onBeatHit 停在个位数像卡死。
   测试入口已 `FlxG.autoPause = false`。看到节拍不动先查这个
2. **测试脚本必须从 bin/mods 清走**。之前 cleanup 只撤 Main.hx 入口，compat_*.lua 留在玩家 mods 里，
   满屏 debugPrint + broken_probe 报错 + 连带 2hot 的 Split Screen.hx 报 camLeft=null。
   现在 run_test.sh 的 cleanup 会全删（只删空目录）。`Split Screen` 那个错在没有测试脚本时不存在，
   是 `callOnScripts` 先 lua 后 HScript、lua 里 triggerEvent 打到还没跑 onCreatePost 的 HScript 导致的
3. `onUpdatePost` 这类每帧回调**别每帧写盘**，只计数，别的回调触发时一起 dump
4. 写 Haxe 代码时对象字面量的 key（`{songSpeed: ...}`）不能加前缀；签名行尾的 `//` 注释会吞后面生成的代码；`:Void` 不能加 `return`（搬运脚本的经验）
5. `prep_assets.sh [release|debug]` 负责把 `assets/base_game` 拷进 bin——**编译不会自动带**，
   因为 `BASE_GAME_FILES` 也在 officialBuild 段里（故意的，别动）
6. `docs/LUA_COMPAT.md` 是兼容层的活文档，每修一条就往里加一段

## 6. 当前状态与已知未修项

- git：约 20 个文件修改 + 6 个新增目录/文件（含晚上的评审四连修），**全部未提交**（用户没提 commit，别擅自提）
- exe：18:56 版已验证（启动无 error、2hot 自动开局视频能创建销毁、回归全绿）；
  22:12 版是评审四连修之后的重编译，**只验证了编译通过，没跑回归**
- 已知未修（都是 mod/素材层面，不是引擎）：
  - `spraycanErectAtlas.png`：2hot mod 里只有 `spraycanAtlas.png`，它的舞台脚本要前者
  - `noteSplashes.png`：0.6.3 是单张图集，1.0 拆成 `noteSplashes/` 目录按类型分文件，
    老脚本按旧名字取图会 404（视觉缺失，不影响运行）
- 备选没做的事：virtualPad 整块移植、lua 报错去重（moreLuaErrors）、`NotesSubState`、
  `animateatlas`/`hxcodec` 之外的库别名——用户没点头就不要动
