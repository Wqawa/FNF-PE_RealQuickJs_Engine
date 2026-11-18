// smoke_a.js 用 addLuaScript 加进来的第二个脚本。
//
// 它和 smoke_a 定义了同名的 onCreatePost / onUpdatePost。
// 一文件一 context 之前，后加载的会把前一个的同名函数顶掉；现在两条都得跑。
// 自己写一份结果文件，证明它不是被顶掉的那一个。

var childTag = 'child-alive';
var childFrame = 0;
var childEventSeen = false;

// 给 smoke_a 的 callScript 用：跨脚本调函数，返回值要能带回去
function addOne(x) {
	return Number(x) + 1;
}

// 给 smoke_a 的 callOnScripts 用：跨通道广播要能打到这里
function onMyCustomEvent(arg) {
	childEventSeen = true;
	trace('[qjs_child] 收到 onMyCustomEvent(' + arg + ')');
}

function onCreatePost() {
	saveFile('@@ROOT@@/.workbuddy/testout/qjs_child.txt',
		'PASS child-onCreatePost :: childTag=' + childTag + '\nPASS child-same-name-callbacks\n' + 'DONE|child\n', true);
}

function onUpdatePost(elapsed) {
	childFrame++;
	if (childFrame === 5) trace('[qjs_child] onUpdatePost 跑到第 5 帧');
}
