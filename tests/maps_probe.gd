extends Node
## 打印四张地图的定义表，并检查特殊地形的分布。
##
## 重点看两件事：
## 1. `Maps.MAPS` 里的 `Color(...)` 常量能不能被常量折叠（不能的话脚本会编译失败）；
## 2. 特殊地形的出现间隔合不合理 —— 太密就是必死路段，太疏玩家碰不到。

const WORLD_SEED := 1337
const CHUNKS := 120


func _ready() -> void:
	_table()
	_features()
	get_tree().quit()


func _table() -> void:
	for id in Maps.IDS:
		var m: Dictionary = Maps.get_map(id)
		print("%-8s %-6s 幅度×%.2f  摩擦×%.2f  阻尼%.1f  油耗×%.1f  天空#%s 泥土#%s  地形=%s" % [
			id, m["zh"], m["amp_scale"], m["friction_scale"], m["drag"], m["fuel_scale"],
			_hex(m["sky"]), _hex(m["dirt"]), m["feature"],
		])
	print("平原是恒等变换 = %s" % str(
		is_equal_approx(Maps.get_map(Maps.PLAINS)["amp_scale"], 1.0)
		and is_equal_approx(Maps.get_map(Maps.PLAINS)["friction_scale"], 1.0)
		and is_equal_approx(Maps.get_map(Maps.PLAINS)["fuel_scale"], 1.0)
		and is_equal_approx(Maps.get_map(Maps.PLAINS)["drag"], 0.0)
		and Maps.noise_seed(WORLD_SEED, Maps.PLAINS) == WORLD_SEED
	))


## 每张图数一遍：多少个区块有特殊地形、平均间隔多少像素。
func _features() -> void:
	for id in Maps.IDS:
		var count := 0
		var first := -1
		var last := -1
		var gaps := PackedFloat32Array()
		for i in range(CHUNKS):
			if Maps.feature_at(WORLD_SEED, id, i) == Maps.FEATURE_NONE:
				continue
			count += 1
			if first < 0:
				first = i
			if last >= 0:
				gaps.append(float(i - last))
			last = i
		var avg := 0.0
		for g in gaps:
			avg += g
		if not gaps.is_empty():
			avg /= float(gaps.size())
		print("%-8s %d 个 / %d 区块   首个在第 %d 区块 (x=%d)   平均间隔 %.2f 区块 = %.0f px" % [
			id, count, CHUNKS, first, first * 800, avg, avg * 800.0,
		])


func _hex(c: Color) -> String:
	return "%02X%02X%02X" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]
