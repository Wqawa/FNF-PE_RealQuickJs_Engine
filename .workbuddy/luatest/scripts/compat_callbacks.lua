-- 回调触发计数：确认脚本挂上来的这些 hook 真的会被叫到。
-- 计数写在文件里，进程被强杀也不丢。
local OUT = '@@ROOT@@/.workbuddy/testout/callbacks.txt'
local c = {}

local function dump()
	local s = ''
	for _, k in ipairs({'onCreate', 'onCreatePost', 'onUpdatePost', 'onStartCountdown',
		'onCountdownTick', 'onSongStart', 'onStepHit', 'onBeatHit', 'onSectionHit',
		'onSpawnNote', 'onNoteMiss', 'goodNoteHit', 'opponentNoteHit'}) do
		s = s .. k .. '=' .. tostring(c[k] or 0) .. '\n'
	end
	saveFile(OUT, s, true)
end

local function bump(name)
	c[name] = (c[name] or 0) + 1
	dump()
end

function onCreate()
	bump('onCreate')
end

function onCreatePost()
	bump('onCreatePost')
end

function onUpdatePost(elapsed)
	c.onUpdatePost = (c.onUpdatePost or 0) + 1
	if c.onUpdatePost == 1 then dump() end
end

function onStartCountdown()
	bump('onStartCountdown')
end

function onCountdownTick(swagCounter)
	bump('onCountdownTick')
end

function onSongStart()
	bump('onSongStart')
end

function onStepHit()
	bump('onStepHit')
end

function onBeatHit()
	bump('onBeatHit')
end

function onSectionHit()
	bump('onSectionHit')
end

function onSpawnNote(id, noteData, noteType, isSustainNote)
	bump('onSpawnNote')
end

function onNoteMiss(id, noteData, noteType, isSustainNote)
	bump('onNoteMiss')
end

function goodNoteHit(id, direction, noteType, isSustainNote)
	bump('goodNoteHit')
end

function opponentNoteHit(id, direction, noteType, isSustainNote)
	bump('opponentNoteHit')
end
