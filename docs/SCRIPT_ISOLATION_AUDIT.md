# 脚本隔离审计 — 三棵树

> 2026-11-17。谁改 `Paths` / `ScriptClassAliases` / `IsolatedImports` / `Paths.findScriptFile`
> 之前先扫一遍这张表；改完把状态那一列更新掉。

三棵树（`source_body` / `source_vanilla` / `source_063`，`source/` 是公共层）编在同一个 exe 里，类名、资源路径、脚本名都长一个样，
只有 `Paths.VERSION_DIR` 和源码目录不同。所以「隔离」不是靠命名空间，是靠**每一处查找都自己
记得加树前缀**——少加一处就串，串了还往往不报错（`assets/body` 里装的就是 1.0.4 官方素材）。

标记：**已修** = 本轮改过并跑过回归；**设计** = 故意的，别当 bug 改；**开着** = 已知未修。

---

## 1. 脚本文件查找

| # | 位置 | 问题 | 后果 | 状态 |
|---|---|---|---|---|
| 1.1 | `Paths.findScriptFile` (`Paths.hx:213`) | 缺 `currentLevel` 那一级 | `scripts/` 目录扫得到 `<level>/scripts/`，按名字却找不到 | 已修 |
| 1.2 | `FunkinLua.findScript` (`FunkinLua.hx:1979`) | 走 `Paths.getPath`，没有 `assets/<ver>/` 根兜底 | 0.6.x 扁平布局下 `isRunning`/`addHScript` 找不到脚本 → 判重失效 → 重复加载 | 已修 |
| 1.3 | 同上 | 扩展名判断区分大小写 | `'X.LUA'` 被拼成 `'X.LUA.lua'`，直接报不存在 | 已修 |
| 1.4 | `PlayState.create` 的 scripts 目录扫描 | 手工拼 `folder + file`，绕过 `findScriptFile` **且完全不判重** | 同一脚本"放在 scripts/ 里 + 再 addHScript 一次"必然两份 | 已修（统一判重） |
| 1.5 | `startCharacterScripts` | 手写 mod→shared 两层 + `Iris.instances` 判重 | 找不到根目录那一级；`Iris.instances` 是进程级表，上一首歌的残留会让新歌脚本静默不跑 | 已修（改走 `startLuasNamed`/`startHScriptsNamed`） |
| 1.6 | 判重比较 | Lua/HScript 字符串直比（区分大小写），JS 用 `toLowerCase` | Windows 下 `exists` 不区分大小写但返回传入的字符串 → 同文件两份 | 已修（`Paths.sameScript`） |
| 1.7 | `Paths.modFolders` (`:560`) | 当前 mod 里没有就**静默**退到 `mods/<ver>/` | 路径拼错不报错，命中版本共享目录的同名文件；`mods/<ver>/` 同时是共享目录和所有 mod 的兜底 | 设计（但见 1.9） |
| 1.8 | `Mods.currentModDirectory` | 全局单值，`modFolders` 调用时现读 | 相对路径是运行时绑定，不是加载时绑定；换歌/换 mod 后同名解析到不同文件 | 设计 |
| 1.9 | `Paths.currentLevel` | 全局，只有 `LoadingState` 设；PlayState 退出到菜单走的是直接 `switchState`，不经过它 | 菜单里的图会先去上一首歌的 week 目录找，有同名文件就显示错的 | 已修（`MusicBeatState.switchState` 里对非 PlayState 的目标复位成 `shared`） |
| 1.10 | `Paths.modFromScriptPath` (`:584`) | 只认 `name == currentModDirectory`，否则 null；绝对路径靠 `indexOf('/mods/')` 猜 | 非当前 mod 的脚本 `modFolder` 恒 null；`mods/<ver>/scripts/` 里的脚本读不到自己的 pack.json | 设计（多 mod 场景待重做） |

## 2. 类解析（hscript `import` / 裸名 / lua 反射）

| # | 位置 | 问题 | 后果 | 状态 |
|---|---|---|---|---|
| 2.1 | `ScriptClassAliases.resolveDeep` (`:358`) | 兜底只按 `backend./objects./states./…` 这些 **body 包名**去猜 | vanilla 模式下未知裸名拿到 body 类 → 那个类的 `Paths` 指向 `assets/body` | 已修（vanilla 模式只认 `vanilla.` 前缀） |
| 2.2 | `ScriptClassAliases.resolve` (`:276`) | 不过滤解析结果属于哪棵树 | body 模式能拿到 `vanilla.*`；vanilla 模式表里映射失败时能悄悄拿 body 类 | 已修（`isForeignTree`） |
| 2.3 | `ScriptClassAliases.init` | 只往 `Iris.proxyImports` 里塞，不清理 | 进程级静态表里的别树条目会让那个名字永远拿错类，且和注册顺序有关 | 已修（`sweepForeignImports`） |
| 2.4 | vanilla `CustomInterp.resolve` (`HScript.hx:570`) | 未知标识符直接报 `EUnknownVariable`，没有兜底；而 `import` 那条一旦落空就回 `Type.resolveClass` → body 类 | vanilla 模式下 hscript 静默用 body 的类，资源从 `assets/body` 出 | 已修（兜底走 `LuaUtils.resolveClass`，只认 `vanilla.*`） |
| 2.5 | `vanilla.psychlua.IsolatedImports` | 是 `manage.sh` 功能 10 **扫目录生成**的静态表（239 条），不是运行时枚举 | 新增 vanilla 类后忘了重跑生成 → hscript `import` 落回 body | 已修（正确性不再依赖这张表：2.9 的 override 拦在 `import` 的落点上，表退化成缓存） |
| 2.6 | `IsolatedImports.register` (`:262`) | 简单名注册时 `if exists(simple) continue`，撞名就跳过 | 同名两个类时只映射一个（有意的，但没日志） | 设计 |
| 2.7 | pe063 `FunkinLua.resolveClass` (`:101`) | 命中 body 类就 `return null`，不再试扁平同名类 | `objects.Note` → 明明有 `pe063.Note` 却返回 nil，脚本拿到 nil 后 `setProperty` 写成 0 | 已修（先剥包名再试 `pe063.<简单名>`） |
| 2.8 | HScript | 没有 `%run_v_0.7.3` 版本伪装，只有 Lua/JS 有 | 按引擎版本分支的 `.hx` 脚本永远看到真实版本 | 已修（`version` 全局，`HScript.parseVersionTag`） |
| 2.9 | vanilla `CustomInterp.getOrImportClass` / body 同名方法 | `import` 的落点是 `proxyImports` → `Tools.getClass` → `Type.resolveClass`，后两步会命中另一棵树 | 上表 2.1~2.7 都是在「查表之后」补救，表本身漏了就没人挡 | 已修（两棵树各自 override：解析结果属于别树就按本树规则重指，指不到返回 null） |

## 3. 资源路径

| # | 位置 | 问题 | 后果 | 状态 |
|---|---|---|---|---|
| 3.1 | 三份 `Paths` | `VERSION_DIR` 编译期写死：`body` / `1.0.4` / 063 用 `getPreloadPath()` | 这是隔离本身：谁调谁的 `Paths` 就进谁的目录 | 设计 |
| 3.2 | `Project.xml:164` | `assets/base_game`（1.0.4 官方素材）**以 `assets/body` 的名字**进清单 | 串树时不报 404，直接返回另一棵树的图；vanilla/063 在清单里查不到官方素材，只能靠 `manage.sh` 硬链接落盘 | 设计（但这是"串味不报错"的根源） |
| 3.3 | 063 `Paths.getPath` (`:137`) | 不校验文件是否存在，直接返回 `assets/0.6.3/<file>` | 调用方必须自己 `exists`；漏一处就退化成"路径有了但文件没有" | 设计（0.6.3 原样保留） |
| 3.4 | 063 `Paths` 的三处清单检查 | 已全改走 `existsOnDiskOrManifest` | `mods/` 和构建后才铺的素材以前一律判缺失 | 已修（2026-11-13） |
| 3.5 | `makeAnimatedLuaSprite` / `AtlasFrameMaker` | 探针实测：官方图集（靠 week 目录）和 mod 图集（`mods/0.6.3/probe`）都能算出正确路径，`construct` 都出了 98 帧 | **不是路径问题**。剩下「贴图出不来」只可能是图集格式：0.6.3 明说不支持 Animate 2019+ 的 `spritemap1.*`，那种 mod 在真 0.6.3 上也一样不可见 | 已定位（不修，见下） |

## 4. 装载与卸载

| # | 位置 | 问题 | 后果 | 状态 |
|---|---|---|---|---|
| 4.1 | `startLuasNamed` / `startHScriptsNamed` | 只认本 state 里活着的脚本（`luaArray` / `hscriptArray`） | 这是对的，别再用 `Iris.instances`（进程级、重名加 `_1` 后缀、取不回来） | 设计 |
| 4.2 | `callOnScripts` | `closed` 的 lua 在下次分发时才从数组里摘掉 | 一次性脚本要等到下一次回调才真正移除 | 设计 |
| 4.3 | `removeHScript` | `destroy()` 后对象还留在 `hscriptArray`（`origin` 被清成 null） | 每次分发都要靠 `exists()` 兜一次 | 已修（destroy 后从数组摘掉；`callOnHScript` / `allScripts` / `setOnHScript` 都跳过 `isClosed()`） |
| 4.4 | `JSPlayer.loadFile` | 每个 .js 一个独立 context，`beginSong()` 每首歌重建 | 上一首的回调不会带到下一首 | 设计 |

---

## 第三轮：README「已知限制」清账（2026-11-17 晚）

| # | 位置 | 问题 | 状态 |
|---|---|---|---|
| 2.10 | vanilla `FunkinLua` 构造 | 仍用上游 `split('/')[0] + '/' == Paths.mods()` 推 modFolder，撞上 `mods/1.0.4/` 这层目录永远不成立，vanilla 树所有脚本 `modFolder` 恒 null | 已修（`vanilla.backend.Paths` 补 `modFromScriptPath`，构造改调它） |
| 3.6 | `QuickJSHandler` 128 / 129 / 219 | `getTextFromFile` / `readJson` 直接查 CWD，`saveFile` 走 `Paths.mods`，`deleteFile` 走 `Paths.getPath` —— 同一通道三套口径，写进去的文件读不回来 | 已修（全走 `Paths`；`readJson` 补 `.json` 后缀回退，返回文本由脚本 `JSON.parse`） |
| 3.7 | `QuickJS.hx` 的 `@:buildXml` / `@:cppFileCode` | 写死 `D:/FNF/...` 绝对路径，靠 `manage.sh` 用 `sed` 对齐，换机器/挪仓库必炸 | 已修（改成相对 hxcpp 构建目录，和 `QuickJSHandler` 同款；`manage.sh` 的 sed 段已删） |
| 4.5 | `QJS_MAX_CTX` | 32 个 context 上限 | 已提到 64 |
| 4.6 | `JSPlayer.emitTo` | 事件只转发第一个参数 | 已修（按桥支持的六种形态转发最多三个参数） |
| 2.11 | HScript `psychEngineVersion` | 直读静态字段拿不到 `(%run_v_)` 伪装值 | 部分修（补 `version` / `psychEngineVersion` 两个全局；静态字段读没法拦，`Interp.get` 是模块私有） |

还开着的（设计 / 需大改）：`modFolders` 静默兜底、`modFromScriptPath` 只认当前 mod、
Animate 2019+ 图集、对象过桥、每首歌重建 context、vanilla 无自动测试。

## 本轮改了什么（2026-11-17）

**第一轮：查找链 + 类解析**

- `Paths.findScriptFile`：补 `currentLevel` 一级，和 `getPath` 的顺序对齐。
- 新增 `Paths.scriptKey` / `Paths.sameScript`：判重统一为「斜杠归一 + 小写」，null 不相等。
- `FunkinLua.findScript`：改成直接调 `findScriptFile`（旧的绝对路径 / CWD 相对路径兜底保留），
  扩展名判断不再区分大小写。
- `PlayState`：新增 `isLuaScriptRunning` / `isHScriptRunning`；目录扫描、`startLuasNamed`、
  `startHScriptsNamed` 全部走它们；`startCharacterScripts` 改成两个调用。
- `ScriptClassAliases`：`resolve` / `resolveDeep` 拒绝另一棵树的类；vanilla 模式只认 `vanilla.`
  前缀；body 模式清扫 `proxyImports` 里的别树条目。
- vanilla `CustomInterp.resolve`：未知标识符兜底走 `LuaUtils.resolveClass`（只认 `vanilla.*`）。
- vanilla `IsolatedImports.register`：先清 `proxyImports` 里指到 body 的引擎类条目，再灌自己的表。
- pe063 `resolveClass`：撞树不再直接放弃，先剥包名试 `pe063.<简单名>`。

**第二轮：把「还开着的」清掉**

- **2.9 两棵树各自 override `getOrImportClass`**：这是最关键的一处。以前所有防线都在
  「查完表之后」，而 `import` 的默认落点是 `proxyImports` → `Tools.getClass` →
  `Type.resolveClass`，后两步照样命中另一棵树。现在 body 拿到 `vanilla.*`/`pe063.*`
  就按本树规则重指、指不到给 null；vanilla 反过来只认 `vanilla.*`。
  `IsolatedImports` 从「正确性依赖」降级成「缓存」。
- **1.9 `currentLevel` 复位**：`MusicBeatState.switchState` 里，目标不是 PlayState 就
  挂回 `shared`（body / vanilla 两份都改了）。`LoadingState` 先设、再切 PlayState，不受影响。
- **2.8 hscript 版本伪装**：`HScript.preset()` 塞 `version` 全局，规则和 `FunkinLua.parseVersionTag`
  一致（`(%run_v_x.x.x)`）。注意只覆盖 `version` 这个全局，脚本直接读
  `MainMenuState.psychEngineVersion` 还是真实值 —— 静态字段没法按脚本伪装，除非改成
  每脚本一份代理，代价比收益大。
- **4.3 `removeHScript`**：`destroy()` 之后从 `hscriptArray` 摘掉；`callOnHScript` / `allScripts` /
  `setOnHScript` 都跳过 `isClosed()`，不再靠 `exists()` 碰运气。
- **3.5 0.6.3 贴图**：见下一节，结论是**不是路径 bug**。

## 0.6.3 那个「lua 贴图出不来」的结论

新加了探针 `source_063/pe063/debug/Probe.hx`（`PE_063_PROBE=1` 触发，
`bash .workbuddy/run_063_probe.sh` 跑）。它不进游戏、不建 state，把 `AtlasFrameMaker`
用到的路径算出来并真的构造一次图集。实测：

```
--- key=cutscenes/stressPico  level=week7  mod=
  fileExists(images/cutscenes/stressPico/spritemap.json) = true
  getTextFromFile(images/cutscenes/stressPico/Animation.json) != null = true
  getPath(...) = assets/0.6.3/week7/images/cutscenes/stressPico/spritemap.png
  construct = 98 frames
--- key=characters/stressPico  level=shared  mod=probe
  ... construct = 98 frames
```

官方图集（靠 week 目录找）和 mod 图集（现造一个 `mods/0.6.3/probe`）**都正常**，
`images/` 也没有被拼两遍。所以 0.2 悬案不是路径问题。

剩下的可能性只有一个：**图集格式**。0.6.3 的 `AtlasFrameMaker` 开头就写死了只认
Adobe Animate 2018 的单个 `spritemap.json`，碰到 2019+ 的 `spritemap1.json` 会
`addTextToDebug("Only Spritemaps made with Adobe Animate 2018 are supported")` 然后返回 null ——
而 0.7+ 时代的 mod 基本都是 `spritemap1`。那种 mod 在**真 0.6.3 上也一样不可见**，
不是兼容层弄坏的。

要支持得把 0.7+ 的 `AtlasFrameMaker`（多 spritemap / `SpriteAnimationLibrary`）搬过来，
那是加功能，不是修 bug。没做。

## 还开着的

1. **2.8 的边角**：hscript 直读 `MainMenuState.psychEngineVersion` 拿不到伪装值（见上）。
2. **1.10 多 mod**：只扫「当前 mod」的 `scripts/`，多 mod 同时启用时非当前 mod 的脚本
   `modFolder` 恒 null。要重做 `Mods` 的当前-mod 模型，动起来面大。
3. **3.5 的加功能版**：支持 Animate 2019+ 图集（上面说的移植）。

## 怎么验证

```bash
bash .workbuddy/run_test.sh            # Lua/兼容层，含 isolation.txt（10 条）
bash .workbuddy/run_qjs_test.sh        # QuickJS 通道
bash .workbuddy/run_063_probe.sh       # 0.6.3 路径探针（不进游戏）
```

`isolation.txt` 覆盖：`Paths.VERSION_DIR` 是 body、`vanilla.*` 类拿不到、assets 根脚本的
`isRunning`、大小写不同的 `isRunning`、`scripts/` 目录脚本的 `isRunning`、`addHScript` 不重复建实例、
hscript 的 `%run_v_` 版本标记（带/不带两种）、`removeHScript` 之后 `isRunning` 立刻为 false。

vanilla 分支仍然没有自动入口，只能人工开机验；pe063 有探针，但它只验路径/图集，
不跑 PlayState。