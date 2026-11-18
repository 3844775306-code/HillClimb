extends Node
## 经典 / 随机两种玩法模式。模式表和那段推理在 [constant Maps.MODES] 上面。
##
## 六节：
##   一 模式表和种子 —— 经典种子是个契约，随机种子每次都不一样
##   二 经典模式一点没变 —— 种子、地表和场景里的默认值逐位相同
##   三 随机模式真的是另一张图 —— 地表、金币油桶、特殊地形、沟全跟着种子走
##   四 同一种子重建出来一模一样 —— 换种子会整张重建，重建是幂等的
##   五 随机模式不写纪录、不领成就，金币照收（和经典模式对照着测）
##   六 选图页那两格开关 —— 几何、点击、Tab、卡片上那行字
##
## **全程 `persist = false`**：这一份不碰玩家真正的存档。落盘那一条在
## `tests/save.tscn` 里测（那边本来就有备份/还原一整套，见它的文件头）。
##
## 第 三 / 四 节都**开真的 `main.tscn`**，不是单独摆一块地形：要验的正是
## 「[method HillGame._ready] 那个种子真的落到了地形上」，只摆地形的话等于绕过它。

const MAIN := preload("res://scenes/main.tscn")
const SELECT := preload("res://scenes/mapselect.tscn")
const PICKUP := preload("res://scripts/pickup.gd")

## 无头视口是 1280×1280（README 坑 #7），量版面必须手工给尺寸，见 tests/mapselect。
const DESIGN := Vector2(1280.0, 720.0)

## 开局等几个**物理帧**。和 tests/vehicles_drive 同一个理由：地形区块的生成挂在
## 物理帧上，等渲染帧的话每轮推进的模拟时间都不一样，指纹会飘。
const WARMUP_FRAMES := 12

## 指纹里取样的：x 位置（地表高度）和区块下标（特殊地形、沟宽）。
## 高度是解析算的（[method HillTerrain.height_at] 不查区块），所以可以取到很远。
const SAMPLES: Array[float] = [100.0, 900.0, 1700.0, 2600.0, 3400.0, 5200.0, 7100.0, 9000.0, 13000.0]
const INDEXES: Array[int] = [3, 4, 5, 6, 7, 8, 9]

## 第五节的那一局：3000 米，也就是 6 个里程成就。
const RUN_METERS := 3000

var _failures := 0


func _ready() -> void:
	SaveData.persist = false
	SaveData.reset_progress()
	_test_tables()
	print("")
	await _test_classic_unchanged()
	print("")
	await _test_random_is_another_map()
	print("")
	await _test_rebuild_is_stable()
	print("")
	await _test_records()
	print("")
	_test_switch()
	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


# ---------------------------------------------------------------- 一 模式表和种子

func _test_tables() -> void:
	print("=== 模式表和种子 ===")
	_check("一共就两格", Maps.MODES.size() == 2, "%d 格" % Maps.MODES.size())
	_check("第一格是经典、第二格是随机",
			Maps.MODES[0] == Maps.MODE_CLASSIC and Maps.MODES[1] == Maps.MODE_RANDOM,
			"%s, %s" % [Maps.MODES[0], Maps.MODES[1]])
	# **这一条是契约**：纪录榜上每一个数字都长在这个种子的地形上，改了它等于把
	# 玩家的纪录挪到别人家的山上去（见 [constant Maps.CLASSIC_SEED]）。
	_check("经典种子还是 1337", Maps.CLASSIC_SEED == 1337, str(Maps.CLASSIC_SEED))
	_check("认不出来的模式退回经典", Maps.normalize_mode("乱写的") == Maps.MODE_CLASSIC,
			Maps.normalize_mode("乱写的"))
	var label: Dictionary = Maps.mode_label(Maps.MODE_RANDOM)
	_check("随机模式有中英两份名字", str(label["zh"]) != "" and str(label["en"]) != "",
			"%s / %s" % [label["zh"], label["en"]])

	# 随机种子：**每次调用都不一样**，而且不是经典种子。
	var seen := {}
	var repeats := 0
	var lo := 1 << 40
	var hi := 0
	for i in 300:
		var s := Maps.random_seed()
		if seen.has(s):
			repeats += 1
		seen[s] = true
		lo = mini(lo, s)
		hi = maxi(hi, s)
	_check("摇 300 次没有一次重复", repeats == 0, "%d 次重复" % repeats)
	_check("随机种子不会是经典种子", not seen.has(Maps.CLASSIC_SEED), "在里面" if seen.has(Maps.CLASSIC_SEED) else "不在")
	_check("随机种子都在正数范围内", lo > 0 and hi <= Maps.SEED_MAX,
			"%d … %d（上限 %d）" % [lo, hi, Maps.SEED_MAX])


# ---------------------------------------------------------------- 二 经典模式没变

func _test_classic_unchanged() -> void:
	print("=== 经典模式：一点没变 ===")
	# 基准：**场景里那块没有游戏节点管着的地形**（种子取 [constant Maps.CLASSIC_SEED]
	# 那个默认值）。它是「玩家一直在玩的那张图」的锚点 —— 游戏跑出来的经典模式地形
	# 和它逐位相同，才叫「一点没变」。
	var base := HillTerrain.new()
	base.world_seed = Maps.CLASSIC_SEED
	add_child(base)
	await get_tree().physics_frame

	var main: HillGame = await _open(Maps.PLAINS, Maps.MODE_CLASSIC)
	_check("开局拿到的是经典模式", main.mode == Maps.MODE_CLASSIC, main.mode)
	_check("地形的种子就是经典种子",
			main.terrain.world_seed == Maps.CLASSIC_SEED,
			"%d（期望 %d）" % [main.terrain.world_seed, Maps.CLASSIC_SEED])

	var diff := PackedStringArray()
	for x in SAMPLES:
		var got := main.terrain.height_at(x)
		var want := base.height_at(x)
		if not is_equal_approx(got, want):
			diff.append("x=%.0f：%.4f ≠ %.4f" % [x, got, want])
	_check("地表和场景默认种子逐位相同", diff.is_empty(),
			"比了 %d 处，全都一样" % SAMPLES.size() if diff.is_empty() else "；".join(diff))
	print("  x=%.0f 处地表 %.2f，起点 %.2f（这一份就是玩家的纪录榜所在的那座山）" % [
			SAMPLES[2], main.terrain.height_at(SAMPLES[2]),
			main.terrain.height_at(SAMPLES[0])])

	_clear(main)
	base.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- 三 随机就是另一张图

## 指纹：种子 + 地表高度 + 特殊地形 + 沟宽 + **金币油桶的位置**。
##
## 少任何一项都会漏掉一种半吊子实现：只换噪声不换金币（地表变了、金币还在原地）、
## 只换地表不换特殊地形（爬到一半发现桥搭在平地中间）等等。
func _fingerprint(main: HillGame) -> String:
	var parts := PackedStringArray()
	for x in SAMPLES:
		parts.append("%.4f" % main.terrain.height_at(x))
	for i in INDEXES:
		parts.append("%s/%.0f" % [main.terrain.feature_kind_at(i),
				Maps.gap_for(main.terrain.world_seed, main.terrain.map_id, i)])
	for node in main.terrain.get_children():
		for child in node.get_children():
			if child.get_script() == PICKUP:
				parts.append("%.0f,%.0f" % [(child as Node2D).position.x, (child as Node2D).position.y])
	return ",".join(parts)


func _test_random_is_another_map() -> void:
	print("=== 随机模式：每次都换一张图 ===")
	var prints := {}
	var seeds := PackedStringArray()
	var coins := PackedStringArray()
	for run in 3:
		var main: HillGame = await _open(Maps.PLAINS, Maps.MODE_RANDOM)
		var fp := _fingerprint(main)
		var coin_count := 0
		for node in main.terrain.get_children():
			for child in node.get_children():
				if child.get_script() == PICKUP:
					coin_count += 1
		seeds.append(str(main.terrain.world_seed))
		coins.append("%d 个" % coin_count)
		print("  第 %d 局：种子 %d，地表/金币/地形的指纹 %d 字符，拾取物 %d 个" % [
				run + 1, main.terrain.world_seed, fp.length(), coin_count])
		_check("第 %d 局的种子不是经典种子" % (run + 1),
				main.terrain.world_seed != Maps.CLASSIC_SEED, str(main.terrain.world_seed))
		prints[fp] = true
		_clear(main)
	_check("三局的种子两两不同", seeds.size() == 3 and prints.size() == 3,
			"种子 %s" % ", ".join(seeds))
	print("  三局的拾取物个数：%s（**个数也算指纹的一部分**，见上）" % ", ".join(coins))

	# 和经典模式也必须是两张图：不是「随机模式摇到一个 1337 才一样」，
	# 而是地表、金币、特殊地形处处都不同。
	var classic: HillGame = await _open(Maps.PLAINS, Maps.MODE_CLASSIC)
	var classic_fp := _fingerprint(classic)
	_check("随机的指纹和平原经典那套不一样", not prints.has(classic_fp),
			"三局都没撞上经典那一份")
	# 反向：经典模式连开两局，指纹必须**一模一样**（不然「经典」就不叫经典了）。
	var again: HillGame = await _open(Maps.PLAINS, Maps.MODE_CLASSIC)
	_check("经典模式连开两局指纹相同", _fingerprint(again) == classic_fp,
			"两局都是同一张图")
	_clear(again)
	_clear(classic)


# ---------------------------------------------------------------- 四 重建是幂等的

func _test_rebuild_is_stable() -> void:
	print("=== 同一种子重建出来一模一样 ===")
	var main: HillGame = await _open(Maps.PLAINS, Maps.MODE_RANDOM)
	var seed_before := main.terrain.world_seed
	var before := _fingerprint(main)

	# 再赋一次同一个种子：setter 会 `_configure_noise()` + `_rebuild()`，
	# 也就是走一遍「换种子」的完整路径。同一个种子重建出来必须逐位相同 ——
	# 不然镜头来回滚一趟（区块建了又拆、拆了又建）地图自己就变了。
	main.terrain.world_seed = seed_before
	await get_tree().physics_frame
	main.terrain._refresh_chunks()
	_check("同一个种子重建后指纹不变", _fingerprint(main) == before,
			"还是那 %d 个字符" % before.length())

	# 换一个种子：**必须整张换**。这一条盯的是「种子改了但噪声没重新配」那种 bug ——
	# 那样 `world_seed` 变了、地表却还是旧的那一张。
	var other := seed_before + 12345
	main.terrain.world_seed = other
	await get_tree().physics_frame
	main.terrain._refresh_chunks()
	_check("换种子之后地表跟着换", _fingerprint(main) != before,
			"种子 %d → %d" % [seed_before, other])
	_check("种子记下来了", main.terrain.world_seed == other, str(main.terrain.world_seed))
	_clear(main)


# ---------------------------------------------------------------- 五 成绩算不算数

## 同一套「跑到 3000 米、领成就、翻车结算」的调用，两种模式各走一遍。
##
## **必须成对**：只测随机模式的话，「什么都没写进存档」也可能是因为这条链根本没接上
## （游戏里从来就没有过纪录），那样测试是空的。经典那一半证明这条链是活的。
func _test_records() -> void:
	print("=== 成绩：经典算、随机不算 ===")
	var rows := {}
	for mode in Maps.MODES:
		SaveData.total_coins = 0
		SaveData.best_by_map[Maps.PLAINS] = 0
		SaveData.achieved_by_map[Maps.PLAINS] = 0
		SaveData.best_distance = 0

		var main: HillGame = await _open(Maps.PLAINS, mode)
		# 直接把「这一局跑出去多远」摆出来 —— 真开 3000 米要跑好几分钟，
		# 而这一节要验的是**结算那两步**，不是车能跑多远。
		main.car.max_distance = Maps.START_OFFSET + float(RUN_METERS) * Maps.PIXELS_PER_METER
		main._check_achievements(RUN_METERS)
		main._on_car_crashed(HillCar.REASON_CRASH)
		var ach := SaveData.achieved_of(Maps.PLAINS)
		var best := SaveData.best_of(Maps.PLAINS)
		rows[mode] = {"ach": ach, "best": best, "coins": main.coins}
		print("  %s：成就 %d 个，本图纪录 %d m，本局金币 %d" % [
				Maps.mode_label(mode)["zh"], ach, best, main.coins])
		_check("%s：这一局跑的是 %d 米" % [Maps.mode_label(mode)["zh"], RUN_METERS],
				main.distance_meters() == RUN_METERS, "%d 米" % main.distance_meters())
		_clear(main)

	var classic: Dictionary = rows[Maps.MODE_CLASSIC]
	var random: Dictionary = rows[Maps.MODE_RANDOM]
	var want_ach := Achievements.index_at(float(RUN_METERS))
	_check("经典：纪录写上去了", int(classic["best"]) == RUN_METERS, str(classic["best"]))
	_check("经典：成就领到了", int(classic["ach"]) == want_ach,
			"%d 个（期望 %d）" % [classic["ach"], want_ach])
	_check("经典：成就发了钱", int(classic["coins"]) > 0, str(classic["coins"]))
	_check("随机：纪录一个字没写", int(random["best"]) == 0, str(random["best"]))
	_check("随机：成就一个没领", int(random["ach"]) == 0, str(random["ach"]))
	_check("随机：成就没发钱", int(random["coins"]) == 0, str(random["coins"]))
	_check("随机：兼容字段也没动", SaveData.best_distance == 0, str(SaveData.best_distance))

	# 金币是**唯一**照收的东西（用户选的那条：随机模式只收金币）。
	var main: HillGame = await _open(Maps.PLAINS, Maps.MODE_RANDOM)
	SaveData.total_coins = 0
	main._award(120)
	_check("随机：吃到金币照常入账", SaveData.total_coins == 120, str(SaveData.total_coins))
	_clear(main)


# ---------------------------------------------------------------- 六 选图页的开关

func _test_switch() -> void:
	print("=== 选图页那两格开关 ===")
	var s: HillMapSelect = SELECT.instantiate()
	# 不挂进树：无头视口 1280×1280，版面得手工给尺寸才等于真实窗口下的答案。
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = DESIGN
	s._ready()

	var a := s.mode_rect(0)
	var b := s.mode_rect(1)
	print("  经典那格 %s，随机那格 %s" % [a, b])
	_check("两格并排不重叠", a.end.x <= b.position.x + 0.01 and absf(a.position.y - b.position.y) < 0.01,
			"间距 %.1f" % (b.position.x - a.end.x))
	_check("两格都在屏幕里",
			a.position.x >= 0.0 and b.end.x <= DESIGN.x and b.end.y <= DESIGN.y,
			"右沿 %.0f ≤ 宽 %.0f，下沿 %.0f ≤ 高 %.0f" % [b.end.x, DESIGN.x, b.end.y, DESIGN.y])
	# **开关不许压住可以点的别的东西**：它一压上卡片，点卡片就会变成切模式。
	var over := PackedStringArray()
	for slot in 2:
		var c := s.mode_rect(slot).get_center()
		if s._card_at(c) != -1:
			over.append("第 %d 格压到了卡 %d" % [slot, s._card_at(c) + 1])
		if s._arrow_at(c) != 0:
			over.append("第 %d 格压到了箭头" % slot)
	_check("开关不压在卡片和箭头上", over.is_empty(),
			"两格都在页脚" if over.is_empty() else "，".join(over))
	_check("自己那一格认得出来", s._mode_at(a.get_center()) == 0 and s._mode_at(b.get_center()) == 1,
			"%d / %d" % [s._mode_at(a.get_center()), s._mode_at(b.get_center())])
	_check("边上点一下什么都不是", s._mode_at(Vector2(DESIGN.x * 0.5, DESIGN.y - 10.0)) == -1,
			str(s._mode_at(Vector2(DESIGN.x * 0.5, DESIGN.y - 10.0))))

	# 点击：走 `_input`（真实入口），不是直接调 `_set_mode` —— 接线漏了要能红。
	SaveData.set_map_mode(Maps.MODE_CLASSIC)
	s._input(_click(b.get_center()))
	_check("点「随机」那格 → 存档里变成随机", SaveData.map_mode == Maps.MODE_RANDOM, SaveData.map_mode)
	s._input(_click(b.get_center()))
	_check("再点同一格是空操作（不会跳回去）", SaveData.map_mode == Maps.MODE_RANDOM, SaveData.map_mode)
	s._input(_click(a.get_center()))
	_check("点「经典」那格 → 变回经典", SaveData.map_mode == Maps.MODE_CLASSIC, SaveData.map_mode)

	# 键盘 / 手柄那两条路（手机上点，桌面上 Tab，手柄 Y）。
	s._on_key(KEY_TAB)
	_check("Tab 切到随机", SaveData.map_mode == Maps.MODE_RANDOM, SaveData.map_mode)
	s._on_pad(JOY_BUTTON_Y)
	_check("手柄 Y 再切回经典", SaveData.map_mode == Maps.MODE_CLASSIC, SaveData.map_mode)

	# 卡片底部那行字：随机模式不许再报「本图最远」—— 那是在另一张地形上跑出来的。
	SaveData.best_by_map[Maps.PLAINS] = 812
	SaveData.set_map_mode(Maps.MODE_CLASSIC)
	var classic_line := s.card_record_line(Maps.PLAINS)
	SaveData.set_map_mode(Maps.MODE_RANDOM)
	var random_line := s.card_record_line(Maps.PLAINS)
	print("  卡片底部：经典「%s」，随机「%s」" % [classic_line, random_line])
	_check("经典：卡片上写着本图最远", classic_line.contains("812"), classic_line)
	_check("随机：卡片上换了口气", random_line != classic_line and not random_line.contains("812"),
			random_line)

	# 页脚那行说明也得跟着换，不然玩家在选图页根本不知道「随机」是什么意思。
	var note: Dictionary = Maps.mode_note(SaveData.map_mode)
	print("  页脚说明：%s" % note["zh"])
	_check("随机模式的说明里写了金币和纪录这两件事",
			str(note["zh"]).contains("金币") and str(note["zh"]).contains("纪录"), note["zh"])
	s.free()


# ---------------------------------------------------------------- 工具

## 按指定的地图和模式开一局，等固定个数的物理帧。
##
## 地形区块的刷新挂到物理帧上（和 tests/vehicles_drive 一样）：`_process` 那一路
## 每渲染帧刷一次，而渲染帧和物理步的比是看机器脸色的，结果会飘。
func _open(map_id: String, mode: String) -> HillGame:
	SaveData.selected_map = map_id
	SaveData.map_mode = mode
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	main.terrain.set_process(false)
	for i in WARMUP_FRAMES:
		await get_tree().physics_frame
		main.terrain._refresh_chunks()
	main.car.fuel = 1.0e9
	return main


## 收掉一局。**先 `remove_child` 再 `queue_free`**：只 queue_free 的话，旧车会和
## 下一局的新车在同一个出生点上活到帧末，两辆车会互相挤开（见 tests/vehicles_drive）。
func _clear(main: HillGame) -> void:
	if main == null or not is_instance_valid(main):
		return
	remove_child(main)
	main.queue_free()


func _click(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	return ev
