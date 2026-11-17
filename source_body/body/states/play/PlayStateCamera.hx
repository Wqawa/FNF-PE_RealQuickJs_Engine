package states.play;

import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import objects.*;
import states.stages.*;
import states.stages.objects.*;
import psychlua.*;
import crowplexus.hscript.Expr.Error as IrisError;

/**
 * Camera and background follow (section camera moves, zoom tweens), moved out of PlayState.hx.
 * Copied line for line; member references became ps.xxx. Needs @:access, and PlayState
 * keeps same-named forwards so callers and overrides are unaffected.
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