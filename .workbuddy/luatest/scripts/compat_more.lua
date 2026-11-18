-- 第三批：偏「老 mod 常见写法」的补充用例。
-- 结果写 .workbuddy/testout/more.txt

local OUT = '@@ROOT@@/.workbuddy/testout/more.txt'
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
	rec('INFO', 'script', 'more loaded')

	-- ── 动态加载 / 卸载脚本 ────────────────────────────────────────
	t('script.addLuaScript', function()
		addLuaScript('scripts/dummy_helper.lua')
		return isRunning('scripts/dummy_helper.lua') == true
	end)
	t('script.removeLuaScript', function()
		return removeLuaScript('scripts/dummy_helper.lua') == nil or true
	end)

	-- ── 文本全家桶 ────────────────────────────────────────────────
	t('text.setup', function()
		makeLuaText('lt3_txt', 'abc', 300, 100, 100)
		addLuaText('lt3_txt')
		return getProperty('lt3_txt.text') == 'abc'
	end)
	t('text.setTextString', function()
		setTextString('lt3_txt', 'hello world')
		return getProperty('lt3_txt.text') == 'hello world'
	end)
	t('text.setTextSize', function()
		setTextSize('lt3_txt', 32)
		return near(getProperty('lt3_txt.size'), 32)
	end)
	t('text.setTextWidth', function()
		setTextWidth('lt3_txt', 250)
		return near(getProperty('lt3_txt.fieldWidth'), 250)
	end)
	t('text.setTextBorder', function()
		setTextBorder('lt3_txt', 2, '000000')
		return near(getProperty('lt3_txt.borderSize'), 2)
	end)
	t('text.setTextColor', function()
		setTextColor('lt3_txt', 'FF00FF')
		return true
	end)
	t('text.screenCenter', function()
		screenCenter('lt3_txt', 'X')
		return getProperty('lt3_txt.x') > 0
	end)

	-- ── 层级 ─────────────────────────────────────────────────────
	t('order.luaSprite', function()
		makeLuaSprite('lt3_s', nil, 0, 0)
		makeGraphic('lt3_s', 8, 8, 'FF0000')
		addLuaSprite('lt3_s', true)
		return getObjectOrder('lt3_s') >= 0, getObjectOrder('lt3_s')
	end)
	t('order.setObjectOrder.luaSprite', function()
		setObjectOrder('lt3_s', 4)
		return getObjectOrder('lt3_s') == 4, getObjectOrder('lt3_s')
	end)

	-- ── 动画 ─────────────────────────────────────────────────────
	t('anim.playAnim.dad', function()
		playAnim('dad', 'singLEFT', true)
		return getProperty('dad.animation.curAnim.name') == 'singLEFT'
	end)
	t('anim.addAnimationByIndices', function()
		makeAnimatedLuaSprite('lt3_a', 'characters/BOYFRIEND', 0, 0, 'sparrow')
		addAnimationByIndices('lt3_a', 'idx', 'BF HEY!!', '1,2,3', 24, false)
		return true
	end)
	t('anim.playAnim.idx', function()
		playAnim('lt3_a', 'idx', true)
		return getProperty('lt3_a.animation.curAnim.name') == 'idx'
	end)
	t('anim.autoSpriteType', function()
		makeAnimatedLuaSprite('lt3_a2', 'characters/BOYFRIEND', 0, 0, 'auto')
		return getProperty('lt3_a2.numFrames') > 0, getProperty('lt3_a2.numFrames')
	end)

	-- ── 补间 ─────────────────────────────────────────────────────
	t('tween.doTweenZoom', function()
		doTweenZoom('lt3_tz', 'camGame', 1.05, 1, 'linear')
		return true
	end)
	t('tween.noteTweenAlpha', function()
		noteTweenAlpha('lt3_tna', 0, 0.5, 1, 'linear')
		return true
	end)
	t('tween.cleanup', function()
		cancelTween('lt3_tz')
		cancelTween('lt3_tna')
		return true
	end)

	-- ── 声音 ─────────────────────────────────────────────────────
	i('sound.playSound', function()
		playSound('freakyMenu', 0.4, 'lt3_snd')
		return 'played'
	end)
	i('sound.stopSound', function()
		stopSound('lt3_snd')
		return 'stopped'
	end)

	-- ── 属性读取 ─────────────────────────────────────────────────
	t('prop.boyfriend.curCharacter', function()
		return getProperty('boyfriend.curCharacter') == 'bf'
	end)
	t('prop.healthBar.percent', function()
		return type(getProperty('healthBar.percent')) == 'number'
	end)
	t('prop.scoreTxt.text', function()
		return getProperty('scoreTxt.text') ~= nil
	end)
	t('prop.camHUD.zoom', function()
		setProperty('camHUD.zoom', 1.1)
		return near(getProperty('camHUD.zoom'), 1.1)
	end)
	t('group.nestedProperty', function()
		return getPropertyFromGroup('strumLineNotes', 0, 'animation.curAnim.name') ~= nil
	end)
	i('group.array.read', function()
		return tostring(getPropertyFromGroup('unspawnNotes', 0, 'noteData'))
	end)
	t('group.array.write', function()
		setPropertyFromGroup('unspawnNotes', 0, 'noteData', 0)
		return getPropertyFromGroup('unspawnNotes', 0, 'noteData') == 0
	end)

	-- ── HScript 里的 0.6.3 裸类名 ────────────────────────────────
	t('hscript.ClientPrefs', function()
		local v = runHaxeCode('return ClientPrefs.downScroll;')
		return type(v) == 'boolean' or v == nil, tostring(v)
	end)
	t('hscript.PlayState', function()
		local v = runHaxeCode('return PlayState.instance.curStep;')
		return type(v) == 'number', tostring(v)
	end)
	i('hscript.className.Boyfriend', function()
		return tostring(runHaxeCode('return Type.getClassName(Boyfriend);'))
	end)
	i('hscript.className.GitarooPause', function()
		return tostring(runHaxeCode('return Type.getClassName(GitarooPause);'))
	end)
	t('hscript.typedLocal', function()
		local v = runHaxeCode('var b:Boyfriend = PlayState.instance.boyfriend; return b.curCharacter;')
		return v == 'bf', tostring(v)
	end)

	-- ── 杂项 ─────────────────────────────────────────────────────
	i('misc.precacheImage', function()
		precacheImage('characters/BOYFRIEND')
		return 'ok'
	end)
	t('misc.updateScoreText', function()
		updateScoreText()
		return true
	end)
	t('misc.setHealthBarColors', function()
		setHealthBarColors('FF0000', '00FF00')
		return true
	end)
	t('misc.setTimeBarColors', function()
		setTimeBarColors('0000FF', 'FFFF00')
		return true
	end)
	t('misc.addCharacterToList', function()
		addCharacterToList('bf')
		return true
	end)
	t('misc.getObjectOrder.missing', function()
		return getObjectOrder('no_such_thing') == -1
	end)

	-- ── 0.6.3/0.7.3 的杂项全局 ────────────────────────────────────
	t('global.cameraX', function()
		return type(cameraX) == 'number', type(cameraX)
	end)
	t('global.cameraY', function()
		return type(cameraY) == 'number', type(cameraY)
	end)
	t('global.inChartEditor', function()
		return inChartEditor == false, tostring(inChartEditor)
	end)
	t('global.debugPrint.multiArg', function()
		debugPrint('a', 'b', 'c')
		return true
	end)
	t('global.debugPrint.colorArg', function()
		debugPrint('colored', 'FF0000')
		return true
	end)

	rec('DONE', 'more', 'failed=' .. failed)
end
