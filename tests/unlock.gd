extends Node
## 解锁（图 [constant Maps.UNLOCK_PRICE] / 车 [constant Vehicles.UNLOCK_PRICE]）的规则测试。
##
## 五节：
##   1. 价钱表 —— 前几张白送、其余一个价、不认识的 id 不算免费
##   2. 买      —— 扣钱、不重复扣、不够钱不扣、不顺手改选中的图/车
##   3. 落盘    —— 买过的读得回来，**没买的不写进文件**
##   4. 全新档  —— `reset_progress()` 之后只剩白送的
##   5. 老档    —— **玩过的就算已解锁**，以及坏掉的选中项怎么修
##
## 会真的往 user://save.cfg 写盘 —— 「买完了下次开机还在不在」正是要测的东西，
## 用 mock 就测不到了。所以开头顶一份**原始字节**，结尾原样写回去。
##
## 备份的是**整个文件**，不是逐个字段（`tests/save` 那份是逐个字段列的）：
## `save_data()` 是整份覆盖写盘，将来存档多一个字段，按字段备份的写法就会漏掉它，
## 而漏掉的后果是「跑一次测试把玩家的进度冲掉」。

const SECTION := "record"
const MAP_SECTION := "maps"
const VEHICLE_SECTION := "vehicle"
const UPGRADE_SECTION := "upgrades"

var _failures := 0
var _had_save := false
var _backup := PackedByteArray()


func _ready() -> void:
	print("存档路径 %s" % ProjectSettings.globalize_path(SaveData.SAVE_PATH))
	print("")
	_backup_save()
	SaveData.persist = true

	_test_prices()
	print("")
	_test_buy()
	print("")
	_test_persist()
	print("")
	_test_fresh()
	print("")
	_test_old_save()

	_restore_save()
	SaveData.persist = false

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


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveData.SAVE_PATH)
	if not _had_save:
		return
	var f := FileAccess.open(SaveData.SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	_backup = f.get_buffer(f.get_length())
	f.close()


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SaveData.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_backup)
			f.close()
	else:
		DirAccess.remove_absolute(SaveData.SAVE_PATH)
	SaveData.load_data()


# ---------------------------------------------------------------- 价钱表

func _test_prices() -> void:
	print("=== 价钱表 ===")
	_check("白送的和收费的都得有", Maps.FREE_COUNT > 0
			and Maps.FREE_COUNT < Maps.IDS.size()
			and Vehicles.FREE_COUNT > 0
			and Vehicles.FREE_COUNT < Vehicles.IDS.size(),
			"图 %d / %d 张白送，车 %d / %d 辆白送" % [
				Maps.FREE_COUNT, Maps.IDS.size(), Vehicles.FREE_COUNT, Vehicles.IDS.size()])
	# 全新档开出来就是这张图、这辆车（[method SaveData.reset_progress]）。它们要是
	# 收费的，玩家一进来就踩在一张没解锁的图上。
	_check("默认选的图/车都在白送的那批里",
			Maps.is_free(Maps.PLAINS) and Vehicles.is_free(Vehicles.DEFAULT),
			"平原 / %s 都是白送的" % Vehicles.DEFAULT)

	var bad := PackedStringArray()
	for i in range(Maps.IDS.size()):
		var id: String = Maps.IDS[i]
		var want := 0 if i < Maps.FREE_COUNT else Maps.UNLOCK_PRICE
		if Maps.price_of(id) != want or Maps.is_free(id) != (want == 0):
			bad.append("%s 标价 %d" % [id, Maps.price_of(id)])
	for i in range(Vehicles.IDS.size()):
		var id: String = Vehicles.IDS[i]
		var want := 0 if i < Vehicles.FREE_COUNT else Vehicles.UNLOCK_PRICE
		if Vehicles.price_of(id) != want or Vehicles.is_free(id) != (want == 0):
			bad.append("%s 标价 %d" % [id, Vehicles.price_of(id)])
	_check("每张图/每辆车都按「前几个白送、其余一个价」标价", bad.is_empty(),
			"图 %d 张：前 %d 张 0、其余 %d；车 %d 辆：前 %d 辆 0、其余 %d" % [
				Maps.IDS.size(), Maps.FREE_COUNT, Maps.UNLOCK_PRICE,
				Vehicles.IDS.size(), Vehicles.FREE_COUNT, Vehicles.UNLOCK_PRICE]
			if bad.is_empty() else "，".join(bad))

	# 不认识的 id：**不算免费**。这一条是权限判断的兜底方向，不能反。
	SaveData.reset_progress()
	_check("不认识的图既不免费、也不算解锁",
			not Maps.is_free("atlantis") and not SaveData.map_unlocked("atlantis")
			and Maps.price_of("atlantis") == 0,
			"is_free=%s unlocked=%s price=%d" % [Maps.is_free("atlantis"),
				SaveData.map_unlocked("atlantis"), Maps.price_of("atlantis")])
	_check("不认识的车既不免费、也不算解锁",
			not Vehicles.is_free("hovercraft") and not SaveData.vehicle_unlocked("hovercraft"),
			"is_free=%s unlocked=%s" % [Vehicles.is_free("hovercraft"),
				SaveData.vehicle_unlocked("hovercraft")])


# ---------------------------------------------------------------- 买

func _test_buy() -> void:
	print("=== 买 ===")
	SaveData.reset_progress()
	var mid: String = Maps.IDS[Maps.FREE_COUNT]          # 第一张收费的
	var car: String = Vehicles.IDS[Vehicles.FREE_COUNT]  # 第一辆收费的

	# 买不起：一分钱都不能动，也不能解锁。
	SaveData.total_coins = Maps.UNLOCK_PRICE - 1
	_check("钱不够买不下来", not SaveData.unlock_map(mid)
			and not SaveData.map_unlocked(mid)
			and SaveData.total_coins == Maps.UNLOCK_PRICE - 1,
			"金币 %d / 要 %d，仍然锁着" % [SaveData.total_coins, Maps.UNLOCK_PRICE])

	# 钱够：扣掉标价，解锁，**选中的图不动**（买和选是两件事）。
	var before_sel := SaveData.selected_map
	SaveData.total_coins = Maps.UNLOCK_PRICE + 30
	_check("钱够就买下来了", SaveData.unlock_map(mid) and SaveData.map_unlocked(mid)
			and SaveData.total_coins == 30,
			"金币 %d（期望 30），「%s」已解锁" % [SaveData.total_coins, mid])
	_check("买图不改选中的图", SaveData.selected_map == before_sel
			and SaveData.map_price(mid) == 0,
			"选中还是 %s，买下的那张价钱归 0" % SaveData.selected_map)

	# 再买一次：不能重复扣钱。界面那边其实点第二下走的是「进图」，
	# 但存档这一层也得自己守住 —— 万一哪天界面漏了一处判断。
	SaveData.total_coins = Maps.UNLOCK_PRICE
	_check("已经解锁的再买一次不扣钱", not SaveData.unlock_map(mid)
			and SaveData.total_coins == Maps.UNLOCK_PRICE,
			"金币 %d（期望 %d）" % [SaveData.total_coins, Maps.UNLOCK_PRICE])
	_check("白送的图买不了（也没得买）", not SaveData.unlock_map(Maps.IDS[0])
			and SaveData.total_coins == Maps.UNLOCK_PRICE,
			"金币没动：%d" % SaveData.total_coins)
	_check("不认识的图买不了", not SaveData.unlock_map("atlantis")
			and SaveData.total_coins == Maps.UNLOCK_PRICE,
			"金币没动：%d" % SaveData.total_coins)

	# 车：同一套规矩。**换车不改里程纪录**（纪录不按车分）。
	var best := SaveData.best_of(SaveData.selected_map)
	SaveData.total_coins = Vehicles.UNLOCK_PRICE - 1
	_check("车钱不够也买不下来", not SaveData.unlock_vehicle(car)
			and not SaveData.vehicle_unlocked(car)
			and SaveData.total_coins == Vehicles.UNLOCK_PRICE - 1,
			"金币 %d / 要 %d" % [SaveData.total_coins, Vehicles.UNLOCK_PRICE])
	SaveData.total_coins = Vehicles.UNLOCK_PRICE
	_check("车钱够就买下来了", SaveData.unlock_vehicle(car)
			and SaveData.vehicle_unlocked(car) and SaveData.total_coins == 0,
			"金币 %d（期望 0），「%s」已解锁" % [SaveData.total_coins, car])
	_check("买车不改选中的车、也不碰纪录",
			SaveData.selected_vehicle == Vehicles.DEFAULT
			and SaveData.best_of(SaveData.selected_map) == best,
			"选中还是 %s，纪录还是 %d m" % [SaveData.selected_vehicle, best])
	_check("不认识的、白送的车都买不了",
			not SaveData.unlock_vehicle("hovercraft")
			and not SaveData.unlock_vehicle(Vehicles.IDS[0]),
			"两条都返回 false")

	# 存档里的升级等级是按车分的，买车**不送**升级。
	var lv := 0
	for id in Upgrades.IDS:
		lv += SaveData.level_of(id, car)
	_check("买下来的车是原厂车", lv == 0, "「%s」各项升级合计 %d 级" % [car, lv])


# ---------------------------------------------------------------- 落盘

func _test_persist() -> void:
	print("=== 落盘 ===")
	SaveData.reset_progress()
	var mid: String = Maps.IDS[Maps.FREE_COUNT]
	var car: String = Vehicles.IDS[Vehicles.FREE_COUNT]
	SaveData.total_coins = Maps.UNLOCK_PRICE + Vehicles.UNLOCK_PRICE
	SaveData.unlock_map(mid)
	SaveData.unlock_vehicle(car)

	# 文件里长什么样 —— 顺手把键名钉住（改键名等于让老玩家的购买记录失效）。
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SaveData.SAVE_PATH) == OK
	_check("买过的东西写进了 [unlocked] 段",
			loaded and bool(cfg.get_value(SaveData.UNLOCK_SECTION, "map_" + mid, false))
			and bool(cfg.get_value(SaveData.UNLOCK_SECTION, "car_" + car, false)),
			"map_%s / car_%s 都是 true" % [mid, car])
	# **只写买过的**：白送的靠 `is_free()` 推出来。写进去的话，以后把某张图改成免费
	# 就得清理一批旧键，而漏清的那个键会让「免费」和「买过」两处说法打架。
	var free_written := PackedStringArray()
	for i in range(Maps.FREE_COUNT):
		if cfg.has_section_key(SaveData.UNLOCK_SECTION, "map_" + Maps.IDS[i]):
			free_written.append(Maps.IDS[i])
	for i in range(Vehicles.FREE_COUNT):
		if cfg.has_section_key(SaveData.UNLOCK_SECTION, "car_" + Vehicles.IDS[i]):
			free_written.append(Vehicles.IDS[i])
	_check("白送的图/车不写进文件", free_written.is_empty(),
			"只写了 %s / %s" % [mid, car] if free_written.is_empty()
			else "多写了：%s" % "，".join(free_written))

	# 重新装档（等于下次开机）：买过的还在。
	SaveData.bought_maps.clear()
	SaveData.bought_vehicles.clear()
	SaveData.load_data()
	_check("重开一次，买过的图和车还在",
			SaveData.map_unlocked(mid) and SaveData.vehicle_unlocked(car),
			"「%s」和「%s」都还是解锁的" % [mid, car])
	# 没买过的**不能被带出来**：`load_data` 是先清空再读的。
	_check("没买过的没被带出来",
			not SaveData.map_unlocked(Maps.IDS[Maps.FREE_COUNT + 1]),
			"「%s」仍然锁着" % Maps.IDS[Maps.FREE_COUNT + 1])

	# 全新档存档里没有 [unlocked] 段时，装档不该炸、也不该冒出解锁的东西。
	SaveData.reset_progress()
	_check("reset 之后只剩白送的",
			not SaveData.map_unlocked(mid) and not SaveData.vehicle_unlocked(car)
			and SaveData.bought_maps.is_empty() and SaveData.bought_vehicles.is_empty(),
			"「%s」「%s」都回到锁着" % [mid, car])


# ---------------------------------------------------------------- 全新档

func _test_fresh() -> void:
	print("=== 全新档 ===")
	SaveData.reset_progress()
	var locked := PackedStringArray()
	for i in range(Maps.IDS.size()):
		if i >= Maps.FREE_COUNT and SaveData.map_unlocked(Maps.IDS[i]):
			locked.append(Maps.IDS[i])
	for i in range(Vehicles.IDS.size()):
		if i >= Vehicles.FREE_COUNT and SaveData.vehicle_unlocked(Vehicles.IDS[i]):
			locked.append(Vehicles.IDS[i])
	_check("全新档只有白送的能开", locked.is_empty(),
			"图 %d 张、车 %d 辆能开" % [Maps.FREE_COUNT, Vehicles.FREE_COUNT]
			if locked.is_empty() else "多开了：%s" % "，".join(locked))
	_check("全新档选中的是白送的图和车",
			SaveData.map_unlocked(SaveData.selected_map)
			and SaveData.vehicle_unlocked(SaveData.selected_vehicle),
			"%s / %s" % [SaveData.selected_map, SaveData.selected_vehicle])
	# 白送的价钱是 0，其余是标价 —— 界面上就是这么显的。
	_check("全新档的价钱：白送 0、其余标价",
			SaveData.map_price(Maps.IDS[0]) == 0
			and SaveData.map_price(Maps.IDS[Maps.FREE_COUNT]) == Maps.UNLOCK_PRICE
			and SaveData.vehicle_price(Vehicles.IDS[Vehicles.FREE_COUNT])
					== Vehicles.UNLOCK_PRICE,
			"平原 0 / 第一张收费的 %d / 第一辆收费的 %d" % [
				SaveData.map_price(Maps.IDS[Maps.FREE_COUNT]),
				SaveData.vehicle_price(Vehicles.IDS[Vehicles.FREE_COUNT])])


# ---------------------------------------------------------------- 老档

## 这一版之前的存档：`[unlocked]` 段根本不存在，那时候所有图和车都是随便选的。
##
## 和玩家确认过的规则是**玩过的就算已解锁**：图上有成绩、车上花过升级钱，或者它
## 就是存档里选中那辆（刚买来还没改就退出了）。不这么办的话，一个跑了 20000 米的
## 老玩家升到新版，那张图会当场变成 50000 金币 —— 把人家已有的成绩锁起来收费。
##
## 另一件事是**坏掉的选中项**：老档可能正好停在一张写着「要钱」的图上。不清掉的话
## 玩家一按「继续」就开进一张没解锁的图 —— 那是界面之外的入口，选图界面拦不住。
func _test_old_save() -> void:
	print("=== 老档 ===")

	# 一、玩过的/改过的：都该白送；选中的也留着。
	var played := Maps.IDS[Maps.FREE_COUNT]        # 这张有成绩
	var upgraded := Vehicles.IDS[Vehicles.FREE_COUNT]  # 这辆改过
	var picked := Vehicles.IDS[Vehicles.FREE_COUNT + 1]  # 这辆只是被选中了
	var up_id: String = Upgrades.IDS[0]
	_write_save(played, picked, {played: 500}, {upgraded: {up_id: 1}})
	SaveData.load_data()
	_check("老档里跑过成绩的图算是已解锁",
			SaveData.map_unlocked(played) and SaveData.bought_maps.has(played),
			"「%s」有 500 米纪录 → 已解锁" % played)
	_check("老档里改过的车算是已解锁",
			SaveData.vehicle_unlocked(upgraded) and SaveData.bought_vehicles.has(upgraded),
			"「%s」有一级改装 → 已解锁" % upgraded)
	_check("老档里选中但没改过的车也算已解锁",
			SaveData.vehicle_unlocked(picked) and SaveData.bought_vehicles.has(picked),
			"「%s」只是被选中 → 也算已解锁" % picked)
	_check("老档选中的图没被改掉", SaveData.selected_map == played,
			"选中 %s（期望 %s）" % [SaveData.selected_map, played])
	_check("老档选中的车没被改掉", SaveData.selected_vehicle == picked,
			"选中 %s（期望 %s）" % [SaveData.selected_vehicle, picked])
	_check("没碰过的图仍然是锁着的",
			not SaveData.map_unlocked(Maps.IDS[Maps.FREE_COUNT + 2]),
			"「%s」锁着" % Maps.IDS[Maps.FREE_COUNT + 2])
	# **迁移只改内存，不写盘**：装档这一步不该有副作用（和 `_migrate` 同一条规矩）。
	var cfg := ConfigFile.new()
	cfg.load(SaveData.SAVE_PATH)
	_check("迁移当场不改写存档",
			not cfg.has_section_key(SaveData.UNLOCK_SECTION, "map_" + played),
			"[unlocked] 段里还是空的，等下一次 save_data() 才落地")

	# 二、选中项是锁着的。
	#
	# 图和车在这里**不一样，是有意的**：
	#  · 图：选中它不算玩过（老版本里 12 张图随便点，手滑点一张再退出很正常），
	#    所以「没成绩」就是没玩过 → 换回平原。
	#  · 车：老版本也只有这几辆、也随便选，但**选中的那辆就是玩家正在开的那辆**，
	#    收回去等于把他手上的车抢走 → 白送（见 [method SaveData._grandfather]）。
	var locked_map: String = Maps.IDS[Maps.FREE_COUNT + 2]   # 没成绩、没买过
	var locked_car: String = Vehicles.IDS[Vehicles.FREE_COUNT + 2]
	_write_save(locked_map, locked_car, {}, {})
	SaveData.load_data()
	_check("老档停在没跑过的收费图上会被换回平原",
			SaveData.selected_map == Maps.PLAINS,
			"选中 %s（期望 %s）" % [SaveData.selected_map, Maps.PLAINS])
	_check("老档停在收费车上不会被抢走，而是白送",
			SaveData.selected_vehicle == locked_car and SaveData.vehicle_unlocked(locked_car),
			"选中还是 %s，且已解锁" % SaveData.selected_vehicle)
	# 这一条是真正要守的东西 —— 具体的兜底怎么实现可以改，但「继续」按钮
	# 一定要能开进一张能开的图、一辆能开的车。
	_check("装完档，选中的图/车一定是能开的",
			SaveData.map_unlocked(SaveData.selected_map)
			and SaveData.vehicle_unlocked(SaveData.selected_vehicle),
			"%s / %s 都解锁" % [SaveData.selected_map, SaveData.selected_vehicle])

	# 三、手改过的 cfg：选中的 id 根本不存在。
	_write_save("atlantis", "hovercraft", {}, {})
	SaveData.load_data()
	_check("选中不认识的图/车会被换回默认",
			SaveData.selected_map == Maps.PLAINS
			and SaveData.selected_vehicle == Vehicles.DEFAULT,
			"%s / %s" % [SaveData.selected_map, SaveData.selected_vehicle])

	SaveData.reset_progress()


## 手写一份存档，模拟「加了付费解锁之前」的老档。
##
## [param best] 是 `{地图 id: 米}`（只写非零的），[param upgrades] 是
## `{车 id: {升级项 id: 等级}}`。**不写 [constant SaveData.UNLOCK_SECTION] 段** ——
## 那正是「老档」的定义。
func _write_save(map_id: String, vehicle_id: String, best: Dictionary,
		upgrades: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "best_distance", 0)
	cfg.set_value(SECTION, "total_coins", 0)
	cfg.set_value(MAP_SECTION, "selected", map_id)
	cfg.set_value(VEHICLE_SECTION, "selected", vehicle_id)
	for id in Maps.IDS:
		cfg.set_value(MAP_SECTION, "best_" + id, int(best.get(id, 0)))
	for vid: String in upgrades:
		var lv: Dictionary = upgrades[vid]
		for uid: String in lv:
			cfg.set_value(UPGRADE_SECTION, vid + "/" + uid, int(lv[uid]))
	cfg.save(SaveData.SAVE_PATH)
