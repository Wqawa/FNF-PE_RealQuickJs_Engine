package options;

/**
 * 版本差异（Compat）—— 只影响本仓的 body 树，原版 1.0.4 和 0.6.3 两棵树不受影响。
 *
 * 每一项默认关闭 = 保持 1.0.4 原本行为；打开才回退成 0.6.3 那套，给老 mod 用。
 */
class CompatSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'Version Differences';
		rpcTitle = 'Version Differences Menu';

		var option:Option = new Option('Legacy HUD Layout',
			'Flatten the HUD group so old scripts can sort objects by member index again (0.6.3 style).',
			'compatLegacyUI',
			BOOL);
		addOption(option);

		option = new Option('Legacy Hold Notes',
			'Dropped hold-note segments stay fully opaque and keep following the strum, like 0.6.3.',
			'compatLegacySustain',
			BOOL);
		addOption(option);

		option = new Option('Legacy Health Gain',
			'Each hit heals 0.023 like 0.6.3 instead of the reduced 1.0.4 amount.',
			'compatLegacyHealth',
			BOOL);
		addOption(option);

		option = new Option('Legacy Icons',
			'Use the 0.6.3 icon cropping/scaling so health icons are not cut off.',
			'compatLegacyIcons',
			BOOL);
		addOption(option);

		super();
	}
}
