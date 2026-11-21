package states.stages.objects;

#if funkin.vis
import funkin.vis.dsp.SpectralAnalyzer;
import funkin.vis.dsp.SpectralAnalyzer.Bar;
#end

class ABotSpeaker extends FlxSpriteGroup
{
	final VIZ_MAX = 7; //ranges from viz1 to viz7
	final VIZ_POS_X:Array<Float> = [0, 59, 56, 66, 54, 52, 51];
	final VIZ_POS_Y:Array<Float> = [0, -8, -3.5, -0.4, 0.5, 4.7, 7];

	public var bg:FlxSprite;
	public var vizSprites:Array<FlxSprite> = [];
	public var eyeBg:FlxSprite;
	public var eyes:FlxAnimate;
	public var speaker:FlxAnimate;

	#if funkin.vis
	var analyzer:SpectralAnalyzer;
	#end
	var volumes:Array<Float> = [];

	public var snd(default, set):FlxSound;
	function set_snd(changed:FlxSound)
	{
		snd = changed;
		#if funkin.vis
		initAnalyzer();
		#end
		return snd;
	}

	public function new(x:Float = 0, y:Float = 0)
	{
		super(x, y);

		var antialias = ClientPrefs.data.antialiasing;

		bg = new FlxSprite(90, 20).loadGraphic(Paths.image('abot/stereoBG'));
		bg.antialiasing = antialias;
		add(bg);

		var vizX:Float = 0;
		var vizY:Float = 0;
		var vizFrames = Paths.getSparrowAtlas('abot/aBotViz');
		for (i in 1...VIZ_MAX+1)
		{
			volumes.push(0.0);
			vizX += VIZ_POS_X[i-1];
			vizY += VIZ_POS_Y[i-1];
			var viz:FlxSprite = new FlxSprite(vizX + 140, vizY + 74);
			viz.frames = vizFrames;
			viz.animation.addByPrefix('VIZ', 'viz$i', 0);
			viz.animation.play('VIZ', true);
			viz.animation.curAnim.finish(); //make it go to the lowest point
			viz.antialiasing = antialias;
			vizSprites.push(viz);
			viz.updateHitbox();
			viz.centerOffsets();
			add(viz);
		}

		eyeBg = new FlxSprite(-30, 215).makeGraphic(1, 1, FlxColor.WHITE);
		eyeBg.scale.set(160, 60);
		eyeBg.updateHitbox();
		add(eyeBg);

		eyes = new FlxAnimate(-10, 230);
		Paths.loadAnimateAtlas(eyes, 'abot/systemEyes');
		eyes.anim.addBySymbolIndices('lookleft', 'a bot eyes lookin', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17], 24, false);
		eyes.anim.addBySymbolIndices('lookright', 'a bot eyes lookin', [18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35], 24, false);
		eyes.anim.play('lookright', true);
		eyes.anim.curFrame = eyes.anim.length - 1;
		add(eyes);

		speaker = new FlxAnimate(-65, -10);
		Paths.loadAnimateAtlas(speaker, 'abot/abotSystem');
		speaker.anim.addBySymbol('anim', 'Abot System', 24, false);
		speaker.anim.play('anim', true);
		speaker.anim.curFrame = speaker.anim.length - 1;
		speaker.antialiasing = antialias;
		add(speaker);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		#if funkin.vis
		if(analyzer == null && snd != null)
		{
			// snd 是在 startSong 里塞进来的，那时候音频通道/解码缓冲可能还没建好，这里补
			initAnalyzer();
		}
		if(analyzer != null)
		{
			updateFromAnalyzer();
			return;
		}
		#end

		// 兜底：拿不到频谱（安卓流式音频没有解码缓冲、没开 funkin.vis、还没开播）时，
		// 用歌曲时间算节拍相位，做一个每拍衰减的假电平，至少跟着歌的节拍动。
		updateFromBeat(elapsed);
	}

	#if funkin.vis
	var levels:Array<Bar>;
	var levelMax:Int = 0;
	function updateFromAnalyzer():Void
	{
		levels = analyzer.getLevels(levels);
		var oldLevelMax = levelMax;
		levelMax = 0;
		for (i in 0...Std.int(Math.min(vizSprites.length, levels.length)))
		{
			var animFrame:Int = Math.round(levels[i].value * 5);
			animFrame = Std.int(Math.abs(FlxMath.bound(animFrame, 0, 5) - 5)); // shitty dumbass flip, cuz dave got da shit backwards lol!
		
			vizSprites[i].animation.curAnim.curFrame = animFrame;
			levelMax = Std.int(Math.max(levelMax, 5 - animFrame));
		}

		if(levelMax >= 4)
		{
			//trace(levelMax);
			if(oldLevelMax <= levelMax && (levelMax >= 5 || speaker.anim.curFrame >= 3))
				beatHit();
		}
	}
	#end

	// 兜底路径的相位记录，用来保证每拍只触发一次 speaker 动画
	var lastFakeBeat:Int = -1;
	function updateFromBeat(elapsed:Float):Void
	{
		var crochet:Float = Conductor.crochet;
		if(crochet <= 0) crochet = 500;

		var pos:Float = Conductor.songPosition;
		if(snd != null && snd.playing && snd.length > 0) pos = snd.time;

		var beatPos:Float = pos / crochet;
		for (i in 0...vizSprites.length)
		{
			// 每根柱子错开一点相位，别整排一起跳
			var phase:Float = beatPos + i * 0.07;
			phase -= Math.floor(phase);
			var amp:Float = Math.pow(1 - phase, 2.5); // 拍头最响，往拍尾衰减
			var frame:Int = Std.int(FlxMath.bound(Math.round(amp * 5), 0, 5));
			vizSprites[i].animation.curAnim.curFrame = 5 - frame; // 和频谱路径同一套帧朝向
		}

		var beat:Int = Std.int(beatPos);
		if(beat != lastFakeBeat)
		{
			lastFakeBeat = beat;
			if(speaker.anim.curFrame >= 3) beatHit();
		}
	}

	public function beatHit()
	{
		speaker.anim.play('anim', true);
	}

	#if funkin.vis
	// openfl 9.3.2 起 SoundChannel 里的字段从 __source 改名成 __audioSource，
	// 而且没播起来（视频过场、还没 play）时这个值就是 null，直接丢进 SpectralAnalyzer
	// 构造会空指针把整首歌打崩，所以统一从这一个口子取。
	static function audioSourceOf(sound:FlxSound):lime.media.AudioSource
	{
		if(sound == null) return null;

		// @:privateAccess 只在表达式上生效（挂在函数声明上不授给函数体），
		// 所以这里拆成两句赋值。
		var channel:openfl.media.SoundChannel = null;
		@:privateAccess
		channel = sound._channel;
		if(channel == null) return null;

		var source:lime.media.AudioSource = null;
		@:privateAccess
		source = channel.__audioSource;
		return source;
	}

	public function initAnalyzer()
	{
		var source = audioSourceOf(snd);
		if(source == null) return;
		// 流式/还没解码完的音乐没有解码缓冲，getLevels 里直接读 buffer.data 会空指针；
		// 位深或声道数为 0 时那边还会除零。拿不到就交给上面的节拍兜底路径。
		if(source.buffer == null || source.buffer.data == null || source.buffer.data.length == 0) return;
		if(source.buffer.bitsPerSample <= 0 || source.buffer.channels <= 0) return;

		analyzer = new SpectralAnalyzer(source, 7, 0.1, 40);

		#if (desktop || android)
		// On desktop it uses FFT stuff that isn't as optimized as the direct browser stuff we use on HTML5
		// So we want to manually change it!
		// 安卓走的是同一套 cpp 后端 snd 实现，不降 FFT 点数会明显掉帧。
		analyzer.fftN = 256;
		#end
	}
	#end

	var lookingAtRight:Bool = true;
	public function lookLeft()
	{
		if(lookingAtRight) eyes.anim.play('lookleft', true);
		lookingAtRight = false;
	}
	public function lookRight()
	{
		if(!lookingAtRight) eyes.anim.play('lookright', true);
		lookingAtRight = true;
	}
}