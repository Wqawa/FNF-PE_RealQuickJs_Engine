-- Version probe.
--
-- Drop into mods/<version>/scripts/ (or a mod's scripts/ folder) and start any song.
-- It prints what *this script* sees as the engine version, on the debug text (debugPrint).
--
-- To check version faking on the body tree, copy it with a tag:
--   version_probe(%run_v_0.7.3).lua   ->  version / psychEngineVersion both report 0.7.3
-- Without a tag you get the real engine version.
--
-- The two lines that matter:
--   version             - lua global, present on the body tree only
--   psychEngineVersion  - MainMenuState.psychEngineVersion, tagged scripts see the tag

local function val(fn)
	local ok, v = pcall(fn)
	if not ok then return '<error>' end
	if v == nil then return '<nil>' end
	return tostring(v)
end

function onCreatePost()
	local lines = {
		'[version_probe] ' .. val(function() return scriptName end),
		'  version            : ' .. val(function() return version end),
		'  psychEngineVersion : ' .. val(function()
			return getPropertyFromClass('MainMenuState', 'psychEngineVersion')
		end),
		'  assets dir         : ' .. val(function()
			return getPropertyFromClass('Paths', 'VERSION_DIR')
		end),
		'  mod folder         : ' .. val(function()
			return getPropertyFromClass('Mods', 'currentModDirectory')
		end)
	}
	debugPrint(table.concat(lines, '\n'))

	-- Want a copy on disk too? Uncomment; absolute=true writes next to the exe.
	-- saveFile('version_probe.txt', table.concat(lines, '\n') .. '\n', true)
end
