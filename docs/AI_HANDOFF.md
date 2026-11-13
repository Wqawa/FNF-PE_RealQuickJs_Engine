> **2026-11-13 晚：** 所有编译/素材/审计脚本已合并进仓库根目录的 `manage.sh` + `manage.bat`，
> 本文里出现的 `building/*.sh`、`tools/*.py`、`setup/*` 命令都已作废，只当历史记录看。

# AI 交接文档 — FNF-PE_RealQuickJs_Engine

> 最后更新 2026-11-10 13:10。逐条修复记录在 `docs/LUA_COMPAT.md`（**改兼容层必须同步更新它**），
> 逐日流水账在 `.workbuddy/memory/YYYY-MM-DD.md`。
>
> **2026-11-13 起另有一份 `docs/HANDOFF_DUAL_ENGINE.md`**：讲 0.6.3 移植、原版 1.0.4 并进
> 同一个 exe、以及 `Std.parseInt` 颜色饱和和窗口缩放两个坑。看那份之前先看这份了解本体。

---

## 0. 2026-11-13 交接：当前状态与未解决的问题

> 这一节是给接手的人看的。**两个问题没修好**，先看这里再动代码。

### 0.0 现在是什么状态

同一个 `PsychEngine.exe` 里跑三棵独立的源码树，靠 `bin/engine.txt` 选：

| engine.txt | 走哪棵 | 源码目录 | 资产目录 |
|---|---|---|---|
| `body`（默认） | 本仓 fork | `source/` | `assets/body/` |
| `vanilla` | 原版 PE 1.0.4 | `source_vanilla/vanilla/` | `assets/1.0.4/` |
| `pe063` | Psych Engine 0.6.3 | `source_063/pe063/` | `assets/0.6.3/` |

三份 Options 菜单里都有 `Switch Engine`，选完写 `engine.txt` + `Sys.exit(0)`，重启生效。
mod 同样分组：`mods/body`、`mods/1.0.4`、`mods/0.6.3`、`mods/global`（全局，三版本共用）。

细节看 `docs/HANDOFF_DUAL_ENGINE.md` 第六点五、六点六节。

**编译**（全程纯命令行，不弹窗）：

```bash
bash building/build.sh                # 增量
bash building/setup.sh                # 环境体检
```

如果从没有控制台的环境启动编译，Windows 会给 haxe/cl/link 各分配一个控制台窗口，
用 `conhost --headless bash building/build.sh` 包一层就没有窗口了。

---

### 0.1 未解决：0.6.3 的 Options → Switch Engine 打不开

**现象**：0.6.3 里选中 Switch Engine，界面不出现（卡住 / 一闪即回）。

**已经查到哪一步**：

诊断日志 `bin/testout/engine_select_063.log` 里 `create start` → `create ok`
**重复了几十遍**，确认不是崩溃，是每帧都在重建这个 SubState。

判断的根因：`Controls.ACCEPT` 用的是 `FlxActionDigital.check()`（**按住**语义，不是按下），
而父菜单 `persistentUpdate` 默认 `true`，SubState 打开后 `update` 照跑，
`controls.ACCEPT` 一直是 true，于是每帧又 `openSubState` 一次，把刚建好的界面关掉重建。

已经改的：`source_063/pe063/options/OptionsState.hx`

```haxe
if (controls.ACCEPT && subState == null) {
    openSelectedSubstate(options[curSelected]);
}
```

**但用户反馈仍然卡住。所以还有第二个原因没找到。**

**下一步建议**：

1. 先确认那个 `subState == null` 真的生效——在 `openSelectedSubstate` 里加 trace，
   看日志里还会不会重复出现多条。如果不再重复，说明问题变成「界面建出来了但看不见」。
2. 若界面建出来看不见，查 `EngineSelectSubState` 的 `alpha`、`camera`、`scrollFactor`，
   以及 `bg` 是否被 `screenCenter` 推到了屏幕外。
3. 对照 0.6.3 原仓（`D:/FNF/PsychEngine_0.6.3`）里能正常打开的
   `options/GraphicsSettingsSubState`，逐行比差异。
4. 注意：**不要**把 `initialState` 直接设成 `OptionsState` 来测——那会跳过
   `PlayerSettings` 初始化，`controls` 为 null，得到的是假崩溃。

### 0.2 未解决：0.6.3 里 lua 创建贴图找不到资源

**现象**：0.6.3 里 lua 建的贴图（`makeAnimatedLuaSprite` 的 `texture` 模式等）出不来。

**已经查到哪一步**：

0.6.3 的 `Paths` 有**三处只查 `OpenFlAssets`**（编译期清单）：

| 位置 | 后果 |
|---|---|
| `fileExists()` | `mods/` 下的资源判成不存在 |
| `getPath()` 的两级 fallback | 磁盘有、清单无的关卡资源被跳过 |
| `returnGraphic()` | 只有清单里有才加载，磁盘图返回 null |

`mods/` 下的文件永远不进编译期清单，构建后才铺进 bin 的素材也一样，
所以这三处等于「运行时才出现的文件一律当不存在」。

已经改的：`source_063/pe063/Paths.hx` 加了 `existsOnDiskOrManifest()`
（先 `FileSystem.exists` 再 `OpenFlAssets.exists`），上述三处改走它。

**但用户反馈仍然没修好。**

**下一步建议**：

1. 拿一个**最小 lua 脚本**在 0.6.3 里单独试 `makeLuaSprite('t', 'images/xxx')` 和
   `makeAnimatedLuaSprite('t', 'xxx', 0, 0, 'texture')`，把 `Paths.image()` 返回的实际
   路径 trace 出来。
2. 重点怀疑 `key` 是否重复带了 `images/` 前缀：0.6.3 的 `getPath('images/$key.png')`
   自己会加一次，如果 lua/上层再传 `images/xxx`，就变成 `images/images/xxx.png`。
   grep 一下调用方。
3. 确认 mod 目录名和 `modsList.txt` 里的名字是否一致（`mods/0.6.3/<名字>`），
   不一致 `currentModDirectory` 就查不到。
4. `AtlasFrameMaker.construct` 里 `getTextFromFile('images/$key/Animation.json')`
   同样的前缀问题也查一遍。

### 0.3 已确认不是 bug 的（别再浪费时间）

- **本体跑 childplayV2 血条上的黑色块**：是 mod 自己的 `pahb` 血条皮肤。
  `mods/body/Gumball cp/scripts/HUD.lua` 里 `setProperty('healthBarBG.visible', false)`
  把原版血条背景藏了，换成它自己的图集。正常现象。
- **0.6.3 画面里没有 BOTPLAY 文字**：0.6.3 本来就没有这个元素，不是缺资源。
- **`StageEditorState` 列出 body/1.0.4/0.6.3 当 stage 名**：已修。

### 0.4 这一轮已经做完的

- 三引擎并进同一个 exe（`1fd1c78`）
- 资产按版本分组：`assets/{body,1.0.4,0.6.3}`，`Project.xml` 三段对称声明（`6ef5666`）
- 0.6.3 去掉 lime 的 library selector，三棵树统一走普通路径（`fceb131`）
- 0.6.3 的 `checkFileExists` 多拼一层 `assets/`（`153ce24`）
- 构建脚本收口到 `building/`：`setup.sh` + `libs.txt` + `README`（`f766a51`）
- 清掉 `.workbuddy` 里四十多个一次性日志、`bin` 里的诊断残留

---

## 1. 项目是什么

Psych Engine 1.0.4 的源码 fork，目标是让 0.6.3 / 0.7.3 时代的老 mod（Lua + HScript）不改一行就能跑，
外加一个把 `.js` 转译成 Lua 的 FunkinJS。

- 仓库：`D:\FNF\FNF-PE_RealQuickJs_Engine`
- 上游参照：`.workbuddy/upstream/`（pe063 / pe073 / pe104 完整，novaflare 只有 `source/`）
- 审计工具：`python tools/lua_compat_audit.py --ref .workbuddy/upstream/<v>/source --label <v>`

## 2. 用户偏好（务必遵守）

- 中文、简短、能容忍速记式拼写；被叫停立即执行
- 报 bug 只给现象，**要自己定位根因，不要猜**；要求"验证过再说"
- 测试成本过高的功能整个删掉，不留死代码
- 不手写 UI，复用引擎原生控件；设置项文案只讲作用不讲设计理由
- 常 AFK，写好问题就走，期望自主推进、不要反复追问
- **`.workbuddy/` 是项目数据不是缓存，永远不要删**

## 3. 构建与测试

```bash
bash building/build.sh            # 增量 release，约 1 分钟
bash building/build.sh -debug     # debug
bash building/build.sh -clean     # 全量重编，约 15~30 分钟
bash building/build.sh -dry       # 只打印计划
```

`building/build.sh` 六步：找 Haxe → 用 `haxelib list` 核对 `Project.xml` 要求的库 → 扫 MSVC/SDK →
关运行中的游戏 / `-clean` → `lime build windows` → 验收 + 铺 `assets/base_game`。
Windows 上双击 `building/Build.bat` 等价。日志在 `building/logs/`。

- **hxcpp 缓存默认开**（`.cache/hxcpp`，命中时直接拷 `.obj` 不跑 cl.exe）。首次填充要算哈希 + 写缓存，
  那次增量 152s；往后稳态增量 73s 左右（不开缓存 42~62s），全量重编省得多。怀疑缓存里躺的是旧 obj 时用 `-no-cache`。
- `assets/base_game` 是编译**之后**才拷进 bin 的（`BASE_GAME_FILES` 故意留在 `Project.xml` 的 officialBuild 段）
- `VIDEOS_ALLOWED` 已移出 officialBuild 段（视频要用），代价是 bin 多 111MB 的 libvlc

回归：

```bash
bash .workbuddy/run_test.sh [song]        # 注入 AutoTestState → 编译 → 放脚本 → 自动开局 → 收结果 → 清理
PE_BUILD=debug bash .workbuddy/run_test.sh
NOPATCH=1 bash .workbuddy/run_test.sh     # 不给谱面打补丁
```

- 测试入口 `AutoTestState.hx` 由 `harness/apply_hook.py on/off` 临时拷进 `source/`，跑完自动撤
- 测试脚本在 `.workbuddy/luatest/scripts/`，舞台/事件/音符类型脚本在 `.workbuddy/luatest/{mods,assets}/`
- 结果写 `.workbuddy/testout/*.txt`，格式 `PASS|名字` / `FAIL|名字` / `ERR|...`
- **`run_test.sh` 的 cleanup 是白名单**：新增测试脚本必须同时加进 cleanup，否则会留在 `bin/mods` 里

**最近一次全绿（2026-11-10 13:04）**

```
edge 10/0   more 37/0   v073 58/0   v104 32/0
versiontag 1/0（带 %run_v_0.7.3 的脚本看到 0.7.3）
versionplain 1/0（不带标记的脚本仍是 1.0.4）
stage / notetype / event 三类脚本都正常
```

## 4. 兼容层现在有哪些东西

分五层，改之前先确认改的是哪一层（详见 `docs/LUA_COMPAT.md` 第一节）：

| 层 | 位置 | 管什么 |
|---|---|---|
| 函数 | `psychlua/*Functions.hx`、`FunkinLua.hx` | 250 多个 Lua 函数 |
| 同名不同义 | `DeprecatedFunctions.hx`、`ReflectionFunctions.hx` | 参数语义变了的，做成"两种写法都认" |
| 类名 | `backend/ScriptClassAliases.hx` | 0.6.3 扁平源码树的裸类名（约 90 条） |
| 设置字段 | `backend/ClientPrefs.hx` | 0.6.3 静态字段 → 1.0 的 `data` |
| 对象/字段 | `states/PlayState.hx`、`objects/Bar.hx` | `healthBarBG`、`modchartSprites`、`uiGroup` 展开、Bar 尺寸 |

### 2026-11-09 完成

- **Lua / HScript 兼容**（1~19 条，见 LUA_COMPAT.md）：`debugPrint` 双签名、三类脚本的路径兜底、
  `Paths.findScriptFile()` 收敛、`ClientPrefs` 32 个转发、HScript 全局补全（Reflect/Lambda/FlxObject…）
- **PlayState 拆分**：3745 → 2821 行，25 个函数搬到 `source/states/play/`（Events / Camera / Judge），
  静态 helper 接 `ps:PlayState`，类上挂 `@:access`，PlayState 保留同名转发 —— 外部和脚本调用完全不变
- **Freeplay / 资源查找**：`Paths.existsOnDiskOrManifest()`（先磁盘后清单），修掉图标全 face、关卡图 404
- **NovaFlare 移植**：PhillyGlow 两条正确的映射、`Section` 数据壳、相机 shader 三件套、33 条模块路径别名
- **视频**：`hxcodec/FlxVideo`（hxvlc 打底，保留 hxcodec 3.x API）、`vlc/MP4Handler` 同名壳

### 2026-11-10 完成

- **谱面引擎版本按文件时间判定**（`Song.hx`）：`PE_100_RELEASE = 2024-10-15T01:54:44Z`（GitHub tag `1.0`），
  创建时间早于它走 `Pe-0.7.3` lane 语义，晚的走 `Pe-1.0.4`。优先级：手动切换 > 文件时间 > 谱面 `format`。
  没有 `{"song":{}}` 包裹层的谱面不按时间降级（那种形状 lane 必然是绝对的）。
  暂停界面右上角显示判定来源。
- **皮肤路径兼容**：`Note.resolveNoteSkin()`（裸名 `NOTE_assets` → `noteSkins/`）、
  `NoteSplash.loadSplash()`（裸名 `noteSplashes` → `noteSplashes/` 子目录），
  外加 `requestedSplash` 修掉"每 spawn 一次就重载图集"。
- **按脚本伪造引擎版本**：文件名带 `(%run_v_0.6.3)` 时，该脚本的 `version` 全局和
  `getPropertyFromClass(..., 'psychEngineVersion')` 返回 0.6.3，其它脚本不受影响。
- **一站式编译**：`building/`（见第 3 节）。

## 5. 踩过的坑（必读）

1. **往 Lua 回调里加 `return` 必须显式标返回类型**。给 `getPropertyFromClass` 加了一句
   `return funk.versionOverride;`（String），Haxe 把整个匿名函数的返回类型推断成 String，
   Float/Array/对象全被 toString，v073 掉 4 项、v104 掉 3 项。写 `function(...):Dynamic` 就好。
2. **窗口挪屏幕外会失焦** → flixel `autoPause` 把 update 停了，onBeatHit 停在个位数像卡死。
   测试入口已 `FlxG.autoPause = false`。
3. **测试脚本必须从 `bin/mods` 清走**（cleanup 白名单，见上）。
4. `onUpdatePost` 这类每帧回调**别每帧写盘**，只计数，别的回调触发时一起 dump。
5. 写 Haxe 时对象字面量的 key（`{songSpeed: ...}`）不能加前缀；签名行尾的 `//` 注释会吞后面生成的代码；
   `:Void` 不能加 `return`（搬运脚本的经验）。
6. `Project.xml` 里 `BASE_GAME_FILES` 和 `VIDEOS_ALLOWED` 是两个独立开关，前者故意留在 officialBuild 段。

## 6. 已知未修

- ~~`weeb/` / `pauseAlt/` / `ui/` / `philly/` 素材在 bin 里不存在~~ —— 2026-11-13 晚修好：
  根因是 `assets/base_game`（官方素材单一源，713 个文件）没被铺进 `bin/assets/<版本>/`，
  连带两棵 1.0.4 树的 `shared/weeks/*.json`、`week*`、`songs`、`characters` 全都缺。
  现在由 `building/prep_assets.sh`（build.sh 第 6 步）用硬链接补齐，已核对两棵树 0 缺。
- `noteSplashes` 的老式扁平图集如果**和 1.0 内置皮肤同名**，仍会被解析到内置皮肤（优先能加载的那个）。
- `FlxUIDropDownMenuCustom` 这类依赖 flixel-ui 的类，1.0 已经没有对应库，接不了。
- 画面层面的兼容（贴图位置、动画观感、UI 层级）这套测试看不出来，只能人眼验。
- 备选没做：virtualPad 移植、lua 报错去重、`NotesSubState` —— 用户没点头就不要动。

## 7. git 状态

工作区未提交改动集中在 11-10 的三块工作 + `building/`。上一笔提交 `4559448` 是 11-09 的全量兼容层。
