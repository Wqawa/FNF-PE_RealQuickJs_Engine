> **2026-11-13 晚：** 所有编译/素材/审计脚本已合并进仓库根目录的 `manage.sh` + `manage.bat`，
> 本文里出现的 `building/*.sh`、`tools/*.py`、`setup/*` 命令都已作废，只当历史记录看。

# AI 交接文档 — FNF-PE_RealQuickJs_Engine

> 最后更新 2026-11-17。逐条修复记录在 `docs/LUA_COMPAT.md`（**改兼容层必须同步更新它**），
> 逐日流水账在 `.workbuddy/memory/YYYY-MM-DD.md`。
>
> - `docs/JS_TRANSPILE_HISTORY.md`（2026-11-17）：FunkinJS 转译器的原始说明和 issue 存档。
>   从 `JavaScriptUtils.hx` 的注释里搬出来的，那个文件现在只留英文说明 + 一个空类。
> - `docs/SCRIPT_ISOLATION_AUDIT.md`（2026-11-17）：三棵树所有「脚本隔离」点的问题表
>   （查找 / 类解析 / 资源路径 / 装载判重），动手改 `Paths`、`ScriptClassAliases`、
>   `IsolatedImports` 之前先看它。
> - `docs/HANDOFF_DUAL_ENGINE.md`（2026-11-13）：0.6.3 移植、原版 1.0.4 并进同一个 exe、
>   `Std.parseInt` 颜色饱和和窗口缩放两个坑。看那份之前先看这份了解本体。
> - `docs/JS_QUICKJS.md`（2026-11-16）：`.js` 两条路（Troll 转译 / 真 QuickJS-NG）的分流、
>   桥的协议、加宿主函数的步骤、停止哨兵、脚本装卸、已知限制、验证方法。
>   **动 `source_body/body/jsruntime/` 之前先看这份。**

---

## 目录约定（2026-11-17 拆分后）

| 目录 | 是什么 | 规矩 |
|---|---|---|
| `source/` | **公共层**：入口 `Main`、`Engine`（读 engine.txt）、`backend.EngineCrash`、`backend.CrashState` | 只许依赖 flixel / lime / std。**不许** import `backend.*` / `states.*` / `objects.*` —— 一 import 就等于把本体的代码带进另外两棵树，资源路径也跟着跑到 `assets/body` |
| `source_body/body/` | 改版 1.0.4（原来整个 `source/` 挪过来）。classpath 根，多数类不加前缀；启动类在 `body/` 子包里（`body.Main`） | 随便用，它就是本体 |
| `source_vanilla/vanilla/` | 原版 1.0.4，全部 `vanilla.` 前缀 | 原版代码，别往里面塞兼容逻辑 |
| `source_063/pe063/` | 0.6.3，全部 `pe063.` 前缀 | 同上 |

三棵树的 classpath 根各是 `source/`、`source_body/body`、`source_vanilla`、`source_063`，
**包名都不带版本前缀的只有 body 那棵** —— 目录多一层只是为了和另外两棵树长得一样，
包里还是 `backend.*` / `states.*`。所以加文件时看包名，不看目录层数。

判断一段代码该放哪：**它依赖不依赖某棵树私有的类**。依赖就放那棵树，不依赖才进 `source/`。
目前公共层只有上面四个文件 —— 崩溃屏能共用，是因为它只用 flixel 原生控件（交接坑 #12）。
`ScriptClassAliases` 这类"兼容件"仍在 body 侧，它要读 body 的类；别的树是按名字用的。

新增公共文件之前先想清楚：它一旦读 `Paths` / `ClientPrefs`，切树之后读的就是 body 的那份。

## 0. 当前状态与未解决的问题

> 这一节是给接手的人看的：先看 0.0 搞清楚现在长什么样，再看 0.1 / 0.2 那两个没修的问题。

### 0.0 现在是什么状态

同一个 `PsychEngine.exe` 里跑三棵独立的源码树，靠 `bin/engine.txt` 选：

| engine.txt | 走哪棵 | 源码目录 | 资产目录 |
|---|---|---|---|
| `body`（默认） | 本仓 fork | `source_body/body/` | `assets/body/` |
| `vanilla` | 原版 PE 1.0.4 | `source_vanilla/vanilla/` | `assets/1.0.4/` |
| `pe063` | Psych Engine 0.6.3 | `source_063/pe063/` | `assets/0.6.3/` |

三份 Options 菜单里都有 `Switch Engine`，选完写 `engine.txt` + `Sys.exit(0)`，重启生效。
mod 同样分组：`mods/body`、`mods/1.0.4`、`mods/0.6.3`，各版本只读自己那本 `modsList.txt`
（2026-11-16 起 `mods/global/` 这套「全局 mod」机制整个删掉了，那个目录不再被读取）。

细节看 `docs/HANDOFF_DUAL_ENGINE.md` 第六点五、六点六节。

**编译**（全程纯命令行，不弹窗）：

```bash
bash manage.sh release                # 增量（= 2 号功能）
bash manage.sh env                    # 环境体检（= 1 号功能）
bash .workbuddy/build.sh -debug       # 薄壳，会自己裹 conhost --headless
```

从没有控制台的环境（编辑器 / CI / 后台任务）启动编译时，Windows 会给 haxe/cl/link
各分配一个控制台窗口，屏幕上一排黑框闪。`.workbuddy/build.sh` 已经用
`conhost --headless` 包好了 —— 它会把子进程退出码吃成 0，所以真结果走临时文件带出来。
直接调 `manage.sh` 时记得自己裹一层。

跑游戏/跑测试一律不弹窗：`AutoTestState` 会把窗口最小化 + 挪到屏幕外 + 静音，
只有设 `PE_AUTOTEST_SHOW=1` 才显示画面。

### 0.0.1 2026-11-16 这一轮做了什么

四笔提交，都编译过、跑过验证：

| 提交 | 内容 |
|---|---|
| `e0a7aab` | **QuickJS 通道补完**：`getVar` 取值、`Function_Stop*` 哨兵、脚本装卸、`onCreate` 分发，外加与 Lua 对齐的 23 个宿主函数；新增 `jsruntime/QJSShaders.hx`。细节看 `docs/JS_QUICKJS.md` |
| `e1b57fe` | **崩溃拦截器**（`backend/EngineCrash` + `backend/CrashState`）；旧版回退开关并进 Gameplay；global mod 改造（下一笔撤销） |
| `353852b` | **删掉 `mods/global/` 全局机制**，每个引擎只读 `mods/<版本>/` |
| `f4a79b3` | **修 0.7.3 的 `getObjectOrder`**：hxcpp 反射不调 getter，HUD 元素上必抛空引用 |

现在几条硬事实，别再照旧印象做事：

- `.js` 有两条路（Troll 转译 / 真 QuickJS-NG），**默认还是 Troll**。QuickJS 那边和 Lua
  只差 `runHaxeCode` / `runHaxeFunction` / `addHaxeLibrary` 三个（Haxe 互操作，刻意不做）。
- **没有全局 mod 了**。跨版本共享自己拷一份，`mods/global/` 不再被读。
- **崩溃不再弹系统对话框**：写 `crash/` dump 后切引擎内的崩溃屏（三棵树共用），
  C 键或 COPY 按钮复制全文，可选退出 / 回当前引擎主菜单；`Ctrl+Alt+Shift+Q` 手动触发。
- 旧版回退三项（Legacy HUD / Health / Icons）在 **Gameplay** 里，独立的 Compat 页已删除。
- Lua 回归之前是坏的（路径停在双引擎改造前），2026-11-16 修好并重新全绿，见第 3 节。

---

### 0.0.2 2026-11-17 这一轮做了什么

**脚本隔离收口**（不做兼容函数，专治「同一个脚本被认成两个」「类拿到另一棵树」）：

- 四套脚本查找入口合成一套：`findScriptFile` 补 `currentLevel`；`FunkinLua.findScript`、
  `scripts/` 目录扫描、角色脚本全部走它；判重统一 `Paths.sameScript`。
- hscript 类解析加跨树守卫：body 拒绝 `vanilla.*` / `pe063.*`；vanilla 模式只认 `vanilla.`
  前缀、未知标识符兜底走 `LuaUtils.resolveClass`、`IsolatedImports` 先清 `proxyImports` 再灌；
  pe063 撞树时改试扁平同名类。
- 两棵树各自 override `getOrImportClass`：`import` 的落点直接拦，不再依赖 `IsolatedImports`
  那张生成表；`HScript` 补 `version` 全局（`%run_v_x.x.x` 对 `.hx` 也生效）。
- 离开 PlayState 时把 `Paths.currentLevel` 挂回 `shared`；`removeHScript` 之后从
  `hscriptArray` 摘掉，分发时跳过 `isClosed()`。
- 新增 `compat_isolation.lua`（10 条），进 `run_test.sh` 白名单。
- 新增 0.6.3 路径探针 `source_063/pe063/debug/Probe.hx` + `.workbuddy/run_063_probe.sh`：
  不进游戏、不建 state，只算路径 + 真构造一次图集。
- 测试窗口现在会 `visible=false`，任务栏里不留格子（`PE_AUTOTEST_TASKBAR=1` 可恢复）。

全量回归（2026-11-17）：`edge 10 / more 37 / v073 58 / v104 32 / jssyntax 1 / versiontag 1 /
versionplain 1 / isolation 10`，失败 0；QuickJS 26 + 27 + 2，失败 0。
vanilla 分支没有自动入口，只能人工开机验；pe063 有探针（只验路径/图集，不跑 PlayState）。

问题表在 `docs/SCRIPT_ISOLATION_AUDIT.md`。

**0.2 那个悬案结案了**：不是路径 bug。探针实测官方图集和 mod 图集都能正确解析并
`construct`（98 帧），`images/` 没拼两遍。真正原因是图集格式 —— 0.6.3 的 `AtlasFrameMaker`
只认 Animate 2018 的单个 `spritemap.json`，0.7+ 的 mod 用 `spritemap1.json`，在真 0.6.3 上
也不可见。详见审计表。

### 0.0.3 2026-11-17 目录拆分

`source/` 一刀切成两层：

- `source/` **只留公共层**：`Main.hx`（入口：装崩溃拦截 → 读 engine.txt → 分叉）、
  `Engine.hx`、`backend/EngineCrash.hx`、`backend/CrashState.hx`。没有 `import.hx`，
  公共文件自己写 import，`Engine.hx` 补了 `using StringTools`。
- `source_body/body/` 收原 `source/` 的全部内容，**body 的类还叫 `Main`**：
  启动类挪进子包 `source_body/body/body/Main.hx`（`package body;` → `body.Main`），
  和 `vanilla.Main` / `pe063.Main` 对称；`<app main="Main">` 指着公共入口，两者不再抢名字。
  引用它的三个文件加 `import body.Main;`，`Main.fpsVar` / `Main.game` 写法不变。
  body 的 `main()` 去掉，`FunkinJS.verifyUtilsIntegrity()` 挪进构造函数。
- `Project.xml` 加一条 `<classpath name="source_body/body" />`；`<app main="Main">` 指向公共入口。
- `.workbuddy/harness/apply_hook.py` 的注入点跟着走（`source_body/body/Main.hx` +
  `source_body/body/AutoTestState.hx`）；`manage.sh` 里 QuickJS 的路径同步。

回归照旧全绿：Lua 10/37/58/32/1/1/1/10、QuickJS 26/27/2、0.6.3 探针 98 帧 ×2。

### 0.0.4 2026-11-17 第二轮：body 也套一层目录

`source_body/*` → `source_body/body/*`，classpath 改成 `source_body/body`，包名不动。
目的只是让三棵树结构对称（`source_vanilla/vanilla`、`source_063/pe063`、`source_body/body`）。

**顺手抓到并修掉一个真会坏的运行时路径**：

`FunkinJS.UTILS_REL` 是 `verifyUtilsIntegrity()` 按 CWD 去找源码文件用的（从 bin 往上
`../../../../` 拼）。它写死的是 `source/psychlua/JavaScriptUtils.hx`，目录一搬就永远找不到 ——
而找不到时函数是**静默放行**（"发行版本来就没有源码"），从日志上完全看不出来。
已改成 `source_body/body/psychlua/JavaScriptUtils.hx`，跑测试能在 game.log 里看到
`[integrity] JavaScriptUtils.hx ok`，改之前是 `not found, skip`。

编译期的路径不受影响，逐个核对过：

| 位置 | 基准 | 是否受影响 |
|---|---|---|
| `jsruntime/QuickJSHandler.hx` 的 `@:buildXml` libpath | 相对 obj 目录（`export/<mode>/windows/obj`） | 否，包名没变 → 生成路径还是 `obj/src/jsruntime/` |
| 同文件 `@:cppFileCode` 的 `#include "../../../.."` | 相对生成的 cpp（`obj/src/jsruntime/`） | 否，同上 |
| body `Main.hx` 的 `@:cppInclude('./external/gamemode_client.h')` | 相对源文件 | 否，`external/` 跟目录树一起搬了；而且只在 linux 分支生效 |
| `manage.sh` 的 QuickJS 源码检查 | 绝对路径 | 已同步 |
| `harness/apply_hook.py` 注入点 | 绝对路径 | 已同步 |

### 0.0.5 2026-11-17 第三轮：注释统一成英文

body 树 41 个文件、1388 行中文注释，逐条改成英文，风格照上游 Psych：`//` 短句、说清「为什么」、
不写 Markdown 标题、不留「注意」「说明」这类前缀。代码一行没动，只换注释。

顺手做了两件事：

- `JavaScriptUtils.hx` 原来是 **1518 行纯注释**（725 行中文，大半是某个同类项目的 issue 存档），
  没有一行代码。现在抽成 `docs/JS_TRANSPILE_HISTORY.md`，`JavaScriptUtils.hx` 只留 30 行英文
  说明 + 一个空类 —— 它仍是 `verifyUtilsIntegrity()` 的哈希锚点，改它必须同步 `UTILS_FNV`。
- 公共层（`source/`）、`pe063`、`vanilla` 里我们自己写的中文注释也一起换了，四个树现在都是英文。

翻译时踩到的两个坑（都属于「注释在字符串里」）：

| 位置 | 坑 |
|---|---|
| `@:cppFileCode('...')` / `@:buildXml('...')` | 里面是单引号字符串，注释里的 `hxcpp's` 会把字符串截断，报 `Expected )` |
| `static inline var WRAPPERS:String = '...'` | 同上，`LuaUtils'`、`Lua's` 都会炸，报 `Missing ;` |

改完编译 + 三条回归全绿。

### 0.0.6 2026-11-17 第四轮：README「已知限制」清账

按 README 第四节逐条核对后修掉的：

- **vanilla 的 modFolder**：`FunkinLua` 构造还在用上游的 `split('/')[0] + '/' == Paths.mods()`，
  撞上 `mods/1.0.4/` 这层版本目录永远不成立，vanilla 树所有脚本的 `modFolder` 恒 null。
  给 `vanilla.backend.Paths` 补了 `modFromScriptPath()`（和 body 同一份逻辑），构造改调它。
- **QuickJS 文件路径**：`getTextFromFile` / `readJson` 以前直接拿脚本字符串查 CWD，
  `saveFile` 走 `Paths.mods`、`deleteFile` 走 `Paths.getPath` —— 写进去的文件读不回来。
  现在四个全走 `Paths`；`readJson` 补 `.json` 后缀回退，返回文本由脚本 `JSON.parse`
  （桥只传字符串）。QJS 回归里新增 `file-roundtrip` / `file-delete` 两条。
- **QuickJS.hx 绝对路径**：`@:buildXml` / `@:cppFileCode` 改成相对 hxcpp 构建目录
  （`../../../../third_party/...`），和 `QuickJSHandler.hx` 同款；`manage.sh` 里那段 sed 删了。
  已验证生成的 `obj/Build.xml` 和 `obj/src/jsruntime/QuickJS.cpp` 都是相对路径且链接通过。
- **context 上限** 32 → 64。
- **事件参数**：`emitTo` 现在按桥支持的形态转发最多三个参数（零参 / 数字 / 字符串 /
  (str,num) / (str,num,num) / (str,str)），以前只用第一个。
- **HScript 版本**：补 `psychEngineVersion` 全局（和 `version` 一样受 `(%run_v_)` 影响）。
  直读静态字段 `MainMenuState.psychEngineVersion` 仍然拿不到伪装值 —— `Interp.get` 是
  模块私有方法，没有钩子能按脚本拦静态字段读。

仍然不修的（写进 README「仍然是限制的」）：`modFolders` 静默兜底、多 mod 的 `modFolder`、
Animate 2019+ 图集、对象过桥、每首歌重建 context、vanilla 无自动测试。

回归：Lua isolation 12 条、QuickJS smoke 28 / selfremove 29 / child 2，全绿。

### 0.1 未解决（2026-11-13 记录，之后没复核）：0.6.3 的 Options → Switch Engine 打不开

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

### 0.2 已结案（2026-11-17）：0.6.3 里 lua 创建贴图找不到资源

> 结论：不是路径问题，是图集格式不兼容（Animate 2019+ 的 `spritemap1.*`）。下面保留
> 2026-11-13 的排查记录，`Paths` 那三处修正本身是对的，别回退。

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

### 0.4 2026-11-13 那一轮做完的

- 三引擎并进同一个 exe（`1fd1c78`）
- 资产按版本分组：`assets/{body,1.0.4,0.6.3}`，`Project.xml` 三段对称声明（`6ef5666`）
- 0.6.3 去掉 lime 的 library selector，三棵树统一走普通路径（`fceb131`）
- 0.6.3 的 `checkFileExists` 多拼一层 `assets/`（`153ce24`）
- 构建脚本收口到 `building/`：`setup.sh` + `libs.txt` + `README`（`f766a51`）
- 清掉 `.workbuddy` 里四十多个一次性日志、`bin` 里的诊断残留

---

## 1. 项目是什么

Psych Engine 1.0.4 的源码 fork，目标是让 0.6.3 / 0.7.3 时代的老 mod（Lua + HScript）不改一行就能跑。
`.js` 有两条路：默认 Troll（把 JS 转译成 Lua 塞回 LuaJIT，兼容优先），
切到 QuickJS 后走真的 QuickJS-NG 运行时（`source_body/body/jsruntime/`，见 `docs/JS_QUICKJS.md`）。

同一个 exe 里并了三棵树（本体 / 原版 1.0.4 / 0.6.3），靠 `bin/engine.txt` 选。

- 仓库：`D:\FNF\FNF-PE_RealQuickJs_Engine`
- 上游参照：`.workbuddy/upstream/`（pe063 / pe073 / pe104 完整，novaflare 只有 `source/`）
- 审计工具：`bash manage.sh audit`（7 号功能，拿 `.workbuddy/upstream/` 当基准比 Lua 函数名）

## 2. 用户偏好（务必遵守）

- 中文、简短、能容忍速记式拼写；被叫停立即执行
- 报 bug 只给现象，**要自己定位根因，不要猜**；要求"验证过再说"
- 测试成本过高的功能整个删掉，不留死代码
- 不手写 UI，复用引擎原生控件；设置项文案只讲作用不讲设计理由
- 常 AFK，写好问题就走，期望自主推进、不要反复追问
- **`.workbuddy/` 是项目数据不是缓存，永远不要删**

## 3. 构建与测试

```bash
bash manage.sh release                 # 增量 release（= 2 号功能，约 1 分钟）
bash manage.sh debug                   # debug
bash manage.sh clean                   # 全量重编（先清 obj/src）
bash manage.sh env                     # 环境体检，缺库会自动补
bash .workbuddy/build.sh [-debug|-clean]   # 薄壳：翻译参数 + 裹 conhost --headless
```

`manage.sh` 现在是唯一的脚本（以前散在 `building/`、`tools/` 里的都并进来了）：
环境体检 → 补库 → `lime build windows` → 铺 `assets/base_game` 并校验。
**直接 `haxelib run lime build` 会失败**，缺 MSVC/SDK 的环境变量。

- hxcpp 缓存在 `.cache/hxcpp`，命中时直接拷 `.obj`
- `assets/base_game` 是编译**之后**才铺进 bin 的（`BASE_GAME_FILES` 故意留在 `Project.xml` 的 officialBuild 段）
- 无控制台环境（编辑器 / CI / 后台任务）要裹 `conhost --headless`，否则 haxe、cl、link
  各弹一个黑框。`.workbuddy/build.sh` 已经包好了，并且用临时文件把退出码带出来
  —— `conhost` 会把子进程退出码吃成 0
- 跑游戏/跑测试一律不弹窗：`AutoTestState` 把窗口最小化 + 挪屏幕外 + 静音，
  只有 `PE_AUTOTEST_SHOW=1` 才显示画面

回归（两条，别混）：

```bash
bash .workbuddy/run_test.sh [song]        # Lua / 兼容层
bash .workbuddy/run_qjs_test.sh [song]    # QuickJS 真运行时
PE_BUILD=debug bash .workbuddy/run_test.sh
NOPATCH=1 bash .workbuddy/run_test.sh     # 不给谱面打补丁
```

- 测试入口 `AutoTestState.hx` 由 `harness/apply_hook.py on/off` 临时拷进 `source_body/body/`，跑完自动撤
- 脚本放 `bin/mods/body/scripts/` —— **按版本分目录**，`bin/mods/scripts` 是扫不到的
- 结果写 `.workbuddy/testout/*.txt`，格式 `PASS|名字` / `FAIL|名字` / `ERR|...`
- 两个 runner 都会把 `engine.txt` 强制成 `body`、跑完还原：不强制的话 `Main.main()`
  走进 pe063/vanilla 分支，测试入口那个补丁不在那条路上，一个结果文件都不会有
- **cleanup 是白名单**：新增测试脚本必须同时加进 cleanup，否则会留在 `bin/mods` 里

**最近一次全绿（2026-11-16）**

```
edge 10/0   more 37/0   v073 58/0   v104 32/0   jssyntax 1/0
versiontag 1/0（带 %run_v_0.7.3 的脚本看到 0.7.3）
versionplain 1/0（不带标记的脚本仍是 1.0.4）
stage / notetype / event 三类脚本都正常
QuickJS 冒烟 26 项（run_qjs_test.sh）
```

## 4. 兼容层现在有哪些东西

分五层，改之前先确认改的是哪一层（详见 `docs/LUA_COMPAT.md` 第一节）：

> `.js` 那条是另算的：默认走 Troll 转译（转成 Lua 塞进 FunkinLua，所以上面五层全部继承），
> 切成 QuickJS 之后走 `source_body/body/jsruntime/`，那套桥的规则在 `docs/JS_QUICKJS.md`。

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
- **PlayState 拆分**：3745 → 2821 行，25 个函数搬到 `source_body/body/states/play/`（Events / Camera / Judge），
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
7. **hxcpp 的反射不调用 getter**。flixel 里 `FlxTypedSpriteGroup.members` 是
   `var members(get, never)`，用 `Dynamic` 取只会拿到 null，接着 `.indexOf()` 就是
   Null Object Reference（0.7.3 的 `getObjectOrder` 就栽在这，见 `FunkinLua.memberArray()`）。
   同一个家族还有 `FlxText.width`：create 阶段它等于 `fieldWidth`，别拿它算居中。
8. flixel 5.6 的 `FlxGroup` / `FlxSpriteGroup` **不是泛型类**，写成 `FlxGroup<FlxBasic>`
   会报 "Too many type parameters"。
9. `conhost --headless` 会把子进程的退出码吃成 0，用它包命令必须另想办法把真状态带出来。
10. 同名 mod 在版本目录和其他位置各留一份会被加载两遍（两套 lua/hscript 同时跑），
    以前 global 机制下实测直接把游戏跑崩 —— 这也是删掉那个机制的原因之一。
11. 别用 `bmp.draw(FlxG.game)` 截屏做布局验证：`allow-high-dpi` + RatioScaleMode 下
    拿到的是放大 1.5 倍又被裁掉的图，看着像排版错了，其实屏幕上是对的。
12. 崩溃屏、启动屏这类**要跨三棵树共用**的 state 只能用 flixel 原生控件，
    不能碰各树的 `Button` / `Alphabet`；而且 `create` 里必须
    `FlxG.cameras.reset()`，否则会带着上一个 state 的 zoom/scroll 摆版。

## 6. 已知未修

- ~~`weeb/` / `pauseAlt/` / `ui/` / `philly/` 素材在 bin 里不存在~~ —— 2026-11-13 晚修好：
  根因是 `assets/base_game`（官方素材单一源，713 个文件）没被铺进 `bin/assets/<版本>/`，
  连带两棵 1.0.4 树的 `shared/weeks/*.json`、`week*`、`songs`、`characters` 全都缺。
  现在由 `manage.sh` 的铺素材步骤（5 号功能）用硬链接补齐，已核对三棵树 0 缺。
- `noteSplashes` 的老式扁平图集如果**和 1.0 内置皮肤同名**，仍会被解析到内置皮肤（优先能加载的那个）。
- `FlxUIDropDownMenuCustom` 这类依赖 flixel-ui 的类，1.0 已经没有对应库，接不了。
- 画面层面的兼容（贴图位置、动画观感、UI 层级）这套测试看不出来，只能人眼验。
- 备选没做：virtualPad 移植、lua 报错去重、`NotesSubState` —— 用户没点头就不要动。
- ~~`run_test.sh` 跑不起来~~ —— 2026-11-16 修好：`patch_chart.py`、测试脚本目录、
  素材目录全都停在双引擎改造前，要加 `mods/body/`、`assets/body/` 这一层。修完 140 条断言全绿。
- `run_test.sh` / `run_qjs_test.sh` 都在 `.workbuddy/` 里，**git 不跟踪**，换机器要自己带。
- JS 那三个 Haxe 互操作函数（`runHaxeCode` / `runHaxeFunction` / `addHaxeLibrary`）没做，
  要做的话得给 `JSScriptHost` 挂一个嵌入式 HScript（`HScript.new` 的 parent 是 `Dynamic`，
  只用 `scriptName` / `modFolder` / `lastCalledFunction` / `hscript` / `get` 五个东西）。

## 7. git 状态

2026-11-16 之后的四笔（都在 master 上，已推不推看用户）：

```
f4a79b3 compat: 修 0.7.3 的 getObjectOrder 在 HUD 元素上必崩
353852b mods: 去掉 mods/global 全局机制，每个引擎只读自己的
e1b57fe engine: global mod 三树通用、崩溃拦截器、兼容开关并进 gameplay
e0a7aab js: QuickJS 通道补完取值/停止/装卸，宿主函数对齐 Lua
```

工作区干净。`export/` 里是编译产物，`.workbuddy/` 整个被 ignore（测试脚本、记忆、构建壳都在
里面，搬机器要单独拷）。
