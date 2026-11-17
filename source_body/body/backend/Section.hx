package backend;

/**
 * 0.6.3 had Section as a real class (a chart section); 1.0 only keeps the SwagSection typedef.
 * Old HScript doing `import Section;` / `new Section()` could not find it, hence this shell.
 * It can be constructed and read from; the engine still uses SwagSection for real data.
 */
class Section
{
	public var sectionNotes:Array<Dynamic> = [];
	public var sectionBeats:Float = 4;
	public var mustHitSection:Bool = true;
	public var gfSection:Bool = false;
	public var bpm:Float = 0;
	public var changeBPM:Bool = false;
	public var altAnim:Bool = false;

	public function new(sectionBeats:Float = 4)
	{
		this.sectionBeats = sectionBeats;
	}
}
