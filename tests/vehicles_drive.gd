extends Node
## 四辆车的实机对比：同一张图、同一个种子，各开一段，看跑了多远、卡住多久。
##
## [tests/vehicles] 量的是**静态**的形状和马达参数（车架多长、离地多高、推重比多少），
## 秒级出结果，也正因为它不跑物理，它量不到「开起来到底怎么样」。这个文件补另一半。
##
## **走 [scenes/main.tscn]，不是自己拼一台车。** 换车那一步在
## [method HillGame._enter_tree] 里 —— 只有走完整流程才验得到「存档里选了哪辆车，
## 开出来的就是哪辆车」，这也是这个文件存在的主要理由（静态测试验不了这条）。
##
## 地形种子是固定的（[member HillTerrain.world_seed] 默认 1337，`main.tscn` 没改），
## 地图走 [method SaveData.reset_progress] 之后的默认图，所以四辆车跑的是**同一段
## 地形**，里程可以直接横比。
##
## 油箱一律灌成无限：这一轮比的是「底盘和马达」，油耗是另一条轴（那张卡片上的
## 「满油多少秒」），混进来只会让跑得快的车先没油、成绩反而更差。
##
## 别拿这个文件的绝对值当标定数据 —— 一段地形上的里程噪声很大。它的用处是
## **横向对比**和**抓明显不对的车**（比如某辆车一上去就翻、或者卡住二十秒）。

const MAIN := preload("res://scenes/main.tscn")
## 每辆车跑多久（**模拟秒**）。四辆加起来就是这个数的四倍，别调太大。
const DURATION := 30.0
## 物理步长。Godot 的默认物理频率就是 60，这里写死一份是为了把「跑多久」换算成
## **物理帧数**。
const TICK := 1.0 / 60.0
## 每隔多久取一次样。
const STEP := 0.5
## 卡住超过这个秒数就抓一次现场：是抓不住地、还是车壳搁浅、还是地形太陡。
const STALL_DUMP := 3.0
## 起点 x。里程按 (x − 起点) / 10 换算成米，和 [tests/range] 一致。
const START_X := 200.0
## 开 trace 时追多少个物理步（240 步 = 4 秒，分岔一般远在撞到第一块坎之前）。
const TRACE_STEPS := 240
## 摆好车之后、开始数帧之前，先空跑多少个物理步。
##
## 目的是等 [method HillCar._apply_inertia_scale] 落地（它最多等 10 帧，这里给 12）。
## **这个数必须是固定的**：等待期间车在自由落体，等几帧决定了初始条件，
## 所以这里不是「够长就行」，而是「每一轮都得一样长」。
const WARMUP_FRAMES := 12

var _failures := 0

## 本轮的死亡现场。写成成员变量而不是 `_run` 里的局部变量：`crashed` 是信号，
## 回调里要读「这一刻」的 t / 姿态，而 GDScript 的 lambda 捕获局部变量是**按值**的
## （`t` 会被冻在创建 lambda 的那一刻，永远是 0）。成员变量没这个问题。
var _died := false
var _death_reason := ""
var _death_t := -1.0
var _death_tilt := 0.0
var _death_speed := 0.0
## 上一次采样时的时刻/姿态/速度。死亡多半发生在两次采样之间（间隔 0.5 秒），
## 所以记下来的是**最近一次采样**的值，不是死亡那一瞬间的 —— 够用来区分
## 「后仰翻过去」和「扎头」了，别拿它当精确的死亡时刻。
var _now := 0.0
var _tilt_now := 0.0
var _speed_now := 0.0


func _ready() -> void:
	Engine.time_scale = 1.0
	# **物理步长必须严格等于 1/60，否则整个文件的结果不可复现。**
	#
	# Godot 默认 `physics_jitter_fix = 0.5`，意思是「把物理步长微微抖动一下，
	# 让物理时间和渲染时间长期对齐」—— 对游戏是好事，对测量是灾难：每一步的 dt
	# 都在变，刚体又是混沌系统，同一辆车同一段地形能跑出完全不同的结果。
	# 实测过：代码一个字没改，摩托一轮 258 米「翻车」、下一轮 1391 米「活着」，
	# 赛车从 1444 漂到 1260，巴士也是。改成 0 之后每一步的 dt 都精确相等，
	# 结果才可复现 —— 拿这些数字做标定之前，先确认这里没被改回去。
	Engine.physics_jitter_fix = 0.0
	# 无头模式下掉帧超过 8 个物理步（133ms）时 Godot 会**丢弃**多余的步，步数一飘
	# 结果就飘。换车那一帧要生成整块新地形，正好是最容易超过 133ms 的地方。
	# 提高上限只是「慢慢追」，不改变单步精度（和 tests/upgrade_calib 同一条）。
	Engine.max_physics_steps_per_frame = 64
	SaveData.persist = false
	# 升级倍率会乘到车的参数上，玩家练满的车会污染这里的对比。
	# reset_progress() 顺带把地图和车都拨回默认值。
	SaveData.reset_progress()
	_trace = OS.get_cmdline_user_args().has("trace")

	print("=== 四辆车 · 同一段地形 · 各 %.0f 秒 ===" % DURATION)
	print("  %-8s %8s %8s %8s %8s %8s  %s" % [
		"车", "里程", "平均", "最高", "最长卡住", "离地时间", "结果",
	])
	var rows := []
	for id in _wanted():
		rows.append(await _run(id))
		# 只追第一辆：要的是「同一次运行里两次启动的差异」，
		# 多追几辆只会把两份 trace 搅在一起。
		_trace = false

	_report(rows)
	print("")
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


## 只跑命令行点名的车：`… res://tests/vehicles_drive.tscn -- moto jeep`。
## 不带参数就跑全部。
##
## 这是**隔离实验**用的：这个文件原本有个「同一辆车跑两遍结果不一样」的毛病，
## 而越野车（永远排第一）却是逐字节可复现的 —— 怀疑是「排在别人后面」才飘。
## 把车单独拎出来跑，就能把「这辆车自己不稳」和「被前一辆车带歪」分开。
func _wanted() -> Array:
	var out := []
	for a in OS.get_cmdline_user_args():
		if Vehicles.has_vehicle(a):
			out.append(a)
	return out if not out.is_empty() else Vehicles.available()


## 开了之后每个物理步打一行车身状态，用来**二分找分岔点**。
##
## 「结果不一样」这句话定位不了任何东西：刚体是混沌系统，第一微秒的一丝差别
## 和第十秒撞上的一块石头，最后都表现为「里程差了 700 米」。把每一帧的状态
## 打出来，两次运行的输出 `diff` 一下，**第一行不同的地方就是分岔点** ——
## 是第一步就歪了（初始状态不同），还是某一步突然岔开（某个事件）。
##
## 开法：命令行加 `-- trace`。
var _trace := false
var _trace_lines := PackedStringArray()


## 开一辆车跑一段，返回它这一轮的成绩。
func _run(id: String) -> Dictionary:
	# **必须在 instantiate 之前设**：换车发生在 HillGame._enter_tree() 里，
	# 而那就是 add_child 的那一刻。
	SaveData.select_vehicle(id)
	var main: HillGame = MAIN.instantiate()
	add_child(main)

	var car: HillCar = main.car
	var name: String = Vehicles.get_vehicle(id)["zh"]
	if car == null:
		_failures += 1
		print("  FAIL %s：开局没拿到车" % name)
		main.queue_free()
		return {}

	# **地形区块的生成从 `_process` 挪到物理帧上。**
	#
	# [HillTerrain] 的 `_process` 每渲染帧调一次 `_refresh_chunks()`，而它建的是
	# 带 [CollisionPolygon2D] 的实体 —— 也就是说「哪些地面存在」是**渲染帧**的函数，
	# 而物理步是死的 1/60，两者的比看机器脸色（见下面 `spawn` 那段）。
	# 关掉 `_process` 改成每个物理步刷一次，「区块什么时候进物理世界」就只由物理步数
	# 决定。刷新区块是幂等的（已经在 `_chunks` 里的不会再建），多刷几次不会改变结果。
	main.terrain.set_process(false)
	var step := func() -> void:
		main.terrain._refresh_chunks()
	step.call()

	# **开局等固定个数的物理帧，不要等渲染帧。**
	#
	# 这条是跑了很多轮才对上的。原来这里是 `add_child(main)` 之后
	# `await get_tree().process_frame`，然后开始数物理帧 —— 而 `process_frame` 和
	# 物理步的比是飘的：Godot 一轮 `Main::iteration` 先跑 N 个物理步再跑一次
	# `_process`，那个 N 实测在 12~17 之间。车出生时是**悬空**的（要掉一下才落地，
	# 见 car.gd 的 `_has_landed`），所以「开始数帧」那一刻车已经自由落体了 N 帧，
	# N 不同 → 初始高度和速度就不同 → 混沌放大 → 里程能差 700 米。
	#
	# 怎么定位到的（命令行加 `-- trace`）：摩托单独跑四轮、每个物理步打一行车身状态
	# 再 diff，**第一行就不同**，而且几条轨迹是**同一条自由落体曲线采样在不同偏移
	# 上** —— vy 分别是 194.2 / 210.2 / 274.0，相邻两数正好差 980/60 = 16.3。
	# 四轮里有两轮的 N 撞上了同一个值，那两轮于是逐字节相同。之前猜过「冷启动」和
	# 「车和车互相污染」，按这个证据都不成立：N 撞上了就一样，没撞上就不一样。
	#
	# 顺带等 [method HillCar._apply_inertia_scale] 落地：它最多等 10 个物理帧，
	# 这里给 12，为的是让转动惯量**每一轮都在同一个物理步**生效。
	# **不要改成「等到惯量不为 0 就往下走」** —— 那样等的帧数又变成变量，
	# 等于把刚修好的初始条件再次交给机器脸色。下面有一条断言盯着它落地。
	#
	# 也别想着「先记下出生姿态、等完再搬回去」来彻底抹掉这段自由落体：那样车会
	# 落一次地、被抬回空中、再落一次，而第二次落地带着上一次的接触和关节冲量，
	# 车身会因为这一下扎头 —— 实测越野车从 1299 米掉到 269 米当场翻。让车老老实实
	# 从出生点掉一次就好，那正是真开局时它经历的东西。
	for i in WARMUP_FRAMES:
		await get_tree().physics_frame
		step.call()
	if not is_equal_approx(car.inertia_scale, 1.0) and car.chassis.inertia <= 0.0:
		_failures += 1
		print("  FAIL %s：转动惯量倍率没落地（车壳惯量仍是 0）" % name)

	# **存档里选了这辆车 → 开出来的就是这辆车。** 这是整个文件最要紧的一条断言，
	# 静态测试验不了它（那边是直接实例化 `.tscn`，走不到换车那一步）。
	# 用 `scene_file_path` 比，不拿 script 比：四辆车共用 car.gd，脚本永远相同。
	var want_path := Vehicles.scene_path(id)
	if car.scene_file_path != want_path:
		_failures += 1
		print("  FAIL %s：开出来的不是这辆车（%s ≠ %s）" % [name, car.scene_file_path, want_path])
	# 换进来的车还必须**顶上 "Car" 这个名字**：[member HillGame.car] 是
	# `@onready var car: HillCar = $Car`，名字没顶上的话 `$Car` 找不到，
	# `car` 是 null，`_ready` 里第一句 `car.apply_map()` 就崩。
	if car.name != "Car":
		_failures += 1
		print("  FAIL %s：换进来的车没顶上 \"Car\" 这个名字（叫 \"%s\"）" % [name, car.name])
	car.fuel_max = 1.0e9
	car.fuel = 1.0e9
	for part in [car.chassis, car.rear_wheel, car.front_wheel]:
		part.contact_monitor = true
		part.max_contacts_reported = 8

	_died = false
	_death_reason = ""
	_death_t = -1.0
	_death_tilt = 0.0
	_death_speed = 0.0
	car.crashed.connect(_on_crash)

	Input.action_press("drive_forward")
	# **按物理帧数跑，不按墙上时钟跑。** 这是踩过的坑：原来这里写的
	# `await create_timer(STEP).timeout`，而 Godot 在机器忙的时候会**丢物理步**
	# （`physics/common/max_physics_steps_per_frame` 是 8），于是 30 秒墙上时间里
	# 实际推进的模拟时间每轮都不一样 —— 同一辆车、同一段地形、代码一个字没改，
	# 摩托第一轮 258 米「翻车」、第二轮 1391 米「活着」，赛车从 1444 米漂到 1260 米。
	# 那种数字不能用来标定，谁快谁慢都成了掷骰子。
	# 数物理帧就没这个问题：跑多少帧是写死的，同样的机器上结果可复现。
	var total_frames := int(DURATION / TICK)
	var sample_every := maxi(1, int(STEP / TICK))
	var sample_dt := float(sample_every) * TICK
	var frames := 0
	var t := 0.0
	var best_x: float = car.chassis.global_position.x
	var progressed_at := 0.0
	var worst_stall := 0.0
	var top_speed := 0.0
	var airborne := 0.0
	var max_tilt := 0.0
	var dumped := false
	while frames < total_frames and car.alive:
		await get_tree().physics_frame
		frames += 1
		# 见 `_run` 开头：每个物理步刷一次地形区块，和渲染帧率脱钩。
		step.call()
		if _trace and frames <= TRACE_STEPS:
			_trace_lines.append("%4d  x=%12.6f y=%12.6f r=%12.9f  vx=%12.6f vy=%12.6f  w=%12.9f %12.9f" % [
				frames,
				car.chassis.global_position.x, car.chassis.global_position.y, car.chassis.rotation,
				car.chassis.linear_velocity.x, car.chassis.linear_velocity.y,
				car.rear_wheel.angular_velocity, car.front_wheel.angular_velocity,
			])
		if frames % sample_every != 0:
			continue
		t = float(frames) * TICK
		car.fuel = 1.0e9
		var x: float = car.chassis.global_position.x
		top_speed = maxf(top_speed, car.chassis.linear_velocity.length())
		max_tilt = maxf(max_tilt, absf(rad_to_deg(car.chassis.rotation)))
		_now = t
		_tilt_now = rad_to_deg(car.chassis.rotation)
		_speed_now = car.chassis.linear_velocity.length()
		if not car.grounded:
			airborne += sample_dt
		if x > best_x + 20.0:
			best_x = x
			progressed_at = t
		worst_stall = maxf(worst_stall, t - progressed_at)
		if not dumped and t - progressed_at > STALL_DUMP:
			dumped = true
			var h0: float = main.terrain.height_at(x - 60.0)
			var h1: float = main.terrain.height_at(x + 60.0)
			print("      卡住现场 t=%.1fs x=%.0f  坡度 %.1f°  俯仰 %.1f°  轮速 %.1f  触地 后%d前%d壳%d" % [
				t, x, rad_to_deg(atan2(h0 - h1, 120.0)), rad_to_deg(car.chassis.rotation),
				car.rear_wheel.angular_velocity,
				car.rear_wheel.get_colliding_bodies().size(),
				car.front_wheel.get_colliding_bodies().size(),
				car.chassis.get_colliding_bodies().size(),
			])
	Input.action_release("drive_forward")
	# 用实际跑掉的模拟时间算平均，别用 DURATION —— 提前翻车的话分母会偏大，
	# 平均速度会被算得比实际好看。
	t = float(frames) * TICK

	if _trace:
		print("### TRACE %s ###" % id)
		for line in _trace_lines:
			print(line)
		print("### TRACE END ###")
		_trace_lines = PackedStringArray()

	var s := Vehicles.stats(id)
	var row := {
		"id": id, "name": name,
		"meters": (best_x - START_X) / 10.0,
		"avg": (best_x - START_X) / 10.0 / maxf(t, 0.001),
		"top": top_speed,
		"stall": worst_stall,
		"air": airborne,
		"died": _died,
		"why": _death_reason,
		"died_at": _death_t,
		"died_tilt": _death_tilt,
		"died_speed": _death_speed,
		"ratio": s["ratio"], "launch": s["launch_ratio"], "clamped": s["torque_clamped"],
		"tilt": max_tilt,
	}
	# **先 remove_child 再 queue_free**：只调 queue_free 的话，旧车会和下一辆车
	# 同时在物理世界里活到帧末，而两辆车是在**同一个出生点**上造出来的 ——
	# 重叠那一帧它们会互相挤开，挤多少取决于当帧的调度。remove_child 立刻把它
	# 摘出场景树，物理世界那边当场就干净了。
	remove_child(main)
	main.queue_free()
	await get_tree().process_frame
	return row


## 死亡现场。**这四个数比「死了」两个字有用得多**：`crash` 是车手头着地，
## 姿态角告诉你它是后仰翻过去（接近 ±180°）还是扎头（接近 ±90°），
## 速度告诉你当时是不是在高速撞坡 —— 三种原因的修法完全不同。
func _on_crash(reason: String) -> void:
	_died = true
	_death_reason = reason
	_death_t = _now
	_death_tilt = _tilt_now
	_death_speed = _speed_now


## 打印成绩表，并挑出明显不对的车。
##
## 判据只有两条硬性的，其余全是打印出来看的：
##
##  · **一辆都没跑起来**（里程近乎 0）—— 那辆车在某一段地形上直接卡死了，是坏的。
##  · **一半时间都在原地**（最长卡住 > 时长的 1/3）—— 同上，但轻一些。
##
## 不硬断言「谁比谁远」：一段地形上的里程噪声很大，摩托在起伏路上可能比巴士还惨，
## 那是地形的脾气不是车的缺陷。谁该比谁快，看的是「平均速度」那一列的趋势。
func _report(rows: Array) -> void:
	for row: Dictionary in rows:
		if row.is_empty():
			continue
		var verdict: String = "活着"
		if row["died"]:
			verdict = "死在 %.1fs（%s，姿态 %.0f°，%.0f px/s）" % [
				row["died_at"], _reason_name(row["why"]), row["died_tilt"], row["died_speed"]]
			_failures += 1
		elif row["stall"] > DURATION / 3.0:
			_failures += 1
			verdict = "FAIL 卡了 %.1fs" % row["stall"]
		elif float(row["meters"]) < 10.0:
			_failures += 1
			verdict = "FAIL 几乎没动"
		print("  %-8s %7.1fm %7.1f %7.0f %8.1fs %7.1fs  %s" % [
			row["name"], row["meters"], row["avg"], row["top"], row["stall"],
			row["air"], verdict,
		])
	print("  「平均」= 里程 ÷ 跑了多久（m/s），「最高」= 车壳速度峰值（px/s）。")
	print("  「离地时间」= 两个轮子都不碰地的累计秒数；越野车飞得最多，那是因为它")
	print("  在搓板路上弹起来 —— 飞得远不等于开得好。")
	print("  **中途死掉算不合格**：这张图的难度是照越野车调的，任何一辆车都不该")
	print("  在头 30 秒里翻掉。死因写出来了 —— crash 是车手头着地，姿态角接近")
	print("  ±180° 是后仰翻过去、接近 ±90° 是扎头，两种的修法完全不同。")


func _reason_name(code: String) -> String:
	match code:
		HillCar.REASON_CRASH:
			return "车手头着地"
		HillCar.REASON_FUEL:
			return "没油"
		HillCar.REASON_DROWN:
			return "淹死"
		HillCar.REASON_BURN:
			return "烧死"
		HillCar.REASON_FALL:
			return "掉下桥"
	return code if code != "" else "原因不明"
