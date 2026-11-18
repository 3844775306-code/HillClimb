extends Node
## 转动惯量参数（car.inertia_scale）的验证。
##
## 1. 确认 body_get_param(BODY_PARAM_INERTIA) 读得到有效值 —— 读不到的话
##    整个倍率会静默失效，这是最容易悄悄翻车的地方（第一版就栽在这）。
## 2. 确认倍率确实线性生效。
## 3. 扫一遍倍率，看它换来了什么、代价是什么。
##
## 第 3 项分两种施加方式对比：
##   all     = 车壳 + 两个轮子一起放大（字面意义的「整车惯性」）
##   chassis = 只放大车壳
## 分开测是因为猜测拖累爬坡的是轮子：轮子惯量大，转速式马达就带不动它提速，
## 爬坡时需要持续给轮子加速，正好撞在这一点上；而俯仰摆动是车壳的事，
## 跟轮子无关。若猜测成立，chassis 模式应当同时拿到稳定性和爬坡。

const CAR_SCENE := preload("res://scenes/car.tscn")

const START_X := 120.0
const CAR_Y := -39.0
const RUN_UP := 700.0
const RAMP_LEN := 900.0
const ARC_RADIUS := 260.0
const CLIMB_ANGLE := 45.0

# 搓板路（washboard）：一串等间距圆鼓包，量「被地形顶得前仰后合」的程度
const BUMP_START := 620.0
const BUMP_END := 1900.0
const BUMP_PERIOD := 70.0
const BUMP_AMP := 9.0
const BUMP_SPINUP := 1.2   ## 进搓板路前的平路助跑时间
const BUMP_FRAMES := 210    ## 逐物理帧采样，60Hz 下约 3.5s

const SCALES := [1.0, 2.0, 4.0]
const MODES := ["all", "chassis"]

var _world: Node2D
var _car: HillCar
var _mode := "all"
var _ramp_end := Vector2.ZERO


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1，理由见 climb.gd
	# 这个测试要手动扫 inertia_scale，不能被车库里「敏捷」那一项的倍率叠乘上去
	SaveData.persist = false
	SaveData.reset_progress()
	await _probe_inertia()
	print("")
	await _probe_linearity()
	for mode in MODES:
		print("")
		await _sweep_bumps(mode)
		for angle in [40.0, 45.0]:
			print("")
			await _sweep_climb(mode, angle)
	get_tree().quit()


## 物理服务器要到第 2 个物理帧才把形状换算成惯量（见 car.gd 的注释），
## 读值前先等够帧数，否则读到的是 0。
func _settle() -> void:
	for i in range(4):
		await get_tree().physics_frame


## 直接读三个刚体的自动惯量：值必须是正数，否则倍率无从谈起。
func _probe_inertia() -> void:
	print("=== 自动惯量读数 ===")
	var car := CAR_SCENE.instantiate()
	car.inertia_scale = 1.0          # 先别放大，看原始值
	add_child(car)
	await _settle()
	for entry in [["车壳", car.chassis], ["后轮", car.rear_wheel], ["前轮", car.front_wheel]]:
		var body: RigidBody2D = entry[1]
		var auto_inertia := _auto_inertia(body)
		print("%s  mass %6.1f  自动惯量 %10.2f  %s" % [
			entry[0], body.mass, auto_inertia,
			"OK" if auto_inertia > 0.0 else "!! 读不到，倍率会静默失效",
		])
	car.queue_free()
	await get_tree().process_frame


## 同一辆车设成不同倍率，惯量应当严格成正比。
func _probe_linearity() -> void:
	print("=== 倍率线性验证（车壳）===")
	var base := 0.0
	for scale in [1.0, 2.0, 4.0]:
		var car := CAR_SCENE.instantiate()
		car.inertia_scale = scale
		add_child(car)
		await _settle()
		var got := _auto_inertia(car.chassis)
		if scale == 1.0:
			base = got
		var ratio := got / base if base > 0.0 else 0.0
		print("倍率 %.1f  →  惯量 %10.2f   实测比值 %.3f %s" % [
			scale, got, ratio,
			"OK" if absf(ratio - scale) < 0.01 else "!! 不成比例",
		])
		car.queue_free()
		await get_tree().process_frame


func _auto_inertia(body: RigidBody2D) -> float:
	return PhysicsServer2D.body_get_param(body.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA)


## 平路 + 搓板路。指标：过搓板路时的俯仰标准差/峰值，以及通过速度。
## 这是惯量最直接的作用面 —— 车越「沉」，被鼓包顶起来的摆动越小、越保速。
func _sweep_bumps(mode: String) -> void:
	print("=== 搓板路（%s）===" % _mode_name(mode))
	for scale in SCALES:
		await _build_bumps(scale, mode)
		Input.action_press("drive_forward")
		var t := 0.0
		while t < BUMP_SPINUP:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		var samples: Array[float] = []
		for i in range(BUMP_FRAMES):
			await get_tree().physics_frame
			if not _car.alive:
				break
			if _car.chassis.global_position.x > BUMP_START:
				samples.append(rad_to_deg(_car.chassis.rotation))
		var speed := _car.chassis.linear_velocity.length()
		Input.action_release("drive_forward")
		var n := maxf(1.0, float(samples.size()))
		var mean := 0.0
		for s in samples:
			mean += s
		mean /= n
		var var_sum := 0.0
		var peak := 0.0
		for s in samples:
			var_sum += (s - mean) * (s - mean)
			peak = maxf(peak, absf(s - mean))
		print("惯量 ×%.1f   出搓板路时速 %4.0f   俯仰标准差 %4.2f°   峰值 %5.2f°   %s" % [
			scale, speed, sqrt(var_sum / n), peak,
			"翻车" if not _car.alive else "",
		])


## 45° 坡：惯量不能把爬坡能力压坏。
## 量的是**坡面上的稳态爬坡速度**，不是「固定时刻爬到百分之几」。
## 后者会把「已经冲上坡顶飞出去」和「还在坡上爬」混为一谈 —— 先到的那个
## 反而会显示成俯仰异常、速度虚高。稳态速度才是爬坡能力的干净读数。
func _sweep_climb(mode: String, angle: float) -> void:
	print("=== %.0f° 坡面稳态爬坡速度（%s）===" % [angle, _mode_name(mode)])
	var theta := deg_to_rad(angle)
	var dir := Vector2(cos(theta), -sin(theta))
	for scale in SCALES:
		await _build_ramp(scale, mode, angle)
		Input.action_press("drive_forward")
		# 等车真正吃上坡面：俯仰贴合坡度，且已经越过圆弧过渡段
		var settled := false
		var t := 0.0
		while t < 8.0 and _car.alive:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if absf(rad_to_deg(_car.chassis.rotation) + angle) < 2.0 \
					and _car.chassis.global_position.x > RUN_UP + ARC_RADIUS:
				settled = true
				break
		var total := 0.0
		var n := 0
		for i in range(90):   # 1.5 秒
			await get_tree().physics_frame
			if not _car.alive:
				break
			total += _car.chassis.linear_velocity.dot(dir)
			n += 1
		Input.action_release("drive_forward")
		var mean := total / maxf(1.0, float(n))
		var note := "翻车" if not _car.alive else ("" if settled else "没吃上坡面")
		print("惯量 ×%.1f   稳态爬坡速度 %4.0f px/s   打滑 %+5.0f   %s" % [
			scale, mean,
			_car.rear_wheel.angular_velocity * 21.0 - mean,
			note,
		])


func _mode_name(mode: String) -> String:
	return "整车：车壳+双轮" if mode == "all" else "只放车壳"


# ---- 场景搭建 ----

## 造车并等倍率真正落地。mode == "chassis" 时把两个轮子退回自动惯量。
func _new_car(scale: float, mode: String) -> HillCar:
	var car := CAR_SCENE.instantiate()
	car.inertia_scale = scale
	car.fuel_max = 1.0e9
	car.position = Vector2(START_X, CAR_Y)
	_world.add_child(car)
	car.fuel = 1.0e9
	for part in [car.chassis, car.rear_wheel, car.front_wheel]:
		part.contact_monitor = true
		part.max_contacts_reported = 8
	await _settle()   # car.gd 是异步应用倍率的，等它落定再决定要不要回退轮子
	if mode == "chassis":
		car.rear_wheel.inertia = 0.0   # 0 = 交回自动
		car.front_wheel.inertia = 0.0
	return car


func _add_ground(points: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = points
	body.add_child(shape)
	_world.add_child(body)


func _reset(mode: String) -> void:
	if _world != null:
		_world.queue_free()
	_world = Node2D.new()
	add_child(_world)
	_mode = mode


func _build_bumps(scale: float, mode: String) -> void:
	_reset(mode)
	var pts := PackedVector2Array()
	pts.append(Vector2(-400.0, 0.0))
	var x := 0.0
	while x <= 2600.0:
		var y := 0.0
		if x > BUMP_START and x < BUMP_END:
			# 全波整流正弦 —— 连续的一串圆鼓包，没有尖角
			y = -BUMP_AMP * absf(sin(x / BUMP_PERIOD * PI))
		pts.append(Vector2(x, y))
		x += 10.0
	pts.append(Vector2(2600.0, 900.0))
	pts.append(Vector2(-400.0, 900.0))
	_add_ground(pts)
	_car = await _new_car(scale, mode)


func _build_ramp(scale: float, mode: String, theta_deg: float) -> void:
	_reset(mode)
	var theta := deg_to_rad(theta_deg)
	var pts := PackedVector2Array()
	pts.append(Vector2(-400.0, 0.0))
	pts.append(Vector2(RUN_UP, 0.0))
	var steps := maxi(4, int(ceil(theta_deg / 4.0)))
	for i in range(1, steps + 1):
		var a := theta * float(i) / float(steps)
		pts.append(Vector2(RUN_UP + ARC_RADIUS * sin(a), -ARC_RADIUS * (1.0 - cos(a))))
	_ramp_end = pts[pts.size() - 1] + Vector2(cos(theta), -sin(theta)) * RAMP_LEN
	pts.append(_ramp_end)
	pts.append(_ramp_end + Vector2(0.0, 900.0))
	pts.append(Vector2(-400.0, 900.0))
	_add_ground(pts)
	_car = await _new_car(scale, mode)
