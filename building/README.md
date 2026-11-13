# 编译入口

> 平时不用记这里的命令，仓库根目录的 `manage.sh` / `manage.bat` 是统一入口
> （先选中文/英文，再按编号选功能）。这里的脚本是它下面被调用的实现。

这个文件夹放编译相关的全部东西：环境校验、依赖清单、编译脚本、日志。

```
building/
  setup.sh      环境体检（Haxe / 库版本 / MSVC / SDK / rc.exe）
  build.sh      编译
  prep_assets.sh 编译后把官方素材铺进 bin，并校验三个引擎的资产
  libs.txt      依赖清单，版本号只在这里维护一份
  Build.bat     Windows 双击入口，转发到 build.sh
  logs/         编译日志，一次一份
```

## 日常用法

```bash
bash building/setup.sh            # 环境体检，缺什么报什么，不改机器
bash building/setup.sh --fix      # 缺库时尝试 haxelib install（要网络）
bash building/build.sh            # 增量 release
bash building/build.sh -debug     # debug
bash building/build.sh -clean     # 清中间产物全量重编
bash building/build.sh -dry       # 只打印计划，不动文件
bash building/build.sh -no-cache  # 关 hxcpp 编译缓存（怀疑缓存里是旧 obj）
bash building/build.sh -no-assets # 跳过素材铺放与校验

# 只校验已铺好的资产，不动文件（发版前跑一次）
bash building/prep_assets.sh --check
```

产物 `export/<release|debug>/windows/bin/PsychEngine.exe`，日志在 `logs/`。

**全部是纯命令行脚本，不弹窗、不抢焦点、不出声。** 需要自动化的场合一律调 `.sh`；
`Build.bat` 只给你手动双击用，它会开一个 cmd 窗口并在结束时 `pause`（不然报错一闪就没了）。

## build.sh 依次做六件事

| 步骤 | 做什么 | 缺东西时 |
|---|---|---|
| 1/6 工具链 | 找 `haxe`，把 `.haxelib` 指到仓库本地 | 提示装 Haxe 4.3.x |
| 2/6 依赖 | 调 `setup.sh --libs-only`，按 `libs.txt` 核对版本 | 列出差异，直接停 |
| 3/6 MSVC | 扫 `D:/VS2019/BuildTools`、VS2022 等位置，取最新版本和 SDK | 提示装 Build Tools 的 C++ 工作负载 |
| 4/6 预处理 | 关掉运行中的游戏；`-clean` 时清 obj/src；打开 hxcpp 编译缓存 | — |
| 5/6 编译 | `haxelib run lime build windows` | 失败时摘出前 10 条 error |
| 6/6 验收 | exe 是否存在 / 时间戳 / 大小 / warning 数；铺素材并校验 | 资产缺项直接判这次构建失败 |

第 6 步的素材部分走 `prep_assets.sh`，它做三件事：

1. **铺**：`assets/base_game`（官方素材的单一源，713 个文件）硬链接进
   `bin/assets/{body,1.0.4}`，再补 `0.6.3` 缺的周目录。已有文件不覆盖 —— 版本目录优先。
   桌面构建跳过 `*.mp3`（三棵树的 `SOUND_EXT` 都是 `ogg`），顺带清掉老构建残留的多余 mp3。
2. **建目录**：`mods/{body,1.0.4,0.6.3,global}` 和默认的 `engine.txt`
   （`mods/<版本>/` 不存在时 `Mods.updateModList()` 会直接崩）。
3. **校验**：base_game 是否零缺、`weekList.txt` 的每条是否有 json、
   舞台 json 里 `directory` 指的周目录是否非空、音频是否都有 `.ogg`、有没有 0 字节文件。

资产缺失不会让游戏崩，只会安静地空白（freeplay 列表空、舞台缺图、选歌没声音），
所以必须在打包时拦住。只想知道现状不铺：`prep_assets.sh --check`。

## 环境版本

`libs.txt` 里那套版本是 2026-11-13 验证过的组合，`setup.sh` 按它逐条比对。
版本对不上会标「注意」但不中断编译 —— 真正会咬人的是 stdlib 语义变化
（比如 Haxe 4.3 的 `Std.parseInt` 在 cpp 上溢出会饱和到 IntMax，而不是环绕，
代码一个字没改，颜色全变白）。所以别随手升级。

## 和上游 setup/ 的关系

根目录的 `setup/` 是上游 Psych Engine 原来的装库脚本（`windows.bat` 等），
只在**这台机器从零配环境**时用一次，装 Haxe 和基础库。
配好之后日常都走这里的 `setup.sh`（只校验，不下载）和 `build.sh`。

## 注意

- `assets/base_game` 是编译**之后**才铺进 `bin/assets/<版本>/` 的（见上面的第 6 步）。
  `assets/body`、`assets/1.0.4`、`assets/0.6.3` 里只放各版本自己的东西，官方素材不要往里抄 ——
  那样仓库里会多出两份 470M。
- 改了 `Project.xml` 的 define、增删 `.hx` 文件、换 Haxe/hxcpp 版本之后会全量重编（本机约 3~4 分钟）；
  平时改代码是增量，一分钟左右。
- hxcpp 编译缓存在 `.cache/hxcpp`（已 gitignore，可以随便删）。怀疑缓存里是旧 obj 了加 `-no-cache`。
- 游戏开着的时候链接器写不进 exe，脚本会先关掉它。
