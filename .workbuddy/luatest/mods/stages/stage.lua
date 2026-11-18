-- 关卡脚本（stage script）：从 mods/stages/<curStage>.lua 加载
-- 只做一件事：证明它被加载并跑到了 onCreate
local OUT = '@@ROOT@@/.workbuddy/testout/kind_stage.txt'

function onCreate()
	saveFile(OUT, 'stage|ok|' .. tostring(curStage) .. '\n', true)
end

function onBeatHit()
	saveFile('@@ROOT@@/.workbuddy/testout/kind_stage_beat.txt', tostring(curBeat) .. '\n', true)
end
