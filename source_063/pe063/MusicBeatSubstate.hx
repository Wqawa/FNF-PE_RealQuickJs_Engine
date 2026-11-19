package pe063;

import pe063.Conductor.BPMChangeEvent;
import flixel.FlxG;
import flixel.FlxSubState;
import flixel.FlxBasic;
import flixel.FlxSprite;
#if MOBILE_CONTROLS
import flixel.util.FlxDestroyUtil;
import pe063.mobile.input.MobileInputID;
import pe063.mobile.input.MobileInputManager;
import pe063.mobile.objects.TouchPad;
#end

class MusicBeatSubstate extends FlxSubState
{
	public function new()
	{
		super();
	}

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	#if MOBILE_CONTROLS
	public var touchPad:TouchPad;
	public var addMenuPad:Bool = true;

	public function addTouchPad(DPad:String, Action:String):TouchPad
	{
		removeTouchPad();
		touchPad = new TouchPad(DPad, Action);
		touchPad.cameras = [FlxG.camera];
		touchPad.register();
		add(touchPad);
		return touchPad;
	}

	public function removeTouchPad():Void
	{
		if(touchPad == null) return;
		touchPad.unregister();
		remove(touchPad, true);
		touchPad = FlxDestroyUtil.destroy(touchPad);
		touchPad = null;
	}

	override function create():Void
	{
		super.create();
		// an options menu already sits on a state that has a pad; don't stack two
		var current:MobileInputManager = MobileInputManager.current;
		if(addMenuPad && (current == null || !current.hasButton(MobileInputID.A)) && ClientPrefs.controlsAlpha > 0.05)
			addTouchPad('LEFT_FULL', 'A_B');
	}

	override function destroy():Void
	{
		removeTouchPad();
		super.destroy();
	}
	#end

	override function update(elapsed:Float)
	{
		//everyStep();
		var oldStep:Int = curStep;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep && curStep > 0)
			stepHit();


		super.update(elapsed);
	}

	private function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
		curDecBeat = curDecStep/4;
	}

	private function updateCurStep():Void
	{
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		//do literally nothing dumbass
	}
}
