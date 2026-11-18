extends Node
## 独轮车的陀螺仪自平衡（[member HillCar.balance_torque]）：跑真物理，量四件事。
##
## 独轮车只有一个轮子，车壳铰在轮心上，**重心必定在接地点上方** —— 纯物理下它开口
## 就倒。整个「这辆车能骑」的假象全靠 [method HillCar._apply_balance] 那一个力矩撑着，
## 所以它是这次加车里最需要盯住的一处：
##
##   1. **没人管也站得住，满油门也站得住**。前半句是「独轮车能骑」的本体；后半句
##      才是它真正难的地方 —— 给油那一下马达的反作用力是个**实打实**的抬头力矩，
##      而反馈回路得先看到倾角才出力。见 [method _test_assist_holds_the_launch]。
##   2. **关掉陀螺仪就必倒**。对照组 —— 没有它，第 1 条量到的到底是不是它撑起来的？
##      少了这一条，一个「其实被关节/地形卡住、本来就不会倒」的实现照样全绿。
##   3. **抗扰动上限**：给车壳一个初始角速度，量出还能救回来的最大值。
##      这才是 [member HillCar.balance_torque] 真正的调参对象（见它自己的注释：
##      「这个数是『能救回多大倾角』的旋钮，不是『会不会倒』的开关」）。
##   4. **永远不发翘头奖励**：独轮车只有一个轮子，「单轮着地」对它恒成立，老判据
##      会给它发一条**永远不会停**的奖。
##
## 顺带把 [method HillCar.bodies] 和 `rear_wheel` / `front_wheel` 那对别名也钉一下：
## 独轮车上它们三个指向同一个轮子，而「同一个刚体在遍历里出现两次」这种事不会报错，
## 只会让质量、碎屑、惯量静默翻倍 —— 而这一条只有在车**进了树**之后才量得到
## （`@onready` 要 `_ready` 才求值），所以放在这里而不是 tests/vehicles。
##
## ## 为什么扰动写成「给车壳一个初始角速度」，而不是「把车壳拧成 θ 度」
##
## [PinJoint2D] 的锚点在车进树那一刻就换算成**车体局部坐标**写进物理服务器了。
## 之后只拧 `chassis.rotation`，锚点会跟着车壳一起转，而轮子在另一头不肯动 ——
## 求解器于是拿很大的力去把两者拽回一起。量到的就成了「求解器拉锯到什么程度」，
## 和陀螺仪没关系。角速度是刚体的合法状态，一个字节的锚点都不碰，量到的才是
## 「这个扰动它顶不顶得住」。

const CAR := preload("res://scenes/vehicles/mono.tscn")
## 对照组要用同一辆车的车架几何，但不能带陀螺仪 —— 直接改 `balance_torque` 即可，
## 别的什么都不动，两组之间的差别只有这一个数。
const WHEEL_REST := 54.0     ## 轮半径 28 + 铰链在车体 (0,26)：车壳静止时 y ≈ −54
const SETTLE := 24           ## 落地并停稳的帧数
const HOLD := 180            ## 3 秒
## 「还算直立」的判据。12° 是给人看的：陀螺仪回正到 1° 以内是秒级的事，留这么宽是
## 为了不因为落地那一下的余摆而抖动。
const UPRIGHT := 12.0

var _failures := 0
var _world: Node2D
var _car: HillCar
var _wheelie_hits := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false
	SaveData.reset_progress()
	_build_world()
	_test_alias()
	print("")
	await _test_stands()
	print("")
	await _test_assist_holds_the_launch()
	print("")
	await _test_gyro_is_what_holds_it()
	print("")
	await _test_kick_table()
	print("")
	await _test_no_wheelie()
	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])


## 一块平地。地面进 `"ground"` 组，[method HillCar._update_airborne] 就是按这个组
## 判触地的 —— 少了它车永远算腾空，而腾空时陀螺仪**不出力**，整个测试会静默地
## 退化成「量了一辆在天上飘的车」。所以下面每个场景都断言一次 `grounded`。
func _build_world() -> void:
	_world = Node2D.new()
	add_child(_world)
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20000.0, 1200.0)
	shape.shape = rect
	# 上面那块的**上沿**落在 y = 0。
	shape.position = Vector2(0.0, 600.0)
	body.add_child(shape)
	_world.add_child(body)


## 摆一辆独轮车出来，落在平地上。上一辆先收掉。
##
## `assist` 传负数表示「用场景里的值」（独轮车是 1.0），传 0.0 才是**关掉**前馈。
func _spawn(torque: float, assist := -1.0) -> HillCar:
	if _car != null:
		_car.queue_free()
		_car = null
		await get_tree().physics_frame
	var car: HillCar = CAR.instantiate()
	# **在进树之前改** —— `balance_torque` 是 `@export`，运行期改也生效，但摆在
	# 进树之前就没有「第一帧用的是旧值」那点含糊。
	car.balance_torque = torque
	if assist >= 0.0:
		car.balance_assist = assist
	car.position = Vector2(0.0, -WHEEL_REST)
	car.fuel = 1.0e9
	_world.add_child(car)
	car.apply_map(Maps.PLAINS)
	_car = car
	for i in SETTLE:
		await get_tree().physics_frame
	return car


## 按住前进 `frames` 帧，返回这一段的**最大**倾角（度）。
func _hold(frames: int) -> float:
	var worst := 0.0
	Input.action_press("drive_forward")
	for i in frames:
		await get_tree().physics_frame
		worst = maxf(worst, absf(_deg(_car.chassis.rotation)))
	Input.action_release("drive_forward")
	return worst


## 满油门 [constant HOLD] 帧，回来报倾角和跑了多远。
func _launch(assist: float) -> Dictionary:
	var car := await _spawn(35.0, assist)
	var start_x := car.chassis.global_position.x
	var worst := await _hold(HOLD)
	return {
		"worst": worst,
		"lean": absf(_deg(car.chassis.rotation)),
		"alive": car.alive,
		"ran": car.chassis.global_position.x - start_x,
	}


func _deg(rad: float) -> float:
	return rad_to_deg(wrapf(rad, -PI, PI))


# ---------------------------------------------------------------- 别名与刚体表

## 独轮车上 `rear_wheel` / `front_wheel` 是同一个轮子的两个别名。
##
## 留着别名的原因是二十来个测试和 effects / trees / hazards / dashboard 都在拿这两
## 个名字「取一个轮子看看」，一次改二十个文件不划算；但**遍历**必须走 [member
## HillCar.wheels] / [method HillCar.bodies]，否则那个轮子会被算两遍 —— 质量翻倍、
## 碎屑翻倍、惯量翻倍，而且都不会报错。
func _test_alias() -> void:
	print("=== 独轮车的轮子表 ===")
	var car: HillCar = CAR.instantiate()
	# 这一节不用跑物理，但 `@onready` 得 `_ready` 才求值，所以还是进树。
	_world.add_child(car)
	_check("wheels 只有一个轮子", car.wheels.size() == 1,
			"读到 %d 个" % car.wheels.size())
	_check("rear_wheel / front_wheel 都指向它（别名）",
			car.rear_wheel == car.wheels[0] and car.front_wheel == car.wheels[0],
			"rear=%s front=%s wheels[0]=%s" % [
				str(car.rear_wheel), str(car.front_wheel), str(car.wheels[0])])
	var seen := {}
	var dup := PackedStringArray()
	for body in car.bodies():
		if seen.has(body):
			dup.append(str(body))
		seen[body] = true
	_check("bodies() 里每个刚体只出现一次（独轮车共 2 个）",
			car.bodies().size() == 2 and dup.is_empty(),
			"bodies() = %d 个，重复：%s" % [
				car.bodies().size(), "无" if dup.is_empty() else "，".join(dup)])
	_world.remove_child(car)
	car.free()


# ---------------------------------------------------------------- 站得住

## 站得住，而且**开着也站得住**。
##
## 只站着不动是测不出东西的：起手是完美对称的直立姿态，那是个不稳定的平衡点，
## 没有扰动时浮点噪声要好几秒才把它推倒，谁都「站得住」。
##
## 真正的扰动来自**给油**。马达的力矩只加在轮子上，而轮子和车壳是销子铰着的 ——
## 轮子一使劲，反作用力矩原样传到车壳上往后掀。这正是玩家开独轮车时唯一会遇到的
## 扰动，也正是陀螺仪要顶的那一下。所以这一段是「站着 1 秒 → 给油 2 秒」。
func _test_stands() -> void:
	print("=== 站着也稳，开着也稳 ===")
	var car := await _spawn(35.0)
	_check("落地了（陀螺仪只在着地时出力，没落地这条测的就不是它）", car.grounded,
			"settle %d 帧后 grounded = %s" % [SETTLE, str(car.grounded)])
	var idle := 60
	var worst_idle := 0.0
	for i in idle:
		await get_tree().physics_frame
		worst_idle = maxf(worst_idle, absf(_deg(car.chassis.rotation)))
	var idle_lean := absf(_deg(car.chassis.rotation))
	# `alive` 要**当场**记下来。等到给油之后再读，量到的就是给油那一段的结果，
	# 「原地站着没摔」这一条会被后半段带崩 —— 两件事挤在一个布尔里。
	var idle_alive := car.alive
	var start_x := car.chassis.global_position.x

	Input.action_press("drive_forward")
	var worst_drive := 0.0
	for i in HOLD - idle:
		await get_tree().physics_frame
		worst_drive = maxf(worst_drive, absf(_deg(car.chassis.rotation)))
	Input.action_release("drive_forward")
	var ran := car.chassis.global_position.x - start_x

	_check("原地 1 秒仍然直立", idle_alive and idle_lean <= UPRIGHT,
			"倾角 %.1f°（判据 %.0f°），全程最大 %.1f°" % [
				idle_lean, UPRIGHT, worst_idle])
	# 这一段是这条线的重点：给油那一下马达的反作用力是**实打实**的抬头力矩，
	# 而反馈回路得先看到倾角才出力。断了 `balance_assist` 这里必红。
	_check("满油门 2 秒仍然直立", car.alive and absf(_deg(car.chassis.rotation)) <= UPRIGHT,
			"倾角 %.1f°（判据 %.0f°），给油全程最大 %.1f°，活着：%s" % [
				_deg(car.chassis.rotation), UPRIGHT, worst_drive, str(car.alive)])
	# 顺带证明它真的在开，不是被卡住了 —— 加在轮子上的反作用力矩正是从
	# 「轮子真的转起来了」来的，一辆原地不动的车根本不会给车壳那一下。
	_check("确实开起来了", ran > 200.0, "2 秒跑了 %.0f px" % ran)


# ---------------------------------------------------------------- 前馈对照组

## [member HillCar.balance_assist] 是**承重**的，不是锦上添花。
##
## 同一辆车、同一块地、同一脚满油门，**只把前馈关掉**：陀螺仪的反馈一点没少，
## 少的只是那个「预判」。少了它就翻 —— 这条要是不红，说明给油那一下的抬头力矩
## 另有出处，那把前馈整段删掉也不会有人发现。
##
## 尺寸也要报出来：前馈**补过头**同样是翻，只是方向相反（往前扎）。所以这里
## 同时钉住两件事 —— 关掉会翻、开着不翻。
func _test_assist_holds_the_launch() -> void:
	print("=== 关掉前馈就翻（对照组）===")
	var on := await _launch(1.0)
	var off := await _launch(0.0)
	_check("前馈开着：满油门 2 秒站得住", bool(on["alive"]) and float(on["worst"]) <= UPRIGHT,
			"最大倾角 %.1f°（判据 %.0f°），2 秒跑了 %.0f px" % [
				on["worst"], UPRIGHT, on["ran"]])
	_check("前馈关掉：同一脚油门就翻", not (bool(off["alive"]) and float(off["worst"]) <= UPRIGHT),
			"最大倾角 %.1f°，活着：%s" % [off["worst"], str(off["alive"])])


# ---------------------------------------------------------------- 对照组

## 同一辆车、同一块地、同一个扰动，**只把 `balance_torque` 从 35 改成 0**。
##
## 不这么比的话，「独轮车站得住」这件事有太多别的解释：铰链的软度、轮子摩擦、
## 车壳底面蹭地……全都能让一个不该站住的东西站住。两组之间只差一个数，量到的差别
## 就只能来自那一个数。
func _test_gyro_is_what_holds_it() -> void:
	print("=== 关掉陀螺仪就必倒（对照组）===")
	var kick := 2.0
	var with_gyro := await _kicked(35.0, kick)
	var without := await _kicked(0.0, kick)
	_check("陀螺仪开着时能救回来", with_gyro["ok"],
			"踢 %.1f rad/s，3 秒后倾角 %.1f°" % [kick, with_gyro["deg"]])
	_check("陀螺仪关掉时救不回来", not without["ok"],
			"踢 %.1f rad/s，3 秒后倾角 %.1f°（要么倒到判据外、要么摔死了）" % [
				kick, without["deg"]])


## 给车壳一个初始角速度，跑 3 秒看回不回得来。
func _kicked(torque: float, kick: float) -> Dictionary:
	var car := await _spawn(torque)
	if not car.grounded:
		return {"ok": false, "deg": _deg(car.chassis.rotation), "air": true}
	car.chassis.angular_velocity = kick
	for i in HOLD:
		await get_tree().physics_frame
	return {"ok": car.alive and absf(_deg(car.chassis.rotation)) <= UPRIGHT,
			"deg": _deg(car.chassis.rotation), "air": false}


# ---------------------------------------------------------------- 极限

## 扫一遍扰动大小，把「还能救回来」的上限打出来。
##
## 这一节**不断言具体数字**，只断言上下限的形状：太小的扰动必须救得回来（否则
## 陀螺仪是坏的），足够大的扰动必须救不回来（否则那个力矩没有上限，等于「永远不
## 倒」—— 而 [method HillCar._apply_balance] 里特意封了顶就是为了避免这个）。
## 中间那个临界值随 `balance_torque` 变，是给人调参看的，钉死它会让每次调手感
## 都得改测试。
func _test_kick_table() -> void:
	print("=== 抗扰动上限（balance_torque = 35，mono.tscn 里的值）===")
	print("  初始角速度   3 秒后倾角   救回来了吗")
	var recovered: Array[float] = []
	var lost: Array[float] = []
	var k := 0.5
	while k <= 8.001:
		var r := await _kicked(35.0, k)
		var ok: bool = r["ok"]
		if ok:
			recovered.append(k)
		else:
			lost.append(k)
		print("  %6.1f rad/s  %8.1f°    %s%s" % [
			k, r["deg"], "是" if ok else "否", "（腾空了）" if r["air"] else ""])
		k += 0.5
	var limit := recovered[recovered.size() - 1] if not recovered.is_empty() else 0.0
	print("  → 还能救回来的最大扰动 %.1f rad/s" % limit)
	_check("小扰动救得回来", not recovered.is_empty() and recovered[0] <= 1.0,
			"能救回来的一共 %d 档，最小 %.1f rad/s" % [
				recovered.size(), recovered[0] if not recovered.is_empty() else -1.0])
	_check("大扰动一定救不回来（力矩有上限，不是永远不倒）", not lost.is_empty(),
			"救不回来的最小 %.1f rad/s" % (lost[0] if not lost.is_empty() else -1.0))


# ---------------------------------------------------------------- 翘头奖励

## 独轮车永远不发翘头奖励。
##
## `_update_wheelie` 的老判据是「一个着地一个不着地」，而独轮车只有一个轮子，
## 「单轮着地」对它恒成立：正常行驶（那唯一一个轮子转得飞快）和腾空都会发奖，
## 于是它会**每 [constant HillCar.WHEELIE_INTERVAL] 秒白拿一次钱**，永远不停。
func _test_no_wheelie() -> void:
	print("=== 翘头奖励 ===")
	var car := await _spawn(35.0)
	_wheelie_hits = 0
	car.wheelie_bonus.connect(func(_coins: int, _rear: bool) -> void: _wheelie_hits += 1)
	Input.action_press("drive_forward")
	# 光站着还不够：「正常行驶」才是老判据最容易误发的那种状态（轮子转着、
	# 车身立着），所以这一段要**真的开起来**。
	var spin := 0.0
	for i in HOLD:
		await get_tree().physics_frame
		spin = maxf(spin, absf(car.wheels[0].angular_velocity))
	Input.action_release("drive_forward")
	_check("开了 3 秒一次翘头奖励都没发", _wheelie_hits == 0,
			"发了 %d 次（车轮最高转速 %.0f rad/s）" % [_wheelie_hits, spin])
