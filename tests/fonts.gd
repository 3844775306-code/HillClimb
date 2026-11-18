extends Node
## 中文字体查找（[UiFonts]）的测试。
##
## 手机上「文字全为英文」是**字体没找到**，不是翻译漏了 —— 详见 [UiFonts] 文件头。
## 所以这一节盯的是三件事：
##
##  1. 「加载成功」不算数，要**真有字形**（[method UiFonts.has_cjk]）。
##  2. 候选表里**得有安卓那条路**（系统家族名 + `/system/fonts/` 路径）。
##  3. 各界面那个 `_cjk` 只能是「字体找到没」推出来的 —— 谁要是写死成 `true`，
##     在没有中文字体的机器上就是一屏豆腐块，比英文还难查。
##
## 第 2、3 条是**结构检查**（读源文件），因为这台机器上跑不出安卓的真实情况：
## `adb devices` 和 `emulator -list-avds` 都是空的，见 README「手机版」一节。

const SCRIPTS_DIR := "res://scripts"
const FONT_SOURCE := "res://scripts/ui_fonts.gd"
## 界面上真会画出来的字。中文字体得是**这些字都有**，不只是碰巧有个「中」。
const USED_GLYPHS := "金币解锁车图隧道雪地火山森林平原距离米升级商店成就"

var _failures := 0


func _ready() -> void:
	print("=== 字形探测 ===")
	_test_probe()
	print("")
	print("=== 系统字体 ===")
	_test_system()
	print("")
	print("=== 路径表 ===")
	_test_paths()
	print("")
	print("=== 真找一个 ===")
	_test_find()
	print("")
	print("=== 界面接线 ===")
	_test_wiring()

	print("")
	if _failures == 0:
		print("全部通过")
	else:
		print("!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


func _test_probe() -> void:
	_check("空字体当然不算能写中文", not UiFonts.has_cjk(null), "has_cjk(null) = false")

	# 引擎内置那个字体。**它写不了中文**，这正是 [UiFonts] 存在的理由 ——
	# 这一条要是哪天变成了 true，说明引擎自带兜底了，那整份候选表都可以删了。
	var base := ThemeDB.fallback_font
	_check("引擎自带字体写不了中文（所以才有这份候选表）",
			base != null and not UiFonts.has_cjk(base),
			"内置默认字体 has_char(中) = %s" % [base != null and UiFonts.has_cjk(base)])

	var probe := UiFonts.CJK_PROBE
	_check("探测用的字是一个汉字",
			probe.length() == 1 and probe.unicode_at(0) >= 0x4E00
			and probe.unicode_at(0) <= 0x9FFF,
			"U+%04X「%s」" % [probe.unicode_at(0), probe])


func _test_system() -> void:
	var names := UiFonts.CJK_FONT_NAMES
	var want := PackedStringArray(UiFonts.CJK_FONT_NAMES)
	_check("名单不是空的", names.size() > 0, "%d 个家族名" % names.size())
	_check("名单里没有空名、没有重名",
			not names.has("") and _unique(names) == names.size(),
			"去重后 %d 个" % _unique(names))
	# 安卓上真正会命中的两条：新的（Noto）和老机器上唯一带汉字的兜底（Droid）。
	_check("名单点了安卓上真有的家族",
			names.has("Noto Sans CJK SC") and names.has("Droid Sans Fallback"),
			"Noto Sans CJK SC / Droid Sans Fallback 都在")

	var font := UiFonts.system_cjk_font()
	_check("系统字体按名单挑、开着系统兜底、常规字重",
			font != null and font.font_names == want
			and font.allow_system_fallback and not font.font_italic
			and font.font_weight == 400,
			"family=%d 个，fallback=%s，weight=%d" % [font.font_names.size(),
				font.allow_system_fallback, font.font_weight])


func _test_paths() -> void:
	var paths := UiFonts.CJK_CANDIDATES
	_check("路径表不是空的", paths.size() > 0, "%d 条" % paths.size())
	var bad := PackedStringArray()
	for p in paths:
		# 相对路径会跟着**当前工作目录**走（手机上根本没有那个目录），
		# 所以候选一律得是绝对路径。
		if not (p.begins_with("/") or p.substr(1, 2) == ":/"):
			bad.append(p)
	_check("每条都是绝对路径", bad.is_empty(),
			"%d 条全部以 / 或 X:/ 开头" % paths.size() if bad.is_empty()
			else "不像绝对路径：%s" % "、".join(bad))
	_check("没有重名", _unique(paths) == paths.size(), "去重后 %d 条" % _unique(paths))

	# 安卓那几条要**排在桌面前面**：手机上先撞到的应该是能用的那条，
	# 而不是每次都白跑十几个 `FileAccess.file_exists` 才轮到它对。
	var android := -1
	var desktop := -1
	for i in range(paths.size()):
		if paths[i].begins_with("/system/fonts/") and android < 0:
			android = i
		if (paths[i].begins_with("C:/") or paths[i].begins_with("/usr/")
				or paths[i].begins_with("/System/")) and desktop < 0:
			desktop = i
	_check("路径表里有安卓的系统字体目录", android >= 0,
			"第 %d 条起是 /system/fonts/" % (android + 1) if android >= 0
			else "一条 /system/fonts/ 都没有（手机上一路英文就是这么来的）")
	_check("安卓那几条排在桌面前面", android >= 0 and (desktop < 0 or android < desktop),
			"安卓第 %d 条、桌面第 %d 条" % [android + 1, desktop + 1])


func _test_find() -> void:
	var file := UiFonts.file_cjk_font()
	var path := _first_candidate_file()
	# 两条路（逐个试文件 vs 上面的实现）必须给出同一个结论。
	_check("逐个试文件的结果和实现一致",
			(file != null) == (path != ""),
			"file_cjk_font() = %s，扫出来的 = 「%s」" % [
				file != null, path if path != "" else "（一条都不行）"])

	var font := UiFonts.load_cjk_font()
	_check("这台机器上找得到一个中文字体", font != null,
			_identity(font) if font != null else "一个都没有 → 界面会退回英文")
	# **返回非 null 就一定得真有字形**：只有拉丁字形的字体也能加载成功，
	# 画出来是豆腐块 —— 那比退回英文还难看，还更容易被当成编码问题去查。
	_check("返回的字体真有界面上要用的那些字",
			font != null and _have_glyphs(font),
			"「%s」缺 %d 个字" % [USED_GLYPHS, _missing_glyphs(font).size()]
			if font != null else "没找到字体")


func _test_wiring() -> void:
	var files := _scan(SCRIPTS_DIR)
	_check("列得出脚本目录", files.size() > 0,
			"%s 下 %d 个 .gd" % [SCRIPTS_DIR, files.size()])

	# 一、**字体的路径表只有一份**。第二份桌面路径表就是「手机上英文」复发的方式：
	# 某个界面自己抄了一份 `C:/Windows/Fonts/...`，桌面上看不出任何异常。
	var dup := PackedStringArray()
	for f in files:
		if f == FONT_SOURCE:
			continue
		var src := FileAccess.get_file_as_string(f)
		if src.contains(".ttc") or src.contains(".ttf") or src.contains(".otf"):
			dup.append(f)
	_check("字体路径表只有 ui_fonts.gd 一份", dup.is_empty(),
			"没有第二处写字体文件名" if dup.is_empty() else "另抄了一份：%s" % "、".join(dup))

	# 二、`_cjk` 只能是「字体找到没」推出来的。
	#
	# 两条合法写法：
	#   · 自己找字体：`_font = UiFonts.load_cjk_font()` + `_cjk = _font != null`
	#   · 字体是别人传进来的（HUD 的子控件）：`_cjk = cjk`
	# 非法的是第三种：写死 `_cjk = true`（没字体的机器上满屏豆腐块）。
	var users := PackedStringArray()
	var wrong := PackedStringArray()
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		if not src.contains("var _cjk"):
			continue
		users.append(f.get_file())
		var looks_ok := (src.contains("_cjk = _font != null")
					and src.contains("load_cjk_font"))
		var passed_in := src.contains("_cjk = cjk")
		# 赋值恰好一次：多出来的那处多半是别处又覆盖了一遍。
		if not (looks_ok or passed_in) or src.count("_cjk = ") != 1:
			wrong.append(f.get_file())
	_check("每一处 _cjk 都是从「字体找到没」推出来的", wrong.is_empty(),
			"%d 处：%s" % [users.size(), "、".join(users)] if wrong.is_empty()
			else "写法不对：%s" % "、".join(wrong))
	# 反过来也要防：`_t()` 挑中文的那套写法别处也该有对应的一份英文，
	# 不然字体没找到时就是**空白**而不是英文。这一条只看「有没有那两参数」。
	var no_en := PackedStringArray()
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		if src.contains("var _cjk") and not src.contains("func _t(zh: String, en: String)"):
			no_en.append(f.get_file())
	_check("每一屏都有一份英文兜底（_t(zh, en)）", no_en.is_empty(),
			"%d 屏都是 _t(zh, en)" % users.size() if no_en.is_empty()
			else "缺英文的：%s" % "、".join(no_en))


# ---------------------------------------------------------------- 小工具

func _unique(list: PackedStringArray) -> int:
	var seen := {}
	for s in list:
		seen[s] = true
	return seen.size()


func _have_glyphs(font: Font) -> bool:
	return _missing_glyphs(font).is_empty()


func _missing_glyphs(font: Font) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(USED_GLYPHS.length()):
		var c := USED_GLYPHS[i]
		if not font.has_char(c.unicode_at(0)):
			out.append(c)
	return out


func _identity(font: Font) -> String:
	if font == null:
		return "null"
	if font is SystemFont:
		return "系统字体（%s）" % "、".join(font.font_names)
	return "字体文件"


## [method UiFonts.file_cjk_font] 里那个循环的**带路径版**：只为了在输出里
## 说清到底是哪一条中了。和实现各写一遍是有风险的，所以上面拿它和实现对了结论。
func _first_candidate_file() -> String:
	for path in UiFonts.CJK_CANDIDATES:
		if not FileAccess.file_exists(path):
			continue
		var font := FontFile.new()
		if font.load_dynamic_font(path) != OK:
			continue
		if UiFonts.has_cjk(font):
			return path
	return ""


## `dir` 下所有 .gd 的完整路径（递归）。字体那两条检查要扫全目录，
## 漏掉子目录就等于漏掉将来放进子目录的界面。
func _scan(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if name.ends_with(".gd"):
			out.append(dir.path_join(name))
	for sub in d.get_directories():
		out.append_array(_scan(dir.path_join(sub)))
	return out
