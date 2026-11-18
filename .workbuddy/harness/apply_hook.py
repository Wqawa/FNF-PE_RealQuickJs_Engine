#!/usr/bin/env python3
"""把临时测试入口塞进 source_body/ 或者撤掉，仓库里不留痕迹。

    python .workbuddy/harness/apply_hook.py on   # 拷 AutoTestState.hx + 给 Main 打两行补丁
    python .workbuddy/harness/apply_hook.py off  # 删文件 + git checkout 还原 Main.hx
"""

import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAIN = os.path.join(ROOT, 'source_body', 'body', 'body', 'Main.hx')
STATE = os.path.join(ROOT, 'source_body', 'body', 'AutoTestState.hx')
SRC = os.path.join(ROOT, '.workbuddy', 'harness', 'AutoTestState.hx')

MARK = '// [harness] autotest entry'
ORIGINAL = '\t\taddChild(new FlxGame(game.width, game.height, game.initialState, game.framerate, game.framerate, game.skipSplash, game.startFullscreen));'
PATCHED = '''\t\t// [harness] autotest entry
\t\tvar firstState:Class<FlxState> = game.initialState;
\t\t#if desktop
\t\tif(AutoTestState.requestedSong() != null) firstState = AutoTestState;
\t\t#end
\t\taddChild(new FlxGame(game.width, game.height, firstState, game.framerate, game.framerate, game.skipSplash, game.startFullscreen));'''


def turn_on() -> int:
    shutil.copyfile(SRC, STATE)
    src = open(MAIN, encoding='utf-8').read()
    if MARK in src:
        print('Main.hx 已经打过补丁')
        return 0
    if ORIGINAL not in src:
        print('Main.hx 里没找到那行 addChild(new FlxGame(...))，版本对不上？', file=sys.stderr)
        return 1
    open(MAIN, 'w', encoding='utf-8', newline='').write(src.replace(ORIGINAL, PATCHED))
    print('已注入测试入口')
    return 0


def turn_off() -> int:
    if os.path.exists(STATE):
        os.remove(STATE)
    # 不要用 git checkout，否则会把 Main.hx 里本仓自己的改动（引擎分支）一起抹掉。
    # 只把注入的那段还原回原始 addChild 行。
    src = open(MAIN, encoding='utf-8').read()
    if PATCHED in src:
        open(MAIN, 'w', encoding='utf-8', newline='').write(src.replace(PATCHED, ORIGINAL))
        print('已移除测试入口补丁')
    else:
        print('Main.hx 里没有测试入口补丁，跳过')
    print('已删除 source_body/body/AutoTestState.hx')
    return 0


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'on'
    sys.exit(turn_on() if mode == 'on' else turn_off())
