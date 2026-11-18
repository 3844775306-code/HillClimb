extends Node
## 卡沟分析：车为什么会卡在沟里出不来。
##
## 三段：
##
##   A 天然地形 —— 噪声谷底的坡度和深度分布。量的是「自然沟」能不能困住车。
##   B 特殊地形的坑 —— 吊桥沟 / 火山口 / 冰湖盆的剖面，以及**把车丢进去会怎样**
##     （死亡区够不够、有没有一块「活着但爬不出来」的地方）。
##   C 真实地形跑 —— 全油门跑一局，每次卡住抓现场并归类。
##
## 车的关键几何全部来自 scenes/car.tscn（**车改了这里要跟着改**，否则量的是另一台车）：
##
##   车壳底面  168 px，从 (-78, 8) 到 (90, 6)
##   轮子      r = 21，轮心比车壳底面低 10.3 px，轮底比车壳底面低 31.3 px
##   两轮轮距  110 px（-52 → +58），轮心都在车壳底面的水平跨度之内
##
## 最后一条是问题的核心：轮子藏在车壳底下 31 px，所以只要沟够窄够陡，车壳底面会
## 先架在两壁上把轮子吊空 —— 而推力只能从轮子来，吊空了就一步也动不了。

const CAR_SCENE := preload("res://scenes/car.tscn")
const MAIN := preload("res://scenes/main.tscn")

## 跑哪几段。调试时改成 "A" 只跑几何扫描（毫秒级）。
const SECTIONS := "B"

const STEP := 20.0            ## = HillTerrain.POINT_SPACING，折线顶点间距
const SEED := 1337
const SCAN_FROM := 700.0
const SCAN_TO := 40000.0
## 从谷底往外爬多高算「这一道壁的坡度」。车要爬出的就是这一段 —— 量全程平均坡度
## 会把「陡壁 + 缓顶」的沟报成缓坡，而车实际卡在陡壁那一段。
const ESCAPE_RISE := 30.0

## 车壳底面两端（car.tscn 的 CS_body 底部两点）。
const BOTTOM: Array[Vector2] = [Vector2(-78.0, 8.0), Vector2(90.0, 6.0)]
## 轮心（车局部坐标）与半径。
const WHEELS: Array[Vector2] = [Vector2(-52.0, 18.0), Vector2(58.0, 18.0)]
const WHEEL_R := 21.0

## 判定「卡住」：连续这么久没有推进 20 px。
const STALL_AFTER := 1.5

var _car: HillCar
## car.gd 里的真实油箱容量。测试里别处会把它改成 1e9 以便长跑，所以单独记一份。
var _fuel_max := 100.0
var _com_local := Vector2.ZERO
var _world: Node
var _death_reason := ""


# ---------------------------------------------------------------- 地形折线

## 一条地形折线。只在区块顶点上取高度、顶点之间线性插值 —— 这才是车真正撞到的东西。
## 直接调 height_at() 等于把折线当成光滑曲线，量出来的坡度会偏小，架住与否也会判错。
class Profile:
	var x0: float
	var step: float
	var ys: PackedFloat64Array

	func height(x: float) -> float:
		var t := (x - x0) / step
		var i := clampi(int(floor(t)), 0, ys.size() - 2)
		return lerpf(ys[i], ys[i + 1], t - float(i))

	## 点到地表的距离（取 ±80 px 内的最近线段）。轮子悬空与否看的是这个，
	## 不是「轮底和地表的高度差」—— 陡壁上后者会严重高估间隙。
	func dist_to_surface(p: Vector2) -> float:
		var i0 := clampi(int(floor((p.x - 80.0 - x0) / step)), 0, ys.size() - 2)
		var i1 := clampi(int(ceil((p.x + 80.0 - x0) / step)), 0, ys.size() - 2)
		var best := 1.0e20
		for i in range(i0, i1 + 1):
			var a := Vector2(x0 + float(i) * step, ys[i])
			var b := Vector2(x0 + float(i + 1) * step, ys[i + 1])
			best = minf(best, _seg_dist(p, a, b))
		return best

	func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		return p.distance_to(a + ab * t)


func _profile_from_terrain(map_id: String) -> Profile:
	var terrain := HillTerrain.new()
	terrain.map_id = map_id
	terrain.world_seed = SEED
	add_child(terrain)
	var prof := Profile.new()
	prof.x0 = SCAN_FROM
	prof.step = STEP
	var n := int((SCAN_TO - SCAN_FROM) / STEP) + 1
	for i in n:
		prof.ys.append(terrain.height_at(SCAN_FROM + float(i) * STEP))
	terrain.queue_free()
	return prof


# ---------------------------------------------------------------- A 天然地形

func _section_a() -> void:
	print("=== A 天然地形（折线，%d~%d px，种子 %d）===" % [SCAN_FROM, SCAN_TO, SEED])
	for map_id in Maps.IDS:
		var prof := _profile_from_terrain(map_id)
		var minima := PackedInt32Array()
		for i in range(1, prof.ys.size() - 1):
			if prof.ys[i] < prof.ys[i - 1] and prof.ys[i] <= prof.ys[i + 1]:
				minima.append(i)

		var wall := {25: 0, 45: 0, 55: 0, 65: 0, 75: 0}
		var deep_steep := 0
		var traps := 0
		var worst := {}
		for i in minima:
			var la := _wall_angle(prof, i, -1)
			var ra := _wall_angle(prof, i, 1)
			var steep := maxf(la, ra)
			for k in [25, 45, 55, 65, 75]:
				if steep >= float(k):
					wall[k] += 1
			var rim := maxf(_rim(prof, i, -1), _rim(prof, i, 1))
			var depth := rim - prof.ys[i]
			if depth > 40.0 and steep > 45.0:
				deep_steep += 1
			# 架住的前提是两壁都够陡（见 _bridge_pose 的推导），先粗筛再精搜
			var pose := {}
			if la > 40.0 and ra > 40.0:
				pose = _bridge_pose(prof, prof.x0 + float(i) * STEP)
			if not pose.is_empty():
				traps += 1
				if worst.is_empty() or steep > float(worst["wall"]):
					worst = {
						"x": prof.x0 + float(i) * STEP, "wall": steep,
						"depth": depth, "pose": pose,
					}
		var km := (SCAN_TO - SCAN_FROM) / 1000.0
		var lo := 1.0e20
		var hi := -1.0e20
		var max_seg := 0.0
		var steep_segs := 0
		for i in prof.ys.size():
			lo = minf(lo, prof.ys[i])
			hi = maxf(hi, prof.ys[i])
			if i + 1 < prof.ys.size():
				var seg := rad_to_deg(atan2(prof.ys[i] - prof.ys[i + 1], STEP))
				if absf(seg) > 40.0:
					steep_segs += 1
				if absf(seg) > absf(max_seg):
					max_seg = seg
		print("  %-8s 高度 %6.0f~%-6.0f  最陡单格 %+.0f°  单格 >40° 的 %3d 个" % [
			map_id, lo, hi, max_seg, steep_segs,
		])
		print("           谷底 %4d 个（%.0f 个/km）  壁≥25°%4d  ≥45°%3d  ≥55°%3d  ≥65°%2d  ≥75°%2d" % [
			minima.size(), float(minima.size()) / km,
			wall[25], wall[45], wall[55], wall[65], wall[75],
		])
		print("           深 >40px 且壁 >45°：%3d   车壳能架住：%d" % [deep_steep, traps])
		if not worst.is_empty():
			print("           最陡的架住点：x=%.0f  壁 %.1f°  深 %.1f px  位姿 %s" % [
				worst["x"], worst["wall"], worst["depth"], worst["pose"],
			])


## 谷底往一侧走，第一次抬升满 ESCAPE_RISE 的那段壁的角度（度）。抬不起来算 0°。
func _wall_angle(prof: Profile, i: int, dir: int) -> float:
	var h0 := prof.ys[i]
	var j := i
	for _k in 40:
		j += dir
		if j < 0 or j >= prof.ys.size():
			return 0.0
		if absf(h0 - prof.ys[j]) >= ESCAPE_RISE:
			break
	return rad_to_deg(atan2(h0 - prof.ys[j], absf(float(j - i)) * STEP))


## 谷底一侧 200 px 内的最高点（沟沿）。
func _rim(prof: Profile, i: int, dir: int) -> float:
	var h := prof.ys[i]
	for k in range(1, 11):
		var j := i + dir * k
		if j < 0 or j >= prof.ys.size():
			break
		h = minf(h, prof.ys[j])
	return h


## 车壳能不能「架」在这条沟上：轮子悬空、车壳底面搁在两壁上。
##
## 同时成立三条才算：
##   1. 车壳底面有 ≥2 段互不相连的接触（分别落在两壁上）
##   2. 最左和最右接触点把重心夹在中间（否则车会翻下去，不会停在这）
##   3. 两个轮子都离地（碰了地就还有牵引力，能滚出来）
##
## 返回位姿描述（空字典 = 架不住）。搜索是穷举：俯仰 ±24°、水平 ±120 px。
##
## 为什么两壁都得陡（粗筛用的 40°）：假设接触点落在底面两端，两个轮子分别在
## 距各自接触点 26 px（前）和 32 px（后）处，轮底比底面低 31.3 px。轮子要离地就要
##
##     tan(壁角) > 31.3 / (接触到轮心的水平距离)
##
## 即前轮那侧的壁要 > 50°、后轮那侧 > 44°。不到这个角度，轮子必然还压在壁上，
## 有牵引力就能滚出来，不成其为死局。
func _bridge_pose(prof: Profile, center_x: float) -> Dictionary:
	var samples := 48
	for pitch_deg in range(-24, 25, 3):
		var phi := deg_to_rad(float(pitch_deg))
		var e0: Vector2 = BOTTOM[0].rotated(phi)
		var e1: Vector2 = BOTTOM[1].rotated(phi)
		for dx in range(-120, 121, 6):
			var ox := center_x + float(dx)
			# 让底面最低的那个采样点正好贴地：y 偏移取「地表 - 底面」的最大值
			var y_off := -1.0e20
			var pts := PackedVector2Array()
			for s in samples + 1:
				var p := e0.lerp(e1, float(s) / float(samples))
				pts.append(p)
				y_off = maxf(y_off, prof.height(p.x + ox) - p.y)
			var runs := []
			var run_start := -1
			for s in samples + 1:
				var gap: float = absf(pts[s].y + y_off - prof.height(pts[s].x + ox))
				if gap < 0.6:
					if run_start < 0:
						run_start = s
				elif run_start >= 0:
					runs.append([run_start, s - 1])
					run_start = -1
			if run_start >= 0:
				runs.append([run_start, samples])
			if runs.size() < 2:
				continue
			var x_lo: float = pts[runs[0][0]].x + ox
			var x_hi: float = pts[runs[-1][1]].x + ox
			if x_hi - x_lo < 100.0:
				continue
			var com: Vector2 = _com_local.rotated(phi) + Vector2(ox, y_off)
			if com.x < x_lo or com.x > x_hi:
				continue
			var clear := []
			for w: Vector2 in WHEELS:
				var c: Vector2 = w.rotated(phi) + Vector2(ox, y_off)
				clear.append(prof.dist_to_surface(c) - WHEEL_R)
			if clear[0] > 1.0 and clear[1] > 1.0:
				return {
					"x": ox, "pitch": pitch_deg,
					"clear": "%.0f/%.0f" % [clear[0], clear[1]],
					"span": "%.0f" % (x_hi - x_lo),
				}
	return {}


# ---------------------------------------------------------------- B 特殊地形的坑

## 每张图的坑：先看剖面，再把车丢进去看结局。
##
## 剖面是**静态**的（和车无关）：坑多宽多深、壁多陡、死亡区盖到哪。
## 丢车是**动态**的：掉进去是死（死亡区够）还是活着卡在壁上（死亡区留了一条缝）。
func _section_b() -> void:
	print("")
	print("=== B 特殊地形的坑（种子 %d）===" % SEED)
	for map_id in Maps.IDS:
		print("  %-8s 特殊地形区块：%s" % [map_id, _feature_chunks(map_id)])
		await _pit_run(map_id)


## 该图在 0~60 号区块里所有带特殊地形的区块序号（连同挖多深）。
func _feature_chunks(map_id: String) -> String:
	var out := PackedStringArray()
	for i in range(0, 60):
		var kind := Maps.feature_at(SEED, map_id, i)
		if kind == Maps.FEATURE_NONE:
			continue
		out.append("%d(%s 深%.0f)" % [
			i, kind, Maps.feature_layout(kind)["depth"],
		])
	return "无" if out.is_empty() else " ".join(out)


func _pit_run(map_id: String) -> void:
	var index := _first_feature_chunk(map_id)
	var kind := Maps.feature_at(SEED, map_id, index)
	if kind == Maps.FEATURE_NONE:
		print("  %-8s 没有特殊地形" % map_id)
		return
	var rect := Maps.feature_rect(SEED, map_id, index, HillTerrain.CHUNK_WIDTH)
	var layout := Maps.feature_layout(kind)
	if rect.size.y <= 0.0:
		print("  %-8s %s（区块 %d）不挖地形，跳过" % [map_id, kind, index])
		return

	var main := await _spawn_main(map_id)
	var car: HillCar = main.car
	var terrain: HillTerrain = main.terrain
	var rim: float = terrain.height_at(rect.position.x)

	var x0 := rect.position.x
	var x1 := rect.position.x + rect.size.x
	var depth := rect.size.y
	# 死亡区：HillFeature.pit_hazard_rect —— 从坑沿往下 55% 才开始算
	var hz_top := rim + depth * 0.55
	var hz_bot := rim + depth + 80.0

	print("  %-8s %s  区块 %d  坑 x=%.0f~%.0f（宽 %.0f，深 %.0f）  坑沿 y=%.0f" % [
		map_id, kind, index, x0, x1, rect.size.x, depth, rim,
	])
	# 剖面的形状：每格 20 px 的坡度
	var slopes := PackedStringArray()
	var max_wall := 0.0
	var x := x0 - 120.0
	while x <= x1 + 120.0:
		var a: float = terrain.height_at(x)
		var b: float = terrain.height_at(x + STEP)
		var s := rad_to_deg(atan2(a - b, STEP))
		# 只看坑范围内的壁
		if x >= x0 - 40.0 and x <= x1 + 40.0:
			max_wall = maxf(max_wall, absf(s))
		slopes.append("%+.0f" % s)
		x += STEP
	print("           每格坡度(%+.0f° 最陡): %s" % [max_wall, " ".join(slopes)])
	print("           死亡区 y=%.0f~%.0f  → 坑沿到死亡区之间有 %.0f px 的『活着但出不去』带" % [
		hz_top, hz_bot, hz_top - rim,
	])
	print("           助跑坡 ramp_h=%.0f ramp_len=%.0f  圆角 edge=%.0f" % [
		float(layout["ramp_h"]), float(layout["ramp_len"]), float(layout["edge"]),
	])

	# 1) 从出生点真·开过去。**不瞬移** —— 瞬移会把车摆进区块还没建好的地方，
	#    或者摆进刚建好的碰撞体里，物理会把车弹飞，量到的就不是地形问题了。
	var t1 := await _drive_to_pit(map_id, rect, rim, depth)
	print("           开过去：%s  到 x=%.0f（坑右沿 %.0f）" % [t1["result"], t1["x"], x1])
	if t1["fell"]:
		print("              进过坑：最低 y=%.0f，比坑沿低 %.0f px" % [t1["lowest"], t1["lowest"] - rim])

	# 2) 沿坑底扫一遍：坑底每一段是死是活。
	await _floor_sweep(map_id, rect, rim, depth)

	# 3) 从坑正上方落下：落在桥面/冰面上以后还走得动吗。
	await _land_on_feature(map_id, rect, rim, depth)


## 从出生点全油门开到坑那边，每 0.25 s 采一次轨迹。
##
## 打印轨迹是为了把「物理爆炸」和「地形卡住」分开：车都被弹到 y=-2000 了还
## 讨论坡度就没意义了。
func _drive_to_pit(map_id: String, rect: Rect2, rim: float, depth: float) -> Dictionary:
	var main := await _spawn_main(map_id)
	var car: HillCar = main.car
	var x0 := rect.position.x
	var x1 := rect.position.x + rect.size.x
	_death_reason = ""
	Input.action_press("drive_forward")
	var t := 0.0
	var lowest := 1.0e20
	var fell := false
	var line := ""
	var last_log := 0.0
	while t < 20.0 and car.alive:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		var p: Vector2 = car.chassis.global_position
		if p.x > x0 and p.x < x1:
			lowest = minf(lowest, p.y)
			if p.y > rim + 20.0:
				fell = true
		# 靠近坑以后每 0.25 s 都打 —— 过桥/过火山口就发生在这一两秒里，
		# 每秒一采会正好跳过去。
		if t - last_log >= (0.25 if p.x > x0 - 400.0 else 1.0):
			last_log = t
			line += "\n              t=%-4.2f x=%-7.0f y=%-7.0f 速度 %-5.0f %s" % [
				t, p.x, p.y, car.chassis.linear_velocity.length(),
				"死" if not car.alive else "",
			]
		if p.x > x1 + 400.0:
			break
	Input.action_release("drive_forward")
	var result := "活着开过坑" if car.alive else "死了（%s）" % _death_reason
	var stuck_on_approach := car.alive and car.chassis.global_position.x <= x1 + 400.0
	if stuck_on_approach:
		result = "活着，但没开过去"
	print(line)
	# 自救测试必须在释放场景之前做 —— 车和区块都是这一局的。
	if stuck_on_approach:
		await _try_escape(car)
	var out := {
		"x": car.chassis.global_position.x, "alive": car.alive,
		"fell": fell, "lowest": lowest, "result": result,
	}
	main.queue_free()
	_world = null
	await get_tree().process_frame
	return out


## 沿坑底扫一遍：把车**直接生成**在坑底每个点上，看它是死是活、能不能爬出来。
##
## 这是整个分析里最关键的一段。死亡区是 `rim_y + 0.55 × 深度` 往下的一条矩形
## （见 [method HillFeature.pit_hazard_rect]），而 `rim_y` 是**坑左沿那一点**的
## 地表高度 —— 可是坑底的实际高度是 `base_height(x) + 深度`，`base_height` 沿路
## 起伏 ±140 px（[constant HillTerrain.MAX_AMPLITUDE]）。所以坑底哪一段落在死亡区
## 里，取决于当地地形相对左沿高低多少，而不是一个定值。
##
## 死区底边在 `rim + 深度 + 80`，坑底在 `base(x) + 深度`，于是
##
##     当 base(x) − base(左沿) > 80 px 时，**这一段坑底在死亡区下方**
##
## 车落在那一段上就活着 —— 而坑壁是 84°，它一步也爬不上去。
func _floor_sweep(map_id: String, rect: Rect2, rim: float, depth: float) -> void:
	var x0 := rect.position.x
	var x1 := rect.position.x + rect.size.x
	var probe := HillTerrain.new()
	probe.map_id = map_id
	probe.world_seed = SEED
	add_child(probe)
	var xs: Array[float] = []
	var floors: Array[float] = []
	var bases: Array[float] = []
	for i in range(1, 10):
		var x := x0 + float(i) * (x1 - x0) / 10.0
		xs.append(x)
		floors.append(probe.height_at(x))
		bases.append(probe._base_height(x))
	var base0 := bases[0]
	probe.queue_free()
	await get_tree().process_frame

	print("           坑底扫描（车直接生成在坑底，静置 2 s）：")
	var live: Array[int] = []
	for i in xs.size():
		_death_reason = ""
		var main := await _spawn_main(map_id, Vector2(xs[i], floors[i] - 39.0))
		var car: HillCar = main.car
		var t := 0.0
		while t < 2.0 and car.alive:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		var y: float = car.chassis.global_position.y
		if car.alive:
			live.append(i)
			print("              x=%-6.0f 坑底 y=%-5.0f 基面差 %+5.0f  活着（%s）" % [
				xs[i], floors[i], bases[i] - base0,
				"停在 x=%.0f" % car.chassis.global_position.x,
			])
		else:
			print("              x=%-6.0f 坑底 y=%-5.0f 基面差 %+5.0f  死了（%s）" % [
				xs[i], floors[i], bases[i] - base0, _death_reason,
			])
		main.queue_free()
		_world = null
		await get_tree().process_frame
	if live.is_empty():
		print("              → 坑底全部致命，掉进去必死，不存在「卡住」")
		return
	# 活下来的那段，试试玩家能不能自救。只测一格，够判断了。
	var i := live[0]
	var main := await _spawn_main(map_id, Vector2(xs[i], floors[i] - 39.0))
	await get_tree().create_timer(1.0).timeout
	print("              → 坑底 x=%.0f 这一段活得下来，试自救：" % xs[i])
	await _try_escape(main.car)
	main.queue_free()
	_world = null
	await get_tree().process_frame


## 把车生成在坑正上方 60 px 处，让它自己落到桥面/冰面上，然后看能不能开走。
##
## 吊桥是 14 块独立刚体板串成的链，板子是**转着**摆的（沿弧线切线），两块板
## 相接的地方天生是个 V 形缝。车壳底面离车轮底只有 31 px，正好是能卡进这种
## 缝里的高度。这一段量的是「落在桥面上会不会被卡住」。
func _land_on_feature(map_id: String, rect: Rect2, rim: float, depth: float) -> void:
	var mid := rect.position.x + rect.size.x * 0.5
	var main := await _spawn_main(map_id, Vector2(mid, rim - 60.0))
	var car: HillCar = main.car
	var t := 0.0
	var min_speed := 1.0e20
	while t < 2.0 and car.alive:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		min_speed = minf(min_speed, car.chassis.linear_velocity.length())
	if not car.alive:
		print("           落在坑面上：死了（%s）" % _death_reason)
		main.queue_free()
		_world = null
		await get_tree().process_frame
		return
	var y: float = car.chassis.global_position.y
	print("           落在坑面上：活着，停在 y=%.0f（坑沿 %.0f → 坑沿下 %.0f px，坑深 %.0f）速度 %.0f" % [
		y, rim, y - rim, depth, car.chassis.linear_velocity.length(),
	])
	await _try_escape(car)
	# 自救之后有没有挪到对岸去？只往前走几百像素不算过关，得到坑外面。
	var end_x: float = car.chassis.global_position.x
	print("              试完自救的位置 x=%.0f（坑 %.0f~%.0f）%s" % [
		end_x, rect.position.x, rect.position.x + rect.size.x,
		"→ 还是没出去" if end_x < rect.position.x + rect.size.x else "→ 出去了",
	])
	main.queue_free()
	_world = null
	await get_tree().process_frame


## 卡住了就试试油门、再试试倒车，看玩家有没有自救的办法。
##
## 轮速和触地数要在**踩着油门的时候**采 —— 松开之后轮子会自己转停，采到的是 0，
## 看起来像「轮子被卡死」，其实是采样时机错了。
func _try_escape(car: HillCar) -> void:
	var x_start: float = car.chassis.global_position.x
	Input.action_press("drive_forward")
	await get_tree().create_timer(3.0).timeout
	var spin := maxf(absf(car.rear_wheel.angular_velocity), absf(car.front_wheel.angular_velocity))
	var belly := car.chassis.get_colliding_bodies().size()
	Input.action_release("drive_forward")
	var fwd: float = car.chassis.global_position.x - x_start
	Input.action_press("drive_back")
	await get_tree().create_timer(3.0).timeout
	Input.action_release("drive_back")
	var back: float = car.chassis.global_position.x - x_start
	print("              自救：油门 %+.0f px  倒车 %+.0f px  油门中的轮速 %.0f  车壳触地 %d → %s" % [
		fwd, back, spin, belly,
		"卡死" if absf(fwd) < 20.0 and absf(back) < 20.0 else "能挪动",
	])
	if absf(fwd) < 20.0 and absf(back) < 20.0:
		await _dump_wedge(car)
		await _wait_death(car, 90.0)


## 卡死之后就这么耗着，看它最后是怎么结束的。
##
## 这一条决定了「卡在沟里」到底是**永久卡死**（玩家只能自己退游戏），还是
## **卡住之后必死**（燃油烧完）。两者的修法不一样，所以必须量出来。
func _wait_death(car: HillCar, limit: float) -> void:
	# 其它几段为了跑得久把油加到了 1e9，这里要换回**真实油量**再等：
	# 卡在坑里既碰不到油桶也走不了，结局完全由油耗决定，用假油量就量不出东西。
	car.fuel_max = _fuel_max
	car.fuel = _fuel_max
	var fuel0: float = car.fuel
	var t := 0.0
	Input.action_press("drive_forward")
	while t < limit and car.alive:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
	Input.action_release("drive_forward")
	if car.alive:
		print("                 耗着 %.0f s 还活着（燃油 %.0f→%.0f，没踩油门）" % [
			t, fuel0, car.fuel,
		])
	else:
		print("                 耗着 %.0f s 后死了（%s）—— 玩家什么都做不了，只能等死" % [
			ceili(t), _death_reason,
		])


## 卡死现场的车身姿态：车壳哪个角撑着、两个轮子到底离地没有、身下那道空档多宽。
##
## 离地用**带符号的高度差**（`地表 y − 点 y`），不用 `dist_to_surface`：
## 后者是「到折线的最近距离」，永远是正的，点埋进地里时照样给个正数，
## 陡壁附近会把「陷进去」读成「离地 11 px」，正好判反。
func _dump_wedge(car: HillCar) -> void:
	var terrain := HillTerrain.new()
	terrain.map_id = car.map_id
	terrain.world_seed = SEED
	add_child(terrain)
	var chassis: RigidBody2D = car.chassis
	var x: float = chassis.global_position.x
	var prof := _local_profile(terrain, x)
	var phi := chassis.rotation
	var front_corner: Vector2 = BOTTOM[1].rotated(phi) + chassis.global_position
	var rear_corner: Vector2 = BOTTOM[0].rotated(phi) + chassis.global_position
	var rear_gap: float = prof.height(car.rear_wheel.global_position.x) - car.rear_wheel.global_position.y - WHEEL_R
	var front_gap: float = prof.height(car.front_wheel.global_position.x) - car.front_wheel.global_position.y - WHEEL_R
	var rear_side: float = prof.height(rear_corner.x) - rear_corner.y
	var front_side: float = prof.height(front_corner.x) - front_corner.y

	print("                 车身姿态：俯仰 %+.0f°  俯仰角速度 %+.1f  轮速 后%.0f 前%.0f" % [
		rad_to_deg(phi), chassis.angular_velocity,
		car.rear_wheel.angular_velocity, car.front_wheel.angular_velocity,
	])
	print("                 离地（正=悬空，0=贴着，负=陷进去）：后轮 %+.0f  前轮 %+.0f  车壳后角 %+.0f  车壳前角 %+.0f px" % [
		rear_gap, front_gap, rear_side, front_side,
	])
	# 车壳底面高度上，脚下那道空档有多宽 —— 和车壳长度比一比就知道是不是架住了。
	var bottom_y: float = maxf(rear_corner.y, front_corner.y)
	var left := x
	while left > x - 400.0 and prof.height(left) > bottom_y:
		left -= 5.0
	var right := x
	while right < x + 400.0 and prof.height(right) > bottom_y:
		right += 5.0
	print("                 车壳底面下方是空的：x %.0f~%.0f（宽 %.0f px），车壳长 168 px，轮距 110 px" % [
		left, right, right - left,
	])
	var wheels_up := rear_gap > 3.0 and front_gap > 3.0
	print("                 轮子转 %.0f rad/s 但车不动 → %s" % [
		maxf(absf(car.rear_wheel.angular_velocity), absf(car.front_wheel.angular_velocity)),
		"**两个轮子都悬空**，发动机再大也没有着力点" if wheels_up
		else "轮子还压在地上，是被地形形状顶住的",
	])
	terrain.queue_free()
	await get_tree().process_frame


## 每张图第一个带特殊地形的区块序号。
func _first_feature_chunk(map_id: String) -> int:
	for i in range(0, 60):
		if Maps.feature_at(SEED, map_id, i) != Maps.FEATURE_NONE:
			return i
	return -1


# ---------------------------------------------------------------- C 真实地形跑

func _section_c(map_id: String, seconds: float) -> void:
	print("")
	print("=== C 真实地形全油门跑（%s，种子 %d，%.0f s）===" % [map_id, SEED, seconds])
	var main := await _spawn_main(map_id)
	var car: HillCar = main.car
	var terrain: HillTerrain = main.terrain

	Input.action_press("drive_forward")
	var t := 0.0
	var best_x: float = car.chassis.global_position.x
	var progress_at := 0.0
	var dumped := false
	var stalls := []
	while t < seconds and car.alive:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		var x: float = car.chassis.global_position.x
		if x > best_x + 20.0:
			if dumped:
				stalls.append([progress_at, t - progress_at])
				dumped = false
			best_x = x
			progress_at = t
		elif t - progress_at > STALL_AFTER and not dumped:
			dumped = true
			_dump_stall(car, terrain, x, t, t - progress_at)
	Input.action_release("drive_forward")

	var metres := (best_x - Maps.START_OFFSET) / Maps.PIXELS_PER_METER
	print("  跑到 %.0f m，卡住 %d 次" % [metres, stalls.size()])
	for s in stalls:
		print("    第 %.1f s 起，卡了 %.1f s" % [s[0], s[1]])
	if dumped:
		print("    （结束时仍在卡住）")
	if not car.alive:
		print("    （中途死亡：%s）" % _death_reason)
	main.queue_free()
	_world = null
	await get_tree().process_frame


## 卡住现场：各刚体离地多少、车壳是哪个角在撑、前后壁多陡。
##
## 离地用**点到地表的距离**而不是高度差 —— 陡坡上高度差会把「贴着壁」算成
## 「离地几十像素」，正好判反。
func _dump_stall(car: HillCar, terrain: HillTerrain, x: float, t: float, stuck: float) -> void:
	var chassis: RigidBody2D = car.chassis
	var prof := _local_profile(terrain, x)
	var phi := chassis.rotation
	var front_corner: Vector2 = BOTTOM[1].rotated(phi) + chassis.global_position
	var rear_corner: Vector2 = BOTTOM[0].rotated(phi) + chassis.global_position
	var rear_gap: float = prof.dist_to_surface(car.rear_wheel.global_position) - WHEEL_R
	var front_gap: float = prof.dist_to_surface(car.front_wheel.global_position) - WHEEL_R
	print("  --- 卡住现场 t=%.1fs 卡了 %.1fs  x=%.0f ---" % [t, stuck, x])
	print("      俯仰 %+.1f°  速度 %.0f  轮速 后%.1f 前%.1f  触地 后%d 前%d 壳%d" % [
		rad_to_deg(phi), chassis.linear_velocity.length(),
		car.rear_wheel.angular_velocity, car.front_wheel.angular_velocity,
		car.rear_wheel.get_colliding_bodies().size(),
		car.front_wheel.get_colliding_bodies().size(),
		chassis.get_colliding_bodies().size(),
	])
	print("      离地：后轮 %+.1f  前轮 %+.1f  车壳前角 %+.1f  车壳后角 %+.1f  px（负=贴地）" % [
		rear_gap, front_gap, prof.dist_to_surface(front_corner), prof.dist_to_surface(rear_corner),
	])
	var line := "      每格坡度(°):"
	for k in range(-6, 7):
		var px: float = floorf(x / STEP) * STEP + float(k) * STEP
		var h: float = terrain.height_at(px)
		var h2: float = terrain.height_at(px + STEP)
		line += " %s%+.0f" % ["*" if k == 0 else "", rad_to_deg(atan2(h - h2, STEP))]
	print(line + "   （*=车所在格，+ = 下坡）")
	var wheels_up := rear_gap > 3.0 and front_gap > 3.0
	var belly := chassis.get_colliding_bodies().size() > 0
	var spinning: bool = absf(car.rear_wheel.angular_velocity) > 5.0 or absf(car.front_wheel.angular_velocity) > 5.0
	var kind := "?"
	if belly and wheels_up:
		kind = "车壳架住、两轮全悬空 —— 没有牵引力来源"
	elif belly and (rear_gap > 3.0 or front_gap > 3.0):
		kind = "车壳贴地且至少一轮悬空 —— 单轮驱动"
	elif spinning and chassis.linear_velocity.length() < 30.0:
		kind = "两轮都在打滑 —— 坡度/抓地不够（不是搁浅）"
	else:
		kind = "被地形顶住、没在打滑"
	print("      判定：%s" % kind)


func _local_profile(terrain: HillTerrain, x: float) -> Profile:
	var prof := Profile.new()
	prof.step = STEP
	prof.x0 = floorf(x / STEP) * STEP - 400.0
	for i in 41:
		prof.ys.append(terrain.height_at(prof.x0 + float(i) * STEP))
	return prof


# ---------------------------------------------------------------- 工具

## 关掉存档写入、清零升级，再起一局真正的 main。
## **必须走真场景**：坑的碰撞是地形挖的，死亡区是特殊地形节点摆的，两个都在
## 区块里，自己 new 一个 HillTerrain 是拿不到死亡区的。
##
## `car_at` 给出时把车生成在那里 —— 在**进树之前**改 Car 节点的位置，三个刚体和
## 两个关节是一起挪的，关节锚点不会错位。这一点很重要：事后去改三个刚体的
## `global_position` 会把 [PinJoint2D] 储存的局部锚点扯开，解算器一帧之内就能把车
## 弹到 y=-9000（实测过），量到的就全是瞬移的副产品了。
func _spawn_main(map_id: String, car_at := Vector2.INF) -> HillGame:
	if _world != null:
		_world.queue_free()
		await get_tree().process_frame
	SaveData.persist = false
	SaveData.reset_progress()
	SaveData.selected_map = map_id
	var main: HillGame = MAIN.instantiate()
	if car_at.is_finite():
		main.get_node("Car").position = car_at
	# 信号要在 `add_child` **之前**接上：车生成在坑底时第一帧就会撞上死亡区，
	# 晚一帧接就采不到死因（打印出来是空的）。
	_death_reason = ""
	var early: HillCar = main.get_node("Car")
	early.crashed.connect(_on_car_dead)
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	_world = main
	var car: HillCar = main.car
	car.fuel_max = 1.0e9
	car.fuel = 1.0e9
	for part in [car.chassis, car.rear_wheel, car.front_wheel]:
		part.contact_monitor = true
		part.max_contacts_reported = 8
	_death_reason = ""
	if not car.crashed.is_connected(_on_car_dead):
		car.crashed.connect(_on_car_dead)
	return main


func _on_car_dead(reason: String) -> void:
	_death_reason = reason


# ---------------------------------------------------------------- 主流程

func _ready() -> void:
	Engine.time_scale = 1.0   # 物理测试不能加速，见 README 的坑 #1
	SaveData.persist = false
	SaveData.reset_progress()
	await _read_car_shape()
	if "A" in SECTIONS:
		_section_a()
	if "B" in SECTIONS:
		await _section_b()
	if "C" in SECTIONS:
		# 荒漠这张图**一个坑都不挖**（沙尘暴只有风，没有地形），所以它是唯一
		# 能干净地回答「天然地形会不会把车卡住」的一张图。
		await _section_c(Maps.DESERT, 100.0)
		await _section_c(Maps.SNOW, 60.0)
		await _section_c(Maps.VOLCANO, 60.0)
	get_tree().quit()


## 从真车上读重心的局部坐标 —— 架住与否要看重心在不在两个接触点之间，
## 而这个值是 Godot 按碰撞形状自动算的，不能手抄。
func _read_car_shape() -> void:
	var car: HillCar = CAR_SCENE.instantiate()
	add_child(car)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_com_local = PhysicsServer2D.body_get_param(
		car.chassis.get_rid(), PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS
	)
	var inertia: float = PhysicsServer2D.body_get_param(
		car.chassis.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA
	)
	# 架住与否看的是**整车**重心：车壳 130 + 两个轮子 22+22（质量都在 car.tscn 里）
	_com_local = (_com_local * 130.0 + WHEELS[0] * 22.0 + WHEELS[1] * 22.0) / 174.0
	_fuel_max = car.fuel_max
	print("整车重心 (%.1f, %.1f)  车壳默认惯量 %.0f  max_wheel_speed=%.0f  motor_strength=%.0f  max_torque=%.0f" % [
		_com_local.x, _com_local.y, inertia,
		car.max_wheel_speed, car.motor_strength, car.max_torque,
	])
	car.queue_free()
	await get_tree().process_frame
