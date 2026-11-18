-- 文件名末尾带 (%run_v_0.7.3)，引擎应该只对这个脚本把版本号伪装成 0.7.3。
-- 对应实现：FunkinLua.versionOverride / parseVersionTag
-- 结果写到 .workbuddy/testout/versiontag.txt

local OUT = '@@ROOT@@/.workbuddy/testout/versiontag.txt'

local function rec(s)
	saveFile(OUT, s .. '\n', true)
end

function onCreate()
	local v = version
	local p = getPropertyFromClass('states.MainMenuState', 'psychEngineVersion')
	if v == '0.7.3' and p == '0.7.3' then
		rec('PASS|version_tag|lua=' .. tostring(v) .. ',property=' .. tostring(p))
	else
		rec('FAIL|version_tag|lua=' .. tostring(v) .. ',property=' .. tostring(p))
	end
end
