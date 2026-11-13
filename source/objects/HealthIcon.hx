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

			if(ClientPrefs.data.compatLegacyIcons)
			{
				// 0.6.3 的算法：帧固定 150x150、偏移按 2 等分居中。
				// 1.0.4 用 round(宽/高) 猜帧数、偏移除以帧数，遇到 300x300 这种
				// “一倍尺寸”的 mod 图标会算成 offset=(300-150)/1=150，
				// 整张图就被往上顶掉一半 —— 头上被切掉那种。
				loadGraphic(graphic, true, 150, 150);
				iconOffsets[0] = (width - 150) / 2;
				iconOffsets[1] = (height - 150) / 2;
			}
			else
			{
				var iSize:Float = Math.round(graphic.width / graphic.height);
				loadGraphic(graphic, true, Math.floor(graphic.width / iSize), Math.floor(graphic.height));
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
		var losing:Bool = isPlayer ? (health < 1.0) : (health > 1.0);
		animation.curAnim.curFrame = losing ? 1 : 0;
	}

	public function getCharacter():String {
		return char;
	}
}
