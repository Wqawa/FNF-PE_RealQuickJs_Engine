package states.play;

import backend.Rating;
import flixel.input.keyboard.FlxKey;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import objects.*;
import states.stages.*;
import states.stages.objects.*;
import psychlua.*;
import psychlua.LuaUtils;
import crowplexus.hscript.Expr.Error as IrisError;

/**
 * 从 PlayState.hx 搬出来的判定与输入（按键、命中、miss、评分弹字）。逻辑是逐行原样搬的，只把对 PlayState 成员的引用改成 ps.xxx，
 * 需要私有访问所以加了 @:access。
 * PlayState 里保留了同名转发，外部调用和子类 override 都不受影响。
 */
@:access(states.PlayState)
@:access(backend.MusicBeatState)
class PlayStateJudge
{
	public static function onKeyPress(ps:PlayState, event:KeyboardEvent):Void
	{

		var eventKey:FlxKey = event.keyCode;
		var key:Int = PlayState.getKeyFromEvent(ps.keysArray, eventKey);

		if (!ps.controls.controllerMode)
		{
			#if debug
			//Prevents crash specifically on debug without needing to try catch shit
			@:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey)) return;
			#end

			if(FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) ps.keyPressed(key);
		}
	}

	public static function keyPressed(ps:PlayState, key:Int)
	{
		if(ps.cpuControlled || ps.paused || ps.inCutscene || key < 0 || key >= ps.playerStrums.length || !ps.generatedMusic || ps.endingSong || ps.boyfriend.stunned) return;

		var ret:Dynamic = ps.callOnScripts('onKeyPressPre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		// more accurate hit time for the ratings?
		var lastTime:Float = Conductor.songPosition;
		if(Conductor.songPosition >= 0) Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		// obtain notes that the player can hit
		var plrInputNotes:Array<Note> = ps.notes.members.filter(function(n:Note):Bool {
			var canHit:Bool = n != null && !ps.strumsBlocked[n.noteData] && n.canBeHit && n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit;
			return canHit && !n.isSustainNote && n.noteData == key;
		});
		plrInputNotes.sort(PlayState.sortHitNotes);

		if (plrInputNotes.length != 0) { // slightly faster than doing `> 0` lol
			var funnyNote:Note = plrInputNotes[0]; // front note

			if (plrInputNotes.length > 1) {
				var doubleNote:Note = plrInputNotes[1];

				if (doubleNote.noteData == funnyNote.noteData) {
					// if the note has a 0ms distance (is on top of the current note), kill it
					if (Math.abs(doubleNote.strumTime - funnyNote.strumTime) < 1.0)
						ps.invalidateNote(doubleNote);
					else if (doubleNote.strumTime < funnyNote.strumTime)
					{
						// replace the note if its ahead of time (or at least ensure "doubleNote" is ahead)
						funnyNote = doubleNote;
					}
				}
			}
			ps.goodNoteHit(funnyNote);
		}
		else
		{
			if (ClientPrefs.data.ghostTapping)
				ps.callOnScripts('onGhostTap', [key]);
			else
				ps.noteMissPress(key);
		}

		// Needed for the  "Just the Two of Us" achievement.
		//									- Shadow Mario
		if(!ps.keysPressed.contains(key)) ps.keysPressed.push(key);

		//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
		Conductor.songPosition = lastTime;

		var spr:StrumNote = ps.playerStrums.members[key];
		if(ps.strumsBlocked[key] != true && spr != null && spr.animation.curAnim.name != 'confirm')
		{
			spr.playAnim('pressed');
			spr.resetAnim = 0;
		}
		ps.callOnScripts('onKeyPress', [key]);
	}

	public static function onKeyRelease(ps:PlayState, event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = PlayState.getKeyFromEvent(ps.keysArray, eventKey);
		if(!ps.controls.controllerMode && key > -1) ps.keyReleased(key);
	}

	public static function keyReleased(ps:PlayState, key:Int)
	{
		if(ps.cpuControlled || !ps.startedCountdown || ps.paused || key < 0 || key >= ps.playerStrums.length) return;

		var ret:Dynamic = ps.callOnScripts('onKeyReleasePre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		var spr:StrumNote = ps.playerStrums.members[key];
		if(spr != null)
		{
			spr.playAnim('static');
			spr.resetAnim = 0;
		}
		ps.callOnScripts('onKeyRelease', [key]);
	}

	public static function keysCheck(ps:PlayState):Void
	{
		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		for (key in ps.keysArray)
		{
			holdArray.push(ps.controls.pressed(key));
			pressArray.push(ps.controls.justPressed(key));
			releaseArray.push(ps.controls.justReleased(key));
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(ps.controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && ps.strumsBlocked[i] != true)
					ps.keyPressed(i);

		if (ps.startedCountdown && !ps.inCutscene && !ps.boyfriend.stunned && ps.generatedMusic)
		{
			if (ps.notes.length > 0) {
				for (n in ps.notes) { // I can't do a filter here, that's kinda awesome
					var canHit:Bool = (n != null && !ps.strumsBlocked[n.noteData] && n.canBeHit
						&& n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit);

					if (ps.guitarHeroSustains)
						canHit = canHit && n.parent != null && n.parent.wasGoodHit;

					if (canHit && n.isSustainNote) {
						var released:Bool = !holdArray[n.noteData];

						if (!released)
							ps.goodNoteHit(n);
					}
				}
			}

			if (!holdArray.contains(true) || ps.endingSong)
				ps.playerDance();

			#if ACHIEVEMENTS_ALLOWED
			else ps.checkForAchievement(['oversinging']);
			#end
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((ps.controls.controllerMode || ps.strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || ps.strumsBlocked[i] == true)
					ps.keyReleased(i);
	}

	public static function noteMiss(ps:PlayState, daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		//Dupe note remove
		ps.notes.forEachAlive(function(note:Note) {
			if (daNote != note && daNote.mustPress && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 1)
				ps.invalidateNote(note);
		});

		ps.noteMissCommon(daNote.noteData, daNote);
		ps.stagesFunc(function(stage:BaseStage) stage.noteMiss(daNote));
		var result:Dynamic = ps.callOnLuas('noteMiss', [ps.notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) ps.callOnHScript('noteMiss', [daNote]);
	}

	public static function noteMissPress(ps:PlayState, direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		if(ClientPrefs.data.ghostTapping) return; //fuck it

		ps.noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		ps.stagesFunc(function(stage:BaseStage) stage.noteMissPress(direction));
		ps.callOnScripts('noteMissPress', [direction]);
	}

	public static function noteMissCommon(ps:PlayState, direction:Int, note:Note = null)
	{
		// score and data
		var subtract:Float = ps.pressMissDamage;
		if(note != null) subtract = note.missHealth;

		// GUITAR HERO SUSTAIN CHECK LOL!!!!
		if (note != null && ps.guitarHeroSustains && note.parent == null) {
			if(note.tail.length > 0) {
				note.alpha = 0.35;
				for(childNote in note.tail) {
					childNote.alpha = note.alpha;
					childNote.missed = true;
					childNote.canBeHit = false;
					childNote.ignoreNote = true;
					childNote.tooLate = true;
				}
				note.missed = true;
				note.canBeHit = false;

				//subtract += 0.385; // you take more damage if playing with this gameplay changer enabled.
				// i mean its fair :p -Crow
				subtract *= note.tail.length + 1;
				// i think it would be fair if damage multiplied based on how long the sustain is -[REDACTED]
			}

			if (note.missed)
				return;
		}
		if (note != null && ps.guitarHeroSustains && note.parent != null && note.isSustainNote) {
			if (note.missed)
				return;

			var parentNote:Note = note.parent;
			if (parentNote.wasGoodHit && parentNote.tail.length > 0) {
				for (child in parentNote.tail) if (child != note) {
					child.missed = true;
					child.canBeHit = false;
					child.ignoreNote = true;
					child.tooLate = true;
				}
			}
		}

		if(ps.instakillOnMiss)
		{
			ps.vocals.volume = 0;
			ps.opponentVocals.volume = 0;
			ps.doDeathCheck(true);
		}

		var lastCombo:Int = ps.combo;
		ps.combo = 0;

		ps.health -= subtract * ps.healthLoss;
		ps.songScore -= 10;
		if(!ps.endingSong) ps.songMisses++;
		ps.totalPlayed++;
		ps.RecalculateRating(true);

		// play character anims
		var char:Character = ps.boyfriend;
		if((note != null && note.gfNote) || (PlayState.SONG.notes[ps.curSection] != null && PlayState.SONG.notes[ps.curSection].gfSection)) char = ps.gf;

		if(char != null && (note == null || !note.noMissAnimation) && char.hasMissAnimations)
		{
			var postfix:String = '';
			if(note != null) postfix = note.animSuffix;

			var animToPlay:String = ps.singAnimations[Std.int(Math.abs(Math.min(ps.singAnimations.length-1, direction)))] + 'miss' + postfix;
			char.playAnim(animToPlay, true);

			if(char != ps.gf && lastCombo > 5 && ps.gf != null && ps.gf.hasAnimation('sad'))
			{
				ps.gf.playAnim('sad');
				ps.gf.specialAnim = true;
			}
		}
		ps.vocals.volume = 0;
	}

	public static function opponentNoteHit(ps:PlayState, note:Note):Void
	{
		var result:Dynamic = ps.callOnLuas('opponentNoteHitPre', [ps.notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) result = ps.callOnHScript('opponentNoteHitPre', [note]);

		if(result == LuaUtils.Function_Stop) return;

		if (ps.songName != 'tutorial')
			ps.camZooming = true;

		if(note.noteType == 'Hey!' && ps.dad.hasAnimation('hey'))
		{
			ps.dad.playAnim('hey', true);
			ps.dad.specialAnim = true;
			ps.dad.heyTimer = 0.6;
		}
		else if(!note.noAnimation)
		{
			var char:Character = ps.dad;
			var animToPlay:String = ps.singAnimations[Std.int(Math.abs(Math.min(ps.singAnimations.length-1, note.noteData)))] + note.animSuffix;
			if(note.gfNote) char = ps.gf;

			if(char != null)
			{
				var canPlay:Bool = true;
				if(note.isSustainNote)
				{
					var holdAnim:String = animToPlay + '-hold';
					if(char.animation.exists(holdAnim)) animToPlay = holdAnim;
					if(char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop') canPlay = false;
				}

				if(canPlay) char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if(ps.opponentVocals.length <= 0) ps.vocals.volume = 1;
		ps.strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / ps.playbackRate);
		note.hitByOpponent = true;
		
		ps.stagesFunc(function(stage:BaseStage) stage.opponentNoteHit(note));
		var result:Dynamic = ps.callOnLuas('opponentNoteHit', [ps.notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) ps.callOnHScript('opponentNoteHit', [note]);

		if (!note.isSustainNote) ps.invalidateNote(note);
	}

	public static function goodNoteHit(ps:PlayState, note:Note):Void
	{
		if(note.wasGoodHit) return;
		if(ps.cpuControlled && note.ignoreNote) return;

		var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
		var leData:Int = Math.round(Math.abs(note.noteData));
		var leType:String = note.noteType;

		var result:Dynamic = ps.callOnLuas('goodNoteHitPre', [ps.notes.members.indexOf(note), leData, leType, isSus]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) result = ps.callOnHScript('goodNoteHitPre', [note]);

		if(result == LuaUtils.Function_Stop) return;

		note.wasGoodHit = true;

		if (note.hitsoundVolume > 0 && !note.hitsoundDisabled)
			FlxG.sound.play(Paths.sound(note.hitsound), note.hitsoundVolume);

		if(!note.hitCausesMiss) //Common notes
		{
			if(!note.noAnimation)
			{
				var animToPlay:String = ps.singAnimations[Std.int(Math.abs(Math.min(ps.singAnimations.length-1, note.noteData)))] + note.animSuffix;

				var char:Character = ps.boyfriend;
				var animCheck:String = 'hey';
				if(note.gfNote)
				{
					char = ps.gf;
					animCheck = 'cheer';
				}

				if(char != null)
				{
					var canPlay:Bool = true;
					if(note.isSustainNote)
					{
						var holdAnim:String = animToPlay + '-hold';
						if(char.animation.exists(holdAnim)) animToPlay = holdAnim;
						if(char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop') canPlay = false;
					}
	
					if(canPlay) char.playAnim(animToPlay, true);
					char.holdTimer = 0;

					if(note.noteType == 'Hey!')
					{
						if(char.hasAnimation(animCheck))
						{
							char.playAnim(animCheck, true);
							char.specialAnim = true;
							char.heyTimer = 0.6;
						}
					}
				}
			}

			if(!ps.cpuControlled)
			{
				var spr = ps.playerStrums.members[note.noteData];
				if(spr != null) spr.playAnim('confirm', true);
			}
			else ps.strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / ps.playbackRate);
			ps.vocals.volume = 1;

			if (!note.isSustainNote)
			{
				ps.combo++;
				if(ps.combo > 9999) ps.combo = 9999;
				ps.popUpScore(note);
			}
			var gainHealth:Bool = true; // prevent health gain, *if* sustains are treated as a singular note
			if (ps.guitarHeroSustains && note.isSustainNote) gainHealth = false;
			if (gainHealth)
			{
				// 0.6.3 每次命中固定回 0.023；1.0.4 按音符 hitHealth * healthGain 算，量小很多
				if (ClientPrefs.data.compatLegacyHealth) ps.health += 0.023;
				else ps.health += note.hitHealth * ps.healthGain;
			}

		}
		else //Notes that count as a miss if you hit them (Hurt notes for example)
		{
			if(!note.noMissAnimation)
			{
				switch(note.noteType)
				{
					case 'Hurt Note':
						if(ps.boyfriend.hasAnimation('hurt'))
						{
							ps.boyfriend.playAnim('hurt', true);
							ps.boyfriend.specialAnim = true;
						}
				}
			}

			ps.noteMiss(note);
			if(!note.noteSplashData.disabled && !note.isSustainNote) ps.spawnNoteSplashOnNote(note);
		}

		ps.stagesFunc(function(stage:BaseStage) stage.goodNoteHit(note));
		var result:Dynamic = ps.callOnLuas('goodNoteHit', [ps.notes.members.indexOf(note), leData, leType, isSus]);
		if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) ps.callOnHScript('goodNoteHit', [note]);
		if(!note.isSustainNote) ps.invalidateNote(note);
	}

	public static function invalidateNote(ps:PlayState, note:Note):Void {
		note.kill();
		ps.notes.remove(note, true);
		note.destroy();
	}

	public static function spawnNoteSplashOnNote(ps:PlayState, note:Note) {
		if(note != null) {
			var strum:StrumNote = ps.playerStrums.members[note.noteData];
			if(strum != null)
				ps.spawnNoteSplash(strum.x, strum.y, note.noteData, note, strum);
		}
	}

	public static function spawnNoteSplash(ps:PlayState, x:Float = 0, y:Float = 0, ?data:Int = 0, ?note:Note, ?strum:StrumNote) {
		var splash:NoteSplash = ps.grpNoteSplashes.recycle(NoteSplash);
		splash.babyArrow = strum;
		splash.spawnSplashNote(x, y, data, note);
		ps.grpNoteSplashes.add(splash);
	}

	public static function cachePopUpScore(ps:PlayState)
	{
		var uiFolder:String = "";
		if (PlayState.stageUI != "normal")
			uiFolder = PlayState.uiPrefix + "UI/";

		for (rating in ps.ratingsData)
			Paths.image(uiFolder + rating.image + PlayState.uiPostfix);
		for (i in 0...10)
			Paths.image(uiFolder + 'num' + i + PlayState.uiPostfix);
	}

	public static function popUpScore(ps:PlayState, note:Note = null):Void
	{
		var noteDiff:Float = Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset);
		ps.vocals.volume = 1;

		if (!ClientPrefs.data.comboStacking && ps.comboGroup.members.length > 0)
		{
			for (spr in ps.comboGroup)
			{
				if(spr == null) continue;

				ps.comboGroup.remove(spr);
				spr.destroy();
			}
		}

		var placement:Float = FlxG.width * 0.35;
		var rating:FlxSprite = new FlxSprite();
		var score:Int = 350;

		//tryna do MS based judgment due to popular demand
		var daRating:Rating = Conductor.judgeNote(ps.ratingsData, noteDiff / ps.playbackRate);

		ps.totalNotesHit += daRating.ratingMod;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;
		score = daRating.score;

		if(daRating.noteSplash && !note.noteSplashData.disabled)
			ps.spawnNoteSplashOnNote(note);

		if(!ps.cpuControlled) {
			ps.songScore += score;
			if(!note.ratingDisabled)
			{
				ps.songHits++;
				ps.totalPlayed++;
				ps.RecalculateRating(false);
			}
		}

		var uiFolder:String = "";
		var antialias:Bool = ClientPrefs.data.antialiasing;
		if (PlayState.stageUI != "normal")
		{
			uiFolder = PlayState.uiPrefix + "UI/";
			antialias = !PlayState.isPixelStage;
		}

		rating.loadGraphic(Paths.image(uiFolder + daRating.image + PlayState.uiPostfix));
		rating.screenCenter();
		rating.x = placement - 40;
		rating.y -= 60;
		rating.acceleration.y = 550 * ps.playbackRate * ps.playbackRate;
		rating.velocity.y -= FlxG.random.int(140, 175) * ps.playbackRate;
		rating.velocity.x -= FlxG.random.int(0, 10) * ps.playbackRate;
		rating.visible = (!ClientPrefs.data.hideHud && ps.showRating);
		rating.x += ClientPrefs.data.comboOffset[0];
		rating.y -= ClientPrefs.data.comboOffset[1];
		rating.antialiasing = antialias;

		var comboSpr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiFolder + 'combo' + PlayState.uiPostfix));
		comboSpr.screenCenter();
		comboSpr.x = placement;
		comboSpr.acceleration.y = FlxG.random.int(200, 300) * ps.playbackRate * ps.playbackRate;
		comboSpr.velocity.y -= FlxG.random.int(140, 160) * ps.playbackRate;
		comboSpr.visible = (!ClientPrefs.data.hideHud && ps.showCombo);
		comboSpr.x += ClientPrefs.data.comboOffset[0];
		comboSpr.y -= ClientPrefs.data.comboOffset[1];
		comboSpr.antialiasing = antialias;
		comboSpr.y += 60;
		comboSpr.velocity.x += FlxG.random.int(1, 10) * ps.playbackRate;
		ps.comboGroup.add(rating);

		if (!PlayState.isPixelStage)
		{
			rating.setGraphicSize(Std.int(rating.width * 0.7));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
		}
		else
		{
			rating.setGraphicSize(Std.int(rating.width * PlayState.daPixelZoom * 0.85));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * PlayState.daPixelZoom * 0.85));
		}

		comboSpr.updateHitbox();
		rating.updateHitbox();

		var daLoop:Int = 0;
		var xThing:Float = 0;
		if (ps.showCombo)
			ps.comboGroup.add(comboSpr);

		var separatedScore:String = Std.string(ps.combo).lpad('0', 3);
		for (i in 0...separatedScore.length)
		{
			var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiFolder + 'num' + Std.parseInt(separatedScore.charAt(i)) + PlayState.uiPostfix));
			numScore.screenCenter();
			numScore.x = placement + (43 * daLoop) - 90 + ClientPrefs.data.comboOffset[2];
			numScore.y += 80 - ClientPrefs.data.comboOffset[3];

			if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
			else numScore.setGraphicSize(Std.int(numScore.width * PlayState.daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = FlxG.random.int(200, 300) * ps.playbackRate * ps.playbackRate;
			numScore.velocity.y -= FlxG.random.int(140, 160) * ps.playbackRate;
			numScore.velocity.x = FlxG.random.float(-5, 5) * ps.playbackRate;
			numScore.visible = !ClientPrefs.data.hideHud;
			numScore.antialiasing = antialias;

			//if (combo >= 10 || combo == 0)
			if(ps.showComboNum)
				ps.comboGroup.add(numScore);

			FlxTween.tween(numScore, {alpha: 0}, 0.2 / ps.playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					numScore.destroy();
				},
				startDelay: Conductor.crochet * 0.002 / ps.playbackRate
			});

			daLoop++;
			if(numScore.x > xThing) xThing = numScore.x;
		}
		comboSpr.x = xThing + 50;
		FlxTween.tween(rating, {alpha: 0}, 0.2 / ps.playbackRate, {
			startDelay: Conductor.crochet * 0.001 / ps.playbackRate
		});

		FlxTween.tween(comboSpr, {alpha: 0}, 0.2 / ps.playbackRate, {
			onComplete: function(tween:FlxTween)
			{
				comboSpr.destroy();
				rating.destroy();
			},
			startDelay: Conductor.crochet * 0.002 / ps.playbackRate
		});
	}
}