package debug;

// Clock + per-script totals for the F3 overlay. Windows' Sys.time() only moves in big
// steps, way too coarse for callbacks that take 20us, so this reads the performance
// counter directly. Callers check `on` first, so a normal build pays one bool read.
@:cppFileCode('
#ifdef HX_WINDOWS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif
static double rqj_now_micros() {
	static LARGE_INTEGER freq;
	if (freq.QuadPart == 0) QueryPerformanceFrequency(&freq);
	LARGE_INTEGER now;
	QueryPerformanceCounter(&now);
	return (double)now.QuadPart * 1000000.0 / (double)freq.QuadPart;
}
#else
static double rqj_now_micros() { return 0.0; }
#endif
')
class Perf
{
	public static function micros():Float
		return untyped __cpp__('rqj_now_micros()');

	// Script timings only get collected while the detailed overlay is up.
	public static var on:Bool = false;

	static var spent:haxe.ds.ObjectMap<Dynamic, Float> = new haxe.ds.ObjectMap();
	static var calls:haxe.ds.ObjectMap<Dynamic, Int> = new haxe.ds.ObjectMap();

	public static inline function begin():Float
		return on ? micros() : -1;

	public static function end(host:Dynamic, t0:Float):Void
	{
		if (t0 < 0 || host == null) return;
		var d:Float = micros() - t0;
		spent.set(host, (spent.exists(host) ? spent.get(host) : 0) + d);
		calls.set(host, (calls.exists(host) ? calls.get(host) : 0) + 1);
	}

	public static function scriptUs(host:Dynamic):Float
		return (host != null && spent.exists(host)) ? spent.get(host) : 0;

	public static function scriptCalls(host:Dynamic):Int
		return (host != null && calls.exists(host)) ? calls.get(host) : 0;

	// Called once the overlay has copied the numbers into its own fields.
	public static function resetScripts():Void
	{
		spent.clear();
		calls.clear();
	}
}
