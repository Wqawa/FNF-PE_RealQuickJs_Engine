# Lua 兼容层

目标：0.6.3 / 0.7.3 时代的 mod 脚本，丢进 1.0.4 里不改一行还能跑。

这份文档分两块：**兼容层是怎么摆的 / 怎么核对它齐不齐**，以及**改过什么、为什么改**。

---

## 一、兼容层分层

脚本能碰到的东西有四类，兼容代码按这个分层放：

| 层 | 位置 | 管什么 |
|---|---|---|
| 函数 | `psychlua/` 下各 `*Functions.hx`、`FunkinLua.hx` | `add_callback` 注册的 250 多个 Lua 函数 |
| 同名不同义 | `psychlua/DeprecatedFunctions.hx`、`psychlua/ReflectionFunctions.hx` | 名字没变但参数含义变了的，做成「两种写法都认」 |
| 类名 | `backend/ScriptClassAliases.hx` | 0.6.3 扁平源码树里的裸类名（`Boyfriend`、`ClientPrefs`…） |
| 设置字段 | `backend/ClientPrefs.hx` | 0.6.3 是静态字段，1.0 收进了 `data` |
| 对象 / 字段 | `states/PlayState.hx`、`objects/Bar.hx` | `healthBarBG`、`modchartSprites`、`uiGroup` 展开、Bar 尺寸 |

`DeprecatedFunctions.implement()` 在 `FunkinLua` 初始化里排在最后一段 —— `Lua_helper.add_callback`
是往 Lua 全局表里塞同名函数，晚注册的覆盖早注册的，所以那里可以安全地"重写"已有函数，
不用去改原实现。

---

## 二、审计

```bash
# 基准源码先拉一份（不用放进仓库）
git clone --depth 1 --branch 0.6.3 https://github.com/ShadowMario/FNF-PsychEngine .workbuddy/upstream/pe063

bash manage.sh --zh 8  # 原 tools/lua_compat_audit.py --ref .workbuddy/upstream/pe063/source --label "PE 0.6.3"
```

工具干四件事，全部静态比对，不跑游戏：

1. **回调名**：基准有的、我们没有的
2. **签名**：只报真会炸的（我们要求传的参数比老 mod 多，或者根本接不住那么多参数）
3. **裸类名**：0.6.3 `source/` 根目录下的类，看有没有别名或同名类
4. **全局变量**：`FunkinLua` 构造函数里 `set('x', ...)` 塞给 Lua 的那些（`curBpm`、`cameraX`…）

它会先剥注释再扫 —— 这是个坑：0.6.3 里 `getGlobals`、`getPropertyAdvanced`、`setPropertyAdvanced`
**本来就是注释掉的**，不剥注释会得出"我们缺 3 个函数"的错误结论。

### 当前覆盖度

| 基准 | 回调 | 签名冲突 | 裸类名 | 全局变量 | ClientPrefs |
|---|---|---|---|---|---|
| 0.6.3 | 0 缺 | 3 | 10 未映射 | 0 缺 | 0 缺 |
| 0.7.3 | 0 缺 | 0 | 3 未映射 | 0 缺 | — |
| 1.0.4 | 0 缺 | 0 | 0 | 0 缺 | — |

剩下的「未映射类名」都是 1.0 里已经不存在的类（`Section`、`MultiCallback`、`NotesSubState`、
`FlxUIDropDownMenuCustom` 这种），没有能对应的现代目标，`resolve()` 返回 null 并打红字。
「签名冲突 3 条」是 `debugPrint` / `makeGraphic` 这类参数增减，见下面的修复记录。

---

## 三、修复记录

每轮都是：写 0.6.3 风格 + 1.0.4 风格的 Lua 脚本 → 自动开局跑 → 看哪条炸了或值不对 → 改 → 重新编译再跑。
脚本在 `.workbuddy/luatest/scripts/`（不入库），结果写 `.workbuddy/testout/`。

### 第 1 轮

v073 失败 7 条、v104 失败 9 条。剔掉我测试写错的，真正的问题两个：

**1. `Bar` 的 width/height 写得进去，读出来不对** — `objects/Bar.hx`

0.7 起 `timeBar` / `healthBar` 从 `FlxBar` 变成 `Bar extends FlxSpriteGroup`。fork 已经补了
`set_width` / `set_height` 转发到 `barWidth` / `barHeight`，但没补 getter：

- `FlxSpriteGroup.get_width()` 量的是所有子对象的包围盒
- 背景条 `bg` 被撑成 `barWidth + 6`（左右各 3px 边框）

`setProperty('timeBar.width', 500)` 之后读回来是 **506**。老脚本里
`setProperty('healthBar.width', getProperty('healthBar.width'))` 这种写法每次都胖 6px。

修：补 `get_width` / `get_height` 返回 `barWidth` / `barHeight`。

**2. `setLuaSpriteCamera` 直接抛异常** — `psychlua/DeprecatedFunctions.hx`

```
CALLBACK ERROR! Exception: Invalid field:cameras
```

老代码是 `MusicBeatState.getVariables().get(tag).cameras = [...]`。`variables` 是
`Map<String, Dynamic>`，取出来是 `Dynamic`；而 `cameras` 在 `FlxBasic` 上是 `(get, set)` 属性、
背后叫 `_cameras`，没有同名实字段，hxcpp 走动态 `SetField` 找不到字段就抛了。
旁边的 `setObjectCamera` 因为先 `var real:FlxBasic` 接了类型，所以一直是好的。

修：赋值前 `cast` 成 `flixel.FlxBasic`。

### 第 2 轮

两处改完重编译，v073 71 项、v104 34 项，`failed=0`。

### 第 3 轮

开始照 `FunkinJS`（`.js` 脚本层）。扔了个 `js_probe.js` 进去，游戏弹窗卡死：

```
[string "-- FunkinJS 冒烟测试：..."]:8: 'then' expected near 'saveFile'
```

**3. 转译器只删花括号，不补 `then` / `do`** — `psychlua/FunkinJS.hx` → `transpile()`

它把 `{` 丢掉、`}` 换成 `end`，但 Lua 要 `if (x) then`。所以**只要脚本里有 if 就一定跑不起来**，
README 那个例子刚好只有函数体，没暴露。

修：遇到代码块的 `{` 往前看，括号条件是 `if` / `elseif` 补 ` then`，`while` / `for` 补 ` do`
（`function` / `else` / `do` 本来不用补）。

**4. `else` / `else if` 翻出来是非法 Lua**

`} else {` 会翻成 `end else`，Lua 里 `end` 后面不能挂 `else`。这个改动前就存在。

修：`}` 往后看一个 token，是 `else` 就不写 `end`（`else if` 写成 `elseif` 并把 `if` 吃掉），
块结尾的 `end` 由最后一个 `}` 收。

### 第 4 轮

把审计工具做出来之后，按报告补齐：

**5. `comboStacking` 没有静态转发** — `backend/ClientPrefs.hx`

0.6.3 是 `ClientPrefs.comboStacking`，1.0 收进 `data` 但 fork 的转发表漏了这个。
补上静态属性。

**6. `debugPrint` 第二个参数语义变了** — `psychlua/DeprecatedFunctions.hx`

0.6.3：`debugPrint(text1, text2, ... text5)` 全部拼起来打印。
1.0.4：`debugPrint(text, color)`。

老 mod 写 `debugPrint('hp', hp)`，新签名会把 `hp` 当颜色、文本直接丢掉。
修：参数多于两个 → 老写法拼起来；只有第二个参数且长得像颜色（颜色名 / 6~8 位十六进制）→ 新写法。
`debugPrint('text', 'RED')` 这种老代码会被当成颜色，属于取舍。

**7. `removeFromGroup` 第三个参数类型冲突** — `psychlua/ReflectionFunctions.hx`

0.6.3：`removeFromGroup(group, index, dontDestroy)`，第三参是 Bool。
1.0.4：`removeFromGroup(group, index, tag, destroy)`，第三参是 String。

`removeFromGroup('myGroup', 0, true)` 在新签名里 `true` 会被塞进 `tag:String`。
修：第三参改 `Dynamic`，是 Bool 就按老语义（`destroy = !dontDestroy`），否则当 tag。

**8. 三个杂项全局变量没有** — `psychlua/FunkinLua.hx`、`states/PlayState.hx`

`cameraX` / `cameraY`（老 mod 做视差用）、`inChartEditor`。前两个要在 `PlayState.update` 里每帧刷。

**9. 四个裸类名没有映射** — `backend/ScriptClassAliases.hx`

`OutdatedState`、`VisualsUISubState`、`AttachedFlxText`、`ModchartText`。
分别指到 `OutdatedSubState`、`VisualsSettingsSubState`、`AttachedText`、`FlxText`。

**10. 脚本报错会弹模态框卡住整个游戏** — `psychlua/FunkinLua.hx`

Windows 上原来走的是 `Application.current.window.alert(...)`：任何一个 mod 脚本写错一个字符，
就弹一个对话框把整个游戏停在那儿等人点确定 —— 而且是在 `PlayState.create` 循环里，后面所有脚本都不执行。

修：改成 `trace` + 屏幕红字（`addTextToDebug`），错误信息不变，不再拦人。

验证：往 `mods/scripts/` 里放一个语法错误的 `broken_probe.lua`，其余 137 项依旧全过。

### 第 5 轮：stage / notetype / event 三类脚本

这三类脚本走的是同一个入口 `startLuasNamed()` / `startHScriptsNamed()`，所以先对了一遍三个版本
从这里找文件的顺序：

| 版本 | 查找顺序 |
|---|---|
| 0.6.3 | `Paths.modFolders()` → `Paths.getPreloadPath()` = **`assets/<file>`** |
| 0.7.3 | `Paths.modFolders()` → `Paths.getSharedPath()` = `assets/shared/<file>` |
| 1.0.4 | 同 0.7.3，另外多一个 `.js` 回退 |

**11. 0.6.x 的 `assets/` 根目录找不到了** — `states/PlayState.hx`

0.6.3 的 `getPreloadPath()` 就是 `'assets/' + file`，1.0 改成了 `assets/shared/`。
所以老 mod 把 `stages/x.lua`、`custom_notetypes/x.lua`、`custom_events/x.lua` 直接放在
`assets/` 下的，升级后**静默不加载**——不报错，就是脚本不跑。

修：`startLuasNamed()` 和 `startHScriptsNamed()` 在 mods / shared 都找不到之后，最后兜一次
`'assets/' + file`。`.js` 那条分支也补了。

顺带确认了两件事（不是 bug，别再查）：

- 0.6.3 的内置事件 `Philly Glow` / `Kill Henchmen` / `Trigger BG Ghouls` / `BG Freaks Expression` /
  `Dadbattle Spotlight`，1.0.4 已经挪进各 `BaseStage` 子类的 `eventCalled()` 里了，全都还在。
- 自定义事件脚本的 `onEvent` 跟引擎有没有实现那个事件无关，`callOnScripts('onEvent', ...)` 照发。

**12. 测试跑久了会「假死」** —— 不是引擎问题，是测试姿势问题

窗口挪到屏幕外之后会失焦，flixel 默认 `FlxG.autoPause = true`，一失焦 update 就停。
表现是 `onBeatHit` / `onStepHit` 计数停在个位数，看着像 PlayState 卡死，其实是被暂停了。
测试入口里已经 `FlxG.autoPause = false`。

顺带记一笔：`onUpdatePost` 那种每秒 60 次的回调**不要每次都写盘**，只记数字，
等别的回调触发时一起 dump，否则光文件 I/O 就能把帧率拖垮。


### 第 6 轮：HScript 全局 / 视频类名

**13. HScript 里 `Reflect` 是未定义变量** — `psychlua/HScript.hx`

Iris 的 `preset()` 只塞了 `Std` / `Math` / `StringTools`，0.6.x 脚本里直接写的
`Reflect.getProperty(...)` 在新版会报 `Unknown variable: Reflect`。
补了 `Reflect` / `Lambda` / `Date` / `EReg` / `StringBuf` / `Json` / `Sys` / `Bytes`，
外加几个常被当全局用的 flixel 类（`FlxObject`、`FlxRect`、`FlxAngle`、`FlxStringUtil`、
`FlxSpriteUtil`、`FlxSave`、`FlxSound`）。`FlxPoint` 是 abstract，不能当值传，没加。

**14. 类名当值用（`Type.getClassName(Boyfriend)`）** — `backend/ScriptClassAliases.hx`

别名表原来只喂给 `Iris.proxyImports`，所以 `import` 和 `new` 能解析，但直接把类名当值用
（`Type.getClassName(Boyfriend)`、`GitarooPause.instance`）仍然是 `Unknown variable`。
新增 `applyToHScript()`，在 `HScript.preset()` 里把整张表倒进变量表。

**15. 视频类名整条线没了** — `Project.xml` + `source/hxcodec/`

两个问题叠在一起：

- `VIDEOS_ALLOWED` 写在 `<section if="officialBuild">` 里，源码 fork 不传 `officialBuild`，
  所以 `hxvlc` 根本没进构建，`VideoSprite` / `startVideo` 全是空壳。
- 1.0 用 hxvlc，老 mod 写的是 `import hxcodec.flixel.FlxVideo;`（3.x）或
  `hxcodec.VideoHandler`（2.6），名字对不上。

修：把 `VIDEOS_ALLOWED` 移出 `officialBuild` 段；新增 `source/hxcodec/flixel/FlxVideo.hx`
（hxvlc 的 `Video` 做底，保留 `play/pause/resume/stop/dispose/onEndReached/bitmapData`），
`hxcodec.VideoHandler` 和 `vlc.MP4Handler` 作为老名字的壳，并在别名表里挂上。

顺带补了 2P Engine 的 `precacheVideo(videoName, ?tag)` —— hxvlc 没有预解码，
这里只做路径校验，至少老 mod 不会因为函数不存在报 nil。

### 第 7 轮：审查文档（COMPAT_REVIEW.md）挑出来的四个雷

**16. `debugPrint` 的 8 位数字被当颜色吞掉** — `psychlua/DeprecatedFunctions.hx`

`looksLikeColor` 认 6/8 位纯 hex 字符，而十进制 8 位数（`16711680` 这种）恰好全是合法
hex 字符，`debugPrint('id', 16711680)` 数值会被判成颜色。查了 1.0.4 上游：`debugPrint`
的 color 参数签名就是 `String`，数字永远不可能是合法的新语义颜色——所以 Int/Float
第二参直接走老拼接分支，零代价。另加逃生门：环境变量 `PE_DEBUGPRINT_LEGACY=1`
强制全走老语义，猜错的 mod 不用改引擎源码。

**17. 裸名 `PhillyGlow` 的错误映射删了** — `backend/ScriptClassAliases.hx`

0.6.3 的 `PhillyGlow.hx` 是个模块名，里面只有 `PhillyGlowParticle` / `PhillyGlowGradient`
两个类，裸名 `PhillyGlow` 从来不是类。原来错挂 `shaders.BlendModeEffect` 的那条
（NovaFlare 的错误映射抄进来的）已删——`new PhillyGlow()` 会得到一个明确的
"类不存在"，好过拿到一个错的对象烂在运行时。

**18. `applyToHScript` 不再倒带点的 key** — `backend/ScriptClassAliases.hx`

`stages.Spooky` 这类带点的 key 是模块路径，hscript 里按字段路径表达式解析，
根本不走变量表，倒进去取不出来。现在只倒裸名。

**19. 三份复制粘贴的脚本路径查找收敛成一份** — `backend/Paths.hx`

`startLuasNamed` / `.js` 兜底 / `startHScriptsNamed` 三处各抄一遍
"mods → shared → assets 根"，现在统一走 `Paths.findScriptFile()`。顺带修了三件事：

- `startHScriptsNamed` 的 `#else` 分支原来裸用 `sys.FileSystem`，非 sys 目标
  编译直接过不了（H5），现在函数内部的系统调用全部配了 `#if`。
- 相对路径依赖进程 CWD 是 bin 目录，从快捷方式拉起时未必成立；
  sys 目标上找不到时会按 exe 所在目录锚定重试一遍。
- 存在性判断统一用 `existsOnDiskOrManifest`（桌面端先磁盘后清单），
  跟 `Paths.getPath` 的口径一致。

### 第 8 轮：皮肤路径 / 脚本版本标记（2026-11-10）

**20. 内置皮肤被挪进了子目录** — `objects/Note.hx`、`objects/NoteSplash.hx`、`objects/StrumNote.hx`、`states/LoadingState.hx`

0.6.x / 0.7.x 的 `arrowSkin` / `splashSkin` 写的是 `images/` 根下的裸名（`NOTE_assets`、`noteSplashes`），
1.0 把内置皮肤拆进了 `noteSkins/` 和 `noteSplashes/`，同名文件已经不在原位，老谱面会直接丢箭头 / 丢 splash。

- `Note.resolveNoteSkin()`：裸名先按原路径找，找不到再试 `noteSkins/<名字>`；带 `/` 的显式路径不动。
  `Note.reloadNote()` / `StrumNote` / `LoadingState` 的预加载都走它（预加载不归一化的话，正式加载有兜底但预热白做）。
- `NoteSplash.loadSplash()`：同上，再试 `noteSplashes/<名字><皮肤后缀>`。
- 判定原则是**能加载就原样用** —— mod 自带的扁平素材（`images/noteSplashes.png`）不受影响。

顺带修了一个隐性开销：`loadSplash` 的 fallback 会把 `texture` 改写成新路径，而 `spawnSplashNote` 里拿
`texture != loadedTexture` 判断要不要重载 —— 两边永远不相等，每打一个音符都重新加载一遍图集。
加 `requestedSplash` 记请求名，比较改用它。（NovaFlare 也是这么做的）

**21. 按脚本伪造引擎版本** — `psychlua/FunkinLua.hx`、`psychlua/ReflectionFunctions.hx`

不少 mod 用 `if version == '0.6.3' then` 决定走哪条分支。文件名加 `(%run_v_x.x.x)` 就能让**这一个脚本**看到指定版本：

```
mods/xxx/scripts/legacy-thing(%run_v_0.6.3).lua
```

`FunkinLua.parseVersionTag()` 从路径里捞出标记存进 `versionOverride`，构造时用它覆盖 `version` 全局；
`getPropertyFromClass('states.MainMenuState', 'psychEngineVersion')` 也返回这个值。
每个脚本一个独立 Lua state，所以其它脚本和引擎自身（标题 / Discord RPC / 日志）仍是真实版本。
`.js` 脚本走同一条构造路径，一并生效。

**22. Haxe 返回类型推断的坑（差点把整套反射打废）** — `psychlua/ReflectionFunctions.hx`

给 `getPropertyFromClass` 回调加了 `return funk.versionOverride;`（String）之后，Haxe 把整个匿名函数的返回类型
**推断成了 String** —— 于是 Float / Array / 对象返回值全被 `toString`。回归里表现为：

```
FAIL|class.oldName.arrowHSV            （数组变成了字符串，type(v) ~= 'table'）
ERR |class.fullName.Conductor           attempt to compare number with string
FAIL|class.ClientPrefs.write            （写入后读回比较失败）
```

v073 掉 4 项、v104 掉 3 项。回调签名补上显式 `:Dynamic` 就恢复了。**以后往这类回调里加 return 一定要标返回类型。**

**23. `Bar.color` 把整条染色，填充边界消失** — `objects/Bar.hx`

0.6.3 的 `FlxBar.color` 只作用于填充条。1.0 的 `Bar` 是 `FlxSpriteGroup`，父类 `set_color`
会 `transformChildren` 把 `leftBar` / `rightBar` / `bg` 一起染色，mod 用 `setProperty('timeBar.color', ...)`
调色时背景和填充变成同一个颜色，"已填充/未填充"的边界就没了，看起来整条时间条一直是满的
（Marios-Madness-HEIHUA pack 的 `HUD2.lua` 第 20 行）。

`Bar` 里 override `set_color`，只染 `leftBar`，跳过 `rightBar` 和 `bg`。
实测 `alone`：修复前 `bgColor` 跟着变 `0xFF3E25`，修复后保持 `0xFFFFFF`，`leftClip` 照常从 0 增长。

### 当前状态

| 脚本 | 用例 | 失败 |
|---|---|---|
| `compat_v073.lua`（0.7.3 写法） | 58 | 0 |
| `compat_v104.lua`（1.0.4 写法） | 32 | 0 |
| `compat_more.lua`（补充） | 37 | 0 |
| `compat_edge.lua`（边界 + js） | 10 | 0 |
| `versionTag(%run_v_0.7.3).lua`（版本标记） | 1 | 0 |
| `versionPlain.lua`（版本标记不泄漏） | 1 | 0 |
| `stages/stage.lua` / `custom_notetypes/*.lua` / `custom_events/*.lua` | 三类都能加载并收到回调 | 0 |
| `compat_callbacks.lua`（回调计数） | onCreate / onCreatePost / onStepHit / onBeatHit / onSectionHit / onSpawnNote / opponentNoteHit 全部有触发 | — |

### 还没验的

- **画面**。所有判定都停在「属性值 / 返回值」这一层，贴图位置、动画观感、UI 层级到底对不对，
  这套测试看不出来。
- **stage / notetype / event 脚本**（`stages/x.lua`、`custom_notetypes/x.lua`、`custom_events/x.lua`）。
- **0.6.3 的 `FlxUIDropDownMenuCustom` 这类**：依赖 flixel-ui，1.0 已经没有这个库，接不了。
