package mobile;

// Button tables. Ports read these from DPadModes/*.json; apk assets can't be listed.
// Coordinates are for the 1280x720 canvas.
typedef ButtonLayout =
{
	button:String, // field name on TouchPad
	graphic:String, // file name in images/mobile/touchpad, lower case
	x:Float,
	y:Float,
	color:Int
}

class MobileLayouts
{
	public static function dpad(mode:String):Array<ButtonLayout>
	{
		return switch (mode)
		{
			case 'RIGHT_FULL': [
					{button: 'buttonUp', graphic: 'up', x: 1022, y: 314, color: 0xFF12FA05},
					{button: 'buttonLeft', graphic: 'left', x: 896, y: 413, color: 0xFFC24B99},
					{button: 'buttonRight', graphic: 'right', x: 1148, y: 413, color: 0xFFF9393F},
					{button: 'buttonDown', graphic: 'down', x: 1022, y: 521, color: 0xFF00FFFF}
				];
			case 'LEFT_FULL': [
					{button: 'buttonUp', graphic: 'up', x: 98, y: 405, color: 0xFF12FA05},
					{button: 'buttonLeft', graphic: 'left', x: 0, y: 500, color: 0xFFC24B99},
					{button: 'buttonRight', graphic: 'right', x: 196, y: 500, color: 0xFFF9393F},
					{button: 'buttonDown', graphic: 'down', x: 98, y: 596, color: 0xFF00FFFF}
				];
			case 'UP_DOWN': [
					{button: 'buttonUp', graphic: 'up', x: 0, y: 472, color: 0xFF12FA05},
					{button: 'buttonDown', graphic: 'down', x: 0, y: 596, color: 0xFF00FFFF}
				];
			case 'LEFT_RIGHT': [
					{button: 'buttonLeft', graphic: 'left', x: 0, y: 587, color: 0xFFC24B99},
					{button: 'buttonRight', graphic: 'right', x: 127, y: 587, color: 0xFFF9393F}
				];
			default: [];
		}
	}

	public static function action(mode:String):Array<ButtonLayout>
	{
		return switch (mode)
		{
			case 'A': [{button: 'buttonA', graphic: 'a', x: 1156, y: 596, color: 0xFF0000}];
			case 'B': [{button: 'buttonB', graphic: 'b', x: 1156, y: 596, color: 0xFFCB00}];
			case 'E': [{button: 'buttonE', graphic: 'e', x: 1156, y: 596, color: 0x44FF00}];
			case 'P': [{button: 'buttonP', graphic: 'p', x: 1156, y: 596, color: 0xFFFFFF}];
			case 'A_B': [
					{button: 'buttonA', graphic: 'a', x: 1156, y: 596, color: 0xFF0000},
					{button: 'buttonB', graphic: 'b', x: 1032, y: 596, color: 0xFFCB00}
				];
			// 颜色界面：B 退出，R 摆在方向键正中间用来重置
			case 'B_R': [
					{button: 'buttonB', graphic: 'b', x: 1032, y: 596, color: 0xFFCB00},
					{button: 'buttonR', graphic: 'r', x: 98, y: 500, color: 0xFFFFFFFF}
				];
			case 'B_C': [
					{button: 'buttonB', graphic: 'b', x: 1156, y: 596, color: 0xFFCB00},
					{button: 'buttonC', graphic: 'c', x: 1032, y: 596, color: 0x44FF00}
				];
			case 'A_B_C': [
					{button: 'buttonA', graphic: 'a', x: 1156, y: 596, color: 0xFF0000},
					{button: 'buttonB', graphic: 'b', x: 1032, y: 596, color: 0xFFCB00},
					{button: 'buttonC', graphic: 'c', x: 908, y: 596, color: 0x44FF00}
				];
			case 'A_B_E': [
					{button: 'buttonA', graphic: 'a', x: 1156, y: 596, color: 0xFF0000},
					{button: 'buttonB', graphic: 'b', x: 1032, y: 596, color: 0xFFCB00},
					{button: 'buttonE', graphic: 'e', x: 908, y: 596, color: 0x44FF00}
				];
			case 'A_B_X_Y': [
					{button: 'buttonA', graphic: 'a', x: 1156, y: 596, color: 0xFF0000},
					{button: 'buttonB', graphic: 'b', x: 1032, y: 596, color: 0xFFCB00},
					{button: 'buttonX', graphic: 'x', x: 908, y: 596, color: 0x99062D},
					{button: 'buttonY', graphic: 'y', x: 784, y: 596, color: 0x4A35B9}
				];
			default: [];
		}
	}
}
