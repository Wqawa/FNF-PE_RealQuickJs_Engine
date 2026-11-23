package;

import backend.ClientPrefs;
import backend.Conductor;
import backend.Difficulty;
import backend.Highscore;
import backend.Mods;
import backend.Song;
import states.LoadingState;
import states.PlayState;

/**
 * 测试专用入口：PE_AUTOTEST=歌名 时跳过全部菜单直接进 PlayState。
 * 只在跑回归时由 .workbuddy/harness/apply_hook.py 临时拷进 source/，平时仓库里没有这个文件。
 *
 * 两个坑：
 *  - FunkinLua 构造时会读 FlxG.sound.music.length，正常流程里那是上一首菜单曲，
 *    直接开局的话是 null，所以这里先放一段菜单音乐垫着。
 *  - 窗口挪到屏幕外，省得跑测试的时候抢人桌面。
 */
class AutoTestState extends MusicBeatState
{
	public static inline var ENV:String = 'PE_AUTOTEST';

	public static function requestedSong():String
	{
		#if desktop
		var song:String = Sys.getEnv(ENV);
		if(song != null && song.length > 0) return song.toLowerCase();
		#end
		return null;
	}

	@:access(states.LoadingState)
	@:access(states.PlayState)
	override function create()
	{
		super.create();

		#if desktop
		// 默认把窗口挪到屏幕外 + 最小化，不弹到桌面上、不抢焦点；要截游戏画面就设 PE_AUTOTEST_SHOW=1。
		// PE_AUTOTEST_SHOW=2 = 可见但挪出屏幕：测帧率时用，隐藏的窗口会被系统降到 ~24fps。
		var show:Null<String> = Sys.getEnv('PE_AUTOTEST_SHOW');
		var offscreen:Bool = (show != null && show == '2');
		var visible:Bool = (show != null && (show == '1' || offscreen));
		var win = lime.app.Application.current.window;
		if(win != null && offscreen)
		{
			win.x = -4000;
			win.y = -4000;
		}
		else if(win != null && !visible)
		{
			win.x = -4000;
			win.y = -4000;
			win.minimized = true;
			// minimized 只是缩小，任务栏里还留一格。真正的"跑测试别烦我"要直接隐藏窗口。
			// 要留着任务栏（比如手动看进程在不在）设 PE_AUTOTEST_TASKBAR=1。
			var keepTaskbar:Null<String> = Sys.getEnv('PE_AUTOTEST_TASKBAR');
			if(keepTaskbar == null || keepTaskbar != '1') win.visible = false;
		}
		// 跑测试一律静音：把默认声音组的音量推到 0，不动玩家存档里的音量设置。
		// 音量不影响 music.time，Conductor 照常往前走。
		FlxG.sound.volume = 0;
		// 窗口可见时顺手开 botplay，不然没人打音符，note splash 根本不会生成，截图看不到东西
		var bot:Null<String> = Sys.getEnv('PE_AUTOTEST_BOT');
		if(visible || (bot != null && bot == '1'))
		{
			try ClientPrefs.data.gameplaySettings.set('botplay', true) catch(e:Dynamic) {}
		}
		// 窗口挪到屏幕外会失焦，flixel 默认失焦自动暂停 —— 一暂停 update 就停了，
		// 后面 beat/step 全不触发，看起来像卡死。测试期间必须关掉。
		FlxG.autoPause = false;
		#end

		var song:String = requestedSong();
		FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);

		// .js 用哪个引擎跑，测试时用环境变量临时定，不改玩家的存档
		// （Gameplay Settings 里那个 JS Engine 就是这个字段）
		var jsEng:Null<String> = Sys.getEnv('PE_AUTOTEST_JSENGINE');
		if(jsEng != null && jsEng.length > 0) ClientPrefs.data.jsEngine = jsEng;

		// 音频流式开关：只改内存里的值，Sys.exit 前不落盘，不会污染存档
		var streamAudio:Null<String> = Sys.getEnv('PE_AUTOTEST_STREAMAUDIO');
		if(streamAudio != null && streamAudio.length > 0) ClientPrefs.data.streamAudio = (streamAudio == '1');

		// 分段加载开关，同样只改内存值
		var segmented:Null<String> = Sys.getEnv('PE_AUTOTEST_SEGMENTED');
		if(segmented != null && segmented.length > 0) ClientPrefs.data.segmentedLoading = (segmented == '1');

		// 加载屏自检：抓一张加载中的截图，顺便把左上角文本和卡死询问面板打出来
		if (Sys.getEnv('PE_AUTOTEST_LOADSHOT') == '1')
		{
			var phase:Int = 0;
			var dump:StringBuf = new StringBuf();
			FlxG.signals.postUpdate.add(function() {
				if (!Std.isOfType(FlxG.state, states.LoadingState)) return;
				var ls:states.LoadingState = cast FlxG.state;
				phase++;
				if (phase == 4)
				{
					dump.add('[loadtext] ' + ls.detailText.text.split('\n').join(' | ') + '\n');
					ls.stallTimer = 999; // 下一帧就弹询问面板
					try sys.io.File.saveContent('./testout/loadshot.txt', dump.toString()) catch(e:Dynamic) {}
				}
				if (phase == 60)
				{
					dump.add('[loadtext] stall=' + ls.stallInfo.text.split('\n').join(' | ') + '\n');
					var vis:Int = 0;
					for (m in ls.stallMembers) if (m.visible) vis++;
					dump.add('[loadtext] visible=' + vis + '/' + ls.stallMembers.length + '\n');
					dump.add('[loadtext] detail y=' + ls.detailText.y + ' alpha=' + ls.detailText.alpha
						+ ' vis=' + ls.detailText.visible + ' h=' + ls.detailText.height + '\n');
					shot();
					try sys.io.File.saveContent('./testout/loadshot.txt', dump.toString()) catch(e:Dynamic) {}
					Sys.exit(0);
				}
			});
		}

		// 帧率分离自检：PE_AUTOTEST_FRAMERATE="绘制/计算"，例如 10/60
		var fr:Null<String> = Sys.getEnv('PE_AUTOTEST_FRAMERATE');
		if (fr != null && fr.indexOf('/') > 0)
		{
			var parts:Array<String> = fr.split('/');
			ClientPrefs.data.drawFramerate = Std.parseInt(parts[0]);
			ClientPrefs.data.updateFramerate = Std.parseInt(parts[1]);
			ClientPrefs.applyFramerate();
			trace('[fps] requested=$fr applied draw=' + FlxG.drawFramerate + ' update=' + FlxG.updateFramerate
				+ ' pref=' + ClientPrefs.data.framerate);
		}

		// 窗口尺寸自检：PE_AUTOTEST_WINSIZE="分辨率/百分比"，例如 720/100、1080/50
		var ws:Null<String> = Sys.getEnv('PE_AUTOTEST_WINSIZE');
		if (ws != null && ws.indexOf('/') > 0)
		{
			var parts:Array<String> = ws.split('/');
			ClientPrefs.data.windowRes = Std.parseInt(parts[0]);
			ClientPrefs.data.windowScale = Std.parseInt(parts[1]);
			backend.WindowSize.apply(ClientPrefs.data.windowRes, ClientPrefs.data.windowScale);
			var win = lime.app.Application.current.window;
			trace('[win] res=' + ClientPrefs.data.windowRes + ' scale=' + ClientPrefs.data.windowScale
				+ ' window=' + win.width + 'x' + win.height + ' wscale=' + win.scale
				+ ' dpi=' + win.display.dpi
				+ ' stage=' + FlxG.stage.stageWidth + 'x' + FlxG.stage.stageHeight
				+ ' flx=' + FlxG.width + 'x' + FlxG.height
				+ ' display=' + Std.int(win.display.bounds.width) + 'x' + Std.int(win.display.bounds.height));
		}

		// HUD 自检：跑 5 秒后把时间/分数/图标缩放打出来（验证 timeTxt 缓存和图标缩放）
		if (Sys.getEnv('PE_AUTOTEST_HUD') == '1')
		{
			var n:Int = 0;
			FlxG.signals.postUpdate.add(function() {
				n++;
				if (n == 300 && PlayState.instance != null)
				{
					var ps:PlayState = PlayState.instance;
					var w2 = lime.app.Application.current.window;
					trace('[hud] window=' + w2.width + 'x' + w2.height
						+ ' stage=' + FlxG.stage.stageWidth + 'x' + FlxG.stage.stageHeight
						+ ' flx=' + FlxG.width + 'x' + FlxG.height
						+ ' cam=' + FlxG.camera.width + 'x' + FlxG.camera.height
						+ ' gamescale=' + FlxG.game.scaleX + 'x' + FlxG.game.scaleY
						+ ' scalemode=' + (FlxG.scaleMode == null ? 'null' : Type.getClassName(Type.getClass(FlxG.scaleMode))));
					shot();
					trace('[hud] time=' + ps.timeTxt.text + ' score=' + ps.scoreTxt.text.split('\n').join(' | ')
						+ ' icon1=' + ps.iconP1.scale.x + ' icon2=' + ps.iconP2.scale.x
						+ ' bpm=' + Conductor.bpm + ' songPos=' + Std.int(Conductor.songPosition));
					if (body.Main.fpsVar != null)
					{
						body.Main.fpsVar.detailed = true;
						body.Main.fpsVar.updateText();
						trace('[hud] fpsvar=' + body.Main.fpsVar.text.split('\n').join(' | '));
					}
				}
			});
		}

		try
		{
			// 测 mod 里的歌要先切到那个 mod，否则 Paths 根本找不到它的 data/
			var mod:Null<String> = Sys.getEnv('PE_AUTOTEST_MOD');
			if(mod != null && mod.length > 0) Mods.currentModDirectory = mod;
			// 脚本回归要干净环境：玩家上次选的 mod 会带进它自己的 lua/hscript，
			// 那些东西的报错会混进测试结果，看起来像脚本桥坏了
			var noMod:Null<String> = Sys.getEnv('PE_AUTOTEST_NOMOD');
			if(noMod != null && noMod == '1') Mods.currentModDirectory = '';

			PlayState.isStoryMode = false;
			// 2 = Hard。默认难度（Normal）的谱面没有难度后缀，这里要测 mod 的 -hard 文件。
			PlayState.storyDifficulty = 2;
			PlayState.storyWeek = 1;

			// 和从菜单进歌一样，先让 currentLevel 停在 shared。谁把它设成 weekN 的，只有
			// loadNextDirectory 一条路 —— 这样测试才能看出那条路有没有被后面的 switchState 打掉。
			Paths.setCurrentLevel('shared');
			// 谱面名默认按难度拼后缀；mod 的难度列表不一定和本体一致，所以留一个直接指定的口子
			var chartOverride:Null<String> = Sys.getEnv('PE_AUTOTEST_CHART');
			var chart:String = (chartOverride != null && chartOverride.length > 0)
				? chartOverride
				: Highscore.formatSong(song, PlayState.storyDifficulty);
			trace('[autotest] diff=' + PlayState.storyDifficulty + ' postfix=' + Difficulty.getFilePath(PlayState.storyDifficulty) + ' chart=' + chart);
			Song.loadFromJson(chart, song);

			// 进歌这一步要和 Freeplay 完全一致：先 prepareToSong() 收集素材，再
			// loadAndSwitchState() 走 getNextState -> loadNextDirectory 切 week 目录 ->
			// LoadingState 预载。以前这里是直接 switchState(new PlayState()) 再手动补一次
			// loadNextDirectory，绕开了 LoadingState，正好把「switchState 会不会把 currentLevel
			// 打回 shared」这个 bug 藏住了。别再改回去。
			trace('[autotest] starting ' + song + ' (mod: ' + Mods.currentModDirectory + ', chart: ' + chart + ')');
		}
		catch(e:Dynamic)
		{
			// 谱面没加载上就别往下走了：PlayState.SONG 是 null 的话 Conductor 直接空引用崩在
			// 一个没有上下文的调用栈里，看不出是测试入口的问题。
			trace('[autotest] failed: ' + e);
			Sys.exit(1);
			return;
		}

		if (Sys.getEnv('PE_AUTOTEST_DIAG') == '1')
		{
			var frames:Int = 0;
			FlxG.signals.postUpdate.add(function()
			{
				frames++;
				// 等谱面和 shader 都挂上再抓，10 秒足够（mod 资源多，4 秒还在 loading）
				if (frames == 600) dumpGeometry();
			});
		}

		// 崩溃屏幕自测：跑起来 1 秒后手动触发，再等几帧看是不是真切过去了
		if (Sys.getEnv('PE_AUTOTEST_CRASH') == '1')
		{
			var cframes:Int = 0;
			FlxG.signals.postUpdate.add(function()
			{
				cframes++;
				if (cframes == 60)
				{
					trace('[autotest] 手动触发崩溃屏幕');
					backend.EngineCrash.report('autotest: manually triggered crash screen', true);
				}
				if (cframes == 100)
				{
					var cls:String = Type.getClassName(Type.getClass(FlxG.state));
					var ok:Bool = Std.isOfType(FlxG.state, backend.CrashState);
					try sys.io.File.saveContent('./testout/crash_check.txt',
						(ok ? 'PASS' : 'FAIL') + ' crash-state :: ' + cls + '\nDONE|crash\n')
					catch (e:Dynamic) trace('[autotest] 写结果失败: ' + e);
					shot();
				}
			});
		}

		// 性能探针：PE_AUTOTEST_PROFILE=秒数 时统计每帧 CPU/间隔/内存，跑完写 profile.txt 退出
		#if (desktop && cpp)
		var profSec:Null<String> = Sys.getEnv('PE_AUTOTEST_PROFILE');
		if (profSec != null && profSec.length > 0 && profSec != '0')
			installProfile(Std.parseFloat(profSec));
		#end

		// 左上角内存显示的取值自检：进歌跑 3 秒后把两种模式的文本抓一次（PE_AUTOTEST_FPSDBG=1）。
		// 顺便在 5 秒时切到 spookeez，验证换歌时旧贴图有没有被清掉
		if (Sys.getEnv('PE_AUTOTEST_FPSDBG') == '1')
		{
			var n:Int = 0;
			var switched:Bool = false;
			FlxG.signals.postUpdate.add(function() {
				n++;
				if (n == 180 && body.Main.fpsVar != null)
				{
					body.Main.fpsVar.detailed = true;
					body.Main.fpsVar.updateText();
					trace('[fpsdbg] song1: ' + body.Main.fpsVar.text.replace('\n', ' | '));
				}
				if (n == 300 && !switched)
				{
					switched = true;
					trace('[fpsdbg] switching to spookeez');
					PlayState.SONG = Song.loadFromJson('spookeez', 'spookeez');
					LoadingState.prepareToSong();
					LoadingState.loadAndSwitchState(new PlayState());
				}
				if (n == 600 && body.Main.fpsVar != null)
				{
					body.Main.fpsVar.detailed = true;
					body.Main.fpsVar.updateText();
					trace('[fpsdbg] song2: ' + body.Main.fpsVar.text.replace('\n', ' | '));
				}
			});
		}

		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());
	}

	#if desktop
	/** 把当前画面抓成 png（窗口最小化也能抓，走的是 display tree 不是窗口） */
	static function shot():Void
	{
		try
		{
			// allow-high-dpi 下窗口逻辑尺寸 1280x720，但渲染已放大 1.5 倍铺到 1920x1080，
			// 按逻辑尺寸建图会把放大后的画面裁掉（看着像排版错了）。
			// 干脆按 2 倍建，怎么缩都装得下。
			var win = lime.app.Application.current.window;
			var w:Int = Std.int(win.width) * 2;
			var h:Int = Std.int(win.height) * 2;
			var bmp = new openfl.display.BitmapData(w, h, true, 0xFF000000);
			bmp.draw(FlxG.stage);
			var png = bmp.encode(bmp.rect, new openfl.display.PNGEncoderOptions());
			if (png != null) sys.io.File.saveBytes('./testout/crash_shot.png', haxe.io.Bytes.ofData(png));
			bmp.dispose();
		}
		catch (e:Dynamic) trace('[autotest] shot failed: ' + e);
	}

	@:access(flixel.FlxCamera)
	static function dumpGeometry():Void
	{
		try
		{
			var sb:StringBuf = new StringBuf();
			sb.add('scaleMode=' + Type.getClassName(Type.getClass(FlxG.scaleMode)) + '\n');
			var sm = FlxG.scaleMode;
			sb.add('scale=' + sm.scale.x + ',' + sm.scale.y
				+ ' gameSize=' + sm.gameSize.x + 'x' + sm.gameSize.y
				+ ' deviceSize=' + sm.deviceSize.x + 'x' + sm.deviceSize.y + '\n');
			sb.add('flxg=' + FlxG.width + 'x' + FlxG.height + '\n');
			sb.add('game=' + FlxG.game.x + ',' + FlxG.game.y + ' scale=' + FlxG.game.scaleX + ',' + FlxG.game.scaleY + '\n');
			sb.add('stage=' + FlxG.stage.stageWidth + 'x' + FlxG.stage.stageHeight + ' scaleMode=' + FlxG.stage.scaleMode + '\n');
			var win = lime.app.Application.current.window;
			sb.add('window=' + win.width + 'x' + win.height + ' dpi=' + lime.system.System.getDisplay(0).dpi + '\n');

			var ps:PlayState = PlayState.instance;
			for (cam in FlxG.cameras.list)
			{
				var tag:String = 'other';
				if (ps != null)
				{
					if (cam == ps.camGame) tag = 'Game';
					else if (cam == ps.camHUD) tag = 'HUD';
				}
				sb.add('cam ' + tag
					+ ' pos=' + cam.x + ',' + cam.y
					+ ' size=' + cam.width + 'x' + cam.height
					+ ' zoom=' + cam.zoom
					+ ' canvasScale=' + (cam.canvas != null ? cam.canvas.scaleX + ',' + cam.canvas.scaleY : 'null')
					+ ' flashSprite=' + (cam.flashSprite != null ? cam.flashSprite.x + ',' + cam.flashSprite.y : 'null')
					+ ' filters=' + (cam.filters != null ? cam.filters.length : 0)
					+ '\n');
			}

			sys.io.File.saveContent('./testout/scale_diag.txt', sb.toString());

			// flixel 5.6 没有 FlxG.screenshot，直接拿 game 画到 BitmapData 再编码
			var bmp = new openfl.display.BitmapData(Std.int(FlxG.width), Std.int(FlxG.height), true, 0);
			bmp.draw(FlxG.game);
			var png = bmp.encode(bmp.rect, new openfl.display.PNGEncoderOptions());
			if (png != null) sys.io.File.saveBytes('./testout/scale_shot.png', haxe.io.Bytes.ofData(png));
			bmp.dispose();
		}
		catch (e:Dynamic) trace('[autotest] dump failed: ' + e);
	}
	@:access(flixel.system.frontEnds.BitmapFrontEnd._cache)
	@:access(states.PlayState)
	static function installProfile(duration:Float):Void
	{
		var cpu:Array<Float> = [];
		var gap:Array<Float> = [];
		var memUse:Array<Int> = [];
		var memCur:Array<Int> = [];
		var started:Bool = false;
		var tStart:Float = 0;
		var tPrev:Float = 0;
		var tPre:Float = 0;
		var lastMem:Float = -1;
		var heapLine:String = '';

		trace('[profile] armed, will sample ' + duration + 's after the song starts');

		FlxG.signals.preUpdate.add(function() tPre = haxe.Timer.stamp());

		FlxG.signals.postDraw.add(function()
		{
			var now:Float = haxe.Timer.stamp();
			var ps:PlayState = PlayState.instance;

			// 等谱面真开跑，loading 和倒计时那段不算
			if (!started)
			{
				if (ps == null || !ps.startedCountdown) return;
				started = true;
				tStart = tPrev = now;
				lastMem = now;
				memUse.push(profileMem(0));
				memCur.push(profileMem(2));

				// Immix 默认回收后留 100% 空闲区（存活量翻倍），先量一下 compact 前后的四个数
				var u0:Int = profileMem(0), r0:Int = profileMem(1), c0:Int = profileMem(2);
				var tt:Float = haxe.Timer.stamp();
				cpp.vm.Gc.compact();
				var compactMs:Int = Math.round((haxe.Timer.stamp() - tt) * 1000);
				heapLine = 'heap usage=' + profileMB(u0) + '/' + profileMB(profileMem(0))
					+ ' reserved=' + profileMB(r0) + '/' + profileMB(profileMem(1))
					+ ' current=' + profileMB(c0) + '/' + profileMB(profileMem(2))
					+ ' compact=' + compactMs + 'ms (before/after)\n';
				return;
			}

			cpu.push((now - tPre) * 1000);
			gap.push((now - tPrev) * 1000);
			tPrev = now;

			if (now - lastMem >= 1.0)
			{
				lastMem = now;
				memUse.push(profileMem(0));
				memCur.push(profileMem(2));
			}

			if (now - tStart < duration) return;

			// 收尾：再抓一次内存，音符/图集计数一起写出去
			memUse.push(profileMem(0));
			memCur.push(profileMem(2));

			var sb:StringBuf = new StringBuf();
			sb.add('song=' + (PlayState.SONG != null ? PlayState.SONG.song : '?')
				+ ' stage=' + (PlayState.SONG != null ? PlayState.SONG.stage : '?')
				+ ' frames=' + cpu.length + ' seconds=' + duration + '\n');
			var win = lime.app.Application.current.window;
			sb.add('loop draw=' + FlxG.drawFramerate + ' update=' + FlxG.updateFramerate
				+ ' pref=' + ClientPrefs.data.framerate
				+ ' win=' + (win != null ? (win.visible ? 'visible' : 'hidden') + (win.minimized ? '/min' : '') : 'null')
				+ '\n');

			var cpuS:Array<Float> = cpu.copy();
			cpuS.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
			var gapS:Array<Float> = gap.copy();
			gapS.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));

			sb.add('cpu_ms  avg=' + profileFixed(profileAvg(cpu)) + ' med=' + profileFixed(profilePct(cpuS, 0.5))
				+ ' p95=' + profileFixed(profilePct(cpuS, 0.95)) + ' max=' + profileFixed(profilePct(cpuS, 1.0)) + '\n');
			sb.add('gap_ms  avg=' + profileFixed(profileAvg(gap)) + ' med=' + profileFixed(profilePct(gapS, 0.5))
				+ ' p95=' + profileFixed(profilePct(gapS, 0.95)) + ' max=' + profileFixed(profilePct(gapS, 1.0)) + '\n');
			sb.add('fps_avg=' + profileFixed(1000 / Math.max(0.001, profileAvg(gap))) + '\n');

			sb.add('mem_use_mb   start=' + profileMB(memUse[0]) + ' end=' + profileMB(memUse[memUse.length - 1])
				+ ' peak=' + profileMB(profileMax(memUse)) + '\n');
			sb.add('mem_cur_mb   peak=' + profileMB(profileMax(memCur)) + '\n');
			var perSec:StringBuf = new StringBuf();
			for (m in memUse) perSec.add(profileMB(m) + ' ');
			sb.add('mem_use_each_second ' + perSec.toString() + '\n');

			var gfx:Int = 0;
			var gfxBytes:Int = 0;
			var big:Array<{k:String, b:Int}> = [];
			for (k in FlxG.bitmap._cache.keys())
			{
				var g:flixel.graphics.FlxGraphic = FlxG.bitmap._cache.get(k);
				if (g == null) continue;
				gfx++;
				var b:Int = Std.int(g.width * g.height * 4);
				gfxBytes += b;
				big.push({k: k, b: b});
			}
			big.sort(function(a, b) return b.b - a.b);

			sb.add(heapLine);

			// 音乐到底是不是流式源：__srcVorbisFile 有值、data 为空就是
			// 走 Dynamic 读私有字段，省得 @:privateAccess 用在这里不生效
			var music:Dynamic = FlxG.sound.music;
			var musicStreaming:Bool = false;
			var bufDetail:String = 'nobuf';
			if(music != null && music._sound != null)
			{
				var buf:Dynamic = music._sound.__buffer;
				musicStreaming = buf != null && buf.__srcVorbisFile != null && buf.data == null;
				bufDetail = 'buf=' + (buf != null) + ' vorbis=' + (buf != null && buf.__srcVorbisFile != null)
					+ ' nodata=' + (buf != null && buf.data == null);
			}
			sb.add('audio_streaming=' + musicStreaming + ' pref=' + ClientPrefs.data.streamAudio
				+ ' viz_needed=' + PlayState.audioVizNeeded + ' ' + bufDetail + '\n');

			sb.add('bitmaps total=' + profileMB(gfxBytes) + 'MB in ' + gfx + ' graphics\n');
			var top:StringBuf = new StringBuf();
			for (i in 0...Std.int(Math.min(8, big.length)))
				top.add(big[i].k + '=' + Std.int(big[i].b / 1024) + 'K ');
			sb.add('bitmaps_top ' + top.toString() + '\n');

			sb.add('counts notes=' + ps.notes.length + ' unspawn=' + ps.unspawnNotes.length
				+ ' graphics=' + gfx
				#if LUA_ALLOWED + ' lua=' + ps.luaArray.length #end
				#if HSCRIPT_ALLOWED + ' hscript=' + ps.hscriptArray.length #end
				+ '\n');

			try sys.io.File.saveContent('./testout/profile.txt', sb.toString())
			catch (e:Dynamic) trace('[profile] write failed: ' + e);

			trace('[profile] done');
			Sys.exit(0);
		});
	}

	static inline function profileMem(what:Int):Int
		return cpp.vm.Gc.memInfo(what);

	static function profileAvg(a:Array<Float>):Float
	{
		if (a.length == 0) return 0;
		var s:Float = 0;
		for (v in a) s += v;
		return s / a.length;
	}

	static function profileMax(a:Array<Int>):Int
	{
		var m:Int = 0;
		for (v in a) if (v > m) m = v;
		return m;
	}

	static function profilePct(sorted:Array<Float>, p:Float):Float
	{
		if (sorted.length == 0) return 0;
		var i:Int = Std.int((sorted.length - 1) * p);
		return sorted[i];
	}

	static inline function profileFixed(v:Float):String
		return Std.string(Math.round(v * 100) / 100);

	static inline function profileMB(bytes:Int):String
		return Std.string(Math.round(bytes / 1048576 * 10) / 10);

	#end
}
