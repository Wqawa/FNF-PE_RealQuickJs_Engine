# Psych Engine 0.6.3 → 1.0.4 编译环境移植记录

## 一、目标与结果

把 **Psych Engine 0.6.3（tag 0.6.3，commit eb0ade3，2022-10-18）** 的源码，放到 **Psych Engine 1.0.4 所使用的依赖栈**上编译运行。

- 编译结果：`export/release/windows/bin/PsychEngine.exe`（28.7 MB），正常启动、正常游玩。
- 游戏逻辑、UI、mod 加载、Lua API、视频播放均保持 0.6.3 原有行为，没有删功能、没有改数值。
- 所有改动都是为了适配新库的 API 和类位置，不涉及玩法调整。

## 二、依赖版本对照

| 库 | 0.6.3 理想环境（PDF 教程） | Psych 1.0+ 官方（wiki / 1.0.4 的 Project.xml） | 本项目实际 |
|---|---|---|---|
| Haxe | 4.2.5 | 4.3.2 | **4.3.7** |
| hxcpp | 4.2.1 | — | 4.3.2（git） |
| flixel | 5.2.2 | 5.6.1 | **5.6.1** ✅ |
| flixel-addons | 3.0.2 | 3.2.2 | **3.2.2** ✅ |
| lime | 8.0.1 | 8.1.2 | **8.1.2** ✅ |
| openfl | 9.2.1 | 9.3.3 | **9.3.3** ✅ |
| flixel-ui | 2.5.0 | 不依赖 | **2.6.5**（0.6.3 必需） |
| hscript | 2.5.0 | hscript-iris 1.1.3 | **官方 2.5.0**（刻意不同） |
| linc_luajit | git | git | 0.0.7 |
| hxCodec | 2.5.1 | 不用 | **移除** |
| hxvlc | — | 2.0.1 | **2.0.1** ✅ |
| discord_rpc (linc) | git | 不用 | **移除** |
| hxdiscord_rpc | — | 1.2.4 | **1.2.4** ✅ |
| tjson | — | 1.4.0 | 不装（0.6.3 用 haxe.Json） |

带 ✅ 的是和官方清单完全一致的项。两处刻意不同：

- **hscript**：1.0.4 用 hscript-iris（包名 `crowplexus.hscript`），而 0.6.3 全项目 `import hscript.*`，连 flixel 自带的 debug console 都依赖官方包名。这一项无法对齐。
- **flixel-ui**：1.0.4 已经不依赖它，但 0.6.3 的编辑器、输入框都用，删了编不过。

Haxe 保持 4.3.7（官方建议 4.3.2，同属 4.3.x 补丁系列，向后兼容，且降级会影响机器上其他工程）。

> 注意：本机 `haxe/lib` 里 flixel 同时存在 `git`（6.1.2，Codename 用）和 `5,6,1`，靠 Project.xml 的 `version` 属性定向，不动全局 current。

## 三、Project.xml 改动

```xml
<haxelib name="flixel" version="5.6.1" />
<haxelib name="flixel-addons" version="3.2.2" />
<haxelib name="hscript" version="2.5.0" />
<define name="hscriptPos" />
<haxedef name="hscript" />            <!-- 新增：0.6.3 的 HScript 模块靠这个宏开启 -->
<haxelib name="flixel-ui" version="2.6.5" />
<haxelib name="linc_luajit" if="LUA_ALLOWED"/>
<haxelib name="hxvlc" if="VIDEOS_ALLOWED" version="2.0.1"/>       <!-- 原 hxCodec -->
<haxelib name="hxdiscord_rpc" if="desktop" version="1.2.4"/>      <!-- 原 discord_rpc -->
```

lime / openfl 不在 Project.xml 里锁版本（1.0.4 官方也是这么做的），而是用 `haxelib set` 切全局 current：

```
haxelib set lime 8.1.2
haxelib set openfl 9.3.3
```

两个要点：

1. **新增 `-D hscript`**。0.6.3 的 `FunkinLua.initHaxeModule()` 和 `class HScript` 都包在 `#if hscript` 里，但 Project.xml 原本没有定义这个宏，原版是靠 hscript 库的额外参数生效的。换库后必须显式定义，否则 Lua 里所有 `.hx` 相关逻辑会缺符号。
2. **必须用官方 hscript，不能用 hscript-iris**。hscript-iris 的包名是 `crowplexus.hscript`，而 0.6.3 全项目 `import hscript.Interp / Parser / Expr`，连 flixel 自带的 debug console 也依赖 `hscript.*`。强行用 iris 会直接报 `Type not found : hscript.Expr`。

## 四、删除的库覆盖文件（7 个）

0.6.3 为了修老版 flixel / lime 的 bug，在 `source/` 下放了 7 个**覆盖库源码**的文件。这些文件会让 classpath 优先使用旧实现，在新库下必然类型冲突。逐一核对后，6 个移除（备份在 `_removed_overrides/`），`FPS.hx` 保留：

| 文件 | 处理 |
|---|---|
| `source/flixel/system/FlxSound.hx` | 移除。flixel 5.6 的 `FlxSound` 已移到 `flixel.sound.FlxSound`，且自带 `pitch` 字段。旧的覆盖类留在 `flixel.system` 下会变成另一个类型，全项目报 `flixel.system.FlxSound should be flixel.sound.FlxSound` |
| `source/flixel/animation/FlxAnimationController.hx` | 移除。flixel 5.6 已内置 `finishCallback:(String)->Void` |
| `source/flixel/addons/display/FlxRuntimeShader.hx` | 移除。flixel-addons 3.2.2 已包含同等实现 |
| `source/flixel/addons/ui/FlxInputText.hx` | 移除。flixel-ui 2.6.5 已内置 Ctrl+C/V 支持 |
| `source/flixel/addons/ui/FlxUIInputText.hx` | 移除。同上 |
| `source/lime/_internal/backend/native/NativeAudioSource.hx` | 移除。lime 8.1 的 native audio 内部结构已重写，旧补丁无法编译 |
| `source/openfl/display/FPS.hx` | **保留**。openfl 自带的 `FPS` 只输出 `FPS: xx`，没有内存显示；0.6.3 的版本还会把帧数钳到 `ClientPrefs.framerate`（否则 60 帧上限会显示成 63/64），并在超过 3000MB 或帧数低于一半时变红。`__enterFrame(deltaTime:Float)` 的签名在 openfl 9.3.3 下依然匹配，直接用 |

## 五、代码改动明细

### 1. `source/Main.hx`

**FlxGame 构造函数去掉 zoom 参数。**

flixel 5.6 移除了 `FlxGame` 的 `zoom` 参数：

```haxe
// 0.6.3
addChild(new FlxGame(gameWidth, gameHeight, initialState, zoom, framerate, framerate, skipSplash, startFullscreen));
// 修改后
addChild(new FlxGame(gameWidth, gameHeight, initialState, framerate, framerate, skipSplash, startFullscreen));
```

原本的 `zoom` 计算保留，但**不能再反算 `gameWidth` / `gameHeight`**：

```haxe
if (zoom == -1)
{
    var ratioX:Float = stageWidth / gameWidth;
    var ratioY:Float = stageHeight / gameHeight;
    zoom = Math.min(ratioX, ratioY);
    // 不要写 gameWidth = Math.ceil(stageWidth / zoom);
}
```

老代码把画布尺寸改成"窗口尺寸 ÷ 缩放比"，再靠删掉的那个 `zoom` 参数缩回去。参数没了之后，画布被放大到 1300 多像素却没有缩放，HUD 按放大后的宽度布局，屏幕上只能显示左半边，看起来就是整体偏左。现在画布固定 1280×720，窗口缩放由 `FlxG.scaleMode`（默认 `RatioScaleMode`，等比缩放并居中）接管。

另外 `stage.align` 从字符串 `"tl"` 改成了常量 `StageAlign.TOP_LEFT`。openfl 9.5.2 才修好对 `"tl"` 这类缩写的解析，9.3.3 认不了，会导致舞台对齐失效。

### 2. `source/PlayState.hx`

**(a) 全局动画速度：`FlxAnimationController.globalSpeed` → `FlxG.animationTimeScale`**

flixel 5.6 删掉了 `globalSpeed`，但新增了等价的 `FlxG.animationTimeScale`（`FlxAnimationController.update` 里就是乘这个值）。两处：

- `set_playbackRate()` 里：`FlxAnimationController.globalSpeed = value` → `FlxG.animationTimeScale = value`
- `destroy()` 里：`FlxAnimationController.globalSpeed = 1` → `FlxG.animationTimeScale = 1`

**(b) 视频播放：hxCodec 的 `vlc.MP4Handler` → hxvlc 的 `FlxVideoSprite`**

import 改为：

```haxe
#if VIDEOS_ALLOWED
import hxvlc.flixel.FlxVideoSprite;
#end
```

`startVideo()` 主体重写（逻辑不变：找不到文件就 `startAndEnd()`，播完也 `startAndEnd()`）：

```haxe
// hxvlc 2.0.1 要先等 libvlc 初始化完成，再 load + 延迟 play
hxvlc.util.Handle.initAsync(function(success:Bool) {
    if (!success) { FlxG.log.warn('Couldnt initialize hxvlc'); startAndEnd(); return; }

    var video:FlxVideoSprite = new FlxVideoSprite(0, 0);
    video.active = false;
    video.antialiasing = ClientPrefs.globalAntialiasing;
    video.bitmap.onFormatSetup.add(function() {
        if (video.bitmap != null && video.bitmap.bitmapData != null) {
            var scale:Float = Math.min(FlxG.width / video.bitmap.bitmapData.width, FlxG.height / video.bitmap.bitmapData.height);
            video.setGraphicSize(video.bitmap.bitmapData.width * scale, video.bitmap.bitmapData.height * scale);
            video.updateHitbox();
            video.screenCenter();
        }
    });
    video.bitmap.onEndReached.add(function() {
        remove(video);
        video.destroy();
        startAndEnd();
    });
    video.load(filepath);
    add(video);
    new FlxTimer().start(0.001, function(tmr:FlxTimer) { video.play(); });
});
```

**踩过的两个坑**：

1. `play()` 不能紧跟在 `load()` 后面，要延后一帧。否则视频尺寸回调还没走完，画面是黑的。
2. hxvlc 2.0.1 和 2.3.1 的接口不同：2.3.1 有 `precache()`（内部帮你处理 libvlc 初始化），2.0.1 没有，必须自己调 `Handle.initAsync()` 等初始化完成。用错版本会直接编译不过。

另外 2.0.1 的 `load()` 内部会先 `FileSystem.exists()` 再 `FileSystem.absolutePath()`，文件不存在时返回 `false` 而不是抛异常，所以路径检查放在调用前就够了。

**(c) 两处 `FlxG.sound.music.pitch` 加空值保护**

`keyShit()` 和倒计时后的自动播放判定里都有：

```haxe
else if (boyfriend.animation.curAnim != null && FlxG.sound.music != null && boyfriend.holdTimer > ...)
```

原因：倒计时阶段 `FlxG.sound.music` 还没被 `startSong()` 创建（`playMusic` 在 `startSong` 里才调），此时访问 `.pitch` 会空引用崩溃。加了 `FlxG.sound.music != null` 后短路，判定逻辑本身不变（音乐没起时本来就没有音符需要判定）。`Character.hx:301` 原版就有同样的 null 检查，说明作者知道这个坑，只是这两处漏了。

### 3. `source/FunkinLua.hx`

**(a) `LuaL.error(...)` → `luaTrace(...)`（5 处）**

linc_luajit 0.0.7 把 `luaL_error` 的绑定注释掉了（`llua/LuaL.hx:63`），`LuaL.error` 不再存在。原来的调用都是参数为 nil 时的防御性报错：

```haxe
// 原来
LuaL.error(lua, "bad argument #1 to 'callOnLuas' (string expected, got nil)");
// 改为
luaTrace("bad argument #1 to 'callOnLuas' (string expected, got nil)", true, false, FlxColor.RED);
```

涉及 `callOnLuas`、`callScript`、`getGlobalFromScript` 共 5 处。效果仍是"打一条红色错误并 return"，参数非法时行为不变。

**(b) `Lua.isboolean()` 返回值是 Int，不能直接当条件（3 处）**

```haxe
// 原来
}else if(Lua.isboolean(luaInstance.lua,-1)){
// 改为
}else if(Lua.isboolean(luaInstance.lua,-1) != 0){
```

`toboolean` 在新版返回 Bool，`isboolean` 仍是 Int，所以只需要改条件判断。

**(c) `songLength` 加空值保护**

```haxe
set('songLength', FlxG.sound.music != null ? FlxG.sound.music.length : 0);
```

全局脚本（`mods/scripts/*.lua`）在 `PlayState.create()` 里加载，这时音乐还没创建。原来这行会直接崩（`FunkinLua.hx:125`）。歌曲内脚本（`mods/<mod>/scripts/<song>.lua`）在 `startSong` 之后才加载，此时 `songLength` 是真实长度，不受影响。

### 4. `source/Discord.hx`（整个文件重写）

`linc_discord-rpc`（`discord_rpc.DiscordRpc`）→ `hxdiscord_rpc`（`hxdiscord_rpc.Discord`）。

对外接口完全保持原样，调用方（几十个 state 里的 `DiscordClient.changePresence(...)`）一个字都没改：

- `DiscordClient.initialize()`
- `DiscordClient.shutdown()`
- `DiscordClient.changePresence(details, state, ?smallImageKey, ?hasStartTimestamp, ?endTimestamp)`
- `DiscordClient.addLuaCallbacks(lua)`
- `DiscordClient.isInitialized`

内部改成 hxdiscord_rpc 的事件回调 + `RunCallbacks` 轮询线程，presence 用一个 `DiscordPresence` 包装类做 String ↔ `cpp.ConstCharStar` 转换（照搬 1.0.4 的写法）。clientID 保持原值 `863222024192262205`，largeImageKey 仍是 `icon`，文本仍是 `Engine Version: <版本>`。

### 5. `source/editors/ChartingState.hx`

```haxe
// 原来
@:access(flixel.system.FlxSound._sound)
// 改为
@:access(flixel.sound.FlxSound)
```

频谱波形功能要读 `FlxSound._sound.__buffer`，而 `FlxSound` 换包了。改成整个类级别的 access，`_sound` 和 `__buffer` 都能访问，波形生成逻辑不变。

### 6. `source/Paths.hx` + `source/FunkinLua.hx`（缺失音效导致 lua 脚本中断）

**现象**：Gumball cp 的 `HUD-countdown.lua` 在 `Childs-Play-V2` 开头，倒计时数到 3 就卡住，BF 停在开枪姿势，之后点箭头 BF 会瞬移，无报错无崩溃；把 lua 禁用就正常。

**根因**：脚本里 `playSound('3')` / `playSound('2')` 找的是 `3.ogg` / `2.ogg`，而 mod 的 `sounds/` 里只有 `intro1/intro2/intro3/introGo`，文件根本不存在。

`Paths.returnSound()` 会无条件执行 `Sound.fromFile('./' + path)`。**openfl 9.5 的 `Sound.fromFile` 遇到不存在的文件直接抛 `IOError`**（老版 openfl 只是返回一个空音效），这个异常把整个 lua 回调打断，于是后面那行 `runTimer('intro2', 0.67)` 根本没执行 —— 倒计时永远停在 3，BF 也就一直保持 '3' 的动作。

**修复**：

`Paths.returnSound()` 加载前先判断文件是否存在，不存在就返回 `null`（恢复老 openfl 的静默失败语义）：

```haxe
if(!currentTrackedSounds.exists(gottenPath))
#if MODS_ALLOWED
{
    var realPath:String = './' + gottenPath;
    if(!FileSystem.exists(realPath))
    {
        trace('Could not find sound asset: $realPath');
        return null;
    }
    currentTrackedSounds.set(gottenPath, Sound.fromFile(realPath));
}
#else
```

`FunkinLua` 的 `playSound` 加上判空：

```haxe
var soundAsset = Paths.sound(sound);
if(soundAsset == null) {
    luaTrace('playSound: Could not find sound "$sound"', false, false, FlxColor.RED);
    return;
}
```

这样缺音效时只会在控制台留一条记录，脚本继续往下跑，和 0.6.3 原版表现一致。

## 六、环境层面的修复（不属于代码改动，但编译必须做）

这几条是本机环境的问题，换台机器可能不需要：

1. **`haxelib run lime` 直接崩溃**（`Primitive not found : lime@lime_audio_load`）。
   原因：`haxelib` 把 lime 绑定到了 Codename Engine 的 dev 分支（`D:/FNF/CodenameEngine-main/.haxelib/lime/git/`），那套 fork 的 ndll 没有 `lime_audio_load` 符号。
   处理：`haxelib dev lime`（清除绑定），改用官方 lime 8.3.1。
   **如果你之后要编 Codename，需要重新绑定**：`haxelib dev lime D:/FNF/CodenameEngine-main/.haxelib/lime/git/`

2. **hxcpp git 版需要重建命令行工具**。首次编译会卡在交互提示，执行：
   ```
   cd C:/HaxeToolkit/haxe/lib/hxcpp/git/tools/hxcpp
   haxe compile.hxml
   ```

3. **MSVC / Windows SDK 环境变量需要手动给**。hxcpp 通过 `reg.exe` 查 SDK 路径，在本机被安全策略拦截，导致找不到 `crtdbg.h` / `rc.exe`。编译前设置：

   ```powershell
   $sdk  = "C:\Program Files (x86)\Windows Kits\10"
   $msvc = "D:\VS2026\main\VC\Tools\MSVC\14.51.36231"
   $env:INCLUDE = "$sdk\Include\10.0.26100.0\ucrt;$sdk\Include\10.0.26100.0\um;$sdk\Include\10.0.26100.0\shared;$msvc\include"
   $env:LIB     = "$sdk\Lib\10.0.26100.0\ucrt\x64;$sdk\Lib\10.0.26100.0\um\x64;$msvc\lib\x64"
   $env:PATH    = "$sdk\bin\10.0.26100.0\x64;$msvc\bin\Hostx64\x64;" + $env:PATH
   ```

4. **hxcpp 增量编译有时不重编改过的文件**（本次 `Main.cpp` 就中招，改了入口却不生效）。遇到"改了代码行为没变"，删掉对应的 obj 强制重编，路径形如：
   `export/release/windows/obj/obj/msvc1964-nc/<hash>_Main.obj`

## 七、编译命令

```powershell
# 先按第六节第 3 条设置环境变量，然后：
cd D:\FNF\PsychEngine_0.6.3
haxelib run lime build windows
```

产物：`export/release/windows/bin/PsychEngine.exe`

## 八、验证记录

| 项目 | 结果 | 说明 |
|---|---|---|
| Haxe 编译 | 通过 | 无 error，只有 `WDeprecated` 警告（`flixel.system.FlxSound` 等旧路径） |
| C++ 编译 + 链接 | 通过 | 首次全量约 11 分钟，增量 40 秒~2 分钟 |
| 启动画面 | 通过 | FPS 62，lime / flixel 初始化正常 |
| 闪光警告页（首次启动） | 通过 | 与原版 0.6.3 一致，可正常跳过 |
| 标题画面 | 通过 | FNF logo、GF 角色、音箱、"Press Enter to Begin" 全部正常渲染 |
| 游戏内 | 通过 | 角色（Daddy Dearest / BF / GF）、音符轨道、判定（SICK）、分数、血条、时间条、舞台背景全部正常 |
| 音频 | 通过 | ogg 解码正常（Inst / Voices `length=76800`），opening 音效可播 |
| Lua mod | 通过 | 标准 mod 结构（`mods/TestMod/pack.json` + `scripts/bopeebo.lua`），`onCreate` 回调 + `setProperty('boyfriend.angle', 45)` 实际生效，画面角色被旋转 |
| 缺失音效的 mod 脚本 | 通过 | Gumball cp / `Childs-Play-V2` 的自定义倒计时脚本（`playSound('3')` 等音效不存在）能完整跑完 3→2→1→Go 并换回原角色，不再卡住 |
| 视频播放 | 部分 | 在 hxvlc **2.3.1** 下实测通过（`onFormatSetup` 拿到 1280x720，画面正常）。降到官方要求的 **2.0.1** 后按官方示例重写了 `startVideo`，目前只过了编译，**没有实测播出** |
| Discord RPC | 通过 | 标题画面初始化不崩；因无 Discord 客户端未验证在线状态显示 |

## 九、已知限制

1. **窗口缩放的实现方式变了**。0.6.3 靠 `FlxGame` 的 `zoom` 参数自适应窗口，flixel 5.6 删了这个参数，改用 `FlxG.scaleMode`（默认 `RatioScaleMode`）。在 1280×720 窗口下两者表现一致；如果把窗口拉到非 16:9 比例，新版会等比留黑边，而老版会改变游戏内部分辨率去填满。这是引擎层面的移除，无法完全复刻。
2. **`songLength` 在全局脚本里为 0**。全局 lua（`mods/scripts/`）在音乐创建前加载，拿不到歌曲长度。原版 0.6.3 在这里会直接崩溃，所以这是修好而不是降级；歌曲内脚本不受影响。
3. **`fix` 类的小改动都写在第五节**，没有额外改任何游戏数值、判定窗口、动画帧率。
4. **视频只验证到编译**。hxvlc 2.0.1 要自己调 `Handle.initAsync()`，代码按官方示例写的，但没有实际播过一次。如果某个 mod 的 cutscene 黑屏，先查这里。

## 十、改动文件汇总

```
M  Project.xml
M  source/Discord.hx              （重写：hxdiscord_rpc）
M  source/FunkinLua.hx            （LuaL.error ×5、isboolean ×3、songLength 保护、playSound 判空）
M  source/Main.hx                 （FlxGame 去 zoom、不再反算画布尺寸、stage.align 用常量）
M  source/MainMenuState.hx        （左下角版本号 0.6.2 -> 0.6.3）
M  source/Paths.hx                （缺音频时返回空音效，不再抛 IOError）
M  source/PlayState.hx            （animationTimeScale ×2、hxvlc 视频、music 判空 ×2）
M  source/editors/ChartingState.hx（@:access 换包）
D  source/flixel/system/FlxSound.hx
D  source/flixel/animation/FlxAnimationController.hx
D  source/flixel/addons/display/FlxRuntimeShader.hx
D  source/flixel/addons/ui/FlxInputText.hx
D  source/flixel/addons/ui/FlxUIInputText.hx
D  source/lime/_internal/backend/native/NativeAudioSource.hx
```

`source/openfl/display/FPS.hx` 属于 0.6.3 自带的覆盖版，保留在原位（提供内存显示和帧数钳制）。

删除的 7 个文件没有真正删掉，备份在项目根目录的 `_removed_overrides/` 下，需要对照或回滚可以直接取回。

---

## 十一、与主仓编译栈对齐（2026-11-12）

为了让这棵树能和 `FNF-PE_RealQuickJs_Engine`（PE 1.0.4 fork）共用一个 `.haxelib`，把依赖再往下压了一档，回到官方 wiki 那份清单：

| 库 | 之前 | 现在（= 主仓） |
|---|---|---|
| lime | 8.3.1 | **8.1.2** |
| openfl | 9.5.2 | **9.3.3** |
| hxvlc | 2.3.1 | **2.0.1** |
| hxdiscord_rpc | 1.1.2 | **1.2.4** |
| linc_luajit | 0.0.7 发布版 | **git @1906c4a** |
| flixel / flixel-addons | 5.6.1 / 3.2.2 | 不变 |

`flixel-ui 2.6.5` 和 `hscript 2.5.0` 是 0.6.3 侧额外需要的，主仓原本没有，已一并放进它的 `.haxelib`。

### 代码上要跟着改的两处

1. **`Lua.isboolean` 返回值类型变了。** 0.0.7 里是 `Int`，git 版包了一层返回 `Bool`：

   ```haxe
   // 0.0.7：   if(Lua.isboolean(lua, -1) != 0)
   // git 版：  if(Lua.isboolean(lua, -1))
   ```

   `FunkinLua.hx` 共 3 处，改完即过。

2. **`flixel.system.FlxSound` 已废弃**，18 个文件的导入改成 `flixel.sound.FlxSound`，清掉 50+ 条 `WDeprecated`。只改 import，不涉及调用。

### 编译方式

不再用全局 haxelib，把库根指到主仓：

```bash
export HAXELIB_PATH=/d/FNF/FNF-PE_RealQuickJs_Engine/.haxelib
haxelib run lime build windows
```

### 验证

| 项目 | 结果 |
|---|---|
| Haxe 编译 | 通过，0 error |
| 剩余警告 | 51 条 `flixel.addons.ui.FlxInputText` deprecated、6 条 Int64→Int、1 条 `FlxCamera.defaultCameras`，均为 0.6.3 旧 API，不影响运行 |
| C++ 全量 | 19 分钟（换 hxcpp 版本必须清 `export/release/windows/obj`，否则链接报 `hx::tlsStackContext` 未定义） |
| 产物 | `PsychEngine.exe` 27.9 MB |

**注意**：换栈后必须删 obj。混用旧版本编出来的 `.obj` 会在链接阶段报 `LNK2001: hx::tlsStackContext`，看起来像代码问题，其实只是对象文件版本不一致。

---

## 十二、`Std.parseInt` 溢出饱和导致颜色全白（2026-11-12）

### 现象

所有经过十六进制字符串解析的颜色都变成**白色**：mod 的 UI 文字、时间条、`getColorFromHex()` 返回的色值。
不受影响的只有创建时就烘焙进 bitmap 的颜色（血条的 `createFilledBar`）。

### 根因

cpp 目标上 `Std.parseInt` 由 hxcpp 运行时实现：

```haxe
// haxe/std/cpp/_std/Std.hx
public static function parseInt(x:String):Null<Int> {
    return untyped __global__.__hxcpp_parse_int(x);
}
```

**32 位溢出时它饱和到 `IntMax`（0x7FFFFFFF），不环绕。**

```
0xff52A5EB  →  2147483647  →  0x7FFFFFFF  →  纯白
```

而 `0xFF52A5EB` 本来是蓝色（ARGB）。任何 8 位十六进制颜色都会中招，
6 位的（如 `0xff3e25` = 16727589）在 Int 范围内，所以看起来"有的颜色正常有的变白"。

### 为什么是移植引入的

`FunkinLua.hx` 里这段代码和上游 tag 0.6.3 **逐字相同**，移植时没动过。差别在工具链：

| | 原版 0.6.3 | 本移植 |
|---|---|---|
| Haxe | 4.2.5 | 4.3.7 |
| hxcpp | 4.2.1 | 4.3.2 |

同一表达式在两个 target 上的实测：

| 环境 | `Std.parseInt('0xff52A5EB')` |
|---|---|
| Haxe `--interp` | -11360789 ✅ |
| cpp 运行时 | 2147483647 ❌ |

代码不变、语义变了。这也解释了为什么 mod 在原版 0.6.3 上正常。

### 修法

新增 `FunkinLua.parseHexColor()`，逐位累加让 32 位自然环绕，接受
`RRGGBB` / `AARRGGBB` / `0xAARRGGBB` / `#RRGGBB` 四种写法。

替换了 **14 处**同款写法：

| 文件 | 位置 |
|---|---|
| `FunkinLua.hx` | `setTextColor`、`setTextBorder`、`setTimeBarColors`、`setHealthBarColors`、`cameraFlash`、`cameraFade`、`makeGraphic`、`setObjectColor`、`getColorFromHex` 等 12 处 |
| `editors/EditorLua.hx` | `getColorFromHex` |
| `CreditsState.hx` | `getCurrentBGColor` |

### 同类隐患排查结论

| 检查项 | 结论 |
|---|---|
| `Std.parseFloat`（7 处） | 全是时间/缩放等小数值，无风险 |
| mod 里直接写的 `0x...` 常量 | 两包全是 6 位，在 Int 范围内，安全 |
| 其它 `Std.parseInt`（共 31 处） | 其余是下标/音量/事件值，量级很小 |
| 主仓 1.0.4（`FNF-PE_RealQuickJs_Engine`） | **零处**此写法，全程用 `FlxColor.fromString`，免疫 |

### 一般性结论

> cpp 目标上 `Std.parseInt` 溢出**饱和**而非环绕。任何可能超过 2147483647 的整数解析
> （ARGB 颜色、时间戳、大 ID）都不能走它，必须自己逐位解析或改用 `Float`。
