package backend;

// 0.6.3 had a real Section class; 1.0 only keeps the SwagSection typedef.
// This shell lets old scripts import/new it; real data is still SwagSection.
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
