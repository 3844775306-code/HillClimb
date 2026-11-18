extends Node
## 空中姿态控制（[method HillCar._apply_air_control]）的验证。
##
## 契约就是用户提的那一句：**腾空时按前进往逆时针转、按倒退往顺时针转**。
## 这句话拆开来有三件事会各自出错，所以分五组测：
##
## A. **方向** —— 前进必须让 `rotation` 变小（Godot 2D 的 y 轴朝下，负角度在
##    屏幕上是逆时针，见 [member HillCar.flip_angle] 那段）。写反了是最容易犯、
##    也最难看出来的错：车照样翻，只是翻反了。
## B. **幅度** —— 一次跳跃那么长的腾空（1.2 秒上下）至少要够翻一整圈，否则
##    这个功能等于没有；但也不能一秒转三圈，那是搅拌机，落点反而更难挑。
## C. **门** —— 只有**两个轮子都不着地**时才生效。这道闸开着的后果最恶性：
##    地面上给油车就原地打转，整个游戏没法玩。所以这里专门造一段地面，
##    全油门跑，断言它**几乎不转**。
## D. **不踩不转** —— 惯性滑行时车身不该自己转。
## E. **四辆车一样快** —— 力矩乘的是车壳**当前的转动惯量**，所以四辆车（以及
##    任何敏捷等级）的**角加速度**都是同一个 [member HillCar.air_spin]。这一组
##    把四辆车各吊起来转一秒，断言转过的角度基本一致。少了这一条，「巴士拧不动、
##    摩托一碰转三圈」这种回归没有任何别的测试会响。

const CAR := preload("res://scenes/car.tscn")

const START_X := 120.0
const CAR_Y := -39.0       ## 轮心离地 21，轮心在车原点下方 18
## 起手把车吊多高。自由落体 t = sqrt(2h/g)，g 取 980：900 px ≈ 1.355s ≈ 81 帧。
## 够跑完下面每一个 1.0 秒的测量窗口，而且四种车质量不同、下落时间**相同**
## （重力加速度和 `gravity_scale` 都与质量无关）。
const DROP := 900.0
## 生成后等几帧再开始量。[method HillCar._apply_inertia_scale] 要等物理服务器
## 把形状换算成惯量（第 2 个物理帧），等不到的话 `_auto_inertia()` 读回来是 0，
## 空中姿态会被静默跳过。
const SETTLE := 8

## 一秒腾空该转过多少度。定的是区间而不是定值：`air_spin` 是留给人手调的，
## 调了不该让测试红。区间只管住「有没有用」和「是不是过头了」两条。
const SEC_MIN_DEG := 180.0
const SEC_MAX_DEG := 540.0

## 四辆车转过角度的最大相对偏差。
##
## **不是 0，而且不该往 0 收。** 力矩乘的是车壳的惯量，但车壳转起来时，两个
## 挂在 [PinJoint2D] 上的轮子会被销子拽着一块走 —— 真正的角加速度是
## `air_spin × I壳 / (I壳 + 轮子拖的那一坨)`。那一坨约等于 `2 × (I轮 + m轮·d²)`，
## d 是轮心到车壳质心的距离，**和车壳惯量无关**，所以壳越轻的车被拖得越狠：
##
##   bus   壳 1448200 → 279.5°    racer 壳 443079 → 239.7°
##   jeep  壳  642807 → 256.4°    moto  壳  92283 → 205.4°
##
## 摩托慢 20%。想拉平得按「总惯量」而不是「壳惯量」出力，但总惯量没有现成的
## API，硬凑一个系数就是把物理换成拟合。20% 在手上分不出来，就留着。
##
## 这道断言管的是**数量级**：惯量补偿整个失效时四辆车会差十几倍（巴士拧不动、
## 摩托转三圈），那才是要响的时候。真调了 wheel_mass 之类的把轮子拖重了，
## 这里也会跟着红。
const SPREAD_TOL := 0.35

var _world: Node2D
var _car: HillCar
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1：它会直接放大物理步长
	# 车库里练满级的车会改 agility（也就是惯量），空中姿态的标定就不作数了
	SaveData.persist = false
	SaveData.reset_progress()

	await _case_flight()
	print("")
	await _case_ground()
	print("")
	await _case_all_vehicles()
	print("")
	_case_constants()

	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


func _near(label: String, got: float, want: float, tol: float) -> void:
	var ok := absf(got - want) <= tol
	if not ok:
		_failures += 1
	print("  %s %s = %.3f（期望 %.3f ±%.3f）" % [
		"OK  " if ok else "FAIL", label, got, want, tol,
	])


func _between(label: String, got: float, lo: float, hi: float) -> void:
	var ok := got >= lo and got <= hi
	if not ok:
		_failures += 1
	print("  %s %s = %.1f（期望 %.1f ~ %.1f）" % [
		"OK  " if ok else "FAIL", label, got, lo, hi,
	])


# ---------------------------------------------------------------- 场景搭建

func _new_world() -> void:
	if _world != null:
		_world.queue_free()
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


func _flat() -> void:
	_solid(PackedVector2Array([
		Vector2(-400.0, 0.0), Vector2(12000.0, 0.0),
		Vector2(12000.0, 1600.0), Vector2(-400.0, 1600.0),
	]))


func _spawn(scene: PackedScene, pos: Vector2) -> void:
	_car = scene.instantiate()
	_car.position = pos
	_world.add_child(_car)
	_car.fuel_max = 1.0e9      # 别被油耗打断：没油 throttle 会归零，空中也调不了
	_car.fuel = 1.0e9


func _release_all() -> void:
	for a in ["drive_forward", "drive_back"]:
		Input.action_release(a)


## 从场景里现读这个值，不在测试里抄一份 —— 抄了就会漂（[Vehicles] 那段注释里
## 记着这个教训）。实例化出来不进树，读完就还回去。
func air_spin_of(scene: PackedScene) -> float:
	var probe: Node = scene.instantiate()
	var value: float = probe.air_spin
	probe.free()
	return value


## 按住 action 跑 seconds 秒，返回这段时间里车身的姿态统计。
##
## `turned` 是**逐帧增量累加**的，不是首尾相减：`RigidBody2D.rotation` 折算在
## ±π 之间，一秒转 300° 的话首尾相减会被折掉一圈，符号都可能反。
## 和 [method HillCar._update_airborne] 里算 `flip_angle` 是同一个做法。
func _measure(seconds: float, action: String) -> Dictionary:
	if action != "":
		Input.action_press(action)
	var prev := _car.chassis.rotation
	var turned := 0.0
	var max_omega := 0.0
	var air_frames := 0
	var one_wheel_frames := 0
	var frames := int(round(seconds * 60.0))
	for i in frames:
		await get_tree().physics_frame
		turned += wrapf(_car.chassis.rotation - prev, -PI, PI)
		prev = _car.chassis.rotation
		max_omega = maxf(max_omega, absf(_car.chassis.angular_velocity))
		if not _car.grounded:
			air_frames += 1
		elif not (_car._touching_ground(_car.rear_wheel)
				and _car._touching_ground(_car.front_wheel)):
			# 恰好一个轮子着地（独轮）：`grounded` 仍然是 true，
			# 空中姿态必须仍然是关的 —— 独轮是「骑在一个轮子上走」。
			one_wheel_frames += 1
	if action != "":
		Input.action_release(action)
	return {
		"turned": turned,
		"max_omega": max_omega,
		"air_frames": air_frames,
		"one_wheel_frames": one_wheel_frames,
		"alive": _car.alive,
	}


# ---------------------------------------------------------------- A/B/D. 空中

func _case_flight() -> void:
	print("=== A/B/D. 空中：前进逆时针、倒退顺时针、不踩不转 ===")
	_new_world()
	_flat()
	# 吊在 900 高：整段 1.0 秒的测量窗口都在空中，够翻大半圈
	_spawn(CAR, Vector2(START_X, CAR_Y - DROP))
	for i in SETTLE:
		await get_tree().physics_frame

	_release_all()
	var idle := await _measure(1.0, "")
	print("  不踩：转过 %.1f°，最长角速度 %.2f rad/s，离地 %d 帧" % [
		rad_to_deg(idle["turned"]), idle["max_omega"], idle["air_frames"],
	])
	_check("不踩油门：全程离地（否则下面的「不转」是地面按着它不转）",
			idle["air_frames"], 60)
	_between("不踩油门的转角（绝对值）", absf(rad_to_deg(idle["turned"])), 0.0, 5.0)

	_new_world()
	_flat()
	_spawn(CAR, Vector2(START_X, CAR_Y - DROP))
	for i in SETTLE:
		await get_tree().physics_frame
	_release_all()
	var fwd := await _measure(1.0, "drive_forward")
	var fwd_deg := rad_to_deg(fwd["turned"])
	print("  前进：转过 %.1f°（负 = 逆时针 = 车头抬起来），最长角速度 %.2f rad/s" % [
		fwd_deg, fwd["max_omega"],
	])
	_check("前进全程都在空中（否则测的是地面行驶）", fwd["air_frames"], 60)
	_check("前进是逆时针（转角为负）", fwd_deg < 0.0, true)
	_between("前进 1 秒转过的角度（绝对值）",
			absf(fwd_deg), SEC_MIN_DEG, SEC_MAX_DEG)

	_new_world()
	_flat()
	_spawn(CAR, Vector2(START_X, CAR_Y - DROP))
	for i in SETTLE:
		await get_tree().physics_frame
	_release_all()
	var back := await _measure(1.0, "drive_back")
	var back_deg := rad_to_deg(back["turned"])
	print("  倒退：转过 %.1f°（正 = 顺时针 = 车头扎下去），最长角速度 %.2f rad/s" % [
		back_deg, back["max_omega"],
	])
	_check("倒退全程都在空中", back["air_frames"], 60)
	_check("倒退是顺时针（转角为正）", back_deg > 0.0, true)
	_between("倒退 1 秒转过的角度（绝对值）",
			absf(back_deg), SEC_MIN_DEG, SEC_MAX_DEG)
	_near("倒退和前进一样快（只是反号）",
			absf(back_deg), absf(fwd_deg), 20.0)
	# 顺手把标定值打出来：改 air_spin 之后跑这个文件，一眼看得出快了还是慢了
	print("  标定：air_spin = %.1f 时，1.00s 转过 %.0f°" % [air_spin_of(CAR), absf(fwd_deg)])


# ---------------------------------------------------------------- C. 地面

func _case_ground() -> void:
	print("=== C. 地面：全油门也不能被空中姿态拧转 ===")
	_new_world()
	_flat()
	_spawn(CAR, Vector2(START_X, CAR_Y))
	for i in SETTLE:
		await get_tree().physics_frame
	_release_all()
	var st := await _measure(1.5, "drive_forward")
	var deg := rad_to_deg(st["turned"])
	print("  地面全油门 1.50s：转过 %.1f°，最长角速度 %.2f rad/s，"
			% [deg, st["max_omega"]]
			+ "离地 %d 帧，独轮 %d 帧，最远 x=%.0f"
			% [st["air_frames"], st["one_wheel_frames"],
			_car.chassis.global_position.x])
	_check("这 1.5 秒里车没飞起来（否则测的不是地面）", st["air_frames"], 0)
	_check("车还在（否则上面那条是废话）", st["alive"], true)
	# 门槛给得很宽：地面上车身本来就会因为轮子扭矩前后俯仰。真漏了空中姿态的话
	# 1.5 秒能转过 400° 以上，和这个数差着两个数量级。
	_between("地面 1.5 秒的转角（绝对值）", absf(deg), 0.0, 60.0)
	_between("地面 1.5 秒的最长角速度", st["max_omega"], 0.0, 3.0)
	# 独轮也算 grounded，所以这一段里一个「空中姿态」的力矩都不该有。
	if st["one_wheel_frames"] > 0:
		print("  （其中 %d 帧是独轮：`grounded` 仍为 true，空中姿态保持关闭）"
				% st["one_wheel_frames"])


# ---------------------------------------------------------------- E. 四辆车

func _case_all_vehicles() -> void:
	print("=== E. 四辆车：空中转得一样快 ===")
	var table := {}
	for id in Vehicles.available():
		_new_world()
		_flat()
		_spawn(Vehicles.scene(id), Vector2(START_X, CAR_Y - DROP))
		for i in SETTLE:
			await get_tree().physics_frame
		_release_all()
		var inertia := _car._auto_inertia(_car.chassis)
		var st := await _measure(1.0, "drive_forward")
		var deg := rad_to_deg(st["turned"])
		table[id] = deg
		print("  %-6s 车壳惯量 %9.0f  转过 %7.1f°  最长角速度 %.2f rad/s  离地 %d 帧" % [
			id, inertia, deg, st["max_omega"], st["air_frames"],
		])
		_check("%s 全程都在空中" % id, st["air_frames"], 60)
		_check("%s 也是逆时针" % id, deg < 0.0, true)

	var lo := INF
	var hi := -INF
	for id in table:
		lo = minf(lo, absf(table[id]))
		hi = maxf(hi, absf(table[id]))
	_near("四辆车里最快的和最慢的之比（相对偏差）",
			(hi - lo) / hi, 0.0, SPREAD_TOL)
	# 惯量补偿整个失效时会出现什么：巴士拧不动（几十度）、摩托转三圈（上千度）。
	# 上面那条比值的断言在「四个数都接近 0」时也会过，所以再钉一条绝对量级。
	for id in table:
		_between("%s 的量级（没被惯量差拉开）" % id,
				absf(table[id]), SEC_MIN_DEG, SEC_MAX_DEG)


# ---------------------------------------------------------------- 常量

func _case_constants() -> void:
	print("=== 常量 ===")
	# **刻意不写进各车的 .tscn。** 质量、底盘形状、马达、油箱都在 .tscn 里，
	# 因为那是「这辆车和别的车不一样」的地方；air_spin 正好相反 —— 它是
	# 「四辆车必须一样」的那一项（E 组就是钉它的）。写进场景就等于开了四个
	# 可以互相漂走的旋钮，而这四个数一旦漂开，车就有一半翻不了身。
	var ids := Vehicles.available()
	var spins := {}
	for id in ids:
		spins[id] = air_spin_of(Vehicles.scene(id))
	print("  四辆车的 air_spin：%s" % [spins])
	_check("air_spin 是正的（符号由代码里的负号管，常量不背这个锅）",
			air_spin_of(CAR) > 0.0, true)
	for id in ids:
		_near("%s 的 air_spin = 默认车的" % id, spins[id], air_spin_of(CAR), 0.0)
