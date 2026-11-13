#if !macro
//Discord API
#if DISCORD_ALLOWED
import vanilla.backend.Discord;
#end

//Psych
#if LUA_ALLOWED
import llua.*;
import llua.Lua;
#end

#if ACHIEVEMENTS_ALLOWED
import vanilla.backend.Achievements;
#end

#if sys
import sys.*;
import sys.io.*;
#elseif js
import js.html.*;
#end
import vanilla.backend.Paths;
import vanilla.backend.Controls;
import vanilla.backend.CoolUtil;
import vanilla.backend.MusicBeatState;
import vanilla.backend.MusicBeatSubstate;
import vanilla.backend.CustomFadeTransition;
import vanilla.backend.ClientPrefs;
import vanilla.backend.Conductor;
import vanilla.backend.BaseStage;
import vanilla.backend.Difficulty;
import vanilla.backend.Mods;
import vanilla.backend.Language;
import vanilla.backend.ui.*; //Psych-UI
import vanilla.objects.Alphabet;
import vanilla.objects.BGSprite;
import vanilla.states.PlayState;
import vanilla.states.LoadingState;

#if flxanimate
import flxanimate.*;
import vanilla.flxanimate.PsychFlxAnimate as FlxAnimate;
#end

//Flixel
import flixel.sound.FlxSound;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.addons.transition.FlxTransitionableState;

using StringTools;
#end
