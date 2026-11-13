package backend;

import flixel.FlxG;
import flixel.system.scaleModes.BaseScaleMode;

/**
 * 让 flixel 内部几何全部按 1:1 算，整体缩放交给 openfl 的 stage（SHOW_ALL）。
 *
 * 原版 RatioScaleMode 会把窗口/画布的比例写进 `scaleMode.scale`，而 FlxCamera 的
 * updateScrollRect() / updateInternalSpritePositions() 都拿这个值去算自己的
 * scrollRect 和 canvas.scaleX —— 也就是每个 camera 各自缩放一份。
 * camera 一旦挂了 ShaderFilter，openfl 就要为每个 camera 单独开离屏 buffer，
 * 各自的边界取整差一个像素，放大后就表现为画面和 HUD 错开。
 *
 * 这里把 scale 恒定为 1，camera 的 flashSprite / scrollRect / canvas 就都是整数像素，
 * filter buffer 也精确等于 1280x720，取整差异消失。窗口比画布大的部分由 openfl
 * 一次性缩放整张 stage，不会破坏 camera 之间的相对位置。
 *
 * 鼠标坐标不受影响：stage 自己缩放时 openfl 会把 mouseX 换算回逻辑坐标，
 * flixel 再除以 scale(=1) 就是对的。
 */
@:access(flixel.system.scaleModes.BaseScaleMode)
@:access(flixel.FlxG)
class NativeScaleMode extends BaseScaleMode
{
	public function new()
	{
		super();
	}

	override public function onMeasure(Width:Int, Height:Int):Void
	{
		FlxG.width = FlxG.initialWidth;
		FlxG.height = FlxG.initialHeight;

		gameSize.set(FlxG.width, FlxG.height);
		deviceSize.set(Width, Height);
		scale.set(1, 1);
		offset.set(0, 0);

		if (FlxG.game != null)
		{
			FlxG.game.x = 0;
			FlxG.game.y = 0;
			FlxG.game.scaleX = 1;
			FlxG.game.scaleY = 1;
		}
	}
}
