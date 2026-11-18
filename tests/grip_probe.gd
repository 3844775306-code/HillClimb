extends Node
## 扫一遍轮子摩擦倍率，看多低才真的开始打滑。
##
## 为什么需要这个：**摩擦系数变小 ≠ 会打滑**。能不能打滑取决于「马达要多少抓地力」
## 和「地面最多给多少」的比。车静止时单轮力矩被 max_torque 卡在 2000000，除以轮半径
## 21 就是要 95238 的抓地力，而单轮正压力只有整车自重的约一半（85260）—— 也就是说
## 需要摩擦系数 1.12 才勉强不打滑。但车起步时轮子自己的惯量才是瓶颈（inertia_scale
## 把轮子惯量放大了 2 倍，轮子转起来慢），实际要的抓地力只有 44109 左右，
## 对应摩擦系数约 0.52。**所以 0.78 的雪地根本不打滑，而 0.5 以下才开始。**
##
## 这个数只能实测，算不准：摩擦的合成规则（PhysicsMaterial.rough）、
## 求解器的迭代次数都会影响结果。

const CAR := preload("res://scenes/car.tscn")

const START_X := 120.0
const CAR_Y := -39.0
const RUN_TIME := 1.5
const SETTLE_FRAMES := 12
const FACTORS := [1.0, 0.6, 0.45, 0.30, 0.20, 0.12, 0.06]

var _world: Node2D
var _car: HillCar
var _radius := 21.0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()
	# 没进树就没有 @onready，只能自己 get_node
	var probe := CAR.instantiate()
	_radius = (probe.get_node("RearWheel/Shape") as CollisionShape2D).shape.radius
	var base_friction: float = probe.get_node("RearWheel").physics_material_override.friction
	probe.free()

	print("原始摩擦 %.3f   跑 %.1fs   正压力/轮 ≈ %.0f" % [
		base_friction, RUN_TIME, (130.0 + 22.0 + 22.0) * 980.0 * 0.5,
	])
	print("")
	print("倍率     摩擦   1.5s车速   轮面速度   打滑     1.5s里程")
	for factor in FACTORS:
		await _run(factor)
	get_tree().quit()


func _run(factor: float) -> void:
	if _world != null:
		_world.queue_free()
	_world = Node2D.new()
	add_child(_world)

	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([
		Vector2(-400.0, 0.0), Vector2(6000.0, 0.0),
		Vector2(6000.0, 900.0), Vector2(-400.0, 900.0),
	])
	body.add_child(shape)
	_world.add_child(body)

	_car = CAR.instantiate()
	_car.position = Vector2(START_X, CAR_Y)
	_world.add_child(_car)
	_car.apply_map(Maps.PLAINS)
	# 直接改倍率而不是改地图 —— 这里要扫的是连续量，不是四张图
	var mat: PhysicsMaterial = _car.rear_wheel.physics_material_override.duplicate()
	var base := mat.friction
	for wheel: RigidBody2D in [_car.rear_wheel, _car.front_wheel]:
		var m: PhysicsMaterial = wheel.physics_material_override.duplicate()
		m.friction = base * factor
		wheel.physics_material_override = m
	_car.fuel = 1.0e9

	for i in SETTLE_FRAMES:
		await get_tree().physics_frame

	Input.action_press("drive_forward")
	var frames := int(round(RUN_TIME / (1.0 / 60.0)))
	for i in frames:
		await get_tree().physics_frame
	Input.action_release("drive_forward")

	var speed := _car.chassis.linear_velocity.x
	var surface := _car.rear_wheel.angular_velocity * _radius
	print("%.2f   %5.2f   %8.0f   %9.0f   %5.2f×   %7.0f" % [
		factor, base * factor, speed, surface, surface / maxf(1.0, speed),
		_car.chassis.global_position.x - START_X,
	])
