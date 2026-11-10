# FNF-PE_RealQuickJs_Engine

基于 [Psych Engine 1.0.4](https://github.com/ShadowMario/FNF-PsychEngine) 的 fork。

主要做两件事：**让 0.6.3 / 0.7.3 时代的 mod 还能跑**，以及**让 `.js` 脚本"能跑"**。

---

## 一、旧版 mod 兼容

Psych 1.0 相比 0.6.x / 0.7.x 改了不少底层结构。官方自己做了不少向下兼容，但漏掉的部分足以让老 mod 白屏或者 UI 全乱。这个 fork 把剩下的补齐了。

### 谱面

| 问题 | 处理 |
|---|---|
| 0.7.x 及更早的谱面用「相对 lane + `mustHitSection`」表示音符归属，1.0 用绝对 lane | `Song.parseJSON` 识别 `{"song": {...}}` 包裹层来判定格式；判成 1.0 语义时走官方 `convert()` 转成绝对 lane |
| 老谱面默认按哪套 lane 语义回放 | 读谱面文件的**创建时间**：早于 PE 1.0 发布（2024-10-15 01:54 UTC）走 `Pe-0.7.3`，晚的走 `Pe-1.0.4`；拿不到时间（谱面被打包进 assets）时退回 `format` 字段判定 |
| 自动判错了，或者想手动确认 | 暂停菜单 `Change Chart Ver` 切到另一套后重载谱面，只对本局有效。暂停界面右上角显示当前引擎和判定来源（`manual` / `file date` / `chart format`） |
| 老谱缺 `bpm` / `speed` / `needsVoices` 等字段 | `fixMissingFields()` 兜底，缺 bpm 会让所有音符变 NaN |
| 独立 `events.json` 会覆盖主谱面的格式判定 | 按 sidecar 跳过版本写入 |

按文件时间自动判定有两个边界：

- 谱面没有 `{"song": {...}}` 包裹层时**不**按时间降级 —— 那个形状是 1.0 之后才有的，lane 必然已经是绝对坐标，套旧语义只会把整首歌左右镜像。
- 创建时间本身不可靠：从压缩包里解出来的谱面，创建时间是解压那一刻，会被判成新谱面。这种情况用暂停菜单手动切。

### 类名与 API

0.6.3 的源码树是**完全扁平**的（`source/*.hx` 没有包目录），所以那个年代的脚本写的是裸类名：

```lua
import Boyfriend;                                  -- 现在是 objects.Character
getPropertyFromClass('ClientPrefs', 'downScroll')  -- 现在在 backend.ClientPrefs.data 里
getPropertyFromClass('GitarooPause', 'instance')   -- 现在是 substates.PauseSubState
```

`source/backend/ScriptClassAliases.hx` 维护了约 90 条映射，同时喂给两条路：HScript 通过 `Iris.proxyImports` 解析（`hscript-iris 1.1.3` 原生支持这张表，不需要换 fork），Lua 的 `getPropertyFromClass` / `setPropertyFromClass` 通过 `resolve()` 查表。

### ClientPrefs

0.6.3 的设置项是 `ClientPrefs.downScroll` 这样的静态字段，1.0 全部收进了 `ClientPrefs.data`。`ClientPrefs` 里补了 32 个转发属性，老脚本读写都会落在同一个 `data` 上。

`globalAntialiasing → antialiasing`、`arrowHSV → arrowRGB`（做了 HSB/RGB 换算）；`noteSplashes` / `cursing` / `violence` / `controllerMode` 在 1.0 已被删掉，用静态后备变量接住，不崩，但也不生效。

### HUD 层级

1.0 把 `healthBar` / `iconP1` / `scoreTxt` / `timeBar` 全塞进了 `PlayState.uiGroup`（一个 `FlxSpriteGroup`）。而 `setObjectOrder` / `getObjectOrder` 依然按 `PlayState.members` 找索引 —— 结果是：

- `getObjectOrder('healthBar')` 返回 `-1`
- `setObjectOrder('healthBar', N)` 的 `remove()` 静默失败，`insert()` 把它直接插进 members 顶层，等于把血条从 UI 组里拽出来甩到所有 mod 贴图上面

这个 fork 在 `create()` 末尾把 `uiGroup` **展开成普通 members**（`uiGroup` 自身没有任何整体变换，展开是视觉无操作），旧 mod 那套按 members 索引做布局的代码就全部恢复了。

顺带补的：

| 对象 | 说明 |
|---|---|
| `healthBarBG` | 1.0 里没有这个对象，背景条在 `Bar.bg` 里，开了个只读通道 |
| `modchartSprites` / `modchartTexts` / `modchartSounds` / `modchartSaves` | 1.0 统一成了 `MusicBeatState.variables`，用只读属性指回同一份数据 |
| `modchartTweens` / `modchartTimers` | 1.0 直接删了，补回字段，并在 `destroy()` 里清空 |
| `instancesExclude` | 旧 HScript 注入时用的排除表 |

### Bar

`timeBar` / `healthBar` 在 0.6.3 是 `FlxBar`（普通 sprite），0.7 起变成 `Bar extends FlxSpriteGroup`。而 `FlxSpriteGroup.set_width` 是**空实现**：

```haxe
override function set_width(Value:Float):Float { return Value; }  // 值直接丢掉
```

所以 `setProperty('timeBar.width', 500)` 从 0.7.3 起就一直静默失效。`Bar` 里补了 `set_width` / `set_height`，转发到真正的 `barWidth` / `barHeight` 并同步缩放背景；另补 `fillDirection`（`FlxBar` 的老属性，映射到 `leftToRight`）。

### Lua API

对照 0.7.3 源码，1.0.4 只缺下面这些，都补回来了：

`getGlobalFromScript`、`setGlobalFromScript`、`getScore`、`getMisses`、`getHits`、`changePresence`

另外补了 `FunkinLua.get()`（0.7.3 的脚本互读靠它）和 `getVarInArray` / `getFlxEaseByString`（1.0 移进了 `LuaUtils`）。

### 退出时崩溃

mod 在 `onDestroy` 里创建 tween 是常见写法（estll 就是）。而 `FlxGame.switchState` 的顺序是：

```
preStateSwitch.dispatch()   ← 官方在这里清了一次 tween
_state.destroy()            ← mod 在这里又建了新的，逃过清理
_state = nextState.create() ← 新 state 这时才建
```

那些 tween 的回调活在 HScript 里，脚本一死、0.5 秒后回调就空引用。`destroy()` 里在脚本销毁之后补了 `FlxTween.globalManager.clear()` + `FlxTimer.globalManager.clear()`（和 NovaFlare 在 GameOver 路径上的做法一致）。

### 其它

- `moreLuaErrors` 设置项：关掉时，重复的 Lua 警告/错误只打印一次（Gameplay Settings 里有开关）
- `Character` 的 `position` / `camera_position` / `sing_duration` 缺字段兜底
- `addHaxeLibrary` 走别名表解析，`addHaxeLibrary('FunkinLua')` 能正常拿到类

### 皮肤路径

0.6.x / 0.7.x 的 `arrowSkin` / `splashSkin` 写的是 `images/` 根下的裸名（`NOTE_assets`、`noteSplashes`），1.0 把内置皮肤挪进了 `noteSkins/` 和 `noteSplashes/`，同名文件已经不在原位。

| 位置 | 处理 |
|---|---|
| `Note.resolveNoteSkin()`（Note / StrumNote / LoadingState 共用） | 裸名先按原路径找，找不到再试 `noteSkins/<名字>`。带 `/` 的显式路径不动 |
| `NoteSplash.loadSplash()` | 同上，找不到再试 `noteSplashes/<名字><皮肤后缀>`；同时用 `requestedSplash` 记录请求名，避免 `texture` 被解析成新路径后每次 spawn 都判定"变了"而重载图集 |

判定原则是**能加载就原样用** —— mod 自带的扁平素材（`images/noteSplashes.png`）不受影响，只有确实指向 1.0 内置皮肤的裸名才改写。

### 按脚本伪造引擎版本

有些 mod 的 Lua 里写着 `if version == '0.6.3' then ...`，靠引擎版本决定走哪条分支，在 1.0.4 上会走进错误的那条。给文件名加个后缀，就能让**那一个脚本**看到它想要的版本：

```
mods/xxx/scripts/legacy-thing(%run_v_0.6.3).lua
```

- 这个脚本里 `version` 和 `getPropertyFromClass('states.MainMenuState', 'psychEngineVersion')` 都返回 `0.6.3`
- 其它脚本、引擎自己（标题界面、Discord RPC、日志）仍然是真实的 `1.0.4`
- 每个脚本一个独立的 Lua 环境，互不影响，也不用改 mod 源码

实现见 `FunkinLua.versionOverride`：构造时用正则从路径里捞出 `(%run_v_x.x.x)`，只影响该脚本的 `version` 全局和版本字段查询。

---

## 二、FunkinJS

让引擎读 `.js` 脚本。

实现方式一句话：**把 `{` 删掉，把 `}` 换成 `end`，然后整段交给现成的 Lua 解释器**。

```js
function onCreatePost() {              function onCreatePost()
    setProperty('bf.x', 600)     →      setProperty('bf.x', 600)
}                                      end
```

没有 V8，没有 QuickJS，没有 AST。

转译器是词法扫描而不是无脑替换：字符串里的 `{ }`、对象字面量、`//` 注释都原样保留，只有「代码块」的花括号会被转换（判断依据是 `{` 前面那个非空白字符）。

用法：把脚本放 `mods/<mod>/scripts/xxx.js`，或者 `mods/<mod>/data/<song>/xxx.js`。引擎在找不到同名 `.lua` 时会自动回退到 `.js`。

**已知限制**（和原引擎一致）：不处理分号、不支持 `let` / `const`、不处理箭头函数，`for (var i = 0; ...)` 这种写法也过不了。

---

## 三、JavaScriptUtils.hx

`source/psychlua/JavaScriptUtils.hx` 里存的是某个同类项目 issue 区的**全文存档**（30 条，7.3 万字）。纯注释文件，不参与编译。

`FunkinJS.verifyUtilsIntegrity()` 在 `Main.main()` 第一行校验它的 FNV-1a 指纹，对不上就 `Sys.exit(1)` 直接终止进程 —— 不弹窗、不降级、不打日志然后继续跑。

改动过该文件的话，必须同步指纹：

```bash
python .workbuddy/hash_utils.py
```

把输出填进 `FunkinJS.hx` 的 `UTILS_FNV`，否则下次启动退出码 1。

> 发行版里没有 `source/` 目录，找不到文件时会放行。这个校验只防「改源码的人」。

---

## 构建

```bash
bash building/build.sh          # 增量 release
bash building/build.sh -debug   # debug
bash building/build.sh -clean   # 全量重编（改了 Project.xml / 诡异链接错误时）
```

Windows 上也可以直接双击 `building/Build.bat`。脚本会自己找 Haxe / MSVC / Windows SDK、核对 `Project.xml` 要求的库、关掉正在运行的游戏，编译完自动把 `assets/base_game` 铺进 bin。细则见 [building/README.md](building/README.md)。

依赖的安装步骤和上游一致，参照 [docs/BUILDING.md](docs/BUILDING.md) —— 只需配一次。

脚本探测不出 MSVC 时，手动注入环境变量比修 VS 安装快：

```bash
export HAXELIB_PATH="$PWD/.haxelib"
export PATH="/g/vs/program/VC/Tools/MSVC/<version>/bin/HostX64/x64:$PATH"
export INCLUDE='<MSVC>/include;<SDK>/ucrt;<SDK>/shared;<SDK>/um;<SDK>/winrt;<SDK>/cppwinrt'
export LIB='<MSVC>/lib/x64;<SDK>/ucrt/x64;<SDK>/um/x64'
haxelib run lime build windows
```

首次全量约 30 分钟，之后增量几分钟。

**注意**：构建前先关掉正在运行的游戏，否则 `lime.ndll` 被占用，会在复制阶段失败。

---

## 目录

```
building/
├── build.sh                     # 一站式编译（探工具链 → 查库 → 编译 → 铺素材 → 验收）
└── Build.bat                    # Windows 双击入口

source/
├── backend/
│   ├── ScriptClassAliases.hx    # 0.6.3 裸类名 → 现代全名
│   ├── ClientPrefs.hx           # 含旧静态字段转发
│   └── Song.hx                  # 谱面格式识别
├── psychlua/
│   ├── FunkinJS.hx              # JS 转译层 + 完整性校验
│   └── JavaScriptUtils.hx       # issue 存档（纯注释）
├── objects/Bar.hx               # 尺寸 / 填充方向兼容
└── states/PlayState.hx          # uiGroup 展开、旧容器、退出清理
```

---

## 致谢

- [Psych Engine](https://github.com/ShadowMario/FNF-PsychEngine) —— 上游
- [NovaFlare Engine](https://github.com/NovaFlare-Engine-Concentration/FNF-NovaFlare-Engine) —— 兼容层的思路参考（`FlxTween.globalManager.clear()` 那套）
- 以及 issue 存档里那 30 位，虽然大概没人希望以这种方式被记住
