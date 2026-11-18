extends Node
## 量特殊地形「落在什么样的一段地上」。
##
## 三条手感反馈其实指向同一件事：坑是**以当地地表为基准**往下挖的（见
## [method HillTerrain._carve]），而自然地表是有起伏的，于是：
##   1. 吊桥两端的岸不一样高 —— 左沿落在 base(x0)，右沿落在 base(x1)
##   2. 火山口的两个坑沿同理，而且坑口太宽
##   3. 冰湖前面赶上上坡时，车到湖边已经没有速度，而冰面只给 0.5 秒
##
## 这个探针**不摆车、不跑物理**，只对着真实噪声打表：每种地形每个出现位置的
## 两端高差、以及坑沿前 300 像素爬了多少。改完再跑一遍对数字。

const SEED := 1337
const CHUNKS := 80
## 前置坡度**不在这里算**：直接问地形（[method HillTerrain._climb_before]）。
## 探针自己再写一个「看多远」的常数，迟早会和规则里的 `LAKE_APPROACH` 对不上，
## 打印出来的数就和它要说明的那条规则是两码事。


func _ready() -> void:
	SaveData.persist = false
	for map_id in Maps.IDS:
		_survey(map_id)
		print("")
	get_tree().quit()


## 真实噪声地形，但**不进树**：不进树就不建区块、不摆金币，只要一条地表折线。
func _terrain(map_id: String) -> HillTerrain:
	var t := HillTerrain.new()
	t.world_seed = SEED
	t.map_id = map_id
	t._configure_noise()
	return t


func _survey(map_id: String) -> void:
	var t := _terrain(map_id)
	print("=== %s（%s）===" % [map_id, Maps.get_map(map_id)["zh"]])
	var counts := {}
	var lakes: Array[float] = []
	var worst_gap := 0.0
	var worst_climb := -1.0e9
	var vetoed := 0
	for i in range(CHUNKS):
		# 骰子掷出来的，和地形**实际摆的**（可能被否决）。
		var dealt := Maps.feature_at(SEED, map_id, i)
		var built := t.feature_kind_at(i)
		if dealt == Maps.FEATURE_NONE or dealt == Maps.FEATURE_SANDSTORM:
			continue
		var lay: Dictionary = Maps.feature_layout(dealt)
		var x0 := float(i) * HillTerrain.CHUNK_WIDTH + float(lay["inset"])
		var x1 := x0 + float(lay["width"])
		var climb := t._climb_before(x0)
		if dealt == Maps.FEATURE_LAKE:
			lakes.append(climb)
		if built == Maps.FEATURE_NONE:
			# 被否决的区块根本没挖坑，那两端的数就是原始地表，没有意义。
			vetoed += 1
			print("  区块 %2d  %-8s 前置上坡 %+.0f  → **否决**，这一块当普通地形" % [i, dealt, climb])
			continue
		var y0 := t.height_at(x0)
		var y1 := t.height_at(x1)
		worst_gap = maxf(worst_gap, absf(y1 - y0))
		worst_climb = maxf(worst_climb, climb)
		counts[dealt] = int(counts.get(dealt, 0)) + 1
		print("  区块 %2d  %-8s x %.0f→%.0f（宽 %.0f）  两端 y %.0f / %.0f（差 %+.0f）  前置上坡 %+.0f" % [
			i, dealt, x0, x1, float(lay["width"]), y0, y1, y1 - y0, climb])
	var parts := PackedStringArray()
	for kind: String in counts:
		parts.append("%s %d 处" % [kind, counts[kind]])
	print("  → 摆上去的：%s；两端最大高差 %.0f，前置最大上坡 %.0f，否决 %d 处" % [
		"，".join(parts) if not parts.is_empty() else "一个都没有", worst_gap, worst_climb, vetoed])
	_sweep(lakes)
	t.free()


## 否决门槛取多少合适：拿实测的每个湖的前置上坡去卡一遍，看各个门槛各留下几个。
func _sweep(lakes: Array) -> void:
	if lakes.is_empty():
		return
	var out := PackedStringArray()
	for thr in [0.0, 12.0, 24.0, 36.0, 48.0, 72.0]:
		var keep := 0
		for c: float in lakes:
			if c <= thr:
				keep += 1
		out.append("%.0f → 留 %d/%d" % [thr, keep, lakes.size()])
	print("  门槛扫描（前置上坡 ≤ 门槛才摆湖）：%s" % "，".join(out))
