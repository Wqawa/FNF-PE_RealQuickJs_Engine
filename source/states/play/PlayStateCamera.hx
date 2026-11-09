package states.play;

import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.Rating;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import haxe.Json;
import cutscenes.DialogueBoxPsych;
import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;
import substates.PauseSubState;
import substates.GameOverSubstate;
import openfl.filters.ShaderFilter;
import shaders.ErrorHandledShader;
import objects.VideoSprite;
import objects.Note.EventNote;
import objects.*;
import states.stages.*;
import states.stages.objects.*;
import psychlua.*;
import psychlua.LuaUtils;
import psychlua.HScript;
import psychlua.HScript.HScriptInfos;
import crowplexus.iris.Iris;
import crowplexus.hscript.Expr.Error as IrisError;
import crowplexus.hscript.Printer;

/**
 * 从 PlayState.hx 搬出来的镜头与背景跟随（段落切镜头、tween 拉近）。逻辑是逐行原样搬的，只把对 PlayState 成员的引用改成 ps.xxx，
 * 需要私有访问所以加了 @:access。
 * PlayState 里保留了同名转发，外部调用和子类 override 都不受影响。
 */
@:access(states.PlayState)
@:access(backend.MusicBeatState)
class PlayStateCamera
{
	public static function moveCameraSection(ps:PlayState, ?sec:Null<Int>):Void {
		if(sec == null) sec = ps.curSection;
		if(sec < 0) sec = 0;

		if(PlayState.SONG.notes[sec] == null) return;

		if (ps.gf != null && PlayState.SONG.notes[sec].gfSection)
		{
			ps.moveCameraToGirlfriend();
			ps.callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		var isDad:Bool = (PlayState.SONG.notes[sec].mustHitSection != true);
		ps.moveCamera(isDad);
		if (isDad)
			ps.callOnScripts('onMoveCamera', ['dad']);
		else
			ps.callOnScripts('onMoveCamera', ['boyfriend']);
	}

	public static function moveCameraToGirlfriend(ps:PlayState)
	{
		ps.camFollow.setPosition(ps.gf.getMidpoint().x, ps.gf.getMidpoint().y);
		ps.camFollow.x += ps.gf.cameraPosition[0] + ps.girlfriendCameraOffset[0];
		ps.camFollow.y += ps.gf.cameraPosition[1] + ps.girlfriendCameraOffset[1];
		ps.tweenCamIn();
	}

	public static function moveCamera(ps:PlayState, isDad:Bool)
	{
		if(isDad)
		{
			if(ps.dad == null) return;
			ps.camFollow.setPosition(ps.dad.getMidpoint().x + 150, ps.dad.getMidpoint().y - 100);
			ps.camFollow.x += ps.dad.cameraPosition[0] + ps.opponentCameraOffset[0];
			ps.camFollow.y += ps.dad.cameraPosition[1] + ps.opponentCameraOffset[1];
			ps.tweenCamIn();
		}
		else
		{
			if(ps.boyfriend == null) return;
			ps.camFollow.setPosition(ps.boyfriend.getMidpoint().x - 100, ps.boyfriend.getMidpoint().y - 100);
			ps.camFollow.x -= ps.boyfriend.cameraPosition[0] - ps.boyfriendCameraOffset[0];
			ps.camFollow.y += ps.boyfriend.cameraPosition[1] + ps.boyfriendCameraOffset[1];

			if (ps.songName == 'tutorial' && ps.cameraTwn == null && FlxG.camera.zoom != 1)
			{
				ps.cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						ps.cameraTwn = null;
					}
				});
			}
		}
	}

	public static function tweenCamIn(ps:PlayState) {
		if (ps.songName == 'tutorial' && ps.cameraTwn == null && FlxG.camera.zoom != 1.3) {
			ps.cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					ps.cameraTwn = null;
				}
			});
		}
	}
}
