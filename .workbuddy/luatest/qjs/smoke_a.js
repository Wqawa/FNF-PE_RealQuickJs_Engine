// QuickJS 路径的冒烟测试。
//
// 只在 Gameplay → JS Engine = QuickJS 时被送进真运行时；Troll 那条路跑不动这个文件
// （它用现代 JS 写，转译器只认花括号和 function）。
//
// 结果写 .workbuddy/testout/qjs_smoke.txt，一行一条 PASS / FAIL，末尾 DONE|qjs，
// 和 Lua 回归那套格式一致，run_qjs_test.sh 靠它判断跑完了没有。

var OUT = '@@ROOT@@/.workbuddy/testout/qjs_smoke.txt';
var SELF = '@@ROOT@@/.workbuddy/testout/qjs_selfremove.txt';

var lines = [];
var frame = 0;
var ticks = 0;
var timerHit = false;
var stopArmed = true;
var stopChecked = false;
var fileChecked = false;
var finished = false;

function say(tag, ok, detail) {
	lines.push((ok ? 'PASS ' : 'FAIL ') + tag + (detail ? ' :: ' + detail : ''));
}

function flush() {
	saveFile(OUT, lines.join('\n') + '\nDONE|qjs\n', true);
}

function onCreate() {
	say('boot', true, 'engine=QuickJS');

	// seedGlobals 塞进 context 的 bpm 应该能直接当 JS 全局读到
	say('seeded-global', Number(curBpm) > 0, 'curBpm=' + curBpm);

	// setVar / getVar 走的是 MusicBeatState.variables，和 Lua 共用一张表
	setVar('qjs_shared', 7);
	say('shared-store', Number(getVar('qjs_shared')) === 7, 'qjs_shared=' + getVar('qjs_shared'));

	// 属性读写走 LuaUtils，和 Lua 同一条路
	setProperty('health', 1.5);
	say('property-roundtrip', Number(getProperty('health')) === 1.5, 'health=' + getProperty('health'));

	// 真加一个 .js 进去（不是转译，是给新文件开新 context）。
	// 这个文件故意不在 scripts/ 里，只有 addLuaScript 才会把它装进来。
	say('addLuaScript', addLuaScript('qjstest/qjs_child.js') === true);
	say('isRunning-after-add', isRunning('qjstest/qjs_child.js') === true);

	trace('[smoke_a] onCreate done');
}

function onCreatePost() {
	// qjs_child.js 也有同名回调。一文件一 context 的意义就在这：
	// 两条都得跑，谁也不会顶掉谁。
	say('onCreatePost', true, '同名回调没有被顶掉');
}

function onCountdownTick(swagCounter) {
	ticks++;
}

function onStartCountdown() {
	// 第一次故意喊停，引擎应该老老实实等我们调 startCountdown()
	if (!stopArmed) return;
	stopArmed = false;
	return Function_Stop;
}

function onTimerCompleted(tag, loops, loopsLeft) {
	if (tag === 'qjs_t') timerHit = true;
}

function onUpdatePost(elapsed) {
	frame++;
	if (finished) return;

	if (frame === 20) {
		// 跨脚本读全局
		var tag = String(getGlobalFromScript('qjstest/qjs_child.js', 'childTag'));
		say('getGlobalFromScript', tag === 'child-alive', 'childTag=' + tag);

		// 跨脚本调函数：callScript 的返回值要能带回来（child 里 addOne 返回 42）
		var r = callScript('qjstest/qjs_child.js', 'addOne', 41);
		say('callScript', Number(r) === 42, 'addOne(41)=' + r);

		// 脚本清单里应该有两个
		say('getRunningScripts', String(getRunningScripts()).indexOf('qjs_child') >= 0);

		// 跨通道广播：child 收到 onMyCustomEvent 会把自己那个 flag 置上
		callOnScripts('onMyCustomEvent', 'ping');
		var seen = String(getGlobalFromScript('qjstest/qjs_child.js', 'childEventSeen'));
		say('callOnScripts', seen === 'true', 'childEventSeen=' + seen);

		// 全脚本写变量：真正写的是各自 context 的全局（和 Lua 的 setOnScripts 一致）
		setOnScripts('qjs_broadcast', 5);
		var bc = (typeof qjs_broadcast === 'undefined') ? 'undefined' : qjs_broadcast;
		say('setOnScripts', bc !== 'undefined' && Number(bc) === 5, 'qjs_broadcast=' + bc);

		// 没有 mod 时 getModSetting 应该老实返回空串（同时会在 js_log 里留一条 warn）
		say('getModSetting-noMod', getModSetting('anything') === '');

		say('achievementExists', achievementExists('__definitely_not_an_achievement__') === false);
		say('getTranslationPhrase', String(getTranslationPhrase('__missing_key__', 'fallback')).length > 0);

		say('removeLuaScript', removeLuaScript('qjstest/qjs_child.js') === true);
		say('isRunning-after-remove', isRunning('qjstest/qjs_child.js') === false);
	}

	if (frame === 25) {
		// shader：先证明找不到的时候老实返回 false，再走一遍真编译/挂载/摘掉
		say('initLuaShader-missing', initLuaShader('__no_such_shader__') === false);
		say('initLuaShader', initLuaShader('qjstest') === true);
		say('setSpriteShader', setSpriteShader('boyfriend', 'qjstest') === true);
		say('addShaderToCam', addShaderToCam('camGame', 'qjstest', 'qjs_cam') === true);
		say('removeCamShader', removeCamShader('camGame', 'qjs_cam') === true);
		say('clearCamShaders', clearCamShaders('camGame') === true);
	}

	if (frame === 40) {
		runTimer('qjs_t', 0.2, 1);
	}

	if (frame === 120) {
		stopChecked = true;
		// 没收到过一次 onCountdownTick，说明 Function_Stop 真把引擎拦住了
		var ok = (ticks === 0);
		say('function-stop', ok, 'ticks=' + ticks);
		if (ok) startCountdown(); // 轮到我们自己放行
	}

	if (frame === 260 && !fileChecked) {
		fileChecked = true;
		// saveFile 落在 Paths.mods()，getTextFromFile 也必须走 Paths 才读得回来。
		// 以前一个查 CWD、一个查 mods/body，写进去的文件永远读不到。
		saveFile('qjs_roundtrip.txt', 'hello-qjs', false);
		var back = getTextFromFile('qjs_roundtrip.txt');
		say('file-roundtrip', back === 'hello-qjs', 'back=' + back);
		say('file-delete', deleteFile('qjs_roundtrip.txt', false, false) === true);
	}

	if (frame === 300 && stopChecked && !finished) {
		say('countdown-after-stop', ticks > 0, 'ticks=' + ticks);
		say('timer-callback', timerHit);
		finished = true;
		flush();

		// 自卸：close() 走的还是 unloadFile，context 的 free 推到下一帧。
		// 当前这一帧必须还能跑完（下面那行 saveFile 就是证据）。
		say('close-self', close() === true);
		saveFile(SELF, lines.join('\n') + '\nDONE|self\n', true);
	}
}
