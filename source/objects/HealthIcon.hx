package objects;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isPlayer:Bool = false;
	private var char:String = '';
	// 图标是按「图片名」缓存的，而不同 mod 的同一角色图片名一模一样（都是 icons/bf）。
	// 只比 char 的话，编辑器里换 mod 之后图标会一直用上一个 mod 的图。
	private var loadedMod:String = '~';

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
		var curMod:String = Mods.currentModDirectory;
		if(curMod == null) curMod = '';
		if(this.char != char || this.loadedMod != curMod) {
			if(animation != null && this.char.length > 0 && animation.exists(this.char))
				animation.remove(this.char);
			var name:String = 'icons/' + char;
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-' + char; //Older versions of psych engine's support
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-face'; //Prevents crash from missing icon
			
			if(ClientPrefs.data.compatLegacyIcons)
			{
				// 直接搬 0.6.3：先无帧加载拿到真实尺寸，再按「宽/2、高」切两帧。
				// 它算宽度用的是第二帧加载后的 width（= 单帧宽），所以 300x300 的
				// 一倍尺寸图标 offset 是 0，不会像 1.0.4 那样算成 150 把头顶顶掉。
				var file:Dynamic = Paths.image(name, allowGPU);
				loadGraphic(file);
				loadGraphic(file, true, Math.floor(width / 2), Math.floor(height));
				iconOffsets[0] = (width - 150) / 2;
				iconOffsets[1] = (width - 150) / 2;
			}
			else
			{
				var graphic = Paths.image(name, allowGPU);
				var iSize:Float = Math.round(graphic.width / graphic.height);
				loadGraphic(graphic, true, Math.floor(graphic.width / iSize), Math.floor(graphic.height));
				iconOffsets[0] = (width - 150) / iSize;
				iconOffsets[1] = (height - 150) / iSize;
			}
			updateHitbox();

			if(ClientPrefs.data.compatLegacyIcons)
				animation.add(char, [0, 1], 0, false, isPlayer);
			else
				animation.add(char, [for(i in 0...frames.frames.length) i], 0, false, isPlayer);
			animation.play(char);
			this.char = char;
			this.loadedMod = curMod;

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
