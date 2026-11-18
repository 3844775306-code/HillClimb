extends Node
## 升级平衡校准：把 [Upgrades] 里拍的倍率实测一遍。
##
## A. 静态表 —— 等级/倍率/花销，顺带断言 Upgrades 里复制的车体常量与真车一致
## B. 平路起步翘头余量 —— 验证「极速做成齿比后，推重比只由引擎决定」
## C. 40° 稳态爬坡 —— 验证齿比改动不会拖慢爬坡
## D. 真实地形里程 —— 验证敏捷等级是单调变好的（升级不能越升越差）
## E1. 平地烧干用时 —— 精确验证油箱 ×1.6
## E2. 真实地形一箱油 —— 说明油箱在实战里几乎不起作用（油桶 + 翻车）
##
## 这个文件里踩过三个坑，都写在对应位置了：contact_monitor 不开就没法判离地、
## queue_free 是延迟的会让新旧地形重叠一帧、爬坡测速必须排除「冲上坡顶掉下去」那段。

const CAR := preload("res://scenes/car.tscn")
const MAIN := preload("res://scenes/main.tscn")

const LAUNCH_TIME := 3.0

## 坡道参数照抄 tests/climb.gd，保证和那里的「极限坡度」数字可比。
const RUN_UP := 700.0
const RAMP_LEN := 900.0
const ARC_RADIUS := 260.0
const START_X := 120.0
const CAR_Y := -39.0
const CLIMB_ANGLE := 40.0
const CLIMB_TIME := 11.0

const RUN_TIME := 20.0
## 一箱油跑完的上限。真烧完大概 30~50 秒，留够余量免得把「超时」误当成「跑完了」。
const FUELLED_TIMEOUT := 120.0

var _failures := 0
var _world: Node2D
var _car: HillCar
var _slope := 0.0
## 坡面（不含圆弧过渡）的水平范围，用来判断车是不是真的还在坡上。
var _slope_x0 := 0.0
var _slope_x1 := 0.0


func _ready() -> void:
	Engine.time_scale = 1.0
	# 无头模式下掉帧超过 8 个物理步（133ms）时 Godot 会**丢弃**多余的步，步数一飘
	# 结果就飘。D/E2 要现场生成整块地形，正好是最容易超过 133ms 的地方。
	# 提高上限只是「慢慢追」，不改变单步精度，所以不违反坑 #1。
	Engine.max_physics_steps_per_frame = 64
	SaveData.persist = false
	SaveData.reset_progress()

	_section_a()
	print("")
	await _section_b()
	print("")
	await _section_c()
	print("")
	await _section_d()
	print("")
	await _section_e1()
	print("")
	await _section_e2()

	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _check_true(label: String, cond: bool, detail: String) -> void:
	if not cond:
		_failures += 1
	print("  %s %s（%s）" % ["OK  " if cond else "FAIL", label, detail])


## 浮点比较。每级倍率是照「满级落在哪儿」**反推**出来的（比如引擎那 1.0197 是
## 1.2155 的十次方根），到不了精确相等，只能用容差。
func _check_close(label: String, got: float, want: float) -> void:
	_check_true(label, absf(got - want) < 0.0005, "%.4f（期望 %.4f）" % [got, want])


## 这个文件测的是「越野车」（`car.tscn`），也就是默认那辆车。
## 升级改成按车分开之后，改等级必须指明是哪辆车 —— 不能靠「当前选中那辆」，
## 那取决于 `selected_vehicle`，而它是玩家存档里来的。
func _set_build(engine: int, speed: int, fuel: int, agility: int) -> void:
	var lv := SaveData.levels_of(Vehicles.DEFAULT)
	lv["engine"] = engine
	lv["speed"] = speed
	lv["fuel"] = fuel
	lv["agility"] = agility


# ------------------------------------------------------------ A. 静态表

func _section_a() -> void:
	print("=== A. 升级表 ===")
	print("  %-8s %-14s %s" % ["项", "满级倍率", "每级花销 → 单项满级"])
	var grand := 0
	for id in Upgrades.IDS:
		var track: Dictionary = Upgrades.TRACKS[id]
		var costs := PackedStringArray()
		var sub := 0
		for lv in range(Upgrades.MAX_LEVEL):
			costs.append(str(Upgrades.cost(lv)))
			sub += Upgrades.cost(lv)
		grand += sub
		print("  %-8s ×%-13.3f %s  = %d" % [
			track["zh"], Upgrades.display_mult(id, Upgrades.MAX_LEVEL), " / ".join(costs), sub,
		])
	print("  四项全满 = %d 币" % grand)
	print("  原厂推重比 %.3f   引擎满级 %.3f   （翘头线 %.2f）" % [
		Upgrades.stock_thrust_ratio(), Upgrades.max_thrust_ratio(), Upgrades.WHEELIE_LINE,
	])

	# ---- 从 4 级改成 10 级时钉下的两条规矩 ----
	#
	# 1. **满级落在哪儿不变。** 把上限从 4 拉到 10 时最容易犯的错是照抄每级倍率，
	#    那样满级强度直接翻几倍。四个每级倍率是反推出来的，等式右边就是旧版 Lv.4
	#    的值，这里再算一遍。
	_check_close("引擎满级 = 旧 4 级版的 1.05⁴", Upgrades.engine_mult(Upgrades.MAX_LEVEL), pow(1.05, 4.0))
	_check_close("极速满级 = 旧 4 级版的 1.06⁴", Upgrades.speed_mult(Upgrades.MAX_LEVEL), pow(1.06, 4.0))
	_check_close("油箱满级 = 旧 4 级版的 1.60", Upgrades.fuel_mult(Upgrades.MAX_LEVEL), 1.60)
	_check_close("敏捷满级 = 旧 4 级版的 0.50", Upgrades.agility_mult(Upgrades.MAX_LEVEL), 0.50)

	# 2. **每一项逐级都得更好，而且显示倍率不能掉到 1 以下。**
	#    这条是照着实测踩到的坑加的：旧的敏捷是 −12.5%/级，直接拉到 10 级的话
	#    Lv.8 就归零、Lv.10 变成 −0.25 —— 转动惯量成了负数，刚体不成立；
	#    而 `display_mult()` 会把它显示成 ×−4.00，面板上看着像降级。
	for id in Upgrades.IDS:
		var bad := ""
		for lv in range(Upgrades.MAX_LEVEL + 1):
			var m := Upgrades.display_mult(id, lv)
			if m < 0.999:
				bad = "Lv%d 显示 ×%.3f < 1（看着像降级）" % [lv, m]
			elif lv > 0 and m <= Upgrades.display_mult(id, lv - 1):
				bad = "Lv%d 没有比 Lv%d 更好" % [lv, lv - 1]
		# 敏捷额外盯一眼**原始**倍率：它是唯一会变负的那项
		if id == "agility" and Upgrades.agility_mult(Upgrades.MAX_LEVEL) <= 0.05:
			bad = "满级转动惯量 ×%.3f，是负数或近零" % Upgrades.agility_mult(Upgrades.MAX_LEVEL)
		_check_true("%s：%d 级逐级更好、倍率 ≥ 1" % [Upgrades.TRACKS[id]["zh"], Upgrades.MAX_LEVEL],
				bad == "", bad if bad != "" else "Lv0 ×1.000 → Lv%d ×%.3f" % [
					Upgrades.MAX_LEVEL, Upgrades.display_mult(id, Upgrades.MAX_LEVEL),
				])

	# Upgrades 的基准值现在是从 car.tscn 现读的（以前是复制一份常量，会失配）。
	# 这里独立地再读一遍同样的东西，确认它的推导没错：轮子集合、重力系数、质量求和。
	#
	# 判据要**自己再写一遍**（而不是复用 Vehicles 的那个 helper）才有意义 —— 这边
	# 数出来几个轮子、质量多少，去对那边算出来的数。两边同时改错就抓不到了，
	# 但那种情况有 tests/vehicles 的场景契约那一节兜着。
	var ref: HillCar = CAR.instantiate()
	var wheels: Array[RigidBody2D] = []
	for child in ref.get_children():
		var body := child as RigidBody2D
		if body != null and body.is_in_group(Vehicles.WHEEL_GROUP):
			wheels.append(body)
	var mass := (ref.get_node("Chassis") as RigidBody2D).mass
	for wheel in wheels:
		mass += wheel.mass
	var radius: float = (wheels[0].get_node("Shape") as CollisionShape2D).shape.radius
	var b := Upgrades.base()
	_check("Upgrades 转速基数 vs 真车", b["wheel_speed"], ref.max_wheel_speed)
	_check("Upgrades 扭矩基数 vs 真车", b["motor_strength"], ref.motor_strength)
	_check("Upgrades 轮半径 vs 真车", b["radius"], radius)
	_check("Upgrades 整车重量 vs 真车", b["weight"], mass * Upgrades.GRAVITY)
	_check("Upgrades 轮数 vs 真车", b["wheels"], wheels.size())
	ref.free()

	# 原厂车自己就越过翘头线的话，练引擎等于练自毁。这里**只报告不判失败**：
	# 车调猛了是车辆调参的事，不是改装系统的 bug，该看到这个数字的是调车的人。
	if Upgrades.stock_thrust_ratio() >= Upgrades.WHEELIE_LINE:
		print("  ⚠ 原厂车推重比 %.3f 已越过翘头线 %.2f，练引擎只会更容易翻车" % [
			Upgrades.stock_thrust_ratio(), Upgrades.WHEELIE_LINE,
		])


# ------------------------------------------------------------ 世界搭建

## 平地故意拉得很长：E1 要全油门跑到烧干（满级油箱 27 秒、约 13000 px），
## 短了车会冲下平台边缘一直往下掉，虽然不影响油耗，但读起来像出了事。
func _flat_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-400.0, 0.0), Vector2(20000.0, 0.0),
		Vector2(20000.0, 900.0), Vector2(-400.0, 900.0),
	])


func _ramp_points(theta: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(-400.0, 0.0))
	pts.append(Vector2(RUN_UP, 0.0))
	var steps := maxi(4, int(ceil(rad_to_deg(theta) / 4.0)))
	for i in range(1, steps + 1):
		var a := theta * float(i) / float(steps)
		pts.append(Vector2(RUN_UP + ARC_RADIUS * sin(a), -ARC_RADIUS * (1.0 - cos(a))))
	var start: Vector2 = pts[pts.size() - 1]
	var dir := Vector2(cos(theta), -sin(theta))
	var end := start + dir * RAMP_LEN
	pts.append(end)
	pts.append(end + Vector2(0.0, 900.0))
	pts.append(Vector2(-400.0, 900.0))
	_slope_x0 = RUN_UP + ARC_RADIUS * sin(theta)
	_slope_x1 = _slope_x0 + RAMP_LEN * cos(theta)
	return pts


## 拆掉当前地形并**等它真的消失**。
##
## `queue_free()` 是延迟到帧末执行的，不等这一帧的话新旧地形会重叠一帧，
## 新出生的车正好卡在旧碰撞体内部被弹飞。（最早没等，D 段每次都是 0 m 秒翻车
## —— 因为 C 段那条 40° 坡道的碰撞体还压在 main 场景的出生点上。）
func _clear_world() -> void:
	if _world == null:
		return
	_world.queue_free()
	_world = null
	await get_tree().process_frame


## 换一套地形 + 一台按当前等级配好的车。
##
## `infinite_fuel` 默认开：B/C/D 段要研究的是扭矩、齿比、惯量，油得从等式里拿掉。
## E1 研究的就是油箱本身，那里传 false。
func _build(theta: float, infinite_fuel := true) -> void:
	await _clear_world()
	_slope = theta
	_world = Node2D.new()
	add_child(_world)

	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = _flat_points() if is_zero_approx(theta) else _ramp_points(theta)
	body.add_child(shape)
	_world.add_child(body)

	_car = CAR.instantiate()
	if infinite_fuel:
		# 必须在 add_child **之前**改：_ready() 里有一句 fuel = fuel_max，
		# 等进了树再改 fuel_max 就只能得到一个半箱油。
		_car.fuel_max = 1.0e9
	_car.position = Vector2(START_X, CAR_Y)
	_world.add_child(_car)
	# 加满。写 fuel_max 而不是 1e9：_ready() 里的 Upgrades.apply 已经把等级倍率
	# 乘进 fuel_max 了，照它加满才能同时兼顾「无限油」和「真实油」两种情况。
	_car.fuel = _car.fuel_max
	# 不开 contact_monitor 的话 get_colliding_bodies() 会一直返回空数组并报错，
	# 「前轮离地时间」就会恒等于总时长，看起来像一直在飞。
	for part in [_car.chassis, _car.rear_wheel, _car.front_wheel]:
		part.contact_monitor = true
		part.max_contacts_reported = 8


## 沿坡面的单位向量（屏幕坐标 y 向下，所以上坡是 -y）。
func _slope_dir() -> Vector2:
	return Vector2(cos(_slope), -sin(_slope))


# ------------------------------------------------------------ B. 平路翘头

func _section_b() -> void:
	print("=== B. 平路起步翘头余量（%.0fs 全油门）===" % LAUNCH_TIME)
	print("  %-22s %-9s %-11s %-13s %s" % ["配置", "推重比", "最大抬头", "前轮离地", "末速"])
	var configs := [
		{"label": "原厂", "engine": 0, "speed": 0},
		{"label": "引擎 Lv2", "engine": 2, "speed": 0},
		{"label": "引擎 Lv4", "engine": 4, "speed": 0},
		{"label": "极速 Lv4", "engine": 0, "speed": 4},
		{"label": "引擎 Lv4 + 极速 Lv4", "engine": 4, "speed": 4},
	]
	for cfg in configs:
		_set_build(cfg["engine"], cfg["speed"], 0, 0)
		await _build(0.0)
		Input.action_press("drive_forward")
		var t := 0.0
		var max_pitch := 0.0
		var air := 0.0
		while t < LAUNCH_TIME:
			await get_tree().create_timer(0.1).timeout
			t += 0.1
			max_pitch = minf(max_pitch, rad_to_deg(_car.chassis.rotation))
			if _car.front_wheel.get_colliding_bodies().is_empty():
				air += 0.1
		Input.action_release("drive_forward")
		print("  %-22s %-9.3f %-11s %-13s %.0f px/s%s" % [
			cfg["label"], Upgrades.thrust_ratio(cfg["engine"]),
			"%.1f°" % -max_pitch,
			"%.2fs / %.2fs" % [air, LAUNCH_TIME],
			_car.chassis.linear_velocity.length(),
			"" if _car.alive else "  （翻车）",
		])


# ------------------------------------------------------------ C. 稳态爬坡

func _section_c() -> void:
	print("=== C. %.0f° 稳态爬坡速度（验证齿比不吃爬坡）===" % CLIMB_ANGLE)
	var theta := deg_to_rad(CLIMB_ANGLE)
	var configs := [
		{"label": "原厂", "engine": 0, "speed": 0},
		{"label": "引擎 Lv4", "engine": 4, "speed": 0},
		{"label": "极速 Lv4", "engine": 0, "speed": 4},
		{"label": "引擎 Lv4 + 极速 Lv4", "engine": 4, "speed": 4},
	]
	print("  %-22s %-12s %s" % ["配置", "坡面均速", "采样帧数"])
	var base := 0.0
	for cfg in configs:
		_set_build(cfg["engine"], cfg["speed"], 0, 0)
		await _build(theta)
		Input.action_press("drive_forward")
		var t := 0.0
		var acc := 0.0
		var n := 0
		while t < CLIMB_TIME:
			await get_tree().create_timer(0.1).timeout
			t += 0.1
			# 只在**还在坡面上**的时候采样：车冲过坡顶会掉下去，那一小段的
			# 速度是朝下的，算进来会把均速拉成负数（最早就是这么得到 -372 的）。
			var x: float = _car.chassis.global_position.x
			if _car.alive and x >= _slope_x0 and x <= _slope_x1:
				acc += _car.chassis.linear_velocity.dot(_slope_dir())
				n += 1
		Input.action_release("drive_forward")
		var avg := acc / maxf(1.0, float(n))
		if cfg["label"] == "原厂":
			base = avg
		var delta := ""
		if base != 0.0 and n > 0:
			delta = "  (%+.0f%%)" % ((avg / base - 1.0) * 100.0)
		print("  %-22s %6.0f px/s%-4s %d%s" % [
			cfg["label"], avg, delta, n, "" if _car.alive else "  （翻车）",
		])


# ------------------------------------------------------------ D. 真实地形

func _section_d() -> void:
	print("=== D. 真实地形里程（敏捷等级 × %.0fs，同种子 1337）===" % RUN_TIME)
	# 把上一步的坡道清干净再进真实关卡，否则两套碰撞体重叠，车一出生就卡住
	await _clear_world()

	var meters: Array[int] = []
	for lv in range(Upgrades.MAX_LEVEL + 1):
		_set_build(0, 0, 0, lv)
		var main: HillGame = MAIN.instantiate()
		add_child(main)
		await get_tree().process_frame

		main.car.fuel_max = 1.0e9
		main.car.fuel = 1.0e9
		Input.action_press("drive_forward")
		var t := 0.0
		while t < RUN_TIME and not main.game_over:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		Input.action_release("drive_forward")

		meters.append(main.distance_meters())
		print("  敏捷 Lv%d（惯量 ×%.3f）  %5d m%s" % [
			lv, Upgrades.agility_mult(lv), meters[lv],
			"  （翻车）" if main.game_over else "",
		])
		main.queue_free()
		await get_tree().process_frame

	# 只断言两端，不断言逐级单调。真实地形里程的噪声有 ±2%（掉帧会推迟区块生成），
	# 而每一级的真实收益只有 ~2.5%，逐级比较必然偶尔出现「Lv3 比 Lv2 低」的假信号。
	# 两端差 10% 则远超噪声，能真正抓住「把敏捷改成越升越差」这种回归。
	var gain := float(meters[Upgrades.MAX_LEVEL]) / maxf(1.0, float(meters[0]))
	print("  满级 / 原厂 = %.3f" % gain)
	_check("敏捷满级至少 +5% 里程（升级不能越升越差）", gain >= 1.05, true)


# ------------------------------------------------------------ E. 油箱

## E1 干净的烧干时长：平地、无补给、全油门。
##
## 油耗只跟油门有关（怠速 1.6 + 全油门 4.4 = 6.0/s），所以用时应该严格等于
## 容量 ÷ 油耗率 —— 这是**唯一**能精确验证「油箱 ×1.6」的场合。
func _section_e1() -> void:
	print("=== E1. 烧干用时（平地、无补给、全油门）===")
	var actual: Array[float] = []
	var expect: Array[float] = []
	var tanks: Array[float] = []
	for lv in [0, Upgrades.MAX_LEVEL]:
		_set_build(0, 0, lv, 0)
		await _build(0.0, false)
		var tank := _car.fuel_max
		var rate: float = _car.fuel_idle_drain + _car.fuel_throttle_drain
		Input.action_press("drive_forward")
		var t := 0.0
		while _car.alive and t < FUELLED_TIMEOUT:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		Input.action_release("drive_forward")
		tanks.append(tank)
		actual.append(t)
		expect.append(tank / rate)
		print("  油箱 Lv%d  容量 %5.0f  烧干用时 %5.2fs（容量÷油耗 = %5.2fs）  跑出 %5.0f px" % [
			lv, tank, t, tank / rate, _car.chassis.global_position.x - START_X,
		])

	print("  容量比 %.3f   用时比 %.3f" % [tanks[1] / tanks[0], actual[1] / actual[0]])
	_check("容量比 = 满级倍率 ×1.60",
			is_equal_approx(snappedf(tanks[1] / tanks[0], 0.001),
					snappedf(Upgrades.fuel_mult(Upgrades.MAX_LEVEL), 0.001)), true)
	# 1% 的宽容度：循环按帧退出，最后一帧可能多烧一点或少烧一点。
	for i in 2:
		_check("Lv%d 用时 = 容量÷油耗率（±1%%）" % [0 if i == 0 else Upgrades.MAX_LEVEL],
				absf(actual[i] - expect[i]) / expect[i] < 0.01, true)


## E2 真实地形上的实际收益。**不能**像 D 段那样把油设成 1e9，那样等于把油箱升级
## 测没了；这里让它真的会烧干。
##
## 结论：满级只多跑约 4%（1995 → 2080 m），远不到容量的 1.6 倍。原因是地形越远越陡
## （振幅 42 → 140），烧干前那几秒的推进速度本来就低；而且两趟都是**烧干**收场
## （剩油 0.0，不是翻车），说明沿途油桶（每个 +34）补给稀疏，撑不到「永远跑下去」。
## 所以油箱是「把这一局多续一口气」，不是「里程 ×1.6」。
func _section_e2() -> void:
	print("=== E2. 真实地形一箱油能跑多远（同种子 1337，沿途有油桶）===")
	# 和 D 段同样的理由：E1 那块 20000 px 长的平地还盖在出生点上，
	# 不清掉的话 main 场景的车一出生就卡在碰撞体里，两趟都是 0 m 秒翻车。
	await _clear_world()
	for lv in [0, Upgrades.MAX_LEVEL]:
		_set_build(0, 0, lv, 0)
		var main: HillGame = MAIN.instantiate()
		add_child(main)
		await get_tree().process_frame

		Input.action_press("drive_forward")
		var t := 0.0
		while t < FUELLED_TIMEOUT and not main.game_over:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		Input.action_release("drive_forward")

		# 死因要看油量：光看 game_over 会把「烧干」也报成「翻车」。实测这两趟
		# 剩油都是 0.0，死因全是烧干（第一版就是这里报错，才误以为「油箱没用」）。
		var why := "超时"
		if main.game_over:
			why = "烧干" if main.car.fuel <= 0.0 else "翻车"
		print("  油箱 Lv%d（容量 ×%.2f）  %5d m   跑了 %4.1fs   剩油 %5.1f / %.0f   （%s）" % [
			lv, Upgrades.fuel_mult(lv), main.distance_meters(), t,
			main.car.fuel, main.car.fuel_max, why,
		])
		main.queue_free()
		await get_tree().process_frame
