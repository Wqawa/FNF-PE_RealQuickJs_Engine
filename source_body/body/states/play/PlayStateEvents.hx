package states.play;

import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import objects.Note.EventNote;
import objects.*;
import states.stages.*;
import states.stages.objects.*;
import psychlua.*;
import psychlua.LuaUtils;
import crowplexus.hscript.Expr.Error as IrisError;

/**
 * 从 PlayState.hx 搬出来的歌曲事件系统（事件预缓存、事件触发、事件判定）。逻辑是逐行原样搬的，只把对 PlayState 成员的引用改成 ps.xxx，
 * 需要私有访问所以加了 @:access。
 * PlayState 里保留了同名转发，外部调用和子类 override 都不受影响。
 */
@:access(states.PlayState)
@:access(backend.MusicBeatState)
class PlayStateEvents
{
	public static function eventPushed(ps:PlayState, event:EventNote) {
		ps.eventPushedUnique(event);
		if(ps.eventsPushed.contains(event.event)) {
			return;
		}

		ps.stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		ps.eventsPushed.push(event.event);
	}

	public static function eventPushedUnique(ps:PlayState, event:EventNote) {
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				ps.addCharacterToList(newCharacter, charType);

			case 'Play Sound':
				Paths.sound(event.value1); //Precache sound
		}
		ps.stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	public static function eventEarlyTrigger(ps:PlayState, event:EventNote):Float {
		var returnedValue:Null<Float> = ps.callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true);
		if(returnedValue != null && returnedValue != 0) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	public static function makeEvent(ps:PlayState, event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		ps.eventNotes.push(subEvent);
		ps.eventPushed(subEvent);
		ps.callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	public static function checkEventNote(ps:PlayState) {
		while(ps.eventNotes.length > 0) {
			var leStrumTime:Float = ps.eventNotes[0].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(ps.eventNotes[0].value1 != null)
				value1 = ps.eventNotes[0].value1;

			var value2:String = '';
			if(ps.eventNotes[0].value2 != null)
				value2 = ps.eventNotes[0].value2;

			ps.triggerEvent(ps.eventNotes[0].event, value1, value2, leStrumTime);
			ps.eventNotes.shift();
		}
	}

	public static function triggerEvent(ps:PlayState, eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(ps.dad.curCharacter.startsWith('gf')) { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						ps.dad.playAnim('cheer', true);
						ps.dad.specialAnim = true;
						ps.dad.heyTimer = flValue2;
					} else if (ps.gf != null) {
						ps.gf.playAnim('cheer', true);
						ps.gf.specialAnim = true;
						ps.gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					ps.boyfriend.playAnim('hey', true);
					ps.boyfriend.specialAnim = true;
					ps.boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				ps.gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if(ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					ps.camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = ps.dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = ps.boyfriend;
					case 'gf' | 'girlfriend':
						char = ps.gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = ps.boyfriend;
							case 2: char = ps.gf;
						}
				}

				if (char != null)
				{
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if(ps.camFollow != null)
				{
					ps.isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						ps.isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						ps.camFollow.x = flValue1;
						ps.camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = ps.dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = ps.gf;
					case 'boyfriend' | 'bf':
						char = ps.boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = ps.boyfriend;
							case 2: char = ps.gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [ps.camGame, ps.camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						if(ps.boyfriend.curCharacter != value2) {
							if(!ps.boyfriendMap.exists(value2)) {
								ps.addCharacterToList(value2, charType);
							}

							var lastAlpha:Float = ps.boyfriend.alpha;
							ps.boyfriend.alpha = 0.00001;
							ps.boyfriend = ps.boyfriendMap.get(value2);
							ps.boyfriend.alpha = lastAlpha;
							ps.iconP1.changeIcon(ps.boyfriend.healthIcon);
						}
						ps.setOnScripts('boyfriendName', ps.boyfriend.curCharacter);

					case 1:
						if(ps.dad.curCharacter != value2) {
							if(!ps.dadMap.exists(value2)) {
								ps.addCharacterToList(value2, charType);
							}

							var wasGf:Bool = ps.dad.curCharacter.startsWith('gf-') || ps.dad.curCharacter == 'gf';
							var lastAlpha:Float = ps.dad.alpha;
							ps.dad.alpha = 0.00001;
							ps.dad = ps.dadMap.get(value2);
							if(!ps.dad.curCharacter.startsWith('gf-') && ps.dad.curCharacter != 'gf') {
								if(wasGf && ps.gf != null) {
									ps.gf.visible = true;
								}
							} else if(ps.gf != null) {
								ps.gf.visible = false;
							}
							ps.dad.alpha = lastAlpha;
							ps.iconP2.changeIcon(ps.dad.healthIcon);
						}
						ps.setOnScripts('dadName', ps.dad.curCharacter);

					case 2:
						if(ps.gf != null)
						{
							if(ps.gf.curCharacter != value2)
							{
								if(!ps.gfMap.exists(value2)) {
									ps.addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = ps.gf.alpha;
								ps.gf.alpha = 0.00001;
								ps.gf = ps.gfMap.get(value2);
								ps.gf.alpha = lastAlpha;
							}
							ps.setOnScripts('gfName', ps.gf.curCharacter);
						}
				}
				ps.reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (ps.songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = PlayState.SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if(flValue2 <= 0)
						ps.songSpeed = newValue;
					else
						ps.songSpeedTween = FlxTween.tween(ps, {songSpeed: newValue}, flValue2 / ps.playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								ps.songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var trueValue:Dynamic = value2.trim();
					if (trueValue == 'true' || trueValue == 'false') trueValue = trueValue == 'true';
					else if (flValue2 != null) trueValue = flValue2;
					else trueValue = value2;

					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], trueValue);
					} else {
						LuaUtils.setVarInArray(ps, value1, trueValue);
					}
				}
				catch(e:Dynamic)
				{
					var len:Int = e.message.indexOf('\n') + 1;
					if(len <= 0) len = e.message.length;
					#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
					ps.addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, len), FlxColor.RED);
					#else
					FlxG.log.warn('ERROR ("Set Property" Event) - ' + e.message.substr(0, len));
					#end
				}

			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}

		ps.stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		ps.callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}
}