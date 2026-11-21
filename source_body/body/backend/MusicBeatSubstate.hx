package backend;

import flixel.FlxSubState;
#if MOBILE_CONTROLS
import flixel.util.FlxDestroyUtil;
import mobile.input.MobileInputID;
import mobile.input.MobileInputManager;
import mobile.objects.TouchPad;
#end

class MusicBeatSubstate extends FlxSubState
{
	public function new()
	{
		super();
	}

	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;
	private var controls(get, never):Controls;

	inline function get_controls():Controls
		return Controls.instance;

	#if MOBILE_CONTROLS
	public var touchPad:TouchPad;
	public var addMenuPad:Bool = true;

	// 父菜单那个 pad。subState 只画自己的成员，父的 pad 留在下面又看不见，
	// 所以进来先把它藏掉，出去再放回来。
	var parentPad:MobileInputManager;

	/** 过场用的子状态（只有一层黑幕）把它设成 false：父界面的 pad 保持可见，
	 *  否则一进新界面会先冒出一套默认 pad，等过场结束才换成真正的布局。 */
	public var hideParentPad:Bool = true;

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
		// 父菜单的 pad 不会跟着 subState 画出来，所以这里自己挂一个，
		// 顺便把父的藏掉，免得它还在收触摸。
		parentPad = MobileInputManager.current;
		if(hideParentPad && parentPad != null && parentPad != touchPad)
			parentPad.visible = false;

		if(addMenuPad && touchPad == null && ClientPrefs.data.controlsAlpha > 0.05)
			addTouchPad('LEFT_FULL', 'A_B');
	}

	override function close():Void
	{
		// 记下关闭时间。子菜单里的 B 会继续传给父界面，父界面靠这个时间窗
		// 躲掉「一次按键被算两遍」，比只靠按键状态判断稳。
		MusicBeatState.lastSubstateClose = openfl.Lib.getTimer();
		super.close();
	}

	override function destroy():Void
	{
		removeTouchPad();
		if(hideParentPad && parentPad != null)
		{
			// 只放回自己藏掉的，免得给没藏过（过场）的情况乱设 visible
			parentPad.visible = true;
		}
		parentPad = null;
		super.destroy();
	}
	#end

	override function update(elapsed:Float)
	{
		//everyStep();
		if(!persistentUpdate) MusicBeatState.timePassedOnState += elapsed;
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

		var shit = ((Conductor.songPosition - ClientPrefs.data.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
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
	
	public function sectionHit():Void
	{
		//yep, you guessed it, nothing again, dumbass
	}
	
	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
}
