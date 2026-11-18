-- 没带版本标记的普通脚本，看到的必须还是真实版本 1.0.4。
-- 和 versionTag(%run_v_0.7.3).lua 成对，防止伪装逻辑漏到全局。
-- 结果写到 .workbuddy/testout/versionplain.txt

local OUT = '@@ROOT@@/.workbuddy/testout/versionplain.txt'

local function rec(s)
	saveFile(OUT, s .. '\n', true)
end

function onCreate()
	local v = version
	local p = getPropertyFromClass('states.MainMenuState', 'psychEngineVersion')
	if v == '1.0.4' and p == '1.0.4' then
		rec('PASS|version_plain|lua=' .. tostring(v) .. ',property=' .. tostring(p))
	else
		rec('FAIL|version_plain|lua=' .. tostring(v) .. ',property=' .. tostring(p))
	end
end
