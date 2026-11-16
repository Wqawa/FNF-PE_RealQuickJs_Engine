package backend;

import openfl.utils.Assets;

import haxe.Json;

typedef ModsList = {
	enabled:Array<String>,
	disabled:Array<String>,
	all:Array<String>
};

class Mods
{
	static public var currentModDirectory:String = '';
	public static final ignoreModFolders:Array<String> = [
		'characters',
		'custom_events',
		'custom_notetypes',
		'data',
		'songs',
		'music',
		'sounds',
		'shaders',
		'videos',
		'images',
		'stages',
		'weeks',
		'fonts',
		'scripts',
		'achievements'
	];

	private static var globalMods:Array<String> = [];

	inline public static function getGlobalMods()
		return globalMods;

	/**
	 * mods/global/ 下面实际存在的 mod 文件夹名。
	 *
	 * 规则是「位置决定语义」：文件夹放进来就算全局，三个版本都能读到 ——
	 * 不用再去各自的 modsList.txt 里启用一遍，也不用在 pack.json 里写 runsGlobally。
	 * 以前那两条要求（列表 + 标记）是 global 只在本体生效的根因：
	 * mods/1.0.4/ 和 mods/0.6.3/ 的 modsList 是空的，全球 mod 就永远进不来。
	 */
	public static function getGlobalDirs():Array<String>
	{
		var out:Array<String> = [];
		#if MODS_ALLOWED
		var root:String = Paths.globalMods();
		if(FileSystem.exists(root))
		{
			for (folder in FileSystem.readDirectory(root))
			{
				var path:String = haxe.io.Path.join([root, folder]);
				if(FileSystem.isDirectory(path) && !ignoreModFolders.contains(folder.toLowerCase()) && !out.contains(folder))
					out.push(folder);
			}
		}
		#end
		return out;
	}

	public static function pushGlobalMods():Array<String>
	{
		globalMods = [];

		// 1) 物理放在 mods/global/ 里的，无条件算全局
		for (mod in getGlobalDirs())
			if(!globalMods.contains(mod)) globalMods.push(mod);

		// 2) 老位置兼容：还在 mods/<版本>/ 里、pack.json 标了 runsGlobally 的照旧认
		for(mod in parseList().enabled)
		{
			if(globalMods.contains(mod)) continue;
			var pack:Dynamic = getPack(mod);
			if(pack != null && pack.runsGlobally) globalMods.push(mod);
		}

		// 启动时留一条，省得以后又出现「global 到底生效了没」的猜谜
		if(globalMods.length > 0) trace('[mods] global: ' + globalMods.join(', '));
		return globalMods;
	}

	inline public static function getModDirectories():Array<String>
	{
		var list:Array<String> = [];
		#if MODS_ALLOWED
		var modsFolder:String = Paths.mods();
		if(FileSystem.exists(modsFolder)) {
			for (folder in FileSystem.readDirectory(modsFolder))
			{
				var path = haxe.io.Path.join([modsFolder, folder]);
				if (FileSystem.isDirectory(path) && !ignoreModFolders.contains(folder.toLowerCase()) && !list.contains(folder))
					list.push(folder);
			}
		}
		#end
		return list;
	}
	
	inline public static function mergeAllTextsNamed(path:String, ?defaultDirectory:String = null, allowDuplicates:Bool = false)
	{
		if(defaultDirectory == null) defaultDirectory = Paths.getSharedPath();
		defaultDirectory = defaultDirectory.trim();
		if(!defaultDirectory.endsWith('/')) defaultDirectory += '/';
		if(!defaultDirectory.startsWith('assets/')) defaultDirectory = 'assets/$defaultDirectory';

		var mergedList:Array<String> = [];
		var paths:Array<String> = directoriesWithFile(defaultDirectory, path);

		var defaultPath:String = defaultDirectory + path;
		if(paths.contains(defaultPath))
		{
			paths.remove(defaultPath);
			paths.insert(0, defaultPath);
		}

		for (file in paths)
		{
			var list:Array<String> = CoolUtil.coolTextFile(file);
			for (value in list)
				if((allowDuplicates || !mergedList.contains(value)) && value.length > 0)
					mergedList.push(value);
		}
		return mergedList;
	}

	inline public static function directoriesWithFile(path:String, fileToFind:String, mods:Bool = true)
	{
		var foldersToCheck:Array<String> = [];
		//Main folder
		if(FileSystem.exists(path + fileToFind))
			foldersToCheck.push(path + fileToFind);

		// Week folder
		if(Paths.currentLevel != null && Paths.currentLevel != path)
		{
			var pth:String = Paths.getFolderPath(fileToFind, Paths.currentLevel);
			if(!foldersToCheck.contains(pth) && FileSystem.exists(pth))
				foldersToCheck.push(pth);
		}

		#if MODS_ALLOWED
		if(mods)
		{
			// Global mods first（mods/global/ 优先，老位置当兼容）
			for(mod in Mods.getGlobalMods())
			{
				var gFolder:String = Paths.globalMods(mod + '/' + fileToFind);
				var hasGlobal:Bool = FileSystem.exists(gFolder);
				if(hasGlobal && !foldersToCheck.contains(gFolder)) foldersToCheck.push(gFolder);

				// 同名副本同时留在 mods/<版本>/ 里的时候只认 global 那份。
				// 两边都推的话脚本会装两遍（同一个 mod 两套 lua/hscript 同时跑，
				// 实测直接把游戏搞崩），这也是 global 改造最容易踩的坑。
				if(hasGlobal) continue;

				var folder:String = Paths.mods(mod + '/' + fileToFind);
				if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
			}

			// Then "PsychEngine/mods/" main folder
			var folder:String = Paths.mods(fileToFind);
			if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(Paths.mods(fileToFind));

			// And lastly, the loaded mod's folder
			if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			{
				var folder:String = Paths.mods(Mods.currentModDirectory + '/' + fileToFind);
				if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
			}
		}
		#end
		return foldersToCheck;
	}

	public static function getPack(?folder:String = null):Dynamic
	{
		#if MODS_ALLOWED
		if(folder == null) folder = Mods.currentModDirectory;

		var path = Paths.mods(folder + '/pack.json');
		// 只放在 mods/global/ 里的 mod 在版本目录下没有包，回退去那边读
		if(!FileSystem.exists(path)) path = Paths.globalMods(folder + '/pack.json');
		if(FileSystem.exists(path)) {
			try {
				#if sys
				var rawJson:String = File.getContent(path);
				#else
				var rawJson:String = Assets.getText(path);
				#end
				if(rawJson != null && rawJson.length > 0) return tjson.TJSON.parse(rawJson);
			} catch(e:Dynamic) {
				trace(e);
			}
		}
		#end
		return null;
	}

	public static var updatedOnState:Bool = false;
	inline public static function parseList():ModsList {
		if(!updatedOnState) updateModList();
		var list:ModsList = {enabled: [], disabled: [], all: []};

		#if MODS_ALLOWED
		try {
			for (mod in CoolUtil.coolTextFile(Paths.modsListPath()))
			{
				//trace('Mod: $mod');
				if(mod.trim().length < 1) continue;

				var dat = mod.split("|");
				list.all.push(dat[0]);
				if (dat[1] == "1")
					list.enabled.push(dat[0]);
				else
					list.disabled.push(dat[0]);
			}
		} catch(e) {
			trace(e);
		}
		#end
		return list;
	}
	
	private static function updateModList()
	{
		#if MODS_ALLOWED
		// Find all that are already ordered
		var list:Array<Array<Dynamic>> = [];
		var added:Array<String> = [];
		try {
			for (mod in CoolUtil.coolTextFile(Paths.modsListPath()))
			{
				var dat:Array<String> = mod.split("|");
				var folder:String = dat[0];
				if(folder.trim().length > 0 && FileSystem.exists(Paths.mods(folder)) && FileSystem.isDirectory(Paths.mods(folder)) && !added.contains(folder))
				{
					added.push(folder);
					list.push([folder, (dat[1] == "1")]);
				}
			}
		} catch(e) {
			trace(e);
		}
		
		// Scan for folders that aren't on modsList.txt yet
		for (folder in getModDirectories())
		{
			if(folder.trim().length > 0 && FileSystem.exists(Paths.mods(folder)) && FileSystem.isDirectory(Paths.mods(folder)) &&
			!ignoreModFolders.contains(folder.toLowerCase()) && !added.contains(folder))
			{
				added.push(folder);
				list.push([folder, true]); //i like it false by default. -bb //Well, i like it True! -Shadow Mario (2022)
				//Shadow Mario (2023): What the fuck was bb thinking
			}
		}

		// Now save file
		var fileStr:String = '';
		for (values in list)
		{
			if(fileStr.length > 0) fileStr += '\n';
			fileStr += values[0] + '|' + (values[1] ? '1' : '0');
		}

		// 版本目录可能是第一次跑（比如刚切到原版），mods/<ver>/ 还不存在，
		// 直接 saveContent 会抛 file_open。先建目录，写失败也不要连累启动。
		var listPath:String = Paths.modsListPath();
		var listDir:String = haxe.io.Path.directory(listPath);
		if(listDir != null && listDir.length > 0 && !FileSystem.exists(listDir))
			FileSystem.createDirectory(listDir);

		try File.saveContent(listPath, fileStr)
		catch(e:Dynamic) trace('Mods: failed to save $listPath: $e');
		updatedOnState = true;
		//trace('Saved modsList.txt');
		#end
	}

	public static function loadTopMod()
	{
		Mods.currentModDirectory = '';
		
		#if MODS_ALLOWED
		var list:Array<String> = Mods.parseList().enabled;
		if(list != null && list[0] != null)
			Mods.currentModDirectory = list[0];
		#end
	}
}