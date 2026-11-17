package objects;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isPlayer:Bool = false;
	private var char:String = '';
	// Icons are cached by image name, and the same character in different mods resolves to
	// the same name (icons/bf), so comparing only the char kept the previous mod's image.
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
				// Straight from 0.6.3: load without frames to get the real size, then cut two frames at w/2 x h.
				// It measures width after loading the second frame (one frame wide), so a 300x300 icon
				// gets offset 0 instead of 1.0.4's 150 that cut the top off.
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

			// Old behaviour: 1.0.4 only refreshed the hurt frame when the opponent pressed a key,
			// so after a Change Character event the icon stayed on the normal face.
			// With this option on, it re-syncs to the current health right after the swap.
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

	/** Puts the icon on the normal or hurt frame for PlayState's current health. */
	public function syncFrameWithHealth():Void
	{
		if(animation == null || animation.curAnim == null) return;
		if(frames == null || frames.frames.length < 2) return;

		var ps:Dynamic = flixel.FlxG.state;
		if(ps == null) return;
		var hp:Dynamic = Reflect.getProperty(ps, 'health');
		if(hp == null) return;
		var health:Float = cast hp;
		// health runs 0..2 with 1 in the middle; the opponent looks hurt at high health
		// 0.6.3 rule: percent < 20 flips the player icon, > 80 flips the opponent's
		// (percent = health / 2 * 100, so <20% is health < 0.4 and >80% is health > 1.6)
		var losing:Bool = isPlayer ? (health < 0.4) : (health > 1.6);
		animation.curAnim.curFrame = losing ? 1 : 0;
	}

	public function getCharacter():String {
		return char;
	}
}
