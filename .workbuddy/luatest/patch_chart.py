#!/usr/bin/env python3
"""给 bopeebo 的谱面打补丁：塞一个自定义事件 + 给第一个音符挂自定义类型。

这样 PlayState 才会去加载 custom_events/<名字>.lua 和 custom_notetypes/<名字>.lua，
用来验证 stage / notetype / event 三类脚本的加载路径。

只改 export/ 里的产物，不动仓库里的 assets。重复执行不会叠加（有 .orig 备份）。
"""

import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODE = os.environ.get('PE_BUILD', 'release')
CHART = os.path.join(ROOT, f'export/{MODE}/windows/bin/assets/body/shared/data/bopeebo/bopeebo.json')
EVENT_NAME = 'luatestevent'
NOTETYPE = 'luatestnote'


def main() -> int:
    if not os.path.exists(CHART):
        print('找不到谱面: ' + CHART, file=sys.stderr)
        return 1

    backup = CHART + '.orig'
    if not os.path.exists(backup):
        shutil.copyfile(CHART, backup)
    data = json.load(open(backup, encoding='utf-8'))

    song = data['song']
    song['events'] = [[0, [[EVENT_NAME, '1', '2']]]]

    patched = False
    for section in song['notes']:
        notes = section.get('sectionNotes') or []
        if not notes:
            continue
        note = notes[0]
        while len(note) < 4:
            note.append(0)
        note[3] = NOTETYPE
        patched = True
        break

    if not patched:
        print('谱面里一个音符都没有，没法挂 notetype', file=sys.stderr)
        return 1

    with open(CHART, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent='\t')

    print(f'谱面已打补丁: event={EVENT_NAME}, notetype={NOTETYPE}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
