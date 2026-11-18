extends Node
## 四张地图的物理修正实测。
##
## A. 静态表 —— 套上地图之后，车的摩擦/阻尼/油耗倍率确实是 [Maps] 里那些数
## B. 平原恒等 —— 默认地图什么都不改（否则以前所有基于平原的实测全废）
## C. 材质不共享 —— 雪地不能把同进程里别的车的轮子一起改滑
## D. 平路全油门 4s —— 荒漠的阻力真的让车变慢
## E. 雪地打滑 —— 轮子空转、车子走不动，用「轮面速度 ÷ 车速」直接量打滑
## F. 踩油门 5s —— 火山烧掉的油是平原的 1.6 倍
##
## 这个文件里的断言全是**比较**（荒漠比平原慢、雪地比平原滑），不是把某个绝对值
## 钉死 —— 车的参数由玩家在编辑器里调，钉死绝对值的测试会被每一次调参打翻。

const CAR := preload("res://scenes/car.tscn")

const START_X := 120.0
const CAR_Y := -39.0
const GROUND_LEN := 6000.0

## 平路跑多久。
const RUN_TIME := 4.0
## 测油耗跑多久。
const FUEL_TIME := 5.0
## 跑起来之前先让车落地。
const SETTLE_FRAMES := 12

var _failures := 0
var _world: Node2D
var _car: HillCar
var _wheel_radius := 21.0


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1，理由见 climb.gd
	SaveData.persist = false
	SaveData.reset_progress()

	_section_a()
	_section_b()
	_section_c()
	await _section_d()
	await _section_e()
	await _section_f()

	print("")
	print("失败 %d 项" % _failures)
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


func _approx(label: String, got: float, want: float, tol: float = 0.001) -> void:
	var ok := absf(got - want) <= tol
	_check(label, ok, "%.4f（期望 %.4f ±%.4f）" % [got, want, tol])


# ---------------------------------------------------------------- 静态表

func _section_a() -> void:
	print("=== A. 静态表 ===")
	var car := CAR.instantiate()
	add_child(car)
	_wheel_radius = (car.get_node("RearWheel/Shape") as CollisionShape2D).shape.radius
	var plain_friction: float = car.rear_wheel.physics_material_override.friction
	print("  场景原始摩擦 = %.3f  轮半径 = %.1f" % [plain_friction, _wheel_radius])

	for id in Maps.IDS:
		car.apply_map(id)
		var m: Dictionary = Maps.get_map(id)
		var got: float = car.rear_wheel.physics_material_override.friction
		var want: float = plain_friction * float(m["friction_scale"])
		_approx("%s 轮子摩擦" % id, got, want, 0.0005)
		_approx("%s 车壳阻尼" % id, car.chassis.linear_damp, m["drag"], 0.0005)
		_approx("%s 轮子阻尼" % id, car.rear_wheel.linear_damp, m["drag"], 0.0005)
		_approx("%s 油耗倍率" % id, car.fuel_drain_scale, m["fuel_scale"], 0.0005)

	# 前轮也得跟上，别只改了后轮。这里**不写死数字**：期望值从表里现取，
	# 断言的是「前轮 == 后轮 == 原值 × 表里的倍率」这个不变量，改平衡时不会失效。
	car.apply_map(Maps.SNOW)
	var snow_scale: float = float(Maps.get_map(Maps.SNOW)["friction_scale"])
	_approx("雪地后轮摩擦", car.rear_wheel.physics_material_override.friction,
			plain_friction * snow_scale, 0.0005)
	_approx("雪地前轮跟上后轮", car.front_wheel.physics_material_override.friction,
			car.rear_wheel.physics_material_override.friction, 0.0005)
	car.queue_free()


func _section_b() -> void:
	print("=== B. 平原恒等 ===")
	var car := CAR.instantiate()
	add_child(car)
	var before: float = car.rear_wheel.physics_material_override.friction
	car.apply_map(Maps.PLAINS)
	_approx("平原不改摩擦", car.rear_wheel.physics_material_override.friction, before, 0.0005)
	_approx("平原不加阻尼", car.chassis.linear_damp, 0.0, 0.0005)
	_approx("平原不改油耗", car.fuel_drain_scale, 1.0, 0.0005)
	_approx("平原不改噪声种子", float(Maps.noise_seed(1337, Maps.PLAINS)), 1337.0, 0.5)
	car.queue_free()


## 物理材质是 car.tscn 里的 sub-resource —— 同一个场景的实例默认**共用同一个
## Resource 对象**。忘了 duplicate() 的话，一辆车调雪地会把全世界都改滑。
func _section_c() -> void:
	print("=== C. 材质不共享 ===")
	var first := CAR.instantiate()
	add_child(first)
	var pristine: float = first.rear_wheel.physics_material_override.friction
	first.apply_map(Maps.SNOW)

	var second := CAR.instantiate()
	add_child(second)
	var other: float = second.rear_wheel.physics_material_override.friction
	_check("第二辆车的轮子没被第一辆的雪地带滑", is_equal_approx(other, pristine),
			"新实例 %.3f（原值 %.3f）" % [other, pristine])
	_check("两辆车不是同一个材质对象",
			first.rear_wheel.physics_material_override != second.rear_wheel.physics_material_override,
			"第一辆 %.3f / 第二辆 %.3f" % [
				first.rear_wheel.physics_material_override.friction, other])
	first.queue_free()
	second.queue_free()


# ---------------------------------------------------------------- 跑起来

func _reset() -> void:
	if _world != null:
		_world.queue_free()
	_world = Node2D.new()
	add_child(_world)


func _add_ground(points: PackedVector2Array) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = points
	body.add_child(shape)
	_world.add_child(body)


## 一条从 -400 一直铺到 GROUND_LEN 的平路，地面 y = 0。
func _build_flat() -> void:
	_reset()
	_add_ground(PackedVector2Array([
		Vector2(-400.0, 0.0),
		Vector2(GROUND_LEN, 0.0),
		Vector2(GROUND_LEN, 900.0),
		Vector2(-400.0, 900.0),
	]))


func _new_car(map_id: String) -> HillCar:
	var car := CAR.instantiate()
	car.position = Vector2(START_X, CAR_Y)
	_world.add_child(car)
	# 地图必须在 _ready 之后套：apply_map 要读 @onready 的轮子节点。
	# 关卡里是 game.gd 干这件事，这里手动补上。
	car.apply_map(map_id)
	car.fuel = 1.0e9
	return car


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().physics_frame


func _drive(seconds: float) -> void:
	Input.action_press("drive_forward")
	var frames := int(round(seconds / (1.0 / 60.0)))
	for i in frames:
		await get_tree().physics_frame
	Input.action_release("drive_forward")


func _section_d() -> void:
	print("=== D. 平路全油门 %.0fs ===" % RUN_TIME)
	print("  地图      里程      末速      轮面速度      打滑")
	var distances := {}
	var speeds := {}
	for id in Maps.IDS:
		_build_flat()
		_car = await _pick_car(id)
		var m: Dictionary = Maps.get_map(id)
		await _drive(RUN_TIME)
		var dist := _car.chassis.global_position.x - START_X
		var speed := _car.chassis.linear_velocity.x
		var surface := _car.rear_wheel.angular_velocity * _wheel_radius
		var slip := surface / maxf(1.0, speed)
		distances[id] = dist
		speeds[id] = speed
		print("  %-8s %7.0f   %7.0f   %9.0f   %6.2f×" % [m["zh"], dist, speed, surface, slip])

	_check("荒漠比平原慢", float(distances[Maps.DESERT]) < float(distances[Maps.PLAINS]) * 0.95,
			"荒漠 %.0f vs 平原 %.0f" % [distances[Maps.DESERT], distances[Maps.PLAINS]])
	_check("荒漠末速低于平原", float(speeds[Maps.DESERT]) < float(speeds[Maps.PLAINS]) * 0.95,
			"荒漠 %.0f vs 平原 %.0f" % [speeds[Maps.DESERT], speeds[Maps.PLAINS]])
	_check("火山和平原一样快（火山只费油，不该改动力）",
			absf(float(speeds[Maps.VOLCANO]) - float(speeds[Maps.PLAINS])) < float(speeds[Maps.PLAINS]) * 0.02,
			"火山 %.0f vs 平原 %.0f" % [speeds[Maps.VOLCANO], speeds[Maps.PLAINS]])


func _section_e() -> void:
	print("=== E. 雪地打滑 ===")
	_build_flat()
	_car = await _pick_car(Maps.PLAINS)
	await _drive(1.5)
	var plain_speed := _car.chassis.linear_velocity.x
	var plain_surface := _car.rear_wheel.angular_velocity * _wheel_radius

	_build_flat()
	_car = await _pick_car(Maps.SNOW)
	await _drive(1.5)
	var snow_speed := _car.chassis.linear_velocity.x
	var snow_surface := _car.rear_wheel.angular_velocity * _wheel_radius

	print("  平原：车速 %.0f  轮面 %.0f  打滑 %.2f×" % [plain_speed, plain_surface,
			plain_surface / maxf(1.0, plain_speed)])
	print("  雪地：车速 %.0f  轮面 %.0f  打滑 %.2f×" % [snow_speed, snow_surface,
			snow_surface / maxf(1.0, snow_speed)])

	_check("雪地起步明显更慢", snow_speed < plain_speed * 0.75,
			"雪地 %.0f vs 平原 %.0f" % [snow_speed, plain_speed])
	_check("雪地轮子明显空转",
			snow_surface / maxf(1.0, snow_speed) > plain_surface / maxf(1.0, plain_speed) * 1.5,
			"雪地 %.2f× vs 平原 %.2f×" % [snow_surface / maxf(1.0, snow_speed),
				plain_surface / maxf(1.0, plain_speed)])


func _section_f() -> void:
	print("=== F. 踩油门 %.0fs 的油耗 ===" % FUEL_TIME)
	var burns := {}
	for id in [Maps.PLAINS, Maps.VOLCANO]:
		_build_flat()
		_car = await _pick_car(id)
		var before := _car.fuel
		await _drive(FUEL_TIME)
		burns[id] = before - _car.fuel
		print("  %-8s 烧掉 %.2f" % [Maps.get_map(id)["zh"], burns[id]])
	var ratio: float = burns[Maps.VOLCANO] / maxf(0.001, burns[Maps.PLAINS])
	_approx("火山油耗倍率", ratio, 1.6, 0.02)


## 换一辆车（同一张图），并且等它落地站稳。
func _pick_car(map_id: String) -> HillCar:
	var car := _new_car(map_id)
	await _settle()
	return car
