extends Node
## 车库面板的无头测试。
##
## 分两半：
##   1. 购买逻辑 —— 点一行会发生什么，选中怎么移动，买不起怎么办
##   2. 版面几何 —— 四行不重叠、都在视口内、文字不越界进到下一列
##
## 几何部分不把车库挂进场景树，而是直接给 size 赋值再调布局函数。原因见 README
## 的坑 #7：无头模式视口是 1280×1280 而不是 720，挂进树里量出来的版面是错的。
## `_row_rect()` 之类的只依赖 `size`，手工设定反而能得到真实窗口下的答案。

const GARAGE := preload("res://scenes/garage.tscn")
const DESIGN := Vector2(1280.0, 720.0)

var _failures := 0


func _ready() -> void:
	SaveData.persist = false
	SaveData.reset_progress()

	_test_buying()
	print("")
	_test_selection()
	print("")
	_test_layout()

	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _check_true(label: String, cond: bool, detail: String) -> void:
	if not cond:
		_failures += 1
	print("  %s %s（%s）" % ["OK  " if cond else "FAIL", label, detail])


func _new_garage() -> HillGarage:
	var g: HillGarage = GARAGE.instantiate()
	# 场景里的锚点是「铺满父节点」，直接改 size 会被 Godot 警告说 _ready() 之后
	# 尺寸会被锚点覆盖。它没进树、_ready() 不会跑，尺寸其实留得住，但那条警告
	# 会混在测试输出里像真问题。先把锚点拉平再设尺寸，警告就没了。
	g.set_anchors_preset(Control.PRESET_TOP_LEFT)
	g.size = DESIGN
	return g


# ------------------------------------------------------------ 购买

func _test_buying() -> void:
	print("=== 购买 ===")
	SaveData.reset_progress()
	var g := _new_garage()

	# 花销走 Upgrades.cost(0)，不写死数字 —— 10 级那版的基价是 20，
	# 写死 80 的话这条用例会在改花销曲线时悄悄变成「其实买得起」。
	SaveData.total_coins = Upgrades.cost(0) - 1
	g._buy(0)                                  # 引擎，第一级
	_check("钱不够时等级不动", SaveData.level_of("engine"), 0)
	_check("钱不够时不扣钱", SaveData.total_coins, Upgrades.cost(0) - 1)
	_check_true("钱不够时给了红闪提示", g._flash_row == 0 and g._flash > 0.0,
			"flash_row=%d flash=%.2f" % [g._flash_row, g._flash])

	SaveData.total_coins = Upgrades.cost(0)
	g._buy(0)
	_check("刚好够就升一级", SaveData.level_of("engine"), 1)
	_check("扣掉第一级的钱", SaveData.total_coins, 0)

	# 满级之后再点
	SaveData.total_coins = 99999
	for i in range(Upgrades.MAX_LEVEL):
		g._buy(3)                              # 敏捷
	_check("敏捷封顶在 MAX_LEVEL", SaveData.level_of("agility"), Upgrades.MAX_LEVEL)
	g._buy(3)
	_check("满级后再点仍是 MAX_LEVEL", SaveData.level_of("agility"), Upgrades.MAX_LEVEL)

	# 各买各的，互不干扰
	SaveData.reset_progress()
	SaveData.total_coins = 99999
	g._buy(1)                                  # 极速
	_check("只动了极速", [SaveData.level_of("engine"), SaveData.level_of("fuel")], [0, 0])
	_check("极速 = 1", SaveData.level_of("speed"), 1)
	g.free()


# ------------------------------------------------------------ 选中

func _test_selection() -> void:
	print("=== 选中 ===")
	var g := _new_garage()
	g._sel = 0

	# 上下要首尾环绕，撞到底不会卡住
	g._move(-1)
	_check("从第 0 项往上 = 绕到最后一项", g._sel, Upgrades.IDS.size() - 1)
	g._move(1)
	_check("再往下回到第 0 项", g._sel, 0)
	g._sel = Upgrades.IDS.size() - 1
	g._move(1)
	_check("从最后一项往下 = 绕回第 0 项", g._sel, 0)

	# 点空白处不该有反应。
	#
	# 这里的钱是够买一级的（[constant Upgrades.BASE_COST] = 1000）：下面要验的
	# 「点某一行会买它」得真买下来，钱不够的话点击会静默失败，测的就不是「会不会买」
	# 而是「穷的时候买不买得起」了。
	SaveData.reset_progress()
	SaveData.total_coins = 10000
	g._sel = 2
	g._on_click(Vector2(4.0, 4.0))
	_check("点标题区不改变选中", g._sel, 2)
	_check("点标题区不买东西", SaveData.level_of("engine"), 0)

	# 点某一行 = 选中它并买一级
	var row := g._row_rect(1)
	g._on_click(row.position + Vector2(40.0, 40.0))
	_check("点第 2 行会选中它", g._sel, 1)
	_check("点第 2 行会买它", SaveData.level_of("speed"), 1)
	g.free()


# ------------------------------------------------------------ 版面

func _test_layout() -> void:
	print("=== 版面（按真实窗口 1280×720 计算）===")
	var g := _new_garage()
	var font := UiFonts.load_cjk_font()
	var cjk := font != null
	if not cjk:
		font = ThemeDB.fallback_font
	print("  中文字体：%s" % ("有" if cjk else "没有，按英文版量"))

	# 四行依次排开、不重叠、都在视口内
	var prev_bottom := 0.0
	var all_rows_ok := true
	for i in range(Upgrades.IDS.size()):
		var r := g._row_rect(i)
		var ok := r.position.y >= prev_bottom and r.end.y <= DESIGN.y \
				and r.position.x >= 0.0 and r.end.x <= DESIGN.x
		all_rows_ok = all_rows_ok and ok
		prev_bottom = r.end.y
	_check_true("四行不重叠且都在视口内", all_rows_ok,
			"第 1 行 y=%.0f..%.0f，第 4 行 y=%.0f..%.0f" % [
				g._row_rect(0).position.y, g._row_rect(0).end.y,
				g._row_rect(3).position.y, g._row_rect(3).end.y,
			])

	# 开始按钮在第 4 行下面、不压住它、自己也在视口内
	var last := g._row_rect(Upgrades.IDS.size() - 1)
	var start := g._start_rect()
	_check_true("开始按钮在第 4 行下方且不重叠",
			start.position.y >= last.end.y and start.end.y <= DESIGN.y,
			"按钮 y=%.0f..%.0f，末行底 %.0f" % [start.position.y, start.end.y, last.end.y])
	_check_true("开始按钮水平居中",
			is_equal_approx(start.position.x + start.size.x * 0.5, DESIGN.x * 0.5),
			"中心 x=%.1f" % (start.position.x + start.size.x * 0.5))

	# 每行的价格药丸要在行内，别戳出去
	var pills_ok := true
	for i in range(Upgrades.IDS.size()):
		var r := g._row_rect(i)
		var p := g._pill_rect(r)
		pills_ok = pills_ok and r.encloses(p)
	_check_true("价格药丸都在行内", pills_ok, "药丸宽 %.0f" % HillGarage.PILL_W)

	# 文字不能越过分栏线。这是最容易出错的一处：中文说明句子长，
	# 字号或文案一改就可能撞到右边的等级方块。
	var row := g._row_rect(0)
	var name_x := row.position.x + 34.0
	var squares_x := row.position.x + row.size.x * 0.40
	var effect_x := squares_x + HillGarage.EFFECT_OFFSET
	var pill_x := row.position.x + row.size.x - HillGarage.PILL_W - 30.0

	# 等级方块自己也得装得下，而且不能压到「当前效果」上。10 级那版方块边长是
	# 从 PIPS_ROOM 反推的，这条断言就是那次改动的看门狗。
	var pips_w := HillGarage.PIPS_ROOM
	_check_true("等级方块区不撞到当前效果", squares_x + pips_w <= effect_x,
			"方块区 %.0f..%.0f，效果文字起于 %.0f" % [
				squares_x, squares_x + pips_w, effect_x,
			])
	_check_true("方块边长正数且装得下 %d 级" % Upgrades.MAX_LEVEL,
			g.pip_size() > 0.0
					and g.pip_size() * Upgrades.MAX_LEVEL
							+ HillGarage.PIPS_GAP * (Upgrades.MAX_LEVEL - 1) <= pips_w + 0.01,
			"边长 %.1f × %d 级" % [g.pip_size(), Upgrades.MAX_LEVEL])

	var worst_name := 0.0
	var worst_note := 0.0
	var worst_effect := 0.0
	for id in Upgrades.IDS:
		var track: Dictionary = Upgrades.TRACKS[id]
		# 必须显式标 String：字典取出来是 Variant，:= 推不出类型（和 save.gd 里
		# `var ok := got == want` 是同一类坑）
		var nm: String = track["zh"] if cjk else track["en"]
		var note: String = track["zh_note"] if cjk else track["en_note"]
		var unit: String = track["zh_unit"] if cjk else track["en_unit"]
		worst_name = maxf(worst_name, font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 29).x)
		worst_note = maxf(worst_note, font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
		worst_effect = maxf(worst_effect,
				font.get_string_size("%s ×1.00" % unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x)

	var name_room := squares_x - name_x - 12.0
	var effect_room := pill_x - effect_x - 12.0
	_check_true("名称不撞到等级方块", worst_name <= name_room,
			"最宽 %.0f / 可用 %.0f" % [worst_name, name_room])
	_check_true("说明不撞到等级方块", worst_note <= name_room,
			"最宽 %.0f / 可用 %.0f" % [worst_note, name_room])
	_check_true("效果文字不撞到价格药丸", worst_effect <= effect_room,
			"最宽 %.0f / 可用 %.0f" % [worst_effect, effect_room])

	# 页脚两行（左边按键说明、右边推重比）别在中间撞上
	var hint := "↑↓ 选择     → / 空格 升级     回车 开始    也可以直接点" if cjk else \
			"UP/DOWN select     RIGHT/SPACE upgrade     ENTER start"
	var ratio := "推重比 1.00  /  1.45 翘头" if cjk else "POWER/WEIGHT 1.00  /  1.45 wheelie"
	var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var ratio_w := font.get_string_size(ratio, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var footer_room := DESIGN.x - 120.0
	_check_true("页脚左右两段不重叠", hint_w + ratio_w <= footer_room,
			"%0.f + %0.f / 可用 %.0f" % [hint_w, ratio_w, footer_room])

	g.free()
