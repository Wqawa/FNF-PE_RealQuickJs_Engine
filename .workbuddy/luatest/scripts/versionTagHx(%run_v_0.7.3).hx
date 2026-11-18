// 文件名带 (%run_v_0.7.3)：脚本里读 version 应该看到 0.7.3，而不是引擎真实版本。
function onCreate()
{
	setVar('hx_version_tagged', version);
	setVar('hx_pe_version_tagged', psychEngineVersion);
}
