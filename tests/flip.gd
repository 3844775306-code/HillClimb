extends Node
## 空翻奖励（空中转满一圈 300 块）的验证。
##
## 空翻最容易写歪的地方**不是「转满了没发钱」，是「没转满也发钱」**：
##
##   * `RigidBody2D.rotation` 是**折算到 ±π** 的。车头从 +180° 转到 −180°，
##     这个数会一步跳 −2π —— 不折算（`wrapf`）就会被当成「倒退了一整圈」白送 50。
##   * 落地不清零的话，空中转半圈、落地再蹭半圈，也能凑出一整圈来骗钱。
##   * 方向：Godot 2D 的 y 轴朝下，**正角度在屏幕上是顺时针** —— 车头往下扎是
##     前空翻。前后写反了玩家看不出来，只能靠断言钉住。
##
## 这一套全部靠**真的物理**：车先在地上坐稳，再整体抬到空中、给一个角速度丢下去。
## 不去断言「角速度 × 时间 = 转过的角度」—— 车壳和两个轮子是关节连着的，转起来
## 会把轮子甩着走，转速被拖慢，那个乘积根本不成立。断言用的是**测试自己一帧一帧
## 量出来的转角**，按被测代码同一条规则折算成「应收几次」（见 [method _fly]）。

const CAR := preload("res://scenes/car.tscn")
const MAIN := preload("res://scenes/main.tscn")

const START_X := 120.0
const CAR_Y := -39.0       ## 轮心离地 21，轮心在车原点下方 18
## 悬空高度。自由落体约 1.56s（重力 980），够转一两圈。
const DROP := 1200.0
const SETTLE := 12         ## 生成后等车坐稳的物理帧数

var _world: Node2D
var _car: HillCar
var _flips := []           ## 每次空翻记 [back, 金币数]
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0   # 必须为 1：它会直接放大物理步长
	# 车库里练满级的车会改马达和转动惯量，转起来的手感不是原厂车的
	SaveData.persist = false
	SaveData.reset_progress()

	await _case_ground()
	print("")
	await _case_one(false)
	print("")
	await _case_one(true)
	print("")
	await _case_short()
	print("")
	await _case_double()
	print("")
	await _case_spawn_drop()

	print("")
	await _case_game_wiring()

	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _check(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failures += 1
	print("  %s %s = %s（期望 %s）" % ["OK  " if ok else "FAIL", label, got, want])


# ---------------------------------------------------------------- 场景搭建

func _new_world() -> void:
	if _world != null:
		# **先断信号再拆世界。** `queue_free()` 是延迟到帧末的，这一帧里旧车还活着、
		# 还在飞 —— 上一条用例最后那个角速度能转出圈来，那笔钱会记到下一条用例头上。
		if _car != null and _car.flip_bonus.is_connected(_on_flip):
			_car.flip_bonus.disconnect(_on_flip)
		_world.queue_free()
	_car = null
	_flips.clear()
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
		Vector2(12000.0, 800.0), Vector2(-400.0, 800.0),
	]))


func _spawn(pos: Vector2) -> void:
	_car = CAR.instantiate()
	_car.position = pos
	_world.add_child(_car)
	_car.fuel_max = 1.0e9      # 别被油耗打断
	_car.fuel = 1.0e9
	_car.flip_bonus.connect(_on_flip)


func _on_flip(coins: int, back: bool) -> void:
	_flips.append([back, coins])


## 摆好一辆悬在空中的车。
##
## `land_first` 为真：先在地上坐稳（把 [member HillCar._has_landed] 立起来）再整体
## 抬上去。**这一步不能省** —— 出生悬空那一段是不给钱的（和腾空奖励同一个闸），
## 车不先在地上待过，后面转多少圈都不会发奖。第一版就是直接悬空丢下去转，
## 转了两圈一个子儿都没有，还以为是发奖逻辑写错了。
##
## `land_first` 为假：直接悬空出生，那正是「落地之前不给钱」要测的情形。
func _setup_air(land_first: bool, drop: float) -> void:
	_new_world()
	_flat()
	_spawn(Vector2(START_X, CAR_Y if land_first else CAR_Y - drop))
	if not land_first:
		return
	for i in SETTLE:
		await get_tree().physics_frame
	# 抬的是 **Car 这个父节点**，三个刚体一起动：只抬车壳的话，两个轮子会被关节
	# 拽着留在原地，抬上去的就不是一辆车了。
	_car.position = Vector2(START_X, CAR_Y - drop)


## 飞 `seconds` 秒，每帧记一次账。`spin` 是初始角速度；`step` 不为 0 时改成
## **每帧直接给车身加 `step` 弧度**，一直加到被测代码的累计转角过了 `step_until`
## 才停手（见 [method _case_short]：这条要的是「过了半圈但不到一圈」，
## 而每帧真能攒下多少是物理说了算，写死帧数是碰运气）。
##
## 返回 `{air, turns, expected, flips, wrapped, flip}`：
##   `air`      最长连续腾空时长
##   `turns`    **最长的一趟**腾空里转过的圈数（用来断「够不够一圈」，不漏空跑）
##   `expected` 按被测代码那条规则算出来的**应收次数**：每一趟腾空掉几个整圈就发几次，
##              落地把这一趟的零头作废（`_has_landed` 之前整段不算）
##   `flips`    实际发出去的次数
##   `wrapped`  有没有哪一帧车身角度**一步跳了超过 π** —— `rotation` 是折算到 ±π 的，
##              车头越过 ±180° 时这个数会一步掉 2π，那正是 `wrapf` 要挡的东西
##   `flip`     最后一个腾空帧上被测代码累计的转角（弧度，带正负），用来直接看
##              `wrapf` 有没有把方向搞反（漏了折算的话这里会变成负数）
##
## 两边**各算各的**：`expected` 是测试按机制推的，`flips` 是代码真发的，
## 对不上就说明代码的规则和文档写的不是一回事。
func _fly(seconds: float, spin: float, step := 0.0, step_until := 0.0) -> Dictionary:
	if spin != 0.0:
		_car.chassis.angular_velocity = spin
	var last: float = _car.chassis.rotation
	var stretch := 0.0        ## 当前这一趟腾空转过的角度
	var best := 0.0           ## 最长的那一趟
	var expected := 0
	var air := 0.0
	var wrapped := false
	var flip := 0.0
	var written := 0
	for i in int(round(seconds * 60.0)):
		if step != 0.0 and (step_until <= 0.0 or absf(_car.flip_angle) < step_until):
			# 写的是**角度**，不是角速度 —— 见 [method _case_short]。
			_car.chassis.rotation += step
			written += 1
		await get_tree().physics_frame
		var r: float = _car.chassis.rotation
		if absf(r - last) > PI:
			wrapped = true
		if _car.grounded:
			# 落地：被测代码在这一帧把累计转角清零（见 [member HillCar.flip_angle]），
			# 这里跟着清，并把这一趟掉下来的整圈数记进账。不跟着清的话，落地之后
			# 又颠起来的那点角度会被算进同一趟里 —— 实测就是这么差了一次。
			if _car._has_landed:
				expected += int(absf(stretch) / TAU)
			best = maxf(best, absf(stretch))
			stretch = 0.0
		else:
			stretch += wrapf(r - last, -PI, PI)
			flip = _car.flip_angle
		last = r
		air = maxf(air, _car.air_time)
	if _car._has_landed:
		expected += int(absf(stretch) / TAU)
	best = maxf(best, absf(stretch))
	return {
		"air": air, "turns": best / TAU, "expected": expected,
		"flips": _flips.size(), "wrapped": wrapped, "flip": flip,
		"written": written,
	}


## 这一趟发的奖励是不是**全部**朝向同一个方向。
func _all_back(back: bool) -> bool:
	for f in _flips:
		if bool(f[0]) != back:
			return false
	return true


## 这一趟发的奖励金额是不是全都是 `want`。
func _all_amount(want: int) -> bool:
	for f in _flips:
		if int(f[1]) != want:
			return false
	return true


# ---------------------------------------------------------------- 1. 平路

func _case_ground() -> void:
	print("=== 1. 平路：轮子转得再快也不给空翻钱 ===")
	_new_world()
	_flat()
	_spawn(Vector2(START_X, CAR_Y))
	for i in SETTLE:
		await get_tree().physics_frame
	Input.action_press("drive_forward")
	var air_frames := 0
	var max_flip := 0.0
	for i in 180:
		await get_tree().physics_frame
		if not _car.grounded:
			air_frames += 1
		max_flip = maxf(max_flip, absf(_car.flip_angle))
	Input.action_release("drive_forward")
	print("  全油门 3.00s：离地 %d 帧，累计转角最大 %.2f 圈，发奖 %d 次" % [
		air_frames, max_flip / TAU, _flips.size(),
	])
	_check("平路全程贴地", air_frames, 0)
	_check("平路一次空翻钱都没发", _flips.size(), 0)
	_check("车还活着（否则上面两条是废话）", _car.alive, true)
	# 贴着地的时候累计转角应该**一直是 0**：代码在触地那一帧就把它清了，
	# 所以轮子转得再快也不该在这个数上留下痕迹。留下痕迹就说明清零漏了。
	_check("贴地时累计转角恒为 0", is_zero_approx(max_flip), true)


# ---------------------------------------------------------------- 2/3. 转满一圈

## `front = true` 是前空翻（顺时针，正角速度）。
func _case_one(front: bool) -> void:
	print("=== %d. %s：空中转满一整圈 ===" % [3 if front else 2, "前空翻" if front else "后空翻"])
	await _setup_air(true, DROP)
	var st := await _fly(3.0, 15.0 if front else -15.0)
	print("  腾空 %.3fs，最长一趟转了 %+.2f 圈，应收 %d 次，实发 %d 次：%s" % [
		st["air"], st["turns"], st["expected"], st["flips"], str(_flips),
	])
	# 空跑闸：一趟都没转够一圈的话，下面是「0 == 0」，等于没测。
	_check("确实转够了一整圈（否则这条是空跑）", st["turns"] >= 1.0, true)
	_check("实发次数 = 应收次数", st["flips"], st["expected"])
	_check("方向对（%s）" % ("前" if front else "后"), _all_back(not front), true)
	_check("金额是 50", _all_amount(HillCar.FLIP_BONUS_COINS), true)


# ---------------------------------------------------------------- 4. 差一点

## **这条是 `wrapf` 的哨兵。** 车身转角要**跨过 ±π**（半圈）但不到一整圈：
## 不折算的话，车头穿过 ±180° 那一帧会被算成「倒退了一整圈」，白送一次。
##
## 这里**一帧一帧直接写 `rotation`**，不是给它一个初始角速度：物理丢下来的车转
## 多少圈是会飘的，而这条断言的窗口只有「半圈到一圈」这么窄 —— 交给物理就等于
## 交给运气。直接写角度，写下多少是算得出来的。
##
## **量出来的两个数会不一样，这不是 bug，是采样点不同。** 测试读 `rotation` 是在
## `physics_frame` 刚发出、物理步**还没跑**的时候；被测代码读它是在 `_physics_process`
## 里、我这一帧写完之后。中间隔着一步物理：我把车身硬拧过去，两个轮子还挂在关节上，
## 这一步里会被拽回来一大截（实测写 24 帧 × 0.35 = 8.40 弧度，测试只量到 2.50 弧度，
## 七成被拧回去了）—— 代码看不到这一截，它只看到我写的。
##
## 所以这条断言断的是**代码自己累计的那个数**（[member HillCar.flip_angle]）：
## 发不发奖全看它，而且它是 `帧数 × 每帧弧度`，不受物理甩动影响 —— 8.40 弧度
## 实测 8.38，准到 0.02。测试自己那个观测值只用来当 ±π 的哨兵。
func _case_short() -> void:
	print("=== 4. 转过半圈多一点、但不到一整圈 ===")
	await _setup_air(true, DROP)
	# 拧到刚过半圈就收手。**不能写死帧数**：每帧真能攒下多少是物理说了算，
	# 写 14 帧只攒到 1.70 弧度（0.27 圈），写 24 帧却已经过了一整圈 —— 中间那段
	# 不是线性的，配不出来。改成盯着代码的累计值，够了就停，窗口就稳了。
	var st := await _fly(3.0, 0.0, 0.35, PI * 1.15)
	var turn: float = absf(st["flip"]) / TAU
	print("  拧了 %d 帧，代码累计了 %+.2f 弧度（%.2f 圈，测试自己量到 %.2f 圈），车身角度跳变超过 π：%s，实发 %d 次" % [
		st["written"], st["flip"], turn, st["turns"], st["wrapped"], st["flips"],
	])
	_check("车身角度确实一步跳过 ±π（不然这条测不到 wrapf）", st["wrapped"], true)
	_check("转过半圈以上", turn > 0.5, true)
	_check("但没到一整圈", turn < 1.0, true)
	_check("一次都没发", st["flips"], 0)
	# **方向不能反。** 漏了 `wrapf` 的话，越过 ±180° 那一帧会被当成「倒退了一整圈」，
	# 累计转角从正翻成负 —— 就算这次没凑够一整圈没发钱，方向也已经错了，
	# 下一条用例（连翻）就会真的发出一次反方向的奖。这里直接读被测代码的累计值。
	_check("累计转角还是正的（wrapf 没把方向搞反）", st["flip"] > 0.0, true)


# ---------------------------------------------------------------- 5. 连翻

func _case_double() -> void:
	print("=== 5. 连翻两圈 ===")
	await _setup_air(true, DROP)
	var st := await _fly(3.0, -30.0)
	print("  腾空 %.3fs，最长一趟转了 %+.2f 圈，应收 %d 次，实发 %d 次" % [
		st["air"], st["turns"], st["expected"], st["flips"],
	])
	_check("确实转够了两圈（否则这条是空跑）", st["turns"] >= 2.0, true)
	_check("实发次数 = 应收次数（两圈发两次）", st["flips"], st["expected"])
	_check("两次都是后空翻", _all_back(true), true)


# ---------------------------------------------------------------- 6. 出生悬空

## 车是悬空出生的，**落地之前不给空翻钱** —— 和腾空奖励同一个闸
## （[member HillCar._has_landed]）。
func _case_spawn_drop() -> void:
	print("=== 6. 出生悬空：落地之前转圈不发钱 ===")
	# 悬得更高一点，好让采样结束时车**还在空中**：没落地的话，「一次都没发」
	# 才真的只说明那道闸起了作用，而不是「发奖逻辑因为别的原因没跑」。
	await _setup_air(false, DROP + 800.0)
	var st := await _fly(1.5, -16.0)
	print("  从 %d 高落下，1.5s 时腾空 %.3fs，最长一趟转了 %+.2f 圈，实发 %d 次" % [
		int(DROP + 800.0), st["air"], st["turns"], st["flips"],
	])
	_check("采样结束时车还在空中", _car.grounded, false)
	_check("确实转够了一整圈（否则这条是空跑）", st["turns"] >= 1.0, true)
	_check("落地之前一次都没发", st["flips"], 0)


# ---------------------------------------------------------------- 7. 关卡接线

func _case_game_wiring() -> void:
	print("=== 7. 关卡：信号要变成金币 ===")
	var main: HillGame = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	var before: int = main.coins
	var bank_before: int = SaveData.total_coins
	main._on_flip_bonus(HillCar.FLIP_BONUS_COINS, true)
	_check("本局金币 +300", main.coins - before, HillCar.FLIP_BONUS_COINS)
	_check("存档金币 +300（空翻奖励也是即时入账的）",
			SaveData.total_coins - bank_before, HillCar.FLIP_BONUS_COINS)
	_check("一次空翻就是整圈", HillCar.FLIP_TURNS, 1.0)
	_check("金额常量就是 300（需求要的数）", HillCar.FLIP_BONUS_COINS, 300)
	# 飘字那条路也走一遍：`_draw_flip_flash()` 平时没人调，写错了（比如中英两条
	# 文案的 `%` 配错）要等到玩家真的翻一圈才会在画面上炸出来。
	main.hud.flash_flip(HillCar.FLIP_BONUS_COINS, true)
	await get_tree().process_frame
	_check("飘字画得出来（没有脚本报错）", main.hud._flip_flash > 0.0, true)
	main.queue_free()
	await get_tree().process_frame
