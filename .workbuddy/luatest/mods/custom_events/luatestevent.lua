-- 自定义事件脚本（custom event script）：从 mods/custom_events/<事件名>.lua 加载
-- 谱面里塞了一个叫 luatestevent 的事件，加载时应该走到这里
local OUT = '@@ROOT@@/.workbuddy/testout/kind_event.txt'
local OTHER = '@@ROOT@@/.workbuddy/testout/kind_event_other.txt'

function onCreate()
	saveFile(OUT, 'event|ok|loaded\n', true)
end

function onEvent(name, value1, value2)
	if name == 'luatestevent' then
		saveFile(OUT, 'event|ok|fired:' .. tostring(value1) .. ':' .. tostring(value2) .. '\n', true)
	else
		-- 别的脚本会 triggerEvent 别的事件，单独记，免得盖掉上面这条
		saveFile(OTHER, tostring(name) .. '\n', true)
	end
end
