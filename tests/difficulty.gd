extends Node
## 难度随里程增长：**「又陡又长的坡」的概率越来越高**。
##
## 需求原话：「请实现：随着里程增大，又陡又长的坡的概率将会增高」。
##
## ## 判据
##
## 「随机站在地形的某处，脚下的路陡 ≥ 20° **而且往前还有至少 400 像素**」的概率。
## 往前看 400 像素取**平均坡度**（不是这一点的瞬时坡度）：「长」这个字必须进到判据里
## —— 噪声每个小疙瘩都能凑出一个 40° 的尖，而车开上去只是颠一下；
## 玩家说的「又长又陡的坡」是咬着牙爬好几百像素。
##
## 这是**统计量**，所以按里程分五段、每段扫几千个采样点、八个种子平均。
## 打印版在同一套判据上跑：`tests/slope_probe.tscn`（它会列出角度和长度两个旋钮
## 各自的分布，用来调参；这个文件是它的**断言版**，阈值一模一样）。
##
## ## 三个断言方向
##
## A. **出生点附近不变**：前 600 米的概率仍然是 0 上下。难度曲线是从零加上去的
##    （[method HillTerrain._long_weight] 前 500 米只涨到 1%），不是把整条地形
##    往前推 —— 前面几百米的手感是钉死的。
## B. **越远越高**：增长段（0.6 → 2.0 km）显著上升，之后只允许在噪声范围内持平，
##    不许回落。
## C. **长坡从无到有**：这一条是需求里最实的一条。加长波层之前，
##    「≥20° 且连续 700 像素」在全地图、全里程上都是 **0.0%**（实测），
##    也就是说**长坡这个种类根本不存在**。
##
## ## 安全线（和上面三条同等重要）
##
## 难度可以涨，但**不能涨出「车爬不上去的墙」**：断崖和超陡长坡是「必死」不是「难」。
## 所以另外钉两条：连续 400 像素的平均坡度不许超过 [constant MAX_SUSTAINED]，
## 10 像素内的单步落差不许超过 [constant MAX_LOCAL_STEP]（这是**局部棱角**的量，
## 断崖会表现为一步跳几百像素）。两个数的来处都写在各自的常数注释里。

## 判据里的角度和窗口长度。
const ANGLE := 20.0
const LOOK := 400.0
## 采样步长（像素）。10 像素 = 1 米。
const STEP := 10.0

## 里程分段（像素）。第一段从 2000 起：出生点的平地和渐入区本来就没有坡，
## 放进来只会稀释成假象。
const BANDS := [
	{"label": "0.2~0.6km", "from": 2000.0, "to": 6000.0},
	{"label": "0.6~1.2km", "from": 6000.0, "to": 12000.0},
	{"label": "1.2~2.0km", "from": 12000.0, "to": 20000.0},
	{"label": "2.0~3.5km", "from": 20000.0, "to": 35000.0},
	{"label": "3.5~5.5km", "from": 35000.0, "to": 55000.0},
]

## 多个种子平均。长波层的波长是 2381 像素，一段八千像素里只有三四个来回，
## 单看一个种子的起伏会被读成趋势。
const SEEDS := [1337, 90210, 555, 4242, 777, 20240, 98765, 31337]
## 地图。平原是基准，竞技场最猛（`amp_scale` 2.2，而且它本来就长），
## 火山和山地是中间档。三档都得成立 —— 长波层是所有噪声图共用的。
const MAP_IDS := [Maps.PLAINS, Maps.ARENA, Maps.VOLCANO, Maps.MOUNTAIN]

## 第一段允许的上限：「出生点附近没变」的量化。
const EARLY_MAX := 0.015
## 采样噪声的容差（百分点/100）。相邻两段都是「封顶之后」的同一个数时，
## 八个种子的平均还会有 1 个百分点上下的抖动，别把它读成趋势。
const NOISE_TOL := 0.015
## 增长段的**最小**涨幅（比例）：0.6→1.2km 到 1.2→2.0km 至少要涨这么多。
const MIN_GROWTH := 0.02
## 「长坡从无到有」的阈值。
const LONG_LOOK := 700.0
const LONG_EARLY_MAX := 0.005
const LONG_LATE_MIN := 0.02
## 安全线：连续 400 像素的平均坡度上限。
##
## **53° 不是随手定的，也不是照抄 tests/climb 的 55°。** 那个 55° 是「一条干净、
## 光滑、900 像素长的人工坡 + 700 像素平地助跑」量出来的，比这里的判据**更宽**：
## 这里卡的是 400 像素的窗口，比 900 像素短得多。所以真实地形上留 2° 余量 ——
## 真地形有疙瘩、不会给你一条笔直的助跑，同样 55° 的一段，实测爬上去比台架上难。
##
## 实测最陡的一处是山地 3.5~5.5km 的 51.6°（加长波层之前是 43.5°）。
const MAX_SUSTAINED := 53.0
const MAX_LOCAL_STEP := 30.0

## 安全线分三段管，因为地形自己是分段的（复利从 2000 米起，见
## [constant HillTerrain.GROWTH_RATE]）。
##
##  · **[constant SAFE_TO] 之内**（2 km）按**原来的阈值一点没动**：
##    最陡的连续 400 px ≤ [constant MAX_SUSTAINED]，单步 ≤ [constant MAX_LOCAL_STEP]。
##    这一段是玩家真跑得到的范围（全油门一趟约 1.5 km，tests/range）。
##  · **[constant SAFE_TO] ~ [constant HARD_TO] 之间**（2~3.5 km）放宽到
##    [constant MAX_HARD_SUSTAINED] —— 车**实测**能爬的那个坡度，一秒余量都不留。
##    复利就是从这里开始吃余量的，这一段还在「难」的范围里。
##  · **[constant HARD_TO] 之外**（3.5 km+）**只打数、不断言**：那一段用户看过实测表
##    之后明确要的就是「越来越离谱」，本来就该有爬不上去的墙。
##
## **这不是放水到看不出来。** 放水是把 53 直接改成 63 —— 那样连「有人把曲线改回
## 原样」都看不出来了。这里 2 km 之内原样严，2~3.5 km 卡在车的物理极限上，
## 3.5 km 之外也照打不误、只是不判红。
##
## 实测峰值（两层都涨、不封顶；角度是连续 400 px 的平均坡度，斜杠后是 10 px 内的
## 单步落差，单位像素）：
##
## | 图 | 0.2~0.6 | 0.6~1.2 | 1.2~2.0 | 2.0~3.5 | 3.5~5.5 |
## |---|---|---|---|---|---|
## | 平原 | 15°/7 | 27°/10 | 36°/15 | 46°/20 | 60°/31 |
## | 竞技场 | 20°/4 | 38°/7 | 45°/11 | **54°/14** | 62°/27 |
## | 火山 | 20°/8 | 32°/14 | 37°/18 | 52°/27 | 61°/42 |
## | 山地 | 20°/8 | 32°/15 | 42°/21 | 51°/27 | 63°/42 |
##
## 车实测能爬 55°（tests/climb）。竞技场那 54° 就是「2 km 之后不再是稳的」的第一处。
const SAFE_TO := 20000.0
const HARD_TO := 35000.0
## [constant SAFE_TO] 到 [constant HARD_TO] 之间允许的上限：**车的实测极限**。
## 取整到 55 而不是留个 54，是因为这个数的意思是「物理上还爬得上去」，
## 不是「留了多少余量」—— 余量在 SAFE_TO 那一段里留。
const MAX_HARD_SUSTAINED := 55.0

var _assertions := 0
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()
	await _section_a()
	print("")
	await _section_b()
	print("")
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


# ---------------------------------------------------------------- 量

## 一张图 × 所有种子：每段给出 `{head, long, sustained, step}`。
func _measure(map_id: String) -> Array:
	var sums: Array = []
	for band in BANDS:
		sums.append({"head": 0.0, "long": 0.0, "sustained": 0.0, "step": 0.0})
	for seed_value in SEEDS:
		var terrain := HillTerrain.new()
		terrain.world_seed = seed_value
		terrain.map_id = map_id
		add_child(terrain)
		await get_tree().process_frame
		for i in BANDS.size():
			var band: Dictionary = BANDS[i]
			var from := float(band["from"])
			var to := float(band["to"])
			var hit := 0
			var long_hit := 0
			var n := 0
			var sustained := 0.0
			var step := 0.0
			var prev: float = terrain._base_height(from)
			var x := from
			while x < to:
				var h: float = terrain._base_height(x)
				# 局部棱角：10 像素之内的落差。断崖 = 一步几百像素。
				step = maxf(step, absf(h - prev))
				prev = h
				var grade := rad_to_deg(atan2(h - terrain._base_height(x + LOOK), LOOK))
				sustained = maxf(sustained, grade)
				if grade >= ANGLE:
					hit += 1
				var long_grade := rad_to_deg(atan2(
						h - terrain._base_height(x + LONG_LOOK), LONG_LOOK))
				if long_grade >= ANGLE:
					long_hit += 1
				n += 1
				x += STEP
			var acc: Dictionary = sums[i]
			acc["head"] = float(acc["head"]) + float(hit) / float(n)
			acc["long"] = float(acc["long"]) + float(long_hit) / float(n)
			acc["sustained"] = maxf(float(acc["sustained"]), sustained)
			acc["step"] = maxf(float(acc["step"]), step)
		terrain.queue_free()
		await get_tree().process_frame
	for acc in sums:
		acc["head"] = float(acc["head"]) / float(SEEDS.size())
		acc["long"] = float(acc["long"]) / float(SEEDS.size())
	return sums


# ---------------------------------------------------------------- A. 出生点

## 长波层在出生点是**零加权**的 —— 这一条是纯函数的，不用跑地形。
func _section_a() -> void:
	print("=== A. 出生点附近一点没变 ===")
	var terrain := HillTerrain.new()
	add_child(terrain)
	await get_tree().process_frame

	var early := 0.0
	var late := 0.0
	for x in [0.0, 300.0, HillTerrain.FLAT_LENGTH]:
		early = maxf(early, terrain._long_weight(x))
		late = maxf(late, terrain._long_weight(x + 1000.0))
	_check("出生直道上长波层的权重是 0", is_zero_approx(early),
			"x ≤ %.0f 处最大权重 %.6f" % [HillTerrain.FLAT_LENGTH, early])
	# 单调不降：权重只能往上走，不能回退（回退 = 地形在原地变浅，玩家看得见）。
	var monotone := true
	var prev := 0.0
	var x := 0.0
	while x <= HillTerrain.LONG_FULL * 1.5:
		var w: float = terrain._long_weight(x)
		if w < prev - 1e-9:
			monotone = false
		prev = w
		x += 500.0
	_check("权重随里程单调不降", monotone, "扫到 %.0f px 为止" % (HillTerrain.LONG_FULL * 1.5))
	_check("权重在 LONG_FULL 处封顶", is_equal_approx(
			terrain._long_weight(HillTerrain.LONG_FULL), 1.0),
			"x=%.0f 处权重 %.4f" % [HillTerrain.LONG_FULL, terrain._long_weight(HillTerrain.LONG_FULL)])
	terrain.queue_free()


# ---------------------------------------------------------------- B. 逐段

func _section_b() -> void:
	print("=== B. 「陡 ≥%.0f° 且 长 ≥%.0f px」的概率逐段 ===" % [ANGLE, LOOK])
	for map_id in MAP_IDS:
		var rows := await _measure(map_id)
		var heads: Array = []
		var longs: Array = []
		var line := ""
		for i in rows.size():
			heads.append(float(rows[i]["head"]))
			longs.append(float(rows[i]["long"]))
			line += "  %s %.1f%%" % [BANDS[i]["label"], float(rows[i]["head"]) * 100.0]
		print("  %s：%s" % [Maps.get_map(map_id)["zh"], line])
		print("      长 %.0fpx 那一档：%s" % [LONG_LOOK, "  ".join(PackedStringArray(
				longs.map(func(v): return "%.1f%%" % (v * 100.0))))])

		# A. 出生点附近：概率仍然是 0 上下。
		_check("%s 前 600 米没有变难" % map_id, float(heads[0]) <= EARLY_MAX,
				"%.2f%%（上限 %.1f%%）" % [float(heads[0]) * 100.0, EARLY_MAX * 100.0])
		# B. 增长段显著上升。
		_check("%s 0.6→1.2km 到 1.2→2.0km 明显变高" % map_id,
				float(heads[2]) >= float(heads[1]) + MIN_GROWTH,
				"%.1f%% → %.1f%%" % [float(heads[1]) * 100.0, float(heads[2]) * 100.0])
		# B. 之后不许回落（封顶段持平算过，容采样噪声）。
		var drop := 0.0
		var drop_at := ""
		for i in range(3, heads.size()):
			var d := float(heads[i - 1]) - float(heads[i])
			if d > drop:
				drop = d
				drop_at = "%s → %s" % [BANDS[i - 1]["label"], BANDS[i]["label"]]
		_check("%s 越远越高（不许回落）" % map_id, drop <= NOISE_TOL,
				"最大回落 %.2f 个百分点（%s，容差 %.1f）" % [
					drop * 100.0, drop_at, NOISE_TOL * 100.0])
		# C. 长坡从无到有。
		_check("%s 长坡（≥%.0f px）从 0 变成有" % [map_id, LONG_LOOK],
				float(longs[0]) <= LONG_EARLY_MAX and float(longs[-1]) >= LONG_LATE_MIN,
				"第一段 %.2f%% → 最后一段 %.2f%%（要 ≤%.1f%% 且 ≥%.1f%%）" % [
					float(longs[0]) * 100.0, float(longs[-1]) * 100.0,
					LONG_EARLY_MAX * 100.0, LONG_LATE_MIN * 100.0])
		# 安全线分三段：SAFE_TO 之内按老阈值，SAFE_TO~HARD_TO 放宽到车的实测极限，
		# 再往外只打数。三段的来由见各自的常数注释。
		var worst_grade := -INF
		var hard_grade := -INF
		var worst_step := -INF
		var at := ""
		var detail := ""
		for i in rows.size():
			var grade := float(rows[i]["sustained"])
			var step := float(rows[i]["step"])
			var to := float(BANDS[i]["to"])
			detail += "  %s %.0f°/%.0f" % [BANDS[i]["label"], grade, step]
			if to <= SAFE_TO:
				if grade > worst_grade:
					worst_grade = grade
					at = String(BANDS[i]["label"])
			elif to <= HARD_TO:
				hard_grade = maxf(hard_grade, grade)
			if to <= HARD_TO:
				worst_step = maxf(worst_step, step)
		print("      每段最陡（连续 %.0fpx 的角度 / 10px 内的单步落差）：%s" % [LOOK, detail])
		_check("%s %.1fkm 之内最陡的连续 %.0fpx 仍在爬坡能力之内" % [
				map_id, SAFE_TO / 10000.0, LOOK],
				worst_grade <= MAX_SUSTAINED,
				"最陡 %.1f°（%s，上限 %.0f°，实测能爬 55°）" % [
					worst_grade, at, MAX_SUSTAINED])
		_check("%s %.1f~%.1fkm 还没越过车的极限" % [
				map_id, SAFE_TO / 10000.0, HARD_TO / 10000.0],
				hard_grade <= MAX_HARD_SUSTAINED,
				"最陡 %.1f°（上限 %.0f° = 车实测能爬的坡度）" % [
					hard_grade, MAX_HARD_SUSTAINED])
		_check("%s %.1fkm 之内没有断崖" % [map_id, HARD_TO / 10000.0],
				worst_step <= MAX_LOCAL_STEP,
				"最大单步 %.1f px（上限 %.0f）" % [worst_step, MAX_LOCAL_STEP])
		print("")
