# 编译入口

双击 `Build.bat`，或者：

```bash
bash building/build.sh            # 增量 release
bash building/build.sh -debug     # debug
bash building/build.sh -clean     # 清中间产物全量重编
bash building/build.sh -dry       # 只打印计划，不动文件
```

产物 `export/<release|debug>/windows/bin/PsychEngine.exe`，日志在 `logs/`。

## 它依次做六件事

| 步骤 | 做什么 | 缺东西时 |
|---|---|---|
| 1/6 工具链 | 找 `haxe`，把 `.haxelib` 指到仓库本地 | 提示装 Haxe 4.3.x |
| 2/6 依赖 | 用 `haxelib list` 核对 `Project.xml` 要求的库 | 列出缺的库 + 补库命令，直接停 |
| 3/6 MSVC | 扫 `D:/VS2019/BuildTools`、VS2022 等位置，取最新版本和 SDK | 提示装 Build Tools 的 C++ 工作负载 |
| 4/6 预处理 | 关掉运行中的游戏；`-clean` 时清 obj/src；打开 hxcpp 编译缓存（`-no-cache` 关） | — |
| 5/6 编译 | `haxelib run lime build windows` | 失败时摘出前 10 条 error |
| 6/6 验收 | exe 是否存在 / 时间戳 / 大小 / warning 数，铺 `assets/base_game` | 时间戳没变会提醒用 `-clean` |

## 和上游脚本的关系

`setup/` 里是上游原来的装库脚本（`windows.bat` 等），只在**第一次配环境**时用一次。
之后日常编译都走 `building/build.sh`，它不会下载任何东西，也不会改系统 PATH / 注册表。

`.workbuddy/build.sh` 现在只是转发到这里，`run_test.sh` 仍然能用。

## 注意

- `assets/base_game` 是编译**之后**才拷进 `bin/assets` 的（`Project.xml` 的 `BASE_GAME_FILES` 故意留在 officialBuild 段）。
  脚本第 6 步会做这件事，用 `.assets_ready` 标记避免重复拷。
- 改了 `Project.xml` 的 define、增删 `.hx` 文件、换 Haxe/hxcpp 版本之后，hxcpp 会判定全量重编（本机约 30 分钟）；
  平时改代码是增量，一分钟左右。
- hxcpp 编译缓存在 `.cache/hxcpp`（已 gitignore，可以随便删）。默认开着，命中时直接拷 `.obj` 不跑 `cl.exe`；
  第一次填充会慢一点（152s），之后稳态增量 73s 左右。怀疑缓存里是旧 obj 了加 `-no-cache`。
- 游戏开着的时候链接器写不进 exe，脚本会先关掉它。
