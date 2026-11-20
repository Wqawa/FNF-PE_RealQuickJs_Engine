package mobile.input;

// Virtual button IDs (MIT port). Plain ints, no macro lookup.
enum abstract MobileInputID(Int) from Int to Int
{
	var ANY = -2;
	var NONE = -1;

	// notes, same order as noteData
	var NOTE_LEFT = 0;
	var NOTE_DOWN = 1;
	var NOTE_UP = 2;
	var NOTE_RIGHT = 3;

	// touchpad letters: A=4 .. Z=29
	var A = 4;
	var B = 5;
	var C = 6;
	var D = 7;
	var E = 8;
	var F = 9;
	var G = 10;
	var H = 11;
	var I = 12;
	var J = 13;
	var K = 14;
	var L = 15;
	var M = 16;
	var N = 17;
	var O = 18;
	var P = 19;
	var Q = 20;
	var R = 21;
	var S = 22;
	var T = 23;
	var U = 24;
	var V = 25;
	var W = 26;
	var X = 27;
	var Y = 28;
	var Z = 29;

	// directional pads that are not notes (menus, editors)
	var UP = 30;
	var DOWN = 31;
	var LEFT = 32;
	var RIGHT = 33;

	// hitbox lanes report their own IDs so a hint can carry NOTE_* as well
	// without the manager picking the wrong one
	var HITBOX_LEFT = 34;
	var HITBOX_DOWN = 35;
	var HITBOX_UP = 36;
	var HITBOX_RIGHT = 37;

	var EXTRA_1 = 38;
	var EXTRA_2 = 39;

	static inline var FIRST_LETTER:Int = 4;
	static inline var LAST_LETTER:Int = 29;
	static inline var LETTER_A_CODE:Int = 65;

	@:from
	public static function fromString(s:String):MobileInputID
	{
		if (s == null || s.length == 0) return NONE;

		var up:String = s.toUpperCase();
		if (up.length == 1)
		{
			var code:Int = up.charCodeAt(0);
			if (code >= LETTER_A_CODE && code <= LETTER_A_CODE + (LAST_LETTER - FIRST_LETTER))
				return cast (FIRST_LETTER + code - LETTER_A_CODE);
		}

		return switch (up)
		{
			case 'NOTE_LEFT': NOTE_LEFT;
			case 'NOTE_DOWN': NOTE_DOWN;
			case 'NOTE_UP': NOTE_UP;
			case 'NOTE_RIGHT': NOTE_RIGHT;
			case 'UP': UP;
			case 'DOWN': DOWN;
			case 'LEFT': LEFT;
			case 'RIGHT': RIGHT;
			case 'HITBOX_UP': HITBOX_UP;
			case 'HITBOX_DOWN': HITBOX_DOWN;
			case 'HITBOX_LEFT': HITBOX_LEFT;
			case 'HITBOX_RIGHT': HITBOX_RIGHT;
			case 'EXTRA_1': EXTRA_1;
			case 'EXTRA_2': EXTRA_2;
			case 'ANY': ANY;
			default: NONE;
		}
	}

	public function toString():String
	{
		var i:Int = this;
		if (i >= FIRST_LETTER && i <= LAST_LETTER)
			return String.fromCharCode(LETTER_A_CODE + i - FIRST_LETTER);

		if (i == NOTE_LEFT) return 'NOTE_LEFT';
		if (i == NOTE_DOWN) return 'NOTE_DOWN';
		if (i == NOTE_UP) return 'NOTE_UP';
		if (i == NOTE_RIGHT) return 'NOTE_RIGHT';
		if (i == UP) return 'UP';
		if (i == DOWN) return 'DOWN';
		if (i == LEFT) return 'LEFT';
		if (i == RIGHT) return 'RIGHT';
		if (i == HITBOX_UP) return 'HITBOX_UP';
		if (i == HITBOX_DOWN) return 'HITBOX_DOWN';
		if (i == HITBOX_LEFT) return 'HITBOX_LEFT';
		if (i == HITBOX_RIGHT) return 'HITBOX_RIGHT';
		if (i == EXTRA_1) return 'EXTRA_1';
		if (i == EXTRA_2) return 'EXTRA_2';
		if (i == ANY) return 'ANY';
		return 'NONE';
	}
}
