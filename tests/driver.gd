extends Node
## 车手（和巴士后排乘客）的颠簸：既要**真的在动**，又**一个字节都不许碰物理**。
##
## 三段：
##   1. 模型本身（纯数学，不开场景）：静止零位移、1 g = 2.76 像素、自由落体往上飘、
##      限幅 5 像素、撤掉加速度半秒内收回来、低帧率不发散
##   2. 实机对照 —— 照 [code]tests/effects.gd[/code] 的写法：同一局跑两遍
##      （开颠簸 / 关颠簸），车的**最终坐标逐位相同**才算过。同样要先空跑一局热身：
##      第一局的自动惯量要到第 2 个物理帧才读得到（见那边那段注释）。
##      越野车（一个车手）和巴士（一个车手 + 四个乘客）各对照一遍。
##   3. 场景契约：八辆车的 `Chassis/Head` 永远在 `Driver` 上方 36 像素、**颠簸不许改它**；
##      乘客只有巴士有，而且整套画在车窗里。
##
## 用法：
##   godot --headless --path . res://tests/driver.tscn

const CAR := preload("res://scenes/car.tscn")
const BUS := preload("res://scenes/vehicles/bus.tscn")

## 车手头顶到司机那 36 像素（`Driver` → `Head`，也是 driver_visual.gd 的 HEAD_CENTER）。
const HEAD_GAP := 36.0

const DT := 1.0 / 60.0
const G := 980.0
## 车从空中落下、轮子比地面低 5 像素进场（和 tests/effects 同一套摆法），
## 头几帧会被地面顶一下 —— 采样前先让它落稳。
const START_X := 120.0
const CAR_Y := -39.0
const SETTLE := 20
const RUN_FRAMES := 240
## 静止那一局：停 2.5 秒之后再盯 1 秒，看有没有静态下沉。
const REST_SETTLE := 150
const REST_FRAMES := 60

var _world: Node2D
var _assertions := 0
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false     # 别让这次对照写进玩家存档
	SaveData.reset_progress()    # 也别让玩家练出来的升级混进来
	print("车手颠簸（模型 / 实机对照 / 场景契约）")
	_test_model()
	print("")
	await _test_live()
	print("")
	await _test_scenes()
	print("")
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


# ---------------------------------------------------------------- 一、模型

func _test_model() -> void:
	print("=== 一、模型（纯数学，不开场景）===")
	var ride := HillSeatRide.new()
	# 稳态位移 = 加速度 ÷ 刚度。1 g 就是那个标定值：**2.76 像素**。
	var want := G / HillSeatRide.K
	_check(absf(want - 2.76) < 0.01, "标定值没说错：980 / %.0f = 2.76 像素" % HillSeatRide.K,
			"%.3f" % want)

	_hold(ride, Vector2.ZERO, 60, DT)
	_check(ride.offset == Vector2.ZERO, "不给加速度就一动不动", str(ride.offset))

	# y 轴向下，所以「往上一个 g」是负的：人被压进座位，位移朝下 = +y。
	_hold(ride, Vector2(0.0, -G), 300, DT)
	_near("向上 1 g → 被压进座位 %.2f 像素" % want, ride.offset.y, want, want * 0.01)
	_near("上下颠不会带出侧倾", ride.lean, 0.0, 1e-9)

	ride.reset()
	_hold(ride, Vector2(0.0, G), 300, DT)
	_near("自由落体 → 往上飘同样多", ride.offset.y, -want, want * 0.01)

	ride.reset()
	_hold(ride, Vector2(0.0, -G * 10.0), 600, DT)
	_check(ride.offset.is_finite() and ride.offset.length() <= HillSeatRide.MAX_OFFSET + 1e-4,
			"10 个 g 也压在限幅 %.1f 像素以内" % HillSeatRide.MAX_OFFSET,
			"%.3f" % ride.offset.length())

	# 撤掉加速度：半秒内要收回来 —— 这条同时管着「不会一直晃下去」。
	ride.reset()
	_hold(ride, Vector2(0.0, -G), 300, DT)
	_hold(ride, Vector2.ZERO, 30, DT)
	_check(ride.offset.length() < 0.1, "松手后 0.5 秒内回到 0.1 像素以内",
			"%.4f" % ride.offset.length())

	# 横向：车往前窜（+x）→ 人往后倒（−x）→ 上身往后倾（负角）。
	ride.reset()
	_hold(ride, Vector2(500.0, 0.0), 300, DT)
	_check(ride.offset.x < 0.0, "加速时人往后倒", "%.2f 像素" % ride.offset.x)
	_check(ride.lean < 0.0, "上身跟着往后倾", "%.3f 弧度" % ride.lean)
	_near("没被限幅时 倾角 = 位移 × LEAN_PER_PX", ride.lean,
			ride.offset.x * HillSeatRide.LEAN_PER_PX, 1e-6)

	# 每秒 20 帧（低端机掉帧）也不许发散：限幅兜着，值还得是有限数。
	ride.reset()
	_hold(ride, Vector2(0.0, -G), 60, 0.05)
	_check(ride.offset.is_finite() and ride.offset.length() <= HillSeatRide.MAX_OFFSET + 1e-4,
			"每秒 20 帧也不发散", "%.3f" % ride.offset.length())


func _hold(ride: HillSeatRide, accel: Vector2, frames: int, dt: float) -> void:
	for i in frames:
		ride.integrate(accel, dt)


# ---------------------------------------------------------------- 二、实机对照

func _test_live() -> void:
	print("=== 二、实机对照（开 / 关颠簸，各 %d 物理帧）===" % RUN_FRAMES)
	await _run(CAR, true)                       # 热身，丢掉（见文件头那段）
	var on: Dictionary = await _run(CAR, true)
	var off: Dictionary = await _run(CAR, false)
	_report("越野车 开颠簸", on)
	_report("越野车 关颠簸", off)
	_check(on["pos"] == off["pos"], "越野车 两遍的最终坐标逐位相同",
			"%s / %s" % [on["pos"], off["pos"]])
	_check(float((on["maxes"] as Array)[0]) > 0.3, "开颠簸时车手真的在动（否则对照是空的）",
			"最大位移 %.2f 像素" % float((on["maxes"] as Array)[0]))
	_check(_all_zero(off), "关颠簸时一动不动（位移严格为零）", "最大 %.3f 像素" % _peak(off))

	var bus_on: Dictionary = await _run(BUS, true)
	var bus_off: Dictionary = await _run(BUS, false)
	_report("巴士 开颠簸", bus_on)
	_report("巴士 关颠簸", bus_off)
	_check(bus_on["pos"] == bus_off["pos"], "巴士 两遍的最终坐标逐位相同",
			"%s / %s" % [bus_on["pos"], bus_off["pos"]])
	_check((bus_on["maxes"] as Array).size() == 5, "巴士上一共五个人（司机 + 后排四个）",
			"%d 个" % (bus_on["maxes"] as Array).size())
	var moved := 1.0e9
	for m in bus_on["maxes"]:
		moved = minf(moved, float(m))
	_check(moved > 0.2, "巴士上五个人都在动", "动得最少的那个 %.2f 像素" % moved)

	# 平地直线加速时整辆车**一起**沉：四个座位离质心的距离确实不同，但离心项和切向项
	# 都来自角速度／角加速度，而平地直线上它们约等于零 —— 所以四个人应该几乎同步。
	# 这不是「化简过头」，恰恰是模型对了：路面起伏时才会各颠各的。
	var means: Array = (bus_on["means"] as Array).slice(1)   # [0] 是司机，看后排四个
	var spread: float = float(means.max()) - float(means.min())
	_check(spread < 0.5, "平地直线上后排四个人几乎同步（互相差不到 0.5 像素）",
			"最大差 %.3f 像素" % spread)

	var rest: Dictionary = await _run(CAR, true, false, REST_FRAMES, REST_SETTLE)
	_check(_peak(rest) < 0.2, "车停着时没有静态下沉",
			"停稳后 %d 帧里最大位移 %.3f 像素" % [REST_FRAMES, _peak(rest)])


## 跑一局。返回车的最终坐标和每个人整局的位移统计。
##
## [param bob] 开着颠簸还是关掉（关掉那一局就是「这辆车还是原来的样子」）；
## [param drive] 踩不踩油门；[param frames] 采样多少物理帧；[param settle] 采样前先落稳多少帧。
func _run(vehicle: PackedScene, bob: bool, drive := true,
		frames := RUN_FRAMES, settle := SETTLE) -> Dictionary:
	if _world != null:
		_world.queue_free()
		# 等一个物理帧，确认上一局的刚体真的从物理服务器里撤走了，
		# 不然两遍会互相挤（尤其是那个 1.0e9 的油量）。
		await get_tree().physics_frame
	_world = Node2D.new()
	add_child(_world)
	_make_ground(_world)

	var car: HillCar = vehicle.instantiate()
	car.position = Vector2(START_X, CAR_Y)
	_world.add_child(car)
	car.fuel = 1.0e9

	# 车上的人：司机一个（八辆车都有），后排乘客只有巴士有。顺序就是 [member maxes] 的
	# 顺序 —— 司机排头，后面跟着后排四个。
	var rides: Array[HillSeatRide] = []
	var driver := car.get_node_or_null("Chassis/Driver")
	if driver != null:
		driver.set("enabled", bob)
		rides.append(driver.get("ride"))
	var people := car.get_node_or_null("Chassis/Passengers")
	if people != null:
		people.set("enabled", bob)
		for r in people.get("rides"):
			rides.append(r)

	for i in settle:
		await get_tree().physics_frame

	if drive:
		Input.action_press("drive_forward")
	var maxes: Array[float] = []
	var totals: Array[float] = []
	for i in rides.size():
		maxes.append(0.0)
		totals.append(0.0)
	for i in frames:
		await get_tree().physics_frame
		for j in rides.size():
			var d: float = rides[j].offset.length()
			maxes[j] = maxf(maxes[j], d)
			totals[j] += d
	if drive:
		Input.action_release("drive_forward")

	var means: Array[float] = []
	for j in rides.size():
		means.append(totals[j] / float(frames))
	return {
		"pos": car.chassis.global_position,
		"maxes": maxes,
		"means": means,
		"speed": car.chassis.linear_velocity.length(),
	}


## 一块平地。**故意不用 main.tscn**：那里的地形是跟着镜头流式生成的，会引入和帧率
## 有关的变量，而这次要测的是「颠簸有没有干扰物理」，不该有第二个变量。
func _make_ground(parent: Node) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([
		Vector2(-400.0, 0.0), Vector2(20000.0, 0.0),
		Vector2(20000.0, 800.0), Vector2(-400.0, 800.0),
	])
	body.add_child(shape)
	parent.add_child(body)


func _peak(r: Dictionary) -> float:
	var out := 0.0
	for m in r["maxes"]:
		out = maxf(out, float(m))
	return out


func _all_zero(r: Dictionary) -> bool:
	for m in r["maxes"]:
		if float(m) != 0.0:
			return false
	return true


func _report(label: String, r: Dictionary) -> void:
	print("  %s  最终 x=%.0f y=%.0f  车速=%.0f" % [
		label, (r["pos"] as Vector2).x, (r["pos"] as Vector2).y, r["speed"]])
	print("        各人最大位移（像素）= %s" % _list(r["maxes"]))
	print("        各人平均位移（像素）= %s" % _list(r["means"]))


func _list(values: Array) -> String:
	var parts := PackedStringArray()
	for v in values:
		parts.append("%.2f" % float(v))
	return "司机" if parts.size() == 1 else ", ".join(parts)


# ---------------------------------------------------------------- 三、场景契约

## 车手和乘客都是**纯视觉**的，所以这里守两条线：
##   1. `Chassis/Head` 那个碰撞体（翻车判据）永远在 `Driver` 上方 36 像素，而且跑一段
##      之后一个像素都不许挪 —— 颠簸只改画出来的东西；
##   2. 乘客只有巴士有，而且整套画在车窗玻璃里。
func _test_scenes() -> void:
	print("=== 三、场景契约 ===")
	var bad_node := PackedStringArray()
	var bad_offset := PackedStringArray()
	var with_passengers := PackedStringArray()
	for id in Vehicles.IDS:
		var car: Node2D = Vehicles.instantiate(id)
		var driver := car.get_node_or_null("Chassis/Driver") as Node2D
		var head := car.get_node_or_null("Chassis/Head") as Node2D
		if driver == null or head == null:
			bad_node.append(id)
		elif head.position != driver.position + Vector2(0.0, -HEAD_GAP):
			bad_offset.append("%s：头在 %s、车手在 %s" % [id, head.position, driver.position])
		if car.get_node_or_null("Chassis/Passengers") != null:
			with_passengers.append(id)
		car.free()
	_check(bad_node.is_empty(), "八辆车都有 Chassis/Driver 和 Chassis/Head",
			"八辆齐全" if bad_node.is_empty() else "缺的是 %s" % [bad_node])
	_check(bad_offset.is_empty(), "头永远在车手正上方 %d 像素" % int(HEAD_GAP),
			"都对" if bad_offset.is_empty() else "；".join(bad_offset))
	_check(with_passengers == PackedStringArray([Vehicles.BUS]), "乘客只有巴士有",
			"有的是 %s" % [with_passengers])

	await _test_head_does_not_move()
	_test_passenger_geometry()


## 跑起来之后，`Driver` 和 `Head` 的局部坐标要和场景里写的一模一样 —— 颠簸只该改
## `_draw()` 里那点平移，不该改节点。
func _test_head_does_not_move() -> void:
	var probe: HillCar = CAR.instantiate()
	var before := [
		(probe.get_node("Chassis/Driver") as Node2D).position,
		(probe.get_node("Chassis/Head") as Node2D).position,
	]
	probe.free()

	if _world != null:
		_world.queue_free()
		await get_tree().physics_frame
	_world = Node2D.new()
	add_child(_world)
	_make_ground(_world)

	var live: HillCar = CAR.instantiate()
	live.position = Vector2(START_X, CAR_Y)
	_world.add_child(live)
	live.fuel = 1.0e9
	Input.action_press("drive_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("drive_forward")

	var driver := live.get_node("Chassis/Driver") as Node2D
	var head := live.get_node("Chassis/Head") as Node2D
	var ride: HillSeatRide = driver.get("ride")
	_check(driver.position == before[0] and head.position == before[1],
			"跑 60 帧之后 Driver / Head 的局部坐标没动过",
			"车手 %s → %s，头 %s → %s" % [before[0], driver.position, before[1], head.position])
	_check(ride.offset.length() > 0.3, "（而画出来的位移确实在动，不然上面那条是空的）",
			"%.2f 像素" % ride.offset.length())


## 后排四个人的**静态**几何要整套落在车窗玻璃里，还得留 1 像素边。
##
## 玻璃那个矩形是**从 bus.tscn 实读**的，不抄数字：改了车窗却没改座位，这条就红。
## 颠簸的时候最多再沉 5 像素、斜 0.12 弧度，那点溢出是有意的（见 passenger_visual.gd）。
func _test_passenger_geometry() -> void:
	var bus: Node2D = Vehicles.instantiate(Vehicles.BUS)
	var win := bus.get_node("Chassis/Windows") as Polygon2D
	var glass := Rect2()
	for i in win.polygon.size():
		var p := win.polygon[i]
		glass = Rect2(p, Vector2.ZERO) if i == 0 else glass.expand(p)
	var people := bus.get_node_or_null("Chassis/Passengers") as Node
	var rides: Array = people.get("rides") if people != null else []
	_check(rides.size() == HillPassengers.SEATS.size(), "巴士上四个乘客各有一个弹簧",
			"%d 个" % rides.size())

	var inner := glass.grow(-1.0)     # 留 1 像素边
	var worst := 1.0e9
	for i in HillPassengers.SEATS.size():
		var seat := Vector2(HillPassengers.SEATS[i], HillPassengers.SEAT_Y)
		var head := seat + Vector2(0.0, HillPassengers.HEAD_DY)
		for corner in [
			head + Vector2(-HillPassengers.HEAD_R, -HillPassengers.HEAD_R),
			head + Vector2(HillPassengers.HEAD_R, -HillPassengers.HEAD_R),
			head + Vector2(-HillPassengers.HEAD_R, HillPassengers.HEAD_R),
			head + Vector2(HillPassengers.HEAD_R, HillPassengers.HEAD_R),
			seat + Vector2(-HillPassengers.SHOULDER_BOT, 0.0),
			seat + Vector2(HillPassengers.SHOULDER_BOT, 0.0),
			seat + Vector2(-HillPassengers.SHOULDER_TOP, HillPassengers.SHOULDER_DY),
			seat + Vector2(HillPassengers.SHOULDER_TOP, HillPassengers.SHOULDER_DY),
		]:
			worst = minf(worst, minf(
				minf(corner.x - inner.position.x, inner.end.x - corner.x),
				minf(corner.y - inner.position.y, inner.end.y - corner.y)))
	_check(worst >= 0.0, "头+肩整套都在车窗玻璃里（还留了 1 像素边）",
			"最窄处还剩 %.1f 像素" % worst)

	var overlaps := PackedStringArray()
	for i in range(1, HillPassengers.SEATS.size()):
		var gap: float = HillPassengers.SEATS[i] - HillPassengers.SEATS[i - 1]
		if gap <= HillPassengers.SHOULDER_BOT * 2.0:
			overlaps.append("第 %d 和第 %d 个只隔 %.0f 像素" % [i - 1, i, gap])
	_check(overlaps.is_empty(), "四个人互不重叠",
			"都对" if overlaps.is_empty() else "；".join(overlaps))

	# 后排：最后一排不许挤到司机身上（司机车身最左在 position.x − 11）。
	var driver := bus.get_node("Chassis/Driver") as Node2D
	var rear := float(HillPassengers.SEATS[HillPassengers.SEATS.size() - 1]) \
			+ HillPassengers.SHOULDER_BOT
	_check(rear < driver.position.x - 11.0, "最后一排不挤到司机身上",
			"乘客最右 %.0f < 司机最左 %.0f" % [rear, driver.position.x - 11.0])
	bus.free()


func _check(ok: bool, label: String, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


func _near(label: String, got: float, want: float, tol: float) -> void:
	_check(absf(got - want) <= tol, label, "%.4f（期望 %.4f ± %.4f）" % [got, want, tol])
