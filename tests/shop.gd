extends Node
## 道具的无头测试：表、存档、商店界面、独轮奖励。
##
## 七节：
##   1. 表完整性 —— [member Items.CATALOG] 和 [member Items.IDS] 对得上，
##      并且**主动道具的动作真的在 InputMap 里**
##   2. 过滤与算价 —— [method Items.clean] / [method Items.cost_of]
##   3. 购买 —— 买不起、刚好够、扣钱、重复 id 只收一份
##   4. 使用 —— 「每场每个最多一次」只有一份实现
##   5. 不落盘 —— 道具是消耗品，写盘之后读回来必须是空的
##   6. 商店界面 —— 余额当场卡住勾选、命中、版面、文字不越出卡片
##   7. 独轮奖励 —— 计时怎么走、什么时候发钱
##
## **不按「出发」键。** [method HillShop._go] 会走 `change_scene_to_file()`，把测试
## 场景本身换掉，测试当场就没了（后面 `get_tree().quit()` 也跑不到）。所以这里只测
## 「勾选状态和总价对不对」，换场景那一步交给别的测试（和 tests/mapselect 一个理由）。
##
## 会真的往 user://save.cfg 写盘 —— 第 3、5 节测的就是「写下去的东西」，用 mock
## 就测不到了。所以开头备份玩家存档，结尾原样写回。

const SHOP := preload("res://scenes/shop.tscn")
const CAR := preload("res://scenes/car.tscn")
const DESIGN := Vector2(1280.0, 720.0)
## 实际可能出现的虚拟尺寸，和 tests/mapselect 同一组（理由见那里）。
const SIZES: Array[Vector2] = [
	Vector2(1280.0, 720.0),   # 16:9 基准
	Vector2(1280.0, 960.0),   # 4:3 窗口
	Vector2(1280.0, 1440.0),  # 竖屏
	Vector2(1720.0, 720.0),   # 21:9
	Vector2(2560.0, 1440.0),  # 2K
]
## 卡片里文字左右各自的留白，和 [constant HillShop.PAD] 对齐。
const CARD_PAD := 22.0

var _failures := 0
var _backup := {}


func _ready() -> void:
	SaveData.persist = false
	SaveData.reset_progress()
	_backup_existing()

	print("")
	_test_catalog()
	print("")
	_test_clean_and_cost()
	print("")
	_test_buy()
	print("")
	_test_use_once()
	print("")
	_test_not_persisted()
	print("")
	_test_screen()
	print("")
	_test_wheelie()
	print("")
	_restore()

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


func _check_eq(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


# ---------------------------------------------------------------- 1. 表

## 道具表自身的完整性，**以及 Catalog 和 project.godot 有没有漂**。
##
## 后一半是这一节真正值钱的地方：`action` 名字和按键提示是手写的两份
## （[member Items.CATALOG] 一份、project.godot 一份），漂了之后
## [method HillCar._pressed] 会返回静默的 false —— 道具买得到、按不出来，而且
## 一句报错都没有。这里把两边对上。
func _test_catalog() -> void:
	print("=== 道具表 ===")
	_check_eq("道具件数", Items.IDS.size(), Items.CATALOG.size())

	var names := PackedStringArray()
	for id in Items.IDS:
		_check("表里有 %s" % id, Items.has_item(id), "CATALOG 有这一项")
		var it := Items.get_item(id)
		names.append(str(it["zh"]))
		for field in ["zh", "en", "zh_note", "en_note", "color", "action", "key"]:
			_check("%s 有 %s" % [id, field], it.has(field), "字段存在")
		_check("%s 的颜色是 Color" % id, it["color"] is Color, str(it["color"]))
	print("  道具 %s" % "  ".join(names))

	# 认不出来的 id 退回第一项（界面宁可显示错一项，也不要整屏崩掉）
	# （比名字而不是比整张表：整张表打出来就是二十行，红了也看不出哪儿不一样）
	_check_eq("脏 id 退回氮气那一行", Items.get_item("unicorn")["zh"], Items.get_item(Items.NITRO)["zh"])
	_check_eq("has_item 认得脏 id", Items.has_item("unicorn"), false)

	var passive := 0
	for id in Items.IDS:
		var action := Items.action_of(id)
		if action == "":
			passive += 1
			_check("%s 是被动的，按键提示不应是个键" % id, str(Items.get_item(id)["key"]) == "—",
					"显示 %s" % str(Items.get_item(id)["key"]))
			continue
		_check("InputMap 里有 %s（%s 的 action）" % [action, id], InputMap.has_action(action),
				"project.godot 里找得到")
		if not InputMap.has_action(action):
			continue
		# 光有动作名不够 —— 还得**真的绑上了键**，而且绑的就是卡片上印的那个。
		# 一个空动作（有名字没事件）在 has_action 上照样是 true，按下去一样没反应。
		var codes := PackedStringArray()
		var key_ok := false
		var pad_ok := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var code := (ev as InputEventKey).physical_keycode
				codes.append(OS.get_keycode_string(code))
				if code == str(Items.get_item(id)["key"]).unicode_at(0):
					key_ok = true
			elif ev is InputEventJoypadButton:
				pad_ok = true
		_check("%s 绑了键盘键 %s" % [action, str(Items.get_item(id)["key"])],
				key_ok, "实际绑的是 %s" % " / ".join(codes))
		_check("%s 也绑了手柄键" % action, pad_ok, "有一个 InputEventJoypadButton")
	_check_eq("被动道具件数", passive, 1)


# ---------------------------------------------------------------- 2. 过滤与算价

func _test_clean_and_cost() -> void:
	print("=== 过滤与算价 ===")
	_check_eq("认得的原样留下", Items.clean([Items.NITRO, Items.SHIELD]),
			[Items.NITRO, Items.SHIELD] as Array)
	_check_eq("不认识的丢掉", Items.clean([Items.NITRO, "unicorn"]), [Items.NITRO] as Array)
	_check_eq("重复的只留一份", Items.clean([Items.FUEL, Items.FUEL]), [Items.FUEL] as Array)
	_check_eq("全脏 → 空", Items.clean(["a", "b"]), [] as Array)
	_check_eq("空的还是空", Items.clean([]), [] as Array)

	_check_eq("一件的价钱", Items.cost_of([Items.NITRO]), Items.PRICE)
	_check_eq("三件的价钱", Items.cost_of(Items.IDS), Items.PRICE * 3)
	_check_eq("重复的不算两份钱", Items.cost_of([Items.FUEL, Items.FUEL]), Items.PRICE)
	_check_eq("脏 id 不算钱", Items.cost_of(["unicorn"]), 0)


# ---------------------------------------------------------------- 3. 购买

func _test_buy() -> void:
	print("=== 购买 ===")
	SaveData.reset_progress()

	_check_eq("没钱时买不了", SaveData.buy_run_items(Items.IDS), false)
	_check_eq("没钱时清单一栏是空的", SaveData.run_item_ids(), [] as Array)
	_check_eq("没钱时一分不扣", SaveData.total_coins, 0)

	SaveData.total_coins = Items.PRICE * 2
	_check_eq("两件的钱买三件", SaveData.buy_run_items(Items.IDS), false)
	_check_eq("买不成时不动钱", SaveData.total_coins, Items.PRICE * 2)
	_check_eq("买不成时背包还是空的", SaveData.run_item_ids(), [] as Array)

	_check_eq("砍到两件就能买", SaveData.buy_run_items([Items.NITRO, Items.SHIELD]), true)
	_check_eq("钱扣掉了", SaveData.total_coins, 0)
	# 顺序按 Items.IDS，不按传进来的先后 —— 否则勾选顺序不同，HUD 上的排列就不同。
	_check_eq("背包按 IDS 排序", SaveData.run_item_ids(), [Items.NITRO, Items.SHIELD] as Array)
	_check_eq("has_item 认得带上的一件", SaveData.has_item(Items.SHIELD), true)
	_check_eq("没带的不认", SaveData.has_item(Items.FUEL), false)

	# 重复 id 只收一份钱
	SaveData.total_coins = Items.PRICE
	_check_eq("重复 id 也买得成", SaveData.buy_run_items([Items.FUEL, Items.FUEL]), true)
	_check_eq("只扣一份钱", SaveData.total_coins, 0)
	_check_eq("背包里也只有一件", SaveData.run_item_ids(), [Items.FUEL] as Array)

	# 一件都没勾 → false，什么都不改（商店那时直接开跑，不走这条路）
	SaveData.total_coins = 500
	_check_eq("空清单买不了", SaveData.buy_run_items([]), false)
	_check_eq("空清单不扣钱", SaveData.total_coins, 500)

	# 再买一次会**整包替换**，不是叠加
	SaveData.total_coins = Items.PRICE * 2
	SaveData.buy_run_items([Items.NITRO])
	SaveData.buy_run_items([Items.SHIELD])
	_check_eq("第二次买替换掉第一次", SaveData.run_item_ids(), [Items.SHIELD] as Array)
	print("  余额 %d" % SaveData.total_coins)


# ---------------------------------------------------------------- 4. 每场一次

func _test_use_once() -> void:
	print("=== 每场每个最多用一次 ===")
	SaveData.reset_progress()
	SaveData.total_coins = Items.PRICE * 3
	SaveData.buy_run_items(Items.IDS)
	SaveData.begin_run()

	for id in Items.IDS:
		_check_eq("%s 第一次用出去" % id, SaveData.use_item(id), true)
		_check_eq("%s 第二次就用不掉了" % id, SaveData.use_item(id), false)
		_check_eq("%s 用掉的标记挂上了" % id, SaveData.item_used(id), true)

	# 没带过的道具，怎么按都用不出去
	_check_eq("没带过的道具用不出去", SaveData.use_item("unicorn"), false)
	SaveData.run_items.clear()
	_check_eq("背包里没有就用不出去", SaveData.use_item(Items.NITRO), false)

	# 重开一局：标记清掉，道具留着（它们就是为这一局买的）
	# **得先把钱补上** —— 上面那一轮把 150 全花光了，不补的话 buy 会失败，
	# 下面两句断言就变成在测「买不起时背包是空的」，不是想测的东西。
	SaveData.total_coins = Items.PRICE * 3
	_check_eq("补了钱就能再买一份", SaveData.buy_run_items(Items.IDS), true)
	SaveData.use_item(Items.NITRO)
	SaveData.begin_run()
	_check_eq("begin_run 清掉「已用」", SaveData.item_used(Items.NITRO), false)
	_check_eq("begin_run 不动背包", SaveData.has_item(Items.NITRO), true)
	_check_eq("begin_run 之后又能用了", SaveData.use_item(Items.NITRO), true)

	# 一局结束：两样一起收摊
	SaveData.end_run()
	_check_eq("end_run 清空背包", SaveData.run_item_ids(), [] as Array)
	_check_eq("end_run 也清掉「已用」", SaveData.item_used(Items.NITRO), false)
	_check_eq("end_run 之后用不出去", SaveData.use_item(Items.NITRO), false)


# ---------------------------------------------------------------- 5. 不落盘

## 道具**故意不写进存档**（[member SaveData.run_items] 的说明）：写进去的话，
## 花 500 块买完 Alt+F4，钱扣了、道具还在档里，下次开局白送一件。
##
## 所以这里同时验两件事：**钱落盘了**（扣费是真的），**道具没落盘**（读回来是空的）。
func _test_not_persisted() -> void:
	print("=== 道具不落盘 ===")
	SaveData.persist = false
	SaveData.reset_progress()
	# 10000 而不是 1000：三件道具是 3×Items.PRICE，给 1000 的话买不成就静默失败
	# （buy_run_items 返回 false、钱不扣、背包是空的），下面三条断言会一起挂。
	var start := 10000
	SaveData.total_coins = start
	SaveData.persist = true
	SaveData.save_data()

	SaveData.buy_run_items(Items.IDS)
	_check_eq("内存里钱扣了", SaveData.total_coins, start - Items.PRICE * 3)
	_check_eq("内存里带上了三件", SaveData.run_item_ids().size(), 3)

	SaveData.load_data()
	_check_eq("读回来钱是扣过的", SaveData.total_coins, start - Items.PRICE * 3)
	_check_eq("读回来背包是空的", SaveData.run_item_ids(), [] as Array)
	_check_eq("「已用」也没留下", SaveData.used_items.size(), 0)

	# 存档文件里根本不该出现道具的键
	var cfg := ConfigFile.new()
	check_file(cfg)


## 存档里有没有混进道具。单独拆出来是为了让上面那节读起来干净。
func check_file(cfg: ConfigFile) -> void:
	var err := cfg.load(SaveData.SAVE_PATH)
	_check("存档读得出来", err == OK, "load 返回 %d" % err)
	var leaked := PackedStringArray()
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			if key.begins_with("item") or key.begins_with("run_") or key.begins_with("used_"):
				leaked.append("%s/%s" % [section, key])
	_check("存档里没有道具的键", leaked.is_empty(),
			"没找到" if leaked.is_empty() else "混进了 %s" % " ".join(leaked))


# ---------------------------------------------------------------- 6. 商店界面

## 一张脱离场景树、尺寸按真实窗口设好的商店界面。
##
## 不挂进树：无头视口是 1280×1280（README 坑 #7），挂进去量出来的尺寸是假的，
## 而 `_card_rect()` 只依赖 `size`，手工设定反而是真实窗口下的答案。
##
## 但 `_ready()` 要**手动叫一次**：不挂进树它永远不跑，`_cjk` 就还是 false，
## `_t()` 会一路返回英文 —— 尺寸那节量出来全是英文的宽度。这台机器上真跑起来
## 用的是中文，量英文等于没量。
func _screen(at: Vector2) -> HillShop:
	var s: HillShop = SHOP.instantiate()
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = at
	s._ready()
	return s


func _test_screen() -> void:
	print("=== 商店界面 ===")
	SaveData.persist = false
	SaveData.reset_progress()

	# 进商店永远是空清单：上一次的勾选早就在上一局里用掉了。
	var s := _screen(DESIGN)
	_check_eq("进来是空清单", s._chosen.size(), 0)
	_check_eq("总价 0", s._total(), 0)

	# 余额当场卡住勾选 —— 这是「出发不会失败」的前提
	SaveData.total_coins = Items.PRICE
	s._chosen.clear()
	_check("买得起时点得动第 0 件", s._can_toggle_on(Items.IDS[0]), "余额 %d" % SaveData.total_coins)
	s._toggle(0)
	_check_eq("勾上了", s._chosen, [Items.IDS[0]] as Array)
	_check_eq("总价跟着涨", s._total(), Items.PRICE)
	_check("钱花光后第二件点不动", not s._can_toggle_on(Items.IDS[1]),
			"余额 %d，已选总价 %d" % [SaveData.total_coins, s._total()])
	s._toggle(1)
	_check_eq("点不动就是真没加上", s._chosen.size(), 1)

	# 再点一下取消，钱和勾选都回来了
	s._toggle(0)
	_check_eq("再点一下取消", s._chosen.size(), 0)
	_check("取消之后又点得动了", s._can_toggle_on(Items.IDS[1]), "总价回到 0")

	# 三件全勾：钱够就一直加得上
	SaveData.total_coins = Items.PRICE * 3
	s._chosen.clear()
	for i in range(Items.IDS.size()):
		s._toggle(i)
	_check_eq("三件都勾上了", s._chosen.size(), 3)
	_check_eq("总价 = 三件", s._total(), Items.PRICE * 3)
	print("  余额 %d，三件全勾后剩 %d" % [SaveData.total_coins, SaveData.total_coins - s._total()])

	_test_screen_hit()
	_test_screen_layout()
	# 这些界面是**脱离场景树**造的，没人会替它们收尸。不显式 free 的话，每次 `_ready()`
	# 装的那份字体和控件一起在退出时报「N 项泄漏」—— 一屏噪声盖住真正的泄漏。
	s.free()


## 哪个坐标算点中哪张卡。用 `_card_at` 判断，不真的点。
func _test_screen_hit() -> void:
	print("  命中：")
	var s := _screen(DESIGN)
	var ok := true
	var report := PackedStringArray()
	for i in range(Items.IDS.size()):
		var r := s._card_rect(i)
		var hit := s._card_at(r.get_center())
		if hit != i:
			ok = false
		report.append("卡%d→%d" % [i + 1, hit + 1])
	_check("每张卡的中心点都命中自己", ok, " ".join(report))
	_check_eq("卡以外的空白不命中", s._card_at(Vector2(4.0, 4.0)), -1)
	_check_eq("「出发」按钮的中心不算卡片", s._card_at(s._go_rect().get_center()), -1)
	s.free()


## 版面：卡片不重叠、居中、在视口内，卡上每一行字都不越出卡片。
##
## 尺寸这一节能写成硬断言，是因为 `stretch/mode = canvas_items` + `aspect = expand`
## + 基准 1280×720 意味着**虚拟尺寸两个方向都不会小于 1280×720**。所以卡宽恒为
## (960 − 22×2) / 3 = 305.33，不是碰运气。
func _test_screen_layout() -> void:
	print("  版面：")
	for at in SIZES:
		var s := _screen(at)
		var n := Items.IDS.size()
		var panel_w := minf(HillShop.PANEL_W, at.x - 120.0)
		var want_w := (panel_w - HillShop.GAP * float(n - 1)) / float(n)
		var problems := PackedStringArray()

		var r0 := s._card_rect(0)
		var rn := s._card_rect(n - 1)
		if not is_equal_approx(r0.size.x, want_w):
			problems.append("卡宽 %.2f≠%.2f" % [r0.size.x, want_w])
		# 整排居中
		var left := r0.position.x
		var right := rn.position.x + rn.size.x
		if not is_equal_approx(left, at.x - right):
			problems.append("不居中（左 %.1f 右空 %.1f）" % [left, at.x - right])
		# 相邻两卡之间正好一个 GAP，不叠
		for i in range(n - 1):
			var a := s._card_rect(i)
			var b := s._card_rect(i + 1)
			if not is_equal_approx(b.position.x - (a.position.x + a.size.x), HillShop.GAP):
				problems.append("卡%d/卡%d 间距不对" % [i + 1, i + 2])
		# 在视口里，而且和「出发」按钮、页脚都不打架
		var go := s._go_rect()
		if r0.position.y < 0.0 or rn.position.y + rn.size.y > at.y:
			problems.append("卡片出视口")
		if rn.position.y + rn.size.y > go.position.y:
			problems.append("卡片压到出发按钮")
		if go.position.y + go.size.y > at.y - 30.0:
			problems.append("出发按钮压到页脚")
		_check("%d×%d 版面" % [int(at.x), int(at.y)], problems.is_empty(),
				"卡宽 %.1f，卡 %d 张" % [want_w, n] if problems.is_empty() else " ".join(problems))

		_test_card_text(s, at)
		s.free()


## 每张卡上的每一行字都得放得下。
##
## `draw_string` 的 width 传 -1 时**不裁不绕**，多出来的部分会直接画到隔壁卡上，
## 两张卡的字叠在一起。商店走的是 [method HillMapSelect.fit_size]，这里就按同一
## 条规则量：缩号之后必须放得下（只有缩到 12 号还放不下才允许越界，那时也没有更
## 短的写法了）。
func _test_card_text(s: HillShop, at: Vector2) -> void:
	var room := s._card_rect(0).size.x - CARD_PAD * 2.0
	var overflow := PackedStringArray()
	var tightest := 999
	for i in range(Items.IDS.size()):
		var id: String = Items.IDS[i]
		var it := Items.get_item(id)
		var lines := [
			[s._t(str(it["zh"]), str(it["en"])), 38],
			[s._t("%d 金币", "%d COINS") % Items.PRICE, 24],
			[s._t(str(it["zh_note"]), str(it["en_note"])), 17],
			[s._t("被动 · 不用按键", "PASSIVE · NO KEY") if Items.action_of(id) == ""
					else s._t("按键 %s" % str(it["key"]), "KEY %s" % str(it["key"])), 16],
			# 底那一行三种状态互斥，三种都得放得下
			[s._t("✓ 已带上", "✓ IN THE CART"), 20],
			[s._t("空格 带上", "SPACE to add"), 20],
			[s._t("金币不够", "NOT ENOUGH COINS"), 20],
		]
		for pair in lines:
			var text := str(pair[0])
			var px := int(pair[1])
			var fit := HillMapSelect.fit_size(s._font, text, px, room)
			var w := s._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fit).x
			tightest = mini(tightest, fit)
			if w > room and fit > HillMapSelect.MIN_FONT:
				overflow.append("「%s」%d→%d 号还要 %.0f px" % [text, px, fit, w])
	_check("%d×%d 卡片文字不越界" % [int(at.x), int(at.y)], overflow.is_empty(),
			"最紧缩到 %d 号" % tightest if overflow.is_empty() else " ".join(overflow))


# ---------------------------------------------------------------- 7. 独轮奖励

## 独轮计时：**恰好一个轮子着地**才算「骑在一个轮子上」，着地的是哪一头
## 决定文案标后轮还是前轮。
##
## 全都着地是正常行驶、全都不着地是腾空，都不算。哪一头离地都发奖。
##
## 签名从「两个布尔值（后轮着地吗 / 前轮着地吗）」改成了「着地几个 + 后轮在不在这
## 几个里面」（见 [method HillCar._update_wheelie]）：独轮车只有一个轮子，前一种
## 写法在它身上说不出「着地一个」到底算前还是算后。下面这套调用就是旧的两个布尔值
## 一对一换算过来的 —— 两个都着地 = 2，腾空 = 0，后轮独走 = 1 且 rear_down。
##
## 这里直接调 [method HillCar._update_wheelie]，**不跑一帧物理** —— 它只碰
## `wheelie_time` 和一个信号。手法是「把车挂进树拿到轮子表，然后一帧都不等」：
## 挂进去 `_ready()` 是同步的，而这一节自始至终没有 `await`，所以物理一次都
## 没轮到过，车不会真的落地。
func _test_wheelie() -> void:
	print("=== 独轮奖励 ===")
	var car: HillCar = CAR.instantiate()
	# **车必须进场景树。** [member HillCar.wheels] 是 `@onready`，`instantiate()`
	# 出来的裸节点还是空数组，而 [method HillCar._update_wheelie] 开头那道
	# 「独轮车不发奖」的闸问的正是 `wheels.size()` —— 不挂进去的话每一帧都从
	# 那道闸溜走，`wheelie_time` 永远是 0，这里量到的就成了「车不在树里」而不是
	# 「计时逻辑」。挂上去 `_ready()` 是当场同步跑完的，而这一节全程不 await，
	# 所以不会有一帧物理插进来搅局。
	add_child(car)
	var got := []
	car.wheelie_bonus.connect(func(coins: int, rear: bool) -> void: got.append([coins, rear]))

	var dt := 1.0 / 60.0
	_check_eq("开局计时是 0", car.wheelie_time, 0.0)

	# 两个都着地：不计
	_ride(car, 60, 2, true, dt)
	_check_eq("两个轮子都着地不计时", car.wheelie_time, 0.0)

	# 两个都不着地（腾空）：也不计
	_ride(car, 60, 0, false, dt)
	_check_eq("腾空不计时", car.wheelie_time, 0.0)
	_check_eq("这一段没发过奖", got.size(), 0)

	# 后轮独走：攒够 WHEELIE_TIME 发一次。
	#
	# **门槛留一帧余量**，别断言「第 need 帧整好发」。`need` 是
	# `ceil(WHEELIE_TIME / dt)` = 120，但 120 个 1/60 累加起来是 1.9999999999999998，
	# 差一个浮点位不到 2.0 —— 于是真的差一帧。这条在实机里没有意义（2 秒的奖励晚
	# 一帧发，谁也看不出来），但写死「第 120 帧发」会让测试红在一个和被测逻辑
	# 无关的地方。这里验的是**门槛在 2 秒附近**，一帧之内都算对。
	var need := int(ceil(HillCar.WHEELIE_TIME / dt))
	_ride(car, need - 1, 1, true, dt)
	_check_eq("差一帧还不发", got.size(), 0)
	_ride(car, 2, 1, true, dt)
	_check_eq("满 %0.1f 秒发一次" % HillCar.WHEELIE_TIME, got.size(), 1)
	if got.size() > 0:
		_check_eq("奖金 = %d" % HillCar.WHEELIE_BONUS_COINS, got[0][0], HillCar.WHEELIE_BONUS_COINS)
		_check_eq("标的是后轮", got[0][1], true)
	# **多出来的部分留着**：接着骑就是连发，而不是重新攒
	_check("发完接着算而不是归零", car.wheelie_time < HillCar.WHEELIE_TIME,
			"余 %0.3f 秒" % car.wheelie_time)
	_ride(car, need + 1, 1, true, dt)
	_check_eq("接着骑再发一次（连发）", got.size(), 2)

	# 中途落地就作废：不攒跨段的时间
	car.wheelie_time = 0.0
	car._update_wheelie(dt, 1, true)
	car._update_wheelie(dt, 0, false)
	_check_eq("腾空一下就把账清了", car.wheelie_time, 0.0)
	car._update_wheelie(dt, 1, true)
	_check_eq("再骑也不是接着上次算", car.wheelie_time, dt)

	# 前轮独走（翘尾）也发奖，只是文案标前轮
	got.clear()
	car.wheelie_time = 0.0
	_ride(car, need + 1, 1, false, dt)
	_check_eq("前轮独走也发奖", got.size(), 1)
	if got.size() > 0:
		_check_eq("标的是前轮", got[0][1], false)
		_check_eq("发奖金额和 WHEELIE_BONUS_COINS 一致",
				got[0][0], HillCar.WHEELIE_BONUS_COINS)

	car.free()


## 按同样的姿态骑 `frames` 帧。[param down] 是着地的轮子数，[param rear_down]
## 是后轮在不在其中。
func _ride(car: HillCar, frames: int, down: int, rear_down: bool, dt: float) -> void:
	for i in frames:
		car._update_wheelie(dt, down, rear_down)


# ---------------------------------------------------------------- 备份 / 还原

func _backup_existing() -> void:
	SaveData.load_data()
	_backup = {
		"best": SaveData.best_distance,
		"coins": SaveData.total_coins,
		# **deep duplicate**：等级是嵌套表，浅拷只复制外层（和 tests/save 同一个坑）
		"levels": SaveData.levels.duplicate(true),
		"best_by_map": SaveData.best_by_map.duplicate(),
		"achieved_by_map": SaveData.achieved_by_map.duplicate(),
		"selected_map": SaveData.selected_map,
		"selected_vehicle": SaveData.selected_vehicle,
	}
	print("已备份玩家存档：最远 %d m，金币 %d，选中 %s / %s" % [
		_backup["best"], _backup["coins"],
		Maps.get_map(SaveData.selected_map)["zh"],
		Vehicles.get_vehicle(SaveData.selected_vehicle)["zh"],
	])


func _restore() -> void:
	print("=== 还原玩家存档 ===")
	SaveData.best_distance = int(_backup["best"])
	SaveData.total_coins = int(_backup["coins"])
	SaveData.levels = (_backup["levels"] as Dictionary).duplicate(true)
	SaveData.best_by_map = (_backup["best_by_map"] as Dictionary).duplicate()
	SaveData.achieved_by_map = (_backup["achieved_by_map"] as Dictionary).duplicate()
	SaveData.selected_map = str(_backup["selected_map"])
	SaveData.selected_vehicle = str(_backup["selected_vehicle"])
	# 道具本来就不落盘，但还是清一遍 —— 免得测试跑完在内存里留个背包
	SaveData.run_items.clear()
	SaveData.used_items.clear()
	SaveData.persist = true
	SaveData.save_data()
	print("  已还原最远 %d m，金币 %d" % [SaveData.best_distance, SaveData.total_coins])
