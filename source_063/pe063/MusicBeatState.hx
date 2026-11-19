package pe063;

import pe063.Conductor.BPMChangeEvent;
import flixel.FlxG;
import flixel.addons.ui.FlxUIState;
import flixel.math.FlxRect;
import flixel.util.FlxTimer;
import flixel.addons.transition.FlxTransitionableState;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.util.FlxGradient;
import flixel.FlxState;
import flixel.FlxCamera;
import flixel.FlxBasic;

#if MOBILE_CONTROLS
import flixel.util.FlxDestroyUtil;
import pe063.mobile.MobileData;
import pe063.mobile.input.MobileInputManager;
import pe063.mobile.objects.Hitbox;
import pe063.mobile.objects.TouchPad;
#end

class MusicBeatState extends FlxUIState
{
	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	private var controls(get, never):Controls;

	public static var camBeat:FlxCamera;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	#if MOBILE_CONTROLS
	public var touchPad:TouchPad;
	public var mobileControls:MobileInputManager;

	/** Set to false before super.create() to skip the default menu pad. */
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

	public function addMobileControls():MobileInputManager
	{
		removeMobileControls();

		var custom:Bool = ClientPrefs.controlsMode == 'Custom';
		mobileControls = switch(ClientPrefs.controlsMode)
		{
			case 'Left': new TouchPad('LEFT_FULL', 'NONE');
			case 'Hitbox': new Hitbox();
			default: new TouchPad('RIGHT_FULL', 'NONE');
		}
		// 'Custom' is the right-hand pad with the buttons where the editor left them
		if (custom)
			MobileData.applyPositions(cast mobileControls);

		mobileControls.cameras = [FlxG.camera];
		mobileControls.register();
		add(mobileControls);
		mobileControls.visible = false;
		return mobileControls;
	}

	public function removeMobileControls():Void
	{
		if(mobileControls == null) return;
		mobileControls.unregister();
		remove(mobileControls, true);
		mobileControls = FlxDestroyUtil.destroy(mobileControls);
		mobileControls = null;
	}
	#end

	override function create() {
		camBeat = FlxG.camera;
		var skip:Bool = FlxTransitionableState.skipNextTransOut;
		super.create();

		#if MOBILE_CONTROLS
		if(addMenuPad && touchPad == null && mobileControls == null && ClientPrefs.controlsAlpha > 0.05)
			addTouchPad('LEFT_FULL', 'A_B');
		#end

		if(!skip) {
			openSubState(new CustomFadeTransition(0.7, true));
		}
		FlxTransitionableState.skipNextTransOut = false;
	}

	override function update(elapsed:Float)
	{
		//everyStep();
		var oldStep:Int = curStep;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep)
		{
			if(curStep > 0)
				stepHit();

			if(PlayState.SONG != null)
			{
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		if(FlxG.save.data != null) FlxG.save.data.fullscreen = FlxG.fullscreen;

		super.update(elapsed);
	}

	private function updateSection():Void
	{
		if(stepsToDo < 1) stepsToDo = Math.round(getBeatsOnSection() * 4);
		while(curStep >= stepsToDo)
		{
			curSection++;
			var beats:Float = getBeatsOnSection();
			stepsToDo += Math.round(beats * 4);
			sectionHit();
		}
	}

	private function rollbackSection():Void
	{
		if(curStep < 0) return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		for (i in 0...PlayState.SONG.notes.length)
		{
			if (PlayState.SONG.notes[i] != null)
			{
				stepsToDo += Math.round(getBeatsOnSection() * 4);
				if(stepsToDo > curStep) break;
				
				curSection++;
			}
		}

		if(curSection > lastSection) sectionHit();
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

	public static function switchState(nextState:FlxState) {
		// Custom made Trans in
		var curState:Dynamic = FlxG.state;
		var leState:MusicBeatState = curState;
		if(!FlxTransitionableState.skipNextTransIn) {
			leState.openSubState(new CustomFadeTransition(0.6, false));
			if(nextState == FlxG.state) {
				CustomFadeTransition.finishCallback = function() {
					FlxG.resetState();
				};
				//trace('resetted');
			} else {
				CustomFadeTransition.finishCallback = function() {
					FlxG.switchState(nextState);
				};
				//trace('changed state');
			}
			return;
		}
		FlxTransitionableState.skipNextTransIn = false;
		FlxG.switchState(nextState);
	}

	public static function resetState() {
		MusicBeatState.switchState(FlxG.state);
	}

	/**
	 * Use this to switch states from inside a substate.
	 *
	 * flixel 5's switchState destroys the current state while the substate is still in its
	 * update, throwing "Attempting to resetState while the current state is destroyed".
	 * 0.6.3's flixel had no such guard, so the original code switches directly everywhere.
	 * Fix: close the substate first, switch next frame.
	 */
	public static function safeSwitch(?next:FlxState):Void
	{
		var cur:Dynamic = FlxG.state;
		if (cur != null && Reflect.getProperty(cur, 'subState') != null)
		{
			try { cur.closeSubState(); } catch (e:Dynamic) {}
		}

		new FlxTimer().start(0.01, function(_) {
			if (next == null) resetState();
			else switchState(next);
		});
	}

	public static function getState():MusicBeatState {
		var curState:Dynamic = FlxG.state;
		var leState:MusicBeatState = curState;
		return leState;
	}

	public function stepHit():Void
	{
		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		//trace('Beat: ' + curBeat);
	}

	public function sectionHit():Void
	{
		//trace('Section: ' + curSection + ', Beat: ' + curBeat + ', Step: ' + curStep);
	}

	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
}
