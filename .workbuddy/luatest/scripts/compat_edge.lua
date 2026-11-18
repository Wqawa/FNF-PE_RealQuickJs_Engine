-- 边界用例：老写法里那些"顺手写"的调用
local OUT = '@@ROOT@@/.workbuddy/testout/edge.txt'
local lines = {}
local failed = 0

local function dump()
	saveFile(OUT, table.concat(lines, '\n') .. '\n', true)
end

local function rec(status, name, detail)
	lines[#lines + 1] = status .. '|' .. name .. (detail ~= nil and ('|' .. tostring(detail)) or '')
	if status == 'FAIL' or status == 'ERR' then failed = failed + 1 end
	dump()
end

local function t(name, fn)
	local ok, res = pcall(fn)
	if not ok then
		rec('ERR', name, res)
	elseif res == false or res == nil then
		rec('FAIL', name)
	else
		rec('PASS', name, (res ~= true) and res or nil)
	end
end

local function i(name, fn)
	local ok, res = pcall(fn)
	rec('INFO', name, ok and tostring(res) or ('ERR: ' .. tostring(res)))
end

local function near(a, b)
	return type(a) == 'number' and math.abs(a - b) < 0.01
end

function onCreatePost()
	rec('INFO', 'script', 'edge loaded')

	-- runHaxeCode 里带 import（0.6.3 脚本的固定写法）
	i('haxe.import.Boyfriend', function()
		return tostring(runHaxeCode('import Boyfriend; return Type.getClassName(Boyfriend);'))
	end)
	i('haxe.import.ClientPrefs', function()
		return tostring(runHaxeCode('import ClientPrefs; return Type.getClassName(ClientPrefs);'))
	end)
	t('haxe.newInstance', function()
		local v = runHaxeCode('var b:Boyfriend = PlayState.instance.boyfriend; return b.getScreenPosition().x;')
		return type(v) == 'number', tostring(v)
	end)

	-- 血条百分比 / 帧号
	t('prop.healthBar.percent.write', function()
		setProperty('healthBar.percent', 50)
		return near(getProperty('healthBar.percent'), 50), getProperty('healthBar.percent')
	end)
	t('prop.curAnim.curFrame', function()
		return type(getProperty('boyfriend.animation.curAnim.curFrame')) == 'number'
	end)

	-- 不带扩展名的脚本名
	t('script.addLuaScript.noExt', function()
		addLuaScript('scripts/dummy_helper')
		return isRunning('scripts/dummy_helper.lua') == true
	end)
	t('script.removeLuaScript.noExt', function()
		removeLuaScript('scripts/dummy_helper')
		return true
	end)

	-- 颜色名
	t('sprite.makeGraphic.colorName', function()
		makeLuaSprite('lt4_s', nil, 0, 0)
		makeGraphic('lt4_s', 16, 16, 'red')
		return true
	end)

	-- 文本销毁
	t('text.removeLuaText', function()
		makeLuaText('lt4_t', 'bye', 100, 0, 0)
		addLuaText('lt4_t')
		removeLuaText('lt4_t', true)
		return getObjectOrder('lt4_t') < 0
	end)

	-- FunkinJS 转译层：js 脚本由 .js → lua 跑
	t('js.scriptRan', function()
		return getVar('js_probe_var') == 'js-ok', tostring(getVar('js_probe_var'))
	end)
	i('js.updateRan', function()
		return tostring(getVar('js_update_ran'))
	end)
	t('js.elseIfBranch', function()
		return getVar('js_branch') == 'elseif', tostring(getVar('js_branch'))
	end)
	t('js.writeFile', function()
		local f = io.open('@@ROOT@@/.workbuddy/testout/js_seen.txt', 'r')
		if f == nil then return false end
		local c = f:read('*a')
		f:close()
		return c == 'js-ok\n' or c == 'js-ok', c
	end)

	rec('DONE', 'edge', 'failed=' .. failed)
end
