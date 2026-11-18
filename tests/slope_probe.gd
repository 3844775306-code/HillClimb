extends Node
## 「又陡又长的坡」有多少 —— 按里程分段量。
##
## 需求原话：「随着里程增大，又陡又长的坡的概率将会增高」。所以这里量的是一个
## **百分比**：随机站在地形的某处，脚下的路「平均坡度 ≥ θ°、而且往前还有至少
## L 像素」的概率。这一个数按里程分段列出来，随里程单调上去就是需求达成。
##
## ## 为什么判据是「窗口平均坡度」，不是「这一点的瞬时坡度」
##
## 「长」这个字必须进到判据里。瞬时坡度高的地方满地都是 —— 噪声每个小疙瘩都能
## 凑出一个 40° 的尖，而车开上去只是颠一下。玩家说的「又长又陡的坡」是
## 「咬着牙爬好几百像素」。所以判据是：**站在 x 处往前看 L 像素，
## `(height(x) − height(x+L)) / L` 这个平均坡度 ≥ θ 才算数**。
##
## ## 两个旋钮分开扫
##
## θ 固定扫 L、L 固定扫 θ。「陡」和「长」是两个独立的自由度：只加幅度是把坡变陡，
## 只降频率是把坡变长，而需求要的是**两个一起**（见 [method HillTerrain._base_height]
## 里长坡层那一段）。
##
## ## 量的是 `_base_height`，不是 `height_at`
##
## 特殊地形（坑、吊桥、火山口）会在地表上挖出几百像素的落差，那是**坑**不是**坡**，
## 混进来会把「坡度」这个指标污染成「有没有坑」。难度曲线的旋钮也只拧在噪声那一层
## （形状地图的屋顶/彩虹是解析算的，一点噪声都不掺），所以量噪声层才是量对了东西。
##
## ## 用法
##
##   godot --headless --path . res://tests/slope_probe.tscn
##
## 输出每个区间一行，最后一行是结论（头号指标有没有随里程单调上去）。

## 采样步长（像素）。10 像素 = 1 米（[constant Maps.PIXELS_PER_METER]），
## 比一个采样点间距（[constant HillTerrain.POINT_SPACING] 20）还细，够密了。
const STEP := 10.0

## 里程分段（像素）。第一段的起点在 [constant HillTerrain.BLEND_LENGTH]（800）之后
## 再多留一截：出生点那段是平地 + 渐入区，本来就没有坡，放进来只会把第一段
## 稀释成接近 0 的假象，让「越远越陡」显得比实际更夸张。
const BANDS := [
	{"label": "0.2~0.6km", "from": 2000.0, "to": 6000.0},
	{"label": "0.6~1.2km", "from": 6000.0, "to": 12000.0},
	{"label": "1.2~2.0km", "from": 12000.0, "to": 20000.0},
	{"label": "2.0~3.5km", "from": 20000.0, "to": 35000.0},
	{"label": "3.5~5.5km", "from": 35000.0, "to": 55000.0},
]

## 「陡」扫的这几个角度（窗口长度固定为 [constant LOOK]）。
const ANGLES := [15.0, 20.0, 25.0, 30.0]
## 「长」扫的这几个窗口长度（角度固定为 [constant BASE_ANGLE]）。
const LOOKS := [250.0, 400.0, 700.0, 1100.0]
## 量「陡」时窗口开多长。
const LOOK := 400.0
## 量「长」时算多少度。
const BASE_ANGLE := 20.0
## 头号指标：**这一个数就是需求要的那个概率**。结论行看它。
const HEAD_ANGLE := 20.0
const HEAD_LOOK := 400.0

## 多个种子平均。同一个种子下的百分比有采样噪声，而且**长波层的噪声特别大**：
## 波长 2381 像素，一段 8000 像素的区间里只有三四个来回，赶上长波在那一段正好
## 是缓的那几节，整段的百分比就偏低。单看一个种子会把这种噪声读成趋势。
const SEEDS := [1337, 90210, 555, 4242, 777, 20240, 98765, 31337]
## 地图。平原是基准（`amp_scale` 1.0），竞技场是起伏最猛的一张（2.2，
## 而且它本来就把频率调到 0.00042 了 —— 加长波层对它的增量最小，是最难推动的一张），
## 火山口和山地是中间档。
const MAP_IDS := [Maps.PLAINS, Maps.ARENA, Maps.VOLCANO, Maps.MOUNTAIN]

var _terrain: HillTerrain


func _ready() -> void:
	for map_id in MAP_IDS:
		print("")
		await _scan_map(map_id)
	get_tree().quit()


## 一张图：每个种子扫一遍所有区间，按区间把百分比平均起来。
func _scan_map(map_id: String) -> void:
	print("=== %s（%d 个种子平均）===" % [Maps.get_map(map_id)["zh"], SEEDS.size()])
	var head := "区间           "
	for a in ANGLES:
		head += "  ≥%2.0f°" % a
	head += "  |"
	for l in LOOKS:
		head += "  长%4.0f" % l
	head += "   |  最大单步  窗口坡度p90"
	print(head)

	# 累加器：`[区间][列]`。
	var sums: Array = []
	var counts: Array = []
	for band in BANDS:
		sums.append(_zeros())
		counts.append(0)
	var p90s: Array = []
	var steps: Array = []
	var head_sums: Array = []
	for band in BANDS:
		p90s.append([0.0])
		steps.append([0.0])
		head_sums.append(0.0)

	for seed_value in SEEDS:
		_terrain = HillTerrain.new()
		_terrain.world_seed = seed_value
		_terrain.map_id = map_id
		add_child(_terrain)
		await get_tree().process_frame
		var result := _scan_seed()
		_terrain.queue_free()
		await get_tree().process_frame
		for i in BANDS.size():
			var row: Array = result["rows"][i]
			var acc: Array = sums[i]
			for j in acc.size():
				acc[j] += row[j]
			counts[i] += 1
			p90s[i][0] += result["p90"][i]
			steps[i][0] = maxf(steps[i][0], result["step"][i])
			head_sums[i] += float(result["head"][i])

	for i in BANDS.size():
		var acc: Array = sums[i]
		var n := float(counts[i])
		var line := "%-13s" % BANDS[i]["label"]
		for j in acc.size():
			line += "  %5.1f%%" % (float(acc[j]) / n * 100.0)
			if j == ANGLES.size() - 1:
				line += " |"
		line += "   |  %6.1f px   %5.1f°" % [steps[i][0], p90s[i][0] / n]
		print(line)

	var heads: Array = []
	for i in BANDS.size():
		heads.append(head_sums[i] / float(counts[i]))
	print("  头号指标（陡 ≥%.0f° 且 长 ≥%.0f px）逐区间：%s" % [
		HEAD_ANGLE, HEAD_LOOK,
		" → ".join(PackedStringArray(heads.map(func(v): return "%.1f%%" % (v * 100.0))))])
	var verdict := "单调递增" if _increasing(heads) else "**不是单调递增**"
	# 第一段是 0.0% 的时候不能报倍数（无穷倍看着像算错了），报「涨了几个百分点」。
	# 第一段本来就该是 0 上下：长波层在 500 米以内几乎不加权（见 HillTerrain._long_weight）。
	var gain := "%.1f → %.1f 个百分点" % [heads[0] * 100.0, heads[-1] * 100.0]
	if heads[0] > 0.002:
		gain += "（%.1f 倍）" % (heads[-1] / heads[0])
	print("  => %s（%s）" % [verdict, gain])


## 一个种子扫一遍：返回每个区间的百分比行（列的顺序 = ANGLES 再 LOOKS）、
## 头号指标、窗口坡度的 p90、以及最大单步跳变。
func _scan_seed() -> Dictionary:
	var rows: Array = []
	for band in BANDS:
		rows.append(_zeros())
	var p90: Array = []
	for band in BANDS:
		p90.append(0.0)
	var steps: Array = []
	for band in BANDS:
		steps.append(0.0)
	var head := []

	for i in BANDS.size():
		var from := float(BANDS[i]["from"])
		var to := float(BANDS[i]["to"])
		var acc: Array = rows[i]
		var grades: Array = []
		var step := 0.0
		var prev: float = _terrain._base_height(from)
		var x := from
		var n := 0
		while x < to:
			var h: float = _terrain._base_height(x)
			# 最大单步跳变：断崖会表现为「一步跳几十像素」。这是**安全线**，
			# 难度怎么涨都不该把它顶上去（撞上断崖 = 必死，不是难）。
			step = maxf(step, absf(h - prev))
			prev = h

			# 窗口坡度：正数 = 前面比这里高（屏幕坐标 y 向下，往上爬 = y 变小）。
			# 两个旋钮各算各的窗口，`LOOK` 那一列复用同一个数，不重算。
			var grade := rad_to_deg(atan2(h - _terrain._base_height(x + LOOK), LOOK))
			grades.append(grade)
			for j in ANGLES.size():
				if grade >= float(ANGLES[j]):
					acc[j] += 1
			for j in LOOKS.size():
				var l := float(LOOKS[j])
				var g := rad_to_deg(atan2(h - _terrain._base_height(x + l), l))
				if g >= BASE_ANGLE:
					acc[ANGLES.size() + j] += 1
			n += 1
			x += STEP

		for j in acc.size():
			acc[j] = float(acc[j]) / float(maxi(n, 1))
		grades.sort()
		p90[i] = float(grades[int(float(grades.size() - 1) * 0.9)]) if not grades.is_empty() else 0.0
		steps[i] = step

	# 头号指标直接取「陡」那一列：`ANGLES` 里找得到 [constant HEAD_ANGLE] 就用它，
	# 找不到（或者窗口长度和 `LOOK` 对不上）就现算一遍 —— 探针改了旋钮也跑得动。
	var head_index := ANGLES.find(HEAD_ANGLE)
	for i in BANDS.size():
		if head_index >= 0 and is_equal_approx(LOOK, HEAD_LOOK):
			head.append(float(rows[i][head_index]))
		else:
			head.append(_head_fraction(float(BANDS[i]["from"]), float(BANDS[i]["to"])))

	return {"rows": rows, "head": head, "p90": p90, "step": steps}


## 头号指标：陡 ≥ [constant HEAD_ANGLE] 且 长 ≥ [constant HEAD_LOOK] 的比例。
func _head_fraction(from: float, to: float) -> float:
	var hit := 0
	var n := 0
	var x := from
	while x < to:
		var drop: float = _terrain._base_height(x) - _terrain._base_height(x + HEAD_LOOK)
		if rad_to_deg(atan2(drop, HEAD_LOOK)) >= HEAD_ANGLE:
			hit += 1
		n += 1
		x += STEP
	return float(hit) / float(maxi(n, 1))


func _zeros() -> Array:
	var out: Array = []
	for i in ANGLES.size() + LOOKS.size():
		out.append(0.0)
	return out


## 一串数是不是**单调不降**（允许相等；容一点点采样噪声：后一段比前一段小
## 但小于半个百分点的话也算没降 —— 这不是放水，是「同一个数」在两次采样里
## 本来就会差这么点）。
func _increasing(values: Array) -> bool:
	for i in range(1, values.size()):
		if float(values[i]) < float(values[i - 1]) - 0.005:
			return false
	return true
