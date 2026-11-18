extends Node
## 特殊地形**落在什么样的地上**。
##
## 坑是「以**当地**地表为基准」往下挖的（见 [method HillTerrain._carve_in_chunk]），
## 而自然地表有起伏 —— 玩家报的三条手感问题全是这么来的：
##
##   1. 吊桥两端的岸不等高（实测最大差 158 像素），而桥两端是按左沿高度钉的，
##      所以一端悬空、一端埋土里
##   2. 火山口两端同理（134 像素），而且右沿该比左沿稍低
##   3. 冰湖前面是上坡的话，车到湖边已经没有速度，而冰面只给 0.5 秒 ——
##      那不是「难」是「必死」
##
## 修法：挖坑之前先把坑那一段**垫平**（[method HillTerrain._level]），火山口再
## 额外让右沿低 `drop`；冰湖则在**摆位**这一层直接否决掉上坡的位置
## （[method HillTerrain.feature_kind_at]）。
##
## 这个套件**不摆车、不跑物理**：直接对着真实噪声问 [method HillTerrain.height_at]，
## 四个地图扫 80 个区块，秒级跑完。

const SEED := 1337
const CHUNKS := 80
const CW := HillTerrain.CHUNK_WIDTH
## 垫平过渡段里，**每 4 个像素**最多允许的落差（像素）。
##
## 过渡段是个 smoothstep，斜率上限 1.5 × 高差 / 垫平长度。最坏的情况（区块的
## 余量全用上、高差两百多像素）算下来约 4 像素/像素，取 5 是留了余量。
## **不用这个阈值去扫坑壁**：坑壁本来就接近垂直（火山口 84°），是设计出来的，
## 这里只扫过渡段 —— 那里出现几十像素的台阶就一定是缝合错了。
const MAX_SLOPE := 5.0
## 扫台阶时的步长。
const STEP := 4

var _failures := 0
var _assertions := 0


func _ready() -> void:
	SaveData.persist = false
	_test_level_ends()
	print("")
	_test_seams()
	print("")
	_test_lake_veto()
	print("")
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


## 真实噪声地形，但**不进树**：不进树就不建区块、不摆金币，只要一条地表折线。
func _real_terrain(map_id: String) -> HillTerrain:
	var t := HillTerrain.new()
	t.world_seed = SEED
	t.map_id = map_id
	t._configure_noise()
	return t


## 某个区块里特殊地形的两个坑沿（世界坐标）。
func _rims(t: HillTerrain, index: int) -> Array:
	var lay: Dictionary = Maps.feature_layout(t.feature_kind_at(index))
	var x0 := float(index) * CW + float(lay["inset"])
	return [x0, x0 + float(lay["width"])]


# ---------------------------------------------------------------- 两端

## 坑的两端必须落在**设计好的**高度上：吊桥和冰湖两端一样高，火山口右沿低 `drop`。
##
## 一个断言盖住三种地形：`drop` 就是「右沿比左沿低多少」，桥和冰湖填 0。
func _test_level_ends() -> void:
	print("=== 两端 ===")
	var built := 0
	var worst := 0.0
	var worst_where := ""
	var bad := PackedStringArray()
	for map_id: String in Maps.IDS:
		var t := _real_terrain(map_id)
		var here := 0
		for i in range(CHUNKS):
			var kind := t.feature_kind_at(i)
			# 跳过「不碰地表」的地形（沙尘暴 / 石子 / 树）。判据走 [method Maps.digs]，
			# 不在这里列白名单：以后新加一种地形，填了 `depth`/`level` 就自动进这套
			# 检查、没填就自动不进，不会漏。
			if kind == Maps.FEATURE_NONE or not Maps.digs(kind):
				continue
			built += 1
			here += 1
			var rims := _rims(t, i)
			var gap: float = t.height_at(rims[1]) - t.height_at(rims[0])
			var want := float(Maps.feature_layout(kind).get("drop", 0.0))
			var err := absf(gap - want)
			if err > worst:
				worst = err
				worst_where = "%s 第 %d 块" % [map_id, i]
			if err > 0.01:
				bad.append("%s 第 %d 块 差 %+.1f（期望 %+.1f）" % [map_id, i, gap, want])
		print("  %s：%d 处" % [map_id, here])
		t.free()
	_check("右沿落在设计高度上（桥/冰湖等高，火山口低 drop）", bad.is_empty(),
			"扫了 %d 处，最大偏差 %.2f 像素（%s）%s" % [built, worst, worst_where,
			"" if bad.is_empty() else "；偏差：" + "，".join(bad)])

	# 右沿比左沿低是**指定的方向**（y 向下为正，所以「低」= 更大的 y）。
	# 上面那条只保证「等于 drop」，drop 填成负数就反了 —— 单独钉一下方向。
	var vt := _real_terrain(Maps.VOLCANO)
	var idx := -1
	for i in range(CHUNKS):
		if vt.feature_kind_at(i) == Maps.FEATURE_CRATER:
			idx = i
			break
	var crater_gap := 0.0
	if idx >= 0:
		var rims := _rims(vt, idx)
		crater_gap = vt.height_at(rims[1]) - vt.height_at(rims[0])
	_check("火山口右沿比左沿低（起跳高、落地低）", crater_gap > 0.0,
			"第 %d 块：右沿低 %.0f 像素" % [idx, crater_gap])
	vt.free()


# ---------------------------------------------------------------- 缝合

## 垫平窗口的边缘必须**正好**压在区块边界上、权重正好是 0。
##
## 不是的话，两个区块各算各的地表会在缝合处差出一截 —— 车开过去就是凭空撞上
## 一堵看不见的墙（或者掉进一条缝）。这里逐 4 像素扫过每个特殊地形区块的
## 全部过渡段，顺带量一下边界本身。
func _test_seams() -> void:
	print("=== 缝合处 ===")
	var worst_step := 0.0
	var worst_at := 0.0
	var bad := PackedStringArray()
	var edges := 0
	for map_id: String in Maps.IDS:
		var t := _real_terrain(map_id)
		for i in range(CHUNKS):
			var kind := t.feature_kind_at(i)
			# 跳过「不碰地表」的地形（沙尘暴 / 石子 / 树）。判据走 [method Maps.digs]，
			# 不在这里列白名单：以后新加一种地形，填了 `depth`/`level` 就自动进这套
			# 检查、没填就自动不进，不会漏。
			if kind == Maps.FEATURE_NONE or not Maps.digs(kind):
				continue
			var lay: Dictionary = Maps.feature_layout(kind)
			var inset := float(lay["inset"])
			var width := float(lay["width"])
			var rims := _rims(t, i)
			var x0: float = rims[0]
			var x1: float = rims[1]

			# 边界本身：区块起点那个位置算出来的应该是**原始**地表。
			for b in [float(i) * CW, float(i + 1) * CW]:
				edges += 1
				var d := absf(t.height_at(b) - t._base_height(b))
				if d > 0.5:
					bad.append("%s 第 %d 块 x=%.0f 边界差了 %.1f" % [map_id, i, b, d])

			# 两条过渡段：左边 [x0 − inset, x0]，右边 [x1, x1 + 余量]。
			var spans := [
				[x0 - inset, x0],
				[x1, x1 + (CW - inset - width)],
			]
			for sp: Array in spans:
				var a: float = sp[0]
				var b2: float = sp[1]
				var prev: float = t.height_at(a - float(STEP))
				var x := a
				while x <= b2:
					var y := t.height_at(x)
					var step := absf(y - prev)
					if step > worst_step:
						worst_step = step
						worst_at = x
					if step > MAX_SLOPE * float(STEP):
						bad.append("%s 第 %d 块 x=%.0f 一个 %d 像素的跨步落了 %.0f" % [
							map_id, i, x, STEP, step])
					prev = y
					x += float(STEP)
		t.free()
	_check("过渡段没有台阶、边界上就是原始地表", bad.is_empty(),
			"扫了 %d 个边界，最陡一处 %.1f 像素/%d 像素（x=%.0f）%s" % [
				edges, worst_step, STEP, worst_at,
				"" if bad.is_empty() else "；" + "，".join(bad)])


# ---------------------------------------------------------------- 冰湖的否决

## 冰湖前面是上坡就不摆。
##
## 两条都要钉：留下来的湖前面确实是平/下坡（规则生效），以及**这条规则确实
## 否决过人**（不是一条永远不触发的死代码）。
func _test_lake_veto() -> void:
	print("=== 冰湖的否决 ===")
	var t := _real_terrain(Maps.SNOW)
	var kept := 0
	var killed := 0
	var worst_kept := -1.0e9
	var worst_dealt := -1.0e9
	for i in range(CHUNKS):
		if Maps.feature_at(SEED, Maps.SNOW, i) != Maps.FEATURE_LAKE:
			continue
		var rims := _rims(t, i)
		var climb := t._climb_before(rims[0])
		worst_dealt = maxf(worst_dealt, climb)
		if t.feature_kind_at(i) == Maps.FEATURE_NONE:
			killed += 1
		else:
			kept += 1
			worst_kept = maxf(worst_kept, climb)
	t.free()

	_check("摆上去的湖，前面都不是陡上坡", worst_kept <= HillTerrain.LAKE_MAX_CLIMB,
			"最陡的一个爬了 %.0f 像素（上限 %.0f）" % [worst_kept, HillTerrain.LAKE_MAX_CLIMB])
	_check("这条规则真的否决过（不是死代码）", killed > 0,
			"扫 %d 块：掷出 %d 个湖，摆上 %d 个、否决 %d 个（掷出来最陡的一个爬 %.0f）" % [
				CHUNKS, kept + killed, kept, killed, worst_dealt])

	# **平地上一律不否决。** 其余几个套件都用「地表压平」的假地形
	# （见 tests/hazards.gd 的 FlatTerrain），平地的前置坡恒为 0，所以规则不触发、
	# 挖坑和摆位照旧 —— 这条是那份约定的一部分，写下来免得以后有人改窗口长度
	# 把它悄悄打破。
	var flat: HillTerrain = FlatTerrain.new()
	flat.world_seed = SEED
	flat.map_id = Maps.SNOW
	var same := true
	for i in range(CHUNKS):
		if flat.feature_kind_at(i) != Maps.feature_at(SEED, Maps.SNOW, i):
			same = false
	_check("地是平的就不否决（测试用的假地形不受影响）", same, "扫了 %d 块，结论全部一致" % CHUNKS)
	flat.free()


## 地表恒定。和 tests/hazards.gd 里那个是同一招：把噪声拿掉，「车到坑沿还有
## 多少速度」就不再是随机的，测的才是地形本身。
class FlatTerrain extends HillTerrain:
	func _base_height(_x: float) -> float:
		return GROUND_Y
