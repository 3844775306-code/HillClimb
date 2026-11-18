extends Node
## 沙尘暴动画：分层、渐变、风势、沙团。
##
## **好看不好看测不了**（无头跑没有画面，Dummy 渲染器连 `_draw()` 都不一定调），
## 能测的是画法本身对不对：层有没有分对、渐变是不是真的在渐变、风势是不是真的在
## 起伏、沙团有没有生老病死。这些写反了画面一定不对，只是没人会把它报成 bug。
##
## 顺带钉住一件和动画无关、但**同一个文件里、最容易被顺手改坏**的事：风力区的
## 尺寸和碰撞层。tests/hazards 的 A/B（开风/关风比车速）只告诉你「慢了」或「没慢」，
## 不会告诉你风区被挪到别的地方去了。
##
## 这一套**不进树**：`_process` 自己一帧一帧调，引擎的自动调用不会插进来，
## 于是「同样步数」的比较才有意义。也因此这里全程走 `Node2D` + `call()` ——
## 脚本自己的字段（`_streaks` 之类）静态类型看不见，写成 `HillFeature` 会直接编译不过。

const SANDSTORM := preload("res://scenes/sandstorm.tscn")
const MAIN := preload("res://scenes/main.tscn")
const SS := preload("res://scripts/sandstorm.gd")

const LEFT := 4000.0
const WIDTH := 800.0
const RIM := 420.0
const DT := 1.0 / 60.0

var _failures := 0
var _zone: Node2D


func _ready() -> void:
	_zone = _build_zone()
	_wind_box()
	print("")
	_haze_profile()
	print("")
	_streaks()
	print("")
	_gust()
	print("")
	_puffs()
	print("")
	_car_depth()

	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


## 不进树地摆一块风区。`size.y = 0` 是沙尘暴的实情：它不挖地形。
func _build_zone() -> Node2D:
	var zone: Node2D = SANDSTORM.instantiate()
	zone.call("setup", Rect2(LEFT, RIM, WIDTH, 0.0), RIM)
	return zone


func _step(seconds: float) -> void:
	_step_zone(_zone, seconds)


func _step_zone(zone: Node2D, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		zone.call("_process", DT)


# ---------------------------------------------------------------- 风区（不能动）

func _wind_box() -> void:
	print("=== 1. 风力区（动画重写了，这一块必须原样） ===")
	var area: Area2D = _zone.get_node_or_null("Wind")
	if area == null:
		_check("风力区还在", false, true)
		return
	_check("风力区还在", true, true)
	# 层 0 是「不打别人」，掩码 1 是「只认车」—— 改错了风会吹到别的东西上
	_check("碰撞层 = 0（不推别的东西）", area.collision_layer, 0)
	_check("碰撞掩码 = 1（只认车）", area.collision_mask, 1)
	var box: RectangleShape2D = (area.get_child(0) as CollisionShape2D).shape
	_check("风区宽度 = 地形给的宽度", box.size.x, WIDTH)
	_check("风区高度 = 地面上 620 + 地面下 120",
			box.size.y, SS.WIND_TOP + SS.WIND_BELOW)
	_check("风区居中", area.position.x, LEFT + WIDTH * 0.5)
	_check("风区上沿在地面之上", area.position.y - box.size.y * 0.5, RIM - SS.WIND_TOP)
	_check("风区下沿在地下（掉坑里也还在吹）",
			area.position.y + box.size.y * 0.5, RIM + SS.WIND_BELOW)


# ---------------------------------------------------------------- 渐变

## 远处那片沙：下浓上淡、两头淡出，而且**格子之间不能有缝**。
##
## 那十几个四边形是按「先横后竖」加的（`下标 = 竖格 × HAZE_SEGS + 横段`），
## 下面直接按下标取，所以下标算法得跟 `_build_haze` 一致。
func _haze_profile() -> void:
	print("=== 2. 远处那片沙的渐变 ===")
	var haze: Node2D = _zone.get_node_or_null("Haze")
	if haze == null:
		_check("沙层还在", false, true)
		return
	var quads := haze.get_children()
	_check("格子数 = 横 3 段 × 竖 6 格",
			quads.size(), SS.HAZE_SEGS * SS.HAZE_BANDS)
	_check("沙层在土坡后面（z = −1）", haze.z_index, -1)

	var mid := SS.HAZE_SEGS / 2                          # 中间那一段是全浓度的
	var bottom_a := _alpha(quads, 0, mid, 0)             # 最下面一格的下沿
	var top_a := _alpha(quads, SS.HAZE_BANDS - 1, mid, 2)  # 最上面一格的上沿
	print("  下沿不透明 %.3f，上沿 %.3f，最左边 %.3f" % [
		bottom_a, top_a, _alpha(quads, 0, 0, 0)])
	# 颜色分量在 [Color] 里是 float32，`0.34` 存进去回来是 `0.34000000357628`，
	# 所以凡是过了一遍 Color 的数都得比近似 —— 不然测的是浮点转换不是画法。
	_check("底下最浓", is_equal_approx(bottom_a, SS.HAZE_ALPHA), true)
	_check("顶上淡（沙是贴地刮起来的）",
			is_equal_approx(top_a, SS.HAZE_ALPHA * SS.HAZE_TOP_RATIO), true)
	_check("顶上比底下淡得多（三倍以上）", bottom_a > top_a * 3.0, true)
	_check("最左边完全透明", _alpha(quads, 0, 0, 0), 0.0)
	# 中间那一段左右两个顶点都是全浓度 —— 少了这个，沙层就成了一个三角形，
	# 整片风区看着中间亮两头黑
	_check("中间一段没有横向渐变", is_equal_approx(_alpha(quads, 0, mid, 1), SS.HAZE_ALPHA), true)

	# **缝**：相邻格子共用的那条边，两边算出来的透明度必须一模一样。
	# 不一样就是一条看得见的直线，放在渐变里格外显眼。
	# 顶点顺序是「左下、右下、右上、左上」，所以竖着接的是 (2 对 1) 和 (3 对 0)。
	var worst := 0.0
	var pairs := 0
	for band in SS.HAZE_BANDS:
		for seg in SS.HAZE_SEGS - 1:
			worst = maxf(worst, absf(_alpha(quads, band, seg, 1) - _alpha(quads, band, seg + 1, 0)))
			pairs += 1
	for band in SS.HAZE_BANDS - 1:
		for seg in SS.HAZE_SEGS:
			worst = maxf(worst, absf(_alpha(quads, band, seg, 2) - _alpha(quads, band + 1, seg, 1)))
			worst = maxf(worst, absf(_alpha(quads, band, seg, 3) - _alpha(quads, band + 1, seg, 0)))
			pairs += 2
	print("  比了 %d 条共用的边，最大的浓度差 %.6f" % [pairs, worst])
	_check("格子之间没有缝", is_zero_approx(worst), true)


## 取第 `band` 竖格、第 `seg` 横段那个四边形第 `v` 个顶点的透明度。
func _alpha(quads: Array, band: int, seg: int, v: int) -> float:
	var quad := quads[band * SS.HAZE_SEGS + seg] as Polygon2D
	return quad.vertex_colors[v].a


# ---------------------------------------------------------------- 沙线

func _streaks() -> void:
	print("=== 3. 沙线：分层、方向、抖动、两端淡出 ===")
	_check("沙线条数 = 中景 14 + 近景 3",
			_zone._streaks.size(), SS.STREAKS + SS.NEAR_STREAKS)

	var mid: Line2D = _zone.get_node_or_null("Streak0")
	var near: Line2D = _zone.get_node_or_null("Near0")
	_check("中景沙线在土坡之前、车之后（z = 0）", mid.z_index, 0)
	_check("近景沙线在车之前（z = 2，车的 z 见第 6 节）", near.z_index, 2)
	_check("近景比中景快", SS.NEAR_SPEED_MIN > SS.STREAK_SPEED_MAX, true)
	_check("每条沙线都套了粗细剖面（两头细中间粗）", mid.width_curve != null, true)
	_check("剖面采样是 0.15 / 1.0 / 0.25",
			[snappedf(mid.width_curve.sample(0.0), 0.01),
			snappedf(mid.width_curve.sample(0.45), 0.01),
			snappedf(mid.width_curve.sample(1.0), 0.01)], [0.15, 1.0, 0.25])
	_check("一条沙线是三段（中间那点抬高，成一缕弧）", mid.points.size(), 3)

	# 往左飘。**先摆到中间**再量：摆在原地量的话，还没走满 0.5 秒就先绕回右边了，
	# 位移是负的，看起来像「风把沙线吹反了」。
	mid.position = Vector2(LEFT + WIDTH * 0.5, RIM)
	var x0: float = mid.position.x
	var speed: float = _zone._speeds[0]
	_step(0.5)
	var moved := x0 - mid.position.x
	print("  0.5s 走了 %.0f 像素（速度 %.0f）" % [moved, speed])
	_check("沙线往左飘（顺风）", moved > 0.0, true)
	_check("速度乘了风势、但没有乘飞",
			moved > speed * 0.5 * 0.35 and moved < speed * 0.5 * 1.5, true)

	# 上下抖动：高度在基准附近来回，而且幅度不会超出这条线自己的幅度
	var y0: float = mid.position.y
	var drifted := false
	var worst_dev := 0.0
	for i in 40:
		_step(DT)
		if absf(mid.position.y - y0) > 0.5:
			drifted = true
		worst_dev = maxf(worst_dev, absf(mid.position.y - _zone._bases[0]))
	print("  抖动幅度最大 %.1f 像素（这条线自己的幅度 %.1f）" % [worst_dev, _zone._amps[0]])
	_check("沙线在上下抖（不是一条直线平移）", drifted, true)
	_check("抖动没超出自己的幅度", worst_dev <= _zone._amps[0] + 0.01, true)

	# 绕回：推到左边界外面，跑一帧，应该从右边回来
	mid.position = Vector2(LEFT - 9999.0, RIM)
	_step(DT)
	_check("绕回右沿", snappedf(mid.position.x, 1.0), LEFT + WIDTH)
	_check("绕回来重掷的高度仍在风区里",
			mid.position.y <= RIM + SS.WIND_BELOW
			and mid.position.y >= RIM - SS.WIND_TOP, true)

	# 两端淡出
	_check("淡出系数：左端 0、中间 1、右端 0",
			[SS._edge_fade(0.0), SS._edge_fade(0.5), SS._edge_fade(1.0)],
			[0.0, 1.0, 0.0])
	mid.position = Vector2(LEFT, RIM)
	_step(DT)
	var at_edge: float = mid.modulate.a
	mid.position = Vector2(LEFT + WIDTH * 0.5, RIM)
	_step(DT)
	var at_mid: float = mid.modulate.a
	print("  贴左沿时 %.3f，中间 %.2f" % [at_edge, at_mid])
	# 不是「正好 0」：这一帧它已经往左走了几个像素，落在淡出段的最外沿上，
	# 所以这里比的是「几乎看不见」。
	_check("贴左沿时几乎透明（进出风区是渐进的）", at_edge < 0.05, true)
	_check("中间是实的", at_mid > 0.25, true)


# ---------------------------------------------------------------- 风势

func _gust() -> void:
	print("=== 4. 风势：一阵一阵，但不会吹飞也不会停 ===")
	var lo := 99.0
	var hi := -99.0
	for i in 1200:
		var g: float = _zone._gust_at(float(i) * 0.1)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	print("  采样 120 秒：风势 %.2f ～ %.2f" % [lo, hi])
	_check("风势有起伏（不是一条恒定的直线）", hi - lo > 0.3, true)
	_check("有下限（不会完全停风）", lo >= 0.35, true)
	_check("有上限（不会抽风）", hi <= 1.5, true)

	# 相邻两块风区不能同相位：否则一整排区块一起喘气，看着像整个屏幕在调亮度
	var other: Node2D = SANDSTORM.instantiate()
	other.call("setup", Rect2(LEFT + 9999.0, RIM, WIDTH, 0.0), RIM)
	_check("相邻区块的相位不同", _zone._phase != other._phase, true)
	_check("同一时刻两边的风势不同", _zone._gust_at(3.0) != other._gust_at(3.0), true)
	other.free()

	# 整片沙跟着风势浓淡，但**幅度比沙线小** —— 它是远处的背景，
	# 跟着沙线一起大幅闪会像有人在调亮度。
	var t_hi := 0.0
	var t_lo := 0.0
	var hi_g := -99.0
	var lo_g := 99.0
	for i in 400:
		var t := float(i) * 0.1
		var g: float = _zone._gust_at(t)
		if g > hi_g:
			hi_g = g
			t_hi = t
		if g < lo_g:
			lo_g = g
			t_lo = t
	_zone._time = t_hi
	_step(DT)
	var haze_hi: float = _zone._haze.modulate.a
	_zone._time = t_lo
	_step(DT)
	var haze_lo: float = _zone._haze.modulate.a
	var lit_hi := clampf(hi_g * 0.9, 0.0, 1.0)
	var lit_lo := clampf(lo_g * 0.9, 0.0, 1.0)
	print("  风势 %.2f→沙层 %.2f（沙线 %.2f），风势 %.2f→沙层 %.2f（沙线 %.2f）" % [
		hi_g, haze_hi, lit_hi, lo_g, haze_lo, lit_lo])
	_check("风大时沙更浓", haze_hi > haze_lo, true)
	_check("沙层的浓淡幅度比沙线小", haze_hi - haze_lo < lit_hi - lit_lo, true)
	# 0.45 是 `_process` 里的下限，回来是 0.44999998（同 float32），所以留一点余量
	_check("沙层不会淡到看不见", haze_lo > 0.44, true)
	_check("沙层不会浓到糊住画面", haze_hi <= 1.0, true)


# ---------------------------------------------------------------- 沙团

func _puffs() -> void:
	print("=== 5. 贴地沙团：生、飘、散 ===")
	# 换个干净的风区：前面几节已经把这块的时间轴带乱了
	var zone: Node2D = _build_zone()
	zone._time = 0.0
	_step_zone(zone, 1.0)
	print("  1 秒后活着 %d 颗（池子里 %d 个槽）" % [_alive(zone), zone._puffs.size()])
	_check("风一吹就有沙团起来", _alive(zone) > 0, true)
	_check("池子没超上限", zone._puffs.size() <= SS.PUFFS, true)

	var x_before := _avg_x(zone)
	_step_zone(zone, 0.5)
	var x_after := _avg_x(zone)
	print("  平均位置 %.0f → %.0f" % [x_before, x_after])
	_check("沙团也被吹着往左走", x_after < x_before, true)

	# 地面是硬的：硬把一颗沙团按到地下，跑一帧它应该回到地面以上
	var p = zone._puffs[0]
	p.life = 1.0
	p.span = 1.0
	p.pos = Vector2(LEFT + WIDTH * 0.5, RIM + 200.0)
	_step_zone(zone, DT)
	_check("沙团不会钻到地面以下", p.pos.y, RIM + 6.0)

	var escaped := 0
	for q in zone._puffs:
		if q.life > 0.0 and (q.pos.x < LEFT - 0.5 or q.pos.x > LEFT + WIDTH + 0.5):
			escaped += 1
	_check("没有沙团飘出风区", escaped, 0)

	# 风大生成的沙团更多
	var t_hi := 0.0
	var t_lo := 0.0
	var hi_g := -99.0
	var lo_g := 99.0
	for i in 400:
		var t := float(i) * 0.1
		var g: float = zone._gust_at(t)
		if g > hi_g:
			hi_g = g
			t_hi = t
		if g < lo_g:
			lo_g = g
			t_lo = t
	var windy: Node2D = _build_zone()
	var calm: Node2D = _build_zone()
	windy._time = t_hi
	calm._time = t_lo
	_step_zone(windy, 1.0)
	_step_zone(calm, 1.0)
	print("  风势 %.2f 起了 %d 颗，风势 %.2f 起了 %d 颗" % [
		hi_g, _alive(windy), lo_g, _alive(calm)])
	_check("风大的时候沙团更多", _alive(windy) > _alive(calm), true)

	# 会散：把寿命压到见底，再跑一小步（生成率 16/s × 0.017s 攒不满一颗新的）
	for q in zone._puffs:
		q.life = 0.01
	zone._emit = 0.0
	zone._time = t_hi
	_step_zone(zone, DT)
	_check("沙团会散尽", _alive(zone), 0)

	# 画出来的样子：越老越大、越大越淡、两头透明、明暗不一
	var v = zone._puffs[0]
	v.pos = Vector2(LEFT + WIDTH * 0.5, RIM)
	v.size = 10.0
	v.tint = 1.0
	# 刚生出来（t = 1）和将散尽（t = 0）两个端点各量一次，半径的两头就是它俩
	v.life = 2.0
	v.span = 2.0
	var young: Dictionary = zone.puff_visual(v)
	v.life = 0.0
	var old: Dictionary = zone.puff_visual(v)
	print("  刚生出来：半径 %.1f 透明度 %.3f；将散时：半径 %.1f 透明度 %.3f" % [
		young["radius"], young["alpha"], old["radius"], old["alpha"]])
	_check("刚生出来是最实的", is_equal_approx(young["alpha"], SS.PUFF_ALPHA), true)
	_check("越大越淡", old["alpha"] < young["alpha"], true)
	_check("越老越大（散开）", old["radius"] > young["radius"], true)
	_check("散尽那一刻半径 = 基础半径 × 1.9",
			is_equal_approx(old["radius"], 10.0 * SS.PUFF_GROW), true)
	_check("散尽那一刻也透明（不然地上会留一串圆点）", old["alpha"], 0.0)
	v.pos = Vector2(LEFT, RIM)
	v.life = 2.0
	_check("贴着左沿的沙团是透明的", zone.puff_visual(v)["alpha"], 0.0)
	v.tint = 1.15
	_check("明暗抖动真的用上了（否则沙团是一片贴纸）",
			zone.puff_visual(v)["color"].r > SS.SAND_COLOR.r, true)

	zone.free()
	windy.free()
	calm.free()


func _alive(zone: Node2D) -> int:
	var n := 0
	for p in zone._puffs:
		if p.life > 0.0:
			n += 1
	return n


func _avg_x(zone: Node2D) -> float:
	var sum := 0.0
	var n := 0
	for p in zone._puffs:
		if p.life > 0.0:
			sum += p.pos.x
			n += 1
	return sum / maxf(1.0, float(n))


# ---------------------------------------------------------------- 和车的先后

## 近景沙线要**画在车前面**、中景要画在车后面，靠的是 z_index 和车的 z 比大小。
## 这里去真场景里读一次车的 z，而不是把「车是 1」抄成常量 —— 抄的那份迟早会过期。
func _car_depth() -> void:
	print("=== 6. 和车的先后（读真场景，不抄常量） ===")
	var main: Node2D = MAIN.instantiate()
	var car_z: int = (main.get_node("Car") as Node2D).z_index
	var near_z: int = (_zone.get_node("Near0") as Line2D).z_index
	var mid_z: int = (_zone.get_node("Streak0") as Line2D).z_index
	var haze_z: int = (_zone.get_node("Haze") as Node2D).z_index
	print("  车 z=%d，近景 %d，中景 %d，远处沙层 %d" % [car_z, near_z, mid_z, haze_z])
	_check("近景沙线盖在车上面（车是开在沙里）", near_z > car_z, true)
	_check("中景沙线在车后面", mid_z < car_z, true)
	_check("远处沙层在中景后面", haze_z < mid_z, true)
	main.free()
	_zone.free()
