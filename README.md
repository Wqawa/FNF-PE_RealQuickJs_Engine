# FNF-PE_RealQuickJs_Engine
（代替傻逼开发的[PE-QuickJs-Engine](https://github.com/rongtang2026/PE-QuickJs-Engine)，烂完了还敢发，态度还恶劣）

在 Psych Engine 1.0.4 的 fork 的基础上添加了其他侧引擎 ，靠 `engine.txt` 切换；主要目标是让 0.6.3 / 0.7.3 的老 mod 不改一行就能跑，同时在保留lua的基础上真正支持js

JS 那侧的 FunkinJS 转译器和存档是个故意留着的装置 —— 针对 rongtang2026/PE-QuickJs-Engine 拿 `{`→`end` 冒充 JS 支持、违反开源协议那件事。存档原本塞在 `JavaScriptUtils.hx` 的注释里，2026-11-17 搬到了 `docs/JS_TRANSPILE_HISTORY.md`。

---


### 切换引擎

`Options → Switch Engine`，选完会写在 exe 旁边的 `engine.txt` 内并退出。三个值代表三个引擎侧：

| `engine.txt` | 侧 | 源码 | 资产 | mod |
|---|---|---|---|---|
| `body`（默认） | 本仓 fork | `source_body/body/` | `assets/body/` | `mods/body/` |
| `vanilla` | 原版 PE 1.0.4 | `source_vanilla/vanilla/` | `assets/1.0.4/` | `mods/1.0.4/` |
| `pe063` | Psych Engine 0.6.3 | `source_063/pe063/` | `assets/0.6.3/` | `mods/0.6.3/` |



### 按名字伪造引擎版本

有些 mod 的 Lua 里写 `if version == '0.6.3' then ...`，在 1.0.4 上会走进错误分支。给文件名加后缀，就能让**那一个脚本**看到它想要的版本：

实例
```
mods/xxx/scripts/legacy-thing(%run_v_0.6.3).lua
```


## 崩溃屏

三侧共用一个拦截器（`source/backend/EngineCrash.hx`）

- 先 `crash/PsychEngine_<时间>.txt`（错误 + 调用栈），再切到引擎内崩溃屏
- 崩溃屏幕会显示引擎、时间、错误和调用栈；
- **QUIT** 退出，**MAIN MENU** 或 **M / ESC** 返回当前侧主菜单
- `Ctrl+Alt+Shift+Q` 手动触发

---

## 目录

```
manage.sh / manage.bat                 中心脚本入口
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
└── psychlua/IsolatedImports.hx        import 别名表（manage.sh 功能 5 重建）

source_063/pe063/                      Psych Engine 0.6.3，全部 pe063.* 前缀

docs/                                  见下一节
third_party/quickjs-ng/                JS 运行时源码 + 静态库（产物不入库）
export/<mode>/windows/bin/             构建产物，engine.txt 在这里
```

---

## 文档

| 文件 | AI含量巨高，等我重写 |
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
