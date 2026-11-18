extends Node
## 存档（scripts/save_data.gd）的读写往返测试。
##
## 会真的往 user://save.cfg 写盘 —— 因为「写完能不能读回来」正是要测的东西，
## 用 mock 就测不到了。所以开头先把玩家现有的战绩备份下来，结尾原样写回去，
## 不留痕迹。

var _backup := {}
var _failures := 0


func _ready() -> void:
	print("存档路径 %s" % ProjectSettings.globalize_path(SaveData.SAVE_PATH))
	print("")

	await _backup_existing()
	await _round_trip()
	await _submit_semantics()
	await _coin_accumulation()
	await _upgrade_semantics()
	await _per_vehicle_levels()
	await _legacy_upgrade_migration()
	await _persist_switch()
	await _restore()

	print("")
	if _failures == 0:
		print("全部通过")
	else:
		print("!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	# 必须显式写 bool：两个 Variant 比较的结果推断不出类型，:= 会解析报错
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _backup_existing() -> void:
	print("=== 备份现有存档 ===")
	SaveData.load_data()
	_backup = {
		"best": SaveData.best_distance,
		"coins": SaveData.total_coins,
		# **deep duplicate**：升级等级现在是 `{车: {项: 级}}` 的嵌套表，浅拷贝
		# 只复制了外层，里层那些表和 SaveData 里的是同一个对象 —— 下面几节随手
		# 改一个等级，备份也跟着变，「还原」就等于没还原。
		"levels": SaveData.levels.duplicate(true),
		# 按图分开的纪录、选中的地图和车也必须备份：下面几节会随手改写它们，
		# 而 save_data() 是整份覆盖写盘 —— 漏了这几项，跑一次测试就把
		# 玩家每张图的成绩、选图、选车一起冲掉了。
		"best_by_map": SaveData.best_by_map.duplicate(),
		"selected_map": SaveData.selected_map,
		"selected_vehicle": SaveData.selected_vehicle,
		# 玩法模式（经典 / 随机）也是玩家自己拨的开关，而且**会落盘** ——
		# 下面几节随手改成随机，不备份的话跑一次测试就把玩家的选图页拨到随机了。
		"map_mode": SaveData.map_mode,
	}
	var lv := PackedStringArray()
	for id in Upgrades.IDS:
		lv.append("%s Lv%d" % [Upgrades.TRACKS[id]["zh"], SaveData.level_of(id)])
	var rec := PackedStringArray()
	for id in Maps.IDS:
		rec.append("%s %d m" % [Maps.get_map(id)["zh"], SaveData.best_of(id)])
	print("  %s：最远 %d m   金币 %d   %s" % [
		Vehicles.get_vehicle(SaveData.selected_vehicle)["zh"],
		_backup["best"], _backup["coins"], "  ".join(lv),
	])
	print("  各图纪录 %s   选中 %s" % [
		"  ".join(rec), Maps.get_map(SaveData.selected_map)["zh"],
	])
	SaveData.persist = true


## 写下去 → 清空内存 → 读回来。这才是「存档」区别于「变量」的地方。
func _round_trip() -> void:
	print("")
	print("=== 写盘 → 清内存 → 读回 ===")
	SaveData.best_distance = 4321
	SaveData.total_coins = 777
	# 等级**按车分开**，所以这里必须指明是哪辆车，不能靠「当前选中那辆」——
	# 玩家可能正选着摩托，那样写下去的是摩托的表，读回来拿默认车断言就成了
	# 冤枉失败。顺手给另一辆车写一份不一样的，验「两辆车互不串味」。
	SaveData.levels_of(Vehicles.DEFAULT)["engine"] = 3
	SaveData.levels_of(Vehicles.DEFAULT)["agility"] = 2
	# 这一项必须**显式写 0**，不能靠「玩家大概没买过油箱」。等级是从玩家存档读进
	# 内存的，玩家真买了油箱（实测撞上过：他买到 Lv2），下面那句断言就会把玩家的
	# 合法存档报成失败。测试要断言的是「写下去的 0 能读回 0」，不是玩家攒了什么。
	SaveData.levels_of(Vehicles.DEFAULT)["fuel"] = 0
	# 玩法模式也要走一趟盘：它不是消耗品，是个要记住的偏好（见 [member SaveData.map_mode]）。
	SaveData.map_mode = Maps.MODE_RANDOM
	var other := _other_vehicle()
	if other != "":
		SaveData.levels_of(other)["engine"] = Upgrades.MAX_LEVEL
		# 和上面 fuel 那行同一个坑，只是踩在另一辆车上：断言「另一辆车没被默认车
		# 串味」时读的是 agility，而那项**玩家自己可能买过** —— 实测撞上过，玩家在
		# 摩托上把敏捷练到 Lv7，下面那句断言就把他的合法存档报成失败。
		# 测的是「写下去的 0 能读回 0」，所以这一项也必须**显式写 0**。
		SaveData.levels_of(other)["agility"] = 0
	SaveData.save_data()

	# 清内存，好让下面读到的东西只可能来自盘上。注意 reset_progress() 自己会写盘，
	# 那会把这轮刚写下去的数据覆盖掉，所以清的这几步必须先关掉落盘。
	SaveData.persist = false
	SaveData.best_distance = 0
	SaveData.total_coins = 0
	SaveData.reset_progress()   # 等级也归零，不然「读回 3 级」可能只是内存里剩的
	SaveData.persist = true
	SaveData.load_data()

	_check("最远里程", SaveData.best_distance, 4321)
	_check("金币总数", SaveData.total_coins, 777)
	_check("引擎等级", SaveData.level_of("engine", Vehicles.DEFAULT), 3)
	_check("敏捷等级", SaveData.level_of("agility", Vehicles.DEFAULT), 2)
	_check("没买过的项是 Lv0", SaveData.level_of("fuel", Vehicles.DEFAULT), 0)
	# reset_progress() 会把内存里的模式抹回经典，所以这一条读到 RANDOM 只可能来自盘上。
	_check("玩法模式", SaveData.map_mode, Maps.MODE_RANDOM)
	if other != "":
		_check("%s 的引擎等级是它自己的" % other,
				SaveData.level_of("engine", other), Upgrades.MAX_LEVEL)
		_check("%s 没被默认车串味" % other, SaveData.level_of("agility", other), 0)
	print("  存档文件存在：%s" % FileAccess.file_exists(SaveData.SAVE_PATH))


## submit_distance 只在**严格超过**时才返回 true，并且顺手刷新纪录。
func _submit_semantics() -> void:
	print("")
	print("=== 破纪录判定 ===")
	SaveData.best_by_map[Maps.PLAINS] = 500
	SaveData.best_distance = 500
	_check("499 m 不算破纪录", SaveData.submit_distance(499, Maps.PLAINS), false)
	_check("500 m 平纪录不算", SaveData.submit_distance(500, Maps.PLAINS), false)
	_check("501 m 算破纪录", SaveData.submit_distance(501, Maps.PLAINS), true)
	_check("纪录已刷新", SaveData.best_of(Maps.PLAINS), 501)
	_check("兼容字段也跟上", SaveData.best_distance, 501)
	_check("再交 501 m 不算", SaveData.submit_distance(501, Maps.PLAINS), false)
	_submit_per_map()


## 四张图的纪录互不干扰 —— 这是按图分开记的全部意义。
##
## 反例（混着记）会让雪地永远看不见天日：雪地打滑、荒漠有阻力，成绩天然比平原低，
## 一个全局纪录会把它们全吃掉。所以这里断言的是**隔离**：雪地的高分不改平原的，
## 平原的高分也不改雪地的。
func _submit_per_map() -> void:
	print("")
	print("=== 各图纪录隔离 ===")
	for id in Maps.IDS:
		SaveData.best_by_map[id] = 0
	SaveData.best_distance = 0
	_check("雪地 300 m 破纪录", SaveData.submit_distance(300, Maps.SNOW), true)
	_check("雪地纪录 = 300", SaveData.best_of(Maps.SNOW), 300)
	_check("平原纪录没被雪地动过", SaveData.best_of(Maps.PLAINS), 0)
	_check("平原 100 m 也算破纪录（各比各的）", SaveData.submit_distance(100, Maps.PLAINS), true)
	_check("平原纪录 = 100", SaveData.best_of(Maps.PLAINS), 100)
	_check("雪地纪录仍是 300", SaveData.best_of(Maps.SNOW), 300)
	_check("跨图不误判：拿平原的 100 去交雪地",
			SaveData.submit_distance(100, Maps.SNOW), false)
	# 兼容字段只跟平原走，别的图不该把它顶上去
	_check("荒漠 900 m 不动 best_distance", SaveData.submit_distance(900, Maps.DESERT), true)
	_check("best_distance 还是平原的 100", SaveData.best_distance, 100)


## 金币是累加的，不是覆盖的。
func _coin_accumulation() -> void:
	print("")
	print("=== 金币累加 ===")
	SaveData.total_coins = 10
	SaveData.add_coins(1)
	SaveData.add_coins(1)
	SaveData.add_coins(5)
	_check("10 + 1 + 1 + 5", SaveData.total_coins, 17)
	# 累加之后要已经落盘
	SaveData.total_coins = 0
	SaveData.load_data()
	_check("重新读盘后仍是累加值", SaveData.total_coins, 17)


## 升级：花销曲线、买不起、满级封顶、扣钱、落盘。
func _upgrade_semantics() -> void:
	print("")
	print("=== 升级购买 ===")
	SaveData.reset_progress()

	var costs := PackedStringArray()
	var expected := 0
	for lv in range(Upgrades.MAX_LEVEL):
		costs.append(str(SaveData.upgrade_cost("engine")))
		expected += Upgrades.cost(lv)
		SaveData.total_coins = 99999
		SaveData.buy_upgrade("engine")
	print("  引擎各级花销 %s（合计 %d）" % [" / ".join(costs), expected])
	_check("花销曲线与 Upgrades 一致", expected, Upgrades.total_cost())
	_check("连买到满级（%d 次）" % Upgrades.MAX_LEVEL, SaveData.level_of("engine"), Upgrades.MAX_LEVEL)
	_check("满级后 upgrade_cost 归零", SaveData.upgrade_cost("engine"), 0)
	_check("满级后再买返回 false", SaveData.buy_upgrade("engine"), false)

	SaveData.reset_progress()
	SaveData.total_coins = Upgrades.cost(0) - 1
	_check("差 1 币买不起", SaveData.can_afford("engine"), false)
	_check("买不起时 buy 返回 false", SaveData.buy_upgrade("engine"), false)
	_check("买不起时等级不变", SaveData.level_of("engine"), 0)
	_check("买不起时不扣钱", SaveData.total_coins, Upgrades.cost(0) - 1)

	SaveData.total_coins = Upgrades.cost(0)
	_check("刚好够就能买", SaveData.buy_upgrade("engine"), true)
	_check("买完扣钱归零", SaveData.total_coins, 0)
	_check("买完等级 +1", SaveData.level_of("engine"), 1)

	# 落盘：升级是买了就写，不是等一局结束
	SaveData.load_data()
	_check("等级已落盘", SaveData.level_of("engine"), 1)


## 车表里第一辆不是默认车的车 id。只有一辆车时返回 ""，调用方的断言就整段跳过
## （那时「按车分开」还没有第二辆车可以对照）。
func _other_vehicle() -> String:
	for id in Vehicles.IDS:
		if id != Vehicles.DEFAULT:
			return id
	return ""


## 升级按车分开：在一辆车上买的等级，另一辆车上一级都不该有；金币是共用的。
func _per_vehicle_levels() -> void:
	print("")
	print("=== 升级按车分开 ===")
	var other := _other_vehicle()
	if other == "":
		print("  车表里只有一辆车，跳过（没有第二辆可以对照）")
		return
	print("  对照组：%s vs %s" % [
		Vehicles.get_vehicle(Vehicles.DEFAULT)["zh"], Vehicles.get_vehicle(other)["zh"],
	])

	SaveData.reset_progress()
	SaveData.total_coins = 99999

	# 只给默认车买，另一辆必须纹丝不动
	SaveData.buy_upgrade("engine", Vehicles.DEFAULT)
	SaveData.buy_upgrade("engine", Vehicles.DEFAULT)
	_check("默认车买到 Lv2", SaveData.level_of("engine", Vehicles.DEFAULT), 2)
	_check("另一辆车仍是 Lv0", SaveData.level_of("engine", other), 0)
	_check("另一辆车没被顺手扣钱", SaveData.total_coins,
			99999 - Upgrades.cost(0) - Upgrades.cost(1))

	# 再给另一辆买，两边各记各的
	SaveData.buy_upgrade("engine", other)
	_check("另一辆车买到 Lv1", SaveData.level_of("engine", other), 1)
	_check("默认车不受影响", SaveData.level_of("engine", Vehicles.DEFAULT), 2)

	# 价格是按**那辆车自己的**等级算的：默认车要第 3 级的价，另一辆才第 2 级
	_check("默认车下一级要第 3 级的价",
			SaveData.upgrade_cost("engine", Vehicles.DEFAULT), Upgrades.cost(2))
	_check("另一辆车下一级只要第 2 级的价", SaveData.upgrade_cost("engine", other), Upgrades.cost(1))

	# 换车不改等级，改的是「level_of 不带参数时看哪辆车」
	SaveData.select_vehicle(other)
	_check("换车后不带参数读到的是新车", SaveData.level_of("engine"), 1)
	SaveData.select_vehicle(Vehicles.DEFAULT)
	_check("换回来读到的还是老车", SaveData.level_of("engine"), 2)

	# 落盘 → 清空 → 读回，两辆车的表都得原样回来
	SaveData.save_data()
	SaveData.levels.clear()
	SaveData.load_data()
	_check("读回：默认车 Lv2", SaveData.level_of("engine", Vehicles.DEFAULT), 2)
	_check("读回：另一辆车 Lv1", SaveData.level_of("engine", other), 1)


## 老存档兼容：加多车之前 `[upgrades]` 是**平表**（`engine=3`，没有车名前缀）。
## 那些等级是玩家在唯一那辆车（就是默认车）上买的，读回来必须挂到它名下 ——
## 否则一次升级就白送给玩家一辆清空的车。
##
## 这条路径**只走一次**：新格式存盘时不写老键，所以它下次就消失了。
## 这也正是要在这里断言「老键确实没被写出去」的原因，否则兼容代码会永远活着。
func _legacy_upgrade_migration() -> void:
	print("")
	print("=== 老存档（无车名前缀的升级键）迁移 ===")
	var other := _other_vehicle()

	# 手工造一份老格式的档：只有平表升级键 + 一点金币，没有 [vehicle] 段
	SaveData.persist = false
	var cfg := ConfigFile.new()
	cfg.set_value(SaveData.UPGRADE_SECTION, "engine", 3)
	cfg.set_value(SaveData.UPGRADE_SECTION, "speed", 1)
	cfg.set_value(SaveData.SECTION, "total_coins", 555)
	_check("写出老格式档", cfg.save(SaveData.SAVE_PATH), OK)

	SaveData.persist = true
	SaveData.load_data()
	_check("金币也读回来了", SaveData.total_coins, 555)
	_check("默认车继承老档的引擎等级", SaveData.level_of("engine", Vehicles.DEFAULT), 3)
	_check("默认车继承老档的极速等级", SaveData.level_of("speed", Vehicles.DEFAULT), 1)
	_check("老档里没买过的项仍是 Lv0", SaveData.level_of("fuel", Vehicles.DEFAULT), 0)
	if other != "":
		_check("别的车不会平白继承老档的等级", SaveData.level_of("engine", other), 0)

	# 存一次盘：老键该消失，换成带车名前缀的新键
	SaveData.save_data()
	var back := ConfigFile.new()
	_check("重新读出存档", back.load(SaveData.SAVE_PATH), OK)
	_check("老键已不再写出",
			back.has_section_key(SaveData.UPGRADE_SECTION, "engine"), false)
	_check("新键已经写出",
			back.has_section_key(SaveData.UPGRADE_SECTION,
					SaveData.upgrade_key(Vehicles.DEFAULT, "engine")), true)


## persist = false 时必须一个字节都不写 —— 测试和演示都靠它避免污染存档。
func _persist_switch() -> void:
	print("")
	print("=== persist = false 不写盘 ===")
	SaveData.best_distance = 999
	SaveData.total_coins = 999
	SaveData.current_levels()["engine"] = 1
	SaveData.save_data()          # 落盘 999

	SaveData.persist = false
	SaveData.best_distance = 11111
	SaveData.total_coins = 11111
	SaveData.current_levels()["engine"] = Upgrades.MAX_LEVEL
	SaveData.save_data()          # 应该什么都不做

	SaveData.load_data()
	_check("盘上仍是最早的 999", SaveData.best_distance, 999)
	_check("金币也未被改写", SaveData.total_coins, 999)
	_check("升级等级也没被改写", SaveData.level_of("engine"), 1)
	SaveData.persist = true


func _restore() -> void:
	print("")
	print("=== 还原玩家存档 ===")
	SaveData.best_distance = int(_backup["best"])
	SaveData.total_coins = int(_backup["coins"])
	SaveData.levels = (_backup["levels"] as Dictionary).duplicate(true)
	SaveData.best_by_map = (_backup["best_by_map"] as Dictionary).duplicate()
	SaveData.selected_map = str(_backup["selected_map"])
	SaveData.selected_vehicle = str(_backup["selected_vehicle"])
	SaveData.map_mode = Maps.normalize_mode(str(_backup["map_mode"]))
	SaveData.save_data()
	var lv := PackedStringArray()
	for id in Upgrades.IDS:
		lv.append("%s Lv%d" % [Upgrades.TRACKS[id]["zh"], SaveData.level_of(id)])
	var rec := PackedStringArray()
	for id in Maps.IDS:
		rec.append("%s %d m" % [Maps.get_map(id)["zh"], SaveData.best_of(id)])
	print("  已还原最远 %d m   金币 %d   %s" % [
		SaveData.best_distance, SaveData.total_coins, "  ".join(lv),
	])
	print("  已还原各图纪录 %s   选中 %s" % [
		"  ".join(rec), Maps.get_map(SaveData.selected_map)["zh"],
	])
