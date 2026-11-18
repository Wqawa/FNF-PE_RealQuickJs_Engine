-- 0.7.3 风格兼容测试：全部按 0.7.3 时代的写法调用，跑在 1.0.4 上。
-- 每条结果即时写盘，挂在 .workbuddy/testout/v073.txt
-- PASS/FAIL/ERR 是断言，INFO 是探测（只记录不判定）

local OUT = '@@ROOT@@/.workbuddy/testout/v073.txt'
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

-- 返回 false/nil 视为失败；抛错记 ERR
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

rec('INFO', 'script', 'v073 loaded, version=' .. tostring(version))

function onCreatePost()
	rec('INFO', 'state', 'onCreatePost')

	-- ── 裸类名解析（0.6.3/0.7.3 的 import Boyfriend 那一套） ──────────────
	t('class.ClientPrefs.downScroll', function()
		return getPropertyFromClass('ClientPrefs', 'downScroll') ~= nil
	end)
	t('class.ClientPrefs.middleScroll', function()
		return getPropertyFromClass('ClientPrefs', 'middleScroll') ~= nil
	end)
	t('class.oldName.globalAntialiasing', function()
		return getPropertyFromClass('ClientPrefs', 'globalAntialiasing') ~= nil
	end)
	t('class.oldName.arrowHSV', function()
		local v = getPropertyFromClass('ClientPrefs', 'arrowHSV')
		if type(v) ~= 'table' or #v ~= 4 then return false, 'not a 4-row table' end
		if type(v[1]) ~= 'table' or #v[1] ~= 3 then return false, 'row is not a triplet' end
		return true
	end)
	t('class.oldName.arrowHSV.write', function()
		local before = getPropertyFromClass('ClientPrefs', 'arrowHSV')
		setPropertyFromClass('ClientPrefs', 'arrowHSV', before)
		local after = getPropertyFromClass('ClientPrefs', 'arrowHSV')
		return type(after) == 'table' and #after == 4
	end)
	t('class.deadField.noteSplashes', function()
		return getPropertyFromClass('ClientPrefs', 'noteSplashes') ~= nil
	end)
	t('class.deadField.cursing', function()
		return getPropertyFromClass('ClientPrefs', 'cursing') ~= nil
	end)
	t('class.oldName.comboOffset', function()
		local v = getPropertyFromClass('ClientPrefs', 'comboOffset')
		return type(v) == 'table' and #v == 4
	end)
	i('class.GitarooPause.instance', function()
		return type(getPropertyFromClass('GitarooPause', 'instance'))
	end)
	i('class.Boyfriend', function()
		return type(getPropertyFromClass('Boyfriend', 'charactersList'))
	end)

	-- ── 静态设置写入 ────────────────────────────────────────────────
	t('class.ClientPrefs.write', function()
		local old = getPropertyFromClass('ClientPrefs', 'downScroll')
		setPropertyFromClass('ClientPrefs', 'downScroll', true)
		local now = getPropertyFromClass('ClientPrefs', 'downScroll')
		setPropertyFromClass('ClientPrefs', 'downScroll', old)
		return now == true
	end)

	-- ── Bar 尺寸（0.7 起被 FlxSpriteGroup 吞掉的 set_width） ──────────────
	t('bar.healthBar.width.read', function()
		return getProperty('healthBar.width') > 0
	end)
	t('bar.healthBar.width.write', function()
		setProperty('healthBar.width', 500)
		return near(getProperty('healthBar.width'), 500)
	end)
	t('bar.timeBar.width.write', function()
		setProperty('timeBar.width', 400)
		return near(getProperty('timeBar.width'), 400)
	end)
	i('bar.timeBar.fillDirection', function()
		setProperty('timeBar.fillDirection', true)
		return tostring(getProperty('timeBar.fillDirection'))
	end)
	i('bar.healthBarBG.width', function()
		return tostring(getProperty('healthBarBG.width'))
	end)

	-- ── HUD 层级（1.0 把 uiGroup 展开前的老行为） ────────────────────────
	t('order.healthBar', function()
		return getObjectOrder('healthBar') >= 0, getObjectOrder('healthBar')
	end)
	t('order.scoreTxt', function()
		return getObjectOrder('scoreTxt') >= 0, getObjectOrder('scoreTxt')
	end)
	t('order.iconP1', function()
		return getObjectOrder('iconP1') >= 0, getObjectOrder('iconP1')
	end)
	t('order.setObjectOrder', function()
		local old = getObjectOrder('healthBar')
		setObjectOrder('healthBar', 2)
		local now = getObjectOrder('healthBar')
		setObjectOrder('healthBar', old)
		return now == 2, now
	end)

	-- ── 旧字段 ──────────────────────────────────────────────────────
	i('field.modchartSprites', function()
		return type(getProperty('modchartSprites'))
	end)
	i('field.modchartTweens', function()
		return type(getProperty('modchartTweens'))
	end)
	i('field.modchartTimers', function()
		return type(getProperty('modchartTimers'))
	end)
	i('field.instancesExclude', function()
		return type(getProperty('instancesExclude'))
	end)

	-- ── lua sprite 老 API ──────────────────────────────────────────
	t('sprite.makeLuaSprite', function()
		makeLuaSprite('lt_s1', nil, 0, 0)
		return getProperty('lt_s1.x') == 0
	end)
	t('sprite.makeGraphic', function()
		makeGraphic('lt_s1', 64, 64, 'FFFFFF')
		return getProperty('lt_s1.width') == 64, getProperty('lt_s1.width')
	end)
	t('sprite.addLuaSprite', function()
		addLuaSprite('lt_s1', false)
		return getObjectOrder('lt_s1') >= 0
	end)
	t('sprite.scaleLuaSprite', function()
		scaleLuaSprite('lt_s1', 2, 2)
		return near(getProperty('lt_s1.scale.x'), 2), getProperty('lt_s1.scale.x')
	end)
	t('sprite.setLuaSpriteScrollFactor', function()
		return setLuaSpriteScrollFactor('lt_s1', 0.5, 0.5) == true
	end)
	t('sprite.setLuaSpriteCamera', function()
		return setLuaSpriteCamera('lt_s1', 'hud') == true
	end)
	t('sprite.setPropertyLuaSprite', function()
		setPropertyLuaSprite('lt_s1', 'alpha', 0.5)
		return near(getProperty('lt_s1.alpha'), 0.5)
	end)
	t('sprite.getPropertyLuaSprite', function()
		return near(getPropertyLuaSprite('lt_s1', 'alpha'), 0.5)
	end)
	t('sprite.objectPlayAnimation', function()
		objectPlayAnimation('boyfriend', 'idle', true)
		return getProperty('boyfriend.animation.curAnim.name') == 'idle'
	end)
	t('sprite.characterPlayAnim', function()
		characterPlayAnim('dad', 'idle', true)
		return getProperty('dad.animation.curAnim.name') ~= nil
	end)

	-- ── 补帧动画 ───────────────────────────────────────────────────
	t('anim.makeAnimatedLuaSprite', function()
		makeAnimatedLuaSprite('lt_a1', nil, 0, 0)
		return getProperty('lt_a1.x') == 0
	end)
	t('anim.loadFrames', function()
		loadFrames('lt_a1', 'characters/BOYFRIEND', 'sparrow')
		return getProperty('lt_a1.numFrames') > 0, getProperty('lt_a1.numFrames')
	end)
	t('anim.addAnimationByPrefix', function()
		return addAnimationByPrefix('lt_a1', 'a', 'BF HEY!!', 24, true) == true
	end)
	t('anim.luaSpriteAddAnimationByPrefix', function()
		luaSpriteAddAnimationByPrefix('lt_a1', 'b', 'BF HEY!!', 24, true)
		return true
	end)
	t('anim.luaSpritePlayAnimation', function()
		luaSpritePlayAnimation('lt_a1', 'a', true)
		return getProperty('lt_a1.animation.curAnim.name') == 'a'
	end)
	t('anim.addAnimationByIndicesLoop', function()
		addAnimationByIndicesLoop('lt_a1', 'c', '', '0,1,2', 24)
		return true
	end)

	-- ── 补间 / 计时器 ──────────────────────────────────────────────
	t('tween.doTweenX', function()
		doTweenX('lt_tw1', 'lt_s1', 300, 1, 'linear')
		return true
	end)
	t('tween.doTweenAngle', function()
		doTweenAngle('lt_tw2', 'lt_s1', 90, 1, 'linear')
		return true
	end)
	t('tween.doTweenColor', function()
		doTweenColor('lt_tw3', 'lt_s1', 'FF0000', 1, 'linear')
		return true
	end)
	t('tween.noteTweenX', function()
		noteTweenX('lt_tn1', 0, 100, 1, 'linear')
		return true
	end)
	t('tween.cancelTween', function()
		cancelTween('lt_tw1')
		return true
	end)
	t('timer.runTimer', function()
		runTimer('lt_tm1', 5)
		return true
	end)
	t('timer.cancelTimer', function()
		cancelTimer('lt_tm1')
		return true
	end)

	-- ── 反射 / 组 ──────────────────────────────────────────────────
	t('reflect.getProperty.nested', function()
		return getProperty('boyfriend.animation.curAnim.name') ~= nil
	end)
	t('reflect.getPropertyFromGroup', function()
		return type(getPropertyFromGroup('strumLineNotes', 0, 'x')) == 'number'
	end)
	t('reflect.setPropertyFromGroup', function()
		setPropertyFromGroup('strumLineNotes', 0, 'visible', true)
		return getPropertyFromGroup('strumLineNotes', 0, 'visible') == true
	end)
	t('reflect.camGame.zoom', function()
		return getProperty('camGame.zoom') > 0
	end)

	-- ── 全局 / 分数 / 命中 ─────────────────────────────────────────
	t('global.getScore', function()
		return type(getScore()) == 'number'
	end)
	t('global.getMisses', function()
		return type(getMisses()) == 'number'
	end)
	t('global.getHits', function()
		return type(getHits()) == 'number'
	end)
	t('global.addScore', function()
		local before = getScore()
		addScore(10)
		return getScore() == before + 10, before .. ' -> ' .. tostring(getScore())
	end)
	t('global.setHealth', function()
		setHealth(1.5)
		return near(getProperty('health'), 1.5)
	end)
	i('global.getRunningScripts', function()
		local v = getRunningScripts()
		if type(v) ~= 'table' then return 'type=' .. type(v) end
		local s = ''
		for k, x in pairs(v) do s = s .. tostring(x) .. ';' end
		return s
	end)
	i('global.isRunning.short', function()
		return tostring(isRunning('compat_v073'))
	end)
	i('global.isRunning.scriptsPath', function()
		return tostring(isRunning('scripts/compat_v073.lua'))
	end)
	t('global.getGlobalFromScript', function()
		return getGlobalFromScript('scripts/compat_v104.lua', 'v104_marker') == 'hello'
	end)
	t('global.setGlobalFromScript', function()
		setGlobalFromScript('scripts/compat_v104.lua', 'v104_got', 42)
		return getGlobalFromScript('scripts/compat_v104.lua', 'v104_got') == 42
	end)
	t('global.getVar.setVar', function()
		setVar('lt_var', 7)
		return getVar('lt_var') == 7
	end)
	i('global.callScript', function()
		return tostring(callScript('scripts/compat_v104.lua', 'helper', {}))
	end)
	t('global.addHaxeLibrary', function()
		addHaxeLibrary('FunkinLua')
		return true
	end)
	t('global.changePresence', function()
		changePresence('test', 'testing')
		return true
	end)
	t('global.changeDiscordPresence', function()
		changeDiscordPresence('test2', 'testing2')
		return true
	end)
	t('global.triggerEvent', function()
		triggerEvent('Add Camera Zoom', '0.015', '0.03')
		return true
	end)

	-- ── 文本 / 收尾 ────────────────────────────────────────────────
	t('text.makeLuaText', function()
		makeLuaText('lt_txt', 'hello', 200, 0, 0)
		return getProperty('lt_txt.text') == 'hello'
	end)
	t('text.addLuaText', function()
		addLuaText('lt_txt')
		return getObjectOrder('lt_txt') >= 0
	end)
	t('sprite.removeLuaSprite', function()
		cancelTween('lt_tw2')
		cancelTween('lt_tw3')
		cancelTween('lt_tn1')
		removeLuaSprite('lt_s1', true)
		return getObjectOrder('lt_s1') < 0
	end)

	rec('DONE', 'v073', 'failed=' .. failed)
end
