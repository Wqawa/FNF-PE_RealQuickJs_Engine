-- 1.0.4 风格测试：按现代写法调用，确认 fork 的兼容层没有把本来正常的路径搞坏。
-- 结果写到 .workbuddy/testout/v104.txt
-- 同时对外暴露 v104_marker / v104_got / helper，供 v073 脚本测脚本互读。

local OUT = '@@ROOT@@/.workbuddy/testout/v104.txt'
local lines = {}
local failed = 0

v104_marker = 'hello'

function helper()
	return 'helped'
end

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

rec('INFO', 'script', 'v104 loaded, version=' .. tostring(version))

function onCreatePost()
	rec('INFO', 'state', 'onCreatePost')

	-- ── 现代全名解析 ────────────────────────────────────────────────
	t('class.fullName.ClientPrefs', function()
		return getPropertyFromClass('backend.ClientPrefs', 'data.downScroll') ~= nil
	end)
	t('class.fullName.data.write', function()
		local old = getPropertyFromClass('backend.ClientPrefs', 'data.downScroll')
		setPropertyFromClass('backend.ClientPrefs', 'data.downScroll', true)
		local now = getPropertyFromClass('backend.ClientPrefs', 'data.downScroll')
		setPropertyFromClass('backend.ClientPrefs', 'data.downScroll', old)
		return now == true
	end)
	t('class.fullName.Conductor', function()
		return getPropertyFromClass('backend.Conductor', 'bpm') > 0
	end)
	i('class.fullName.PlayState', function()
		return type(getPropertyFromClass('states.PlayState', 'instance'))
	end)

	-- ── Bar ────────────────────────────────────────────────────────
	t('bar.healthBar.width.write', function()
		setProperty('healthBar.width', 480)
		return near(getProperty('healthBar.width'), 480), getProperty('healthBar.width')
	end)
	t('bar.healthBar.height.write', function()
		setProperty('healthBar.height', 24)
		return near(getProperty('healthBar.height'), 24)
	end)
	t('bar.timeBar.width.write', function()
		setProperty('timeBar.width', 380)
		return near(getProperty('timeBar.width'), 380)
	end)

	-- ── 层级 / 相机 ────────────────────────────────────────────────
	t('order.setObjectOrder', function()
		local old = getObjectOrder('boyfriend')
		setObjectOrder('boyfriend', 3)
		local now = getObjectOrder('boyfriend')
		setObjectOrder('boyfriend', old)
		return now == 3, now
	end)
	t('order.setObjectOrder.group', function()
		local old = getObjectOrder('dad', 'dadGroup')
		setObjectOrder('dad', 0, 'dadGroup')
		local now = getObjectOrder('dad', 'dadGroup')
		setObjectOrder('dad', old, 'dadGroup')
		return now == 0, now
	end)
	t('cam.zoom', function()
		setProperty('camGame.zoom', 0.9)
		return near(getProperty('camGame.zoom'), 0.9)
	end)

	-- ── sprite ────────────────────────────────────────────────────
	t('sprite.makeLuaSprite', function()
		makeLuaSprite('lt2_s1', nil, 10, 20)
		return getProperty('lt2_s1.x') == 10
	end)
	t('sprite.makeGraphic', function()
		makeGraphic('lt2_s1', 32, 32, '00FF00')
		return getProperty('lt2_s1.width') == 32
	end)
	t('sprite.addLuaSprite', function()
		addLuaSprite('lt2_s1', true)
		return getObjectOrder('lt2_s1') >= 0
	end)
	t('sprite.loadGraphic', function()
		loadGraphic('lt2_s1', 'noteSplashes')
		return getProperty('lt2_s1.width') > 0
	end)
	t('sprite.setScrollFactor.xy', function()
		setScrollFactor('lt2_s1', 0.25, 0.75)
		return near(getProperty('lt2_s1.scrollFactor.x'), 0.25)
	end)
	t('sprite.setObjectCamera', function()
		setObjectCamera('lt2_s1', 'hud')
		return true
	end)
	t('sprite.scaleObject', function()
		scaleObject('lt2_s1', 1.5, 1.5, false)
		return near(getProperty('lt2_s1.scale.x'), 1.5)
	end)

	-- ── 动画 ──────────────────────────────────────────────────────
	t('anim.makeAnimatedLuaSprite', function()
		makeAnimatedLuaSprite('lt2_a1', 'characters/BOYFRIEND', 0, 0, 'sparrow')
		return getProperty('lt2_a1.numFrames') > 0, getProperty('lt2_a1.numFrames')
	end)
	t('anim.addAnimationByPrefix', function()
		addAnimationByPrefix('lt2_a1', 'hey', 'BF HEY!!', 24, false)
		playAnim('lt2_a1', 'hey', true)
		return getProperty('lt2_a1.animation.curAnim.name') == 'hey'
	end)
	t('anim.playAnim.bf', function()
		playAnim('boyfriend', 'idle', true)
		return getProperty('boyfriend.animation.curAnim.name') == 'idle'
	end)

	-- ── 补间 / 计时器（新签名带 options 表） ─────────────────────────
	t('tween.startTween', function()
		startTween('lt2_tw1', 'lt2_s1', {x = 200}, 1, {ease = 'linear'})
		return true
	end)
	t('tween.doTweenAlpha', function()
		doTweenAlpha('lt2_tw2', 'lt2_s1', 0.5, 1, 'linear')
		return true
	end)
	t('tween.cancelTween', function()
		cancelTween('lt2_tw1')
		cancelTween('lt2_tw2')
		return true
	end)
	t('timer.runTimer', function()
		runTimer('lt2_tm1', 5)
		cancelTimer('lt2_tm1')
		return true
	end)

	-- ── 组 ────────────────────────────────────────────────────────
	t('group.getPropertyFromGroup', function()
		return type(getPropertyFromGroup('strumLineNotes', 0, 'x')) == 'number'
	end)
	t('group.setPropertyFromGroup', function()
		setPropertyFromGroup('strumLineNotes', 0, 'visible', true)
		return getPropertyFromGroup('strumLineNotes', 0, 'visible') == true
	end)
	t('group.getObjectOrder', function()
		return getObjectOrder('dadGroup') >= 0, getObjectOrder('dadGroup')
	end)

	-- ── 设置 / 引擎信息 ────────────────────────────────────────────
	t('engine.version', function()
		return version ~= nil and #version > 0, version
	end)
	t('engine.bpm', function()
		return bpm > 0, bpm
	end)
	i('engine.getModSetting', function()
		return tostring(getModSetting('nope', 'luatest'))
	end)

	-- ── 文件 ──────────────────────────────────────────────────────
	t('file.saveFile', function()
		return saveFile('luatest_save.txt', 'ok', false) == true
	end)
	i('file.saveFile.readback', function()
		return tostring(getProperty('camGame.zoom'))
	end)

	-- ── 分数 / 血量 ───────────────────────────────────────────────
	t('game.setHealth', function()
		setHealth(1.2)
		return near(getProperty('health'), 1.2)
	end)
	t('game.addScore', function()
		local before = getScore()
		addScore(5)
		return getScore() == before + 5
	end)
	t('game.triggerEvent', function()
		triggerEvent('Add Camera Zoom', '0.01', '0.02')
		return true
	end)

	rec('DONE', 'v104', 'failed=' .. failed)
end
