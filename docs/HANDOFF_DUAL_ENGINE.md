# 交接文档：0.6.3 移植 + 原版 1.0.4 双引擎（2026-11-13）

> 上一份总交接在 `docs/AI_HANDOFF.md`（2026-11-09，讲本体兼容层）。
> 这份只讲 11-12 ~ 11-13 这几天做的事：0.6.3 移植收尾、原版 1.0.4 并进同一个 exe、
> 以及颜色和缩放两个坑。

## 一、现在有几个东西

| 位置 | 是什么 | 状态 |
|---|---|---|
| `D:/FNF/FNF-PE_RealQuickJs_Engine` | 主仓，PE 1.0.4 fork（本体） | 分支 `main`，**有一堆未提交改动**，见第四节 |
| `D:/FNF/PsychEngine_0.6.3` | 0.6.3 独立移植仓 | 分支 `dev_0.6.3`，已推到 fork，最新 `9659b03` |
| `https://github.com/Wqawa/FNF-PE_RealQuickJs_Engine` | 两者的远端 | `main` + `dev_0.6.3` 两条分支 |

0.6.3 仓的 remote 有两个：
- `origin` → ShadowMario/FNF-PsychEngine（上游，只 fetch）
- `fork` → Wqawa/FNF-PE_RealQuickJs_Engine（推这里）

**推送 0.6.3 仓必须在那个仓本地配证书**，否则报 `schannel: CRYPT_E_NO_REVOCATION_CHECK`：

```bash
git config --local http.sslbackend schannel
git config --local http.sslcainfo "C:/Users/S062PT/.git-ca-steamtools.pem"
```

主仓本来就配了，0.6.3 仓是新加的。

## 二、库版本（两边共用一份 `.haxelib`）

`.haxelib/openfl/.current` = `9.5.2`，`.haxelib/lime/.current` = `8.3.1`。

**注意**：官方 wiki 给 1.0.4 的清单是 openfl 9.3.3 / lime 8.1.2，我们试过并且**回退了**。
回退原因是 0.6.3 那边颜色全白，当时怀疑是 openfl，后来证明无关（真因是 `Std.parseInt`，
见第三节）。现在两棵树都用 9.5.2 / 8.3.1，保持一致，合并时少一个变量。

0.6.3 侧额外需要的两个库（主仓原本没有，已拷进 `.haxelib`，**不入库**，别人 clone 要自己装）：

- `flixel-ui 2.6.5`（`flixel.addons.ui.*` 的老 UI 基类）
- `hscript 2.5.0`

## 三、0.6.3 侧：颜色全白的真因（已修，已推）

**现象**：所有走十六进制字符串的颜色都变白；血条正常。

**根因**：cpp 目标上 `Std.parseInt` 由 hxcpp 运行时 `__hxcpp_parse_int` 实现，
32 位溢出时**饱和到 IntMax（0x7FFFFFFF）而不是环绕**。

```
0xff52A5EB → 2147483647 → 0x7FFFFFFF → 纯白
```

同一个表达式在 `haxe --interp` 下是 -11360789（正确），cpp 运行时是 2147483647。
原版 0.6.3 用 Haxe 4.2.5 + hxcpp 4.2.1（环绕），移植用 4.3.7 + 4.3.2（饱和），
**代码一个字没改，语义变了**。

**修法**：`FunkinLua.parseHexColor()` 逐位累加，让 32 位自然环绕，替换 14 处：

| 文件 | 处数 |
|---|---|
| `FunkinLua.hx` | 12（`setTextColor` / `setTextBorder` / `setTimeBarColors` / `setHealthBarColors` / `cameraFlash` / `cameraFade` / `makeGraphic` / `setObjectColor` / `getColorFromHex` …） |
| `editors/EditorLua.hx` | 1（`getColorFromHex`） |
| `CreditsState.hx` | 1（`getCurrentBGColor`） |

`getColorFromHex` 是最要命的一个：mod 写 `setProperty('dad.color', getColorFromHex('000000'))`，
拿回来是白色。

**后续补丁**（`9659b03`）：`setTimeBarColors('52A5EB', '')` 第二个参数是空串，
`parseHexColor('')` 兜底返回白，导致时间条空槽那半截变白。空串/null 现在显式映射成
`FlxColor.TRANSPARENT`（上游 `Std.parseInt('')` → null → 0 就是这个语义）。

细节写在 `D:/FNF/PsychEngine_0.6.3/PORTING_TO_1.0.4.md` 第十二节。

## 四、主仓：原版 1.0.4 并进同一个 exe（**未提交**）

做法：真·原版代码并行编译，不是"关兼容层"。

```
新增  source_vanilla/vanilla/…            157 个 .hx，原版 pe104 整体加 vanilla. 前缀
新增  source/Engine.hx                    读 bin/engine.txt，默认 body
新增  source/options/EngineSelectSubState.hx   NF 那套：选中→写文件→Sys.exit(0)
改    source/Main.hx:68                   main() 按 Engine.isVanilla() 分叉
改    source/options/OptionsState.hx      'Switch Engine' 菜单项
改    Project.xml                         classpath + --macro include('vanilla', true, ['vanilla.unused'])
改    building/build.sh                   SDK bin 进 PATH（rc.exe）；生成 返回本体.bat
```

产物 37 MB（原 30 MB），`obj/src/vanilla` 下 186 个 cpp，确认真的编了。

切换流程：设置 → Switch Engine → 选 Vanilla → 写 `engine.txt` + 退出 → 重启进原版；
原版侧没有我们的菜单，用 bin 根目录的 `返回本体.bat` 写回 `body`。

已知限制：
1. `vanilla.unused` 的 7 个文件没编（上游死代码，依赖 faxe / heaps）
2. HScript 侧只覆盖别名表内的类，表外的冷门类仍会落到本体
3. 两棵树的 `__init__` 都会跑（DPI 标志等，无副作用）

## 五、11-13 凌晨改的三处（也未提交，未验证）

### 1. 静态初始化只跑选中的那棵

`substates/OutdatedSubState.hx`（两棵树都改）里原来是：

```haxe
public static var updateVersion:String = CoolUtil.checkForUpdates();
```

静态字段初始化 hxcpp 无条件执行，两棵树各发一次更新检查。改成 `(get, never)` 惰性属性，
首次访问才查。

### 2. HScript 导航到 vanilla

`crowplexus/hscript/Interp.getOrImportClass()` 查表顺序是 **先 `Iris.proxyImports`，
再 `Tools.getClass`**。所以在 `backend/ScriptClassAliases.hx` 里加了 `remapToVanilla()`：
vanilla 模式下遍历整张别名表，用 `Type.getClassName()` 取本体全名、拼 `vanilla.` 解析，
成功就替换表项，并把原全名也注册进 proxyImports。`resolve()` 里同款优先逻辑。

### 3. 缩放偏移 → 改整数倍窗口

实测几何（150% DPI 屏）：

```
dpi=144  bounds=1920x1080
window=1632x918      ← 1280*1.5=1920 被 85% 上限卡到 1632
flxg=1280x720
RatioScaleMode → scale=1.275,1.275
```

1.275 是非整数缩放。平时不明显，但 Gumball cp 的 childplayV2 给 `camGame` 和 `camHUD`
都挂了 `ShaderFilter`（色差），滤镜按画布尺寸采样，非整数缩放就让画面和 HUD 整体错开一点。

`backend/Native.hx` 改成只按**整数倍**放大：

```haxe
var factor = floor(min(displayW*0.85/1280, displayH*0.85/720));
if (factor < 1) factor = 1;
winW = 1280 * factor; winH = 720 * factor;
```

1920x1080 上 factor=1 → 窗口 1280x720，复测 `scale=1,1 offset=0,0`。

**代价**：150% DPI 屏上窗口变物理 1280x720，看着偏小。要舒服就得加"窗口倍率"选项，
但选 1.5x 偏移会回来。

vanilla 那侧没改，保持原版 `1280*dpi` 行为。

## 六、构建与调试手册（这几天踩的坑）

```bash
# 主仓
cd D:/FNF/FNF-PE_RealQuickJs_Engine && bash building/build.sh
# 0.6.3（用主仓的库根编）
bash .workbuddy/tmp/build063.sh
```

- **`rc.exe` 找不到**：lime 8.3 起多一步资源编译。PATH 里必须写 **POSIX 路径**
  `/d/FNF/tools/rc`，写 `D:/FNF/tools/rc` 不生效（MSYS 不认）。那份 rc.exe + rcdll.dll
  是从 SDK 拷出来的，因为原路径带空格，hxcpp 拼命令行会炸。
- **编译卡死**：日志十几分钟不增长、`cl.exe` 挂着。`taskkill //F //IM cl.exe` 后重跑，
  通常 1 分钟内接着编完。
- **`rm -rf` 被安全策略拦**（>50 文件）：清 obj 用 `mv obj obj_stale_时间戳` 改名。
- **`LNK1136`**：`.cache/hxcpp` 里有 0 字节 obj，删掉那个文件。
- **`reg.exe` 被拦**：沙箱噪声，忽略。
- **`LNK2001: hx::tlsStackContext`**：换了 hxcpp 版本但没清 obj，旧对象文件版本不一致。

## 六点五、资产按版本分组（2026-11-13 下午）

之前 `assets/` 是扁平的（`assets/shared`、`assets/week1`…），所有版本共用一套。
为了往里塞 0.6.3，改成按版本分目录。

### 目录结构

```
assets/
  base_game/       共享的官方素材源，不打包，由 prep_assets.sh 铺进 bin
  body/            修改版 1.0.4 —— fonts shared embed videos songs
                   week_assets secrets translations
  1.0.4/           原版 Psych Engine 1.0.4 —— 同样是上面那一套（复制品）
  exclude/ meta/   打包/发布用的，不参与运行时寻路，留在原处
mods/
  body/            本体的 mod + modsList.txt
  1.0.4/           原版的 mod + modsList.txt
  global/          全局 mod，三个版本都读
```

`body` 这个名字跟 `bin/engine.txt` 里的 `body` / `vanilla` 是同一套术语，`Engine.BODY` 现成能用。

### 代码怎么走

只有一个开关：`Paths.VERSION_DIR`。

```haxe
// source/backend/Paths.hx
public static var VERSION_DIR:String = 'body';

// source_vanilla/vanilla/backend/Paths.hx
public static var VERSION_DIR:String = '1.0.4';
```

所有路径都由它派生，改动过的就这几行：

| 函数 | 变成 |
|---|---|
| `getFolderPath(file, folder)` | `assets/$VERSION_DIR/$folder/$file` |
| `getSharedPath(file)` | `assets/$VERSION_DIR/shared/$file` |
| `findScriptFile` 的根兜底 | `assets/$VERSION_DIR/$file` |
| `video(key)` | `assets/$VERSION_DIR/videos/…` |
| `font(key)` | `assets/$VERSION_DIR/$folderKey` |
| `mods(key)` | `mods/$VERSION_DIR/$key` |
| `modsListPath()` | `mods/$VERSION_DIR/modsList.txt`（新增） |
| `globalMods(key)` | `mods/global/$key`（新增） |

`Mods.hx` 里三处硬编码 `'modsList.txt'` 全部换成 `Paths.modsListPath()`，
`directoriesWithFile` 里全局 mod 优先查 `mods/global/`、再退回本版本目录。

### 新增一个版本要做什么

1. `assets/<ver>/` 放一套素材
2. 新版本的 Paths 里 `VERSION_DIR = '<ver>'`
3. `prep_assets.sh` / `build.sh` 里加一条拷贝
4. Project.xml 加 `<assets path="assets/<ver>/…">`（只有要打进 exe 的才需要）
5. `OptionsState` 的引擎列表加一项，`EngineSelectSubState` 的 `options`/`keys` 加一项

### 两个注意

- **`assets/1.0.4` 不打包进 exe**，靠 `prep_assets.sh` 铺到 `bin/assets/1.0.4`。
  原版模式全靠磁盘文件，`existsOnDiskOrManifest()` 本来就先查磁盘，所以能读到。
  真要单文件分发时得把这块补上。
- **`base_game` 在 1.0.4 那边用硬链接**（`cp -rl`），省 470M。改 `assets/base_game`
  里的文件会同时影响两边 —— 它是共享素材源，本来就是给两边用的，不算 bug。

## 六点六、0.6.3 也接进来了（2026-11-13 中午）

现在同一个 exe 里跑三棵树，靠 `bin/engine.txt` 选：

| engine.txt | 走哪棵 | 源码 |
|---|---|---|
| `body`（默认） | 本仓 fork | `source/` |
| `vanilla` | 原版 PE 1.0.4 | `source_vanilla/vanilla/` |
| `pe063` | 0.6.3 | `source_063/pe063/` |

`Engine.BODY / VANILLA / PE063`，`Engine.current()` 认这三个值，不认识就回 body。
三份 Options 菜单里都有 `Switch Engine`，选完写 engine.txt + `Sys.exit(0)`。

### 0.6.3 是怎么搬过来的

1. `D:/FNF/PsychEngine_0.6.3/source` 整个拷到 `source_063/pe063/`
2. 跑 `.workbuddy/tmp/ns_pe063.py source_063/pe063` 加前缀（package → `pe063.*`，import 跟着改）
3. `Project.xml` 加 `<classpath name="source_063" />` 和 `haxelib name="flixel-ui"/"hscript"`
4. `Paths` 里 `getPreloadPath` → `assets/0.6.3/`，`mods()` → `mods/0.6.3/`

**前缀化漏掉的四处**（脚本只管 package 和 import，下面这些是手工补的）：

| 漏的东西 | 表现 | 修法 |
|---|---|---|
| `@:access(...)` / `@:allow(...)` 里的类路径 | `Cannot access private constructor` | 参数里加 `pe063.` |
| `@:allow(DiscordClient)` 这种**模块内的类** | 权限失效 | 脚本只认文件名 stem，模块内的类要单独补 |
| 内联包引用 `editors.Xxx` / `options.Xxx` | `Type not found : editors.ChartingState` | 正则 `(?<![\w.])(editors\|animateatlas\|options)\.([A-Z])` |
| `import Discord.DiscordClient` | `Type not found : Discord` | 要写 `import pe063.Discord.DiscordClient`（模块.类型） |

`pe063/Discord.hx` 里的类叫 `DiscordClient`（文件名是 Discord），Haxe 的 import 必须写成
`模块.类型`，写成 `pe063.DiscordClient` 找不到。

### 0.6.3 的资产：library selector

0.6.3 和 1.0.4 的寻路机制不一样 —— 它用 lime 的 `library`：

```haxe
getLibraryPathForce(file, "shared")  →  "shared:assets/shared/$file"
```

`shared:` 是库名，后面的 `assets/shared/...` 是**库内路径**，不是磁盘路径。
所以 `Project.xml` 里磁盘路径写 `assets/0.6.3/shared`、库内路径必须保持 `assets/shared`：

```xml
<assets path="assets/0.6.3/shared" library="shared" rename="assets/shared" ... />
```

`rename` 写 `assets/0.6.3/shared` 的话库内路径就对不上了，运行时全部 404。

`preload` 是例外：它走 `getPreloadPath()`，我们改成了 `assets/0.6.3/$file`，
所以 `rename="assets/0.6.3"`。

### 踩到的两个运行时崩溃

1. **`[file_contents,assets/images/titleEnter.xml]`** — `TitleState` 里有一段兜底硬编码
   `"assets/images/titleEnter.png"`，改成 `assets/0.6.3/...`。
2. **`[file_open,mods/1.0.4/modsList.txt]`** — 见上面那节，`Mods.updateModList()` 写列表前
   要确保 `mods/<版本>/` 目录存在。

## 七、下一步（优先级）

1. **验证第五节三处改动**：跑 childplayV2 看偏移还在不在；看启动日志只剩一条
   "checking for updates"；在 vanilla 模式下跑个用 HScript 的 mod。
2. 验证通过后把主仓这批改动**整理成一个 commit**（现在全在工作区，9 个文件 + `source_vanilla/`）。
3. **把 0.6.3 接进引擎选择**：`source_vanilla` 那套流程再来一遍，目标
   `source_063/engine063/…`，菜单加第三项。0.6.3 的坑已经在
   `PORTING_TO_1.0.4.md` 里记全了，照着走。
4. 窗口倍率选项（可选）：1x / 1.5x 让用户自己选，1.5x 会带回偏移。

## 八、一句话教训

**换工具链版本时，stdlib 函数的语义可能变，而代码一个字没动。**
`Std.parseInt` 的饱和是这几天最贵的坑——花了四个探针、五次运行才定位。
以后遇到"代码没改但行为变了"，先怀疑 stdlib / hxcpp 运行时，再去查库版本。
