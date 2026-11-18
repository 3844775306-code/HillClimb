extends Node
## 特效不许碰物理 —— 这条用数据守，不靠自觉。
##
## 同一个场景跑两遍（开特效 / 关特效），比较车的最终坐标，**逐位相同**才算过。
## 只比坐标还不够：万一特效一颗粒子都没出，两边当然也一样，所以还要检查粒子数，
## 否则这个对照是空的、是自欺欺人。
##
## README 坑 #9 的反面教材：一个「只是好看」的浮动动画让同种子的一局路程差了 37%。
## 特效是最容易再犯的地方 —— 它每帧都要读刚体状态（接触点、角速度、油门），
## 手一滑写成「顺手把 rotation 改一下」就完了。
##
## 用法：
##   godot --headless --path . res://tests/effects.tscn

const CAR := preload("res://scenes/car.tscn")

## 跑多少个**物理帧**。按物理帧计数、不看真实时间：`_process` 的 delta 是墙上时钟，
## 拿它当基准的话，光是多画几颗粒子就会让采样点落到别的物理帧上，量出来的差异是
## 采样误差而不是物理差异（tests/sim.gd 的 t=10 那一行就是这么飘的）。
const RUN_FRAMES := 240
const SETTLE := 12
## 压低抓地力，让轮子真的空转起来，好有碎屑可测。
## 0.12 就是雪地那一档（摩擦系数 0.31）：tests/grip_climb_probe 实测它在平地上
## 打滑 1.68×，所以这局一定搓得出碎屑。
const GRIP := 0.12

const START_X := 120.0
const CAR_Y := -39.0

var _world: Node2D
var _assertions := 0
var _failures := 0


func _ready() -> void:
	Engine.time_scale = 1.0
	SaveData.persist = false     # 别让这次对照写进玩家存档
	SaveData.reset_progress()    # 也别让玩家练出来的升级混进来
	print("特效开关对照（同一场景跑两遍，各 %d 物理帧）" % RUN_FRAMES)
	# 先空跑一局丢掉，**这一步不能省**：第一局的物理服务器还没热起来（车壳的自动
	# 惯量要到第 2 个物理帧才读得到，见 HillCar._apply_inertia_scale），所以第一局
	# 和后面几局之间天生有 1e-3 像素级的差别。实测（关、关、关、开 四连跑）：
	#   关1 → 关2 差 0.00096，关2 → 关3 差 0，关3 → 开4 差 0
	# 差别只跟「第几局」有关、跟开关无关 —— 不热身的话，这个测试会永远挂在一个
	# 假阳性上，而那个假阳性看起来还特别像「特效真的动了物理」。
	await _run(true)
	var on: Dictionary = await _run(true)
	var off: Dictionary = await _run(false)
	_report("开特效", on)
	_report("关特效", off)
	_check(on["pos"] == off["pos"], "两遍的最终坐标逐位相同", str(on["pos"]))
	_check(int(on["grains"]) > 0, "开特效时真的有粒子在跑", "%d 颗" % int(on["grains"]))
	_check(int(off["grains"]) == 0, "关特效时一颗都不出", "%d 颗" % int(off["grains"]))
	print("断言 %d 条，失败 %d 项" % [_assertions, _failures])
	print("全部通过" if _failures == 0 else "!! %d 项不通过" % _failures)
	get_tree().quit()


func _run(effects: bool) -> Dictionary:
	if _world != null:
		_world.queue_free()
		# 等一个物理帧，确认上一局的刚体真的从物理服务器里撤走了，
		# 不然两遍会互相挤（尤其是那个 1.0e9 的油量）。
		await get_tree().physics_frame
	_world = Node2D.new()
	add_child(_world)

	# 一块平地。**故意不用 main.tscn**：那里的地形是跟着镜头流式生成的，会引入
	# 和帧率有关的变量，而这次要测的是「特效有没有干扰物理」，不该有第二个变量。
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([
		Vector2(-400.0, 0.0), Vector2(20000.0, 0.0),
		Vector2(20000.0, 800.0), Vector2(-400.0, 800.0),
	])
	body.add_child(shape)
	_world.add_child(body)

	var car: HillCar = CAR.instantiate()
	car.position = Vector2(START_X, CAR_Y)
	_world.add_child(car)
	car.fuel = 1.0e9
	car.surface_grip = GRIP
	var fx = car.get_node("Effects")
	fx.enabled = effects

	for i in SETTLE:
		await get_tree().physics_frame

	Input.action_press("drive_forward")
	for i in RUN_FRAMES:
		await get_tree().physics_frame
	Input.action_release("drive_forward")

	# 轮面速度 / 车速 = 打滑倍率。这个数远大于 1，说明轮子在空转，碎屑有得可扬。
	var surface := car.rear_wheel.angular_velocity * 21.0
	var speed := car.chassis.linear_velocity.x
	return {
		"pos": car.chassis.global_position,
		"grains": fx.live_count(),
		"speed": speed,
		"surface": surface,
		"slip": surface / maxf(1.0, absf(speed)),
	}


func _report(label: String, r: Dictionary) -> void:
	print("  %s  最终 x=%.0f  y=%.0f  车速=%.0f  轮面=%.0f  打滑=%.2f×  粒子=%d" % [
		label, (r["pos"] as Vector2).x, (r["pos"] as Vector2).y,
		r["speed"], r["surface"], r["slip"], int(r["grains"]),
	])


func _check(ok: bool, label: String, detail: String) -> void:
	_assertions += 1
	if not ok:
		_failures += 1
	print("  %s %s —— %s" % ["OK  " if ok else "FAIL", label, detail])
