extends RefCounted
class_name UiFonts
## Godot 内置的默认字体只带拉丁字形，直接写中文会渲染成方块。
## 这里在运行时找一个中文字体，找不到就退回英文文案（各界面 `_t()` 的那个分支）。
##
## ## 手机和网页上一路英文，就是这里没找到
##
## 早先这张表**全是桌面路径**（`C:/Windows/Fonts/msyh.ttc`、`/usr/share/fonts/...`、
## macOS 的 PingFang），安卓上一个都不存在 —— 于是 `load_cjk_font()` 返回 null，
## 每一屏的 `_cjk` 都是 false，`_t()` 全程返回英文那一份。所以手机上「文字全为英文」
## **不是翻译漏了，是字体没找到**。
##
## 现在分三段找，**顺序就是优先级**：
##
##   1. [method system_cjk_font] 问系统要（[SystemFont]）。这是跨平台的正路 ——
##      桌面/安卓上它查的是系统字体库，比硬编码路径可靠，也不用把字体塞进包里。
##   2. 系统挑不出来，用**随项目携带的子集中文字体**（[constant BUNDLED_FONT_PATH]）。
##      网页版（Web）就是靠这一段活下来的：浏览器里 `SystemFont` 拿不到系统字体，
##      `C:/Windows/Fonts/...` 这种路径也根本不存在（HTML5 没有文件系统）——
##      没有这一档时网页版一直退回英文，`▸`/`◆` 之类的图标字还会变成方块。
##   3. 最后才逐个试 [constant CJK_CANDIDATES] 里的文件路径（桌面那几条 + 安卓的
##      `/system/fonts/...`）。
##
## ## 内置字体是子集，不是整个 Noto
##
## `fonts/NotoSansSC-Game.ttf` 是 Noto Sans SC 的**子集**（SIL OFL 1.1，许可见
## `fonts/OFL.txt`），用 fontTools 的 `pyftsubset` 切出来：GB2312 全部汉字 + 界面字符串
## 里用到的标点/箭头/几何符号 + 拉丁字母，约 2.1 MB。**全量 Noto Sans SC 是 10.5 MB**，
## 直接塞进包里既肥又没必要 —— 界面文案覆盖 GB2312 已经绰绰有余。
##
## 两个维护要点：
##   · 加了新的中文/符号文案后，先跑 `tests/fonts.tscn`；它会逐个核对内置字体有没有
##     界面用到的字形，缺了会红。真缺就重新切子集（README「中文文案」一节有命令）。
##   · Noto Sans SC 没有 `▸`（U+25B8），HUD 那个项目符号用的是 `▶`（U+25B6）。
##
## ## 「加载成功」不等于「能写中文」
##
## 三段都过一道 [method has_cjk]：**拿真字形验一次**。只看
## `load_dynamic_font()` 有没有返回 OK 是不够的 —— 那个字体可能一个汉字都没有，
## 于是界面画出来是**豆腐块**，比退回英文还难看，而且更难查（看着像编码问题）。
## 验不过就接着找下一个，全都不行才返回 null。


## 让系统挑字体时点名的家族。按「先简体中文专用、后兜底」排。
##
## `Droid Sans Fallback` 是老安卓（4.x~7.x）上唯一带汉字的那个；
## `Noto Sans CJK SC` / `Noto Sans SC` 是现在安卓和 Linux 的通名；
## `Microsoft YaHei` / `PingFang SC` / `Heiti SC` 分别是 Windows / macOS / iOS。
const CJK_FONT_NAMES := [
	"Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC", "Source Han Sans CN",
	"Droid Sans Fallback", "Microsoft YaHei", "SimHei", "PingFang SC", "Heiti SC",
	"WenQuanYi Micro Hei", "Noto Sans CJK JP",
]

## 一个汉字，用来验「这个字体真能写中文」。见 [method has_cjk]。
const CJK_PROBE := "中"

## 随项目携带的**子集中文字体**（Noto Sans SC 子集，OFL 1.1，许可见 `fonts/OFL.txt`）。
##
## 网页版（Web）没有系统字体可查、`CJK_CANDIDATES` 里的绝对路径也一条都不存在，
## 这一档是中文文案和图标字形的**唯一**来源 —— 没有它，网页版整屏退回英文，
## `▶` / `◆` / `★` / `←→` 这些图标字会变成方块。
const BUNDLED_FONT_PATH := "res://fonts/NotoSansSC-Game.ttf"


## 系统字体挑不出来时，逐个试这些文件路径。**安卓那几条是给老机器兜底的**
## （不认字体家族名的、或者系统数据库读不出来的）。
const CJK_CANDIDATES := [
	# 安卓
	"/system/fonts/NotoSansCJK-Regular.ttc",
	"/system/fonts/NotoSansCJKsc-Regular.otf",
	"/system/fonts/NotoSansSC-Regular.otf",
	"/system/fonts/DroidSansFallbackFull.ttf",
	"/system/fonts/DroidSansFallback.ttf",
	# Windows
	"C:/Windows/Fonts/msyh.ttc",
	"C:/Windows/Fonts/msyhl.ttc",
	"C:/Windows/Fonts/simhei.ttf",
	"C:/Windows/Fonts/simsun.ttc",
	# macOS / iOS
	"/System/Library/Fonts/PingFang.ttc",
	"/System/Library/Fonts/STHeiti Medium.ttc",
	# Linux
	"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
]


## 这个字体**真有汉字字形**吗。
##
## 用 [method Font.has_char] 而不是「加载成功了没」：一个只有拉丁字形的字体照样能
## 加载成功，画出来却全是豆腐块。见文件头。
static func has_cjk(font: Font) -> bool:
	if font == null:
		return false
	return font.has_char(CJK_PROBE.unicode_at(0))


## 让系统按家族名挑一个中文字体。挑不出来返回的字体 [method has_cjk] 为假。
##
## `allow_system_fallback` 开着：家族名一个都对不上时，还允许引擎按字形去系统里
## 兜底找（安卓上经常是这条把它救回来的）。字体则一律不用斜体、用常规字重。
##
## 单独抽成函数是为了**能测**：测试不必依赖这台机器上装没装字体，就能断
## 「名单里有没有中文家族」「兜底开着没有」。
static func system_cjk_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(CJK_FONT_NAMES)
	font.allow_system_fallback = true
	font.font_italic = false
	font.font_weight = 400
	return font


## 返回一个能写中文的字体；三种来源全落空才返回 null，调用方应回退到英文。
##
## 顺序：系统字体 → 随包内置子集 → [constant CJK_CANDIDATES] 文件路径。
static func load_cjk_font() -> Font:
	var system := system_cjk_font()
	if has_cjk(system):
		return system
	var bundled := bundled_cjk_font()
	if bundled != null:
		return bundled
	return file_cjk_font()


## 随包内置的中文字体；资源没导入、或它不是真带汉字的字体时返回 null。
##
## [b]网页版走的就是这一条[/b]（浏览器里没有系统字体，绝对路径也不存在）。
##
## 用 [method ResourceLoader.exists] 判断而不是 [method FileAccess.file_exists]：导出后
## 的 pck 里只有**导入过的资源**（[FontFile]），原始 `.ttf` 字节不再单独存在。
static func bundled_cjk_font() -> Font:
	if not ResourceLoader.exists(BUNDLED_FONT_PATH):
		return null
	var res := load(BUNDLED_FONT_PATH)
	if res is Font and has_cjk(res):
		return res
	return null


## [constant CJK_CANDIDATES] 里第一个**真有汉字**的字体；一个都没有返回 null。
##
## 和 [method load_cjk_font] 分开：上面那条路走系统，这条走文件。测试要能单独量这条
## （「盘上这个文件在不在、读了有没有汉字」和「系统挑不挑得出来」是两件事）。
static func file_cjk_font() -> Font:
	for path in CJK_CANDIDATES:
		if not FileAccess.file_exists(path):
			continue
		var font := FontFile.new()
		if font.load_dynamic_font(path) != OK:
			continue
		if has_cjk(font):
			return font
	return null
