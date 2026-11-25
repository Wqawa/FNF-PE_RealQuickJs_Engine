package options;

// script channel debug switches. used to sit inside Gameplay, buried between gameplay options.
class DebugSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.getPhrase('debug_menu', 'Debug Settings');
		rpcTitle = 'Debug Settings Menu';

		var option:Option = new Option('JS Engine',
			"Which engine runs .js scripts in mods.\nTroll = the joke 'interpreter' that has always been there,\nQuickJS = the real QuickJS-NG runtime.",
			'jsEngine',
			STRING,
			['Troll', 'QuickJS']);
		addOption(option);

		var option:Option = new Option('More Lua Errors',
			'If checked, every Lua error gets printed instead of only the first one of its kind.',
			'moreLuaErrors',
			BOOL);
		addOption(option);

		var option:Option = new Option('Show HScript Errors',
			'If checked, HScript errors show on screen.\nUnchecked, they only go to testout/js_log.txt.',
			'hscriptErrors',
			BOOL);
		addOption(option);

		super();
	}
}
