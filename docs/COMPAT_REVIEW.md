# Lua 向下兼容层审查

> 立场：挑刺。只看"0.6.3 / 0.7.3 的 mod 不改一行能不能跑"这一个目标，别的不算分。
> 所有行号对应当前工作区（2026-11-09）。
>
> **定位澄清（2026-11-09 晚补充）**：这个 fork 出生目的之一就是嘲讽
> rongtang2026/PE-QuickJs-Engine（违反开源协议、拿 `{`→`end` 冒充 JS 支持的那个）。
> JavaScriptUtils.hx 的档案和 FunkinJS 是**故意的装置，不是私货**——初版报告把这两条
> 判成"建议整删"是建立在错误的项目假设上的，已修正：标准换成"作为装置是否成立"。
>
> **修复状态（2026-11-09 22:00）**：三、四、五节的问题当晚已全修，代码与细节见
> `docs/LUA_COMPAT.md` 第 7 轮（16~19 条）；下文各节标题后带 ✅ 的即已处理。
> 结论区建议 5 / 6 / 7 相应完成。

## 一句话总评

兼容层本体（函数/类名/字段/路径/壳子）是认真做的，静态审计做到"0 缺"可信；
嘲讽装置（哈希锁 + 假 JS 复刻品）作为装置成立，但**装置的工程质量跟不上它的野心**：
报错不指路、指路指到不存在的工具、项目定位没写进任何交接文档——
下一个接手的人（无论人还是 AI）必然把它当私货误判并动手拆。

---

## 一、实际是怎么解决的（机制盘点）

| 层面 | 做法 | 位置 |
|---|---|---|
| 函数 | 250+ 回调全数注册，双签名的靠"晚注册覆盖早注册"重写 | `psychlua/DeprecatedFunctions.hx` |
| 类名 | 一张 0.6.3 裸名 → 1.0 包路径的 Map，同时喂 proxyImports 和变量表 | `backend/ScriptClassAliases.hx` |
| 设置字段 | 静态 get/set 成批转发进 `data`（含 arrowHSV 的 HSV→RGB 换算） | `backend/ClientPrefs.hx` |
| 对象/字段 | PlayState 补 cameraX/Y、inChartEditor、comboStacking 转发；Bar 补 width/height getter | `states/PlayState.hx`、`objects/Bar.hx` |
| 路径 | 存在性判断改成"先磁盘后清单"；stage/notetype/event 三类脚本找文件兜 `assets/` 根 | `backend/Paths.hx:185`、`states/PlayState.hx:2438` |
| 实体 | `Section` 纯数据壳、hxcodec 3.x / hxvlc / MP4Handler 三个名字一套实现 | `source/hxcodec/` |
| 验证 | 静态审计工具 + 自动开局回归（137 项断言） | `tools/lua_compat_audit.py`、`.workbuddy/luatest/` |

这套组合拳方向是对的：不是逐个 mod 打补丁，而是把 API 面和路径面系统补齐。

## 二、不算反人类、值得肯定的部分

- **审计工具是正经工程**：剥注释再比对（避开 0.6.3 注释掉的 3 个函数的假阴性）、
  覆盖三种注册方式、签名只报"真会炸"的差异。没有它，漏一个 comboStacking 这种事会永远漏下去。
- **Bar 的 width/height getter 是对的根因修复**：0.7 起 Bar 是 FlxSpriteGroup，bg 被撑成
  barWidth+6，不补 getter 老脚本每读写一轮就胖 6px。找到的是机制层根因，不是打补丁。
- **removeFromGroup 第三参 Dynamic 分流**（`ReflectionFunctions.hx:164`）：丑，但边界都想到了
  （Bool→老语义、否则当 tag、tag 无效先报错）。可辩护。
- **cameraX/Y 每帧 setOnScripts 是 1:1 复刻 0.6.3 行为**，不是自创的开销。
- **测试基建完整**：注入入口、自动开局、收结果、自动清理（还吃过测试脚本忘删的亏后补了 cleanup）。

## 三、反人类清单（按严重度）

### 1. JavaScriptUtils.hx：1517 行源码，98% 是嘲讽档案，还有一把哈希锁

`source/psychlua/JavaScriptUtils.hx` 1517 行，第 32 行起到文件尾是从
rongtang2026/PE-QuickJs-Engine 抓的 31 条 issue 全文（含大量侮辱内容、外部图片链接）。
真正的代码一行都没有——转译器在旁边的 `FunkinJS.hx` 里。

然后是 `FunkinJS.hx:25-93` + `Main.hx:69`：FNV-1a 哈希硬编码，游戏启动第一件事
就是读这个源文件算哈希，不匹配 → `Sys.exit(1)`，整个进程直接退出。

**作为嘲讽装置，这个设计本身成立**：留档、防篡改、git 历史专门有一笔
`Move issue archive into JavaScriptUtils.hx and guard it`，都是有意为之。
但装置的做工有三处硬伤：

1. **报错不指路**：哈希不符时黑屏退出，报错只给 expected/actual 两个哈希值 +
   "Put it back"（`FunkinJS.hx:50-52`）。改文件的人（包括未来的自己）对着崩溃两眼一抹黑。
2. **指路指到空气**：注释教人改完跑 `python .workbuddy/hash_utils.py` 重算哈希
   （`FunkinJS.hx:22`）——**这个工具在仓库里不存在**。注释开空头支票，
   报错信息也不提工具。三步闭环：锁文件 → 报错无修复指引 → 指引指向不存在的脚本。
3. **启动期做构建期该做的事**：每次启动读文件 + 全文 FNV，为一段注释服务。
   既然有 build.sh 这种工程化习惯，哈希校验应该挪进构建脚本，运行期只留告警。
   现在这个锁防的不是外人（发行版没 source 目录直接跳过），是手滑的自己人——
   而防自己人的正确姿势是把重算工具做出来，不是每次启动杀进程。

另外一个跟做工无关、但对"嘲讽装置"更致命的风险：**档案内容跟公开 git 历史共存亡**。
那些人身攻击内容触的是 GitHub conduct/harassment 政策的边——
装置被平台下架，等于装置报废。嘲讽想做持久，载体得先活得久。

**定性：装置成立，做工不及格。**

### 2. FunkinJS 假 JS 层：作为"活的复刻品"成立，但兼容性叙事是错的

transpile() 把 `{` 删掉、`}` 换成 `end` 丢给 Lua——注释自己承认行为和被嘲讽的
引擎"完全一致"，连它的坑都原样复刻。作为嘲讽装置，这是整件事里最狠的部分：
不只是嘴上说，是真做了一个能跑的复刻品。

修正后的挑剔：

- **它在交接文档里被当成了正经兼容功能**。LUA_COMPAT.md 第 3 轮、AI_HANDOFF
  第 3.1 节都把 .js 分支当成兼容层的一部分在记录，没有一个字提"这是复刻嘲讽"。
  项目有两个目标，文档只写了一个。后果就是初版审查那样的误判：后来者把它当
  兼容功能评估，结论必然是"对 0.6.x 贡献为零、风险为正、建议删掉"。
  **装置说明书缺失，装置就有被拆掉的风险。**
- **转译器本身是筛子**（这点不变，而且恰是嘲讽要复刻的点）：`var/let/const`、
  `&&`/`||`/`!`、`++`、`===`、块注释 `/* */`、`do-while`、`return {...}` 全烂。
  作为复刻品这叫"行为一致"；但 mods 里附带 .js 文件被误吞转译的风险面也是真的
  （`PlayState.hx:2451` 找不到同名 .lua 会自动找 .js）——复刻品得说清自己是
  展品还是功能，现在代码里没这个界限。
- 三级路径查找（mods→shared→assets 根）抄成了**复制粘贴三份**
  （startLuasNamed 一份、js 分支一份、startHScriptsNamed 一份），将来改一处忘两处。

### 3. ✅ debugPrint 启发式有真实误判，且没有逃生门（已修）

> 修复备注：Int/Float 第二参直接走老拼接分支（1.0.4 上游的 color 参数本来就是 String，
> 数字永远不是合法新语义颜色）；逃生门是环境变量 `PE_DEBUGPRINT_LEGACY=1`。
> 另外下面说的"裸 hex 静默返回白色"其实不成立——`colorFromString` 第 62 行有
> `FlxColor.fromString('#$color')` 的兜底重试，裸 `'FF0000'` 能正常解析，别去修这个。

`DeprecatedFunctions.hx:170-222`：第二参数"像不像颜色"决定走新语义还是老语义。
`looksLikeColor` 认 6/8 位纯 hex 字符——**十进制 8 位数全是合法 hex 字符**。

真实炸点：老 mod 写 `debugPrint('id', 16711680)`（八位十进制数），`'' + 16711680`
= `'16711680'`，8 位全 hex → 被判成颜色 → 数值被吞、文本上屏。
文档只承认了 `'RED'` 这种字符串误判，没算到数字这条更隐蔽的路。

另一个口子：裸 `'FF0000'`（不带 0x/#）会走新分支，但 `CoolUtil.colorFromString`
对裸 hex 大概率静默返回白色——判成颜色了，颜色却是白的，两头都没落好。

而且**没有任何强制走旧语义的开关**。双签名分流靠猜，猜错只能改引擎源码。

### 4. ✅ 已知是错的映射，留着不删（已删）

> 修复备注：`PhillyGlow → BlendModeEffect` 已从表里删掉。查过 0.6.3 上游，
> `PhillyGlow.hx` 只是模块名（里面是 Particle/Gradient 两个类），裸名从来不是类。

- `ScriptClassAliases.hx:119`：`PhillyGlow → shaders.BlendModeEffect`。
  LUA_COMPAT.md 自己写着：NovaFlare 把 PhillyGlow 映射到 BlendModeEffect **是错的**
  （0.6.3 的 PhillyGlow 是两个 FlxSprite），并补了正确的 Particle/Gradient 两条——
  然后错的那条没删。mod 里 `new PhillyGlow()` 拿到的是一个 shader 效果对象，直接烂。
  已知错误映射还挂在表里，等于给老 mod 埋了一颗自己标注过的雷。
- `ScriptClassAliases.hx:253-258`：`applyToHScript` 把**整张表**倒进 hscript 变量表，
  包括 `stages.Spooky`、`editors.ChartingState` 这类带点的 key。hscript 里
  `stages.Spooky` 是字段路径表达式，根本不走变量表——40 多条纯垃圾 entry 白占内存。

### 5. ✅ 路径兜底：三份复制粘贴 + 硬编码 CWD 依赖（已收敛）

`startLuasNamed` / `startHScriptsNamed` / js 分支三处各自硬拼
`Paths.modFolders → getSharedPath → 'assets/'+file`。没有公共函数。
`'assets/' + luaFile` 是裸相对路径，依赖进程 CWD 恰好是 bin 目录——现在能跑，
Paths 结构动一次就全烂。另外 `startHScriptsNamed` 的 `#else` 分支（`PlayState.hx:2492`）
在非 sys 目标下用 `sys.FileSystem`，没配 `#if sys`，H5 构建直接编译不过（虽然只发 Windows，但 FunkinJS 里倒是记得写 `#if sys`，同一批人两套标准）。

### 6. "编译完再手动拷素材"的绕路工作流

`BASE_GAME_FILES` 故意留在 officialBuild 段 → 编译清单里没有 base_game →
`Paths.existsOnDiskOrManifest` 被迫发明（先查磁盘再查清单）→ 素材靠 `prep_assets.sh`
手动拷进 bin。一条链四个部件互相补锅。忘跑脚本 = 图标全 face、关卡图 404——
**用户已经踩过一次**（AI_HANDOFF 3.4 的三连 bug 就是这条链的账单）。
能用，但这是"绕路绕出一套架构"，忘了就是静默坏，坏得毫无线索。

### 7. 测试是自证循环，"137 项全绿"不是兼容性证据

测试脚本是自己写的，断言是自己定的，测的全是自己修的点。
0.6.3 的 250+ 回调里被脚本实际摸过的只有一小部分；更关键的：
**画面、时序、动画观感、UI 层级全部没验**（LUA_COMPAT.md 自己承认）。
老 mod 最常炸的从来不是"函数不存在"，而是"函数存在但渲染结果不对"。
`noteSplashes.png` 404、`spraycanErectAtlas` 缺图这类静默视觉缺失，
现在的测试体系一个都抓不到。全绿只证明"测过的点没退步"。

### 8. 小账本

- 兼容层靠 `Lua_helper.add_callback` 注册顺序覆盖（`DeprecatedFunctions.hx:169` 注释自述）。
  谁在 FunkinLua 构造里动一下 implement 顺序，debugPrint 语义静默换人，没有任何保护。
- `Bar` 一类修复顺带把部分 private 转发放大成 public（AI_HANDOFF 自己承认），可见性净增。
- `FlxVideo.stop()` 后再 `play('')` 只调 `bitmap.play()`，hxvlc stop 过的实例未必能直接续播，
  壳子没处理重新 load。
- 整个 3.2 节的 PlayState 拆分（2821 行 + 静态 helper + 转发）与兼容层无关，是顺手夹带的
  大重构——混在兼容 commit 里，出问题时无法单独回滚。

## 四、结论与建议优先级

做得怎么样：**兼容层本体 API 面"0 缺"可信，机制方向正确；拖后腿的是测试盲区
和几处自己文档里都认账的错误映射。嘲讽装置作为装置成立，做工跟不上野心。**

1. **给装置写说明书**：AI_HANDOFF.md / LUA_COMPAT.md 补一段项目定位——
   "JavaScriptUtils.hx 档案和 FunkinJS 是复刻嘲讽装置，勿按兼容功能评估、勿删"。
   不写这个，下一个接手的人必然重演初版审查的误判（初版报告自己就是活例证）。
2. **把锁的闭环补全**：真做 `.workbuddy/hash_utils.py`（重算 FNV 并回写 FunkinJS.hx），
   报错信息里加上"跑这个工具"的指引。锁文件、报错、修法三步现在断在中间两步。
3. **校验挪出启动流程**：哈希校验放构建脚本里做，运行期降级成 trace 告警——
   防手滑的目的没变，但不用每次启动都杀进程的威胁挂在头上。
4. **公开仓库前评估档案内容的风险**：那 31 条 issue 里的辱骂内容触 GitHub conduct
   政策的边，被下架=装置报废。要持久嘲讽，考虑把人身攻击部分脱敏、只留技术鉴赏，
   完整版另存本地。
5. ~~删 `PhillyGlow → BlendModeEffect` 这条自己都标注"是错的"的映射；
   `applyToHScript` 只倒不带点的 key。~~ ✅ 已做
6. ~~`debugPrint`：数字第二参不走颜色分支（`Std.isOfType(v, Float/Int)` 优先），
   并留一个环境变量/设置项强制旧语义。~~ ✅ 已做（PE_DEBUGPRINT_LEGACY）
7. ~~路径查找抽公共函数，三份复制粘贴收敛成一份；`startHScriptsNamed` 的 #else 分支配 `#if sys`。~~
   ✅ 已做（`Paths.findScriptFile()`，顺带加了 exe 目录锚定兜底）
8. 找 3~5 个真实老 mod（0.6.3 时代下载量大的）跑通才叫兼容性验证；
   现在的 137 项只能算回归网。
