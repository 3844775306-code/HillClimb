extends Node
## 爬坡能力测试。
##
## 造一段带圆弧过渡的固定坡度直坡（圆弧是为了贴近真实地形的平滑起伏，
## 直角拐点会让轮子撞在棱上，测出来的不是爬坡能力），让车从平路加速冲上去，
## 记录马达转速、打滑、以及**各刚体的触地情况** —— 最后一项用来区分
## 「牵引力不够」和「翘头后车壳搁浅」这两种完全不同的失败原因。
##
## 最后扫一遍角度，得出「能完整爬上的最陡坡度」。

const CAR_SCENE := preload("res://scenes/car.tscn")

const RUN_UP := 700.0      ## 平路助跑段长度
const RAMP_LEN := 900.0    ## 坡面长度（沿坡面）
const ARC_RADIUS := 260.0  ## 平路到坡面的圆弧过渡半径
const START_X := 120.0
const CAR_Y := -39.0       ## 轮心离地 21，轮心在车原点下方 18

const DIAG_ANGLE := 40.0
const DIAG_TIME := 5.0
const SWEEP_ANGLES := [30.0, 35.0, 40.0, 45.0, 50.0, 55.0]
const SWEEP_TIME := 6.0

var _world: Node2D
var _car: HillCar
var _slope := 0.0
var _ramp_end := Vector2.ZERO


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1：time_scale 会直接放大物理步长，加速=换了一套物理
	# 车库里的升级会乘到车的参数上（见 Upgrades.apply），玩家练满的车会污染这里的
	# 爬坡数据 —— 这里要的是原厂车。Lv 全 0 时升级倍率恒为 1.0，等于没装升级系统。
	SaveData.persist = false
	SaveData.reset_progress()
	await _flat_launch()
	print("")
	await _diagnose(DIAG_ANGLE)
	print("")
	await _sweep()
	Engine.time_scale = 1.0
	get_tree().quit()


## 平路全油门起步。前轮离地 = 翘头，说明推力已经吃满抓地上限，
## 再往上调扭矩就要开始翻车了 —— 这是「还能加多少推力」的余量表。
func _flat_launch() -> void:
	print("=== 平路起步（看翘头余量）===")
	_build(0.0)
	Input.action_press("drive_forward")
	var t := 0.0
	var max_pitch := 0.0
	var air_time := 0.0
	while t < 3.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		var pitch := rad_to_deg(_car.chassis.rotation)
		max_pitch = minf(max_pitch, pitch)   # 屏幕坐标下抬头 = 负角
		if _car.front_wheel.get_colliding_bodies().is_empty():
			air_time += 0.25
		print("t=%4.2f  时速 %4.0f  俯仰 %+5.1f  前轮触地 %d" % [
			t, _car.chassis.linear_velocity.length(), pitch,
			_car.front_wheel.get_colliding_bodies().size(),
		])
	Input.action_release("drive_forward")
	print("  最大抬头 %.1f°   前轮离地时间 %.2fs / 3.00s" % [-max_pitch, air_time])


## 平路 → 圆弧 → 等角坡面。圆弧与平路、坡面都相切，所以没有棱角。
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
	_ramp_end = start + dir * RAMP_LEN
	pts.append(_ramp_end)
	pts.append(_ramp_end + Vector2(0.0, 700.0))
	pts.append(Vector2(-400.0, 700.0))
	return pts


func _build(angle_deg: float) -> void:
	if _world != null:
		_world.queue_free()
		_world = null
	_slope = deg_to_rad(angle_deg)

	_world = Node2D.new()
	add_child(_world)

	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = _ramp_points(_slope)
	body.add_child(shape)
	_world.add_child(body)

	_car = CAR_SCENE.instantiate()
	_car.fuel_max = 1.0e9          # 测爬坡，别被油耗打断
	_car.position = Vector2(START_X, CAR_Y)
	_world.add_child(_car)
	_car.fuel = 1.0e9
	for part in [_car.chassis, _car.rear_wheel, _car.front_wheel]:
		part.contact_monitor = true
		part.max_contacts_reported = 8


## 沿坡面的单位向量（屏幕坐标 y 向下，所以上坡是 -y）。
func _slope_dir() -> Vector2:
	return Vector2(cos(_slope), -sin(_slope))


func _line(t: float, angle: float) -> String:
	var chassis: RigidBody2D = _car.chassis
	var wheel: RigidBody2D = _car.rear_wheel
	var omega: float = wheel.angular_velocity
	# 打滑：轮子表面线速度超出实际前进速度的部分
	var slip := omega * 21.0 - chassis.linear_velocity.dot(_slope_dir())
	# 车壳自己有没有蹭到地 —— 有就是翘头搁浅，不是牵引力问题
	var belly := chassis.get_colliding_bodies().size()
	return "t=%4.1f  %5.0f°  轮速 %5.1f/%4.0f  时速 %4.0f  打滑 %+5.0f  触地 后%d前%d壳%d  俯仰 %+5.1f" % [
		t, angle, omega, _car.max_wheel_speed, chassis.linear_velocity.length(), slip,
		wheel.get_colliding_bodies().size(),
		_car.front_wheel.get_colliding_bodies().size(),
		belly,
		rad_to_deg(chassis.rotation),
	]


func _diagnose(angle: float) -> void:
	print("=== 诊断：%.0f° 坡（圆弧过渡）===" % angle)
	_build(angle)
	Input.action_press("drive_forward")
	var t := 0.0
	var next_log := 0.0
	while t < DIAG_TIME:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		if t < next_log or not _car.alive:
			continue
		next_log = t + 0.5
		print(_line(t, angle))
	Input.action_release("drive_forward")
	if not _car.alive:
		print("  （中途翻车）")


func _sweep() -> void:
	print("=== 极限坡度扫描 ===")
	var best := 0.0
	for angle in SWEEP_ANGLES:
		_build(angle)
		Input.action_press("drive_forward")
		var t := 0.0
		while t < SWEEP_TIME and _car.alive:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		Input.action_release("drive_forward")
		var span := _ramp_end.x - RUN_UP
		var climbed := clampf((_car.max_distance - RUN_UP) / span, 0.0, 1.0)
		var note := ""
		if not _car.alive:
			note = "（翻车）"
		elif climbed >= 1.0:
			note = "（登顶）"
			best = angle
		print("%5.0f°  爬到 %3.0f%%  末速 %3.0f  %s" % [
			angle, climbed * 100.0, _car.chassis.linear_velocity.length(), note,
		])
	print("=> 能完整爬上的最陡坡度：%.0f°" % best)
