extends Node
## 扫摩擦倍率 × 坡度：雪地到底该多滑。
##
## 上一支探针（grip_probe）量出：平地上要摩擦系数低于约 0.5 才开始打滑，而
## **这个车的抓地力需求本来就低**（起步时轮子自己的惯量才是瓶颈），所以
## 「平地空转」和「爬得上去」互相矛盾 —— 摩擦压到能空转，爬坡极限也掉到
## 十几度，地图直接没法玩。
##
## 所以选值要看的是**爬坡极限**（tan 可爬坡度 = 摩擦系数）。这里直接量：
## 每条坡度、每个摩擦倍率下，车在坡上**触地期间**的平均打滑和平均车速，
## 以及爬了多高。坡造得足够长，保证 3 秒内车不会冲出坡顶变成自由落体
## （上一版就是栽在这：坡 700 却跑 7 秒，量到的全是飞出坡顶后的滑翔）。

const CAR := preload("res://scenes/car.tscn")

const START_X := 120.0
const CAR_Y := -39.0
const RUN_UP := 500.0
const ARC_RADIUS := 260.0
const RAMP_LEN := 2600.0   ## 够长：3 秒内车爬不到头
const RUN_TIME := 3.0
const SETTLE_FRAMES := 12

const FACTORS := [1.00, 0.20, 0.15, 0.12]
const ANGLES := [20.0, 30.0, 35.0]

var _world: Node2D
var _car: HillCar
var _radius := 21.0
var _base := 2.6


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()
	var probe := CAR.instantiate()
	_radius = (probe.get_node("RearWheel/Shape") as CollisionShape2D).shape.radius
	_base = probe.get_node("RearWheel").physics_material_override.friction
	probe.free()

	print("摩擦倍率 → 摩擦系数   坡度   坡上均速   坡上打滑   爬升   触地帧")
	for factor in FACTORS:
		for angle in ANGLES:
			await _run(factor, angle)
		print("")
	get_tree().quit()


func _run(factor: float, theta_deg: float) -> void:
	if _world != null:
		_world.queue_free()
	_world = Node2D.new()
	add_child(_world)

	var theta := deg_to_rad(theta_deg)
	var slope_dir := Vector2(cos(theta), -sin(theta))
	var pts := PackedVector2Array()
	pts.append(Vector2(-400.0, 0.0))
	pts.append(Vector2(RUN_UP, 0.0))
	var steps := maxi(4, int(ceil(theta_deg / 4.0)))
	for i in range(1, steps + 1):
		var a := theta * float(i) / float(steps)
		pts.append(Vector2(RUN_UP + ARC_RADIUS * sin(a), -ARC_RADIUS * (1.0 - cos(a))))
	var ramp_start: Vector2 = pts[pts.size() - 1]
	var ramp_end := ramp_start + slope_dir * RAMP_LEN
	pts.append(ramp_end)
	pts.append(ramp_end + Vector2(0.0, 1400.0))
	pts.append(Vector2(-400.0, 1400.0))

	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = pts
	body.add_child(shape)
	_world.add_child(body)

	_car = CAR.instantiate()
	_car.position = Vector2(START_X, CAR_Y)
	_world.add_child(_car)
	_car.apply_map(Maps.PLAINS)
	for wheel: RigidBody2D in [_car.rear_wheel, _car.front_wheel]:
		var m: PhysicsMaterial = wheel.physics_material_override.duplicate()
		m.friction = _base * factor
		wheel.physics_material_override = m
	_car.fuel = 1.0e9

	for i in SETTLE_FRAMES:
		await get_tree().physics_frame

	Input.action_press("drive_forward")
	var frames := int(round(RUN_TIME * 60.0))
	var slip_sum := 0.0
	var speed_sum := 0.0
	var grounded := 0
	var y_top := 1.0e9
	for i in frames:
		await get_tree().physics_frame
		y_top = minf(y_top, _car.chassis.global_position.y)
		var wheel: RigidBody2D = _car.rear_wheel
		var on_ramp := _car.chassis.global_position.x > RUN_UP
		if on_ramp and not wheel.get_colliding_bodies().is_empty():
			var speed: float = _car.chassis.linear_velocity.dot(slope_dir)
			slip_sum += wheel.angular_velocity * _radius - speed
			speed_sum += speed
			grounded += 1
	Input.action_release("drive_forward")

	var avg_speed := speed_sum / maxf(1.0, float(grounded))
	var avg_slip := slip_sum / maxf(1.0, float(grounded))
	print("%.2f → %.2f        %4.0f°  %8.0f   %8.0f   %5.0f   %5d" % [
		factor, _base * factor, theta_deg, avg_speed, avg_slip,
		maxf(0.0, -y_top - 40.0), grounded,
	])
