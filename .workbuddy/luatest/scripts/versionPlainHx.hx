// 不带标记：version 必须还是引擎真实版本，别被隔壁那个带标记的污染。
function onCreate()
{
	setVar('hx_version_plain', version);
	setVar('hx_pe_version_plain', psychEngineVersion);
}
