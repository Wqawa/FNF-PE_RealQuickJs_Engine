# QuickJS 运行时交接 — `.js` 脚本到底跑的哪个引擎

> 2026-11-16 写。之前 `JS` 这块只有「转译器」的说明，真运行时的结构一直没落文档，
> 接手的人只能对着 2000 行 `QuickJSHandler.hx` 猜。这份补上。
> 逐日流水账在 `.workbuddy/memory/`，兼容层那摊在 `docs/LUA_COMPAT.md`。

---

## 1. 两条路，别搞混

| `Gameplay Settings → JS Engine` | `.js` 怎么跑 | 代码 |
|---|---|---|
| `Troll`（默认） | 8 遍词法扫描，把 JS 源码改写成 Lua 源码，塞回同一个 LuaJIT | `psychlua/FunkinJS.hx` 里的 `transpile()` |
| `QuickJS` | 真 QuickJS-NG，一个文件一个 context | `jsruntime/*` |

分流点在 `FunkinJS.start()`：`jsEngine == 'QuickJS'` 就把路径交给 `JSPlayer.loadFile()` 并返回
`null`（脚本不进 `luaArray`），否则走原来的转译。默认留在 Troll 是刻意的 —— 兼容优先，
QuickJS 要手动开。

开启之后 `.js` 不再有任何 Lua 痕迹：报错写 `js_log.txt`，不写 Lua 的栈。

---

## 2. 文件分工

```
jsruntime/QuickJS.hx        只跑一次 1+1，验证静态库链接通了；结果写 testout/quickjs_smoke.txt
jsruntime/QuickJSHandler.hx JSRuntime/JSContext 生命周期 + C 侧桥 + 宿主函数总表（90% 的活在这）
jsruntime/JSPlayer.hx       脚本清单、事件分发、timer/tween 归属、加载与卸载
jsruntime/JSScriptHost.hx   IScriptHost 的实现（一个 .js 的落脚点）
psychlua/FunkinJS.hx        .js 入口分流 + Troll 转译器
```

`IScriptHost` 把三条通道（Lua / HScript / QuickJS）收敛成同一个契约，
`PlayState.callOnScripts()` 只认这个接口。加事件不用再记「三处都要发」。

---

## 3. 运行时形状

- **进程一个 `JSRuntime`**，内存上限 256MB，所有 context 共同吃这个额度（`JS_SetMemoryLimit`）。
- **每个 `.js` 一个 `JSContext`**，上限 `QJS_MAX_CTX = 64`（`g_ctxs[]` 数组，句柄就是下标）。
  跟 Lua「一个文件一个 `lua_State`」对齐，同名回调不会互相顶掉。
- **一首歌一个世代**：`PlayState.create()` 调 `JSPlayer.beginSong()`，把上一首的 context 全
  dispose，脚本里的全局变量不会跨歌残留。
- **microtask 每帧推一次**：`Main` 的 `postUpdate` 里 `JSPlayer.update()` → `JS_ExecutePendingJob`。
  `Promise` 能用，但别指望它在同一帧里 resolve。

`JS_FreeRuntime` 从来没被调用 —— 进程退出时一起回收，不需要（也不该）在中途重建 runtime。

---

## 4. 桥：单 trampoline + 函数编号

```
JS 脚本
  playSound('x', 1, 'tag', false)
        ↓ WRAPPERS 里那层箭头函数（每个名字一行）
  __h(4, "x", "1", "tag", "false", "", "")
        ↓ C 侧唯一的 CFunction
  qjs_host(ctx, ...)   // 读编号 + 六个 JS_ToCString，攒进 buf[6][1024]
        ↓
  QuickJSHandler.hostDispatch(idx, a..f)   // Haxe，switch 分派
        ↓ 返回 String
  JS_NewString(ctx, r.utf8_str())
```

为什么这么设计：早先试过「每个函数一条 trampoline」（代码量爆炸）和
「`JS_SetOpaque` 存函数名」（对 CFunction 不可靠，class id 对不上就读不到）。
现行方案加函数只动两张表，C 侧一个字都不用改。

**类型全是字符串**。没有 table、没有对象、没有 Map：

| 类型 | 过桥方式 |
|---|---|
| 数字 | 出去 `String(n)`，回来 `Number(__h(...))` |
| 布尔 | 出去 `"true"/"false"`，回来 `__h(...) === "1"`（宿主的约定） |
| 数组 | `String.fromCharCode(1)` 拼起来再 `split` |
| 对象 | 过不去。`setProperty` 之类只能塞标量 |

两个上限要记住：

- **进宿主**：每个参数 `snprintf` 到 1024 字节，**超了直接截断**。大内容别从参数进。
- **出宿主**：`JS_NewString(r.utf8_str())` 不做长度限制（`getTextFromFile` 靠这个）。
- **回调返回值**：`g_js_ret` 1KB 截断 —— 返回值本来就只该是哨兵或短值。

---

## 5. 加一个宿主函数

1. `WRAPPERS` 里加一行：`globalThis.xxx = (a, b) => __h(<新编号>, a, b);`
2. `hostDispatch` 里加 `case <新编号>:`
3. **编号只能往后加**，不许插队 —— 编号是硬编码在 `WRAPPERS` 字符串里的，改前面的等于
   把后面全错位。目前用到 `-1`（trace）和 `0..229`。
4. 参数想拿真类型就自己 `coerce()` / `fnum()` / `inum()` / `truthy()` 转一把。
5. 改完跑 `bash .workbuddy/run_qjs_test.sh`。

`default:` 分支会打一条 `[warn] 未实现的宿主函数编号`，编号漏了能立刻看出来。

---

## 6. 停止哨兵（`Function_Stop*`）

`WRAPPERS` 把五个常量铺成了 JS 全局，值逐字等于 `LuaUtils` 里那五个：

```js
globalThis.Function_Stop = "##PSYCHLUA_FUNCTIONSTOP";
```

脚本里跟 Lua 一样用：

```js
function onStartCountdown() {
    if (waitingForMyStuff) return Function_Stop;
}
```

链路：`js_invoke` 把回调的 return 字符串化进 `g_js_ret` → `emitTo` 经 `coerce` 还原 →
`JSPlayer.forward` 收集（遇到停就 `break`，同通道后面的脚本不再发） →
`PlayState.callOnScripts` 认 `Stop / StopLua / StopAll`，**直接 return，让 Lua / HScript 这次收不到**。

`ignoreStops` 只压「后面两条通道还发不发」，值照样往上交 —— 因为调用方(`onStartCountdown`
那些)就靠 `ret != Function_Stop` 决定要不要继续做动作，吞掉等于 JS 永远停不了引擎。

---

## 7. 脚本管理

| 函数 | 行为 |
|---|---|
| `addLuaScript('scripts/x.js')` | 新开一个 context，装宿主函数、预置全局、eval |
| `addHScript('scripts/x.js')` | 同上（JS 通道只管 `.js`，`.hx` 请走 Lua/HScript 那条） |
| `isRunning('scripts/x.js')` | 按路径后缀匹配，忽略大小写和斜杠方向 |
| `removeLuaScript('scripts/x.js')` | **真卸**：解绑 → 清掉它的 timer/tween 归属 → `JS_FreeContext` |

路径要写 `scripts/x.js`（`Paths.findScriptFile` 不会自动补 `scripts/`）。没写扩展名会补 `.js`。
注意 mod 是按版本分目录的：本体这棵树的脚本在 `mods/body/scripts/`，不是 `mods/scripts/`。

**`onCreate` 是装载完立刻发的**，不走 `callOnScripts` —— 那条队列里根本没有 `onCreate`
（Lua 是在 `FunkinLua` 构造末尾自己调的，HScript 是建实例时调的）。JS 在
`JSPlayer.loadFile()` 末尾跟一下，所以运行时 `addLuaScript` 进来的脚本也能立刻拿到 `onCreate`。
`onCreatePost` 之后的事件才走 `callOnScripts` 统一分发。

**一个坑**：脚本在回调里卸自己（或卸一个正在执行回调的脚本）时，C 栈上还压着那个
`JSContext`，当场 `JS_FreeContext` 是 use-after-free，实测直接崩。所以
`JSPlayer.unloadFile()` 发现 `handle == QuickJSHandler.current()` 就把句柄扔进
`pendingFree`，下一帧 `update()` 里再真释放。当前这一帧照常跑完。

---

## 8. `getVar` 有两层，别搞混

| 谁调 | 读的是哪 | 类型 |
|---|---|---|
| 脚本里 `getVar('x')`（宿主函数 195） | `MusicBeatState.variables`，跨脚本跨通道共享 | 字符串 |
| Haxe 侧 `JSScriptHost.getVar('x')` | **该脚本自己 context 的全局** | 数字/布尔/字符串原类型 |

Lua 那边是同一个两层结构（`FunkinLua.getVar` 走 `get(name)`，脚本里的 `getVar` 走
`MusicBeatState.variables`），所以这不是 JS 独有的怪癖，照着抄的。

读自己的全局走 `QuickJSHandler.getGlobal()`：C 侧 `js_get_typed_h` 带回类型标记
（0=undefined/null，1=bool，2=number，3=string，4=对象/函数），Haxe 侧还原。
对象只能拿 `String(obj)` 的结果 —— 桥过不去。

---

## 9. 脚本之间怎么互调

| 想干什么 | 用什么 | 备注 |
|---|---|---|
| 运行时加载另一个 `.js` | `addLuaScript('qjstest/x.js')` | 新开一个 context，装完立刻发 `onCreate` |
| 卸掉一个 `.js` | `removeLuaScript('qjstest/x.js')` | 真卸；卸自己会延到下一帧 |
| 在不在跑 | `isRunning('qjstest/x.js')` | 路径后缀匹配，忽略大小写和斜杠方向 |
| 现在有哪些在跑 | `getRunningScripts()` | 返回**数组** |
| 调别的脚本里的函数 | `callScript('qjstest/x.js', 'addOne', 41)` | 返回值原样带回（`addOne(41)` → `42`）；**只能传一个字符串参数** |
| 读别的脚本的全局 | `getGlobalFromScript('qjstest/x.js', 'tag')` | 返回**字符串**，类型丢了 |
| 写别的脚本的全局 | `setGlobalFromScript('qjstest/x.js', 'tag', v)` | 写入侧保留类型（数字/布尔原样） |
| 调自己这个 context 里的函数 | `callMethod('f', arg)` | |

拿不到**函数引用** —— 桥是字符串桥，`getGlobalFromScript` 只会把函数 `String()` 成源码文本。
想「回调式」互调只有两条路：`callScript` 按名字调，或者走全局变量传状态。

`addLuaScript` / `addHScript` 在 JS 通道里只认 `.js`。JS 脚本传 `.lua` 进去会被当 JS 解析，
直接 load failed；反过来 Lua 脚本 `addLuaScript('x.js')` 也不行（`findScript` 会补成 `x.js.lua`）。
唯一跨扩展名的地方是舞台 / 音符类型 / 事件脚本（`startLuasNamed` 会兜一次 `.js`）。

---

## 10. 和 Lua 的 API 差在哪（2026-11-16 实测对比）

方法：Lua 侧 `add_callback` + `addLocalCallback` 一共 **259** 个名字，JS 的 `WRAPPERS`
**261** 个，取差集。

**现在只剩 3 个（+1 个假阳性）**：

| 缺的 | 为什么 |
|---|---|
| `runHaxeCode` `runHaxeFunction` `addHaxeLibrary` | Haxe 互操作。JS 里跑不了 Haxe 源码，这条是刻意不做的 —— 别指望，也别去试 |
| `name` | 假阳性：那是 `JavaScriptUtils.hx` 注释里的一段文字被正则扫到了，不是真回调 |

2026-11-16 补齐的 23 个（都过了一遍冒烟测试）：

| 类别 | 补上的 |
|---|---|
| mod 设置 | `getModSetting`（不传 mod 名就用脚本自己所属的 mod） |
| 跨通道 | `setOnScripts` `setOnLuas` `setOnHScript` `callOnScripts` `callOnLuas` `callOnHScript`（`callOn*` 默认不发给自己，防死循环） |
| Shader | `initLuaShader` `setSpriteShader` `addShaderToCam` `removeCamShader` `clearCamShaders` |
| 成就 | `unlockAchievement` `isAchievementUnlocked` `achievementExists` `get/set/addAchievementScore` |
| Discord | `changeDiscordPresence`（就是 227 的同义别名）、`changeDiscordClientID` |
| 翻译 | `getTranslationPhrase` `getFileTranslation` |
| 其它 | `close()`（= 卸掉自己，走 `unloadFile`，延迟一帧释放） |

顺带修了一个**原本 Lua 那边也坏着**的东西：`addShaderToCam` / `removeCamShader` 里
`camera._filters` 在 flixel 5.6 已经改成 deprecated 的 get/set 属性，`Dynamic` 上取会抛
`Invalid field:_filters`。现在两个通道都改走公开的 `filters` / `setFilters`。

补 shader 的时候注意：`initLuaShader` 只负责**读文件**（找到 `.frag`/`.vert` 就返回 true），
真正编译是 `setSpriteShader` / `addShaderToCam` 里那步。编译失败会由
`ErrorHandledShader` 写一份 `bin/crash/shader_<名字>_<时间>.txt`，别把它当成引擎崩了。

---

## 11. 已知限制

- **最多 64 个 `.js`**。超了 `newContext` 返回 `-1`，日志里有 `could not create a context (more than 64 scripts?)`。
- **事件最多带三个参数**。`emitTo` 按桥支持的形态转发：零参、`(number)`、`(string)`、
  `(string, number)`、`(string, number, number)`、`(string, string)`。`onSpawnNote` 那种五个参数
  的只到前三个；第四个起 JS 拿不到（Lua / HScript 有）。
- **参数只有字符串和数字**。对象 / 数组过不了桥，`readJson` 返回的是 JSON 文本，脚本自己 `JSON.parse`。
- **对象过不了桥**。`instanceArg` 只能传 tag，脚本自己 `getVar` 取回来。
- **默认引擎是 Troll**。想真跑 QuickJS 得在 Gameplay Settings 里切。
- 每首歌重建 context，脚本里攒的状态不跨歌（跟 Lua 一致，但和「全局变量」的直觉不一样）。

---

## 12. 怎么验证它真的在跑

```bash
bash .workbuddy/run_qjs_test.sh bopeebo
```

流程：注入 `AutoTestState` → 编译（窗口最小化 + 静音 + 挪屏幕外，不抢焦点）→
把 `.workbuddy/luatest/qjs/*.js` 放进 `bin/mods/scripts/` → 以 `PE_AUTOTEST_JSENGINE=QuickJS`
自动开局 → 等结果文件 → 关进程 → 清走测试脚本。

产物在 `.workbuddy/testout/`：

| 文件 | 内容 |
|---|---|
| `qjs_smoke.txt` | 主结果，一行一条 PASS / FAIL，末尾 `DONE\|qjs` |
| `qjs_child.txt` | 第二个脚本（同名回调）自己写的，证明一文件一 context |
| `qjs_selfremove.txt` | 自卸之后那一帧还活着 |
| `qjs_js_log.txt` | 运行期 `js_log.txt` 的副本（trace / 报错 / 脚本装载记录） |
| `quickjs_smoke.txt` | 静态库链接自检（`ok 2` 才对） |

冒烟脚本覆盖：eval 生效、seedGlobals、共享变量表、属性读写、`Function_Stop` 拦下倒计时、
`addLuaScript` / `removeLuaScript` / `isRunning`、跨脚本读全局、timer 回调、同名回调不互顶、
回调里自卸不崩。
