# FNF-PE_RealQuickJs_Engine

Psych Engine 1.0.4 的 fork。一个 exe 里塞了三棵源码树，靠 `engine.txt` 切换；主要目标是让 0.6.3 / 0.7.3 的老 mod 不改一行就能跑，同时让 `.js` 脚本有两条路可走。

JS 那侧的 FunkinJS 转译器和存档是个故意留着的装置 —— 针对 rongtang2026/PE-QuickJs-Engine 拿 `{`→`end` 冒充 JS 支持、违反开源协议那件事。存档原本塞在 `JavaScriptUtils.hx` 的注释里，2026-11-17 搬到了 `docs/JS_TRANSPILE_HISTORY.md`。

---

## 快速上手

### 选引擎

`Options → Switch Engine`，选完写 exe 旁边的 `engine.txt` 并退出，下次启动生效。三个值：

| `engine.txt` | 走哪棵 | 源码 | 资产 | mod |
|---|---|---|---|---|
| `body`（默认） | 本仓 fork | `source_body/body/` | `assets/body/` | `mods/body/` |
| `vanilla` | 原版 PE 1.0.4 | `source_vanilla/vanilla/` | `assets/1.0.4/` | `mods/1.0.4/` |
| `pe063` | Psych Engine 0.6.3 | `source_063/pe063/` | `assets/0.6.3/` | `mods/0.6.3/` |

文件缺失、读失败、值不认识，一律回 `body`。三棵树各读自己那本 `modsList.txt`；11-16 起 `mods/global/` 那套全局 mod 机制整个删了，编译时也不再创建这个目录。

### 编译

```bash
bash manage.sh              # 菜单：先选中文/英文，再按编号
bash manage.sh --zh 2       # 跳过菜单，直接编译 release（2 号）
bash manage.sh --zh debug   # 名字别名，同样跳过菜单
```

菜单编号连续 **1–9** / 0 退出：
1 环境体检、2 编译、3 素材、4 Lua 兼容审计、5 重建 import 表、6 QuickJS 静态库、7 回归测试、8 安卓构建、9 安卓环境补齐。
1/2/3/6/7 进二级菜单再选子项。**编号可能再调整，稳定调用请用名字别名**：`release` / `debug` / `clean` / `verify` / `audit` / `imports` / `luatest` / `qjstest` / `android`。带参数可跳过二级询问：`manage.sh --zh build debug`、`--zh test qjs bopeebo`、`--zh env android`。

所有脚本都收在根目录 `manage.sh`（双击 `manage.bat`），`.workbuddy/` 只放测试数据和工具链，不再有散落的 sh。带动作调用时（如 `--zh 2`）会自己裹 `conhost --headless`，从编辑器/CI/后台起也不会给 haxe/cl/link 弹黑框。

编译产物 `export/<release|debug>/windows/bin/realQuickJSEngine.exe`，日志 `.cache/build-<mode>.log`。

编译前会自动用本机 MSVC 编 `third_party/quickjs-ng`，产物不入库，第一次十几秒，之后命中缓存跳过。Haxe 本体从零装照 `docs/BUILDING.md` 走一次。

### 跑测试

```bash
bash manage.sh --zh luatest [song]   # Lua / 兼容层（7 号），自动开局、收结果、清测试脚本
bash manage.sh --zh qjstest [song]   # QuickJS 桥（7 号二级第 2 项）
bash manage.sh --zh probe063         # 0.6.3 路径探针（7 号二级第 3 项），不进游戏
```

等价写法：`--zh test lua [song]` / `--zh test qjs [song]` / `--zh test probe`。
调试构建加 `PE_BUILD=debug`，跳过谱面补丁用 `NOPATCH=1`；对 Lua/QuickJS 两条都生效。

跑游戏/跑测试不弹窗：窗口最小化 + 挪出屏幕 + 静音，不抢焦点。`PE_AUTOTEST_SHOW=1` 才显示画面。

---

## 一、旧版 mod 兼容

Psych 1.0 改了不少底层结构，官方补了一部分，漏掉的那些足以让老 mod 白屏或 UI 全乱。这一节是补剩下那些。

### 谱面

| 问题 | 处理 |
|---|---|
| 0.7.x 及更早用「相对 lane + `mustHitSection`」表示归属，1.0 用绝对 lane | `Song.parseJSON` 识别 `{"song": {...}}` 包裹层判定格式，判成 1.0 语义时走官方 `convert()` |
| 老谱默认按哪套 lane 回放 | 读文件创建时间，早于 `2024-10-15 01:54:44 UTC`（`1728957284000.0`）走 `Pe-0.7.3`，晚的走 `Pe-1.0.4`；拿不到时间（打包进 assets）时退回 `format` 字段 |
| 判错了 | 暂停菜单 `Change Chart Ver` 切另一套后重载，只对本局有效。暂停界面右上角显示当前引擎和判定来源（`manual` / `file date` / `chart format`） |
| 老谱缺 `bpm` / `speed` / `needsVoices` | `fixMissingFields()` 兜底，缺 bpm 会让所有音符变 NaN |
| 独立 `events.json` 覆盖主谱判定 | 按 sidecar 跳过版本写入 |

两个边界：没有 `{"song": {...}}` 包裹层时**不**按时间降级（那个形状是 1.0 之后才有的，套旧语义会把整首歌左右镜像）；从压缩包解出来的谱面创建时间是解压那一刻，会被判成新谱，用暂停菜单手动切。

### 类名与 API

0.6.3 源码树是完全扁平的（`source/*.hx` 没有包目录），那个年代的脚本写裸类名：

```lua
import Boyfriend;                                  -- 现在是 objects.Character
getPropertyFromClass('ClientPrefs', 'downScroll')  -- 现在在 backend.ClientPrefs.data 里
getPropertyFromClass('GitarooPause', 'instance')   -- 现在是 substates.PauseSubState
```

`body/backend/ScriptClassAliases.hx` 里有 135 条映射（5 条在 `#if` 里），同时喂两条路：HScript 走 `Iris.proxyImports`（hscript-iris 1.1.3 原生支持，不用换 fork），Lua 的 `getPropertyFromClass` / `setPropertyFromClass` 走 `resolve()`。

### ClientPrefs

0.6.3 的设置项是 `ClientPrefs.downScroll` 这样的静态字段，1.0 全收进了 `ClientPrefs.data`。补了 33 个静态 get/set 转发到同一份 `data`。

`globalAntialiasing → antialiasing`、`arrowHSV → arrowRGB`（HSB/RGB 换算）；`noteSplashes` / `cursing` / `violence` / `controllerMode` 在 1.0 已删，用静态后备接住，不崩但也不生效。

### HUD 层级

1.0 把 `healthBar` / `iconP1` / `scoreTxt` / `timeBar` 塞进了 `PlayState.uiGroup`（`FlxSpriteGroup`），而 `setObjectOrder` / `getObjectOrder` 还按 `PlayState.members` 找索引：

- `getObjectOrder('healthBar')` 返回 `-1`
- `setObjectOrder('healthBar', N)` 的 `remove()` 静默失败，`insert()` 把血条插进 members 顶层，等于从 UI 组里拽出来甩到所有 mod 贴图上面

`create()` 末尾把 `uiGroup` 展开成普通 members（它本身没有整体变换，展开是视觉无操作），旧 mod 那套按 members 索引布局的代码就恢复了。**这项现在是可选开关**：Gameplay 设置里的 `Legacy HUD Layout`（`compatLegacyUI`），默认关，老 mod 需要时自己开。旁边还有 `Legacy Health Gain` / `Legacy Icons`。

顺带补的：`healthBarBG` 只读通道；`modchartSprites` / `modchartTexts` / `modchartSounds` / `modchartSaves` 指回 `MusicBeatState.variables`；`modchartTweens` / `modchartTimers` 补回字段并在 `destroy()` 清空；`instancesExclude` 旧 HScript 排除表。

### Bar

`timeBar` / `healthBar` 在 0.6.3 是 `FlxBar`，0.7 起变成 `Bar extends FlxSpriteGroup`，而 `FlxSpriteGroup.set_width` 是空实现（值直接丢掉）—— 所以 `setProperty('timeBar.width', 500)` 从 0.7.3 起一直静默失效。补了 `set_width` / `set_height`，转发到 `barWidth` / `barHeight` 并同步缩放背景；补 `fillDirection` 映射到 `leftToRight`。

`color` 也按老语义走：默认的 `FlxSpriteGroup.set_color` 会 `transformChildren` 把填充条、剩余条、背景一起染，填充/未填充的边界就没了（看起来整条一直满）。`Bar` 里 override 成只染填充条。

### Lua API

对照 0.7.3 源码，1.0.4 只缺这些，都补回来了：`getGlobalFromScript`、`setGlobalFromScript`、`getScore`、`getMisses`、`getHits`、`changePresence`。另外补 `FunkinLua.get()` 和 `getVarInArray` / `getFlxEaseByString`。

### 皮肤路径

0.6.x / 0.7.x 的 `arrowSkin` / `splashSkin` 写的是 `images/` 根下裸名（`NOTE_assets`、`noteSplashes`），1.0 把内置皮肤挪进了 `noteSkins/` / `noteSplashes/`，同名文件已不在原位。

- `Note.resolveNoteSkin()`（Note / StrumNote / LoadingState 共用）：裸名先按原路径找，找不到再试 `noteSkins/<名字>`；带 `/` 的显式路径不动
- `NoteSplash.loadSplash()`：同上，找不到再试 `noteSplashes/<名字><皮肤后缀>`；用 `requestedSplash` 记录请求名，避免 texture 被解析成新路径后每次 spawn 都判定"变了"重载图集

原则是**能加载就原样用** —— mod 自带的扁平素材不受影响，只有确实指向 1.0 内置皮肤的裸名才改写。

### 按脚本伪造引擎版本

有些 mod 的 Lua 里写 `if version == '0.6.3' then ...`，在 1.0.4 上会走进错误分支。给文件名加后缀，就能让**那一个脚本**看到它想要的版本：

```
mods/xxx/scripts/legacy-thing(%run_v_0.6.3).lua
```

脚本里 `version` 和 `getPropertyFromClass('states.MainMenuState', 'psychEngineVersion')` 都返回 `0.6.3`，其它脚本和引擎自己（标题界面、Discord RPC、日志）仍是真实 `1.0.4`。实现在 `body/psychlua/FunkinLua.versionOverride`，构造时用正则从路径捞 `(%run_v_x.x.x)`。

### 退出时崩溃

mod 在 `onDestroy` 里建 tween 是常见写法，而 `FlxGame.switchState` 的顺序是：

```
preStateSwitch.dispatch()   ← 官方在这里清了一次 tween
_state.destroy()            ← mod 在这里又建新的，逃过清理
_state = nextState.create() ← 新 state 这时才建
```

那些 tween 的回调活在 HScript 里，脚本一死、0.5 秒后回调就空引用。`destroy()` 里在脚本销毁之后补 `FlxTween.globalManager.clear()` + `FlxTimer.globalManager.clear()`（和 NovaFlare 在 GameOver 路径上的做法一致）。

其它：`moreLuaErrors` 设置项（Gameplay 里，关掉时重复警告只打一次）、`Character` 的 `position` / `camera_position` / `sing_duration` 缺字段兜底、`addHaxeLibrary` 走别名表解析。

---

## 二、JavaScript：两条路

Gameplay 设置 → **JS Engine** 选，只有两个值：

- **Troll**（默认）—— 转译成 Lua 塞回现成的解释器，兼容优先
- **QuickJS** —— 真的 QuickJS-NG 运行时，一文件一个 context，`getVar` / `Function_Stop` / 脚本装卸 / shader / 成就那批 API 和 Lua 对齐。结构和扩展方法见 `docs/JS_QUICKJS.md`

`.js` 放 `mods/<版本>/<mod>/scripts/xxx.js` 或 `mods/<版本>/<mod>/data/<song>/xxx.js`，引擎找不到同名 `.lua` 时自动回退到 `.js`。

### Troll 转译

照样交给现成 Lua 解释器，但转译比分花括号多做了几层：

```js
let arrow = (a, b) => a + b;        →   local arrow = function(a, b) return a + b end;
let label = `hi ${name}`;           →   local label = ("hi " .. tostring(name));
for (let i = 0; i < 4; i++) { }     →   do local i = 0 while i < 4 do  end  i = i + 1 end
let obj = {a: 1};                   →   local obj = {a = 1};
if (a === b && c !== d) { }         →   if (a == b and c ~= d) then  end
total += 1;                         →   total = total + 1;
```

没有 V8、没有 AST —— 8 遍独立词法扫描，每遍只管一种语法，字符串和注释全程原样跳过：

| 顺序 | 处理 | 例子 |
|---|---|---|
| 1 | 模板字符串 | `` `hi ${name}` `` → `("hi " .. tostring(name))` |
| 2 | 箭头函数 | `(a, b) => a + b` → `function(a, b) return a + b end`；`x => { ... }` → `function(x) ... end` |
| 3 | C 风格 for | `for (i = 0; i < 4; i++) { body }` → `do local i = 0 while i < 4 do body i = i + 1 end end` |
| 4 | 复合赋值 | `x += 1` / `-=` / `*=` / `/=` → `x = x + 1` 之类 |
| 5 | 对象字面量 | `{a: 1, b: 2}` → `{a = 1, b = 2}`，嵌套递归 |
| 6 | 运算符 | `===` → `==`，`!==` / `!=` → `~=`，`&&` → `and`，`\|\|` → `or` |
| 7 | let / const / var | → `local` |
| 8 | 花括号 | 代码块 → `end`，对象字面量原样保留（看 `{` 前面那个非空白字符） |

每遍都是「扫描 + 重写」而不是正则替换，字符串里的 `=>`、注释里的 `{` 不会被误伤。

**做不了的**（转译路线的边界，不是 bug）：`class` / `new` / `this` 原样输出、Lua 侧明确报语法错；单行 `if (x) return;`；三元 `a ? b : c`、数组方法 `.map/.filter/.forEach`；`+` 同时当数字加法和字符串拼接（拼接请写 `..`）；真 JS 的原型链、松散相等、`undefined` vs `nil`、数组和 table 的区别。

`PE_JS_DUMP=1` 时每个脚本旁边生成 `<脚本>.transpiled.txt`，就是实际喂给 Lua 的源码。

### JavaScriptUtils.hx 与完整性校验

`body/psychlua/JavaScriptUtils.hx` 现在是 30 行说明 + 一个空类，只是校验锚点；30 条 issue 全文存档（7.3 万字）搬到了 `docs/JS_TRANSPILE_HISTORY.md`。

`FunkinJS.verifyUtilsIntegrity()` 在 `body.Main` 构造器里（`sys` 目标）算 FNV-1a 31，和 `FunkinJS.UTILS_FNV`（`0x1CF604D9`）对不上就 `Sys.exit(1)` —— 不弹窗、不降级。源码文件找不到时放行（发行版不带 `source/`），这个校验只防改源码的人。

改过锚点文件后重算哈希（注释里写的 `.workbuddy/hash_utils.py` 仓库里**不存在**，用这条，已验证和常量对得上）：

```bash
python -c "from functools import reduce; s=open('source_body/body/psychlua/JavaScriptUtils.hx','rb').read().replace(b'\r\n',b'\n'); print(hex(reduce(lambda h,b: ((h^b)*0x01000193)&0xFFFFFFFF, s, 0x811c9dc5)&0x7FFFFFFF))"
```

---

## 三、崩溃屏

三棵树共用一个拦截器（`source/backend/EngineCrash.hx`），装在 `Main.main()` 分叉之前 —— 切到 vanilla 或 0.6.3 崩了也一样走这条路。

- 先写 `crash/PsychEngine_<时间>.txt`（错误 + 调用栈），再切到引擎内崩溃屏，不弹系统对话框
- 屏幕上显示引擎、时间、错误和调用栈；**C** 或点 COPY 复制全文
- **QUIT** 退出，**MAIN MENU** 或 **M / ESC** 回当前引擎主菜单（按 `engine.txt` 判）
- `Ctrl+Alt+Shift+Q` 手动触发一次，验证这个屏本身

界面只用 flixel 原生控件（色块 + `FlxText`），不依赖任何一棵树的 Button / Alphabet —— 崩溃的时候最不该假设的就是「引擎自己的 UI 还好使」。

---

## 四、已知限制

更完整的问题表见 `docs/SCRIPT_ISOLATION_AUDIT.md` 和 `docs/JS_QUICKJS.md`。

**2026-11-17 修掉的**

- vanilla 树的 `modFolder` 一直推不出来（上游 `split('/')[0]` 撞上 `mods/1.0.4/` 这层目录）→ 改用 `Paths.modFromScriptPath()`
- QuickJS 读写文件路径口径不统一 → `getTextFromFile` / `readJson` / `saveFile` / `deleteFile` 全走 `Paths`
- `QuickJS.hx` 嵌死绝对路径、靠 `manage.sh` 用 `sed` 对齐 → 改成相对 hxcpp 构建目录的路径，挪仓库不用再改
- `.js` 最多 32 个 → 64 个
- 事件只传第一个参数 → 按桥支持的类型转发最多三个
- HScript 拿不到 `(%run_v_)` 伪装值 → 补 `version` 和 `psychEngineVersion` 两个全局

**仍然是限制的**

- `Paths.modFolders` 在当前 mod 里找不到文件时静默退到 `mods/<版本>/`，而那个目录同时是共享目录和兜底目录 → 可能命中同名错文件且不报错（设计如此，改了会破坏大量老 mod）
- `Paths.modFromScriptPath` 只认 `currentModDirectory`，非当前 mod 的脚本 `modFolder` 恒 null（多 mod 同时启用时才会碰到，要动 `Mods` 的当前-mod 模型）
- HScript 直读静态字段 `MainMenuState.psychEngineVersion` 仍是真实版本 —— hscript 的 `Interp.get` 是模块私有，没有钩子能按脚本拦静态字段读；带标记的脚本请读 `psychEngineVersion` 全局
- Animate 2019+ 图集未支持（0.6.3 只认 2018 单 spritemap；移植 0.7+ 的 `AtlasFrameMaker` 属于加功能）
- 对象过不了桥（JS 侧只有字符串桥，`readJson` 返回文本，需要自己 `JSON.parse`）
- 每首歌重建 context，脚本状态不跨歌（设计）
- 测试覆盖：vanilla 分支没有自动测试入口，只能人工开机验

---

## 目录

```
manage.sh / manage.bat                 唯一的脚本入口：体检 / 补库 / 编译 / 铺素材 / 校验 / 审计 / 三条回归 / 安卓构建
.workbuddy/harness/                    测试入口注入（apply_hook.py）
.workbuddy/luatest/                    Lua / JS / HScript 测试脚本与谱面补丁
.workbuddy/toolchain/                  安卓 JDK17 + SDK + NDK（不入库）
.workbuddy/upstream/                   上游参照（pe063 / pe073 / pe104 / novaflare）
.workbuddy/memory/                     逐日流水账

source/                                公共层，只许依赖 flixel / lime / std
├── Main.hx                            入口，读 engine.txt 分叉
├── Engine.hx                          engine.txt 读写
└── backend/{EngineCrash,CrashState}.hx 崩溃拦截 + 崩溃屏（三棵树共用）

source_body/body/                      改版 1.0.4（本体），包 backend.* / states.*，启动类在 body.Main
├── backend/                           Paths / Song / ClientPrefs / ScriptClassAliases
├── psychlua/                          FunkinLua / FunkinJS / JavaScriptUtils（校验锚点）
├── jsruntime/                         真 QuickJS-NG 运行时
├── objects/Bar.hx                     尺寸 / 填充方向兼容
├── options/EngineSelectSubState.hx    引擎切换界面
└── states/PlayState.hx                uiGroup 展开、旧容器、退出清理

source_vanilla/vanilla/                原版 1.0.4，全部 vanilla.* 前缀
└── psychlua/IsolatedImports.hx        import 别名表（manage.sh 功能 8 重建）

source_063/pe063/                      Psych Engine 0.6.3，全部 pe063.* 前缀
└── debug/Probe.hx                     路径探针

docs/                                  见下一节
third_party/quickjs-ng/                JS 运行时源码 + 静态库（产物不入库）
export/<mode>/windows/bin/             构建产物，engine.txt 在这里
```

---

## 文档

| 文件 | 讲什么 |
|---|---|
| `docs/AI_HANDOFF.md` | 总交接：目录约定、修复索引、文档导航。改兼容层先看它 |
| `docs/LUA_COMPAT.md` | Lua 兼容层逐条修复记录（改兼容层必须同步更新） |
| `docs/HANDOFF_DUAL_ENGINE.md` | 0.6.3 移植 + 原版 1.0.4 并进同一 exe 的交接 |
| `docs/JS_QUICKJS.md` | QuickJS 桥协议、加宿主函数的步骤、已知限制。动 `jsruntime/` 前先看 |
| `docs/JS_TRANSPILE_HISTORY.md` | Troll 转译器原始说明 + 30 条 issue 存档 |
| `docs/SCRIPT_ISOLATION_AUDIT.md` | 三棵树脚本隔离问题表。动 `Paths` / 别名表前先看 |
| `docs/COMPAT_REVIEW.md` | 挑刺式审查，项目定位说明 |
| `docs/BUILDING.md` | 上游 Haxe 环境搭建步骤 |

---

## 参与者

<table>
  <tr>
    <td align="center" valign="top" width="33%">
      <img src="docs/contributors/deepseek.png" width="150"><br>
      <b>DeepSeek</b><br>
      <sub>主要开发 · Developer</sub>
    </td>
    <td align="center" valign="top" width="33%">
      <img src="docs/contributors/wq.png" width="150"><br>
      <b>WQ</b><br>
      <sub>监督 · Supervision</sub>
    </td>
    <td align="center" valign="top" width="33%">
      <img src="docs/contributors/maopou.png" width="150"><br>
      <b>Maopou</b><br>
      <sub>特别感谢 · Special Thanks</sub><br>
      <sub>NovaFlare Engine</sub>
    </td>
  </tr>
</table>

<p align="center">
  <img src="docs/contributors/maopou-card.jpg" width="420"><br>
  <sub>Lanli 为 Maopou 使用 画世界pro 绘制的 Programmer 名片。这个仓库兼容层的好几个思路是从那边学的。</sub>
</p>

## 致谢与许可

- [Psych Engine](https://github.com/ShadowMario/FNF-PsychEngine) —— 上游
- [NovaFlare Engine](https://github.com/NovaFlare-Engine-Concentration/FNF-NovaFlare-Engine) —— 兼容层思路参考（`FlxTween.globalManager.clear()` 那套），Maopou 在那边做开发

本仓库 Apache-2.0（`LICENSE`）；`third_party/quickjs-ng` MIT（见其目录下 `LICENSE`）。
