extends Node
## 独轮车「满油门就翻」的力学账。**这不是测试，是量尺** —— 不判对错，只打数字。
##
## 背景：独轮车满油门会给车壳一个**实打实**的抬头力矩。马达的力矩 τ 让轮子把地面
## 往后蹬，地面把轮子往前推，销子再把这个力拽到车壳上；力作用在**轮心**，而车壳
## 重心在轮心上方 `d` 处，于是多出 `d · P`。反馈回路得先看到倾角才出力，等它反应
## 过来车已经仰过去了 —— 独轮车只有这一个支点，一仰就是翻。
##
## [method HillCar.balance_assist] 那套前馈就是补这一项。**补多补少都会翻，只是方向
## 反过来**（补多了往前扎），所以下面第二节把「实测销力 / 模型销力 / 前馈力矩 /
## 陀螺仪力矩 / 重力倾覆力矩」逐帧并排打出来，一眼看得出哪一项没对上。
##
## ## 三个坑，都踩过
##
## 1. **探针必须调 `SaveData.reset_progress()`。** `persist = false` 只挡「写盘」，
##    **不挡开局 `load_data()`** —— 不调的话跑的是存档里那套（练满的引擎、敏捷……
##    都在），量出来的习性和全新档完全不是一回事。实测：玩家存档里敏捷练满时
##    `inertia_scale` 从 2.0 被降到 1.0，`_apply_inertia_scale` 于是**整体跳过**
##    （那是它的恒等分支），陀螺仪力矩上限当场少一半，车翻得更早。
## 2. **Godot 2D 的「自动重心」不是形状的面积质心。** `RectangleShape2D` /
##    `CircleShape2D` 看不出来（原点就是质心），但 `ConvexPolygonShape2D` 认的是
##    **碰撞形状自己的位置**。第一节用动力学把它量出来（引擎报什么不算数）。
## 3. **残差是恒定的**，所以 `balance_damping` 几乎不影响常驻倾角，能压住它的是
##    `balance_full_angle`（第三节扫的就是这个）。

const CAR := preload("res://scenes/vehicles/mono.tscn")
const WHEEL_REST := 54.0
const SETTLE := 24
const DRIVE := 120
const LOG := 132

var _world: Node2D


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	# 见头注释第 1 条：不调这个，量到的是存档里那套。
	SaveData.reset_progress()
	_build_world()
	await _lever()
	print("")
	await _transient()
	print("")
	await _sweep()
	print("")
	get_tree().quit()


func _build_world() -> void:
	_world = Node2D.new()
	add_child(_world)
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# 够长：第三节每种组合都要满油门跑 2 秒（一千多像素）。
	rect.size = Vector2(200000.0, 1200.0)
	shape.shape = rect
	shape.position = Vector2(0.0, 600.0)
	body.add_child(shape)
	_world.add_child(body)


func _make(full := -1.0, damp := -1.0) -> HillCar:
	if _world.get_child_count() > 1:
		_world.get_child(1).queue_free()
	var car: HillCar = CAR.instantiate()
	if full >= 0.0:
		car.balance_full_angle = full
	if damp >= 0.0:
		car.balance_damping = damp
	car.position = Vector2(0.0, -WHEEL_REST)
	car.fuel = 1.0e9
	_world.add_child(car)
	car.apply_map(Maps.PLAINS)
	return car


# ---------------------------------------------------------------- 一、力臂

## 销子（轮心）在重心下方多少 —— 也就是马达那个反作用力的力臂。
##
## 判别法：自由刚体（无重力、无碰撞）上加一个**过原点**的冲量 J = (Jx, 0)，则
##     Δω = ((冲量作用点 − 重心) × J) / I = −(dy · Jx) / I
## 于是 `dy = −I · Δω / Jx`。**只信动力学，不信 `BODY_PARAM_CENTER_OF_MASS` 报什么**。
func _lever() -> void:
	print("=== 一、力臂：过原点的冲量推一把，看它转不转 ===")
	var mono := CAR.instantiate()
	var real_shape := (mono.get_node("Chassis/Body") as CollisionShape2D).shape
	mono.free()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(80.0, 250.0)
	await _weigh("矩形 偏移 (0, 0)　", rect, 0.0)
	await _weigh("矩形 偏移 (0, 50) ", rect, 50.0)
	await _weigh("矩形 偏移 (0, -50)", rect, -50.0)
	await _weigh("梯形（车壳真形状）", real_shape, 0.0)
	print("  → 前三条是**对照组**：偏移多少就该量出多少，方法本身是对的；")
	print("    梯形量出 0，说明引擎给它的重心取的是**形状自己的位置**，")
	print("    不是面积质心（面积质心在 (0, 3.8)，见下面那张表的差）。")


func _weigh(label: String, shape: Shape2D, offset: float) -> void:
	var body := RigidBody2D.new()
	body.gravity_scale = 0.0
	body.mass = 62.0
	body.can_sleep = false
	body.collision_layer = 0
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0.0, offset)
	body.add_child(cs)
	# 摆远一点、并排摆：都堆在原点的话它们会互相撞，量到的 ω 里混着接触力。
	body.position = Vector2(4000.0 * float(_weighed), 0.0)
	add_child(body)
	_weighed += 1
	for i in 4:
		await get_tree().physics_frame
	var reported: Vector2 = PhysicsServer2D.body_get_param(
			body.get_rid(), PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS)
	var inertia: float = PhysicsServer2D.body_get_param(
			body.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA)
	var jx := 500.0
	body.apply_impulse(Vector2(jx, 0.0), Vector2.ZERO)
	await get_tree().physics_frame
	print("  %s  引擎报的重心 %-12s 实测力臂 dy = %+7.3f" % [
		label, str(reported), -inertia * body.angular_velocity / jx])


var _weighed := 0


# ---------------------------------------------------------------- 二、逐帧的账

## 满油门起步那 2 秒，把车壳受的力矩逐项打出来。
##
## 「实测销力」是车壳的水平动量变化率 ÷ 质量 —— 水平方向上只有销子在推它，所以这
## 是**真的**销力。但它里面已经含着前馈的效果了（前馈把车壳往低头拧，车壳于是更
## 难被销子拽动），所以它是**交叉验证**，不是「如果没有前馈会怎样」。
func _transient() -> void:
	print("=== 二、满油门起步：车壳受的力矩逐项 ===")
	var car := _make()
	for i in SETTLE:
		await get_tree().physics_frame
	var chassis := car.chassis
	var wheel: RigidBody2D = car.wheels[0]
	var mass := chassis.mass
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var radius := car._wheel_radius()
	var lever := car._pin_lever()
	var share := car._reaction_share()
	print("  力臂 %.2f   反作用比例 %.4f   惯量 %.0f" % [
		lever, share, car._auto_inertia(chassis)])
	print("  陀螺仪力矩上限 %.0f   重力倾覆上限 %.0f   → 极限倾角 %.1f°" % [
		car.balance_torque * car._auto_inertia(chassis),
		mass * Upgrades.GRAVITY * lever,
		rad_to_deg(asin(clampf(
			car.balance_torque * car._auto_inertia(chassis)
				/ (mass * Upgrades.GRAVITY * lever), -1.0, 1.0)))])
	print("")
	print("  帧   倾角°    车壳ω   马达τ    实测销力  模型销力   前馈τ    陀螺仪τ  重力倾覆τ")
	var prev_vx := chassis.linear_velocity.x
	for i in LOG:
		if i == 0:
			Input.action_press("drive_forward")
		await get_tree().physics_frame
		var vx := chassis.linear_velocity.x
		var p_meas := mass * (vx - prev_vx) / dt
		prev_vx = vx
		var tau := car._motor_torque
		var lean := wrapf(chassis.rotation, -PI, PI)
		var gyro := 0.0
		if car.grounded:
			gyro = (-clampf(lean / car.balance_full_angle, -1.0, 1.0) * car.balance_torque
					- car.balance_damping * chassis.angular_velocity) * car._auto_inertia(chassis)
		if i % 4 == 0 and i <= 60 or i % 12 == 0:
			print("  %3d  %6.1f  %7.2f  %9.0f  %9.0f  %9.0f  %9.0f  %9.0f  %9.0f%s" % [
				i, rad_to_deg(lean), chassis.angular_velocity, tau, p_meas,
				share * tau / radius, car.balance_assist * lever * share * tau / radius,
				gyro, mass * Upgrades.GRAVITY * lever * sin(lean),
				"  翻" if absf(rad_to_deg(lean)) > 60.0 else ""])
	Input.action_release("drive_forward")


# ---------------------------------------------------------------- 三、调参扫描

## `balance_full_angle` 是压住常驻倾角的那一个数，`balance_damping` 不是。
##
## 陀螺仪对**恒定**力矩的等效刚度只有 `斜率 − m·g·d`（重力是正反馈，吃掉一大半），
## 斜率 = `balance_torque × 惯量 ÷ balance_full_angle`。前馈补完之后还剩一个恒定
## 残差，于是 常驻倾角 = 残差 ÷ (斜率 − m·g·d) —— **把 full_angle 调小就能压下去**，
## 而极限倾角不受影响（那由最大力矩定，两边都封顶）。
func _sweep() -> void:
	print("=== 三、满油门 2 秒之后的倾角（扫 balance_full_angle × balance_damping）===")
	print("  full_angle  damping    结束时倾角   全程最大   活着")
	for full in [0.50, 0.35, 0.25, 0.18, 0.12]:
		for damp in [0.6, 1.2]:
			var car := _make(full, damp)
			for i in SETTLE:
				await get_tree().physics_frame
			var worst := 0.0
			Input.action_press("drive_forward")
			for i in DRIVE:
				await get_tree().physics_frame
				worst = maxf(worst, absf(rad_to_deg(wrapf(car.chassis.rotation, -PI, PI))))
			Input.action_release("drive_forward")
			print("     %.2f       %.1f     %7.1f°    %7.1f°    %s" % [
				full, damp, absf(rad_to_deg(wrapf(car.chassis.rotation, -PI, PI))),
				worst, str(car.alive)])
	print("  → 场景里取的是 0.18：2.9° 前倾，而且留了余量（引擎练满后给油力矩还要涨两成）。")
	print("    阻尼那一列几乎不动 —— 残差是**恒定**的，速度阻尼压不住它。")
