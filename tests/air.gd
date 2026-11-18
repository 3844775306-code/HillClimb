extends Node
## 腾空奖励（[constant HillCar.AIR_BONUS_TIERS]：2.5 秒起每 0.5 秒 50，4 秒后 100，
## 6 秒后 200，8 秒停发）的验证。
##
## 分五种情形，缺一不可：
##
## 1. **平路** —— 一根毛都不能给。只测「跳起来有钱」是不够的，奖励逻辑写歪
##    （比如忘判触地、`int()` 边界写反）最常见的表现就是**开车途中一直在发钱**，
##    这个情形专门钉死它。
## 2. **整条时间轴** —— [method HillCar.air_bonus_coins] / [method HillCar.air_bonus_tick]
##    现在是纯函数，于是可以**把 0~9 秒按 0.01 秒铺一遍全验掉**，包括真地形上
##    根本凑不出来的 6~8 秒那两档（要一个 16000 像素的落差才飞得到）。
##    靠实机去够这些档位不现实，靠人来读表更不现实 —— 这一组是唯一能钉住
##    「4 秒那一拍换成 100」这种边界的地方。
## 3. **真的飞起来** —— 造一段带落点平台的跳台，断言的**不只是「有奖励」，
##    而是每一笔都落在 2.5 / 3.0 / 3.5 秒这些整拍上、金额跟着档位走**。
##    只数个数的话，把间隔写成 0.4 或者每次加 1 块也照样能过；断言发生时刻和
##    金额才测得出「半秒一节，越飞越值钱」。落点够深，所以这一趟会**跨过 50→100
##    那道档**，第三组因此不只是「纯函数说的对」。
## 4. **出生悬空** —— 车是悬空出生的，落地之前不给钱。少了这道闸，每次重开
##    白送钱（见 [member HillCar._has_landed]）。落点高度是照着**起奖线**配的：
##    要让它掉够 2.5 秒以上，否则「没有那道闸」和「有那道闸」的结果都是 0 次，
##    这一组会变成一句废话。
## 5. **关卡接线** —— 车发的信号要真的变成关卡里的金币。

const CAR := preload("res://scenes/car.tscn")
const MAIN := preload("res://scenes/main.tscn")

const START_X := 120.0
const CAR_Y := -39.0       ## 轮心离地 21，轮心在车原点下方 18
const RUN_UP := 700.0      ## 跳台助跑段
const RAMP_ANGLE := 25.0
const RAMP_LEN := 700.0
const ARC_RADIUS := 260.0
const GAP := 300.0         ## 坡顶到落点平台的水平空档
## 落点平台比坡顶低多少。10130 是这么来的：出坡的垂直速度约 241（25°、570 出头），
## 从坡顶往下落 H 的滞空是 `(241 + √(241² + 2×980×H)) / 980` —— 代进去
## `H = 10130` 得 **4.8 秒**，整拍落在 2.5 / 3.0 / 3.5 / 4.0 / 4.5 上，
## 前三拍 50、后面两拍 100。
##
## **必须跨过 4 秒那条线**，否则这一组只能证明「50 那一档是 50」，而档位切换才是
## 新增的东西；同时又要给 4.5 那一拍留出余量（0.3 秒 ≈ 18 帧），不然差半帧就
## 少一拍，测试会随机地红。
##
## （上一版是 1020 / 1.71 秒，那时起奖线还是 1.0 秒，够看第二拍就行。）
const DROP_TO_LANDING := 10130.0
## 两块多边形往下延伸多少。落点平台得**够厚**：落地时速接近 4700 px/s，
## 一步物理帧走 78 像素，薄板会被直接穿过去（RigidBody2D 默认不做连续碰撞）。
const DEPTH := 2600.0
## 出生悬空那一组往下掉多少。4500 高 = `√(2×4500/980)` ≈ **3.03 秒**，
## 越过起奖线 0.5 秒 —— 没有 [_has_landed] 那道闸的话这一趟会白送 2 笔。
const DROP_FROM := 4500.0
const SETTLE := 12         ## 生成后等车坐稳的物理帧数

var _world: Node2D
var _car: HillCar
var _awards := []          ## 每次奖励记 [触发时的 air_time, 金币数]
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1：它会直接放大物理步长
	# 车库里练满级的车会改马达和油箱，测出来的腾空时间不是原厂车的
	SaveData.persist = false
	SaveData.reset_progress()

	await _case_flat()
	print("")
	_case_tiers()
	print("")
	await _case_jump()
	print("")
	await _case_spawn_drop()
	print("")
	await _case_game_wiring()

	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _approx(label: String, got: float, want: float, tol: float) -> void:
	var ok := absf(got - want) <= tol
	if not ok:
		_failures += 1
	print("  %s %s = %.3f（期望 %.3f ±%.3f）" % [
		"OK  " if ok else "FAIL", label, got, want, tol,
	])


# ---------------------------------------------------------------- 场景搭建

func _new_world() -> void:
	if _world != null:
		_world.queue_free()
	_awards.clear()
	_world = Node2D.new()
	add_child(_world)


## 一块实心地面。collision_layer = 2 是地形层，组名 "ground" 是车的触地判据。
func _solid(pts: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = pts
	body.add_child(shape)
	_world.add_child(body)


func _spawn(pos: Vector2) -> void:
	_car = CAR.instantiate()
	_car.position = pos
	_world.add_child(_car)
	_car.fuel_max = 1.0e9      # 别被油耗打断
	_car.fuel = 1.0e9
	_car.air_bonus.connect(_on_bonus)


func _on_bonus(coins: int) -> void:
	# air_time 在 emit 之前就已经加过这一帧的 delta，所以这里读到的是
	# 「触发那一刻的连续腾空时长」，正好用来验证发钱的节拍。
	_awards.append([_car.air_time, coins])


## 全油门开 seconds 秒，返回腾空统计。每帧采一次 air_time 的最大值 ——
## 落地时车会把 air_time 清零，不采样就只剩 0 了。
##
## `coast_in_air` 是给「要一段干净的抛物线」的情形用的：腾空期间松开油门，
## 落地再踩回去。**不松的话车会在空中被 [method HillCar._apply_air_control] 拧着转**
## —— 飞 1 秒就转过 300°，落地是砸下来的，测出来的腾空时长和落点全不是这条
## 抛物线该有的。这个文件测的是**发钱的节拍**，不是空中姿态，所以飞的两处都
## 要 `true`；平路那处从头到尾贴地，给不给都一样。
func _drive(seconds: float, coast_in_air := false) -> Dictionary:
	var frames := int(round(seconds * 60.0))
	var max_air := 0.0
	var air_frames := 0
	var max_x := _car.chassis.global_position.x
	for i in frames:
		if coast_in_air and not _car.grounded:
			Input.action_release("drive_forward")
		else:
			Input.action_press("drive_forward")
		await get_tree().physics_frame
		max_air = maxf(max_air, _car.air_time)
		max_x = maxf(max_x, _car.chassis.global_position.x)
		if not _car.grounded:
			air_frames += 1
	Input.action_release("drive_forward")
	return {"max_air": max_air, "air_frames": air_frames, "max_x": max_x}


# ---------------------------------------------------------------- 1. 平路

func _case_flat() -> void:
	print("=== 1. 平路不该有腾空奖励 ===")
	_new_world()
	_solid(PackedVector2Array([
		Vector2(-400.0, 0.0), Vector2(12000.0, 0.0),
		Vector2(12000.0, 800.0), Vector2(-400.0, 800.0),
	]))
	_spawn(Vector2(START_X, CAR_Y))
	for i in SETTLE:
		await get_tree().physics_frame
	var st := await _drive(3.0)
	print("  跑 3.00s：腾空 %.3fs，全程离地 %d 帧，发奖 %d 次" % [
		st["max_air"], st["air_frames"], _awards.size(),
	])
	_check("平路全程贴地", st["air_frames"], 0)
	_check("平路一次奖励都没发", _awards.size(), 0)
	_check("车还活着（否则上面两条是废话）", _car.alive, true)


# ---------------------------------------------------------------- 2. 档位表

## 腾空奖励的档位表 —— **纯函数，一个物理帧都不用跑**。
##
## 这是本次改动的核心：奖励从「一律 25 块」变成了按滞空时长分档
## （[constant HillCar.AIR_BONUS_TIERS]）。分档的边界全是 `>=`，而 `int()` 截断、
## 浮点累加这些坑全长在边界上，所以是**把 0~9 秒按 0.01 秒铺一遍**，不是挑几个
## 好数测 —— 挑着测的话「6 秒那一档写成 6.5」这种错要飞一次 6.5 秒的跳才现形。
##
## 6~8 秒那两档也在这里验。真地形上凑不出来（4 秒就要一个 10000 像素的落差，
## 8 秒要 20000+），拿实机去够它不现实，靠人读表更不现实。
func _case_tiers() -> void:
	print("=== 2. 档位表：越飞越值钱，8 秒后停 ===")
	var first: float = HillCar.AIR_BONUS_TIERS[0][0]
	var last: Array = HillCar.AIR_BONUS_TIERS[HillCar.AIR_BONUS_TIERS.size() - 1]
	_check("起奖线就是第一档的秒数（两处不一致的话节拍和金额会各说各话）",
			HillCar.AIR_BONUS_DELAY, first)
	_check("第一档就是 2.5 秒", first, 2.5)
	_check("最后一档是 6 秒 / 200 块", last, [6.0, 200])
	_check("停发线就是 8 秒", HillCar.AIR_BONUS_STOP, 8.0)
	# 表必须升序：[method HillCar.air_bonus_coins] 是「一路覆盖过去，最后留下的那档
	# 赢」，顺序写乱了它不报错，只会静默给出错的档位。
	var sorted := true
	var prev := -INF
	for tier in HillCar.AIR_BONUS_TIERS:
		if float(tier[0]) <= prev:
			sorted = false
		prev = float(tier[0])
	_check("档位表按秒数升序（乱了的话金额会静默取错档）", sorted, true)

	# 金额：整条时间轴铺一遍。0.01 秒一格，每条边界两侧都留得下好几格。
	var wrong := PackedStringArray()
	var tick_bad := 0
	var t := 0.0
	while t < 9.0:
		var want := 0
		if t >= 2.5 and t < 8.0:
			want = 50
			if t >= 4.0:
				want = 100
			if t >= 6.0:
				want = 200
		if HillCar.air_bonus_coins(t) != want:
			wrong.append("%.2fs 得 %d（要 %d）" % [t, HillCar.air_bonus_coins(t), want])
		var want_tick: int = -1 if t < 2.5 else int((t - 2.5) / 0.5)
		if HillCar.air_bonus_tick(t) != want_tick:
			tick_bad += 1
		t += 0.01
	_check("0~9 秒每 0.01 秒的金额都对上（错的格子数）", wrong.size(), 0)
	if wrong.size() > 0:
		print("      %s" % "  ".join(wrong.slice(0, 8)))
	_check("0~9 秒每 0.01 秒的节号都对上（错了几格）", tick_bad, 0)

	# 节号的边界：起奖线**之前**那一瞬间还不算第 0 节。
	_check("起奖线前一瞬间的节号是 −1", HillCar.air_bonus_tick(2.4999), -1)
	_check("起奖线那一刻是第 0 节", HillCar.air_bonus_tick(2.5), 0)
	_check("3.5 秒是第 2 节", HillCar.air_bonus_tick(3.5), 2)
	_check("1 秒时是 −1（老版本这里是「已经发了 0 笔」，现在连节都不算）",
			HillCar.air_bonus_tick(1.0), -1)

	# 一趟飞满整个奖励区间能拿多少：2.5/3.0/3.5 三拍 50，4.0~5.5 四拍 100，
	# 6.0~7.5 四拍 200。
	var total := 0
	var beats := PackedStringArray()
	var n := 0
	while true:
		var at := 2.5 + 0.5 * float(n)
		var coins := HillCar.air_bonus_coins(at)
		if coins == 0:
			break
		total += coins
		beats.append("%.1fs:%d" % [at, coins])
		n += 1
	print("  每 0.5 秒一拍：%s = %d 块" % ["  ".join(beats), total])
	_check("一共 11 拍（2.5 秒到 7.5 秒）", n, 11)
	_check("飞满整个奖励区间的总金额", total, 1350)
	# 8.0 那一拍**不发**：`_update_airborne` 里那句 `coins > 0` 就是为它写的。
	_check("8.0 秒整那一拍是 0 块（发了 HUD 就会飘「+0 腾空」）",
			HillCar.air_bonus_coins(8.0), 0)
	_check("7.99 秒还是 200（停发线是「到 8.0 为止」，不是「过了 8.0 才停」）",
			HillCar.air_bonus_coins(7.99), 200)
	_check("8 秒之后一直是 0（不许无限刷）", HillCar.air_bonus_coins(120.0), 0)


# ---------------------------------------------------------------- 3. 跳台

## 平路 → 圆弧 → 25° 上坡 → 坡顶悬崖 → 空档 → 落点平台。
##
## **落点平台压到坡顶下面 [constant DROP_TO_LANDING] 那么深**，一次跳跃的腾空因此
## 有 4.8 秒 —— 够跨过 4 秒那道档位线，也够在 4.5 那一拍之后还有余量。
## 原来平台就在坡顶下方一个坡高（回到 y=0），腾空 1.05 秒，连起奖线都过不去。
func _build_jump() -> Vector2:
	var theta := deg_to_rad(RAMP_ANGLE)
	var pts := PackedVector2Array([Vector2(-400.0, 0.0), Vector2(RUN_UP, 0.0)])
	var steps := maxi(4, int(ceil(RAMP_ANGLE / 4.0)))
	for i in range(1, steps + 1):
		var a := theta * float(i) / float(steps)
		pts.append(Vector2(RUN_UP + ARC_RADIUS * sin(a), -ARC_RADIUS * (1.0 - cos(a))))
	var lip: Vector2 = pts[pts.size() - 1] + Vector2(cos(theta), -sin(theta)) * RAMP_LEN
	# 两块多边形的下缘都跟着落点深度走 —— 写死 y=2400 的话，落点平台会整个翻过来
	# （上缘在 10130、下缘在 2400），车一穿而过，这一组会变成「一次都没发奖」。
	var bottom := lip.y + DROP_TO_LANDING + DEPTH
	pts.append(lip)
	pts.append(Vector2(lip.x, bottom))
	pts.append(Vector2(-400.0, bottom))
	_solid(pts)
	_solid(PackedVector2Array([
		Vector2(lip.x + GAP, lip.y + DROP_TO_LANDING),
		Vector2(lip.x + GAP + 6000.0, lip.y + DROP_TO_LANDING),
		Vector2(lip.x + GAP + 6000.0, bottom), Vector2(lip.x + GAP, bottom),
	]))
	return lip


func _case_jump() -> void:
	print("=== 3. 飞起来：奖励要落在半秒整拍上，金额跟着档位走 ===")
	_new_world()
	var lip := _build_jump()
	_spawn(Vector2(START_X, CAR_Y))
	for i in SETTLE:
		await get_tree().physics_frame
	# 助跑 700 + 圆弧 + 坡面 700 拉直了约 2100，全油门也就 500 上下，
	# 光开到坡顶就要 4 秒出头；再加上 [constant DROP_TO_LANDING] 换来的 4.8 秒滞空，
	# 10 秒才够「开到坡顶 → 飞出去 → 落地」。**给少了的话这一组会静默地只测半程**
	# （第一版就栽在这：2.5 秒开不到坡顶，最长腾空 0.033s = 在圆弧上颠了一下）。
	# 腾空后松油门：理由见 [method _drive] 的 `coast_in_air`。
	var st := await _drive(10.0, true)
	print("  坡顶 (%.0f, %.0f)，跑 10.0s：最远 x=%.0f，最长腾空 %.3fs，离地 %d 帧" % [
		lip.x, lip.y, st["max_x"], st["max_air"], st["air_frames"],
	])
	_check("够得着坡顶（否则后面全是空跑）", st["max_x"] > lip.x + GAP, true)
	var beats := PackedStringArray()
	for a in _awards:
		beats.append("%.3fs +%d" % [a[0], a[1]])
	print("  发奖 %d 次：%s" % [_awards.size(), ", ".join(beats) if _awards.size() > 0 else "（无）"])

	_check("确实飞起来了（腾空 > 起奖线 + 0.5，否则下面测不出整拍）",
			st["max_air"] > HillCar.AIR_BONUS_DELAY + HillCar.AIR_BONUS_INTERVAL, true)
	_check("车还活着", _car.alive, true)
	# 次数：**起奖线那一拍本身要算进去**（第 1 次就落在起奖线上），所以是 +1。
	var due := int((st["max_air"] - HillCar.AIR_BONUS_DELAY) / HillCar.AIR_BONUS_INTERVAL) + 1
	_check("发奖次数 = floor((腾空 − 起奖线) / 间隔) + 1", _awards.size(), due)
	_check("至少测到三拍（一拍看不出「整拍」）", due >= 3, true)
	# 节拍：第 i 次发奖必须发生在 起奖线 + 间隔×i 附近。帧长 1/60，容差给 0.05。
	#
	# **金额不是常数了**，所以拿 [method HillCar.air_bonus_coins] 按触发时刻算一遍
	# 去比 —— 这一趟 4.8 秒会跨过 4 秒那道线，于是前几拍 50、后几拍 100。
	# 写成「一律等于某个常量」的话，档位切换就是没有测到。
	var amounts := {}
	var zero := 0
	for i in _awards.size():
		var want := HillCar.AIR_BONUS_DELAY + HillCar.AIR_BONUS_INTERVAL * float(i)
		_approx("第 %d 次发奖的时刻" % (i + 1), _awards[i][0], want, 0.05)
		var coins: int = HillCar.air_bonus_coins(_awards[i][0])
		_check("第 %d 次发奖的金额（按触发时刻的档位）" % (i + 1), _awards[i][1], coins)
		amounts[coins] = true
		if coins <= 0:
			zero += 1
	_check("没有一笔 0 块（0 块的节根本不该发信号，否则 HUD 会飘「+0 腾空」）", zero, 0)
	_check("这一趟跨过了 50 和 100 两档（只出现一档的话档位切换没被测到）",
			amounts.has(50) and amounts.has(100), true)
	_check("间隔常量就是 0.5s", HillCar.AIR_BONUS_INTERVAL, 0.5)
	_check("起奖线就是 2.5s（小颠一下不该发钱）", HillCar.AIR_BONUS_DELAY, 2.5)


# ---------------------------------------------------------------- 4. 出生悬空

func _case_spawn_drop() -> void:
	print("=== 4. 出生悬空：落地前不发钱 ===")
	_new_world()
	_solid(PackedVector2Array([
		Vector2(-400.0, 0.0), Vector2(12000.0, 0.0),
		Vector2(12000.0, 800.0), Vector2(-400.0, 800.0),
	]))
	# 悬在 [constant DROP_FROM] 高：自由落体约 3.0s —— **必须越过起奖线 2.5s**，
	# 否则「有没有那道闸」的结果都是 0 笔，这一组就成了废话。
	# （起奖线还是 1.0s 那一版悬的是 1200 高 / 1.56s。）
	_spawn(Vector2(START_X, CAR_Y - DROP_FROM))
	# 同样是自由落体，全程松油门（见 [method _drive] 的 `coast_in_air`）：
	# 踩着的话车身在空中被拧转，落地姿态就不是「坐稳了」，`grounded` 那条断言会挂。
	var st := await _drive(4.0, true)
	print("  从 %.0f 高落下：腾空 %.3fs，发奖 %d 次（没有那道闸的话这一趟会发 %d 笔）" % [
		DROP_FROM, st["max_air"], _awards.size(),
		HillCar.air_bonus_tick(st["max_air"]) + 1,
	])
	_check("落下途中 > 起奖线（否则这道闸测不出来）",
			st["max_air"] > HillCar.AIR_BONUS_DELAY, true)
	_check("落地前一次都没发", _awards.size(), 0)
	_check("已经落地了", _car.grounded, true)


# ---------------------------------------------------------------- 5. 关卡接线

func _case_game_wiring() -> void:
	print("=== 5. 关卡：信号要变成金币 ===")
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	# 金额从档位表里取，不写死一个数 —— 写死的话改档位时这条会红，而它想测的
	# 是「信号变成钱」这件事，和具体多少块无关。取 4.2 秒（第三档，100 块），
	# 顺带保证测的不是第一档那个最容易和「没改之前的 25」混淆的数。
	var bonus: int = HillCar.air_bonus_coins(4.2)
	_check("4.2 秒落在 100 那一档（下面的断言要有个非 25 的数才有意义）", bonus, 100)
	var before: int = main.coins
	var bank_before: int = SaveData.total_coins
	main._on_air_bonus(bonus)
	_check("本局金币 +100", main.coins - before, bonus)
	_check("存档金币 +100（腾空奖励是即时入账的）",
			SaveData.total_coins - bank_before, bonus)
	main.queue_free()
	await get_tree().process_frame
