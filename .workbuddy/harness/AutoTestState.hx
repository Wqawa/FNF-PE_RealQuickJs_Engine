package;

import backend.ClientPrefs;
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

	override function create()
	{
		super.create();

		#if desktop
		// 默认把窗口挪到屏幕外 + 最小化，不弹到桌面上、不抢焦点；要截游戏画面就设 PE_AUTOTEST_SHOW=1。
		var show:Null<String> = Sys.getEnv('PE_AUTOTEST_SHOW');
		var visible:Bool = (show != null && show == '1');
		var win = lime.app.Application.current.window;
		if(win != null && !visible)
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
	#end
}
