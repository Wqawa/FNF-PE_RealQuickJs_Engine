package objects;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isPlayer:Bool = false;
	private var char:String = '';

	public function new(char:String = 'face', isPlayer:Bool = false, ?allowGPU:Bool = true)
	{
		super();
		this.isPlayer = isPlayer;
		changeIcon(char, allowGPU);
		scrollFactor.set();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 12, sprTracker.y - 30);
	}

	private var iconOffsets:Array<Float> = [0, 0];
	public function changeIcon(char:String, ?allowGPU:Bool = true) {
		if(this.char != char) {
			var name:String = 'icons/' + char;
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-' + char; //Older versions of psych engine's support
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-face'; //Prevents crash from missing icon
			
			var graphic = Paths.image(name, allowGPU);

			var iSize:Float = Math.round(graphic.width / graphic.height);
			loadGraphic(graphic, true, Math.floor(graphic.width / iSize), Math.floor(graphic.height));

			if(ClientPrefs.data.compatLegacyIcons)
			{
				// 0.6.3 只按 2 等分居中算偏移；1.0.4 多除了一个帧数，
				// 300x300 这种“一倍尺寸”的单帧图标会算成 (300-150)/1 = 150，
				// 整张图被往上顶掉一半 —— 头顶被裁。分帧规则保持原样，
				// 强塞 150x150 会把这类异形图切成 0 帧，直接变占位方块。
				iconOffsets[0] = (width - 150) / 2;
				iconOffsets[1] = (height - 150) / 2;
			}
			else
			{
				iconOffsets[0] = (width - 150) / iSize;
				iconOffsets[1] = (height - 150) / iSize;
			}
			updateHitbox();

			animation.add(char, [for(i in 0...frames.frames.length) i], 0, false, isPlayer);
			animation.play(char);
			this.char = char;

			// 旧版行为：1.0.4 只在对手按键时才刷新图标的“被打”帧，
			// 所以 Change Character 事件换完人，图标还是普通脸，状态没同步。
			// 打开这个开关时，换完立刻按当前血量对齐一次。
			if(ClientPrefs.data.compatLegacyIcons)
				syncFrameWithHealth();

			if(char.endsWith('-pixel'))
				antialiasing = false;
			else
				antialiasing = ClientPrefs.data.antialiasing;
		}
	}

	public var autoAdjustOffset:Bool = true;
	override function updateHitbox()
	{
		super.updateHitbox();
		if(autoAdjustOffset)
		{
			offset.x = iconOffsets[0];
			offset.y = iconOffsets[1];
		}
	}

	/** 按 PlayState 当前血量把图标摆到「普通 / 被打」对应的帧 */
	public function syncFrameWithHealth():Void
	{
		if(animation == null || animation.curAnim == null) return;
		if(frames == null || frames.frames.length < 2) return;

		var ps:Dynamic = flixel.FlxG.state;
		if(ps == null) return;
		var hp:Dynamic = Reflect.getProperty(ps, 'health');
		if(hp == null) return;
		var health:Float = cast hp;
		// health 是 0~2，1 是中间；对手图标在血高时才是「被打」
		// 0.6.3 的判据：血条 percent < 20 玩家图标变脸，> 80 对手图标变脸
		// （percent = health / 2 * 100，所以 <20% 等于 health < 0.4，>80% 等于 health > 1.6）
		var losing:Bool = isPlayer ? (health < 0.4) : (health > 1.6);
		animation.curAnim.curFrame = losing ? 1 : 0;
	}

	public function getCharacter():String {
		return char;
	}
}
