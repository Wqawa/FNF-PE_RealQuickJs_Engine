package backend;

/**
 * 0.6.3 里 Section 是个独立的类（谱面段落），1.0 只保留了 `SwagSection` 这个 typedef。
 * 老 HScript 写 `import Section;` / `new Section()` 会直接找不到类，所以补个壳子。
 * 只负责"能建、能读字段"，不参与引擎的谱面流程 —— 真正的段落数据还是 SwagSection。
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
